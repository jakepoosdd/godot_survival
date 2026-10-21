extends CharacterBody3D
## 第三人称角色控制器（Layer 1 核心）。
## 自带：碰撞体、可视体(RPG 角色动画)、相机支架、需求系统、交互系统。
## 可视体优先用 RPG_Character.glb（explosive-llc RPG Animations，64 段人形动画，含完整动作 RPG 套件）；
## 若 GLB 未导入/加载失败，回退到胶囊体，保证工程始终能跑。

const SPEED_MULT := 1.6     # 行走/冲刺整体倍率（用户反馈偏慢）；同步缩放动画播放速率保持脚锁不滑步
var speed := 1.2           # 行走速度，由角色注册表按实测脚速*SPEED_MULT 覆盖（见 _build_visual）
var sprint_speed := 3.0     # 冲刺速度，同上；运行时至少为 walk_speed，避免冲刺反而更慢
var base_walk := 1.2        # 实测无滑步脚速（未乘倍率），脚锁缩放用
var base_run := 3.0         # 同上，run
var jump_velocity := 4.5
var gravity := 14.0
var mouse_sensitivity := 0.0015   # 鼠标转视角灵敏度（用户反馈偏高，0.0025→0.0015）
var is_sprinting := false

var yaw := 0.0
var pitch := 0.3

var cam_pivot: Node3D
var camera: Camera3D
var body_mesh: Node3D            # 可视体根节点（GLB 或胶囊）
var anim: AnimationPlayer = null # GLB 内的动画播放器
var attacking := false           # 是否正在播放一次性攻击动画

# —— 魔法师治疗（Arissa）：准星选人 + R 键施放 ——
var _is_mage := false              # 所选角色是否为魔法师：是则可施放治疗
var heal_range := 14.0             # 治疗射线最大距离（准星选人）
var heal_amount := 70.0            # 单次治疗量
var heal_cooldown := 2.5           # 治疗冷却（秒）
var _heal_cd := 0.0                # 当前冷却剩余
var _casting := false              # 正在播施法动画（阻止 _update_anim 覆盖）
var _cast_timer := 0.0             # 施法动画兜底计时（防 animation_finished 未触发）
var _heal_particle_tex: Texture2D = null  # 治疗粒子柔光圆点贴图（按需生成并缓存）
var _combo := 0                 # 攻击连段步数 0/1/2
var _combo_timer := 0.0         # 连段窗口计时
var first_person := false       # 第一人称模式（V 键切换）
var fishing := false            # 是否正在钓鱼（锁定移动，播放鱼竿动作）
var _fp_before_fishing: bool = false   # 钓鱼前是否第一人称（结束后还原）
var _rod = null                  # 手持鱼竿模型（FishingRod 实例；钓鱼时显示，挂相机上）
var _cast_bobber: Node3D = null       # 世界空间浮标（抛出去落在水面上）
var _cast_line: MeshInstance3D = null # 世界空间鱼线（竿尖 → 浮标，每帧重算）
var _fish_landing := Vector3.ZERO     # 本竿抛投落点
var _fish_face_target := 0.0     # 钓鱼时面朝钓点的目标朝向
var anim_map: Dictionary = {}    # 当前角色的动画名映射（按角色切换）
var _char_index := 0             # 当前角色索引（由 CharacterRegistry 决定，支持 MOD 切换）
## 手中武器挂点：加武器 = 改 core/weapon_mount.gd 的 WEAPON_TABLE（纯数据表）；
## 换武器 = Equipment 快捷栏 1~6 键 / 滚轮，equipped_changed 信号驱动这里实时换模型。
var _mount = null                # core/weapon_mount.gd 实例（运行时武器挂点）
var attack_reach := 2.8         # 近战命中半径（米）
var attack_damage := 25.0        # 单次攻击对敌人的伤害
var _facing_dir := Vector3(0, 0, -1)  # 当前朝向（世界空间，用于攻击方向判定）

## 角色定义（含内置角色与外部 MOD）统一由 core/character_registry.gd 管理；
## player 只通过 CharacterRegistry.get_character(index) 取可视体来源与动画映射。
## 加新可玩角色：往注册表的 BUILTIN 加一条，或在 user://mods/characters/ 丢一个 GLB。

# 用 preload 而不是 class_name：本机 Godot 4.7 偶发跨脚本 class_name 解析失败
const WeaponMount := preload("res://core/weapon_mount.gd")


