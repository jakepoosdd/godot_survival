extends Node
## 成就（Autoload: Achievements）。监听既有事件信号，达成条件即解锁并提示。

const DEFS := [
	{"id": "first_kill", "name": "初战告捷", "desc": "击杀第一头野兽"},
	{"id": "level5", "name": "渐入佳境", "desc": "达到 5 级"},
	{"id": "builder", "name": "筑巢者", "desc": "建造第一个结构"},
	{"id": "cook", "name": "炊烟袅袅", "desc": "烹饪第一道食物"},
	{"id": "trader", "name": "以物易物", "desc": "完成第一笔交易"},
	{"id": "survivor3", "name": "三日之约", "desc": "活过第 3 天"},
	{"id": "collector", "name": "拾荒达人", "desc": "采集 50 次"},
]
var unlocked: Dictionary = {}
var _harvest_count := 0
signal achievement_unlocked(id: String, name: String, desc: String)

func _ready() -> void:
	EventBus.creature_died.connect(func(_c, _d): unlock("first_kill"))
	EventBus.leveled_up.connect(func(lv): if lv >= 5: unlock("level5"))
	EventBus.structure_placed.connect(func(_s, _at): unlock("builder"))
	EventBus.food_cooked.connect(func(_i): unlock("cook"))
	EventBus.trade_made.connect(func(): unlock("trader"))
	EventBus.resource_harvested.connect(func(_s, _d):
		_harvest_count += 1
		if _harvest_count >= 50:
			unlock("collector")
	)
	EventBus.day_changed.connect(func(d): if d >= 3: unlock("survivor3"))

func unlock(id: String) -> void:
	if unlocked.get(id, false):
		return
	var def: Dictionary = _def(id)
	if def.is_empty():
		return
	unlocked[id] = true
	achievement_unlocked.emit(id, def["name"], def["desc"])
	EventBus.achievement_unlocked.emit(id, def["name"], def["desc"])
	EventBus.toast.emit("成就解锁：%s" % def["name"])

func _def(id: String) -> Dictionary:
	for d in DEFS:
		if d["id"] == id:
			return d
	return {}

func is_unlocked(id: String) -> bool:
	return unlocked.get(id, false)

func get_defs() -> Array:
	return DEFS
