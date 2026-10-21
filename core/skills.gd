extends Node
## 技能树（Autoload: Skills）。数据驱动：技能在 _build_skills() 里定义（id/名称/描述/花费/数值/类型）。
## 解锁：花费 available_xp，apply 效果到对应系统（生命/攻击/移速/背包/精神抗性）。
## 无 UI 依赖——HUD 用 try_unlock() + get_list() 渲染技能面板（L 键）。

signal skills_changed()

enum Type { HEALTH, ATTACK, SPEED, INV, SANITY, MATERIAL }

var skills: Array = []
var unlocked: Dictionary = {}   # id -> level(>=1 表示已解锁)
var material_mult := 1.0        # 材料消耗倍率：1.0=原价；解锁「省材料」技能后下降（crafting/building 扣料时乘此值）

func _ready() -> void:
	_build_skills()

func _build_skills() -> void:
	skills = [
		{
			"id": "vit_health", "name": "强健体魄", "desc": "最大生命 +20",
			"cost": 40, "value": 20, "type": Type.HEALTH, "unlocked": false
		},
		{
			"id": "combat_atk", "name": "利刃精通", "desc": "近战伤害 +10",
			"cost": 50, "value": 10, "type": Type.ATTACK, "unlocked": false
		},
		{
			"id": "move_spd", "name": "疾行", "desc": "移动速度 +0.8（冲刺 +1.0）",
			"cost": 40, "value": 0.8, "type": Type.SPEED, "unlocked": false
		},
		{
			"id": "pack_slot", "name": "行囊扩容", "desc": "背包 +4 格",
			"cost": 30, "value": 4, "type": Type.INV, "unlocked": false
		},
		{
			"id": "mind_resist", "name": "夜行者的心", "desc": "夜间精神衰减 -35%",
			"cost": 35, "value": 0.35, "type": Type.SANITY, "unlocked": false
		},
		{
			"id": "eff_build", "name": "高效制造", "desc": "制作与建造材料消耗 -15%",
			"cost": 35, "value": 0.15, "type": Type.MATERIAL, "unlocked": false
		},
		{
			"id": "quick_hands", "name": "快手", "desc": "制作与建造材料消耗 再 -10%",
			"cost": 30, "value": 0.10, "type": Type.MATERIAL, "unlocked": false
		},
	]

func get_list() -> Array:
	return skills

func can_unlock(id: String) -> bool:
	for s in skills:
		if s["id"] == id:
			if s["unlocked"]:
				return false
			return XP.available_xp >= int(s["cost"])
	return false

func try_unlock(id: String) -> bool:
	for s in skills:
		if s["id"] == id and not s["unlocked"]:
			var cost: int = int(s["cost"])
			if XP.spend_xp(cost):
				s["unlocked"] = true
				unlocked[id] = 1
				_apply(s)
				EventBus.skill_unlocked.emit(id)
				EventBus.toast.emit("解锁技能：%s" % s["name"])
				skills_changed.emit()
				return true
			else:
				EventBus.toast.emit("经验不足，无法解锁 %s（需 %d）" % [s["name"], cost])
				return false
	return false

func _apply(s: Dictionary) -> void:
	var val: float = float(s["value"])
	match int(s["type"]):
		Type.HEALTH:
			var ns = _needs()
			if ns != null:
				ns.max_health += val
				ns.health += val
		Type.ATTACK:
			var p = GameManager.player
			if p != null and "attack_damage" in p:
				p.attack_damage += val
		Type.SPEED:
			var p = GameManager.player
			if p != null:
				if "speed" in p:
					p.speed += val
				if "sprint_speed" in p:
					p.sprint_speed += val * 1.25
		Type.INV:
			Inventory.upgrade_slots(int(val))
		Type.SANITY:
			var ns = _needs()
			if ns != null:
				ns.night_sanity_mult = 1.0 - val
		Type.MATERIAL:
			material_mult *= (1.0 - val)

## 把「配方原始数量」换算成「实际扣除数量」：乘当前材料倍率并取整（至少 1，永不免费）。
## crafting.gd 与 building.gd 扣料时统一走这里，使「省材料」技能对两者同时生效。
func effective_cost(amount: int) -> int:
	return maxi(1, int(float(amount) * material_mult))

func _needs() -> Node:
	var p = GameManager.player
	if p == null:
		return null
	return p.get_node_or_null("NeedsSystem")