func _ready() -> void:
	# 碰撞体
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.6
	col.shape = cap
	# 胶囊底部对齐到人物原点（脚底），这样落地后脚正好踩在地表上，不会陷进草里
	col.position = Vector3(0, cap.height * 0.5, 0)
	add_child(col)

	# 当前角色索引由角色注册表决定（内置角色或外部 MOD，选择已持久化）
	_char_index = CharacterRegistry.get_selected_index()
	# 是否魔法师（Arissa）：决定玩家能否施放治疗
	_is_mage = (CharacterRegistry.get_character(_char_index).get("id", "") == "arissa")

	# 可视体：由角色注册表决定（内置角色或外部 MOD 角色）
	_build_visual()

	# 手中武器：把挂点绑到可视体骨架，并跟随快捷栏实时换模型
	_bind_weapon_mount()
	if Equipment != null and not Equipment.equipped_changed.is_connected(_on_equipped_changed):
		Equipment.equipped_changed.connect(_on_equipped_changed)

	# 相机支架：CameraPivot(Node3D, 由 camera_rig 控制 yaw/pitch)
	#   > SpringArm3D(球体碰撞，自动回缩防穿墙) > CamMount > Camera3D
	cam_pivot = Node3D.new()
	cam_pivot.name = "CameraPivot"
	cam_pivot.position = Vector3(0, 1.4, 0)
	cam_pivot.set_script(load("res://player/camera_rig.gd"))

	# 第三人称相机用 SpringArm3D 做碰撞：臂沿自身 -Z 伸出；
	# 这里把 SpringArm 绕 Y 转 180° 使其指向角色背后(+Z)，终点即相机位置。
	var spring := SpringArm3D.new()
	spring.name = "SpringArm3D"
	spring.position = Vector3.ZERO
	spring.rotation = Vector3(0, PI, 0)
	spring.spring_length = 5.0
	spring.collision_mask = 3            # 与世界/地形碰撞层(layer 1 与 2)一致，避免穿地穿墙
	spring.add_excluded_object(get_rid())  # 排除玩家自身碰撞体
	var sph := SphereShape3D.new()
	sph.radius = 0.3
	spring.shape = sph

	var mount := Node3D.new()
	mount.name = "CamMount"
	mount.position = Vector3.ZERO

	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	camera.position = Vector3(0, 0.6, 0)   # 相对臂尖抬高，模拟视线高度（第一人称时由 camera_rig 接管）
	mount.add_child(camera)
	spring.add_child(mount)
	cam_pivot.add_child(spring)
	# 相机支架挂到场景根节点并置 top_level：XZ 精确跟随玩家（角色居中），
	# Y 由 camera_rig 平滑吸收地形吸附的上下抖动，解决“相机容易晃”。
	var _host = get_tree().current_scene
	if _host == null:
		_host = get_parent()
	_host.add_child(cam_pivot)
	cam_pivot.top_level = true
	_link_sky_exposure()
	_attach_rod()   # 鱼竿挂到相机上做第一人称视图模型（相机已在上方创建）

	# 需求系统
	var n := Node.new()
	n.name = "NeedsSystem"
	n.set_script(load("res://player/needs_system.gd"))
	add_child(n)
	SaveManager.register(n)

	# 交互系统
	var it := Node.new()
	it.name = "InteractionSystem"
	it.set_script(load("res://inventory/interaction_system.gd"))
	add_child(it)

	EventBus.player_died.connect(_on_dead)
	# 钓鱼动作：由钓鱼点通过 EventBus 驱动鱼竿模型
	EventBus.fishing_started.connect(_on_fishing_started)
	EventBus.fishing_cast.connect(_on_fishing_cast)
	EventBus.fishing_bite.connect(_on_fishing_bite)
	EventBus.fishing_fight_started.connect(_on_fishing_fight_started)
	EventBus.fishing_tension.connect(_on_fishing_tension)
	EventBus.fishing_result.connect(_on_fishing_result)
	EventBus.fishing_ended.connect(_on_fishing_ended)
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_visual() -> void:
	var ch: Dictionary = CharacterRegistry.get_character(_char_index)
	# 按角色实测无滑步脚速设定行走/冲刺速度（消除脚滑）。
	# run 不能超过实测脚速（否则冲刺时脚向前滑），但也不能低于 walk（否则冲刺反而更慢）。
	# 整体乘 SPEED_MULT 让移动更快；动画播放速率在 _update_anim 同步缩放，保持脚锁不滑步。
	base_walk = float(ch.get("walk_speed", 1.2))
	base_run = float(ch.get("run_speed", 3.0))
	speed = base_walk * SPEED_MULT
	sprint_speed = max(base_run * SPEED_MULT, speed)
	var root: Node = null
	if ch.has("packed"):
		root = ch["packed"].instantiate()
	elif ch.has("scene_path"):
		var sc = load(ch["scene_path"])
		if sc != null:
			root = sc.instantiate()
	if root != null:
		# 保证可视体是 Node3D（部分 GLB 根节点是普通 Node），否则包一层
		if root is Node3D:
			body_mesh = root
		else:
			var wrap := Node3D.new()
			wrap.add_child(root)
			body_mesh = wrap
		body_mesh.name = "BodyVisual"
		add_child(body_mesh)
		body_mesh.scale = Vector3.ONE * float(ch.get("scale", 1.0))
		body_mesh.position.y = float(ch.get("y_offset", 0.0))
		anim = _find_anim_player(body_mesh)
		anim_map = ch["anim"]
		if CharacterRegistry != null and anim != null:
			anim_map = CharacterRegistry.resolve_anim_map(anim, ch["anim"])
		if anim != null:
			var idle: String = anim_map.get("idle", "")
			if idle != "" and anim.has_animation(idle):
				anim.play(idle)
		return
	# 回退：胶囊体
	body_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.35
	cyl.height = 1.6
	body_mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.7, 0.5)
	body_mesh.material_override = mat
	body_mesh.position = Vector3(0, 0.9, 0)
	add_child(body_mesh)

