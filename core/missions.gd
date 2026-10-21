extends Node
## 任务系统（Autoload: Missions）。数据驱动的任务树：每个任务含多个目标（collect/craft/build/kill/cook/eat），
## 满足全部前置（prereq）才激活；所有目标完成发放 XP 奖励并解锁后续任务。
## 监听 EventBus 现有信号推进进度，不持有任何节点引用，保持解耦。

signal missions_changed()
signal mission_completed(key: String, xp: int)

# 目标类型（用字符串便于跨脚本比较）
#   collect: {item, amount}       背包累计该物品数量 >= amount
#   craft:   {item}               制作出该物品（recipe_crafted）
#   build:   {item}               放置该结构（structure_placed）
#   kill:    {amount}             击杀动物 >= amount
#   cook:    {item}               烹饪出该食物（food_cooked）
#   eat:     {item}               进食该食物（food_eaten）

var _missions: Array = []
var _active: Dictionary = {}      # key -> {"def":Dictionary, "prog":Array, "done":bool}
var _completed: Array = []

func _ready() -> void:
	_build_missions()
	EventBus.inventory_changed.connect(_on_inv)
	EventBus.recipe_crafted.connect(_on_craft)
	EventBus.structure_placed.connect(_on_build)
	EventBus.creature_died.connect(_on_kill)
	EventBus.food_cooked.connect(_on_cook)
	EventBus.food_eaten.connect(_on_eat)
	EventBus.xp_changed.connect(_on_xp)
	_activate_initial()

func _build_missions() -> void:
	_missions = [
		{"key":"t1", "name":"拾荒者", "desc":"收集 5 树枝 + 3 石头", "cat":"主线", "xp":20, "prereq":[],
		 "objs":[{"type":"collect", "item":"stick", "amount":5}, {"type":"collect", "item":"stone", "amount":3}]},
		{"key":"t2", "name":"工匠学徒", "desc":"制作一把斧头", "cat":"主线", "xp":25, "prereq":["t1"],
		 "objs":[{"type":"craft", "item":"axe"}]},
		{"key":"t3", "name":"安营扎寨", "desc":"放置一个营火", "cat":"主线", "xp":30, "prereq":["t2"],
		 "objs":[{"type":"build", "item":"campfire"}]},
		{"key":"t4", "name":"饱餐一顿", "desc":"烹饪并进食一份熟食", "cat":"主线", "xp":25, "prereq":["t3"],
		 "objs":[{"type":"cook", "item":"cookedmeat"}, {"type":"eat", "item":"cookedmeat"}]},
		{"key":"t5", "name":"猎人", "desc":"猎杀 1 只动物", "cat":"主线", "xp":40, "prereq":["t3"],
		 "objs":[{"type":"kill", "amount":1}]},
		{"key":"t6", "name":"建造师", "desc":"放置一个帐篷和一座房子", "cat":"支线", "xp":35, "prereq":["t3"],
		 "objs":[{"type":"build", "item":"tent"}, {"type":"build", "item":"house"}]},
		{"key":"t7", "name":"拓荒者", "desc":"收集 10 木材 + 5 燧石", "cat":"支线", "xp":30, "prereq":["t2"],
		 "objs":[{"type":"collect", "item":"log", "amount":10}, {"type":"collect", "item":"flintstone", "amount":5}]},
		{"key":"t8", "name":"工具大师", "desc":"制作镐、镰刀、铲子", "cat":"支线", "xp":40, "prereq":["t2"],
		 "objs":[{"type":"craft", "item":"pickaxe"}, {"type":"craft", "item":"sickle"}, {"type":"craft", "item":"shovel"}]},
		{"key":"t9", "name":"生存专家", "desc":"累计猎杀 3 只动物", "cat":"主线", "xp":60, "prereq":["t5"],
		 "objs":[{"type":"kill", "amount":3}]},
		{"key":"t10", "name":"巨兽猎人", "desc":"击败 1 只熊", "cat":"支线", "xp":70, "prereq":["t5"],
		 "objs":[{"type":"kill", "species":"Bear", "amount":1}]},
		{"key":"t11", "name":"驯兽师", "desc":"累计猎杀 5 只动物", "cat":"支线", "xp":50, "prereq":["t9"],
		 "objs":[{"type":"kill", "amount":5}]},
		{"key":"t12", "name":"强者之路", "desc":"达到 5 级", "cat":"主线", "xp":80, "prereq":["t4"],
		 "objs":[{"type":"level", "amount":5}]},
	]

func _activate_initial() -> void:
	for m in _missions:
		if _can_activate(m):
			_activate(m)

func _can_activate(m: Dictionary) -> bool:
	for p in m["prereq"]:
		if not (p in _completed):
			return false
	return true

func _activate(m: Dictionary) -> void:
	var key: String = m["key"]
	if _active.has(key) or key in _completed:
		return
	var prog: Array = []
	for _o in m["objs"]:
		prog.append(0)
	_active[key] = {"def": m, "prog": prog, "done": false}
	# 激活时先按当前状态对齐一次（例如背包里已有材料 / 已达等级）
	_sync_collect(key)
	_sync_level(key)
	_check_complete(key)
	missions_changed.emit()

