extends Node
## 全面钓鱼系统（Autoload: FishingSystem）。对标 Tidewater 的钓鱼设计：
##   抛竿 → 等待 → 咬钩(限时刺鱼) → 张力博弈(收线/泄力/鱼冲刺) → 入护/脱钩 → 图鉴/冷藏箱。
## 鱼种按 栖息地(近岸/海湾/礁/深水) + 水深 + 时段 从 FishDatabase 筛；张力博弈用左键收线。
## 复用现有 EventBus.fishing_* 信号驱动 player.gd 的鱼竿动画；新增信号驱动 FishingUI。
## 接入 SaveManager 持久化图鉴与冷藏箱；装备修正来自 FishingGear。

enum State { IDLE, CASTING, WAITING, BITE, FIGHT, CAUGHT, ENDED }

const SEA_LEVEL := 0.0

var state: int = State.IDLE
var spot_position: Vector3 = Vector3.ZERO

# 当前这一竿的鱼
var _species: FishSpecies = null
var _length_cm: float = 0.0
var _weight_kg: float = 0.0
var _habitat: String = FishSpecies.H_SHALLOWS
var _depth: float = 1.0
var _cast_landing: Vector3 = Vector3.ZERO   # 本竿浮标落点（世界坐标，落在真实水面）

# 计时器（用 delta 累加，避免额外 Timer 节点）
var _cast_t: float = 0.0
var _wait_t: float = 0.0
var _bite_t: float = 0.0
var _end_t: float = 0.0

# 张力博弈
var _tension: float = 0.0
var _progress: float = 0.0
var _run_timer: float = 0.0
var _running: bool = false
var _run_dur: float = 0.0
var _strain_played: bool = false   # 张力红区音效去抖（跨入红区只播一次）
var _fish_stamina: float = 1.0     # 鱼的体力 0..1（随拉扯消耗，冲刺回一点）
var _exhausted: bool = false        # 鱼力竭（体力归零）后自动收线入护
var _fight_dist0: float = 16.0     # 本竿起点距离（米），用于"拉力对决"面板显示鱼离竿距离

# 图鉴（持久化）；渔获直接进营地仓库（CampStorage），不再用私有冷藏箱计数
var _log: Dictionary = {}      # species_id -> {count, best_len, first}
var fishing_xp: int = 0        # 钓鱼经验：升级鱼竿/装备的货币（取代金币）

# ----------------------------- 生命周期 ----------------------------------
func _ready() -> void:
	SaveManager.register(self)

func _process(delta: float) -> void:
	match state:
		State.CASTING:
			_cast_t -= delta
			if _cast_t <= 0.0:
				EventBus.fishing_cast.emit()
				state = State.WAITING
				_wait_t = randf_range(1.5, 3.5) / maxf(FishingGear.bite_rate(), 0.5)
				# 抛线离手 + 浮标入水（plop）
				AudioManager.play_sfx("line_out")
				AudioManager.play_sfx("plop")
		State.WAITING:
			_wait_t -= delta
			if _wait_t <= 0.0:
				_enter_bite()
		State.BITE:
			_bite_t -= delta
			# 双保险触发刺鱼：轮询左键按下（比仅依赖 _unhandled_input 更稳，避免输入被吞）
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_start_fight()
			elif _bite_t <= 0.0:
				_fail("鱼跑掉了……（鱼饵已消耗）", "plop")
		State.FIGHT:
			_tick_fight(delta)
		State.CAUGHT, State.ENDED:
			_end_t -= delta
			if _end_t <= 0.0 and state != State.IDLE:
				_finish_session()

func _unhandled_input(event) -> void:
	if state == State.BITE and event is InputEventMouseButton \
		and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_start_fight()

# ----------------------------- 开始 / 结束 ----------------------------------
## 供外部（钓点/UI）判断当前是否空闲，避免直接引用枚举（autoload 无 class_name）。
func is_idle() -> bool:
	return state == State.IDLE

