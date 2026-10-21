extends Node
## 怪物刷新系统（Autoload: CreatureSpawner）。
## 维护一张生物模板表（物种/体型/属性/掉落），负责：
##   1) initial_populate() 在开局生成初始种群；
##   2) 每隔 spawn_interval 秒，若场上存活数 < max_alive，则补员到上限，让世界持续有怪可打。
## 完全数据驱动，复用 enemy/enemy.gd；不持有场景节点引用，通过 get_tree().current_scene 挂接。

signal population_changed(alive: int, cap: int)

const ENEMY_SCRIPT := "res://enemy/enemy.gd"
# 与 world.gd 同步的岛屿尺度（用于把野怪撒向全岛，而非只绕玩家）
const ISLAND_R := 347.8
const SEA_LEVEL := 0.0

# 权重越高越常刷出。
var _templates: Array = [
	{
		"name": "Wolf", "species": "Wolf", "weight": 3,
		"is_aggressive": true, "max_health": 80.0, "enemy_speed": 4.2,
		"attack_damage": 18.0, "attack_range": 2.2, "attack_interval": 1.4,
		"xp_reward": 25, "drops": {"rawmeat": 2, "log": 1, "stick": 1},
		"visual_scale": 1.0, "mark_color": Color(0.85, 0.15, 0.15)
	},
	{
		"name": "Deer", "species": "Deer", "weight": 3,
		"is_aggressive": false, "max_health": 45.0, "enemy_speed": 3.4,
		"flee_speed": 6.0, "attack_damage": 0.0, "attack_range": 2.2, "attack_interval": 1.4,
		"xp_reward": 10, "drops": {"rawmeat": 2, "berry": 1},
		"visual_scale": 1.0, "mark_color": Color(0.3, 0.8, 0.4)
	},
	{
		"name": "Boar", "species": "Boar", "weight": 2,
		"is_aggressive": true, "max_health": 55.0, "enemy_speed": 5.2,
		"attack_damage": 13.0, "attack_range": 2.0, "attack_interval": 1.1,
		"xp_reward": 18, "drops": {"rawmeat": 2, "stick": 2},
		"visual_scale": 0.75, "mark_color": Color(0.6, 0.4, 0.25)
	},
	{
		"name": "Fox", "species": "Fox", "weight": 2,
		"is_aggressive": false, "max_health": 28.0, "enemy_speed": 4.6,
		"flee_speed": 7.5, "attack_damage": 0.0, "attack_range": 2.2, "attack_interval": 1.4,
		"xp_reward": 8, "drops": {"berry": 2, "rawmeat": 1},
		"visual_scale": 0.7, "mark_color": Color(0.95, 0.6, 0.2)
	},
	{
		"name": "Bear", "species": "Bear", "weight": 1,
		"is_aggressive": true, "max_health": 170.0, "enemy_speed": 3.2,
		"attack_damage": 30.0, "attack_range": 2.6, "attack_interval": 1.8,
		"xp_reward": 55, "drops": {"rawmeat": 3, "log": 2, "stick": 2},
		"visual_scale": 1.4, "mark_color": Color(0.5, 0.3, 0.2)
	},
	{
		"name": "Demon", "species": "Demon", "weight": 2,
		"is_aggressive": true, "is_humanoid": true,
		"visual_path": "res://assets/monsters/Demon.glb",
		"max_health": 140.0, "enemy_speed": 4.2,
		"attack_damage": 25.0, "attack_range": 2.2, "attack_interval": 1.3,
		"xp_reward": 45, "drops": {"rawmeat": 3, "log": 1, "cloth": 1},
		"visual_scale": 1.05, "mark_color": Color(0.85, 0.1, 0.3)
	},
	{
		"name": "SkeletonZombie", "species": "SkeletonZombie", "weight": 2,
		"is_aggressive": true, "is_humanoid": true,
		"visual_path": "res://assets/monsters/SkeletonZombie.glb",
		"max_health": 95.0, "enemy_speed": 3.0,
		"attack_damage": 18.0, "attack_range": 2.0, "attack_interval": 1.5,
		"xp_reward": 30, "drops": {"bone": 3, "rawmeat": 1},
		"visual_scale": 1.0, "mark_color": Color(0.7, 0.7, 0.75)
	},
	{
		"name": "Warrok", "species": "Warrok", "weight": 1,
		"is_aggressive": true, "is_humanoid": true,
		"visual_path": "res://assets/monsters/Warrok.glb",
		"max_health": 210.0, "enemy_speed": 2.8,
		"attack_damage": 35.0, "attack_range": 2.6, "attack_interval": 1.8,
		"xp_reward": 70, "drops": {"rawmeat": 4, "log": 2, "cloth": 1},
		"visual_scale": 1.2, "mark_color": Color(0.6, 0.2, 0.1)
	},
]

