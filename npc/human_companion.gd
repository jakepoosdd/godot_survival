extends CharacterBody3D
class_name HumanCompanion
const HealthBarScript := preload("res://ui/health_bar.gd")
const WeaponMountScript := preload("res://core/weapon_mount.gd")

## 各伙伴默认手持武器（运行时挂到右手，替代烘焙进 GLB 的武器）。
## 空串 = 不挂武器。
const WEAPON_BY_CHAR := {
	"kachujin": "sword",
}
## 可指挥的人类伙伴（男主下令：采集食物 / 自己去战斗 / 跟随自己战斗 / 召集回来）。
## 复用 CharacterRegistry 里已绑定好的 GLB 可视体 + 动画映射；行为状态机参考 spirit_companion.gd。
## 敌人现在也会把附近伙伴当目标（见 enemy.gd），故伙伴可被攻击、可被打死；死亡后自动回营地躺着，
## 直到女主好感满后通过交互菜单复活（revive_now）。

const SPEED := 5.4
const ATTACK_ANIM_TIME := 0.5
# 每人每天对营地仓库的贡献上限（采集 + 猎获战利品共享，防止挂机刷资源）。
# 一天 = real_seconds_per_game_hour(30) × 24 = 720 秒 ≈ 12 分钟；采集 7 秒一份、约 1-2 个，
# 连续采集约 3 分钟即触顶，留足余量又限制 AFK 刷量。集中于一处方便调参。
const DAILY_CAP := 40.0

# 各伙伴战斗属性（远程用更大的 range / detect）
const STATS := {
	"maria":    {"speed": 6.0, "dmg": 16.0, "range": 2.3,  "detect": 16.0, "interval": 1.1, "hp": 140.0, "attack_style": "melee"},
	"erika":    {"speed": 6.5, "dmg": 13.0, "range": 12.0, "detect": 22.0, "interval": 1.3, "hp": 110.0, "attack_style": "arrow"},
	"arissa":   {"speed": 5.8, "dmg": 15.0, "range": 10.0, "detect": 20.0, "interval": 1.4, "hp": 100.0, "attack_style": "magic",
	             "can_heal": true, "heal_amount": 18.0, "heal_cd": 6.0, "heal_threshold": 0.6},
	"kachujin": {"speed": 6.2, "dmg": 20.0, "range": 2.5,  "detect": 16.0, "interval": 1.0, "hp": 160.0, "attack_style": "melee"},
	"ch46":     {"speed": 6.8, "dmg": 11.0, "range": 2.1,  "detect": 14.0, "interval": 0.9, "hp": 90.0, "attack_style": "melee"},
}

var char_id: String = ""
var char_name: String = "伙伴"

var body_mesh: Node3D = null
var anim: AnimationPlayer = null
var anim_map: Dictionary = {}
var _yaw_offset: float = 0.0

var command_mode: String = "idle"      # idle | follow | fight | gather | return

var max_hp: float = 120.0
var hp: float = 120.0
var is_dead: bool = false       # 真实死亡（躺着），区别于可行动的指令状态
var _daily_contrib := 0.0        # 今日已贡献进营地仓库的数量（采集 + 猎获共享），满 DAILY_CAP 即停

var _speed: float = SPEED
var _base_walk: float = 1.2    # 实测无滑步脚速（GLB 的 Walk_Loop 在 speed_scale=1.0 时的脚速），脚锁缩放用
var _base_run: float = 3.0     # 同上，Sprint_Loop
var _dmg: float = 14.0
var _range: float = 2.3
var _detect: float = 16.0
var _interval: float = 1.1
var _attack_style: String = "melee"
var _can_heal: bool = false
var _heal_amount: float = 0.0
var _heal_cd: float = 6.0
var _heal_threshold: float = 0.6
var _heal_timer: float = 0.0

var _attack_cd: float = 0.0
var _atk_anim_t: float = 0.0
var _harvest_cd: float = 6.0
# 基准属性（缩放前，从 STATS 读取，不随等级变化）：用于按玩家等级统一缩放
var _base_dmg: float = 14.0
var _base_hp: float = 120.0
var _base_heal: float = 0.0
var _wander_t: float = 0.0
var _wander_dir: Vector3 = Vector3.ZERO
var _t: float = 0.0
var _dt: float = 0.0

