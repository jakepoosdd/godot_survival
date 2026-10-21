extends Node
## 巢穴讨伐（Autoload: NestRaid）。终局 Act 4。
## 解锁条件：伙伴总数 ≥ 4 且（战斗型 ≥ 2 或 主角等级 ≥ 8）。满足条件后解锁岛心祭坛。
## 玩家在祭坛按 E 发起讨伐：岛心刷出唯一 BOSS「巨口魔 Maw」；击杀后雾散、弹出结局分支（离开/留下）。
## Maw 来自 D 盘 guaiwuMaw 怪物模型，绑定 monster_anim 变种人动作包（idle/walk/run/jump/swipe/die），
## 并从模型库取「Mutant Jump Attack」作为跳击（动作包本身无跳击）。体型放大为 BOSS。
## 设计见 玩法与剧情设计文档 3.11 / 3.12。

const NEST := Vector2(-152.2, -195.7)   # 与 world.gd NEST_CENTER 同步（岛心深处·祭坛所在）。原 (-70,-90) 未乘放大因子 2.174，会让 BOSS 刷错位置

var available := false
var cleared := false
var sandbox := false
var _boss: Node = null
# —— 90 天最后通牒：攻营状态 ——
var _siege_active := false
var _siege_timer: Timer = null
const SIEGE_RAIDER_COUNT := 5
const SIEGE_BATTER_DMG := 40.0      # 每 SIEGE_BATTER_INTERVAL 秒对随机栅栏造成的伤害（模拟撞击，保证营地能被推平）
const SIEGE_BATTER_INTERVAL := 3.0

func _ready() -> void:
	EventBus.day_changed.connect(_on_day)
	EventBus.nest_cleared.connect(func(): cleared = true)
	EventBus.creature_died.connect(_on_creature_died)

func _on_day(day: int) -> void:
	if cleared:
		return
	# 解锁逻辑（保持原样）
	if not available:
		var c := Companions.get_status()
		if c["total"] >= 4 and (c["fighter"] >= 2 or XP.level >= 8):
			available = true
			EventBus.nest_available.emit()
			EventBus.toast.emit("岛心传来异动——巢穴的封印松动了！前往岛心祭坛讨伐。")
	# 90 天最后通牒：未击杀 BOSS 则 BOSS 率众攻营（守不住 = GAME OVER）
	if day >= 90 and not cleared and not _siege_active:
		_start_camp_siege()

func can_assault() -> bool:
	return available and not cleared and _boss == null

## 巨口魔 Maw 模板（按威胁缩放）。祭坛讨伐与 90 天攻营共用。
func _boss_template(threat: float) -> Dictionary:
	var hp_mult := 1.0 + 0.06 * threat
	var dmg_mult := 1.0 + 0.04 * threat
	return {
		"name": "Maw", "species": "Boss", "weight": 0,
		"is_aggressive": true, "is_humanoid": true,
		"visual_path": "res://assets/monsters/Maw.glb",
		"max_health": 1200.0 * hp_mult, "enemy_speed": 3.0,
		"attack_damage": 40.0 * dmg_mult, "attack_range": 3.0, "attack_interval": 1.6,
		"xp_reward": 300, "drops": {"cloth": 3, "log": 4, "stick": 4, "stone": 3, "rawmeat": 5},
		"visual_scale": 2.4, "mark_color": Color(0.6, 0.0, 0.0),
		"is_boss": true,
		"anim_map": {
			"idle": "Idle_Loop", "walk": "Walk_Loop", "run": "Sprint_Loop",
			"fall": "Jump_Loop", "attack": "Sword_Attack", "dead": "Die",
			"jump_attack": "Jump_Attack"
		},
		"jump_attack_anim": "Jump_Attack",
		"jump_attack_range": 11.0,
		"jump_attack_damage": 55.0 * dmg_mult,
		"jump_attack_cooldown": 7.0
	}

## 祭坛交互触发：在岛心刷出 Boss。
func start_assault() -> void:
	if not can_assault():
		return
	var t := _boss_template(_threat())
	var pos := _nest_position()
	_boss = CreatureSpawner.spawn_template_at(t, pos)
	if _boss != null:
		_boss.add_to_group("boss")
		EventBus.toast.emit("祭坛爆出黑雾——巨口魔 Maw 现身了！")

