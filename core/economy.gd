extends Node
## 金币经济（Autoload: Economy）。金币用于商店买卖。
## 物品的 buy_price/sell_price 为 0 且未显式标记时，按类别推导一个默认价，使商店始终有内容。

var gold: int = 0
signal gold_changed(gold: int)
signal trade_made()

func _ready() -> void:
	gold_changed.emit(gold)
	EventBus.gold_changed.emit(gold)

func add_gold(n: int) -> void:
	gold += n
	gold_changed.emit(gold)
	EventBus.gold_changed.emit(gold)
	if n > 0:
		trade_made.emit()
		EventBus.trade_made.emit()

func spend(n: int) -> bool:
	if gold < n:
		return false
	gold -= n
	gold_changed.emit(gold)
	EventBus.gold_changed.emit(gold)
	trade_made.emit()
	EventBus.trade_made.emit()
	return true

## 物品实际卖价（覆盖优先于推导）。
func effective_sell(it: ItemResource) -> int:
	if it == null:
		return 0
	if it.sell_price > 0:
		return it.sell_price
	if it.purchasable and it.buy_price > 0:
		return maxi(1, it.buy_price / 2)
	if it.sellable:
		return maxi(1, int(it.item_weight * 2.0))
	# 默认：能买的东西也能卖（材料/消耗品/工具/武器/装备/建筑），按重量给个保底价
	if is_buyable(it):
		return maxi(1, int(it.item_weight * 2.0))
	return 0

## 物品实际买价（覆盖优先于推导）。
func effective_buy(it: ItemResource) -> int:
	if it == null:
		return 0
	if it.buy_disabled:
		return 0
	if it.buy_price > 0:
		return it.buy_price
	if it.purchasable:
		return maxi(2, int(it.item_weight * 5.0))
	# 默认：工具/武器/装备/建筑/消耗品可买
	if it.category == ItemResource.Category.TOOL or it.category == ItemResource.Category.WEAPON \
		or it.category == ItemResource.Category.GEAR or it.category == ItemResource.Category.BUILDING \
		or it.category == ItemResource.Category.CONSUMABLE:
		return maxi(2, int(it.item_weight * 5.0))
	return 0

func is_sellable(it: ItemResource) -> bool:
	return effective_sell(it) > 0

func is_buyable(it: ItemResource) -> bool:
	return effective_buy(it) > 0

func buy(item_id: String) -> bool:
	var it: ItemResource = ItemDatabase.get_item(item_id)
	if it == null or not is_buyable(it):
		EventBus.toast.emit("该物品无法购买")
		return false
	var price := effective_buy(it)
	if gold < price:
		EventBus.toast.emit("金币不足（需 %d）" % price)
		return false
	gold -= price
	Inventory.add_item(item_id, 1)
	gold_changed.emit(gold)
	EventBus.gold_changed.emit(gold)
	trade_made.emit()
	EventBus.trade_made.emit()
	EventBus.toast.emit("购入 %s（-%d 金币）" % [it.display_name, price])
	return true

func sell(item_id: String) -> bool:
	if not Inventory.has(item_id, 1):
		return false
	var it: ItemResource = ItemDatabase.get_item(item_id)
	if it == null or not is_sellable(it):
		EventBus.toast.emit("该物品不可出售")
		return false
	var price := effective_sell(it)
	Inventory.consume(item_id, 1)
	gold += price
	gold_changed.emit(gold)
	EventBus.gold_changed.emit(gold)
	trade_made.emit()
	EventBus.trade_made.emit()
	EventBus.toast.emit("售出 %s（+%d 金币）" % [it.display_name, price])
	return true
