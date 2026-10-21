extends Node
## 人类伙伴队伍管理（Autoload: PartyManager）。
## 招募门控（GATING_ENABLED=true）：开局不自动生成任何伙伴（全部处于未招募状态）。
## 招募路径（均需女主好感满）：
##   1) 手动招募：靠近女主按 E -> 交互菜单出现「召唤 XXX」，点选即招入队（消耗好感、清零）。
##   2) 自动感召：女主好感+心情双满 -> 次日随机感召一位尚未出现过的伙伴（_on_day，每人仅一次）。
## 阵亡伙伴的复活同样走女主交互菜单（「复活 XXX」，消耗好感）。

const SCRIPT := "res://npc/human_companion.gd"
const PARTNER_IDS := ["maria", "erika", "arissa", "kachujin", "ch46"]

var GATING_ENABLED := true
var save_id := "party"

var _list: Array = []
var _next_idx := 0
var _unlocked: Dictionary = {}   # id -> true（已解锁可选 / 可召唤）
var _appeared: Dictionary = {}   # id -> true（已在世界中出现过）
var _recruited: Dictionary = {}  # id -> true（已加入队伍，无论存活/阵亡）
var _pending_dead: Array = []    # 读档时待恢复的阵亡 id

func _ready() -> void:
	EventBus.day_changed.connect(_on_day)
	if SaveManager != null:
		SaveManager.register(self)
	call_deferred("_spawn_all")

func _spawn_all() -> void:
	for id in PARTNER_IDS:
		if GATING_ENABLED and not _unlocked.get(id, false):
			continue
		if _recruited.has(id):
			continue
		_spawn(id)
		if _recruited.has(id):
			EventBus.toast.emit("%s 加入了队伍！" % _partner_name(id))
	# 首帧可能 autoload 早于场景：世界/玩家都还没就绪时不重复生成，稍后重试
	if _list.is_empty() and GameManager.world == null and GameManager.player == null:
		call_deferred("_spawn_all")

func _spawn(id: String) -> void:
	var def: Dictionary = CharacterRegistry.find_by_id(id)
	if def.is_empty():
		return
	var c := CharacterBody3D.new()
	c.set_script(load(SCRIPT))
	c.name = "Companion_%s_%d" % [id, _next_idx]
	_next_idx += 1
	c.set("char_id", id)
	c.set("char_name", def.get("name", id))
	var root: Node = GameManager.world if GameManager.world != null else get_tree().current_scene
	if root != null:
		root.add_child(c)
		c.global_position = _spawn_position()
		_recruited[id] = true

func _spawn_position() -> Vector3:
	var base: Vector3
	if GameManager.player != null:
		base = GameManager.player.global_position
	else:
		var cc: Vector2 = GameManager.camp_center
		base = Vector3(cc.x, 0.0, cc.y)
	var ang := randf() * TAU
	var r := 3.0 + randf() * 3.0
	var p := base + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
	var gy: float = 0.0
	if GameManager.world != null and GameManager.world.has_method("get_ground_height"):
		gy = float(GameManager.world.call("get_ground_height", p.x, p.z))
	return Vector3(p.x, gy + 0.2, p.z)

func register(c: Node) -> void:
	if not _list.has(c):
		_list.append(c)

## Object.get() 只接受一个参数，故用这个带默认值的读取助手。
func _cstr(n: Node, key: String, default_value := "") -> String:
	var v = n.get(key)
	if v == null:
		return default_value
	return str(v)

## 男主 T 键全员广播：每位伙伴都回「好的Daddy」。
func command_all(mode: String) -> void:
	var names: PackedStringArray = []
	for c in _list:
		if is_instance_valid(c) and not bool(c.get("is_dead")):
			c.command(mode)
			names.append(str(_cstr(c, "char_name", "伙伴")))
	if not names.is_empty():
		EventBus.toast.emit("%s：好的Daddy" % "、".join(names))

## 走近 E 键单人下指令：仅该伙伴回「好的Daddy」。
func command_one(c: Node, mode: String) -> void:
	if c == null or not is_instance_valid(c):
		return
	c.command(mode)
	EventBus.toast.emit("%s：好的Daddy" % str(_cstr(c, "char_name", "伙伴")))

## 「召集她们几个回来」：全员召回玩家身边待命。
func summon_all() -> void:
	command_all("return")

func nearest_companion(pos: Vector3, max_dist: float) -> Node:
	var best: Node = null
	var best_d := max_dist
	for c in _list:
		if not is_instance_valid(c):
			continue
		if bool(c.get("is_dead")):
			continue   # 阵亡躺营地的不响应 E 互动
		var d := pos.distance_to(c.global_position)
		if d < best_d:
			best_d = d
			best = c
	return best

