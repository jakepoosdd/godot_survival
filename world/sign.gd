extends "res://inventory/interactable.gd"
## 漂流木牌：交互触发一段对话（演示对话系统）。视觉用基础图元拼。

func _ready() -> void:
	prompt = "木牌：查看 (E)"
	_build_visual()
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.extents = Vector3(0.3, 0.6, 0.1)
	col.shape = bs
	col.position.y = 0.6
	add_child(col)

func _build_visual() -> void:
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.06
	pm.bottom_radius = 0.06
	pm.height = 1.2
	post.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.2, 0.1)
	post.material_override = m
	post.position.y = 0.6
	add_child(post)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.5, 0.08)
	board.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.5, 0.4, 0.25)
	board.material_override = bmat
	board.position.y = 1.1
	add_child(board)

func interact(_player) -> void:
	if Dialogue.active:
		return
	Dialogue.start("漂流木牌", [
		"「如果你读到这块牌子，说明你活下来了。」",
		"「白天采集、夜晚警惕——狼群会在黑暗里出没。」",
		"「按 L 用经验解锁技能，按 U 查看任务；活下去，就是胜利。」"
	])