## 运行时切换角色（主菜单选角色时调用，即时换皮）。
func set_character(index: int) -> void:
	_char_index = index
	_rebuild_visual()

func _rebuild_visual() -> void:
	if _rod != null:
		_rod.queue_free()   # 鱼竿挂在相机上，不在 body_mesh 内，需单独释放
		_rod = null
	if body_mesh != null:
		body_mesh.queue_free()
		body_mesh = null
		anim = null
		anim_map = {}
	_build_visual()
	_bind_weapon_mount()   # 挂点属于旧骨架，换完可视体必须重新绑
	_attach_rod()

## 运行时武器挂载：把手 Models 挂到当前可视体的右手骨（BoneAttachment3D）。
## 换角色（_rebuild_visual）时需要重新绑，因为挂点属于旧骨架。
func _bind_weapon_mount() -> void:
	if _mount == null:
		_mount = WeaponMount.new()
	elif is_instance_valid(_mount) and _mount.is_bound():
		_mount.clear()
	if _mount == null:
		return
	if not _mount.bind(body_mesh):
		push_warning("[Player] 该可视体没有 Skeleton3D，跳过手持武器挂载")
		return
	_sync_equipped()

func _on_equipped_changed(item_id: String, _i: int) -> void:
	_sync_equipped(item_id)

func _sync_equipped(force_id: String = "") -> void:
	if _mount == null or not _mount.is_bound():
		return
	var id: String = force_id if force_id != "" else Equipment.active_id()
	_mount.equip(id)

## 正在播放攻击动画时把武器收回手里/抽出的钩子（供动画事件或上层调用）。
func set_weapon_visible(v: bool) -> void:
	if _mount != null and _mount.current_node() != null:
		_mount.current_node().visible = v

## 把鱼竿模型挂到相机（Camera3D）上，作为第一人称视图模型。
## 这样强制第一人称钓鱼时，即使角色身体（body_mesh）被隐藏，鱼竿依然可见并播放抛竿/咬钩/收线动作。
func _attach_rod() -> void:
	if _rod != null or camera == null:
		return
	_rod = Node3D.new()
	_rod.set_script(load("res://player/fishing_rod.gd"))
	_rod.name = "FishingRod"
	# 相机本地空间：+X 右、+Y 上、-Z 前方。放在视野右下前方，像手持视图模型；
	# 略微前倾 + 侧偏，看起来像把竿伸向水面前方而非竖直一根棍。
	_rod.position = Vector3(0.30, -0.34, -0.62)
	_rod.rotation = Vector3(-0.5, 0.0, 0.18)
	camera.add_child(_rod)
	_rod.visible = false

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null

func _on_dead() -> void:
	# 死亡即复活（GameManager 处理传送/复位），这里只保持鼠标捕获，不打断操作。
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# =========================================================
# 钓鱼动作：鱼竿模型显示 + 面朝钓点 + 播放抛竿/咬钩/收竿
# =========================================================
func _on_fishing_started(spot_pos: Vector3) -> void:
	fishing = true
	# 整个钓鱼过程强制第一人称（用户要求），结束后再还原
	_fp_before_fishing = first_person
	first_person = true
	if cam_pivot != null:
		cam_pivot.first_person = true
	if body_mesh != null:
		body_mesh.visible = false
	var to := spot_pos - global_position
	to.y = 0.0
	if to.length_squared() > 1e-4:
		_fish_face_target = atan2(to.x, to.z) + float(CharacterRegistry.get_character(_char_index).get("yaw_offset", PI))
	if _rod != null:
		_rod.visible = true
		_rod.play("start")
	# 本竿落点由 FishingSystem 计算（落在真实水面，按落点判定栖息地）
	_fish_landing = FishingSystem.get_landing()

func _on_fishing_cast() -> void:
	if _rod != null:
		_rod.play("cast")
	# 浮标抛出去（世界空间，落在水面上）
	_cast_bobber_to(_fish_landing)