var max_alive := 18
var spawn_interval := 12.0

## 设置刷怪上限（阶段系统据此随进度提升难度）。
func set_cap(n: int) -> void:
	max_alive = maxi(1, int(n))
	population_changed.emit(_alive_count(), max_alive)

func get_cap() -> int:
	return max_alive
var _timer: Timer = null
var _next_idx := 0

func _ready() -> void:
	call_deferred("_start")

func _start() -> void:
	if _timer == null:
		_timer = Timer.new()
		_timer.wait_time = spawn_interval
		_timer.timeout.connect(_tick)
		add_child(_timer)
		_timer.start()

## 开局种群（初始约 15 只：5 物种动物 + 3 人形），覆盖全部可刷物种。
func initial_populate() -> void:
	var plan := [
		{"name": "Wolf", "count": 3},
		{"name": "Deer", "count": 3},
		{"name": "Boar", "count": 2},
		{"name": "Fox",  "count": 2},
		{"name": "Bear", "count": 2},
		{"name": "Demon", "count": 1},
		{"name": "SkeletonZombie", "count": 1},
		{"name": "Warrok", "count": 1},
	]
	for spec in plan:
		for i in int(spec["count"]):
			_spawn_one(_find_template(spec["name"]))
	# 开局保证玩家附近有怪可打（引导任务⑨需要猎物），其余已撒向全岛
	var near := _alive_near_player(85.0)
	var need := maxi(0, 3 - near)
	for i in need:
		_spawn_one(_weighted_pick(), _pick_position_near_player())
	# 开局保证「看得见人形怪」：人形怪（Demon/SkeletonZombie/Warrok）全岛随机后常在数百米外，
	# 玩家会误以为人形怪消失了。这里固定补 1 只骨架僵尸在营地 70~120m 的陆地上（不贴脸、不立刻袭营）。
	_spawn_one(_find_template("SkeletonZombie"), _pick_position_ring(70.0, 120.0))
	population_changed.emit(_alive_count(), max_alive)

## 定时补员：场上少于上限时，按权重随机补齐。
func _tick() -> void:
	if get_tree() == null or get_tree().current_scene == null:
		return
	if GameManager.world == null or GameManager.player == null:
		return
	var alive := _alive_count()
	if alive >= max_alive:
		return
	var to_add := max_alive - alive
	# 玩家周围怪太少时优先补到附近（保证始终有怪可打），其余撒向全岛
	var near := _alive_near_player(85.0)
	var near_quota := 0
	if near < 3:
		near_quota = mini(to_add, 3 - near)
	for i in to_add:
		if i < near_quota:
			_spawn_one(_weighted_pick(), _pick_position_near_player())
		else:
			_spawn_one(_weighted_pick(), _pick_position())
	population_changed.emit(_alive_count(), max_alive)

func _alive_count() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e.get("dead"):
			n += 1
	return n

func _find_template(name: String) -> Dictionary:
	for t in _templates:
		if t["name"] == name:
			return t
	return _templates[0]

func _weighted_pick() -> Dictionary:
	var total := 0
	for t in _templates:
		total += int(t["weight"])
	var r := randi() % total
	for t in _templates:
		r -= int(t["weight"])
		if r < 0:
			return t
	return _templates[0]

