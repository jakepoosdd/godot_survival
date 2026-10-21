// 崖壁瀑布（移植 Tidewater 思路的程序化水流）：
//  - 双层垂直条纹 fbm（快细流 + 慢厚帘）叠加，取代纯色半透明片
//  - 底部撞击区白沫翻滚（Worley 花边感噪声）
//  - 两侧/顶部羽化，水流"长"在崖壁上而不是一块悬空的塑料片
//  - 顶点级横向摆动（下摆自由度高，贴崖壁的顶部不动）
// 不依赖 screen/depth texture（沿用本项目"绝不屏幕反馈"底线）。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled, shadows_disabled;

uniform float u_flow_speed = 1.6;     // 下落速度（uv/s）
uniform float u_width = 4.0;          // 瀑布宽度（米）
uniform float u_height = 18.0;        // 瀑布高度（米）
uniform float u_exposure = 1.0;
uniform vec4 u_tint : source_color = vec4(0.82, 0.92, 1.0, 1.0);

varying vec3 v_local;   // 局部坐标（x 横向, y 纵向）

// ---- hash / value noise / fbm（纯 ALU，无贴图） ----
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_local = VERTEX;
	// 顶点摆动：底部自由摆动，顶部贴崖壁。QuadMesh 局部 y: 顶=+h/2 底=-h/2
	float hnorm = clamp(0.5 - VERTEX.y / max(u_height, 0.001), 0.0, 1.0);
	float sway = sin(VERTEX.y * 0.9 + TIME * 2.3) * 0.06 + sin(VERTEX.y * 2.1 - TIME * 3.7) * 0.03;
	VERTEX.x += sway * hnorm * hnorm * u_width * 0.12;
}

void fragment() {
	// QuadMesh UV：x 横向 0..1，y 顶 0 → 底 1（水流方向：y 增大 = 往下落）
	vec2 uv = UV;
	float t = TIME * u_flow_speed;

	// 第 1 层：宽厚水帘（低频、慢）——竖向拉伸的 fbm 向下滚
	float sheet = fbm(vec2(uv.x * 5.0, uv.y * 1.2 - t * 0.55));
	// 第 2 层：细快流丝（高频、快）——瀑布的"速度感"主要来自这层
	float streak = fbm(vec2(uv.x * 18.0 + sheet * 1.5, uv.y * 2.0 - t * 1.9));
	float flow = sheet * 0.62 + streak * 0.55;

	// 条纹锐化：让水丝有明暗相间的"束"感
	float bands = smoothstep(0.25, 0.95, flow);

	// 底部撞击白沫：y 接近 1 处翻滚剧烈
	float base_d = smoothstep(0.62, 0.98, uv.y);
	float foam_n = fbm(vec2(uv.x * 14.0, uv.y * 9.0 - t * 2.6));
	float foam = base_d * smoothstep(0.35, 0.75, foam_n + base_d * 0.35);

	// 边缘羽化：两侧收窄（水柱中腰最宽），顶部渐隐融入崖壁
	float side = smoothstep(0.0, 0.18, uv.x) * smoothstep(1.0, 0.82, uv.x);
	float top_fade = smoothstep(0.0, 0.22, uv.y);
	// 水柱中线更实、边缘更透明
	float core = smoothstep(0.5, 0.18, abs(uv.x - 0.5));

	float alpha = (0.38 + 0.62 * bands) * side * top_fade;
	alpha = mix(alpha, 0.95, foam);              // 白沫几乎不透明
	alpha *= mix(0.75, 1.0, core);

	vec3 water = u_tint.rgb * (0.55 + 0.75 * bands);
	vec3 col = mix(water, vec3(1.02, 1.04, 1.05), foam); // 白沫提亮到纯白
	col *= u_exposure;

	ALBEDO = col;
	EMISSION = col * (0.18 + foam * 0.30);   // 轻自发光：阴影里也保持"水"的亮感，不再发灰
	ALPHA = clamp(alpha, 0.0, 1.0);
	ROUGHNESS = 0.25;
}
