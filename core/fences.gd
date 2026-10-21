extends Node
## 栅栏管理器（Autoload: Fences）。维护营地所有栅栏段的 HP / 等级。
## 夜袭（NightRaid）调用 damage_random 攻击栅栏；玩家交互调用 repair / try_upgrade。
## 设计见 玩法与剧情设计文档 3.1。

signal fence_damaged(seg: int, hp_left: float)
signal fence_broken(seg: int)
signal fence_upgraded(level: int)

var _fences: Array = []   # Fence 节点列表

func register_fence(f: Node) -> void:
	f.seg_index = _fences.size()
	_fences.append(f)

func count() -> int:
	return _fences.size()

func any_broken() -> bool:
	for f in _fences:
		if is_instance_valid(f) and f.hp <= 0.0:
			return true
	return false

func alive_count() -> int:
	var n := 0
	for f in _fences:
		if is_instance_valid(f) and f.hp > 0.0:
			n += 1
	return n

## 取所有「存活且可破坏」的栅栏（营地支柱 indestructible 不参与）。
func _destructible_alive() -> Array:
	var out := []
	for f in _fences:
		if is_instance_valid(f) and f.hp > 0.0 and not f.indestructible:
			out.append(f)
	return out

## 对指定栅栏结算伤害：HP<=0 时从世界移除（连同血条一起消失）。
## 营地支柱（indestructible）不参与，保证营地框架永不被清空。
func _apply_damage(f: Node, amount: float) -> void:
	f.hp -= amount
	if f.hp <= 0.0:
		f.hp = 0.0
		_fences.erase(f)
		fence_broken.emit(f.seg_index)
		if f.has_method("destroy"):
			f.destroy()
	else:
		fence_damaged.emit(f.seg_index, f.hp)

## 夜袭攻击（计时器兜底）：对随机一段「存活且可破坏」的栅栏造成伤害。
func damage_random(amount: float) -> void:
	var alive := _destructible_alive()
	if alive.is_empty():
		return
	_apply_damage(alive[randi() % alive.size()], amount)

## 距某点最近的「存活且可破坏」栅栏（供夜袭怪主动攻营时选目标）。无则返回 null。
func nearest(pos: Vector3) -> Fence:
	var best: Fence = null
	var best_d := INF
	for f in _fences:
		if is_instance_valid(f) and f.hp > 0.0 and not f.indestructible:
			var d := Vector2(pos.x, pos.z).distance_to(Vector2(f.global_position.x, f.global_position.z))
			if d < best_d:
				best_d = d
				best = f
	return best

## 对距某点最近的「存活且可破坏」栅栏造成伤害（夜袭怪挥击命中时调用）。
func damage_nearest(pos: Vector3, amount: float) -> void:
	var f := nearest(pos)
	if f != null:
		_apply_damage(f, amount)

## 玩家修复：耗 原木×2 + 石头×1，+40 HP（不超上限）。
func repair(f: Node) -> void:
	if f == null or not is_instance_valid(f):
		return
	if f.indestructible:
		EventBus.toast.emit("营地支柱无法破坏")
		return
	if f.hp >= f.maxhp:
		EventBus.toast.emit("栅栏无需修复")
		return
	if not Inventory.has("log", 2) or not Inventory.has("stone", 1):
		EventBus.toast.emit("修复需 原木×2 + 石头×1")
		return
	Inventory.consume("log", 2)
	Inventory.consume("stone", 1)
	f.hp = minf(f.maxhp, f.hp + 40.0)
	if not f.visible:
		f.visible = true
	fence_damaged.emit(f.seg_index, f.hp)
	EventBus.toast.emit("栅栏已修复 %d/%d" % [int(f.hp), int(f.maxhp)])

## 玩家升级：T1→T2 耗 原木6+石4；T2→T3 耗 石12+原木4。升级即满血。
func try_upgrade(f: Node) -> void:
	if f == null or not is_instance_valid(f) or f.level >= 3:
		return
	if f.indestructible:
		return
	var cost := {}
	if f.level == 1:
		cost = {"log": 6, "stone": 4}
	else:
		cost = {"stone": 12, "log": 4}
	for id in cost:
		if not Inventory.has(id, cost[id]):
			EventBus.toast.emit("升级需 %s×%d" % [id, cost[id]])
			return
	for id in cost:
		Inventory.consume(id, cost[id])
	f.level += 1
	f.maxhp = f.HP_BY_LEVEL[f.level]
	f.hp = f.maxhp
	fence_upgraded.emit(f.level)
	EventBus.toast.emit("栅栏升级到 Lv%d（HP %d）" % [f.level, int(f.maxhp)])

func get_status() -> Array:
	var out := []
	for f in _fences:
		if is_instance_valid(f):
			out.append({"seg": f.seg_index, "level": f.level, "hp": f.hp, "maxhp": f.maxhp})
	return out

## 营地是否已失守：所有「可破坏」栅栏均被摧毁（支柱 indestructible 不参与，营地框架永清）。
func camp_fallen() -> bool:
	return _destructible_alive().is_empty()

## 复位（重开游戏用）：清空栅栏列表引用；场景重载后由新栅栏重新 register_fence 填充。
func reset_state() -> void:
	_fences.clear()
