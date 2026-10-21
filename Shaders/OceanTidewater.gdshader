shader_type spatial;
// =====================================================================================
// OceanTidewater.gdshader —— 把 dgreenheck/tidewater 的海面外观模型移植到 Godot 4.7
// 参考：src/ocean/WaterMaterial.js、WaterSurface.js、ShoreWaves.js、SurfFoam.js、SeaDetail.js
//
// 照搬的物理部分（数值与公式同 Tidewater）：
//   · 精确介电菲涅尔 fresnelDielectric(cosI, eta)，IOR = 1.333
//   · 水体 Beer-Lambert 透射 exp(-(a+s)*L) + 单次散射解析式（HG 相函数 g=0.86 + 多次散射 Gordon 项）
//   · 吸收/散射系数 = (0.42,0.075,0.035) / (0.012,0.018,0.024)（蓝绿透、红光快速吃掉）
//   · 波峰次表面透光（back-lit SSS，青绿色 (0.12,0.55,0.45)*0.06）
//   · 泡沫 = 明亮漫反射散射体（albedo 0.85，wrapped sun + sky irradiance）
//   · Cox-Munk 未解析斜率方差驱动粗糙度 gone: mss = 0.003 + 0.00512*U
//   · 折射用 Snell 折射光线 ray-march 到海床（不用 screen/depth texture，绝不屏幕反馈花屏）
//   · 破碎波/爬沙（Green 定律浅化 + 破碎深度 db=(A*3.556/gamma)^0.8 + bore + swash）
//   · 阵风/浮油/风纹（SeaDetail 的四通道可平铺 fbm）+ 花边白浪（SurfFoam lace）
//
// 与 Tidewater 的差异（引擎能力所限，做等价替代）：
//   · FFT 级联 → 8 级 Gerstner 波（解析导数出法线，按像素足迹淡出高频）
//   · 行程时间场 τ → 沿径向 10 步积分的实时近似（只在近岸 d<26m 计算）
//   · CDLOD → 近/远双层网格 + 距离阻尼（两层在 300m 外都是平面，接缝不可见）
// =====================================================================================
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled, skip_vertex_transform;

// PI / TAU 由 Godot 内建提供，这里不要重复定义
const float OT_INV_PI = 0.3183098861837907;
const float OT_GRAV = 9.81;
const float OT_IOR = 1.333;
const int OT_NWAVE = 8;

// ---- 场景常量（全部由 world.gd 注入，默认值与本作光照一致）
uniform sampler2D hmap;                      // 合成地形图（R = 世界高度，米）
uniform vec2 hmap_meta = vec2(460.0, 512.0); // x: 世界跨度(m)  y: 纹理边长(px)
uniform sampler2D sea_noise : repeat_enable; // RGBA 可平铺 fbm（移植 SeaDetail）
uniform sampler2D lace_tex : repeat_enable;  // RGBA 花边/细胞噪声（移植 SurfFoam）

uniform vec3 u_sun_dir = vec3(0.36, 0.70, -0.62);
uniform vec3 u_sun_color = vec3(2.30, 2.16, 1.94);
uniform vec3 u_sky_irr = vec3(0.30, 0.42, 0.62);
uniform vec3 u_horizon = vec3(0.60, 0.71, 0.86);
uniform vec3 u_zenith = vec3(0.16, 0.36, 0.82);
uniform vec3 u_absorption = vec3(0.42, 0.075, 0.035);
uniform vec3 u_scattering = vec3(0.012, 0.018, 0.024);
uniform vec2 u_wind_dir = vec2(0.86, 0.51);
uniform float u_wind_speed = 6.5;
uniform float u_sea_level = 0.0;
uniform float u_time_scale = 1.0;
uniform float u_wave_scale = 0.60;
uniform float u_shore_amp = 0.42;
uniform float u_backscatter = 0.035;
uniform float u_sss = 1.0;
uniform float u_foam = 1.0;
uniform float u_water_rough = 0.035;
uniform float u_refl = 1.0;
uniform float u_exposure = 1.0;
uniform float u_mesh_cell = 3.0;             // 本层网格边长(m)，用于顶点级 band-limit
uniform float u_use_detail = 1.0;            // 远层关掉 fbm/花边采样省带宽
uniform int u_debug = 0;

