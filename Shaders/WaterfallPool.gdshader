// 瀑布水潭：撞击涟漪 + 缓旋噪声 + 边缘白沫环。
// 用世界坐标 XZ 画同心涟漪（与网格 UV 无关），不依赖 screen/depth texture。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;

uniform vec4 u_shallow : source_color = vec4(0.30, 0.62, 0.66, 1.0);  // 潭心青碧
uniform vec4 u_deep    : source_color = vec4(0.10, 0.34, 0.46, 1.0);  // 潭边深青
uniform float u_radius = 6.0;      // 潭半径（米）
uniform float u_flow_speed = 1.0;

varying vec3 v_wpos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1,0)), u.x),
	           mix(hash12(i + vec2(0,1)), hash12(i + vec2(1,1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 3; i++) { v += a * vnoise(p); p = p * 2.13 + vec2(11.7, 5.3); a *= 0.5; }
	return v;
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 rel = (v_wpos.xz) ;   // 潭心由节点位置决定，这里用节点局部近似：以网格中心为原点
	// CylinderMesh 顶面 UV 是圆映射；直接用 UV 的极坐标最稳
	vec2 cuv = UV - vec2(0.5);
	float r = length(cuv) * 2.0;              // 0=潭心 1=潭缘
	float ang = atan(cuv.y, cuv.x);

	float t = TIME * u_flow_speed;
	// 撞击涟漪：从潭心向外扩的环
	float ripple = sin(r * 22.0 - t * 5.0) * 0.5 + 0.5;
	ripple *= smoothstep(0.9, 0.15, r);        // 越靠心越强
	// 缓转的水流纹理
	float swirl = fbm(vec2(ang * 3.0 + r * 4.0, r * 6.0 - t * 0.8));
	// 潭缘白沫环
	float rim = smoothstep(0.72, 0.97, r) * smoothstep(0.4, 0.75, fbm(vec2(ang * 8.0, t * 0.5)));

	float shade = clamp(r * 0.7 + ripple * 0.25 + swirl * 0.2, 0.0, 1.0);
	vec3 col = mix(u_shallow.rgb, u_deep.rgb, shade);
	col = mix(col, vec3(0.95, 0.99, 1.0), rim * 0.8);

	ALBEDO = col;
	EMISSION = vec3(0.5, 0.75, 0.8) * ripple * 0.10 * (1.0 - r);
	ALPHA = clamp(0.88 - r * 0.10 + rim * 0.12, 0.0, 1.0);
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
}