var _mount = null   # WeaponMount 实例（手持武器挂载）

func _ready() -> void:
	add_to_group("companion")
	_apply_stats()
	_build_visual()
	_setup_health_bar()
	if PartyManager != null:
		PartyManager.register(self)
	if EventBus != null:
		EventBus.day_changed.connect(_on_day_changed)
		EventBus.leveled_up.connect(_on_leveled_up)

## 头顶血条（默认满血；受伤实时更新，死亡时隐藏，复活后恢复）。
func _setup_health_bar() -> void:
	var hb := HealthBarScript.new()
	hb.name = "HealthBar"
	add_child(hb)
	hb.position = Vector3(0, 2.3, 0)
	hb.set_fraction(hp / max_hp)
	_hp_bar = hb

var _hp_bar: Node = null

func _apply_stats() -> void:
	var s: Dictionary = STATS.get(char_id, {})
	_speed = s.get("speed", SPEED)
	_base_dmg = s.get("dmg", 14.0)
	_range = s.get("range", 2.3)
	_detect = s.get("detect", 16.0)
	_interval = s.get("interval", 1.1)
	_base_hp = s.get("hp", 120.0)
	_attack_style = s.get("attack_style", "melee")
	_can_heal = s.get("can_heal", false)
	_base_heal = s.get("heal_amount", 0.0)
	_heal_cd = s.get("heal_cd", 6.0)
	_heal_threshold = s.get("heal_threshold", 0.6)
	_heal_timer = 0.0
	_rescale(false)

## 伙伴随玩家等级缩放系数：让「伙伴升级」真正有意义（玩家本身不靠升级变强，战力成长走伙伴+形态）。
func _comp_mult() -> float:
	var lvl := 1
	if XP != null:
		lvl = XP.level
	return 1.0 + 0.04 * maxf(0.0, float(lvl) - 1.0)

## 按玩家等级缩放属性。keep_ratio=true 时（升级瞬间）保留当前血量比例，避免回满或溢出。
func _rescale(keep_ratio := false) -> void:
	var ratio := 1.0
	if keep_ratio and max_hp > 0.0:
		ratio = hp / max_hp
	var m := _comp_mult()
	_dmg = _base_dmg * m
	max_hp = _base_hp * m
	_heal_amount = _base_heal * m
	hp = clampf(max_hp * ratio, 0.0, max_hp)
	if _hp_bar != null:
		_hp_bar.set_fraction(hp / max_hp)

## 玩家升级：伙伴随之变强（按比例保留当前血量）。
func _on_leveled_up(_lvl: int) -> void:
	if is_dead:
		return
	_rescale(true)

func _build_visual() -> void:
	var def: Dictionary = {}
	if CharacterRegistry != null:
		def = CharacterRegistry.find_by_id(char_id)
	# 实测脚速（GLB 动画在 speed_scale=1.0 时的无滑步脚速），供脚锁缩放用。
	_base_walk = float(def.get("walk_speed", 1.2))
	_base_run = float(def.get("run_speed", 3.0))
	if def.is_empty():
		# 兜底胶囊：保证工程始终能跑
		body_mesh = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.height = 1.7; cyl.top_radius = 0.35; cyl.bottom_radius = 0.35
		body_mesh.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.7, 0.5)
		body_mesh.material_override = mat
		body_mesh.position = Vector3(0, 0.9, 0)
		add_child(body_mesh)
		anim_map = {}
	else:
		var root: Node = null
		if def.has("packed"):
			root = def["packed"].instantiate()
		elif def.has("scene_path"):
			var sc = load(def["scene_path"])
			if sc != null:
				root = sc.instantiate()
		if root != null:
			if root is Node3D:
				body_mesh = root
			else:
				var wrap := Node3D.new()
				wrap.add_child(root)
				body_mesh = wrap
			body_mesh.name = "BodyVisual"
			add_child(body_mesh)
			body_mesh.scale = Vector3.ONE * float(def.get("scale", 1.0))
			body_mesh.position.y = float(def.get("y_offset", 0.0))
			_yaw_offset = float(def.get("yaw_offset", 0.0))
		anim = _find_anim_player(body_mesh)
		# 用「真实存在的动画名」解析一遍：GLB 重导出后带不带 _Loop 后缀都能对上
		anim_map = def["anim"]
		if CharacterRegistry != null and anim != null:
			anim_map = CharacterRegistry.resolve_anim_map(anim, def["anim"])
		if anim != null:
				var idle: String = anim_map.get("idle", "")
				if idle != "" and anim.has_animation(idle):
					anim.play(idle)
			# 运行时挂载手持武器（覆盖 GLB 里烘焙的武器，避免 Mixamo 重定位踩坑）
		if WEAPON_BY_CHAR.has(char_id):
			_bind_weapon_mount(WEAPON_BY_CHAR[char_id])
	# 碰撞胶囊：直接挂到自身（CharacterBody3D 才是 CollisionObject3D）。
	# 把自身 collision_mask 置 0，使其不与世界/玩家互相碰撞（我们手动贴地，无需物理碰撞）。
	collision_mask = 0
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4; cap.height = 1.6
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	add_child(col)

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null