varying vec3 v_pos;        // 位移后的世界坐标
varying vec2 v_lagxz;      // 拉格朗日坐标（波形随之漂移的水体原始 xz）
varying float v_tau;       // 近岸行程时间(s)：低频量，顶点插值即可，不必在片元重算

// =============================================================== 工具
float hash11(float p) { return fract(sin(p * 127.1 + 311.7) * 43758.5453); }

float gnd(vec2 xz) {
	vec2 uv = xz / hmap_meta.x + 0.5;
	return texture(hmap, clamp(uv, vec2(0.0025), vec2(0.9975))).r;
}

vec2 gnd_grad(vec2 xz, float e) {
	float hl = gnd(xz - vec2(e, 0.0));
	float hr = gnd(xz + vec2(e, 0.0));
	float hd = gnd(xz - vec2(0.0, e));
	float hu = gnd(xz + vec2(0.0, e));
	return vec2(hr - hl, hu - hd) / max(2.0 * e, 0.001);
}

// Tidewater: WaterMaterial.js fresnelDielectric —— 精确非偏振介电菲涅尔
float fresnelDielectric(float cosI, float eta) {
	float c = clamp(cosI, 0.0, 1.0);
	float g2 = eta * eta - 1.0 + c * c;
	float g = sqrt(max(g2, 0.0));
	float a = (g - c) / (g + c);
	float b = (c * (g + c) - 1.0) / (c * (g - c) + 1.0);
	float r = 0.5 * a * a * (b * b + 1.0);
	if (g2 < 0.0) { r = 1.0; }
	return r;
}

// Tidewater: waterPhaseHG —— Henyey-Greenstein
float phaseHG(float cth, float g) {
	float g2 = g * g;
	float d = max(1.0 + g2 - cth * 2.0 * g, 0.0001);
	return (1.0 - g2) / (4.0 * PI) / pow(d, 1.5);
}

float dGGX(float NdH, float a2) {
	float d = NdH * NdH * (a2 - 1.0) + 1.0;
	return a2 / (d * d * PI);
}
float vSmithGGX(float NdL, float NdV, float a2) {
	float gv = NdL * sqrt(NdV * NdV * (1.0 - a2) + a2);
	float gl = NdV * sqrt(NdL * NdL * (1.0 - a2) + a2);
	return 0.5 / max(gv + gl, 0.00001);
}

// 解析天空：地平线色 → 天顶色的近似 + 太阳盘/前向散射光晕（对标 sky/Atmosphere）
vec3 sky_radiance(vec3 d, float with_sun) {
	float up = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(u_horizon, u_zenith, pow(up, 0.42));
	float cd = clamp(dot(normalize(d), normalize(u_sun_dir)), -1.0, 1.0);
	float ang = acos(cd);
	float halo = exp(-pow(ang / 0.09, 2.0)) * 1.4 + exp(-pow(ang / 0.34, 2.0)) * 0.24;
	float disk = exp(-pow(ang / 0.028, 2.0)) * 40.0 * with_sun;
	col += u_sun_color * (halo + disk);
	return max(col, vec3(0.0));
}

