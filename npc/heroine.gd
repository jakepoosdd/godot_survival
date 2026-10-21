extends Node3D
class_name Heroine
## 女主（固定营地 NPC）。受伤留守，不出营地。
## 靠近按 E：弹出交互菜单（交谈 / 送礼），由 HUD 渲染。
## 送礼改为「从背包（+营地仓库）里点选物品赠送」，不再自动挑最高价值物品。
## 好感/心情由 RelationshipManager 管理；繁衍（岛灵化形）也由那里判定。

const NAME := "女主"
var prompt := "按 [E] 与女主交互"

func _ready() -> void:
	add_to_group("heroine")
	add_to_group("camp_npc")
	# 碰撞体（供交互射线命中）
	var col := StaticBody3D.new()
	var shp := SphereShape3D.new()
	shp.radius = 1.3
	var cs := CollisionShape3D.new()
	cs.shape = shp
	cs.position = Vector3(0, 1.0, 0)
	col.add_child(cs)
	add_child(col)
	# 待机动画
	var ap := _find_anim()
	if ap != null and ap.has_animation("idle"):
		ap.play("idle")

# =========================================================
# 交互菜单入口（E 键由 InteractionSystem 调用）
# =========================================================
func interact(_p) -> void:
	if Dialogue.active:
		return
	EventBus.npc_menu_requested.emit(NAME, interact_options(), self)

## 交互菜单选项（HUD 按此渲染按钮）。新增动作只要往这里加一条 + do_interact 里加分支。
func interact_options() -> Array:
	var opts := [
		{"id": "talk", "label": "交谈", "hint": "聊聊近况"},
		{"id": "gift", "label": "送礼", "hint": "从背包挑一件礼物送她"},
	]
	# 好感满：未招满伙伴 -> 可召唤；有阵亡 -> 可指定复活（消耗好感）。
	if RelationshipManager.affection >= RelationshipManager.AFF_MAX:
		if not PartyManager.all_recruited():
			for id in PartyManager.recruitable_ids():
				var nm: String = _partner_name(id)
				if nm != "":
					opts.append({"id": "summon:" + id, "label": "召唤 " + nm, "hint": "感召其前来（消耗好感）"})
		for id in PartyManager.dead_ids():
			var nm: String = _partner_name(id)
			if nm != "":
				opts.append({"id": "revive:" + id, "label": "复活 " + nm, "hint": "唤醒倒下的伙伴（消耗好感）"})
	return opts

func _partner_name(id: String) -> String:
	var def: Dictionary = CharacterRegistry.find_by_id(id)
	if def.is_empty():
		return id
	return str(def.get("name", id))

## HUD 点击菜单项后回调（"gift" 由 HUD 自己打开送礼面板，不走这里）。
func do_interact(action_id: String) -> void:
	if action_id.begins_with("summon:"):
		PartyManager.summon_new(action_id.trim_prefix("summon:"))
		return
	if action_id.begins_with("revive:"):
		PartyManager.revive_by_id(action_id.trim_prefix("revive:"))
		return
	match action_id:
		"talk":
			Dialogue.start(NAME, _lines())
		"gift":
			# 兜底：若被直接调用（无 HUD），送背包里第一件可送物品
			var cands := gift_list()
			if cands.is_empty():
				EventBus.toast.emit("你两手空空，女主温柔地笑了笑")
			else:
				give_item(str(cands[0]["id"]), str(cands[0]["src"]))

# =========================================================
# 送礼：候选列表（背包优先，其次营地仓库；同 id 只出现一次）
# =========================================================
func gift_list() -> Array:
	var out: Array = []
	var seen := {}
	for id in Inventory.items:
		var c := int(Inventory.items[id])
		if c > 0:
			seen[id] = true
			out.append({"id": id, "count": c, "src": "bag"})
	var all: Dictionary = CampStorage.get_all()
	for id in all:
		var c := int(all[id])
		if c <= 0 or seen.has(id):
			continue
		out.append({"id": id, "count": c, "src": "warehouse"})
	return out

## 赠送一件物品（HUD 点击「赠送」时调用）。src: "bag"=背包, "warehouse"=营地仓库。
func give_item(id: String, src: String = "bag") -> void:
	if not _consume_gift(id, src):
		EventBus.toast.emit("这件物品已经没有了")
		return
	var d := RelationshipManager.gift(id)
	var nm := _item_name(id)
	if d > 0.0:
		EventBus.toast.emit("送给女主%s，好感 +%d" % [nm, int(d)])
	elif d < 0.0:
		EventBus.toast.emit("女主嫌弃%s" % nm)
	else:
		EventBus.toast.emit("女主收下了%s" % nm)

## 按来源优先扣 1 个，来源不足则回退另一处。返回是否成功扣到。
func _consume_gift(id: String, src: String) -> bool:
	if src == "warehouse":
		if CampStorage.has(id, 1):
			CampStorage.consume(id, 1)
			return true
		return Inventory.consume(id, 1)
	if Inventory.consume(id, 1):
		return true
	if CampStorage.has(id, 1):
		CampStorage.consume(id, 1)
		return true
	return false

func _item_name(id: String) -> String:
	var it: ItemResource = ItemDatabase.get_item(id)
	return it.display_name if it != null else id

func _lines() -> Array:
	return [
		"（她坐在火边，抬头看你）今天也平安回来了，真好。",
		"把钓到的鱼、做好的吃食递给我，我会更有精神打理营地。",
		"只要你好好守着这里……总有一天，岛会回应我们的。",
	]

func _find_anim() -> AnimationPlayer:
	for c in get_children():
		var ap := _scan(c)
		if ap != null:
			return ap
	return null

func _scan(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _scan(c)
		if r != null:
			return r
	return null
