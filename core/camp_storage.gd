extends Node
## 营地仓库（Autoload: CampStorage）。柜子交互打开，作为负重中转与长期存储。
## 与玩家背包（Inventory）并列；数据驱动复用 ItemResource 的重量/显示名。

var _store: Dictionary = {}   # id -> count
signal storage_changed()

func add_item(id: String, n: int = 1) -> void:
	_store[id] = int(_store.get(id, 0)) + n
	storage_changed.emit()

func has(id: String, n: int = 1) -> bool:
	return int(_store.get(id, 0)) >= n

func get_count(id: String) -> int:
	return int(_store.get(id, 0))

func consume(id: String, n: int = 1) -> bool:
	if not has(id, n):
		return false
	_store[id] -= n
	if _store[id] <= 0:
		_store.erase(id)
	storage_changed.emit()
	return true

func get_all() -> Dictionary:
	return _store.duplicate()
