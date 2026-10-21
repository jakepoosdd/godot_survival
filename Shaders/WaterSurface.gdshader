shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// 海面（水平 PlaneMesh，**不要**再绕 X 转 -90°！PlaneMesh 默认就躺在 XZ 平面上）。
// 设计：本体只做「薄薄一层会反光的青水」，水色深浅完全交给海床地形着色
//（world.gd 的 _make_terrain_material 按水深给沙→青→深蓝），这样
//  ① 无需 depth_texture/screen_texture，不会出现屏幕反馈花屏；
//  ② 近岸自动是通透的浅绿松石色，远海自动是深蓝，视觉上等价于 depth-based 水色；
//  ③ 掠射角由菲涅尔补天空色，避免远处硬边。
uniform vec4 tint : source_color = vec4(0.26, 0.62, 0.72, 0.34);
uniform vec4 horizon_color : source_color = vec4(0.55, 0.74, 0.88, 1.0);
uniform vec4 sparkle_color : source_color = vec4(0.92, 0.97, 1.0, 1.0);
uniform float wave_height : hint_range(0.0, 1.0) = 0.10;
uniform float wave_speed : hint_range(0.0, 1.0) = 0.22;
uniform float fresnel_power : hint_range(0.5, 6.0) = 2.4;
uniform float horizon_fade_start : hint_range(0.0, 4000.0) = 700.0;
uniform float horizon_fade_end : hint_range(0.0, 6000.0) = 2600.0;
uniform float sparkle_strength : hint_range(0.0, 1.0) = 0.18;

varying vec3 v_world;
varying float v_wave;

void vertex() {
	// 低频涌动：波长 ~130m，顶点细分足够大也看不出三角边（避免掠射角摩尔纹）
	float t = TIME * wave_speed;
	float w = sin(VERTEX.x * 0.048 + t) * 0.5 + sin(VERTEX.z * 0.041 + t * 1.31) * 0.5;
	VERTEX.y += w * wave_height;
	v_wave = w;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world);
	float grazing = 1.0 - clamp(abs(V.y), 0.0, 1.0);
	float fres = pow(grazing, fresnel_power);

	// 远处（地平线）融入天空色，水面与天空无缝相接
	float dist = length(CAMERA_POSITION_WORLD.xz - v_world.xz);
	float hf = smoothstep(horizon_fade_start, horizon_fade_end, dist);

	vec3 col = mix(tint.rgb, horizon_color.rgb, hf);
	col = mix(col, sparkle_color.rgb, clamp(v_wave * 0.12 + 0.06, 0.0, 1.0) * sparkle_strength);
	// 掠射角反光（天空/太阳），克制不冲白
	col = mix(col, horizon_color.rgb, fres * 0.30);

	ALBEDO = col;
	ROUGHNESS = mix(0.045, 0.22, fres);
	METALLIC = 0.0;
	// 垂直看几乎全透（露出海床深浅色），掠射角逐渐变实
	ALPHA = clamp(mix(tint.a, 0.72, fres) + hf * 0.55, 0.0, 1.0);
}