// =============================================================== 波场
// 8 级 Gerstner：振幅 ∝ 波长（每级对斜率的贡献相同），覆盖 λ=96m → 0.46m
void eval_waves(vec2 p, float t, float vis_scale, out vec3 disp, out vec2 slope, out float jac) {
	disp = vec3(0.0);
	slope = vec2(0.0);
	jac = 1.0;
	float base_ang = atan(u_wind_dir.y, u_wind_dir.x);
	float dist_damp = 1.0 - smoothstep(240.0, 300.0, length(p));
	for (int i = 0; i < OT_NWAVE; i++) {
		float fi = float(i);
		float lambda = 96.0 / pow(2.15, fi);
		float k = TAU / lambda;
		float amp = u_wave_scale * 0.0035 * lambda;
		float ang = base_ang + sin(fi * 2.399) * 0.85;
		vec2 D = vec2(cos(ang), sin(ang));
		float w = sqrt(OT_GRAV * k);
		float ph = k * dot(D, p) - w * t + fi * 2.13;
		float c = cos(ph);
		float s = sin(ph);
		// band-limit：像素足迹超过半波长就把这一级淡掉（Tidewater 用显式 LOD 做同一件事）
		float vis = 1.0 - smoothstep(0.22, 0.62, vis_scale * k / PI);
		if (vis <= 0.0) { continue; }
		// 位移按距离阻尼（保证近/远两层网格在拼合半径处几何连续），
		// 法线/雅可比只按足迹淡出 —— 远处的长涌浪靠片元法线依旧可见（Tidewater 同款思路）
		float geo = vis * dist_damp;
		disp.xz += (0.16 / k) * D * c * geo;
		disp.y += amp * s * geo;
		slope += D * (amp * k * c) * vis;
		jac *= (1.0 - 0.16 * D.x * D.x * s * vis) * (1.0 - 0.16 * D.y * D.y * s * vis);
	}
}

// =============================================================== 近岸波（ShoreWaves 简化版）
// Tidewater 用一张累计行程时间场让波列沿等深线传给岸；这里用「沿径向从深海向岸积分」
// 在 shader 里实时积分近似（只在 d<26m 的近岸像素付这笔开销）。
float shore_travel(vec2 xz) {
	vec2 out_dir = normalize(xz + vec2(0.0002, 0.0001));
	float tau = 0.0;
	float step_len = 2.0;
	for (int i = 0; i < 10; i++) {
		vec2 p = xz + out_dir * (float(i) + 0.5) * step_len;
		float d = max(u_sea_level - gnd(p), 0.25);
		tau += step_len / sqrt(OT_GRAV * d);
		step_len *= 1.32;
	}
	return tau;
}

// 破碎波剖面：s∈[0,1)，0..0.72 缓慢抬升到波峰，之后急速跌落（坡度随 sha 变陡）
float shore_profile(float s, float sha) {
	float r = 0.72;
	if (s < r) {
		float q = s / r;
		return mix(-1.0, 1.0, pow(q, mix(1.0, 2.4, sha)));
	}
	float q = (s - r) / (1.0 - r);
	return mix(1.0, -1.0, pow(q, mix(1.0, 0.55, sha)));
}

