extends Node
## 夜袭调度（Autoload: NightRaid）。入夜按天数表生成波次、围攻栅栏；天亮撤退。
## 设计见 玩法与剧情设计文档 3.2 / 3.10 / 3.12。
## 与 CreatureSpawner 的「世界游荡种群」分离：本系统只负责定时波次。

var current_day := 1
var wave_active := false
var _siege := false
var _siege_t := 0.0
var _raid_enemies: Array = []

func _ready() -> void:
	EventBus.day_changed.connect(_on_day)

func _on_day(day: int) -> void:
	current_day = day

func _process(delta: float) -> void:
	if DayNightCycle == null or GameManager.player == null:
		return
	if NestRaid.sandbox:
		return   # 自由模式：不再有夜袭
	var night := DayNightCycle.is_nighttime()
	if night and not wave_active:
		_start_wave()
	elif not night and wave_active:
		_end_wave()
	if _siege and wave_active:
		_siege_t += delta
		if _siege_t >= 3.0:
			_siege_t = 0.0
			_batter_fences()

## 威胁等级（双轴最大值）：天数档 + 等级档。
func _threat() -> float:
	var day_scaled := floorf((current_day - 1) / 2.0)
	var level_scaled := maxf(0.0, float(XP.level) - 1.0)
	return maxf(day_scaled, level_scaled)

## 夜袭波次表（草案 4.3）。
func _wave_plan() -> Dictionary:
	if current_day <= 1:
		return {"beasts": 0, "raiders": 0}     # 第 1 夜平安
	var threat := _threat()
	var beasts := 2 + int(floorf(threat / 2.0))
	var raiders := 0
	if current_day >= 3:
		raiders = int(floorf((current_day - 3) / 3.0)) + 1
	return {"beasts": beasts, "raiders": raiders}

func _start_wave() -> void:
	if Fences.count() == 0:
		return
	wave_active = true
	var plan := _wave_plan()
	EventBus.raid_wave_started.emit(current_day, plan["beasts"], plan["raiders"])
	if plan["beasts"] == 0 and plan["raiders"] == 0:
		EventBus.toast.emit("第 %d 夜：风平浪静（平安夜）" % current_day)
		return
	_siege = true
	_siege_t = 0.0
	EventBus.toast.emit("第 %d 夜来袭：%d 野兽 + %d 野怪" % [current_day, plan["beasts"], plan["raiders"]])
	var threat := _threat()
	for i in plan["beasts"]:
		_spawn_raider_near(CreatureSpawner._weighted_pick(), threat)
	for i in plan["raiders"]:
		_spawn_raider_near(CreatureSpawner.make_raider_template(threat), threat)

func _spawn_raider_near(t: Dictionary, _threat: float) -> void:
	var pos := _camp_edge_position()
	var e := CreatureSpawner.spawn_template_at(t, pos)
	if e != null:
		e.is_sieger = true   # 主动攻营：玩家不在侦测范围时寻路砸栅栏（见 enemy.gd _siege_step）
		e.add_to_group("raid_enemy")
		_raid_enemies.append(e)

## 围攻：每隔几秒对随机一段存活栅栏造成伤害（模拟野怪撞击）。
func _batter_fences() -> void:
	if Fences.alive_count() == 0:
		return
	var alive := 0
	for en in _raid_enemies:
		if is_instance_valid(en) and not bool(en.get("dead")):
			alive += 1
	if alive == 0:
		return
	Fences.damage_random(randf_range(8.0, 16.0))

func _camp_edge_position() -> Vector3:
	var c: Vector2 = GameManager.camp_center
	var ang := randf() * TAU
	var r := 24.0 + randf() * 6.0
	var x := c.x + cos(ang) * r
	var z := c.y + sin(ang) * r
	var gy: float = 0.0
	if GameManager.world != null and GameManager.world.has_method("get_ground_height"):
		gy = GameManager.world.call("get_ground_height", x, z)
	return Vector3(x, gy + 1.2, z)

func _end_wave() -> void:
	wave_active = false
	_siege = false
	for e in _raid_enemies:
		if is_instance_valid(e):
			e.queue_free()
	_raid_enemies.clear()
	EventBus.raid_wave_ended.emit()
