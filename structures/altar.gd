extends Node3D
class_name Altar
## 岛心祭坛（终局交互点）。玩家满足反攻条件后按 E 发起讨伐，刷出 Boss。
## 视觉由 world.gd 的 _add_altar 用基础图元拼出；本脚本只负责碰撞 + 交互。

var prompt := "祭坛（被黑雾封锁）"

func _ready() -> void:
	add_to_group("altar")
	_build_collision()
	_refresh_prompt()
	EventBus.nest_available.connect(_refresh_prompt)
	EventBus.nest_cleared.connect(_refresh_prompt)

func _build_collision() -> void:
	var sb := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.height = 3.0
	cyl.radius = 2.5
	col.shape = cyl
	col.position = Vector3(0, 1.5, 0)
	sb.add_child(col)
	add_child(sb)

func interact(_p) -> void:
	if NestRaid.cleared:
		EventBus.toast.emit("祭坛已碎，雾早已散去。")
		return
	if not NestRaid.available:
		EventBus.toast.emit("祭坛被黑雾环绕——还需更多伙伴或更强的实力才能撼动。")
		return
	NestRaid.start_assault()

func _refresh_prompt() -> void:
	if NestRaid.cleared:
		prompt = "祭坛（已碎）"
	elif NestRaid.available:
		prompt = "祭坛（按 E 讨伐岛心首领）"
	else:
		prompt = "祭坛（被黑雾封锁）"
