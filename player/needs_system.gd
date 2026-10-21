extends Node
## 需求系统（Layer 1 核心逻辑）：饥饿/生命/精神 三值随时间衰减。
## 饥饿归零 -> 渐进掉血（不秒死，反模式已规避）。饱食缓慢回血。
## 通过 EventBus.needs_changed 广播，HUD 只读它；其它块用 apply_food() 回值。

@export var max_hunger := 100.0
@export var max_health := 100.0
@export var max_sanity := 100.0

var hunger := 100.0
var health := 100.0
var sanity := 100.0
var temperature := 36.0
var night_sanity_mult := 1.0      # 技能「夜行者的心」可降低夜间精神衰减

@export var hunger_rate := 0.15         # 每秒（步行约 11 分钟饿空；冲刺 1.8×≈6 分钟。原 0.8 太快，约 2 分钟就空）
@export var sanity_rate := 0.15
@export var starve_damage := 3.0        # 饥饿时每秒掉血
@export var regen_rate := 0.3           # 饱食时每秒回血

var save_id := "needs"

func _ready() -> void:
	EventBus.player_damaged.connect(_on_damaged)

## 敌人攻击玩家：直接扣血（与饥饿掉血走同一 health 字段，HUD 通过 needs_changed 统一刷新）。
func _on_damaged(amount: float) -> void:
	health = max(0.0, health - amount)
	_emit()

func _process(delta: float) -> void:
	var rate := hunger_rate
	var p := get_parent()
	if p and "is_sprinting" in p and p.is_sprinting:
		rate *= 1.8
	hunger = max(0.0, hunger - rate * delta)
	# 夜间(18:00-6:00)精神衰减加速；技能可降低该系数
	var sr := sanity_rate
	var t01: float = GameManager.time_of_day
	if t01 > 0.75 or t01 < 0.25:
		sr *= 3.0 * night_sanity_mult
	sanity = clamp(sanity - sr * delta, 0.0, max_sanity)

	if hunger <= 0.0:
		health = max(0.0, health - starve_damage * delta)
	else:
		health = min(max_health, health + regen_rate * delta)

	_emit()
	if health <= 0.0 and not GameManager.player_dead:
		EventBus.player_died.emit()

func _emit() -> void:
	EventBus.needs_changed.emit("hunger", hunger / max_hunger)
	EventBus.needs_changed.emit("health", health / max_health)
	EventBus.needs_changed.emit("sanity", sanity / max_sanity)

func apply_food(h: float, s: float) -> void:
	hunger = clamp(hunger + h, 0.0, max_hunger)
	sanity = clamp(sanity + s, 0.0, max_sanity)
	_emit()

## 通用消耗品效果应用（正=恢复，负=扣）。由 Inventory/玩家进食、营火取暖等调用。
func apply_effects(health_change: float, hunger_change: float, sanity_change: float) -> void:
	health = clamp(health + health_change, 0.0, max_health)
	hunger = clamp(hunger + hunger_change, 0.0, max_hunger)
	sanity = clamp(sanity + sanity_change, 0.0, max_sanity)
	_emit()

## 死亡复活：回满血、精神，饥饿略降（见 GameManager._respawn_player）。
func respawn() -> void:
	health = max_health
	hunger = max_hunger * 0.6
	sanity = max_sanity * 0.6
	_emit()

func save() -> Dictionary:
	return {hunger = hunger, health = health, sanity = sanity, temperature = temperature}

func load(d: Dictionary) -> void:
	hunger = d.get("hunger", hunger)
	health = d.get("health", health)
	sanity = d.get("sanity", sanity)
	temperature = d.get("temperature", temperature)
