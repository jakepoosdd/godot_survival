extends Node
## 全局状态单例。只存"跨块共享的少量状态"，不持有任何游戏节点。

var day_count: int = 1
var time_of_day: float = 0.35          # 0..1，0=午夜
var is_paused: bool = false
var player = null                       # Player 在 _ready 自注册
var world = null                        # World 在 _ready 自注册（供敌人等地表查询）
var camp_center: Vector2 = Vector2(70.0, 95.0)   # 营地中心（World 初始化时写入，供夜袭等使用）
var game_over: bool = false
var player_dead: bool = false           # 死亡瞬间锁，避免 needs_system 每帧重复触发 player_died
var build_mode: bool = false            # 建造模式开关（玩家攻击/交互在建造模式暂停）
var interact_menu_open: bool = false    # NPC 交互菜单/送礼面板打开（锁定攻击与 E 交互，鼠标可见）
# 面板开合状态（供 Menus 在 Esc 时让位给对应面板）
var shop_open: bool = false
var bulletin_open: bool = false
var ach_open: bool = false

func _ready() -> void:
	EventBus.player_died.connect(_on_dead)
	EventBus.creature_died.connect(_on_creature_died)

## 动物死亡掉落：把 drops 字典里的物品加进背包并提示。
## 敌人 enemy.gd 在 die() 时 emit creature_died(self, drops)，此前没有任何监听者把掉落物给玩家，
## 所以"打死动物不掉肉"——这里补上真正的拾取逻辑。
func _on_creature_died(_creature, drops: Dictionary) -> void:
	if drops == null or drops.is_empty():
		return
	# 最后一击来源：敌人死亡节点上记录（玩家或伙伴）。信号参数不能带默认值，故从节点读取。
	var killer = null
	if _creature != null and is_instance_valid(_creature) and _creature.has_method("get"):
		killer = _creature.get("_killer")
	# 伙伴击杀：战利品归属该伙伴的每日贡献上限，统一进营地仓库
	if killer != null and is_instance_valid(killer):
		if killer.has_method("contribute_loot"):
			killer.contribute_loot(drops)
			return
		if killer is Node and killer.is_in_group("companion"):
			# 其它类型伙伴（如精灵伙伴）也进营地仓库，但不计个人上限
			var parts0: Array[String] = []
			for id in drops:
				var n: int = int(drops[id])
				if n <= 0:
					continue
				CampStorage.add_item(id, n)
				var it: ItemResource = ItemDatabase.get_item(id)
				var nm: String = it.display_name if it != null else id
				parts0.append("%s×%d" % [nm, n])
			if not parts0.is_empty():
				EventBus.toast.emit("掉落：" + ", ".join(parts0))
			return
	# 玩家 / 环境击杀：照旧进玩家背包
	var parts: Array[String] = []
	for id in drops:
		var n: int = int(drops[id])
		if n <= 0:
			continue
		Inventory.add_item(id, n)
		var it: ItemResource = ItemDatabase.get_item(id)
		var nm: String = it.display_name if it != null else id
		parts.append("%s×%d" % [nm, n])
	if not parts.is_empty():
		EventBus.toast.emit("掉落：" + ", ".join(parts))

## 死亡 = 在营地复活（非 game over）。保留等级/技能/工具/武器/建筑；
## 仅掉落当前携带的材料、女主好感清零、精神受挫（见设计文档 3.9，已由 RelationshipManager 处理）。
func _on_dead() -> void:
	if player_dead:
		return
	player_dead = true
	EventBus.toast.emit("你倒下了……将在营地苏醒。")
	_drop_carried_materials()
	_respawn_player()
	player_dead = false

## 掉落主角「当前身上携带的材料」（raw 资源），工具/武器/装备/等级/技能全部保留。
func _drop_carried_materials() -> void:
	var raw := ["log", "stick", "stone", "flintstone", "fiber", "linen", "berry", "bait", "rawmeat", "root"]
	var dropped := 0
	for id in raw:
		if Inventory.has(id, 1):
			var n: int = Inventory.count(id)
			Inventory.consume(id, n)
			dropped += n
	if dropped > 0:
		EventBus.toast.emit("携带的材料散落了（%d 件）" % dropped)

## 传送回营地 + 复位需求（回血/回精神，饥饿略降）。
func _respawn_player() -> void:
	var p = player
	if p == null:
		return
	var c: Vector2 = camp_center
	var gy: float = 0.0
	if world != null and world.has_method("get_ground_height"):
		gy = float(world.call("get_ground_height", c.x, c.y))
	p.global_position = Vector3(c.x, gy + 0.2, c.y)
	var ns = p.get_node_or_null("NeedsSystem")
	if ns != null and ns.has_method("respawn"):
		ns.respawn()
	# 复活后保持鼠标捕获（第三人称控制）
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## 终局失败：营地失守 → 置位 game_over（player.gd 据此冻结移动），并广播 GAME OVER 界面。
func trigger_game_over(reason: String) -> void:
	if game_over:
		return
	game_over = true
	EventBus.game_over.emit(reason)

## 重开：复位关键全局状态后重载当前场景。各 Autoload 的 reset_state 由各自实现，
## 用 has_method 守卫，缺失也不崩；场景重载会重建玩家与世界节点。
func restart_game() -> void:
	game_over = false
	player_dead = false
	day_count = 1
	if NestRaid.has_method("reset_state"):
		NestRaid.reset_state()
	if NightRaid.has_method("reset_state"):
		NightRaid.reset_state()
	if Fences.has_method("reset_state"):
		Fences.reset_state()
	if XP.has_method("reset"):
		XP.reset()
	if RelationshipManager.has_method("reset"):
		RelationshipManager.reset()
	get_tree().reload_current_scene()