func _on_fishing_bite() -> void:
	if _rod != null:
		_rod.play("bite")
	_dip_bobber()   # 咬钩：浮标下沉一下

func _on_fishing_fight_started(_data: Dictionary) -> void:
	# 进入张力博弈：渔轮开始旋转（收线）
	if _rod != null:
		_rod.set_reeling(true)

func _on_fishing_tension(tension: float, _p: float, _n: String) -> void:
	# 张力越大竿越弯（承重弯曲）
	if _rod != null:
		_rod.set_load(tension)

func _on_fishing_result(success: bool) -> void:
	if _rod != null:
		_rod.play("reel" if success else "escape")

func _on_fishing_ended() -> void:
	_hide_cast_rig()
	var r = _rod
	if r != null:
		r.set_reeling(false)
		r.set_load(0.0)
		r.play("end")
		var t := get_tree().create_timer(0.45)
		t.timeout.connect(func(): if is_instance_valid(r): r.visible = false)
	# 还原第一人称状态（钓鱼中强制为 true，这里回到钓鱼前的设置）
	first_person = _fp_before_fishing
	if cam_pivot != null:
		cam_pivot.first_person = _fp_before_fishing
	if body_mesh != null:
		body_mesh.visible = not _fp_before_fishing
	fishing = false

# =========================================================
# 抛投可视：世界空间浮标 + 鱼线（竿尖 → 浮标）
# 说明：视图模型里的竿只负责"手"，真正的浮标抛到水面上，鱼线每帧从竿尖牵过去。
# =========================================================
## 懒创建世界空间浮标 + 鱼线节点（挂在当前场景根节点下，故为世界空间）。
func _ensure_cast_rig() -> void:
	if _cast_bobber != null and is_instance_valid(_cast_bobber):
		return
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent()
	if host == null:
		return
	_cast_bobber = Node3D.new()
	_cast_bobber.name = "CastBobber"
	var bi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.075
	sph.height = 0.15
	sph.radial_segments = 12
	sph.rings = 6
	bi.mesh = sph
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.90, 0.13, 0.13)
	bmat.emission_enabled = true
	bmat.emission = Color(0.35, 0.03, 0.03)
	bi.material_override = bmat
	_cast_bobber.add_child(bi)
	host.add_child(_cast_bobber)
	_cast_bobber.visible = false

	_cast_line = MeshInstance3D.new()
	_cast_line.name = "CastLine"
	var lm := CylinderMesh.new()
	lm.top_radius = 0.006
	lm.bottom_radius = 0.006
	lm.height = 1.0
	lm.radial_segments = 4
	_cast_line.mesh = lm
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.95, 0.95, 0.90, 0.75)
	lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cast_line.material_override = lmat
	host.add_child(_cast_line)
	_cast_line.visible = false

