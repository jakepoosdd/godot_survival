extends Node
## 岛灵伙伴管理（Autoload: Companions）。
## 监听 EventBus.companion_bred，在营地附近生成对应类型的 SpiritCompanion，并维护数量统计。

const SCRIPT := "res://npc/spirit_companion.gd"

var _list: Array = []          # 存活伙伴实例
var _next_idx := 0

func _ready() -> void:
	EventBus.companion_bred.connect(_on_bred)

## 由 spirit_companion.gd 在 _ready 时调用，登记自身。
func register(c: Node) -> void:
	if not _list.has(c):
		_list.append(c)

func _on_bred(type: String) -> void:
	_spawn(type)

func _spawn(type: String) -> void:
	var sc := load(SCRIPT)
	if sc == null:
		return
	var c := CharacterBody3D.new()
	c.name = "Spirit_%s_%d" % [type, _next_idx]
	_next_idx += 1
	c.set_script(sc)
	c.set("companion_type", type)
	c.set("companion_name", _type_name(type))
	var pos := _camp_spawn_position()
	c.global_position = pos
	var root: Node = GameManager.world if GameManager.world != null else get_tree().current_scene
	if root != null:
		root.add_child(c)
	EventBus.toast.emit("%s 在营地旁显形了！" % c.get("companion_name"))

func _type_name(type: String) -> String:
	match type:
		"fighter": return "战斗型岛灵"
		"versatile": return "全能型岛灵"
		_: return "采集型岛灵"

## 营地附近随机点（保证在营地空地范围内）。
func _camp_spawn_position() -> Vector3:
	var c: Vector2 = GameManager.camp_center
	var ang := randf() * TAU
	var r := 6.0 + randf() * 8.0
	var x := c.x + cos(ang) * r
	var z := c.y + sin(ang) * r
	var gy: float = 0.0
	if GameManager.world != null and GameManager.world.has_method("get_ground_height"):
		gy = float(GameManager.world.call("get_ground_height", x, z))
	return Vector3(x, gy + 0.2, z)

func alive() -> int:
	var n := 0
	for c in _list:
		if is_instance_valid(c):
			n += 1
	return n

func count_by_type(type: String) -> int:
	var n := 0
	for c in _list:
		if is_instance_valid(c) and c.get("companion_type") == type:
			n += 1
	return n

func get_status() -> Dictionary:
	return {
		"total": alive(),
		"gather": count_by_type("gather"),
		"fighter": count_by_type("fighter"),
		"versatile": count_by_type("versatile"),
	}
