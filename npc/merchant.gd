extends "res://inventory/interactable.gd"
## 流浪商人：交互打开商店（EventBus.shop_requested）。视觉用基础图元拼。

func _ready() -> void:
	prompt = "流浪商人：交易 (E)"
	_build_visual()
	var col := CollisionShape3D.new()
	var bs := CapsuleShape3D.new()
	bs.radius = 0.5
	bs.height = 1.6
	col.shape = bs
	col.position.y = 0.9
	add_child(col)

func _build_visual() -> void:
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.35
	bm.bottom_radius = 0.45
	bm.height = 1.4
	body.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.3, 0.5, 0.7)
	body.material_override = bmat
	body.position.y = 0.7
	add_child(body)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.28
	hm.height = 0.56
	head.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.9, 0.75, 0.6)
	head.material_override = hmat
	head.position.y = 1.6
	add_child(head)
	var signp := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(1.4, 0.6, 0.1)
	signp.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.7, 0.55, 0.2)
	signp.material_override = smat
	signp.position = Vector3(0, 2.0, -0.4)
	add_child(signp)

func interact(_player) -> void:
	if Dialogue.active:
		return
	EventBus.shop_requested.emit()
