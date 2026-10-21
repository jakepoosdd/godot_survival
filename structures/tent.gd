extends "res://inventory/interactable.gd"
## 帐篷（可放置结构）。interact 时进帐休息，恢复较多生命与精神。视觉用基础图元拼（无需外部网格）。

func _ready() -> void:
	prompt = "帐篷：休息 (E)"
	_build_visual()
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.extents = Vector3(1.1, 0.8, 1.1)
	col.shape = bs
	col.position.y = 0.8
	add_child(col)

func _build_visual() -> void:
	# 帐篷主体（圆锥）
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 1.2
	cm.height = 1.6
	body.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.45, 0.32)
	body.material_override = m
	body.position.y = 0.8
	add_child(body)
	# 入口（暗色三角示意）
	var door := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.0
	dm.bottom_radius = 0.35
	dm.height = 0.9
	door.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.15, 0.1, 0.06)
	door.material_override = dmat
	door.position = Vector3(0, 0.45, 1.05)
	door.rotation.x = -0.25
	add_child(door)
	# 支撑杆
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.04
	pm.bottom_radius = 0.04
	pm.height = 1.8
	pole.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.25, 0.16, 0.09)
	pole.material_override = pmat
	pole.position.y = 0.9
	add_child(pole)

func interact(_player) -> void:
	# 钻进帐篷睡到天亮（DayNightCycle 负责快进时间 + 醒来恢复状态）
	DayNightCycle.sleep_until_dawn()