## 游荡野怪随天数/等级「缓慢」加强（比 BOSS 温和）：
## wt = max(⌊(日-1)/3⌋, ⌊(级-1)/4⌋)；hp×1+0.03wt, dmg×1+0.02wt。
## 注意：BOSS（nest_raid）与夜袭杂兵（night_raid）各自在模板里带缩放，不在此处叠加——只缩放世界游荡种群。
func _world_mult() -> Dictionary:
	var day := 1
	if GameManager != null:
		day = GameManager.day_count
	var lvl := 1
	if XP != null:
		lvl = XP.level
	var wt := int(floorf((day - 1) / 3.0))
	wt = maxi(wt, int(floorf((lvl - 1) / 4.0)))
	wt = maxi(0, wt)
	return {"hp": 1.0 + 0.03 * float(wt), "dmg": 1.0 + 0.02 * float(wt)}

## 生成一只生物：自包含，挂到当前场景根（与玩家同级）。
## pos 为 null 时默认在全岛陆地随机取点（见 _pick_position）。
func _spawn_one(t: Dictionary, pos = null) -> void:
	if get_tree() == null or get_tree().current_scene == null:
		return
	var sc := load(ENEMY_SCRIPT)
	if sc == null:
		return
	var e := CharacterBody3D.new()
	e.name = "%s_%d" % [t["name"], _next_idx]
	_next_idx += 1
	e.set_script(sc)
	# 游荡野怪随天数/等级缓慢加强（BOSS / 夜袭杂兵各自带缩放，不在此处叠加）
	var m := _world_mult()
	# 注入参数（_ready 已用默认值初始化，这里覆盖并修正派生值 health）
	for k in t:
		if k in ["name", "weight", "mark_color"]:
			continue
		if k in e:
			if k == "max_health":
				e.set(k, float(t[k]) * m["hp"])
			elif k == "attack_damage":
				e.set(k, float(t[k]) * m["dmg"])
			else:
				e.set(k, t[k])
	if "max_health" in t:
		e.health = float(t["max_health"]) * m["hp"]
	# 选点（未指定则全岛随机）
	var p: Vector3 = _pick_position()
	if pos is Vector3:
		p = pos
	e.position = p
	get_tree().current_scene.add_child(e)

## 钓点刷怪禁区半径：任何候选刷怪点若落在某钓点此半径内，则换一个位置，
## 保证玩家在钓点钓鱼时（强制第一人称、不便战斗）周围不会刷出野怪。
const FISHING_EXCLUDE_R := 30.0

## 在指定位置生成一只生物（夜袭/特殊刷怪用）。返回实例或 null。
func spawn_template_at(t: Dictionary, pos: Vector3) -> Node:
	if get_tree() == null or get_tree().current_scene == null:
		return null
	var sc := load(ENEMY_SCRIPT)
	if sc == null:
		return null
	var e := CharacterBody3D.new()
	e.name = "%s_%d" % [t.get("name", "Mob"), _next_idx]
	_next_idx += 1
	e.set_script(sc)
	for k in t:
		if k in ["name", "weight", "mark_color"]:
			continue
		if k in e:
			e.set(k, t[k])
	if "max_health" in t:
		e.health = float(t["max_health"])
	e.position = pos
	get_tree().current_scene.add_child(e)
	return e

## 当前世界的全部钓点（世界未加载时为空数组，退化为不限制）。
func _fishing_spots() -> Array:
	if GameManager.world != null and GameManager.world.has_method("get_fishing_spot_positions"):
		return GameManager.world.call("get_fishing_spot_positions")
	return []

func _near_fishing_spot(p: Vector3, spots: Array) -> bool:
	for s in spots:
		var sp: Vector2 = s
		if Vector2(p.x, p.z).distance_to(sp) < FISHING_EXCLUDE_R:
			return true
	return false

## 人形野怪 Raider 模板（按威胁等级缩放）。设计见 3.5 / 3.10 / 3.12。
func make_raider_template(threat: float) -> Dictionary:
	var hp_mult := 1.0 + 0.06 * threat
	var dmg_mult := 1.0 + 0.04 * threat
	return {
		"name": "Raider", "species": "Raider", "weight": 0,
		"is_aggressive": true, "is_humanoid": true,
		"max_health": 120.0 * hp_mult, "enemy_speed": 3.6,
		"attack_damage": 22.0 * dmg_mult, "attack_range": 2.0, "attack_interval": 1.2,
		"xp_reward": 40, "drops": {"stick": 2, "log": 1, "cloth": 1},
		"visual_scale": 1.0, "mark_color": Color(0.6, 0.1, 0.1)
	}

