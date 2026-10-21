extends Node
## 制作系统（Autoload: Crafting）。配方由各物品的 ItemResource.crafting_costs 推导：
## 凡 crafting_costs 非空者，即为「可制作成品」，配方 = 产出该物品、消耗其 costs。
## 这样加配方 = 在 data/items/*.tres 里填 crafting_costs，无需改此脚本（数据驱动）。

signal recipes_changed()

var recipes: Array = []   # [{id, name, costs:[{id,amount}]}]

func _ready() -> void:
	_build_recipes()

func _build_recipes() -> void:
	recipes.clear()
	for it: ItemResource in ItemDatabase.all_items():
		if it.crafting_costs.size() > 0:
			recipes.append({"id": it.id, "name": it.display_name, "costs": it.crafting_costs})
	recipes_changed.emit()

## 能否制作（材料是否足够）。
func can_craft(id: String) -> bool:
	var it: ItemResource = ItemDatabase.get_item(id)
	if it == null:
		return false
	for c in it.crafting_costs:
		if not Inventory.has(str(c["id"]), int(c["amount"])):
			return false
	return true

## 执行制作：扣材料 -> 产出 1 个成品。
func craft(id: String) -> bool:
	if not can_craft(id):
		return false
	var it: ItemResource = ItemDatabase.get_item(id)
	for c in it.crafting_costs:
		Inventory.consume(str(c["id"]), Skills.effective_cost(int(c["amount"])))
	if it.upgrade_slots > 0:
		Inventory.upgrade_slots(it.upgrade_slots)
		EventBus.toast.emit("背包扩容：+%d 格" % it.upgrade_slots)
	else:
		Inventory.add_item(id, 1)
	EventBus.recipe_crafted.emit(id)
	return true

## 给 UI 用的可读配方字符串，如 "斧头: 树枝x3 石头x1"。
func recipe_text(id: String) -> String:
	var it: ItemResource = ItemDatabase.get_item(id)
	if it == null:
		return id
	var s := it.display_name + ": "
	var parts: Array = []
	for c in it.crafting_costs:
		var cid: String = str(c["id"])
		var cit = ItemDatabase.get_item(cid)
		var cn: String = cit.display_name if cit != null else cid
		parts.append("%s×%d" % [cn, int(c["amount"])])
	return s + "  ".join(parts)