func get_status() -> Dictionary:
	var s := {"total": 0, "follow": 0, "fight": 0, "gather": 0, "idle": 0, "dead": 0}
	for c in _list:
		if not is_instance_valid(c):
			continue
		s["total"] += 1
		var m: String = str(_cstr(c, "command_mode", "idle"))
		if m == "dead":
			s["dead"] += 1
		elif s.has(m):
			s[m] += 1
	return s

## 是否已招满全部 5 位伙伴（无论存活/阵亡都算「招过」）。
func all_recruited() -> bool:
	return _recruited.size() >= PARTNER_IDS.size()

## 某伙伴是否已加入队伍（已招募/召唤）。供「换角色」菜单判定：
## 未招募的伙伴不可在换角色里切换到。
func is_recruited(id: String) -> bool:
	return _recruited.has(id)

## 尚未加入队伍、可被召唤的伙伴 id。
func recruititable_ids() -> Array:
	var out: Array = []
	for id in PARTNER_IDS:
		if not _recruited.has(id):
			out.append(id)
	return out

## 当前阵亡（躺着）的伙伴 id。
func dead_ids() -> Array:
	var out: Array = []
	for c in _list:
		if is_instance_valid(c) and bool(c.get("is_dead")):
			out.append(str(_cstr(c, "char_id", "")))
	return out

func companion_by_id(id: String) -> Node:
	for c in _list:
		if is_instance_valid(c) and str(_cstr(c, "char_id", "")) == id:
			return c
	return null

func get_companions() -> Array:
	return _list

func _partner_name(id: String) -> String:
	var def: Dictionary = CharacterRegistry.find_by_id(id)
	if def.is_empty():
		return id
	return str(def.get("name", id))

## 女主好感满后召唤一位尚未加入的伙伴（消耗好感）。
func summon_new(id: String) -> void:
	if not PARTNER_IDS.has(id):
		return
	if _recruited.has(id):
		EventBus.toast.emit("%s 已经在队伍里了" % _partner_name(id))
		return
	_spawn(id)
	if _recruited.has(id):
		EventBus.toast.emit("%s 被感召而来，加入了队伍！" % _partner_name(id))
		RelationshipManager.affection = 0.0
		EventBus.affection_changed.emit(0.0)

## 女主好感满后复活一位阵亡的伙伴（消耗好感）；复活后恢复行动、可被召集/互动。
func revive_by_id(id: String) -> void:
	var c := companion_by_id(id)
	if c == null:
		return
	if not bool(c.get("is_dead")):
		EventBus.toast.emit("%s 并未倒下" % _partner_name(id))
		return
	c.revive_now()
	EventBus.toast.emit("%s 苏醒了，重新站了起来！" % _partner_name(id))
	RelationshipManager.affection = 0.0
	EventBus.affection_changed.emit(0.0)

## 次日检查：女主好感/心情满 -> 随机召唤一位尚未出现过的伙伴（GATING_ENABLED=true 时生效）。
func _on_day(_day: int) -> void:
	if not GATING_ENABLED:
		return
	if RelationshipManager.affection >= RelationshipManager.AFF_MAX \
		and RelationshipManager.mood >= RelationshipManager.MOOD_MAX:
		var cand: Array = []
		for id in PARTNER_IDS:
			if not _appeared.get(id, false):
				cand.append(id)
		if not cand.is_empty():
			var pick: String = cand[randi() % cand.size()]
			_appeared[pick] = true
			_unlocked[pick] = true
			_spawn(pick)
			EventBus.toast.emit("一位新的伙伴加入了队伍……")

# =========================================================
# 存档：记住每位伙伴当前指令（gating 集合一并持久化）
# =========================================================
func save() -> Dictionary:
	var modes := {}
	for c in _list:
		if is_instance_valid(c):
			modes[str(_cstr(c, "char_id", ""))] = str(_cstr(c, "command_mode", "idle"))
	return {"modes": modes, "unlocked": _unlocked, "appeared": _appeared, "recruited": _recruited, "dead": dead_ids()}

func load(data: Dictionary) -> void:
	if data.has("unlocked"):
		_unlocked = data["unlocked"]
	if data.has("appeared"):
		_appeared = data["appeared"]
	if data.has("recruited"):
		_recruited = data["recruited"]
	if data.has("modes"):
		var modes: Dictionary = data["modes"]
		call_deferred("_apply_modes", modes)
	if data.has("dead"):
		_pending_dead = data["dead"]
		call_deferred("_apply_dead")

## 读档后恢复阵亡状态（此时 _list 已由 _spawn_all 填充）。
func _apply_dead() -> void:
	for id in _pending_dead:
		var c := companion_by_id(id)
		if c != null and not bool(c.get("is_dead")):
			c.set_dead_state()
	_pending_dead = []

func _apply_modes(modes: Dictionary) -> void:
	for c in _list:
		if not is_instance_valid(c):
			continue
		var id: String = str(_cstr(c, "char_id", ""))
		if modes.has(id):
			c.command(modes[id])