## 运行时武器挂载：把武器模型挂到右手骨（BoneAttachment3D -> 掌心 PalmPoint），
## 并隐藏 GLB 里烘焙的同类武器（Kachujin 的 "Kachujin_Axe"）。
func _bind_weapon_mount(item_id: String) -> void:
	if item_id == "":
		return
	if _mount == null:
		_mount = WeaponMountScript.new()
	elif is_instance_valid(_mount) and _mount.is_bound():
		_mount.clear()
	if body_mesh == null:
		return
	if not _mount.bind(body_mesh):
		push_warning("[HumanCompanion] %s 无 Skeleton3D，跳过手持武器挂载" % char_id)
		return
	_hide_baked_axe()
	_mount.equip(item_id)

## 隐藏 Kachujin_Axe.glb 里烘焙进右手骨的斧头（"Skeleton3D > mixamorig_RightHand
## (BoneAttachment3D) > Kachujin_Axe (MeshInstance3D)"），避免与运行时挂载的斧头重叠。
func _hide_baked_axe() -> void:
	if body_mesh == null:
		return
	var baked := _find_named(body_mesh, "Kachujin_Axe")
	if baked != null and baked is Node3D:
		(baked as Node3D).visible = false

func _find_named(node: Node, name_want: String) -> Node:
	if node.name == name_want:
		return node
	for c in node.get_children():
		var r := _find_named(c, name_want)
		if r != null:
			return r
	return null

## 男主/队伍下发的指令。return 是一次性召回（传送到玩家身边并转为 idle）。
func command(mode: String) -> void:
	if is_dead:
		return   # 死亡（躺着）期间不响应任何指令（召集也不会唤醒）
	if mode == "return":
		_return_to_player()
		return
	command_mode = mode

func _return_to_player() -> void:
	var p = GameManager.player
	if p != null:
		var ang := randf() * TAU
		var off := Vector3(cos(ang) * 2.5, 0.0, sin(ang) * 2.5)
		global_position = p.global_position + off
		var gy: float = _ground_height(global_position.x, global_position.z)
		global_position.y = gy + 0.2
	command_mode = "idle"

func _physics_process(delta: float) -> void:
	_dt = delta
	_t += delta
	if is_dead:
		_stick_camp()
		return
	if _attack_cd > 0.0: _attack_cd -= delta
	if _atk_anim_t > 0.0: _atk_anim_t -= delta
	if _harvest_cd > 0.0: _harvest_cd -= delta
	if not is_dead:
		_heal_think(delta)

	match command_mode:
		"idle":    _idle_step()
		"follow":  _follow_step()
		"fight":   _fight_step()
		"gather":  _gather_step()
		"return":  _idle_step()   # return 已在 command() 里完成传送，这里待命

	var gy: float = _ground_height(global_position.x, global_position.z)
	velocity.y = 0.0
	move_and_slide()
	global_position.y = gy + 0.05
	_update_anim()

func _idle_step() -> void:
	# 附近有敌人则自动进入战斗反击（避免发呆挨打）
	if _nearest_enemy(_detect) != null:
		command_mode = "fight"
		return
	velocity = Vector3.ZERO

