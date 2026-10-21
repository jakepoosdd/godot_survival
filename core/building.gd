extends Node
## 建造系统（Autoload: Building）。把所有「可放置物品」（ItemResource.constructable_scene 非空）
## 作为可建造物。B 进入/退出建造模式，TAB 切换候选，E 在准星前方地表放置（消耗 1 个该物品）。
## 放置物是独立场景实例（如营火），自带交互（烹饪/取暖）。建造模式下玩家攻击与交互暂停。

var build_mode := false
var buildables: Array = []   # ItemResource 列表
var sel_idx := 0
var ghost: Node3D = null

func _ready() -> void:
	_collect()

func _collect() -> void:
	buildables.clear()
	for it in ItemDatabase.all_items():
		if it.constructable_scene != null:
			buildables.append(it)

func _unhandled_input(event) -> void:
	if event is InputEventKey and event.pressed:
		# B 键不再直接进建造模式，改为由 HUD 打开「建造选择菜单」（见 EventBus.build_menu_requested）
		if event.keycode == KEY_TAB and build_mode:
			_cycle()
		elif event.keycode == KEY_E and build_mode:
			_place()

func _toggle() -> void:
	build_mode = not build_mode
	GameManager.build_mode = build_mode
	if build_mode:
		if buildables.is_empty():
			_collect()
		_refresh_ghost()
	else:
		_clear_ghost()

func _cycle() -> void:
	if buildables.is_empty():
		return
	sel_idx = (sel_idx + 1) % buildables.size()
	_refresh_ghost()

func _refresh_ghost() -> void:
	_clear_ghost()
	if buildables.is_empty():
		return
	sel_idx = clampi(sel_idx, 0, buildables.size() - 1)
	var it = buildables[sel_idx]
	if it.constructable_scene == null:
		return
	ghost = it.constructable_scene.instantiate()
	_disable_collision(ghost)   # 预览鬼影只显示、不带物理碰撞，避免在建造模式下推挤玩家
	ghost.name = "BuildGhost"
	add_child(ghost)
	_update_ghost_pos()

func _clear_ghost() -> void:
	if ghost != null:
		ghost.queue_free()
		ghost = null

func _update_ghost_pos() -> void:
	if not build_mode or ghost == null:
		return
	var p = GameManager.player
	if p == null:
		return
	# 以玩家为基准向前投射，避免用相机坐标（相机在玩家身后 5m）导致鬼影落在玩家脚下与之重叠被推挤。
	var origin: Vector3 = p.global_position + Vector3(0, 1.2, 0)
	var dir3: Vector3
	var cam = get_viewport().get_camera_3d()
	if cam != null:
		dir3 = -cam.global_transform.basis.z
	else:
		dir3 = -p.global_transform.basis.z
	dir3.y = 0.0
	if dir3.length_squared() < 1e-6:
		dir3 = Vector3(0, 0, -1)
	dir3 = dir3.normalized()
	var target: Vector3 = origin + dir3 * 3.0
	if GameManager.world != null and GameManager.world.has_method("get_ground_height"):
		target.y = float(GameManager.world.get_ground_height(target.x, target.z))
	ghost.global_position = target

## 递归关闭节点的物理碰撞，让建造预览鬼影只显示、不推挤玩家/世界。
func _disable_collision(n: Node) -> void:
	if n is CollisionObject3D:
		n.collision_layer = 0
		n.collision_mask = 0
		if n is CollisionShape3D or n is CollisionPolygon3D:
			n.disabled = true
	for c in n.get_children():
		_disable_collision(c)

func _process(_delta: float) -> void:
	if build_mode:
		_update_ghost_pos()

## 当前候选的「建造配方」：build_costs 非空则用原材配方，否则退回「耗 1 个成品」。
func _costs_of(it: ItemResource) -> Array:
	if it.build_costs.size() > 0:
		return it.build_costs
	return [{"id": it.id, "amount": 1}]

## 给 UI 用的当前候选配方文本，如 "树枝×5  石头×3  燧石×1"（已计入省材料倍率）。
func current_cost_text() -> String:
	if buildables.is_empty() or sel_idx >= buildables.size():
		return ""
	var it = buildables[sel_idx]
	var parts: Array = []
	for c in _costs_of(it):
		var cid: String = str(c["id"])
		var cit = ItemDatabase.get_item(cid)
		var cn: String = cit.display_name if cit != null else cid
		parts.append("%s×%d" % [cn, Skills.effective_cost(int(c["amount"]))])
	return "  ".join(parts)

func _place() -> void:
	if ghost == null or sel_idx >= buildables.size():
		return
	var it = buildables[sel_idx]
	var costs: Array = _costs_of(it)
	# 先校验材料是否足够（按省材料倍率折算后）
	for c in costs:
		var cid: String = str(c["id"])
		var need: int = Skills.effective_cost(int(c["amount"]))
		if not Inventory.has(cid, need):
			var cit = ItemDatabase.get_item(cid)
			var cn: String = cit.display_name if cit != null else cid
			EventBus.toast.emit("材料不足：需要 %s ×%d" % [cn, need])
			return
	# 扣材料并放置
	for c in costs:
		var cid: String = str(c["id"])
		Inventory.consume(cid, Skills.effective_cost(int(c["amount"])))
	var inst = it.constructable_scene.instantiate()
	get_tree().current_scene.add_child(inst)
	inst.global_position = ghost.global_position
	inst.global_rotation.y = ghost.global_rotation.y
	EventBus.structure_placed.emit(it.id, inst.global_position)

## 给 UI 用的当前候选名。
func current_name() -> String:
	if buildables.is_empty() or sel_idx >= buildables.size():
		return ""
	return buildables[sel_idx].display_name

## 给建造菜单用的：指定索引的候选名 / 配方文本。
func buildable_name(i: int) -> String:
	if i < 0 or i >= buildables.size():
		return ""
	return buildables[i].display_name

func buildable_cost_text(i: int) -> String:
	if i < 0 or i >= buildables.size():
		return ""
	var it = buildables[i]
	var parts: Array = []
	for c in _costs_of(it):
		var cid: String = str(c["id"])
		var cit = ItemDatabase.get_item(cid)
		var cn: String = cit.display_name if cit != null else cid
		parts.append("%s×%d" % [cn, Skills.effective_cost(int(c["amount"]))])
	return "  ".join(parts)

## 选择一个候选并进入建造模式（供建造菜单点击调用）。
func enter_with(idx: int) -> void:
	if buildables.is_empty():
		_collect()
	if buildables.is_empty():
		return
	sel_idx = clampi(idx, 0, buildables.size() - 1)
	if not build_mode:
		_toggle()
	else:
		_refresh_ghost()

## 退出建造模式（供热键 / 菜单关闭调用）。
func exit_build() -> void:
	if build_mode:
		_toggle()