## 从竿尖把浮标抛到落点（抛物线弧线：距离越远抛得越高、飞得越久，像真实甩竿落水）。
func _cast_bobber_to(landing: Vector3) -> void:
	_ensure_cast_rig()
	if _cast_bobber == null or not is_instance_valid(_cast_bobber):
		return
	var from := _rod_tip_global()
	_cast_bobber.visible = true
	_cast_bobber.global_position = from
	var d := from.distance_to(landing)
	if d < 0.05:
		_cast_bobber.global_position = landing
		return
	var dur := clampf(d / 14.0, 0.45, 1.1)
	var peak := clampf(1.2 + d * 0.10, 1.4, 4.0)
	var ctx := {"from": from, "to": landing, "peak": peak}
	var t := create_tween()
	t.tween_method(_arc_to.bind(ctx), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## 抛物线插值：t∈[0,1]，从 from 飞到 to，中段上拱 peak。
func _arc_to(t: float, ctx: Dictionary) -> void:
	if _cast_bobber == null or not is_instance_valid(_cast_bobber):
		return
	var a: Vector3 = ctx["from"]; var b: Vector3 = ctx["to"]; var peak: float = ctx["peak"]
	var p := a.lerp(b, t)
	p.y += peak * sin(PI * t)   # 空中上拱；t=0/1 时 sin=0，精确起止于竿尖/水面
	_cast_bobber.global_position = p

## 咬钩：浮标下沉一下再回到水面。
func _dip_bobber() -> void:
	if _cast_bobber == null or not is_instance_valid(_cast_bobber) or not _cast_bobber.visible:
		return
	var p := _cast_bobber.global_position
	var t := create_tween()
	t.tween_property(_cast_bobber, "global_position", p + Vector3(0, -0.16, 0), 0.12)
	t.tween_property(_cast_bobber, "global_position", p, 0.18)

func _hide_cast_rig() -> void:
	if _cast_bobber != null and is_instance_valid(_cast_bobber):
		_cast_bobber.visible = false
	if _cast_line != null and is_instance_valid(_cast_line):
		_cast_line.visible = false

## 竿尖世界坐标（拿不到鱼竿时退化为相机前方一点）。
func _rod_tip_global() -> Vector3:
	if _rod != null and is_instance_valid(_rod):
		return _rod.tip_global()
	if camera != null:
		return camera.global_position - camera.global_transform.basis.z * 0.7
	return global_position

## 收线时把浮标从落点向玩家脚边（水线）拉近：进度越高越近，让"收线"看得见。
## 鱼冲刺时 FishingSystem 的进度会自动回退，浮标也跟着往外退 —— 与张力博弈同步。
func _update_fight_reel() -> void:
	if not FishingSystem.is_fighting() or _fish_landing == Vector3.ZERO:
		return
	if _cast_bobber == null or not is_instance_valid(_cast_bobber) or not _cast_bobber.visible:
		return
	var p := clampf(FishingSystem.get_progress(), 0.0, 1.0)
	var sea := _sea_dir()
	var target := global_position + sea * 3.0
	if GameManager.world != null:
		var gh := float(GameManager.world.get_ground_height(target.x, target.z))
		if gh < 0.0:
			target.y = 0.0
		else:
			target.y = gh + 0.06
	else:
		target.y = 0.0
	_cast_bobber.global_position = _fish_landing.lerp(target, p)

## 朝海方向（岛心 → 落点 的归一化水平向量），用于推算收线终点。
func _sea_dir() -> Vector3:
	var d := Vector3(_fish_landing.x, 0.0, _fish_landing.z)
	if d.length_squared() < 0.01:
		return Vector3(0, 0, -1)
	return d.normalized()

## 每帧把鱼线画成"竿尖 → 浮标"的世界空间线段。
func _update_cast_line() -> void:
	if _cast_line == null or not is_instance_valid(_cast_line):
		return
	if _cast_bobber == null or not is_instance_valid(_cast_bobber) or not _cast_bobber.visible:
		_cast_line.visible = false
		return
	var a := _rod_tip_global()
	var b := _cast_bobber.global_position
	var d := a.distance_to(b)
	if d < 0.08:
		_cast_line.visible = false
		return
	_cast_line.visible = true
	var mid := (a + b) * 0.5
	var y_axis := (b - a) / d
	var x_axis := y_axis.cross(Vector3.UP)
	if x_axis.length_squared() < 0.0001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	# CylinderMesh 默认沿本地 +Y、高 1；把本地 Y 轴映射为 y_axis 且长度 d。
	_cast_line.global_transform = Transform3D(Basis(x_axis, y_axis * d, z_axis), mid)

## 接入 Sky3D 的相机曝光参数（若存在 Sky3D），让夜景/正午曝光一致。找不到则跳过。
func _link_sky_exposure() -> void:
	var sky: Node = get_tree().get_first_node_in_group("sky3d")
	if sky == null:
		return
	var ca: CameraAttributes = sky.get("camera_attributes")
	if ca != null:
		camera.attributes = ca

func _unhandled_input(event) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, -1.0, 0.8)
		if cam_pivot:
			cam_pivot.target_yaw = yaw
			cam_pivot.target_pitch = pitch
	# V 键切换第一/第三人称（钓鱼时强制第一人称，禁止切换）
	if event is InputEventKey and event.pressed and event.keycode == KEY_V:
		if fishing:
			EventBus.toast.emit("钓鱼中已强制第一人称")
			return
		first_person = not first_person
		if cam_pivot:
			cam_pivot.first_person = first_person
		if body_mesh != null:
			body_mesh.visible = not first_person
	# F 键进食：消耗背包里第一个有恢复效果的消耗品
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		if not GameManager.interact_menu_open:
			_eat()
	# R 键：魔法师治疗（准星选中的伙伴）。非魔法师角色按 R 无效果。
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		_try_heal()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 钓鱼时左键由 FishingSystem 用于刺鱼/收线，不要触发攻击
		if not fishing:
			_try_attack()

func _try_attack() -> void:
	if GameManager.build_mode:
		return   # 建造模式下左键用于放置，不攻击
	if GameManager.interact_menu_open:
		return   # NPC 交互菜单/送礼面板打开时左键用于点按钮，不挥击
	if anim == null:
		return
	if attacking:
		return
	var atk: Array = anim_map.get("attack", [])
	if atk.is_empty():
		return
	var name: String = atk[_combo % atk.size()]
	if not anim.has_animation(name):
		name = atk[0]
		_combo = 0
	attacking = true
	anim.play(name)
	if not anim.is_connected("animation_finished", _on_anim_finished):
		anim.animation_finished.connect(_on_anim_finished)
	_spawn_attack_hitbox()