func _follow_step() -> void:
	var enemy = _nearest_enemy(_detect)
	if enemy != null:
		_combat_move(enemy)
		return
	var p = GameManager.player
	if p != null:
		_move_toward(p.global_position, _speed, 3.2)
	else:
		velocity = Vector3.ZERO

func _fight_step() -> void:
	var enemy = _nearest_enemy(maxf(_detect, 40.0))
	if enemy != null:
		_combat_move(enemy)
		return
	_wander()

func _gather_step() -> void:
	if _harvest_cd <= 0.0:
		_harvest_cd = 7.0
		_deliver_harvest()
	var p = GameManager.player
	if p != null:
		_wander_around(p.global_position, 10.0)
	else:
		velocity = Vector3.ZERO

## 朝敌人移动；进入攻击距离则停下攻击。
func _combat_move(enemy: Node3D) -> void:
	var to: Vector3 = enemy.global_position - global_position
	to.y = 0.0
	var d: float = to.length()
	if d > _range:
		_move_toward(enemy.global_position, _speed, 0.0)
	else:
		velocity = Vector3.ZERO
		_face(to)
		if _attack_cd <= 0.0:
			_attack(enemy)

func _move_toward(target_pos: Vector3, spd: float, stop_dist: float) -> void:
	var to: Vector3 = target_pos - global_position
	to.y = 0.0
	var d: float = to.length()
	if d > stop_dist + 0.05:
		var dir: Vector3 = to.normalized()
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
		_face(dir)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

func _wander() -> void:
	_wander_t -= _dt
	if _wander_t <= 0.0:
		_wander_t = randf_range(1.5, 3.5)
		var ang := randf() * TAU
		_wander_dir = Vector3(cos(ang), 0.0, sin(ang))
	velocity.x = _wander_dir.x * _speed * 0.5
	velocity.z = _wander_dir.z * _speed * 0.5
	_face(_wander_dir)

func _wander_around(center: Vector3, radius: float) -> void:
	var to: Vector3 = center - global_position
	to.y = 0.0
	if to.length() > radius:
		_move_toward(center, _speed * 0.5, radius * 0.8)
	else:
		_wander()

