extends "res://inventory/interactable.gd"
## 营地仓库（储物箱）。按 E 打开 CampStorage 存储面板，作为跨负重中转与长期存储。
## 两处复用同一场景：① world.gd 在营地预摆放一个；② 玩家制作后在建造模式(B)放置更多。
## 交互识别走 interaction_system 的 has_method("interact")，无需注册。

const CHEST_PATH := "res://assets/fantasy_props/Chest_Wood.gltf"

func _ready() -> void:
	prompt = "营地仓库（按 E 存取）"
	_build_visual()
	_build_collision()

## 视觉：优先用 Fantasy Props 的木箱（约 1.14 × 0.69 × 0.75 m，底面在 y=0）；素材缺失时退回程序化木箱。
func _build_visual() -> void:
	var res = load(CHEST_PATH)
	if res is PackedScene:
		var m := (res as PackedScene).instantiate() as Node3D
		if m != null:
			add_child(m)
			return
	_build_fallback_box()

func _build_fallback_box() -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.65, 0.6)
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.28, 0.15)
	mat.roughness = 0.9
	m.material_override = mat
	m.position.y = 0.33
	add_child(m)

## 交互射线与玩家移动都要用的碰撞体（贴合木箱足迹）。
func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.extents = Vector3(0.6, 0.35, 0.4)
	col.shape = bs
	col.position = Vector3(0, 0.35, 0)
	add_child(col)

func interact(_player) -> void:
	EventBus.camp_storage_requested.emit()