## 挥击命中判定：遍历 enemy 组，挑正前方 attack_reach 内、角度合理的最近敌人并造成伤害。
## 用「组遍历 + 距离/朝向」替代 Area3D 命中盒——本项目下 Godot 4 的 Area↔Body 检测
## 会出现几何重叠却检测不到的情况（挥击永远落空），手动判定更可靠。
func _spawn_attack_hitbox() -> void:
	var origin := global_position + Vector3(0, 1.0, 0)
	var fwd: Vector3 = -camera.global_transform.basis.z
	fwd = Vector3(fwd.x, 0, fwd.z)
	if fwd.length_squared() < 1e-4:
		fwd = _facing_dir
		if fwd.length_squared() < 1e-4:
			fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	var best: Node = null
	var best_d: float = attack_reach + 0.8
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self or not is_instance_valid(e):
			continue
		var ec: Vector3 = e.global_position + Vector3(0, 1.0, 0)
		var to: Vector3 = ec - origin
		var d: float = to.length()
		if d > attack_reach + 0.8:
			continue
		var dir: Vector3 = to.normalized()
		if dir.dot(fwd) < 0.2:   # 约 78° 前向锥角内
			continue
		if d < best_d:
			best_d = d
			best = e
	if best != null:
		var dmg := attack_damage + Equipment.active_weapon_damage()
		EventBus.player_attacked.emit(best, dmg)

## 背包里武器伤害取最高（spear 等 weapon_damage>0 的物品）。
func _best_weapon_damage() -> float:
	var best := 0.0
	for id in Inventory.items:
		var it: ItemResource = ItemDatabase.get_item(id)
		if it != null and it.weapon_damage > best:
			best = it.weapon_damage
	return best

## 背包里武器伤害最高的物品 id（用于损耗该武器）。
func _best_weapon_id() -> String:
	var best := ""
	var best_val := 0.0
	for id in Inventory.items:
		var it: ItemResource = ItemDatabase.get_item(id)
		if it != null and it.weapon_damage > best_val:
			best_val = it.weapon_damage
			best = id
	return best

func _on_anim_finished(_name: String) -> void:
	attacking = false
	_casting = false
	_combo = (_combo + 1) % 3

## 魔法师治疗：从相机正前（准星中心）发射射线，命中并在治疗范围内的伙伴即被治疗。
## 治疗：准星对准哪个可治疗伙伴，就给谁回血；准星没有对准任何可治疗伙伴时，
## 按 R 改为自我治疗（魔法师自身走需求系统回血）。仅魔法师(Arissa)可用。
func _try_heal() -> void:
	if not _is_mage:
		return
	if GameManager.game_over:
		return
	if _heal_cd > 0.0:
		EventBus.toast.emit("治疗冷却中（%.1f 秒）" % _heal_cd)
		return
	# 1) 优先治疗准星选中的伙伴
	var companion: Node = _resolve_crosshair_target()
	if companion != null and "hp" in companion and companion.hp < companion.max_hp:
		_cast_apply(companion, "治疗：为 %s 回复 %d 点生命" % [companion.char_name, int(heal_amount)])
		return
	# 2) 没目标（或目标满血）→ 自我治疗
	_self_heal()

## 从准星（相机正前）打射线，返回命中的可治疗伙伴节点；无则 null。
func _resolve_crosshair_target() -> Node:
	var cam: Camera3D = camera
	if cam == null:
		cam = get_viewport().get_camera_3d()
	if cam == null:
		return null
	var space := get_world_3d().direct_space_state as PhysicsDirectSpaceState3D
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var to := from + dir * heal_range
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_bodies = true
	q.exclude = [self]
	var hit := space.intersect_ray(q) as Dictionary
	if hit and hit.collider != null:
		return _find_heal_target(hit.collider)
	return null

## 自我治疗：玩家自身走需求系统(health/max_health)，满血则提示并返回。
func _self_heal() -> void:
	var ns = get_node_or_null("NeedsSystem")
	if ns == null:
		EventBus.toast.emit("自我治疗不可用")
		return
	if ns.health >= ns.max_health:
		EventBus.toast.emit("生命已满")
		return
	_play_cast_anim()
	ns.apply_effects(heal_amount, 0.0, 0.0)
	_heal_cd = heal_cooldown
	EventBus.toast.emit("自我治疗：回复 %d 点生命" % int(heal_amount))
	_spawn_heal_fx(self)

## 播放施法动画（Cast_Heal），并用 _casting 阻止 _update_anim 每帧覆盖。
func _play_cast_anim() -> void:
	var cast_anim: String = anim_map.get("cast", "")
	if cast_anim != "" and anim != null and anim.has_animation(cast_anim):
		if not anim.is_connected("animation_finished", _on_anim_finished):
			anim.animation_finished.connect(_on_anim_finished)
		_casting = true
		_cast_timer = 1.2
		anim.play(cast_anim)