## 浮标落点（世界坐标），供 player.gd 把浮标抛到真实水面。
func get_landing() -> Vector3:
	return _cast_landing

## 是否正处于张力博弈（收线）阶段。
func is_fighting() -> bool:
	return state == State.FIGHT

## 当前收线进度 0..1（供视图模型做收线动画）。
func get_progress() -> float:
	return _progress

## 在钓点开始一竿。override_habitat 可强制栖息地（如码头钓点传 "pier"）。
func begin(spot_pos: Vector3, override_habitat: String = "") -> void:
	if state != State.IDLE:
		return
	# 装备门槛：鱼竿（起始赠送）+ 鱼饵（采灌木得蚯蚓）
	if not Inventory.has("fishing_rod", 1):
		EventBus.toast.emit("钓鱼需要鱼竿（起始已赠送）")
		return
	if not Inventory.has("bait", 1):
		EventBus.toast.emit("钓鱼需要鱼饵（采集灌木可得蚯蚓）")
		return
	Inventory.consume("bait", 1)
	spot_position = spot_pos
	# 浮标落点落在真实水面（远离岛心=朝海），栖息地/水深按"落点"判定，
	# 这样抛得越远越能钓到礁区/深水鱼 —— 而非按你站的位置。
	_cast_landing = _compute_landing(spot_pos)
	var info := _detect_water(_cast_landing)
	if override_habitat != "":
		_habitat = override_habitat
	else:
		_habitat = info["habitat"]
	_depth = float(info["depth"])
	state = State.CASTING
	_cast_t = 0.8
	AudioManager.play_sfx("rod_swish")   # 挥竿
	EventBus.fishing_started.emit(spot_pos)
	EventBus.interactable_changed.emit("抛竿中……（静待鱼儿）")

## 强制第一人称由 player.gd 在 fishing_started/ended 时处理。

func _finish_session() -> void:
	state = State.IDLE
	_species = null
	_stop_fish_loops()
	EventBus.fishing_ended.emit()
	EventBus.interactable_changed.emit("")

# ----------------------------- 咬钩 ----------------------------------
func _enter_bite() -> void:
	var t01: float = GameManager.time_of_day
	var roll: Dictionary = FishDatabase.roll_bite(_habitat, _depth, t01, FishingGear)
	# 兜底：当前时段无匹配鱼种时，放宽时段限制（time01<0 表示忽略时段），保证一定有鱼可钓
	if roll.is_empty() or not roll.has("species"):
		roll = FishDatabase.roll_bite(_habitat, _depth, -1.0, FishingGear)
	if roll.is_empty() or not roll.has("species"):
		# 连放宽后都没有（极少见：该栖息地/水深无任何鱼种），回到等待稍后再试
		_wait_t = randf_range(2.0, 4.0)
		state = State.WAITING
		EventBus.toast.emit("水面平静……什么都没咬钩")
		return
	_species = roll["species"]
	_length_cm = float(roll["length_cm"])
	_weight_kg = _species.weight_kg(_length_cm)
	state = State.BITE
	_bite_t = 3.5   # 刺鱼窗口（秒），放宽以便玩家反应
	EventBus.fishing_bite.emit()
	AudioManager.play_sfx("fish_splash")   # 鱼炸水咬饵
	EventBus.interactable_changed.emit("鱼上钩了！按住左键刺鱼！")

# ----------------------------- 张力博弈 ----------------------------------
func _start_fight() -> void:
	if state != State.BITE or _species == null:
		return
	state = State.FIGHT
	_tension = 0.35
	_progress = 0.0
	_run_timer = randf_range(1.0, 2.0)
	_running = false
	_run_dur = 0.0
	_strain_played = false
	_fish_stamina = 1.0
	_exhausted = false
	_stop_fish_loops()
	var a := Vector3(spot_position.x, 0.0, spot_position.z)
	var b := Vector3(_cast_landing.x, 0.0, _cast_landing.z)
	_fight_dist0 = maxf(6.0, a.distance_to(b))
	EventBus.fishing_fight_started.emit(_catch_data())
	EventBus.fishing_tension.emit(_tension, _progress, _species.display_name)
	EventBus.fishing_fight_state.emit(_fight_state())
	EventBus.interactable_changed.emit("搏鱼中：按住左键收线，松开泄力，鱼冲刺时放手！")