func _attack(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
		return
	_attack_cd = _interval
	var atks: Array = anim_map.get("attack", [])
	if not atks.is_empty():
		var nm: String = atks[randi() % atks.size()]
		if anim != null and anim.has_animation(nm):
			anim.play(nm, 0.1)
			# 按动画实际长度保护，避免挥到一半被 _update_anim 切回待机
			var len := ATTACK_ANIM_TIME
			var alen := anim.get_animation(nm).length
			if alen > len:
				len = alen
			_atk_anim_t = len
	if _attack_style == "magic":
		var from := global_position + Vector3(0, 1.4, 0)
		var to := enemy.global_position + Vector3(0, 1.0, 0)
		SpellVfx.magic_bolt(from, to, SpellVfx.MAGIC_COLOR, func():
			if is_instance_valid(enemy):
				enemy.take_damage(_dmg, self)
				EventBus.damage_popup.emit(enemy.global_position + Vector3(0, 2.4, 0), _dmg, "enemy")
		)
	elif _attack_style == "arrow":
		var from := global_position + Vector3(0, 1.4, 0)
		var to := enemy.global_position + Vector3(0, 1.0, 0)
		SpellVfx.arrow_shot(from, to, func():
			if is_instance_valid(enemy):
				enemy.take_damage(_dmg, self)
				EventBus.damage_popup.emit(enemy.global_position + Vector3(0, 2.4, 0), _dmg, "enemy")
		)
	else:
		enemy.take_damage(_dmg, self)
		EventBus.damage_popup.emit(enemy.global_position + Vector3(0, 2.4, 0), _dmg, "enemy")

func _heal_think(delta: float) -> void:
	if not _can_heal or is_dead:
		return
	_heal_timer -= delta
	if _heal_timer > 0.0:
		return
	var targets: Array = []
	if is_instance_valid(GameManager.player):
		targets.append(GameManager.player)
	for c in get_tree().get_nodes_in_group("companion"):
		if c != self and is_instance_valid(c) and not bool(c.get("is_dead")):
			targets.append(c)
	var best: Node = null
	var best_ratio := _heal_threshold
	for t in targets:
		var r := _hp_ratio(t)
		if r < best_ratio:
			best_ratio = r
			best = t
	if best == null:
		return
	_heal_timer = _heal_cd
	var cast_anim: String = anim_map.get("cast", "")
	if cast_anim != "" and anim != null and anim.has_animation(cast_anim):
		anim.play(cast_anim, 0.1)
	SpellVfx.heal_burst(best, SpellVfx.HEAL_COLOR, _heal_amount)
	_apply_heal(best, _heal_amount)

func _hp_ratio(t: Node) -> float:
	if t == GameManager.player:
		var ns: Node = GameManager.player.get_node_or_null("NeedsSystem")
		if ns != null and "health" in ns:
			return float(ns.health) / float(ns.max_health)
		return 1.0
	if t.has_method("heal"):
		return float(t.hp) / float(t.max_hp)
	return 1.0

func _apply_heal(t: Node, amount: float) -> void:
	if t == GameManager.player:
		var ns: Node = GameManager.player.get_node_or_null("NeedsSystem")
		if ns != null and ns.has_method("apply_effects"):
			ns.apply_effects(amount, 0.0, 0.0)
	elif t.has_method("heal"):
		t.heal(amount)

func heal(amount: float) -> void:
	if is_dead:
		return
	hp = minf(max_hp, hp + amount)
	if _hp_bar != null:
		_hp_bar.set_fraction(hp / max_hp)

func _nearest_enemy(detect: float) -> Node3D:
	var best: Node = null
	var best_d := detect
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == null or not is_instance_valid(e):
			continue
		if bool(e.get("dead")):
			continue
		var d := global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

## 采集型：周期把食物送进营地仓库（计入每日贡献上限）。
func _deliver_harvest() -> void:
	var pool: PackedStringArray = ["berry", "rawmeat", "cookedmeat", "bait"]
	var id := pool[randi() % pool.size()]
	var amt := randi_range(1, 2)
	var give := _contribute(id, amt)
	if give <= 0:
		EventBus.toast.emit("%s 今日贡献已达上限（%d），先收手了" % [char_name, int(DAILY_CAP)])
		return
	CampStorage.add_item(id, give)
	var it: ItemResource = ItemDatabase.get_item(id)
	var nm: String = it.display_name if it != null else id
	EventBus.toast.emit("%s 采集到 %s ×%d，存入营地仓库（今日 %d/%d）" % [char_name, nm, give, int(_daily_contrib), int(DAILY_CAP)])

## 战利品入库入口（由 GameManager 在伙伴击杀怪物时调用）。
## 与采集共享同一每日上限；超限部分作废并提示。
func contribute_loot(drops: Dictionary) -> void:
	if drops == null or drops.is_empty():
		return
	var parts: Array[String] = []
	var capped_full := false
	for id in drops:
		var n: int = int(drops[id])
		if n <= 0:
			continue
		var give := _contribute(id, n)
		if give <= 0:
			capped_full = true
			continue
		CampStorage.add_item(id, give)
		var it: ItemResource = ItemDatabase.get_item(id)
		var nm: String = it.display_name if it != null else id
		parts.append("%s×%d" % [nm, give])
	if capped_full:
		EventBus.toast.emit("%s 今日贡献已达上限（%d），多余战利品作废" % [char_name, int(DAILY_CAP)])
	if not parts.is_empty():
		EventBus.toast.emit("%s 猎获 %s，存入营地仓库（今日 %d/%d）" % [char_name, ", ".join(parts), int(_daily_contrib), int(DAILY_CAP)])

## 计算本次可入库数量：受每日上限剩余量限制，并返回实际入库数（0 = 已满）。
func _contribute(id: String, amt: int) -> int:
	if amt <= 0:
		return 0
	var remain := DAILY_CAP - _daily_contrib
	if remain <= 0.0:
		return 0
	var give := int(minf(float(amt), remain))
	_daily_contrib += float(give)
	return give

## 跨日重置每日贡献计数。
func _on_day_changed(_day: int) -> void:
	_daily_contrib = 0.0

func _face(v: Vector3) -> void:
	if body_mesh == null or v.length_squared() < 1e-4:
		return
	var yaw := atan2(v.x, v.z) + _yaw_offset
	body_mesh.rotation.y = lerp_angle(body_mesh.rotation.y, yaw, 0.2)

func _update_anim() -> void:
	if anim == null or anim_map.is_empty():
		return
	# 攻击/施法动画保持原速播放，不被脚锁缩放影响
	if _atk_anim_t > 0.0:
		anim.speed_scale = 1.0
		return
	var spd := Vector2(velocity.x, velocity.z).length()
	var want: String
	if spd > 0.6:
		want = anim_map.get("run", "") if spd > 4.5 else anim_map.get("walk", "")
	else:
		want = anim_map.get("idle", "")
	if want != "" and anim.has_animation(want) and anim.current_animation != want:
		anim.play(want, 0.15)
	# 脚锁：按当前动画实测脚速缩放播放速率，移动更快也不滑步；非步态动画(待机/坠落)保持原速
	var walk_name: String = anim_map.get("walk", "")
	var run_name: String = anim_map.get("run", "")
	if want == run_name and run_name != "":
		anim.speed_scale = clampf(spd / maxf(_base_run, 0.001), 0.5, 3.0)
	elif want == walk_name and walk_name != "":
		anim.speed_scale = clampf(spd / maxf(_base_walk, 0.001), 0.5, 3.0)
	else:
		anim.speed_scale = 1.0

func _ground_height(x: float, z: float) -> float:
	if GameManager.world != null and GameManager.world.has_method("get_ground_height"):
		return float(GameManager.world.call("get_ground_height", x, z))
	return 0.0

## 受伤：扣血 + 更新血条；归零则进入死亡（回营地躺着）。
func take_damage(dmg: float) -> void:
	if is_dead:
		return
	# 被攻击即反击（不再发呆挨打）：切到战斗模式追敌
	if command_mode != "fight":
		command_mode = "fight"
	hp -= dmg
	if hp < 0.0:
		hp = 0.0
	if _hp_bar != null:
		_hp_bar.set_fraction(hp / max_hp)
	if hp <= 0.0:
		die()

## 死亡：被打死 -> 自动回到营地躺着（永久死亡，直到女主好感满后复活）。
func die() -> void:
	set_dead_state()
	EventBus.toast.emit("%s 倒下了……" % char_name)

## 仅置死亡状态（不弹提示），供读档恢复使用。
func set_dead_state() -> void:
	is_dead = true
	command_mode = "dead"
	if _hp_bar != null:
		_hp_bar.visible = false
	var die_anim: String = anim_map.get("die", "")
	if anim != null and die_anim != "" and anim.has_animation(die_anim):
		anim.play(die_anim, 0.1)
	# 回到营地躺着
	var cc: Vector2 = GameManager.camp_center
	var ang := randf() * TAU
	var off := Vector3(cos(ang) * 2.5, 0.0, sin(ang) * 2.5)
	global_position = Vector3(cc.x, 0.0, cc.y) + off
	var gy: float = _ground_height(global_position.x, global_position.z)
	global_position.y = gy + 0.05

## 复活：女主好感满后通过交互菜单唤醒，复活后恢复行动、可被召集 / 互动。
func revive_now() -> void:
	is_dead = false
	hp = max_hp
	if _hp_bar != null:
		_hp_bar.visible = true
		_hp_bar.set_fraction(1.0)
	command_mode = "idle"
	var idle: String = anim_map.get("idle", "")
	if anim != null and idle != "" and anim.has_animation(idle):
		anim.play(idle, 0.1)
	var p = GameManager.player
	if p != null:
		global_position = p.global_position + Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
		var gy: float = _ground_height(global_position.x, global_position.z)
		global_position.y = gy + 0.2

## 死亡期间固定在营地地面（躺着），不移动、不更新动画（保持死亡姿势）。
func _stick_camp() -> void:
	velocity = Vector3.ZERO
	var gy: float = _ground_height(global_position.x, global_position.z)
	global_position.y = gy + 0.05

