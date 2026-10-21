extends Node
## 装备 / 快捷栏系统（Autoload: Equipment）。
## 把背包里的武器/工具装进快捷栏（最多 6 格），数字键 1-6 切换当前装备。
## 当前装备决定：攻击伤害加成。采集仍按 Inventory 判定（无需先装备）。

const MAX_SLOTS := 6
var hotbar: Array[String] = []      # 当前可装备物品 id 列表
var equipped_index := 0
signal hotbar_changed(hotbar: Array)
signal equipped_changed(item_id: String, index: int)

func _ready() -> void:
	EventBus.inventory_changed.connect(_rebuild)
	_rebuild()

func _is_equippable(id: String) -> bool:
	var it: ItemResource = ItemDatabase.get_item(id)
	if it == null:
		return false
	if it.category == ItemResource.Category.WEAPON or it.category == ItemResource.Category.TOOL or it.category == ItemResource.Category.GEAR:
		return true
	return it.weapon_damage > 0.0

func _rebuild() -> void:
	var prev_id := ""
	if equipped_index >= 0 and equipped_index < hotbar.size():
		prev_id = hotbar[equipped_index]
	hotbar.clear()
	for id in Inventory.items:
		if _is_equippable(id):
			hotbar.append(id)
	# 排序：武器 > 工具 > 其它，再按名字，保证稳定
	hotbar.sort_custom(func(a: String, b: String) -> bool:
		var ia: ItemResource = ItemDatabase.get_item(a)
		var ib: ItemResource = ItemDatabase.get_item(b)
		var ca := _rank(ia)
		var cb := _rank(ib)
		if ca != cb:
			return ca < cb
		return a < b
	)
	if hotbar.size() > MAX_SLOTS:
		hotbar = hotbar.slice(0, MAX_SLOTS)
	if prev_id != "" and hotbar.has(prev_id):
		equipped_index = hotbar.find(prev_id)
	else:
		equipped_index = _best_index()
	hotbar_changed.emit(hotbar)
	_emit_equipped()

func _rank(it: ItemResource) -> int:
	if it == null:
		return 9
	match it.category:
		ItemResource.Category.WEAPON: return 0
		ItemResource.Category.TOOL: return 1
		ItemResource.Category.GEAR: return 2
		_: return 3

func _best_index() -> int:
	var best := -1
	var best_wd := -1.0
	for i in hotbar.size():
		var it: ItemResource = ItemDatabase.get_item(hotbar[i])
		var wd := it.weapon_damage if it != null else 0.0
		if wd > best_wd:
			best_wd = wd
			best = i
	if hotbar.size() == 0:
		return 0
	return maxi(0, best)

func active_id() -> String:
	if equipped_index >= 0 and equipped_index < hotbar.size():
		return hotbar[equipped_index]
	return ""

func active_weapon_damage() -> float:
	var id := active_id()
	if id == "":
		return 0.0
	var it: ItemResource = ItemDatabase.get_item(id)
	return it.weapon_damage if it != null else 0.0

func equip_index(i: int) -> void:
	if i < 0 or i >= hotbar.size():
		return
	equipped_index = i
	_emit_equipped()

func cycle(dir: int) -> void:
	if hotbar.size() == 0:
		return
	equipped_index = wrapi(equipped_index + sign(dir), 0, hotbar.size())
	_emit_equipped()

func _emit_equipped() -> void:
	equipped_changed.emit(active_id(), equipped_index)
