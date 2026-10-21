extends Node
## 法术特效：优先使用生成的贴图（assets/vfx/*.png，加法混合 + billboard），
## 缺图时回退到纯发光几何体，保证没有贴图也不会崩。

const MAGIC_COLOR := Color(0.55, 0.45, 1.0)   # 法师魔法弹（紫）
const HEAL_COLOR  := Color(0.3, 1.0, 0.5)      # 治疗（绿）
const BOLT_SPEED  := 16.0                        # 飞弹速度（单位/秒）

const TEX_BOLT   := "res://assets/vfx/magic_bolt.png"
const TEX_IMPACT := "res://assets/vfx/magic_impact.png"
const TEX_HEAL   := "res://assets/vfx/heal_mote.png"
const TEX_GLOW   := "res://assets/vfx/soft_glow.png"
const TEX_ARROW  := "res://assets/vfx/arrow.png"

func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

## 发光精灵材质：贴图优先（加法混合 + 朝向相机），无贴图回退到纯发光色。
## billboard=false 时关闭朝向相机（飞箭用，改由 arrow_projectile.gd 手动定向）。
func _sprite_mat(color: Color, tex: Texture2D, additive := true, billboard := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	if billboard:
		m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if tex != null:
		m.albedo_texture = tex
		m.emission_enabled = true
		m.emission_texture = tex
		m.emission = Color(1.0, 1.0, 1.0)
		m.emission_energy = 1.5
	else:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy = 2.2
		m.albedo_color = Color(color.r, color.g, color.b, 1.0)
	return m

func _sprite_mesh(size := 0.4) -> Mesh:
	# 用 QuadMesh（XY 竖直平面）：天然竖立，禁 billboard 时也不会变成"躺地片"。
	# 旧用 PlaneMesh 是 XZ 水平面，一旦 billboard 失效就会拍平，是纸片/隐形的隐患。
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	return qm

func _make_particles(color: Color, tex: Texture2D, count: int, lifetime: float, upward: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = count
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.spread = 70.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 3.2
	if upward > 0.0:
		pm.direction = Vector3(0, 1, 0)
		pm.gravity = Vector3(0, -1.5, 0)
	else:
		pm.direction = Vector3(0, 0, 0)
		pm.gravity = Vector3(0, -3.0, 0)
	p.process_material = pm
	p.draw_pass_1 = _sprite_mesh(0.3)
	p.material_override = _sprite_mat(color, tex)
	return p

func _auto_free(node: Node, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(node):
		node.queue_free()

## 纯发光实体核心（真 3D 球，任何角度看都有体积，不再是纸片）。
func _glow_sphere(radius: float, color: Color) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	return sm

func _glow_mat(color: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.emission_enabled = true
	m.emission = color
	m.emission_energy = energy
	m.albedo_color = Color(color.r, color.g, color.b, 1.0)
	return m

## 飞弹：真 3D 发光球体 + billboard 光晕贴图 + 拖尾粒子。任何角度都是"球"而非纸片。
func magic_bolt(from: Vector3, to: Vector3, color: Color, on_arrive: Callable) -> void:
	var orb := Node3D.new()
	orb.position = from
	get_tree().root.add_child(orb)
	# 核心：真 3D 自发光球（体积感来源）。energy 适中，别糊成死白球。
	var core := MeshInstance3D.new()
	core.mesh = _glow_sphere(0.15, color)
	core.material_override = _glow_mat(color, 2.4)
	orb.add_child(core)
	# 内核：更亮更小的一点白芯（有层次，不是整体纯白）
	var inner := MeshInstance3D.new()
	inner.mesh = _glow_sphere(0.08, color)
	inner.material_override = _glow_mat(color.lerp(Color.WHITE, 0.55), 3.0)
	orb.add_child(inner)
	# 外层光晕：billboard 贴图（贴图原本就是球状发光，正面看更饱满）
	var tex := _tex(TEX_BOLT)
	if tex != null:
		var halo := MeshInstance3D.new()
		halo.mesh = _sprite_mesh(0.55)
		var hm := _sprite_mat(color, tex, true, true)
		hm.emission_energy = 0.9
		halo.material_override = hm
		halo.position.z = -0.01
		orb.add_child(halo)
	# 拖尾
	var trail := _make_particles(color, _tex(TEX_GLOW), 10, 0.32, 0.0)
	orb.add_child(trail)
	trail.emitting = true
	var dist := from.distance_to(to)
	var dur := maxf(0.12, dist / BOLT_SPEED)
	var t := create_tween()
	t.set_trans(Tween.TRANS_LINEAR)
	t.tween_property(orb, "global_position", to, dur)
	t.tween_callback(func():
		impact_burst(to, color)
		if on_arrive.is_valid():
			on_arrive.call()
		orb.queue_free()
	)

## 箭矢：从 from 飞到 to，到达时结算（非魔法，不加打击反馈）。
## 有 arrow.png 用贴图（透明底、竖直朝上），无图用棕色占位镖，都不会崩。
## 飞箭用 arrow_projectile.gd 让箭尖在屏幕里始终指向目标，避免"纸片"观感。
const ARROW_PROJ := preload("res://core/arrow_projectile.gd")

func arrow_shot(from: Vector3, to: Vector3, on_arrive: Callable) -> void:
	var arr := ARROW_PROJ.new()
	arr.mesh = _sprite_mesh(0.3)
	var tex := _tex(TEX_ARROW)
	arr.material_override = _sprite_mat(Color(0.55, 0.38, 0.2), tex, false, false)
	arr.scale = Vector3(1.0, 2.6, 1.0)
	arr.position = from
	arr._target = to
	get_tree().root.add_child(arr)
	var dist := from.distance_to(to)
	var dur := maxf(0.08, dist / 34.0)
	var t := create_tween()
	t.set_trans(Tween.TRANS_LINEAR)
	t.tween_property(arr, "global_position", to, dur)
	t.tween_callback(func():
		if on_arrive.is_valid():
			on_arrive.call()
		arr.queue_free()
	)

## 命中爆点：真 3D 膨胀球核 + 扩展淡出的星芒贴图 + 粒子喷溅。
func impact_burst(pos: Vector3, color: Color) -> void:
	# 3D 球核：从中心向外膨胀、淡出，给爆点体积感（energy 适中，避免糊成死白）
	var core := MeshInstance3D.new()
	core.mesh = _glow_sphere(0.2, color)
	core.material_override = _glow_mat(color.lerp(Color.WHITE, 0.25), 2.2)
	core.position = pos
	get_tree().root.add_child(core)
	var tc := create_tween()
	tc.set_trans(Tween.TRANS_QUAD)
	tc.tween_property(core, "scale", Vector3(2.6, 2.6, 2.6), 0.28)
	tc.parallel().tween_property(core.material_override, "emission_energy", 0.0, 0.28)
	tc.tween_callback(core.queue_free)
	var tex := _tex(TEX_IMPACT)
	if tex != null:
		# 交叉 3 片（0/60/120 度）星芒：从任意角度看都有形状，不再是单张纸片。
		# 用普通 alpha 混合、不开自发光，避免叠出大白团，保留尖刺轮廓。
		var burst := Node3D.new()
		burst.position = pos
		get_tree().root.add_child(burst)
		var angles: Array[float] = [0.0, PI / 3.0, PI * 2.0 / 3.0]
		var mats: Array = []
		for i in angles.size():
			var spr := MeshInstance3D.new()
			spr.mesh = _sprite_mesh(1.0)
			var sm := StandardMaterial3D.new()
			sm.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			sm.albedo_texture = tex
			sm.albedo_color = Color(color.r, color.g, color.b, 0.85)
			spr.material_override = sm
			spr.rotation.y = angles[i]
			burst.add_child(spr)
			mats.append(sm)
		var t := create_tween()
		t.set_trans(Tween.TRANS_QUAD)
		t.tween_property(burst, "scale", Vector3(2.0, 2.0, 2.0), 0.3)
		for sm in mats:
			t.parallel().tween_property(sm, "albedo_color", Color(color.r, color.g, color.b, 0.0), 0.3)
		t.tween_callback(burst.queue_free)
	else:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.1; torus.outer_radius = 0.35
		ring.mesh = torus
		ring.rotation.x = PI * 0.5
		var mat := StandardMaterial3D.new()
		mat.emission_enabled = true; mat.emission = color; mat.emission_energy = 2.2
		mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
		mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = mat
		ring.position = pos
		get_tree().root.add_child(ring)
		var t := create_tween()
		t.set_trans(Tween.TRANS_QUAD)
		t.tween_property(ring, "scale", Vector3(3.2, 3.2, 3.2), 0.3)
		t.parallel().tween_property(mat, "albedo_color", Color(color.r, color.g, color.b, 0.0), 0.3)
		t.tween_callback(ring.queue_free)
	var p := _make_particles(color, _tex(TEX_GLOW), 16, 0.4, 0.0)
	p.position = pos
	get_tree().root.add_child(p)
	p.emitting = true
	_auto_free(p, 0.7)

## 治疗绿光：上浮粒子 + 柔光球；回血飘字走 damage_popup(kind="heal") 复用 HUD。
func heal_burst(target: Node3D, color: Color, amount: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var base: Vector3 = target.global_position + Vector3(0, 1.0, 0)
	var p := _make_particles(color, _tex(TEX_HEAL), 18, 0.9, 1.0)
	p.position = base
	get_tree().root.add_child(p)
	p.emitting = true
	_auto_free(p, 1.3)
	var glow := MeshInstance3D.new()
	glow.mesh = _sprite_mesh(1.0)
	glow.material_override = _sprite_mat(color, _tex(TEX_GLOW))
	glow.position = base
	get_tree().root.add_child(glow)
	var t := create_tween()
	t.tween_property(glow, "scale", Vector3(1.5, 1.5, 1.5), 0.5)
	t.parallel().tween_property(glow.material_override, "albedo_color", Color(color.r, color.g, color.b, 0.0), 0.8)
	t.tween_callback(glow.queue_free)
	EventBus.damage_popup.emit(base + Vector3(0, 0.6, 0), amount, "heal")