## 以「玩家」为中心、40~200m 环带随机取陆地点（不再以岛心(0,0)为基准撒满全岛）。
## 营地位于岛屿边缘（≈340,72），若仍以岛心为基准，绝大多数野怪会落在离玩家约 340m 的岛心附近，
## 玩家在营地附近几乎遇不到怪。改为绕玩家刷，并强制候选点仍落在岛内（离岛心 <= 半径-12），避开水面/钓点/贴脸。
func _pick_position() -> Vector3:
	var center := Vector3.ZERO
	var has_player := false
	if GameManager.player != null:
		center = GameManager.player.global_position
		has_player = true
	var spots := _fishing_spots()
	for tries in 48:
		var ang := randf() * TAU
		var r := 40.0 + randf() * 160.0            # 40~200m 环带：够近能看到、又不贴脸
		var x := center.x + cos(ang) * r
		var z := center.z + sin(ang) * r
		if sqrt(x * x + z * z) > ISLAND_R - 12.0:
			continue                              # 超出岛界（多在边缘海域）→ 换点
		var gy: float = 0.0
		if GameManager.world != null and GameManager.world.has_method("get_ground_height"):
			gy = GameManager.world.call("get_ground_height", x, z)
		if gy <= SEA_LEVEL + 1.0:
			continue                              # 海面/水边不刷
		var p := Vector3(x, gy + 0.3, z)
		if has_player and p.distance_to(center) <= 16.0:
			continue                              # 离玩家太近不刷（避免贴脸）
		if _near_fishing_spot(p, spots):
			continue                              # 钓鱼安全区
		return p
	# 兜底：玩家附近 40~120m 环带
	return _pick_position_ring(40.0, 120.0) if has_player else Vector3(0.0, 5.0, 0.0)

## 玩家附近的陆地取点（26~64m），用于「保证身边有怪可打」的保底补员。
func _pick_position_near_player() -> Vector3:
	if GameManager.player == null:
		return _pick_position()
	var center: Vector3 = GameManager.player.global_position
	var spots := _fishing_spots()
	var gy: float = 0.0
	for tries in 24:
		var ang := randf() * TAU
		var r := 26.0 + randf() * 38.0
		var x := center.x + cos(ang) * r
		var z := center.z + sin(ang) * r
		if GameManager.world != null and GameManager.world.has_method("get_ground_height"):
			gy = GameManager.world.call("get_ground_height", x, z)
		if gy <= SEA_LEVEL + 1.0:
			continue
		var p := Vector3(x, gy + 0.3, z)
		if _near_fishing_spot(p, spots):
			continue
		return p
	return _pick_position()

## 营地外环带取陆地点（min_r~max_r 米），保证附近必有人形怪可见、又不贴脸。
func _pick_position_ring(min_r: float, max_r: float) -> Vector3:
	if GameManager.player == null:
		return _pick_position()
	var center: Vector3 = GameManager.player.global_position
	var spots := _fishing_spots()
	var gy: float = 0.0
	for tries in 32:
		var ang := randf() * TAU
		var r := min_r + randf() * (max_r - min_r)
		var x := center.x + cos(ang) * r
		var z := center.z + sin(ang) * r
		if GameManager.world != null and GameManager.world.has_method("get_ground_height"):
			gy = GameManager.world.call("get_ground_height", x, z)
		if gy <= SEA_LEVEL + 1.0:
			continue
		var p := Vector3(x, gy + 0.3, z)
		if _near_fishing_spot(p, spots):
			continue
		return p
	return _pick_position()

## 玩家半径内还活着的野怪数量（判断是否需要在身边补员）。
func _alive_near_player(radius: float) -> int:
	if get_tree() == null or GameManager.player == null:
		return 0
	var pp: Vector3 = GameManager.player.global_position
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e.get("dead"):
			if e.global_position.distance_to(pp) <= radius:
				n += 1
	return n
