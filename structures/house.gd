extends "res://inventory/interactable.gd"
## 房子（可放置结构）。interact 时进屋休息到天亮（与帐篷同逻辑）。
## 视觉用项目自带的村庄外屋模型 EA03_Village_OutBuilding_PentHouse_01a.fbx（完整单体建筑）。

const HOUSE_PATH := "res://Objects/EA03_Village_OutBuilding_PentHouse_01a.fbx"
const HOUSE_SCALE := 0.85

# 上材质：FBX 自带材质在 Godot FBX 导入下常丢失贴图变成白模，这里统一套一层木色材质。
const WOOD_COLOR := Color(0.46, 0.34, 0.23)   # 墙体暖木色
const ROOF_COLOR := Color(0.30, 0.22, 0.16)   # 屋顶深木色

func _ready() -> void:
	prompt = "房子：进屋休息 (E)"
	_build_visual()
	_build_collision()

func _build_visual() -> void:
	var res = load(HOUSE_PATH)
	if res is PackedScene:
		var m := (res as PackedScene).instantiate() as Node3D
		if m != null:
			m.scale = Vector3.ONE * HOUSE_SCALE
			add_child(m)
			_apply_wood_material(m)
			return
	_build_fallback_hut()

# 遍历实例化的 FBX，给所有网格套木色材质（按节点名区分墙体/屋顶），解决白模。
func _apply_wood_material(root: Node) -> void:
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = WOOD_COLOR
	wall_mat.roughness = 0.85
	wall_mat.metallic = 0.0
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = ROOF_COLOR
	roof_mat.roughness = 0.92
	roof_mat.metallic = 0.0
	_apply_material_recursive(root, wall_mat, roof_mat)

func _apply_material_recursive(node: Node, wall_mat: StandardMaterial3D, roof_mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		# FBX 网格名多含 Roof/Wall 之类，按名区分屋顶与墙体；兜底统一走墙体材质
		var nm := str(node.name).to_lower()
		if "roof" in nm:
			mi.material_override = roof_mat
		else:
			mi.material_override = wall_mat
	for c in node.get_children():
		_apply_material_recursive(c, wall_mat, roof_mat)

# 回退：模型缺失时仍用程序化小木屋，保证房屋可见可交互
func _build_fallback_hut() -> void:
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4.0, 2.6, 3.4)
	body.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WOOD_COLOR
	body.material_override = mat
	body.position.y = 1.3
	add_child(body)
	var roof := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.0
	rm.bottom_radius = 3.4
	rm.height = 1.8
	rm.radial_segments = 4
	roof.mesh = rm
	roof.material_override = mat
	roof.rotation.y = PI / 4
	roof.position.y = 3.5
	add_child(roof)

func _build_collision() -> void:
	# 改用薄地面碰撞：仅保留一层地面高度，墙体不再挡人，
	# 玩家可走到门口/进屋（解决"门进不去"）。整块实心盒会让门被挡死。
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.extents = Vector3(4.0 * HOUSE_SCALE, 0.2, 4.6 * HOUSE_SCALE)
	col.shape = bs
	col.position.y = 0.1
	add_child(col)

func interact(_player) -> void:
	# 钻进房子睡到天亮（DayNightCycle 负责快进时间 + 醒来恢复状态）
	DayNightCycle.sleep_until_dawn()
