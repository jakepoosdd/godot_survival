extends Node
## 经验与等级（Autoload: XP）。经验来自击杀动物/完成任务；等级随累计总经验按阈值自动提升。
## 可用经验(available_xp)用于解锁技能；花掉后 total 不变、available 减少。

var total_xp := 0
var available_xp := 0
var level := 1
var xp_for_next := 0

const BASE_XP := 80       # 第 1->2 级所需
const MULT := 1.35        # 每级递增系数
const MAX_LEVEL := 50

func _ready() -> void:
	EventBus.xp_awarded.connect(award_xp)
	_recalc_level()
	call_deferred("_emit")   # 延后到主场景/HUD _ready 之后，确保对方已连接

func award_xp(amount: int) -> void:
	if amount <= 0:
		return
	total_xp += amount
	available_xp += amount
	var old := level
	_recalc_level()
	_emit()
	if level > old:
		EventBus.leveled_up.emit(level)

func spend_xp(amount: int) -> bool:
	if available_xp >= amount:
		available_xp -= amount
		_emit()
		return true
	return false

func _emit() -> void:
	EventBus.xp_changed.emit(total_xp, available_xp, level, _xp_into, _xp_needed)

func _recalc_level() -> void:
	var lvl := 1
	var need := BASE_XP
	var acc := 0
	while acc + need <= total_xp and lvl < MAX_LEVEL:
		acc += need
		lvl += 1
		need = int(BASE_XP * pow(MULT, lvl - 1))
	if lvl != level:
		level = lvl
	_xp_needed = need
	_xp_into = total_xp - acc
	if lvl >= MAX_LEVEL:
		_xp_needed = 0
		_xp_into = 0

var _xp_into := 0
var _xp_needed := BASE_XP

## 重开游戏用：清零经验/等级并重新广播。
func reset() -> void:
	total_xp = 0
	available_xp = 0
	level = 1
	_recalc_level()
	_emit()
