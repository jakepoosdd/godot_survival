shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// 简单稳定水面：不依赖 depth_texture / screen_texture。
// 关键：避免高频世界坐标正弦（在掠射角下会产生摩尔纹竖条），
// 改用低频色彩渐变 + 柔和高光；远距离靠雾/天空融入。

uniform vec4 shallow_color : source_color = vec4(0.28, 0.72, 0.74, 0.72);
uniform vec4 deep_color : source_color = vec4(0.03, 0.18, 0.38, 0.94);
uniform vec4 horizon_color : source_color = vec4(0.62, 0.78, 0.86, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float water_depth : hint_range(0.1, 20.0) = 4.0;
uniform float wave_height : hint_range(0.0, 1.5) = 0.10;
uniform float wave_speed : hint_range(0.0, 0.5) = 0.06;
uniform float fresnel_power : hint_range(0.0, 4.0) = 3.0;
uniform float horizon_fade_start : hint_range(0.0, 1.0) = 0.55;
uniform float horizon_fade_end : hint_range(0.0, 1.0) = 0.98;

varying vec3 v_world_pos;

void vertex() {
	float t = TIME * wave_speed;
	// 平面绕 X 转 -90° -> 局部 Z = 世界 Y；沿局部 x/y 取相位
	float w = sin(VERTEX.x * 0.08 + t) * 0.5 + cos(VERTEX.y * 0.075 + t * 1.3) * 0.5;
	VERTEX.z += w * wave_height;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 极低频色彩渐变（避免高频摩尔纹）
	float band = 0.5 + 0.5 * sin(v_world_pos.x * 0.06 + v_world_pos.z * 0.05 + TIME * 0.15);
	vec3 col = mix(deep_color.rgb, shallow_color.rgb, band);

	// 菲涅尔（随视线角度）：掠射角趋向天空/地平线色
	vec3 V = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	float fres = pow(1.0 - clamp(V.y, 0.0, 1.0), max(0.1, fresnel_power));

	// 远处（地平线）淡入天空色，避免水面在远端形成硬边/闪烁条纹
	float dist = length(CAMERA_POSITION_WORLD.xz - v_world_pos.xz);
	float hf = smoothstep(300.0, 900.0, dist);
	col = mix(col, horizon_color.rgb, hf);

	ALBEDO = col;
	ROUGHNESS = mix(0.06, 0.30, band);
	METALLIC = 0.0;
	// 垂直看更透明，掠射更实
	ALPHA = mix(shallow_color.a, deep_color.a, 0.5) + fres * 0.25 + hf * 0.5;
	ALPHA = clamp(ALPHA, 0.0, 1.0);
	// 掠射反光（克制，不冲白）
	ALBEDO = mix(ALBEDO, horizon_color.rgb, fres * 0.35);

	// 岸线泡沫：世界高度接近海面（y≈0）的地方出现白沫
	// 用海面自身 y 与世界坐标判断不了水深，这里仅用菲涅尔+低频噪声做轻微浪花点缀
	float foam_n = sin(v_world_pos.x * 0.35 + TIME * 0.8) * 0.5 + 0.5;
	float foam_band = smoothstep(0.92, 1.0, foam_n) * 0.25;
	ALBEDO = mix(ALBEDO, foam_color.rgb, foam_band);
}