// 返回 vec3(位移高度, 白浪量, 爬沙覆盖)
vec3 shore_eval(vec2 xz, float tau, float t) {
	float d = max(u_sea_level - gnd(xz), 0.0);
	float env = smoothstep(26.0, 13.0, d);
	if (env <= 0.0) { return vec3(0.0, 0.0, 0.0); }

	// 沿岸相位扰动（Tidewater shoreWobble）：波峰沿岸弯折，避免圆岛出现完美的同心圆
	float along0 = atan(xz.y, xz.x) * 170.0;
	tau += sin(along0 * 0.029 + 0.7) * 0.42 + sin(along0 * 0.083 + 2.1) * 0.22 + sin(along0 * 0.190 + 0.4) * 0.10;

	float T = 7.0;
	float phase = (t - tau) / T;
	float m = floor(phase);
	float u = fract(phase);

	// 组（sets）：~7 个波一组，中间的最大（Tidewater: abs(sin(m*PI/7))*0.6+0.55）
	float set_env = abs(sin(m * PI / 7.0)) * 0.6 + 0.55;
	// 沿岸变化：波峰 peel，不会整条海滩同时闭合
	float along = atan(xz.y, xz.x) * 170.0;
	float rnd = hash11(m);
	float warp = sin(along * 0.016 + m * 0.9) * 1.6;
	float a1 = sin(along * 0.062 + m * 1.7 + warp);
	float a2 = sin(along * 0.130 + m * 4.1 + 1.3 - warp * 0.7);
	float a3 = sin(along * 0.290 + m * 2.3 + warp * 0.5) * 0.6 + sin(along * 0.470 + m * 5.9 + 0.8) * 0.4;
	float along_v = a1 * 0.6 + a2 * 0.4 + a3 * 0.28;
	float bar = 0.9 + (sin(along * 0.031 + 7.3) * 0.6 + sin(along * 0.083 + 1.1) * 0.4) * 0.14;
	float A = max(u_shore_amp * set_env * (1.0 + (rnd - 0.5) * 0.5 + along_v * 0.30) * bar, 0.02);

	// Green 定律浅化 + 破碎深度 + 破碎进度（同 shoreBreakParams）
	float shoal = pow(10.0 / clamp(d, 0.35, 10.0), 0.25);
	float Ash = A * shoal;
	float gamma = 0.78;
	float db = pow(A * 3.556 / gamma, 0.8);
	float b = (db - d) / max(db * 0.55, 0.05);

	float sha = clamp(smoothstep(-1.2, 0.4, b), 0.0, 1.0);
	float prof = shore_profile(u, sha);
	float yc = Ash * 1.30;
	float yt = -Ash * 0.70;
	float h = mix(yt, yc, prof * 0.5 + 0.5);

	// 卷倒成崩落水滚（bore）：注入点之后塌陷、推动一层水滚向前
	float w_bore = smoothstep(0.85, 1.35, b);
	if (w_bore > 0.0) {
		float Hb = min(Ash * 0.60, max(d, 0.0) * 0.75) * (smoothstep(0.0, 0.3, d) * 0.7 + 0.3);
		float yc_b = mix(yc, yt * 0.6 + Hb, w_bore);
		float yt_b = mix(yt, yt * 0.6, w_bore);
		h = mix(h, mix(yt_b, yc_b, prof * 0.5 + 0.5), w_bore);
	}
	// 爬沙：波峰的上冲余量把水膜再往岸上推一点
	float runup = max(h, 0.0) * 0.35 * smoothstep(1.2, 0.0, d);
	h += runup;
	// 物理限幅：水爬不上无限高的滩，波峰不能高出「水深*0.55 + 0.15m」的包络
	h = min(h, max(d, 0.0) * 0.55 + 0.15);

	// 白浪：注入点开始出现，随 bore 铺开并在最后的滩面上消散
	float ww = smoothstep(-0.1, 0.3, b) * (1.0 - smoothstep(1.6, 2.6, b));
	ww *= 0.55 + 0.45 * abs(sin(along * 0.09 + m * 1.3));
	ww *= smoothstep(0.58, 0.88, prof * 0.5 + 0.5);
	ww *= 0.55;

	h *= env;
	ww *= env;
	return vec3(h, ww, env);
}

