extends Node
## 背包（Autoload: Inventory）。格子背包：max_slots 个槽位，每槽放一种物品、数量上限=ItemResource.stack_size。
## 源数据为 slots；items 字典是聚合镜像（id->count，供旧代码/合成/进食读取，保持向后兼容）。
## 提供升级：upgrade_slots(n) 增加槽位数（背包扩容包制作时调用）。

var max_slots := 8
var slots := []          # 长度 = max_slots，元素为 null 或 {"id":String, "count":int}
var items := {}          # 聚合 id->count（由 slots 同步得到，仅供读取）
var total_weight := 0.0
var max_weight := 30.0
signal weight_changed(current: float, maximum: float)
signal overburdened_changed(is_over: bool)
var _over := false
var save_id := "inventory"

func _init() -> void:
	_reset_slots()

func _reset_slots() -> void:
	slots = []
	slots.resize(max_slots)
	for i in max_slots:
		slots[i] = null

func _item_stack(id: String) -> int:
	var it: ItemResource = ItemDatabase.get_item(id)
	if it == null:
		return 99
	return maxi(1, int(it.stack_size))

## 入包：先填同类型已存在槽位（到堆叠上限），再用空槽位；放不下则溢出并提示。
func add_item(id: String, n: int = 1) -> void:
	if n <= 0:
		return
	var cap := _item_stack(id)
	var left := n
	for s in slots:
		if s != null and s.id == id:
			var can: int = cap - int(s.count)
			if can > 0:
				var take: int = mini(can, left)
				s.count = int(s.count) + take
				left -= take
				if left <= 0:
					break
	var i := 0
	while left > 0 and i < slots.size():
		if slots[i] == null:
			var take: int = mini(cap, left)
			slots[i] = {"id": id, "count": take}
			left -= take
		i += 1
	_sync_items()
	var added := n - left
	EventBus.item_picked_up.emit(id, added)
	if left > 0:
		var nm := id
		var it: ItemResource = ItemDatabase.get_item(id)
		if it != null:
			nm = it.display_name
		EventBus.toast.emit("背包已满，%s×%d 未能拾取" % [nm, left])

func has(id: String, n: int = 1) -> bool:
	return count(id) >= n

## 背包是否还能容纳该物品：已有同种堆叠槽 → 可继续叠；否则需有空槽位。
## 营地仓库取出时调用，避免「从仓库扣了却放不进背包」丢物品。
func can_hold(id: String) -> bool:
	if count(id) > 0:
		return true
	for s in slots:
		if s == null:
			return true
	return false

## 是否持有任意「可烹饪生食材」（cooked_result 非空且数量>0）
func has_cookable_raw() -> bool:
	for id in items:
		var it: ItemResource = ItemDatabase.get_item(id)
		if it != null and it.cooked_result != "" and int(items[id]) > 0:
			return true
	return false

func count(id: String) -> int:
	var c := 0
	for s in slots:
		if s != null and s.id == id:
			c += s.count
	return c

## 消耗：跨多个同类型槽位扣减，空槽位回收为 null。
func consume(id: String, n: int = 1) -> bool:
	if not has(id, n):
		return false
	var left := n
	for i in slots.size():
		var s = slots[i]
		if s != null and s.id == id:
			var take: int = mini(int(s.count), left)
			s.count = int(s.count) - take
			left -= take
			if s.count <= 0:
				slots[i] = null
			if left <= 0:
				break
	_sync_items()
	return true

func _sync_items() -> void:
	items = {}
	for s in slots:
		if s != null:
			items[s.id] = items.get(s.id, 0) + s.count
	_recalc_weight()
	EventBus.inventory_changed.emit()

func _recalc_weight() -> void:
	total_weight = 0.0
	for id in items:
		total_weight += _item_weight(id) * items[id]
	var over := total_weight > max_weight
	if over != _over:
		_over = over
		overburdened_changed.emit(_over)
	weight_changed.emit(total_weight, max_weight)

func is_overburdened() -> bool:
	return total_weight > max_weight

func weight_ratio() -> float:
	if max_weight <= 0.0:
		return 1.0
	return clampf(total_weight / max_weight, 0.0, 1.0)

func _item_weight(id: String) -> float:
	var it: ItemResource = ItemDatabase.get_item(id)
	if it == null:
		return 1.0
	return it.item_weight

## 扩容：增加 n 个槽位（新增槽位自动为 null）。
func upgrade_slots(n: int = 4) -> void:
	max_slots += n
	slots.resize(max_slots)
	EventBus.inventory_changed.emit()
	EventBus.toast.emit("背包容量提升：%d 格" % max_slots)

func save() -> Dictionary:
	return {"max_slots": max_slots, "slots": slots.duplicate()}

func load(d: Dictionary) -> void:
	if d.has("slots"):
		max_slots = int(d.get("max_slots", 8))
		var raw: Array = d["slots"]
		slots = []
		for s in raw:
			if s == null:
				slots.append(null)
			else:
				slots.append({"id": str(s["id"]), "count": int(s["count"])})
		while slots.size() < max_slots:
			slots.append(null)
		_sync_items()
	elif d.has("items"):
		# 旧存档（仅 items 字典）迁移：尽量塞进默认 8 格
		max_slots = 8
		_reset_slots()
		_slots_from_items(d["items"])
		_sync_items()

func _slots_from_items(itd: Dictionary) -> void:
	for id in itd:
		var n := int(itd[id])
		var cap := _item_stack(id)
		while n > 0 and _free_slot_count() > 0:
			var take := mini(cap, n)
			_put_in_free(id, take)
			n -= take

func _free_slot_count() -> int:
	var c := 0
	for s in slots:
		if s == null:
			c += 1
	return c

func _put_in_free(id: String, n: int) -> void:
	for i in slots.size():
		if slots[i] == null:
			slots[i] = {"id": id, "count": n}
			return