func _tick_fight(delta: float) -> void:
	if _species == null:
		return
	var reeling: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	# 力竭后玩家输入不再生效（鱼已没劲，自动收线入护）
	var eff_reeling: bool = reeling and not _exhausted

	# 循环音效：收线(按住左键或力竭自动收线)播 reel_wind，鱼冲刺播 reel_drag（泄力摩擦声）
	AudioManager.set_loop("reel_wind", reeling or _exhausted)
	AudioManager.set_loop("reel_drag", _running and not _exhausted)
	# 张力跨入红区时播一次 line_strain（回落到绿区后允许再播）
	if _tension > 0.80 and not _strain_played:
		AudioManager.play_sfx("line_strain")
		_strain_played = true
	elif _tension < 0.6:
		_strain_played = false

	# 鱼冲刺调度：体力耗尽（力竭）则停止冲刺；冲刺时长随剩余体力缩短，鱼越累越难挣脱
	_run_timer -= delta
	if _run_timer <= 0.0 and _fish_stamina > 0.12:
		_running = true
		_run_dur = _species.fight_stamina * randf_range(0.3, 0.6) * clamp(_fish_stamina, 0.0, 1.0)
		_run_timer = randf_range(1.4, 2.8)
	if _running:
		_run_dur -= delta
		if _run_dur <= 0.0:
			_running = false

	# 张力动力学
	# 设计目标（对标 Tidewater 绿区博弈、且公平）：
	#  - 收线时张力平稳上升；松开时明显回落（不至于一松手还涨）。
	#  - 鱼冲刺时张力被推高 → 必须松开左键泄力；松开后的回落速度要盖过冲刺推升，
	#    这样"看到红就松手"真的能救回来。
	#  - 力竭后鱼不再挣扎，张力自然回落（不会断线）。
	var dT: float = 0.0
	if eff_reeling:
		dT += 0.46 * FishingGear.reel_power() * FishingGear.tension_assist()
		dT -= 0.06
	else:
		dT -= 0.45
	if _running:
		# 冲刺推升随鱼的挣扎力与剩余体力放大，但系数已调低，保证"松开即回落"
		dT += _species.fight_pull * (0.20 + 0.30 * _fish_stamina)
	_tension = clamp(_tension + dT * delta, 0.0, 1.0)

	# 鱼的体力：收线时被消耗（变"累"），冲刺时也掉，歇息时回复；
	# 体力越低，冲刺越弱 → 长时间拉锯后鱼会被拖累，符合真实搏鱼手感。
	# 力竭后体力锁定为 0，不再消耗/回复。
	if _exhausted:
		_fish_stamina = 0.0
	elif eff_reeling:
		_fish_stamina -= 0.06 * FishingGear.reel_power() * delta
	elif _running:
		_fish_stamina -= 0.02 * delta
	else:
		_fish_stamina += 0.035 * delta
	_fish_stamina = clamp(_fish_stamina, 0.0, 1.0)
	# 力竭触发：体力归零立即进入自动收线状态（无需玩家操作，直接入护）
	if _fish_stamina <= 0.001 and not _exhausted:
		_exhausted = true
		_running = false

	# 进度：收线且鱼未冲刺时前进；否则停滞/倒退。
	# 力竭后自动快速收线（鱼已没劲），玩家不用再按住左键。
	if _exhausted:
		_progress += 1.2 * delta
	elif eff_reeling:
		_progress += 0.28 * FishingGear.reel_power() * delta
	else:
		_progress -= 0.05 * delta
	_progress = clamp(_progress, 0.0, 1.0)

	EventBus.fishing_tension.emit(_tension, _progress, _species.display_name)
	EventBus.fishing_fight_state.emit(_fight_state())

	if _tension >= FishingGear.break_threshold():
		_fail("线断了！（张力过大）", "line_snap")
		return
	if _progress >= 1.0:
		_succeed()