// =============================================================== 顶点
void vertex() {
	// 自己写变换：波形在世界空间算出，绕开节点变换（Godot 没有 INV_MODEL_MATRIX）
	vec2 xz = VERTEX.xz;
	float t = TIME * u_time_scale;

	vec3 disp;
	vec2 slope;
	float jac;
	eval_waves(xz, t, u_mesh_cell, disp, slope, jac);

	float tau = 0.0;
	vec3 sh_res = vec3(0.0);
	if (u_sea_level - gnd(xz) < 26.0) {
		tau = shore_travel(xz);
		sh_res = shore_eval(xz, tau, t);
	}

	vec3 world = vec3(xz.x + disp.x, u_sea_level + disp.y + sh_res.x, xz.y + disp.z);
	v_pos = world;
	v_lagxz = xz;
	v_tau = tau;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

// =============================================================== 海床着色
vec3 seabed_color(vec2 xz, float h, vec2 grad) {
	float d = max(u_sea_level - h, 0.0);
	float slope = length(grad);
	vec3 sand = vec3(0.50, 0.46, 0.34);
	vec3 wet = vec3(0.30, 0.27, 0.20);
	vec3 rock = vec3(0.30, 0.29, 0.27);
	vec3 weed = vec3(0.09, 0.24, 0.19);
	vec3 c = mix(sand, rock, smoothstep(0.25, 0.85, slope));
	c = mix(c, weed, smoothstep(2.5, 9.0, d) * 0.45);
	c = mix(wet, c, smoothstep(-0.2, 0.6, d));
	return c;
}

// =============================================================== 片元
void fragment() {
	vec3 P = v_pos;
	vec3 to_cam = CAMERA_POSITION_WORLD - P;
	float dist = length(to_cam);
	vec3 V = to_cam / max(dist, 0.0001);
	vec3 L = normalize(u_sun_dir);
	float footprint = max(length(fwidth(v_lagxz)), 0.0004);
	float t = TIME * u_time_scale;

	// ---------------------------------------------------------- 法线
	vec3 disp;
	vec2 slope;
	float jac;
	eval_waves(v_lagxz, t, footprint, disp, slope, jac);

	float ground_h = gnd(P.xz);
	float depth = max(u_sea_level - ground_h, 0.0);

	// 近岸波的出现 tuy: 用三点差分取真实梯度（含卷倒形态）
	float sh_h = 0.0;
	float sh_ww = 0.0;
	vec2 sh_grad = vec2(0.0);
	if (depth < 26.0) {
		vec3 s0 = shore_eval(P.xz, v_tau, t);
		sh_h = s0.x;
		sh_ww = s0.y;
		float e = max(0.35, footprint * 0.9);
		float hx = shore_eval(P.xz + vec2(e, 0.0), v_tau, t).x;
		float hz = shore_eval(P.xz + vec2(0.0, e), v_tau, t).x;
		sh_grad = vec2(hx - sh_h, hz - sh_h) / e;
	}

	// 短波斜率调制：阵风 / 浮油 / 风纹（移植 SeaDetail）
	float rough = 1.0;
	float gust = 0.5;
	float slick = 0.0;
	float streak = 0.0;
	if (u_use_detail > 0.5) {
		vec2 wp = v_lagxz - u_wind_dir * (t * u_wind_speed * 0.7);
		float g1 = texture(sea_noise, wp / 620.0).x;
		float g2 = texture(sea_noise, wp / 230.0 + vec2(t * 0.0009, 0.37)).y;
		gust = clamp((g1 * 0.62 + g2 * 0.38 - 0.5) * 2.4 + 0.5, 0.0, 1.0);
		vec2 w = normalize(u_wind_dir);
		float along = dot(wp, w);
		float across = dot(wp, vec2(-w.y, w.x)) + (g2 - 0.5) * 26.0;
		float sl = texture(sea_noise, vec2(along / 1100.0, across / 70.0)).z;
		float calm = smoothstep(13.0, 4.0, u_wind_speed);
		slick = smoothstep(0.64, 0.76, sl) * (1.0 - gust * 0.8) * calm;
		float st = texture(sea_noise, vec2(along / 380.0, across / 11.0) + vec2(0.13, 0.71)).w;
		streak = smoothstep(0.68, 0.82, st) * smoothstep(6.0, 12.0, u_wind_speed) * 0.30;
		rough = mix(0.55, 1.5, gust) * (1.0 - slick * 0.8);
	}
	slope *= rough;

	vec2 total_slope = slope + sh_grad;
	vec3 N = normalize(vec3(-total_slope.x, 1.0, -total_slope.y));

	// 上方看还是水下看（Tidewater 用 (camHeight) 与 facet 折叠判定）
	float cam_h = CAMERA_POSITION_WORLD.y - u_sea_level;
	bool folded = jac < 0.1 || N.y < 0.35;
	bool near_surface = abs(cam_h) < 1.5;
	bool view_from_below = near_surface ? (cam_h < 0.0) : (cam_h < 0.0 || FRONT_FACING == false);
	vec3 Nup = N;
	vec3 Nside = view_from_below ? -Nup : Nup;
	vec3 Nview = normalize(Nside + V * max(-dot(Nside, V) + 0.03, 0.0));

	// ---------------------------------------------------------- 白浪 / 泡沫
	float wind_gate = smoothstep(2.5, 8.5, u_wind_speed) * 0.75 + 0.25;
	float fresh = clamp((0.90 - jac) * 2.5, 0.0, 1.0) * wind_gate;
	float whitecaps = fresh * mix(0.5, 1.5, gust) + streak * 0.5;
	float coverage = clamp(whitecaps * 0.62 + sh_ww * 0.8, 0.0, 1.0);
	coverage *= 1.0 - smoothstep(0.35, 0.08, footprint) * 0.25;

	float foam = coverage;
	if (u_use_detail > 0.5) {
		vec2 fuv = v_lagxz * 0.09;
		float p1 = texture(lace_tex, fuv).x;
		vec2 r2 = vec2(fuv.x * 0.8 - fuv.y * 0.6, fuv.x * 0.6 + fuv.y * 0.8);
		float p2 = texture(lace_tex, r2 * 2.37 + vec2(0.31, 0.77)).x;
		float pattern = p1 * 0.62 + p2 * 0.38;
		float thresh = 1.05 - coverage * 1.1;
		float soft = 0.06 + footprint * 0.10;
		float detail_f = smoothstep(thresh - soft, thresh + soft, pattern) * (texture(lace_tex, fuv).y * 0.25 + 0.8);
		float far_f = smoothstep(0.15, 1.2, footprint);
		foam = mix(detail_f, coverage * 0.85, far_f);
	}
	// 拍岸线：水膜极薄处始终有一圈持久的泡沫蕾丝
	float edge_foam = (1.0 - smoothstep(0.02, 0.55, P.y - ground_h)) * smoothstep(-0.15, 0.05, ground_h - u_sea_level);
	foam = clamp(foam + sh_ww * 0.30 + edge_foam * 0.30, 0.0, 1.0);
	// 气泡混入 → 水变乳青、看不见底
	float aeration = clamp(sh_ww * 0.8 * (1.0 - smoothstep(-0.1, 0.3, depth)) + fresh * 0.15, 0.0, 1.0);

	// ---------------------------------------------------------- 粗糙度（Cox-Munk）
	float mss = (0.003 + u_wind_speed * 0.00512) * rough;
	float kpx = PI / footprint;
	float unresolved = clamp(log2(110.0 / kpx) / 9.0, 0.0, 1.0);
	float alpha2 = (u_water_rough * u_water_rough + mss * 2.0 * unresolved * rough * rough + foam * 0.2 + aeration * 0.03);
	float sigma_unres = sqrt(mss * unresolved * rough * rough);

	vec3 sun_light = u_sun_color;
	vec3 out_col = vec3(0.0);
	float out_alpha = 1.0;

	if (!view_from_below) {
		// =============================================== 水上
		vec3 N_a = Nview;
		float NdV = max(dot(N_a, V), 0.0001);
		float F = fresnelDielectric(NdV, OT_IOR);

		// ---- 反射
		vec3 Rraw = reflect(-V, N_a);
		float Rup = max(Rraw.y, 0.004) + sigma_unres * 1.3 * (1.0 - max(Rraw.y, 0.0));
		vec3 R = normalize(vec3(Rraw.x, Rup, Rraw.z));
		float thickness0 = P.y - ground_h;
		float horizon_occ = max(smoothstep(-0.40, 0.08, Rraw.y), smoothstep(0.25, 0.06, thickness0));
		// 指向地平线以下的反射光线打在别的波浪上：收敛到深海本色（过暗会在远海拉出一条暗带）
		vec3 sea_deep = vec3(0.06, 0.19, 0.30);
		vec3 refl_col = mix(sea_deep, sky_radiance(R, 1.0), horizon_occ) * u_refl;

		// ---- 太阳镜面（GGX，三项 FF=lF）
		vec3 Hv = normalize(L + V);
		float NdL = max(dot(N_a, L), 0.0);
		float NdH = max(dot(N_a, Hv), 0.0);
		float VdH = max(dot(V, Hv), 0.0);
		float Fs = fresnelDielectric(VdH, OT_IOR);
		float spec = dGGX(NdH, alpha2) * vSmithGGX(NdL, NdV, alpha2) * Fs * NdL;
		vec3 sun_spec = sun_light * min(spec, 400.0);

		// ---- 折射：Snell 折射光线 ray-march 到海床
		vec3 Tr = refract(-V, N_a, 1.0 / OT_IOR);
		if (dot(Tr, Tr) < 0.5) { Tr = -V; }
		vec3 Tv = normalize(vec3(Tr.x, min(Tr.y, -0.08), Tr.z));
		float tdown = max(-Tv.y, 0.04);

		float Lt = max(P.y - ground_h, 0.0) / tdown;
		if (Lt < 100.0) {
			float L1 = max(P.y - gnd(P.xz + Tv.xz * min(Lt, 200.0)), 0.0) / tdown;
			Lt = max(P.y - gnd(P.xz + Tv.xz * min(L1 * 0.5 + Lt * 0.5, 200.0)), 0.0) / tdown;
		}
		float Lter = clamp(Lt, 0.0, 400.0);

		vec2 hit_xz = P.xz + Tv.xz * min(Lter, 80.0);
		float hit_h = gnd(hit_xz);
		float path_len = clamp(min(Lter, max(P.y - hit_h, 0.0) / tdown), 0.0, 400.0);

		// ---- 海床着色 + 焦散
		vec2 bed_grad = gnd_grad(hit_xz, max(0.6, footprint * 0.6));
		vec3 bed_n = normalize(vec3(-bed_grad.x, 1.0, -bed_grad.y));
		vec3 bed_albedo = seabed_color(hit_xz, hit_h, bed_grad);
		float caust = 0.0;
		if (u_use_detail > 0.5) {
			vec2 cv = hit_xz * 0.13 + vec2(t * 0.03, t * 0.021);
			float c1 = texture(lace_tex, cv).y;
			float c2 = texture(lace_tex, hit_xz * 0.31 - vec2(t * 0.02, t * 0.017)).z;
			caust = clamp((c1 * 0.55 + c2 * 0.45) * 2.0 - 1.0, -1.0, 1.0);
		}
		float caust_k = caust * 0.16 * exp(-max(u_sea_level - hit_h, 0.0) * 0.20) * clamp(L.y, 0.0, 1.0);
		vec3 scene_col = bed_albedo * (sun_light * max(dot(bed_n, L), 0.0) * (1.0 + caust_k) + u_sky_irr) * OT_INV_PI;

		// ---- 水体：Beer-Lambert + 单次散射（同 WaterMaterial Above Water 段）
		vec3 sigA = u_absorption;
		vec3 sigS = u_scattering + vec3(aeration * 0.9);
		vec3 sigT = sigA + sigS;
		vec3 Tview = exp(-sigT * path_len);

		vec3 Ls = -refract(-L, vec3(0.0, 1.0, 0.0), 1.0 / OT_IOR);
		float muS = max(Ls.y, 0.1);
		float muV = max(-Tv.y, 0.15);
		vec3 sun_in = sun_light * (1.0 - fresnelDielectric(max(L.y, 0.02), OT_IOR));
		vec3 kSun = sigT * (1.0 + muV / muS);
		vec3 kAmb = sigT * (1.0 + muV / 0.75);
		float cos_ph = dot(Tv, Ls);
		float phase = phaseHG(cos_ph, 0.86) * 0.7 + 0.02387324;
		vec3 bb = sigS * mix(u_backscatter, 0.06, clamp(aeration * 2.0, 0.0, 1.0));
		vec3 albedoMS = bb * 1.32 / (sigA + bb);
		vec3 in_sun = sun_in * (sigS * phase + albedoMS * sigT * OT_INV_PI) * (vec3(1.0) - exp(-kSun * path_len)) / kSun;
		vec3 in_amb = u_sky_irr * (sigS * 0.25 + albedoMS * sigT) * (vec3(1.0) - exp(-kAmb * path_len)) / kAmb;

		// ---- 波峰次表面透光
		vec2 vH = normalize(vec2(V.x, V.z) + vec2(0.0001));
		vec2 lH = normalize(vec2(L.x, L.z) + vec2(0.0001));
		float back = pow(clamp(dot(vH, -lH) * 0.6 + 0.4, 0.0, 1.0), 2.5);
		float crest = clamp(disp.y * 0.9 + 0.1, 0.0, 1.0) * (clamp((1.0 - N_a.y) * 4.0, 0.0, 1.0) + 0.25);
		vec3 sss = sun_light * vec3(0.12, 0.55, 0.45) * 0.06 * back * crest * u_sss * smoothstep(0.0, 0.25, L.y);

		vec3 transmitted = scene_col * Tview + in_sun + in_amb + sss;

		// ---- 泡沫：明亮漫反射散射体（albedo 0.85，wrapped sun + 天空辐照）
		vec3 foam_lit = (sun_light * (max(dot(N_a, L), 0.0) * 0.75 + 0.25) * OT_INV_PI + u_sky_irr * 0.95) * 0.85;
		vec3 foam_col = foam_lit * u_foam;

		vec3 water_col = mix(transmitted, refl_col, F) + sun_spec;
		out_col = mix(water_col, foam_col + sun_spec * 0.05, clamp(foam, 0.0, 1.0));

		// ---- 浅

		// 浅水/拍岸处的透明度：让角色的腿、木桩、礁石能透出来
		float thick = P.y - ground_h;
		out_alpha = clamp(mix(0.45, 1.0, smoothstep(0.02, 0.45, thick)), 0.0, 1.0);
		if (thick < 0.02) { out_alpha = 0.0; }
	} else {
		// =============================================== 水下：Snell 窗
		vec3 N_b = Nview;
		float NdV2 = max(dot(N_b, V), 0.0001);
		float F2 = fresnelDielectric(NdV2, 1.0 / OT_IOR);
		vec3 Tt = refract(-V, N_b, OT_IOR);
		vec3 Td = (dot(Tt, Tt) > 0.5) ? normalize(Tt) : vec3(0.0, 1.0, 0.0);
		vec3 sky_t = min(sky_radiance(Td, 1.0), vec3(60.0));

		vec3 sigA2 = u_absorption;
		vec3 sigS2 = u_scattering;
		vec3 sigT2 = sigA2 + sigS2;
		vec3 bb2 = sigS2 * u_backscatter;
		vec3 albedoMS2 = bb2 * 1.32 / (sigA2 + bb2);
		vec3 Rr = reflect(-V, N_b);
		vec3 LsU = -refract(-L, vec3(0.0, 1.0, 0.0), 1.0 / OT_IOR);
		float muU = max(LsU.y, 0.15);
		float phR = phaseHG(dot(Rr, LsU), 0.86) * 0.7 + 0.02387324;
		float kS = sigT2.x * (1.0 - min(Rr.y, 0.0) / muU);
		float kA = sigT2.x * (1.0 - min(Rr.y, 0.0) / 0.8);
		vec3 eSunU = sun_light * (1.0 - fresnelDielectric(max(L.y, 0.02), OT_IOR));
		vec3 deep_col = eSunU * (sigS2 * phR + albedoMS2 * sigT2 * OT_INV_PI) / kS
				+ u_sky_irr * PI * (sigS2 / (4.0 * PI) + albedoMS2 * sigT2 * OT_INV_PI) / kA;
		vec3 foam_under = (u_sky_irr + sun_light * 0.5) * 0.25;
		out_col = mix(sky_t * (1.0 - F2) + deep_col * F2, foam_under, clamp(foam, 0.0, 1.0) * 0.7);
		out_alpha = 1.0;
	}

	// 调试视图：1 法线 2 深度 3 泡沫 4 足迹 5 菲涅尔
	if (u_debug == 1) { out_col = Nup * 0.5 + 0.5; }
	else if (u_debug == 2) { out_col = vec3(depth * 0.02, 0.0, 0.0); }
	else if (u_debug == 3) { out_col = vec3(foam); }
	else if (u_debug == 4) { out_col = vec3(fract(footprint * 0.5), 0.0, 0.0); }
	else if (u_debug == 5) { out_col = vec3(sh_ww, sh_h * 0.5 + 0.5, 0.0); }

	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	EMISSION = out_col * u_exposure;
	ALPHA = out_alpha;
	if (out_alpha < 0.02) { discard; }
}
