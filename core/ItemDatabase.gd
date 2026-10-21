extends Node
## 物品注册中心（Autoload: ItemDatabase）。扫描 data/items/ 下所有 .tres（ItemResource），按 id 注册。
## 加物品 = 在 data/items/ 丢一个 .tres，本类自动收录，不改此处代码（数据驱动）。

const ITEM_FOLDER := "res://data/items/"
var _items: Dictionary = {}   # id -> ItemResource

func _ready() -> void:
	_scan()
	# 兜底：任何情况下扫描为空（导出包目录形态变化等），用显式清单再试一次，
	# 保证物品表绝不为空（物品表空 → 界面显示英文 id、无法使用、合成配方全空）。
	if _items.is_empty():
		push_warning("ItemDatabase: 目录扫描为空，改用显式清单兜底")
		_load_known_items()

## 已知物品 id 清单（与 data/items/*.tres 文件名一致）。仅在扫描失败时兜底。
const KNOWN_ITEM_IDS: PackedStringArray = [
	"axe", "backpack_upgrade", "bait", "berry", "camp_storage", "campfire", "cloth",
	"coal", "cooked_fish", "cookedmeat", "fence", "fish_big", "fish_rare", "fish_small",
	"fishing_rod", "flintstone", "house", "log", "pickaxe", "rawmeat", "root", "rope",
	"shovel", "sickle", "spear", "stick", "stone", "tent",
]

func _load_known_items() -> void:
	for id in KNOWN_ITEM_IDS:
		var p := ITEM_FOLDER.path_join(id + ".tres")
		if not ResourceLoader.exists(p):
			continue
		var res = load(p)
		if res is ItemResource:
			var it := res as ItemResource
			if it.id != "":
				if it.icon == null:
					it.icon = ItemIcons.icon_for(it.id)
				_items[it.id] = it

func _scan() -> void:
	var dir := DirAccess.open(ITEM_FOLDER)
	if dir == null:
		push_warning("ItemDatabase: 文件夹不存在 " + ITEM_FOLDER)
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		# ⚠️ 导出包(PCK)里目录项是 "rawmeat.tres.remap"（导入 remap 文件），
		#    源 .tres 不以该名字存在。必须去掉 .remap 后缀再判断，否则导出后扫到 0 个物品
		#    → 界面显示英文 id、物品无法使用。
		var nm := fn
		if nm.ends_with(".remap"):
			nm = nm.substr(0, nm.length() - 6)
		if nm.ends_with(".tres") or nm.ends_with(".res"):
			var res = load(ITEM_FOLDER.path_join(nm))
			if res is ItemResource:
				var it := res as ItemResource
				if it.id != "":
					if it.icon == null:
						it.icon = ItemIcons.icon_for(it.id)
					_items[it.id] = it
		fn = dir.get_next()

func get_item(id: String) -> ItemResource:
	return _items.get(id)

## 运行时注册物品（钓鱼系统等动态生成 fish_* 物品用）。重复 id 覆盖。
func register_item(it: ItemResource) -> void:
	if it == null or it.id == "":
		return
	if it.icon == null:
		it.icon = ItemIcons.icon_for(it.id)
	_items[it.id] = it

func has_item(id: String) -> bool:
	return _items.has(id)

func all_items() -> Array[ItemResource]:
	var arr: Array[ItemResource] = []
	for it in _items.values():
		arr.append(it)
	return arr
