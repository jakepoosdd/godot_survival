extends "res://inventory/interactable.gd"
## 公告板：交互打开公告列表（EventBus.bulletin_opened）。视觉用基础图元拼。

func _ready() -> void:
	prompt = "公告板：查看 (E)"
	_build_visual()
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.extents = Vector3(0.6, 1.0, 0.2)
	col.shape = bs
	col.position.y = 1.0
	add_child(col)

func _build_visual() -> void:
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.08
	pm.bottom_radius = 0.08
	pm.height = 2.0
	post.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.2, 0.1)
	post.material_override = m
	post.position.y = 1.0
	add_child(post)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4, 1.0, 0.1)
	board.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.85, 0.8, 0.6)
	board.material_override = bmat
	board.position.y = 1.9
	add_child(board)

func interact(_player) -> void:
	if Dialogue.active:
		return
	EventBus.bulletin_opened.emit()