func _on_creature_died(creature, _drops) -> void:
	if creature == _boss and is_instance_valid(_boss):
		_boss = null
		if _siege_active:
			_end_siege_victory()
		else:
			cleared = true
			available = false
			EventBus.nest_cleared.emit()
			EventBus.toast.emit("巨口魔 Maw 倒下，笼罩荒岛的雾气散去了……")

## 90 天最后通牒：BOSS 率众攻营。玩家须守住营地（清掉 BOSS 与杂兵），否则营地失守 = GAME OVER。
func _start_camp_siege() -> void:
	_siege_active = true
	var t := _threat()
	# BOSS：若玩家已在祭坛开打则引向营地，否则在营地边缘刷出
	if _boss == null:
		_boss = CreatureSpawner.spawn_template_at(_boss_template(t), _camp_edge_position())
		if _boss != null:
			_boss.add_to_group("boss")
	else:
		_boss.global_position = _camp_edge_position()
	if _boss != null:
		_boss.is_sieger = true
	# 杂兵攻营（专砸栅栏）
	for i in SIEGE_RAIDER_COUNT:
		var rt := CreatureSpawner.make_raider_template(t)
		rt["is_sieger"] = true
		var re := CreatureSpawner.spawn_template_at(rt, _camp_edge_position())
		if re != null:
			re.add_to_group("raid_enemy")
	EventBus.toast.emit("第 90 天——巨口魔率众踏破了营地大门！守住，否则一切终结！")
	if _siege_timer == null:
		_siege_timer = Timer.new()
		_siege_timer.wait_time = SIEGE_BATTER_INTERVAL
		_siege_timer.timeout.connect(_siege_tick)
		add_child(_siege_timer)
	_siege_timer.start()

## 攻营砸栏循环：检测营地失守 / BOSS 被击杀（惨胜），否则持续砸栏。
func _siege_tick() -> void:
	if not _siege_active:
		return
	if Fences.camp_fallen():
		if _siege_timer != null:
			_siege_timer.stop()
		GameManager.trigger_game_over("营地失守——巨口魔踏碎了最后的栅栏。")
		return
	if _boss == null:
		_end_siege_victory()
		return
	Fences.damage_random(SIEGE_BATTER_DMG)

## 攻营惨胜：BOSS 倒下，营地守住。
func _end_siege_victory() -> void:
	_siege_active = false
	if _siege_timer != null:
		_siege_timer.stop()
	cleared = true
	available = false
	EventBus.nest_cleared.emit()
	EventBus.toast.emit("巨口魔倒下了——营地守住了！雾气散去，你赢得了惨烈的喘息。")

## 营地边缘选点（与夜袭同款）。
func _camp_edge_position() -> Vector3:
	var c: Vector2 = GameManager.camp_center
	var ang := randf() * TAU
	var r := 22.0 + randf() * 6.0
	var x := c.x + cos(ang) * r
	var z := c.y + sin(ang) * r
	var gy: float = 0.0
	if GameManager.world != null and GameManager.world.has_method("get_ground_height"):
		gy = float(GameManager.world.call("get_ground_height", x, z))
	return Vector3(x, gy + 1.2, z)

## 复位（重开游戏用）。
func reset_state() -> void:
	cleared = false
	available = false
	sandbox = false
	_boss = null
	_siege_active = false
	if _siege_timer != null:
		_siege_timer.stop()

func _threat() -> float:
	var day_scaled := floorf((float(GameManager.day_count) - 1.0) / 2.0)
	var level_scaled := maxf(0.0, float(XP.level) - 1.0)
	return maxf(day_scaled, level_scaled)

func _nest_position() -> Vector3:
	var gy: float = 0.0
	if GameManager.world != null and GameManager.world.has_method("get_ground_height"):
		gy = float(GameManager.world.call("get_ground_height", NEST.x, NEST.y))
	return Vector3(NEST.x, gy + 1.2, NEST.y)

## 结局分支：离开荒岛（真结局） / 继续留下（自由模式）。
func leave_island() -> void:
	cleared = true
	Dialogue.start("尾声", [
		"祭坛碎裂，笼罩荒岛的浓雾如潮水般退去。",
		"你与女主、岛灵伙伴登上木筏，驶向海平面尽头的晨光。",
		"—— 真结局 · 雾散之时 ——",
	])

func enter_sandbox() -> void:
	sandbox = true
	EventBus.toast.emit("你选择留下——雾散后的荒岛归于宁静，自由经营模式开启。")
