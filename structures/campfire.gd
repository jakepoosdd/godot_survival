extends "res://inventory/interactable.gd"
## 营火（可放置结构）。interact 时把背包里的生肉烤成熟肉；没有生肉则在火边取暖回一点精神。
## 视觉在 _ready 里用基础图元拼出（无需外部网格文件）。
## use_external_visual = true 时跳过内置图元/灯光，改用外部（如世界摆位的 GLB）视觉，
## 仅保留碰撞体 + interact 逻辑，避免双重视觉。

var use_external_visual := false

func _ready() -> void:
	prompt = "营火：烤生肉 / 取暖 (E)"
	if not use_external_visual:
		_build_visual()
	# 碰撞体：供交互系统射线命中（本节点即 StaticBody3D，带 interact 方法）
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.extents = Vector3(1.0, 1.0, 1.0)
	col.shape = bs
	col.position.y = 0.6
	add_child(col)

func _build_visual() -> void:
	# 石圈（略小、压低，别抢火苗）
	for i in 8:
		var a := float(i) / 8.0 * TAU
		var rock := MeshInstance3D.new()
		rock.name = "Stone"
		var sm := SphereMesh.new()
		sm.radius = 0.15
		sm.height = 0.3
		rock.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.5, 0.5, 0.52)
		rock.material_override = m
		rock.position = Vector3(cos(a) * 0.52, 0.1, sin(a) * 0.52)
		add_child(rock)
	# 交叉木柴（压在石圈内、更矮，让火从上方窜出）
	for k in 2:
		var logm := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.07
		cyl.height = 0.85
		logm.mesh = cyl
		logm.rotation.z = PI / 2.0
		logm.rotation.y = float(k) * PI / 2.0
		logm.position.y = 0.16
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.35, 0.22, 0.12)
		logm.material_override = lm
		add_child(logm)
	# 火焰：3 片"竖直"纯火苗贴图交叉摆放（0/60/120 度）组成立体火柱。
	# 贴图 fire_heart.png 是程序化生成的纯火苗（底橙红→顶黄白、带火尖、透明底），
	# 交叉后从任意角度看都有厚度，不再是正面纸片。缺图回退 fire_flame 再回退圆锥。
	var fire_tex: Texture2D = null
	if ResourceLoader.exists("res://assets/vfx/fire_heart.png"):
		fire_tex = load("res://assets/vfx/fire_heart.png") as Texture2D
	if fire_tex == null and ResourceLoader.exists("res://assets/vfx/fire_flame.png"):
		fire_tex = load("res://assets/vfx/fire_flame.png") as Texture2D
	if fire_tex != null:
		# 火柱容器（便于整体跳动动画）；火苗从柴堆顶窜出
		var flame_root := Node3D.new()
		flame_root.name = "Flame"
		flame_root.position.y = 0.62
		add_child(flame_root)
		# 三片交叉竖直火苗：每片是 XY 平面 QuadMesh（自然竖立），绕 Y 均匀分布。
		# 纯火苗贴图较瘦高，用 1.05 x 1.7，火焰自然从柴堆向上窜。
		var angles: Array[float] = [0.0, PI / 3.0, PI * 2.0 / 3.0]
		for i in angles.size():
			var seg := MeshInstance3D.new()
			seg.name = "FlameSeg%d" % i
			var qm := QuadMesh.new()
			qm.size = Vector2(1.05, 1.7)
			seg.mesh = qm
			var fm := StandardMaterial3D.new()
			fm.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			fm.cull_mode = BaseMaterial3D.CULL_DISABLED   # 双面可见，从背后也有火
			fm.albedo_texture = fire_tex
			fm.emission_enabled = true
			fm.emission_texture = fire_tex
			fm.emission = Color(1.0, 0.7, 0.3)
			fm.emission_energy = 1.7
			seg.material_override = fm
			seg.rotation.y = angles[i]
			flame_root.add_child(seg)
		# 火心：真 3D 发光球，给火柱一个实在的亮核（任何角度都亮）
		var core := MeshInstance3D.new()
		core.name = "Core"
		var csm := SphereMesh.new()
		csm.radius = 0.16
		csm.height = 0.32
		csm.radial_segments = 12
		csm.rings = 6
		core.mesh = csm
		var cm := StandardMaterial3D.new()
		cm.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		cm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cm.emission_enabled = true
		cm.emission = Color(1.0, 0.55, 0.18)
		cm.emission_energy = 2.4
		cm.albedo_color = Color(1.0, 0.55, 0.18, 1.0)
		core.material_override = cm
		core.position.y = 0.02
		flame_root.add_child(core)
		# 火星粒子（上浮小颗粒）
		var ember := GPUParticles3D.new()
		ember.name = "Ember"
		ember.amount = 12
		ember.lifetime = 1.2
		ember.emitting = true
		var epm := ParticleProcessMaterial.new()
		epm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		epm.emission_sphere_radius = 0.18
		epm.direction = Vector3(0, 1, 0)
		epm.spread = 28.0
		epm.initial_velocity_min = 0.4
		epm.initial_velocity_max = 1.0
		epm.gravity = Vector3(0, 0.25, 0)
		epm.scale_min = 0.04
		epm.scale_max = 0.10
		ember.process_material = epm
		var em := QuadMesh.new()
		em.size = Vector2(0.1, 0.1)
		ember.draw_pass_1 = em
		var emat := StandardMaterial3D.new()
		emat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		emat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		emat.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		emat.albedo_texture = fire_tex
		emat.emission_enabled = true
		emat.emission_texture = fire_tex
		emat.emission = Color(1.0, 0.7, 0.3)
		emat.emission_energy = 1.6
		ember.material_override = emat
		ember.position.y = 0.6
		add_child(ember)
	else:
		var flame := MeshInstance3D.new()
		flame.name = "Flame"
		var fm := CylinderMesh.new()
		fm.top_radius = 0.0
		fm.bottom_radius = 0.25
		fm.height = 0.7
		flame.mesh = fm
		var fmat := StandardMaterial3D.new()
		fmat.emission_enabled = true
		fmat.emission = Color(1.0, 0.4, 0.05)
		fmat.emission_energy = 2.0
		fmat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		fmat.albedo_color = Color(1.0, 0.5, 0.1, 0.9)
		flame.material_override = fmat
		flame.position.y = 0.7
		add_child(flame)
	# 点光源（Godot 4 中 PointLight3D 已更名为 OmniLight3D）
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 8.0
	light.omni_range = 12.0
	light.position.y = 0.9
	add_child(light)

func _process(_delta: float) -> void:
	var fl = get_node_or_null("Flame")
	if fl != null:
		# 火柱整体轻微跳动（三片交叉一起缩放，不变形）
		var s := 1.0 + sin(Time.get_ticks_msec() * 0.012) * 0.06
		fl.scale = Vector3(s, s, s)
	var lt = get_node_or_null("Light")
	if lt != null:
		lt.light_energy = 8.0 + sin(Time.get_ticks_msec() * 0.02) * 2.0

func interact(_player) -> void:
	if EventBus.cooking_menu_open:
		return
	if Inventory.has_cookable_raw():
		EventBus.cooking_menu_requested.emit()
	else:
		var ns = _player.get_node_or_null("NeedsSystem")
		if ns != null:
			ns.apply_effects(2.0, 0.0, 3.0)
		EventBus.toast.emit("在火边取暖，回了点精神")