## 对伙伴执行施法动画 + 治疗 + 冷却 + 反馈。
func _cast_apply(target: Node, msg: String) -> void:
	_play_cast_anim()
	target.heal(heal_amount)
	_heal_cd = heal_cooldown
	EventBus.toast.emit(msg)
	_spawn_heal_fx(target as Node3D)

## 沿父链向上，找最近的「可治疗」节点：有 heal 方法、有 hp/max_hp、未死亡。
func _find_heal_target(from: Node) -> Node:
	var n: Node = from
	while n != null:
		if n != self and n.has_method("heal") and "hp" in n and "max_hp" in n and not bool(n.get("is_dead")):
			return n
		n = n.get_parent()
	return null

## 治疗视觉反馈：在目标身上喷发一圈向上飘升的绿色柔光粒子（一次性，自动释放）。
func _spawn_heal_fx(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	if _heal_particle_tex == null:
		_heal_particle_tex = _make_heal_particle_texture()
	var ps := CPUParticles3D.new()
	ps.emitting = false
	ps.one_shot = true
	ps.amount = 28
	ps.lifetime = 1.1
	ps.explosiveness = 0.7
	ps.speed_scale = 1.0
	ps.texture = _heal_particle_tex
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.55
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 35.0
	pm.gravity = Vector3(0.0, 1.4, 0.0)        # 轻微上浮，像治愈气息升起
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.6
	pm.linear_accel_min = 0.3
	pm.linear_accel_max = 0.9
	pm.angular_velocity_min = -1.5
	pm.angular_velocity_max = 1.5
	pm.scale_min = 0.18
	pm.scale_max = 0.42
	var grad := Gradient.new()
	grad.add_point(0.0, Color(0.75, 1.0, 0.78, 1.0))
	grad.add_point(0.55, Color(0.4, 1.0, 0.55, 0.85))
	grad.add_point(1.0, Color(0.3, 1.0, 0.45, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	ps.process_material = pm
	target.add_child(ps)
	ps.global_position = target.global_position + Vector3(0.0, 1.0, 0.0)
	ps.emitting = true
	# 一次性喷发后自动释放（避免节点堆积）
	var dur := ps.lifetime + 0.25
	await get_tree().create_timer(dur).timeout
	if is_instance_valid(ps):
		ps.queue_free()

## 程序化生成治疗粒子贴图：柔光圆点（径向渐变、边缘透明），避免方块感。
## 不依赖任何外部资源，首次调用时生成并缓存复用。
func _make_heal_particle_texture() -> Texture2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var dx := float(x) - c
			var dy := float(y) - c
			var d: float = sqrt(dx * dx + dy * dy) / c
			var a: float = clamp(1.0 - d, 0.0, 1.0)
			a = a * a * a            # 边缘更柔和，中心更聚拢
			img.set_pixel(x, y, Color(0.55, 1.0, 0.6, a))
	var tex := ImageTexture.create_from_image(img)
	return tex

## 进食指定物品：消耗背包里 1 个 id，并应用其效果到需求系统。
## 供背包格子「点击使用」与自动进食（_eat）共用。返回是否成功使用。
func eat_item(id: String) -> bool:
	var it: ItemResource = ItemDatabase.get_item(id)
	if it == null:
		return false
	if it.category != ItemResource.Category.CONSUMABLE:
		return false
	if it.health_change == 0.0 and it.hunger_change == 0.0 and it.sanity_change == 0.0 and it.thirst_change == 0.0:
		return false
	if not Inventory.has(id, 1):
		return false
	Inventory.consume(id, 1)
	var ns = get_node_or_null("NeedsSystem")
	if ns != null:
		ns.apply_effects(it.health_change, it.hunger_change, it.sanity_change)
	EventBus.food_eaten.emit(id)
	EventBus.toast.emit("吃了 %s" % it.display_name)
	return true

## 自动进食：消耗背包里第一个带恢复效果的消耗品（浆果/熟肉/生肉）。
func _eat() -> void:
	for id in Inventory.items:
		var it: ItemResource = ItemDatabase.get_item(id)
		if it == null:
			continue
		if it.category == ItemResource.Category.CONSUMABLE and (it.health_change != 0.0 or it.hunger_change != 0.0 or it.sanity_change != 0.0 or it.thirst_change != 0.0):
			eat_item(id)
			return
	EventBus.toast.emit("背包里没有可吃的东西")

func _update_anim() -> void:
	if anim == null or anim_map.is_empty():
		return
	# 攻击/施法动画保持原速播放，不被脚锁缩放影响
	if attacking or _casting:
		anim.speed_scale = 1.0
		return
	var spd := Vector2(velocity.x, velocity.z).length()
	var walk_name: String = anim_map.get("walk", "")
	var run_name: String = anim_map.get("run", "")
	var want: String
	if not is_on_floor():
		want = anim_map.get("fall", "")
	elif is_sprinting and spd > 0.3:
		want = run_name
	elif spd > 0.3:
		want = walk_name
	else:
		want = anim_map.get("idle", "")
	if want != "" and anim.has_animation(want) and anim.current_animation != want:
		anim.play(want, 0.15)
	# 脚锁：按当前动画实测脚速缩放播放速率，移动更快也不滑步；非步态动画(待机/坠落)保持原速
	if want == walk_name and walk_name != "":
		anim.speed_scale = clampf(spd / max(base_walk, 0.001), 0.5, 3.0)
	elif want == run_name and run_name != "":
		anim.speed_scale = clampf(spd / max(base_run, 0.001), 0.5, 3.0)
	else:
		anim.speed_scale = 1.0

func _physics_process(delta: float) -> void:
	if GameManager.game_over:
		velocity = Vector3.ZERO
		return

	# 治疗冷却 / 施法占位计时
	if _heal_cd > 0.0:
		_heal_cd = maxf(0.0, _heal_cd - delta)
	if _casting:
		_cast_timer -= delta
		if _cast_timer <= 0.0:
			_casting = false

	# 钓鱼中：锁定移动，面朝钓点，仅做重力/落地与鱼竿动作
	if fishing:
		velocity.x = 0.0
		velocity.z = 0.0
		if is_on_floor():
			velocity.y = 0.0
		else:
			velocity.y -= gravity * delta
		if body_mesh != null:
			body_mesh.rotation.y = lerp_angle(body_mesh.rotation.y, _fish_face_target, 0.15)
		move_and_slide()
		if GameManager.world != null:
			var gh := float(GameManager.world.get_ground_height(global_position.x, global_position.z))
			if velocity.y <= 0.0 and global_position.y - gh < 0.6:
				global_position.y = gh
				if velocity.y < 0.0:
					velocity.y = 0.0
		_update_fight_reel()
		_update_cast_line()
		return

	var f := Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var st := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	# 冲刺：Godot 4 下纯修饰键动作 is_action_pressed 偶发不触发，故用多重兜底：
	#   1) InputMap 动作 "sprint"（已绑 KEY_SHIFT）；2) keycode 直接检测（对修饰键最稳）；3) 物理按键检测。
	# 任意一种命中即视为冲刺，确保按住 Shift 一定能跑。
	is_sprinting = Input.is_action_pressed("sprint") \
		or Input.is_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SHIFT)
	# 方向基于相机实际朝向（修复 W/S、A/D 反向）：W=相机前方、D=相机右方。
	# 直接取相机视线水平分量，避免 SpringArm3D 旋转导致的前后/左右反向。
	var cam_fwd: Vector3 = -camera.global_transform.basis.z
	cam_fwd.y = 0.0
	if cam_fwd.length_squared() < 1e-5:
		cam_fwd = Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
	cam_fwd = cam_fwd.normalized()
	var cam_right: Vector3 = cam_fwd.cross(Vector3.UP).normalized()
	var dir := (cam_fwd * f + cam_right * st)
	if dir.length() > 0.001:
		dir = dir.normalized()

	var cur := sprint_speed if is_sprinting else speed
	# 超重：大幅减速并禁止冲刺
	if Inventory.is_overburdened():
		cur = speed * 0.35
		is_sprinting = false
	velocity.x = dir.x * cur
	velocity.z = dir.z * cur

	if is_on_floor():
		velocity.y = 0.0
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
	else:
		velocity.y -= gravity * delta

	if dir.length() > 0.01:
		# 朝向偏移按角色配置：RPG 模型正面是 -Z（需 +PI），Mixamo 女角色正面是 +Z（偏移 0）。
		# 若某角色仍面朝移动反方向，只需把它在注册表定义里的 yaw_offset 在 0 与 PI 之间对调。
		var target := atan2(dir.x, dir.z) + float(CharacterRegistry.get_character(_char_index).get("yaw_offset", PI))
		body_mesh.rotation.y = lerp_angle(body_mesh.rotation.y, target, 0.15)
		_facing_dir = dir

	move_and_slide()
	# 双向地面吸附：贴着真实地表（terrain_height），避免悬空或陷地。
	# 只在「贴近地面且未在向上跳」时吸附；跳起(velocity.y>0)或坠落悬崖时不吸附。
	if GameManager.world != null:
		var gh := float(GameManager.world.get_ground_height(global_position.x, global_position.z))
		if velocity.y <= 0.0 and global_position.y - gh < 0.6:
			global_position.y = gh
			if velocity.y < 0.0:
				velocity.y = 0.0
	_update_anim()