# ----------------------------- 结算 ----------------------------------
func _succeed() -> void:
	var id: String = "fish_" + _species.id
	# 渔获直接进玩家背包（随身鱼篓；容量见 cooler_capacity，满则提示升级冷藏箱）
	Inventory.add_item(id, 1)
	_record_log(_species.id, _length_cm)
	var xp := _xp_reward()
	add_xp(xp)
	var cap: int = FishingGear.cooler_capacity()
	if cooler_count() > cap:
		EventBus.toast.emit("背包鱼篓已满（容量 %d），升级冷藏箱扩充" % cap)
	EventBus.fishing_caught.emit(id, 1)
	EventBus.fishing_result.emit(true)
	_stop_fish_loops()
	AudioManager.play_sfx("fish_flop")   # 鱼在甲板拍跳
	EventBus.fishing_catch_card.emit(_catch_data())
	EventBus.fishing_log_updated.emit()
	EventBus.toast.emit("钓到 %s！体长 %.0fcm / %.2fkg（+%d 钓鱼经验）" % [_species.display_name, _length_cm, _weight_kg, xp])
	state = State.CAUGHT
	_end_t = 2.6   # 展示入护卡后自动收竿

## 钓到鱼给的钓鱼经验（价值 + 体长 综合）
func _xp_reward() -> int:
	return int(round(_species.value * 0.5 + _length_cm * 0.1))

func add_xp(n: int) -> void:
	fishing_xp = maxi(0, fishing_xp + n)
	EventBus.fishing_xp_changed.emit(fishing_xp)

func spend_xp(n: int) -> bool:
	if fishing_xp < n:
		return false
	fishing_xp -= n
	EventBus.fishing_xp_changed.emit(fishing_xp)
	return true

func _fail(msg: String, sound: String = "") -> void:
	EventBus.fishing_result.emit(false)
	EventBus.toast.emit(msg)
	_stop_fish_loops()
	if sound != "":
		AudioManager.play_sfx(sound)
	state = State.ENDED
	_end_t = 0.6

## 统一停止搏鱼循环音（收线/泄力），并复位红区去抖标记。
func _stop_fish_loops() -> void:
	AudioManager.set_loop("reel_wind", false)
	AudioManager.set_loop("reel_drag", false)
	_strain_played = false

func _catch_data() -> Dictionary:
	if _species == null:
		return {}
	return {
		"species": _species.id,
		"name": _species.display_name,
		"length_cm": _length_cm,
		"weight_kg": _weight_kg,
		"value": _species.value,
		"tint": _species.tint,
		"xp": _xp_reward(),
	}

## 搏鱼时"鱼的状态"快照：驱动 UI 的"拉力对决"面板（鱼名/体长/体重/离竿距离/冲刺/体力）。
func _fight_state() -> Dictionary:
	if _species == null:
		return {}
	var dist: float = _fight_dist0 * (1.0 - _progress)
	return {
		"name": _species.display_name,
		"length_m": _length_cm / 100.0,
		"weight_kg": _weight_kg,
		"distance_m": maxf(0.0, dist),
		"running": _running,
		"exhausted": _exhausted,
		"stamina": _fish_stamina,
		"habitat": _habitat,
		"progress": _progress,
	}

func _record_log(sp_id: String, len: float) -> void:
	if not _log.has(sp_id):
		_log[sp_id] = {"count": 0, "best_len": 0.0, "first": true}
	var e: Dictionary = _log[sp_id]
	e["count"] = int(e["count"]) + 1
	if len > float(e["best_len"]):
		e["best_len"] = len
	e["first"] = false

