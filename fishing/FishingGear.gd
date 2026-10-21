extends Node
## 钓鱼装备（Autoload: FishingGear）。对标 Tidewater 的 gear（线/轮/竿/油箱/探鱼器/夜钓灯）。
## 各级影响：咬钩率、可钓体型、断线张力阈值、收线速度、冷藏容量、夜钓许可。
## 升级通过 Economy 扣金币，并接入 SaveManager 存档。

const MAX_LV := 3

# 各装备等级（0=初始）
var rod_level: int = 0
var reel_level: int = 0
var line_level: int = 0
var hold_level: int = 0
var fishfinder_level: int = 0
var nightlight_level: int = 0

# 升级花费表（到达下一级的花费；已满级为 -1）
const COSTS := {
	"rod":        [60, 140, 300],
	"reel":       [50, 120, 260],
	"line":       [40, 100, 220],
	"hold":       [30, 70, 150],
	"fishfinder": [90, 200, -1],
	"nightlight": [120, -1, -1],
}

func _ready() -> void:
	SaveManager.register(self)

# ---------------- 修正系数（供 FishingSystem 使用） ----------------
func bite_rate() -> float:
	return 1.0 + 0.15 * float(line_level) + 0.10 * float(fishfinder_level)

func size_bonus() -> float:
	return 1.0 + 0.05 * float(rod_level)

# 断线张力阈值：必须落在 UI 红色警戒区(>0.80)的顶部，
# 让玩家"先看到红、再断线"，而不是在绿区里莫名断掉。
# 更好的线等级 → 阈值更高 → 更不容易断。
func break_threshold() -> float:
	return 0.92 + 0.02 * float(line_level)

func reel_power() -> float:
	return 0.90 + 0.15 * float(reel_level)

func tension_assist() -> float:
	return 1.0 - 0.10 * float(rod_level)   # 高等级竿收线时张力上升更缓

func cooler_capacity() -> int:
	return 10 + 10 * hold_level

func sees_depth() -> bool:
	return fishfinder_level >= 1

func night_fishing_allowed() -> bool:
	return nightlight_level >= 1

# ---------------- 升级 ----------------
func next_cost(kind: String) -> int:
	if not COSTS.has(kind):
		return -1
	var arr: Array = COSTS[kind]
	var lv := _lv_of(kind)
	if lv >= MAX_LV or lv >= arr.size():
		return -1
	return int(arr[lv])

func _lv_of(kind: String) -> int:
	match kind:
		"rod": return rod_level
		"reel": return reel_level
		"line": return line_level
		"hold": return hold_level
		"fishfinder": return fishfinder_level
		"nightlight": return nightlight_level
	return 0

func _set_lv(kind: String, v: int) -> void:
	match kind:
		"rod": rod_level = v
		"reel": reel_level = v
		"line": line_level = v
		"hold": hold_level = v
		"fishfinder": fishfinder_level = v
		"nightlight": nightlight_level = v

## 尝试升级某装备。成功扣钓鱼经验并返回 true（升级货币 = 钓鱼经验，不再用金币）。
func upgrade(kind: String) -> bool:
	var cost := next_cost(kind)
	if cost < 0:
		EventBus.toast.emit("该装备已满级")
		return false
	if not FishingSystem.spend_xp(cost):
		EventBus.toast.emit("钓鱼经验不足（需 %d）" % cost)
		return false
	_set_lv(kind, _lv_of(kind) + 1)
	EventBus.fishing_gear_changed.emit()
	EventBus.toast.emit("%s 升级到 Lv%d（-%d 钓鱼经验）" % [kind, _lv_of(kind), cost])
	return true

# ---------------- 存档 ----------------
func save_id() -> String:
	return "fishing_gear"

func save() -> Dictionary:
	return {
		"rod": rod_level, "reel": reel_level, "line": line_level,
		"hold": hold_level, "fishfinder": fishfinder_level, "nightlight": nightlight_level,
	}

func load(d: Dictionary) -> void:
	if d.is_empty():
		return
	rod_level = int(d.get("rod", 0))
	reel_level = int(d.get("reel", 0))
	line_level = int(d.get("line", 0))
	hold_level = int(d.get("hold", 0))
	fishfinder_level = int(d.get("fishfinder", 0))
	nightlight_level = int(d.get("nightlight", 0))
