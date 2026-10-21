extends Node
## 存档中枢（多存档栏版本）。
## 块在 _ready 调 register(self)，暴露 save_id 与 save()/load()。
## 支持 SAVE_SLOTS 个存档栏，文件 user://save_<i>.json。
## 旧版 user://savegame.json 在首次运行时自动迁移到存档栏 0。

const SAVE_SLOTS := 4
const SLOT_PATH := "user://save_%d.json"
const LEGACY_PATH := "user://savegame.json"

var _blocks: Array = []

func _ready() -> void:
	_migrate_legacy()

## 需要存档的块在 _ready 调本函数登记自己。
func register(b) -> void:
	if not _blocks.has(b):
		_blocks.append(b)

## 各块 save() 汇总成字典。
func save_all() -> Dictionary:
	var data := {}
	for b in _blocks:
		if b.get("save_id") != null and b.has_method("save"):
			data[b.save_id] = b.save()
	return data

## 把存档字典分发回各块。
func load_all(data: Dictionary) -> void:
	for b in _blocks:
		if b.get("save_id") != null and data.has(b.save_id) and b.has_method("load"):
			b.load(data[b.save_id])

# =========================================================
# 路径 / 存在
# =========================================================
func slot_path(i: int) -> String:
	return SLOT_PATH % i

func has_slot(i: int) -> bool:
	return FileAccess.file_exists(slot_path(i))

## 向后兼容：默认存档栏 0。
func has_save() -> bool:
	return has_slot(0)

# =========================================================
# 元信息（供存档栏界面显示：天数 / 时刻）
# =========================================================
func slot_meta(i: int) -> Dictionary:
	var d := {"exists": false, "day": 0, "time": 0.0}
	if not has_slot(i):
		return d
	var parsed = _read(slot_path(i))
	if parsed.is_empty():
		return d
	d["exists"] = true
	var meta: Dictionary = parsed.get("_meta", {})
	if meta.has("day"):
		d["day"] = int(meta["day"])
	if meta.has("time"):
		d["time"] = float(meta["time"])
	return d

# =========================================================
# 读写删
# =========================================================
func _write(path: String, data: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true

func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

## 收集各块数据 + 元信息（玩家坐标 / 天数 / 时刻）。
func _collect() -> Dictionary:
	var data := save_all()
	var meta := {}
	meta["day"] = GameManager.day_count
	meta["time"] = GameManager.time_of_day
	var p = GameManager.player
	if p != null:
		meta["px"] = p.global_position.x
		meta["py"] = p.global_position.y
		meta["pz"] = p.global_position.z
	data["_meta"] = meta
	return data

func save_slot(i: int) -> bool:
	return _write(slot_path(i), _collect())

func load_slot(i: int) -> bool:
	var data := _read(slot_path(i))
	if data.is_empty():
		return false
	load_all(data)
	var meta: Dictionary = data.get("_meta", {})
	if meta.has("day"):
		GameManager.day_count = int(meta["day"])
	if meta.has("time"):
		GameManager.time_of_day = float(meta["time"])
	if meta.has("px"):
		var p = GameManager.player
		if p != null:
			p.global_position = Vector3(float(meta["px"]), float(meta["py"]), float(meta["pz"]))
	return true

func delete_slot(i: int) -> void:
	if has_slot(i):
		DirAccess.remove_absolute(slot_path(i))

# =========================================================
# 旧版兼容：自动存档 / 退出仍走存档栏 0
# =========================================================
func save_game() -> bool:
	return save_slot(0)

func load_game() -> bool:
	return load_slot(0)

## 首次运行：把旧版 savegame.json 迁移到存档栏 0（不丢失已有进度）。
func _migrate_legacy() -> void:
	if FileAccess.file_exists(LEGACY_PATH) and not has_slot(0):
		var data := _read(LEGACY_PATH)
		if not data.is_empty():
			_write(slot_path(0), data)