# ----------------------------- 图鉴查询 ----------------------------------
func log_entry(sp_id: String) -> Dictionary:
	if _log.has(sp_id):
		return _log[sp_id]
	return {}

func total_caught() -> int:
	var n: int = 0
	for e in _log.values():
		n += int(e["count"])
	return n

func cooler_count() -> int:
	# 背包里 fish_* 的总数（随身鱼篓容量见 cooler_capacity）
	var n := 0
	for fid in Inventory.items:
		if str(fid).begins_with("fish_"):
			n += int(Inventory.items[fid])
	return n

# ----------------------------- 存档 ----------------------------------
func save_id() -> String:
	return "fishing_log"

func save() -> Dictionary:
	return {"log": _log, "xp": fishing_xp}

func load(d: Dictionary) -> void:
	if d.is_empty():
		return
	if d.has("log"):
		_log = d["log"]
	fishing_xp = int(d.get("xp", 0))

# ----------------------------- 抛投落点 ----------------------------------
## 计算浮标落点：以岛心为原点，钓点大致在 r≈159 的环海岸上，
## 朝岛外法线(spot_pos.normalized())即朝海方向甩出；距离基础 14m + 竿等级加成，
## 若落点仍在陆地则逐段外推直到进入水面，保证浮标一定落进海里。
func _compute_landing(spot_pos: Vector3) -> Vector3:
	var sea := Vector3(spot_pos.x, 0.0, spot_pos.z)
	if sea.length_squared() < 0.01:
		sea = Vector3(0, 0, -1)
	sea = sea.normalized()
	var dist: float = 16.0 + 6.0 * float(FishingGear.rod_level)
	var land := Vector3(spot_pos.x + sea.x * dist, 0.0, spot_pos.z + sea.z * dist)
	var w = GameManager.world
	var tries := 0
	while w != null and float(w.get_ground_height(land.x, land.z)) >= 0.0 and tries < 16:
		dist += 2.0
		land = Vector3(spot_pos.x + sea.x * dist, 0.0, spot_pos.z + sea.z * dist)
		tries += 1
	if w != null:
		var gh := float(w.get_ground_height(land.x, land.z))
		if gh < 0.0:
			land.y = 0.0
		else:
			land.y = gh + 0.06
	else:
		land.y = 0.0
	return land

# ----------------------------- 栖息地/水深检测 ----------------------------------
## 本作地形是 world.gd 的高度图 Mesh（非 Terrain3D），用 GameManager.world.get_ground_height 取真实高度。
## 水深 = SEA_LEVEL - 地面高度；离岸距离 = 8 方向采样直到地面高度高于海平面。
func _detect_water(pos: Vector3) -> Dictionary:
	var w = GameManager.world
	if w == null:
		return {"habitat": FishSpecies.H_SHALLOWS, "depth": 1.0}
	var h: float = float(w.get_ground_height(pos.x, pos.z))
	var depth: float = SEA_LEVEL - h
	if depth <= 0.0:
		depth = 0.2
	# 离岸距离：8 方向采样直到地面高度高于海平面
	var shore: float = 120.0
	for i: int in 8:
		var ang: float = float(i) / 8.0 * TAU
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		for r: int in range(2, 120, 4):
			var sp := pos + dir * float(r)
			if float(w.get_ground_height(sp.x, sp.z)) > SEA_LEVEL + 0.1:
				shore = float(r)
				break
	return {"habitat": _classify(depth, shore), "depth": depth}

func _classify(depth: float, shore: float) -> String:
	if depth < 1.5 and shore < 12.0:
		return FishSpecies.H_SHALLOWS
	if shore < 15.0 and depth < 5.0:
		return FishSpecies.H_BAY
	if depth >= 2.0 and depth <= 20.0 and shore < 70.0:
		return FishSpecies.H_REEF
	if depth > 8.0 or shore > 90.0:
		return FishSpecies.H_DEEP
	return FishSpecies.H_BAY

func maxf(a: float, b: float) -> float:
	if a > b:
		return a
	return b