func _sync_collect(key: String) -> void:
	if not _active.has(key):
		return
	var a: Dictionary = _active[key]
	var objs: Array = a["def"]["objs"]
	var changed := false
	for i in objs.size():
		var o: Dictionary = objs[i]
		if o["type"] == "collect":
			var cur: int = Inventory.count(o["item"])
			var amt: int = int(o["amount"])
			var v: int = mini(cur, amt)
			if int(a["prog"][i]) != v:
				a["prog"][i] = v
				changed = true
	if changed:
		_check_complete(key)

func _set_done(key: String, idx: int) -> void:
	if not _active.has(key):
		return
	var a: Dictionary = _active[key]
	if int(a["prog"][idx]) >= 1:
		return
	a["prog"][idx] = 1
	_check_complete(key)

func _inc(key: String, idx: int, amount: int) -> void:
	if not _active.has(key):
		return
	var a: Dictionary = _active[key]
	var o: Dictionary = a["def"]["objs"][idx]
	var cur: int = int(a["prog"][idx]) + 1
	a["prog"][idx] = mini(cur, int(o["amount"]))
	_check_complete(key)

func _obj_done(o: Dictionary, prog_i: int) -> bool:
	if o["type"] == "collect" or o["type"] == "kill":
		return prog_i >= int(o["amount"])
	if o["type"] == "level":
		return prog_i >= 1
	return prog_i >= 1

func _check_complete(key: String) -> void:
	if not _active.has(key):
		return
	var a: Dictionary = _active[key]
	if a["done"]:
		return
	var objs: Array = a["def"]["objs"]
	var prog: Array = a["prog"]
	var all := true
	for i in objs.size():
		if not _obj_done(objs[i], int(prog[i])):
			all = false
			break
	if all:
		_complete(key)

func _complete(key: String) -> void:
	if not _active.has(key):
		return
	var a: Dictionary = _active[key]
	a["done"] = true
	var def: Dictionary = a["def"]
	var xp: int = int(def["xp"])
	_completed.append(key)
	_active.erase(key)
	EventBus.xp_awarded.emit(xp)
	_activate_new()
	missions_changed.emit()
	mission_completed.emit(key, xp)

func _activate_new() -> void:
	for m in _missions:
		if not _active.has(m["key"]) and not (m["key"] in _completed):
			if _can_activate(m):
				_activate(m)

# ---- 事件处理 ----
func _on_inv() -> void:
	for key in _active.keys():
		_sync_collect(key)

func _on_craft(item_id: String) -> void:
	for key in _active.keys():
		var objs: Array = _active[key]["def"]["objs"]
		for i in objs.size():
			if objs[i]["type"] == "craft" and objs[i]["item"] == item_id:
				_set_done(key, i)

func _on_build(item_id: String, _at: Vector3 = Vector3.ZERO) -> void:
	for key in _active.keys():
		var objs: Array = _active[key]["def"]["objs"]
		for i in objs.size():
			if objs[i]["type"] == "build" and objs[i]["item"] == item_id:
				_set_done(key, i)

func _on_kill(c, _d) -> void:
	for key in _active.keys():
		var objs: Array = _active[key]["def"]["objs"]
		for i in objs.size():
			if objs[i]["type"] == "kill":
				if objs[i].has("species"):
					var sp: String = c.get("species", "") if c != null else ""
					if sp != objs[i]["species"]:
						continue
				_inc(key, i, 1)

func _on_xp(_total: int, _avail: int, _level: int, _into: int, _need: int) -> void:
	for key in _active.keys():
		_sync_level(key)

## 等级类目标：XP.level 达到要求即视为完成。
func _sync_level(key: String) -> void:
	if not _active.has(key):
		return
	var a: Dictionary = _active[key]
	var objs: Array = a["def"]["objs"]
	var changed := false
	for i in objs.size():
		var o: Dictionary = objs[i]
		if o["type"] == "level":
			var done := 0
			if XP.level >= int(o["amount"]):
				done = 1
			if int(a["prog"][i]) != done:
				a["prog"][i] = done
				changed = true
	if changed:
		_check_complete(key)

func _on_cook(item_id: String) -> void:
	for key in _active.keys():
		var objs: Array = _active[key]["def"]["objs"]
		for i in objs.size():
			if objs[i]["type"] == "cook" and objs[i]["item"] == item_id:
				_set_done(key, i)

func _on_eat(item_id: String) -> void:
	for key in _active.keys():
		var objs: Array = _active[key]["def"]["objs"]
		for i in objs.size():
			if objs[i]["type"] == "eat" and objs[i]["item"] == item_id:
				_set_done(key, i)

# ---- 给 UI 用 ----
func get_active_list() -> Array:
	var out: Array = []
	for key in _active.keys():
		var a: Dictionary = _active[key]
		out.append({
			"key": key,
			"name": a["def"]["name"],
			"desc": a["def"]["desc"],
			"cat": a["def"]["cat"],
			"xp": int(a["def"]["xp"]),
			"objs": a["def"]["objs"],
			"prog": a["prog"]
		})
	return out

func get_mission_def(key: String) -> Dictionary:
	for m in _missions:
		if m["key"] == key:
			return m
	return {}

func is_completed(key: String) -> bool:
	return key in _completed

func is_active(key: String) -> bool:
	return _active.has(key)
