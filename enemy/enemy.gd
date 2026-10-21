extends CharacterBody3D
const HealthBarScript := preload("res://ui/health_bar.gd")
## 敌人（生物/战斗层）。
## 复用 RPG_Character.glb 可视体（UrbanMan 真人模型 + UAL 动画，运行时 GLTFDocument 直接导入，
## 不依赖编辑器 .import 缓存），无需任何重映射。
##
## 状态机：IDLE(待机) -> CHASE(侦测到玩家后追击) -> ATTACK(进入攻击距离循环攻击) -> DEAD。
## 与玩家解耦、只走 EventBus：
##   - 被玩家攻击：监听 EventBus.player_attacked，自判 target==self 后扣血
##   - 攻击玩家：挥击中点发出 EventBus.player_damaged(dmg)，由 NeedsSystem 扣玩家血
##   - 死亡：发出 EventBus.creature_died(self, drops) 后缩放消失并释放

@export var max_health := 60.0
@export var enemy_speed := 4.0        # 略低于玩家基础速度(5)，保证可逃
@export var detect_range := 18.0      # 仇恨/侦测半径
@export var attack_range := 2.2       # 进入此距离开始攻击
@export var attack_damage := 15.0
@export var attack_interval := 1.4    # 两次攻击间隔（秒）
@export var drops := {"rawmeat": 2, "log": 1, "stick": 1} as Dictionary  # 死亡掉落（生肉/木材，供烹饪与制作）
@export var is_aggressive := true      # false = 被动动物，见玩家就逃（鹿等）
@export var xp_reward := 15            # 击杀给的经验
@export var flee_speed := 5.0          # 逃跑速度（被动动物略快于玩家，可逃）
@export var species := "Beast"         # 物种名（供任务按种类统计击杀，如 Wolf/Bear）
@export var visual_scale := 1.0        # 体型缩放：野猪小(0.7)、熊大(1.4)
@export var is_humanoid := false       # true = 人形野怪(Raider/Boss)，用 RPG 角色网格；false = 四足动物，用图元拼接

# ===== BOSS 专属：跳击（跳+劈）=====
@export var is_boss := false            # true = BOSS（唯一），启用跳击等特殊行为
@export var jump_attack_anim := ""      # 跳击动画名（anim_map 中的 jump_attack），如 Jump_Attack
@export var jump_attack_range := 9.0    # 在此距离内、且未贴身时发动跳击（远大于普通攻击距离）
@export var jump_attack_damage := 45.0  # 跳击伤害
@export var jump_attack_cooldown := 7.0 # 两次跳击间隔（秒）

enum State { IDLE, CHASE, ATTACK, FLEE, DEAD }

var health := max_health
var state := State.IDLE
var target: Node3D = null
var attack_cooldown := 0.0
var dead := false
var attacking := false
var _killer: Node = null   # 最后一击来源（玩家或伙伴），死亡时随 drops 一起上报，用于战利品归属
var is_sieger := false      # true = 夜袭怪：玩家/伙伴不在侦测范围时主动攻营（寻路至最近栅栏并攻击）
var _siege_target: Fence = null  # 当前攻击的栅栏节点（is_sieger 专用）
var _facing := Vector3(0, 0, 1)   # 当前朝向（xz 平面），用于视野锥侦测
var _knockback := Vector3.ZERO    # 击退速度累加器（打击感：受击被推开，每帧衰减）
const KNOCK_DECAY := 9.0          # 击退衰减速度（单位/秒）

var body_mesh: Node3D = null
var anim: AnimationPlayer = null
## 人形野怪的动画映射。默认用 UAL 命名（Idle_Loop/Walk_Loop/Sprint_Loop/Jump_Loop/Sword_Attack/Die），
## 与玩家 RPG_Character.glb 一致；spawner 可按怪物 GLB 覆盖。
@export var anim_map: Dictionary = {
	"idle": "Idle_Loop", "walk": "Walk_Loop", "run": "Sprint_Loop",
	"fall": "Jump_Loop", "attack": "Sword_Attack", "dead": "Die",
	# 第二攻击（可选）：存在时与 attack 轮流播放（人形怪 GLB 加了 Axe_Combo 大力近战连击）
	"attack2": "Axe_Combo"
}
## 攻击轮换索引：0=attack，1=attack2。每次出手交替，让怪不总用同一招。
var _attack_toggle := 0
## 本次攻击实际播放的动画名（供 _update_anim 稳定维持，不被强制切回）。
var _active_attack := ""
## 人形野怪模型路径（GLB，运行时由 GLTFDocument 直接导入）。spawner 按物种注入。
@export var visual_path := "res://player/RPG_Character.glb"
var _animal_root: Node3D = null   # 动物图元/模型根（行走摆动用）
var _bob_t := 0.0
var _animal_yaw_offset := 0.0      # 模型前向修正（GLB 朝向与引擎 +Z 不一致时改此值）
var _animal_models_cache: Dictionary = {}  # 物种 -> PackedScene（已解析模型，避免重复扫描目录）
var _hp_bar: Node = null                   # 头顶血条（HealthBar）

# BOSS 跳击运行时状态
var _jumping := false
var _jump_from := Vector3.ZERO
var _jump_to := Vector3.ZERO
var _jump_t := 0.0
var _jump_dur := 1.0
var _jump_height := 2.5
var _jump_cd := 0.0

func _ready() -> void:
	add_to_group("enemy")
	_setup_visual()        # 先建可视体，碰撞胶囊要按模型实际高度生成
	_setup_collision()
	_setup_detection()
	_setup_health_bar()
	EventBus.player_attacked.connect(_on_player_attacked)
	EventBus.creature_spawned.emit(self)

## 物理落地：用重力 + 胶囊碰撞让身体真正「站」在地形碰撞面上
## （之前靠采样高度场后硬传送，暂停/高度场错位时动物会浮空或插地）。
const GRAVITY := 20.0

func _setup_collision() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	# 按可视模型实际高度生成胶囊，避免人形大胶囊套在小动物身上导致浮空。
	var h := _visual_height()
	cap.radius = clampf(h * 0.28, 0.22, 0.6)
	cap.height = maxf(0.4, h * 0.7)
	col.shape = cap
	# 胶囊底对齐到敌人原点(=地表)，脚底可视体对齐到原点 → 落地后脚踩地面。
	col.position = Vector3(0, (cap.height + 2.0 * cap.radius) * 0.5, 0)
	add_child(col)

## 可视模型在敌人本地空间的实际高度（含缩放与子节点嵌套变换）。
func _visual_height() -> float:
	if body_mesh == null:
		return 1.6
	var a: AABB = _model_aabb(body_mesh, Transform3D())
	if a.size.y > 0.001:
		return a.size.y
	return 1.6

func _setup_visual() -> void:
	if is_humanoid:
		_setup_humanoid_visual()
	else:
		_build_animal_visual()

## 人形野怪：复用 RPG_Character.glb（现在是 UrbanMan + UAL 动画，运行时 GLTFDocument 直接导入，
## 不依赖编辑器 .import 缓存；动画名用 UAL 的 Idle_Loop/Walk_Loop/Sprint_Loop/Jump_Loop/Sword_Attack）。

## GLTFDocument 兜底加载入口（仅当 load() 失败时调用，例如 user:// MOD 未预导入的磁盘 glb）。
## ⚠️ 导出包(PCK)内 .glb 源文件并不以可读字节存在，必须先由 load() 走 import remap 加载。
func _gltf_load(gltf: GLTFDocument, state: GLTFState, scene_path: String) -> int:
	var err := gltf.append_from_file(scene_path, state)
	if err == OK:
		return OK
	if FileAccess.file_exists(scene_path):
		var bytes := FileAccess.get_file_as_bytes(scene_path)
		if bytes.size() > 0:
			return gltf.append_from_buffer(bytes, scene_path, state)
	return err

func _setup_humanoid_visual() -> void:
	# 优先 load()（PCK 内 .glb 已导入成 .scn，带贴图，最稳）
	var res := ResourceLoader.load(visual_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var ps: PackedScene = null
	if res is PackedScene:
		ps = res
	else:
		# 回退：GLTFDocument（user:// MOD 等未预导入的 glb，磁盘可用）
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if _gltf_load(doc, st, visual_path) == OK:
			var node := doc.generate_scene(st)
			if node != null:
				ps = PackedScene.new()
				if ps.pack(node) != OK:
					ps = null
				node.free()
	if ps != null:
		body_mesh = ps.instantiate()
		body_mesh.name = "BodyVisual"
		add_child(body_mesh)
		body_mesh.scale = Vector3.ONE * 1.05 * visual_scale
		anim = _find_anim_player(body_mesh)
		# anim_map 由 spawner 注入或默认 UAL 命名（Idle_Loop/Walk_Loop/.../Die）
		if anim_map.is_empty():
			anim_map = {
				"idle": "Idle_Loop", "walk": "Walk_Loop", "run": "Sprint_Loop",
				"fall": "Jump_Loop", "attack": "Sword_Attack", "dead": "Die"
			}
		# ⚠️ GLB 导入后动画名会被清洗掉 `_Loop` 后缀（Idle_Loop→Idle、Walk_Loop→Walk、
		#    Sprint_Loop→Sprint、Jump_Loop→Jump）。若直接用 anim_map 里的 _Loop 名去
		#    has_animation()，会全部 false → 人形怪一帧动画都不播 → 停在绑定姿势 **T-pose**。
		#    用 CharacterRegistry 的稳健解析把每个键映射到 AnimationPlayer 里真实存在的名字
		#    （同伴 human_companion.gd 用的同一套，故伙伴不 T-pose）。
		if anim != null:
			anim_map = CharacterRegistry.resolve_anim_map(anim, anim_map)
		var idle_name: String = anim_map.get("idle", "")
		if anim != null and idle_name != "" and anim.has_animation(idle_name):
			anim.play(idle_name)
	else:
		# 回退：红色胶囊
		body_mesh = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.4
		cyl.bottom_radius = 0.4
		cyl.height = 1.6
		body_mesh.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.2, 0.2)
		body_mesh.material_override = mat
		body_mesh.position = Vector3(0, 0.9, 0)
		add_child(body_mesh)
## 动物：优先加载真实 GLB/glTF 模型（res://assets/animals/ 下按物种名匹配文件，支持嵌套子目录），
## 找不到时退回图元拼接（保证任何情况下都有可见身体，且仍能正常战斗/被攻击）。
func _build_animal_visual() -> void:
	var sc := _resolve_animal_scene(species)
	if sc != null:
		body_mesh = sc.instantiate()
		body_mesh.name = "BodyVisual"
		# 自动归一化尺寸：不同来源的 GLB 比例差异极大（实测 wolf 0.06 / deer 139 单位），
		# 直接 instantiate 会要么几乎不可见、要么撑爆场景。统一缩放到目标体长再乘视觉缩放。
		var a: AABB = _model_aabb(body_mesh, Transform3D())
		var mdim: float = max(a.size.x, max(a.size.y, a.size.z))
		if mdim > 0.0001:
			var k: float = (_species_target_length() * visual_scale) / mdim
			body_mesh.scale = Vector3.ONE * k
		else:
			body_mesh.scale = Vector3.ONE * visual_scale
		# 脚底对齐：用 pivot 包裹，把模型本地脚底(最小 y) 对齐到 enemy 原点(=地表)。
		# 否则 GLB 原点常位于模型中心/上方，下半身会插进地形（"卡进地图"）。
		# pivot 单独承载行走摆动的 y 浮动，不会破坏这里的脚底对齐。
		var a2: AABB = _model_aabb(body_mesh, Transform3D())
		body_mesh.position.y = -a2.position.y
		var pivot := Node3D.new()
		pivot.name = "AnimalPivot"
		pivot.add_child(body_mesh)
		add_child(pivot)
		_animal_root = pivot
		anim = _find_anim_player(body_mesh)
		anim_map = _build_anim_map(anim)
		if anim != null and anim_map.has("idle"):
			anim.play(anim_map["idle"])
		_animal_yaw_offset = _species_model_yaw(species)
		return
	_build_animal_visual_primitives()

## 目标体长（米）：四足动物统一缩放到此最大边长，再乘以模板的 visual_scale 微调。
## 用「最大边长」而非高度，是因为模型朝向不一，取最长轴最稳。
func _species_target_length() -> float:
	return 1.6

## 递归合并模型内所有网格的包围盒，并叠加各层节点的局部变换（位置/旋转/缩放），
## 得到模型在自身坐标系下的真实尺寸（不受运行时缩放影响）。
## 必须叠加嵌套变换：部分 GLB 在子节点上挂了缩放/位移（如狐狸），仅取网格局部 AABB
## 会严重低估真实尺寸，导致归一化系数过大、模型被渲染成巨物。Transform3D * AABB 合法。
func _model_aabb(n: Node, xf: Transform3D) -> AABB:
	var acc: Transform3D = xf
	if n is Node3D:
		acc = xf * (n as Node3D).transform
	var a := AABB()
	if n is GeometryInstance3D:
		var la := (n as GeometryInstance3D).get_aabb()
		if la.size.length() > 1e-6:
			a = acc * la
	for c in n.get_children():
		a = a.merge(_model_aabb(c, acc))
	return a

## 图元兜底：用基础图元拼出四足轮廓，按 species 区分形态/配色，明显区别于人形 RPG 角色。
func _build_animal_visual_primitives() -> void:
	var pal: Dictionary = _species_palette()
	var root: Node3D = Node3D.new()
	root.name = "BodyVisual"
	# 躯干（横向长条）
	var body: MeshInstance3D = MeshInstance3D.new()
	var bmesh: BoxMesh = BoxMesh.new()
	bmesh.size = Vector3(0.5, 0.4, 1.0)
	body.mesh = bmesh
	_tint(body, pal.body as Color)
	body.position = Vector3(0, 0.5, 0)
	root.add_child(body)
	# 头（前上方）
	var head: MeshInstance3D = MeshInstance3D.new()
	var hmesh: BoxMesh = BoxMesh.new()
	hmesh.size = Vector3(0.34, 0.34, 0.34)
	head.mesh = hmesh
	_tint(head, pal.head as Color)
	head.position = Vector3(0, 0.62, 0.6)
	root.add_child(head)
	# 4 条腿
	for lx in [-0.18, 0.18]:
		for lz in [-0.35, 0.35]:
			var leg: MeshInstance3D = MeshInstance3D.new()
			var lg: BoxMesh = BoxMesh.new()
			lg.size = Vector3(0.12, 0.5, 0.12)
			leg.mesh = lg
			_tint(leg, pal.body as Color)
			leg.position = Vector3(lx, 0.25, lz)
			root.add_child(leg)
	root.scale = Vector3.ONE * visual_scale
	add_child(root)
	body_mesh = root
	anim = null
	_animal_root = root
## 按物种返回配色（身体/头/头顶标识）。
func _species_palette() -> Dictionary:
	match species:
		"Wolf":  return {"body": Color(0.5,0.5,0.55), "head": Color(0.45,0.45,0.5),  "marker": Color(0.85,0.15,0.15)}
		"Deer":  return {"body": Color(0.55,0.45,0.3), "head": Color(0.6,0.5,0.35),  "marker": Color(0.3,0.8,0.4)}
		"Boar":  return {"body": Color(0.4,0.28,0.18), "head": Color(0.35,0.24,0.16), "marker": Color(0.6,0.4,0.25)}
		"Fox":   return {"body": Color(0.9,0.55,0.2),  "head": Color(0.95,0.6,0.25),  "marker": Color(0.95,0.6,0.2)}
		"Bear":  return {"body": Color(0.4,0.28,0.2),  "head": Color(0.45,0.32,0.22), "marker": Color(0.5,0.3,0.2)}
		_:      return {"body": Color(0.5,0.35,0.2),  "head": Color(0.5,0.35,0.2),   "marker": Color(0.8,0.2,0.2)}

## 头顶血条：放在头顶标识（marker 锥）上方，跟随生命值缩放。
func _setup_health_bar() -> void:
	var hb := HealthBarScript.new()
	hb.name = "HealthBar"
	add_child(hb)
	hb.position = Vector3(0, 2.7 * visual_scale, 0)
	hb.set_fraction(health / max_health)
	_hp_bar = hb

## 给图元上纯色（StandardMaterial，自发光一点便于暗处辨识）。
func _tint(mi: MeshInstance3D, col: Color) -> void:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	m.emission = col * 0.15
	mi.material_override = m

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null

## 已知物种 -> 模型资源路径（显式列出，不能靠目录扫描）。
## ⚠️ 导出包(PCK)内**只有导入后的 .godot/imported/*.scn，源 .glb 不在包内**：
##    目录里能看到的只是 "wolf.glb.import" 这类文本文件，靠 DirAccess 扫到 .glb 后缀
##    在导出包里永远为 0 命中 → 动物全部退回方块图元。显式路径 + load() 走 import remap 才可靠。
## ⚠️ 必须用「带骨骼动画」的模型：原 deer.glb / boar.glb / bear.glb 是**静态网格**
##    （skins=0 / anims=0，只有 1 个 node），无论代码怎么写都只会是一尊滑行的雕像。
##    - deer → stag.gltf（Quaternius 动画鹿，13 个动画：Idle/Walk/Gallop/Attack…）
##    - bear / boar → 用 Blender 把原静态网格重新蒙皮到 wolf.glb 的四足骨架 AnimalArmature
##      上再导出（24 个动画，命名与 wolf 一致，故 _build_anim_map 可直接识别）
const ANIMAL_MODEL_PATHS: Dictionary = {
	"wolf": "res://assets/animals/wolf.glb",
	"deer": "res://assets/animals/stag.gltf",
	"boar": "res://assets/animals/boar_anim.glb",
	"fox": "res://assets/animals/fox.glb",
	"bear": "res://assets/animals/bear_anim.glb",
}

func _resolve_animal_scene(sp: String) -> PackedScene:
	if _animal_models_cache.has(sp):
		return _animal_models_cache[sp]
	var key := sp.to_lower()
	var sc: PackedScene = null
	# 1) 显式路径优先：load() 会按 .import remap 拿到带贴图的 .scn（编辑器/导出包都成立）
	if ANIMAL_MODEL_PATHS.has(key):
		var res = ResourceLoader.load(ANIMAL_MODEL_PATHS[key], "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
		if res is PackedScene:
			sc = res
	# 2) 兜底：目录扫描（MOD 新增模型、临时换文件名时有效）
	if sc == null:
		sc = _scan_for_model("res://assets/animals/", key, 0)
	if sc == null:
		push_warning("[Enemy] 未找到动物模型，退回图元兜底: " + sp)
	_animal_models_cache[sp] = sc
	return sc

## 兜底扫描：在 res://assets/animals/（含嵌套子目录，最多 2 层）下按物种名匹配 GLB/glTF。
## 仅用于显式表未覆盖的情况（MOD 新增模型）；导出包内目录只有 *.glb.import，故已做后缀容错。
func _scan_for_model(dir: String, sp_low: String, depth: int) -> PackedScene:
	var d := DirAccess.open(dir)
	if d == null:
		return null
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if d.current_is_dir():
			if depth < 2:
				var r := _scan_for_model(dir + f + "/", sp_low, depth + 1)
				if r != null:
					d.list_dir_end()
					return r
		else:
			# 导出包(PCK)内目录里只有 "wolf.glb.import" 这类文本文件，源 .glb 不在包内；
			# 去掉 .import 后缀后按原名 load()，才能命中 import remap 得到真正的 .scn。
			var nm := f
			if nm.ends_with(".import"):
				nm = nm.substr(0, nm.length() - 7)
			var ext := nm.get_extension().to_lower()
			if ext == "glb" or ext == "gltf":
				if nm.to_lower().contains(sp_low):
					var res := ResourceLoader.load(dir + nm, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
					if res is PackedScene:
						d.list_dir_end()
						return res
					# 运行时兜底：编辑器未预导入（headless / 导出包）时，用 GLTFDocument 直接解析，
					# 打包成 PackedScene 复用同一套 instantiate 流程，确保任何环境都能加载真实模型。
					var doc := GLTFDocument.new()
					var st := GLTFState.new()
					if _gltf_load(doc, st, dir + f) == OK:
						var node := doc.generate_scene(st)
						if node != null:
							var ps := PackedScene.new()
							if ps.pack(node) == OK:
								node.free()
								d.list_dir_end()
								return ps
		f = d.get_next()
	d.list_dir_end()
	return null

## 从 AnimationPlayer 现有动画名里按关键字（不区分大小写）挑出 idle/walk/run/attack/dead，
## 兼容 Quaternius 等自带动画包（如 Gallop/Walk/Attack/Death）。无动画则返回空表。
func _build_anim_map(ap: AnimationPlayer) -> Dictionary:
	var m: Dictionary = {}
	if ap == null:
		return m
	var names: PackedStringArray = ap.get_animation_list()
	for n in names:
		var low := n.to_lower()
		if "idle" in low and not m.has("idle"):
			m["idle"] = n
		elif "walk" in low and not m.has("walk"):
			m["walk"] = n
		elif ("run" in low or "gallop" in low or "sprint" in low) and not m.has("run"):
			m["run"] = n
		elif "attack" in low and not m.has("attack"):
			m["attack"] = n
		elif ("death" in low or "dead" in low or "die" in low) and not m.has("dead"):
			m["dead"] = n
	return m

## 模型前向修正（弧度）。GLB 一般朝 +Z；若接入后动物「倒着走」，把对应物种改成 PI 即可。
func _species_model_yaw(sp: String) -> float:
	return 0.0

func _setup_detection() -> void:
	var area := Area3D.new()
	area.name = "Detect"
	var c := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = detect_range
	c.shape = sph
	area.add_child(c)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)

func _on_body_entered(body: Node) -> void:
	if body == GameManager.player:
		if _can_see(body):
			target = body
			if state == State.IDLE:
				state = State.CHASE if is_aggressive else State.FLEE
	elif body.is_in_group("companion") and body.get("is_dead") != true and _can_see(body):
		target = body
		if state == State.IDLE:
			state = State.CHASE if is_aggressive else State.FLEE

func _on_body_exited(body: Node) -> void:
	if body == target:
		target = null

## 侦测：玩家在侦测半径内即被发现（360°，不再限制正前方视野锥，
## 避免从背后/侧面靠近时动物完全看不见、导致「怪不理我 / 打不到」）。
## 慢速移动(潜行)时侦测半径减半，仍可悄悄靠近。
func _can_see(p: Node3D) -> bool:
	var to := p.global_position - global_position
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()
	if dist > detect_range:
		return false
	var spd := 0.0
	if p is CharacterBody3D:
		spd = p.velocity.length()
	var eff := detect_range
	if spd < 1.5:
		eff *= 0.5
	return dist <= eff

## 索敌：在侦测范围内挑选最近的可攻击目标（玩家或存活的伙伴）。
func _acquire_target() -> Node3D:
	var best: Node3D = null
	var best_d := detect_range
	var p = GameManager.player
	if p != null and is_instance_valid(p) and _can_see(p):
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	for cld in get_tree().get_nodes_in_group("companion"):
		if cld == null or not is_instance_valid(cld):
			continue
		if cld.get("is_dead") == true:
			continue
		if not _can_see(cld):
			continue
		var d := global_position.distance_to(cld.global_position)
		if d < best_d:
			best_d = d
			best = cld
	return best

func _on_player_attacked(tgt, dmg: float) -> void:
	if tgt == self:
		take_damage(dmg, GameManager.player)

func take_damage(dmg: float, source: Node = null) -> void:
	if dead:
		return
	if source != null:
		_killer = source
	health -= dmg
	var hit_dir := Vector3.ZERO
	if source != null:
		hit_dir = global_position - source.global_position
		hit_dir.y = 0.0
	var by_player: bool = source != null and source == GameManager.player
	EventBus.hit_registered.emit(self, hit_dir, dmg, by_player)
	_flash()
	if _hp_bar != null:
		_hp_bar.set_fraction(health / max_health)
	EventBus.damage_popup.emit(global_position + Vector3(0, 2.4, 0), dmg, "enemy")
	if health <= 0.0:
		die()

func apply_knockback(dir: Vector3, strength: float) -> void:
	if dead:
		return
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() > 0.001:
		d = d.normalized()
	_knockback += d * strength

func _flash() -> void:
	if body_mesh == null:
		return
	var base := body_mesh.scale
	var t := create_tween()
	t.tween_property(body_mesh, "scale", base * 1.2, 0.08)
	t.tween_property(body_mesh, "scale", base, 0.12)

func die() -> void:
	dead = true
	state = State.DEAD
	velocity = Vector3.ZERO
	if _hp_bar != null:
		_hp_bar.visible = false
	# 最后一击来源记在 self._killer 上，由 GameManager 从 creature 节点读取（信号参数不能带默认值）
	EventBus.creature_died.emit(self, drops)
	EventBus.xp_awarded.emit(int(xp_reward))
	# 优先播放死亡动画（怪物有 Die 动画）；否则用缩放到 0 兜底
	var dead_anim: String = anim_map.get("dead", "")
	if anim != null and dead_anim != "" and anim.has_animation(dead_anim):
		anim.play(dead_anim, 0.05)
		var dur: float = anim.get_animation(dead_anim).length
		var t := get_tree().create_timer(dur)
		t.timeout.connect(queue_free)
	else:
		var t := create_tween()
		t.tween_property(self, "scale", Vector3.ZERO, 0.4)
		t.tween_callback(queue_free)

func _physics_process(delta: float) -> void:
	if dead:
		return
	# 竖直：用重力 + 胶囊碰撞真正贴地（物理引擎介入），不再硬传送。
	# 若极端情况下没踩到地形（穿地间隙），用高度场兜底回拉，避免掉出世界。
	var ground_y := _ground_height_at(global_position.x, global_position.z)

	# BOSS 跳击：跳跃中由脚本驱动抛物线位移，跳过常规移动/重力
	if _jumping:
		_tick_jump_attack(delta, ground_y)
		_update_anim()
		return

	# 锁敌：玩家或附近伙伴皆可成为目标（伙伴会吸引仇恨，可被攻击致死）
	if target == null:
		target = _acquire_target()
		if target != null and state == State.IDLE:
			state = State.CHASE if is_aggressive else State.FLEE

	if target != null and is_instance_valid(target):
		# 目标已死 / 跑太远 -> 失去仇恨，下一帧重新索敌
		var _lost := false
		if target != GameManager.player and target.get("is_dead") == true:
			_lost = true
		if not _lost and global_position.distance_to(target.global_position) > detect_range * 1.8:
			_lost = true
		if _lost:
			target = null

	if target != null and is_instance_valid(target):
		var to := target.global_position - global_position
		var dist := to.length()
		if not is_aggressive:
			# 被动动物：远离玩家（逃跑时仍回头盯着威胁）
			state = State.FLEE
			var flat := Vector3(-to.x, 0, -to.z)
			if flat.length() > 0.001:
				flat = flat.normalized()
			velocity.x = flat.x * flee_speed
			velocity.z = flat.z * flee_speed
			_face(flat)
			_facing = -flat    # 逃跑时面朝来敌（玩家方向）
			if dist > detect_range * 1.6:
				target = null
		elif dist > attack_range:
			# BOSS 在中距离且跳击冷却就绪时，发动跳击扑向目标（跳+劈）
			if is_boss and is_instance_valid(target) and _jump_cd <= 0.0 and not attacking and not _jumping and dist <= jump_attack_range:
				_start_jump_attack()
			else:
				state = State.CHASE
				var flat := Vector3(to.x, 0, to.z)
				if flat.length() > 0.001:
					flat = flat.normalized()
				velocity.x = flat.x * enemy_speed
				velocity.z = flat.z * enemy_speed
				_face(flat)
				_facing = flat
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			if attack_cooldown <= 0.0 and not attacking:
				_start_attack()
	elif is_sieger:
		_siege_step()
	else:
		state = State.IDLE
		velocity.x = 0.0
		velocity.z = 0.0

	if attack_cooldown > 0.0:
		attack_cooldown -= delta

	if _jump_cd > 0.0:
		_jump_cd -= delta

	# 竖直处理：重力让身体自然下落（避免悬空/穿地），落地或偏离地表时
	# 用高度场把脚底锚定到可视地表（terrain_height 与地形可视网格同源，
	# 保证脚不陷、不浮）。水平移动仍由 move_and_slide 的碰撞处理。
	velocity.x += _knockback.x
	velocity.z += _knockback.z
	_knockback = _knockback.move_toward(Vector3.ZERO, KNOCK_DECAY * delta)
	velocity.y -= GRAVITY * delta
	move_and_slide()
	if global_position.y > ground_y + 0.05 or not is_on_floor():
		global_position.y = ground_y
		velocity.y = 0.0
	_update_anim()
	# 动物行走摆动（仅无骨骼动画的模型/图元，用正弦起伏表现移动；带骨骼动画的由动画本身表现）
	if _animal_root != null and anim == null:
		if state == State.CHASE or state == State.FLEE:
			_bob_t += delta * 12.0
			_animal_root.position.y = sin(_bob_t) * 0.07
		else:
			_animal_root.position.y = lerp(_animal_root.position.y, 0.0, 0.2)

## 当前 (x,z) 的地表高度（委托给 World 的同一套高度函数）。
func _ground_height_at(x: float, z: float) -> float:
	if GameManager.world != null and GameManager.world.has_method("get_ground_height"):
		return GameManager.world.call("get_ground_height", x, z)
	return 0.0

func _face(dir: Vector3) -> void:
	if body_mesh == null:
		return
	var target_yaw := atan2(dir.x, dir.z) + _animal_yaw_offset
	body_mesh.rotation.y = lerp_angle(body_mesh.rotation.y, target_yaw, 0.2)

## 当前应播放的攻击动画名：在 attack / attack2 之间轮换（attack2 不存在则一直用 attack）。
## 若动画系统里没有 attack2，也自动退回 attack，避免播放空名。
func _current_attack_anim() -> String:
	var a1: String = anim_map.get("attack", "")
	var a2: String = anim_map.get("attack2", "")
	if a2 == "" or anim == null or not anim.has_animation(a2):
		return a1
	if a1 == "" or not anim.has_animation(a1):
		return a2
	return a2 if (_attack_toggle % 2) == 1 else a1

func _start_attack() -> void:
	attacking = true
	state = State.ATTACK
	var atk := ""
	if anim != null:
		atk = _current_attack_anim()
		_active_attack = atk
		_attack_toggle += 1   # 下次换另一招
		if atk != "" and anim.has_animation(atk):
			anim.play(atk, 0.1)
			# 命中帧结算伤害（只发伤害，不在这里结束攻击，否则动画会被提前切回）
			var dmg_t := get_tree().create_timer(0.45)
			dmg_t.timeout.connect(_deal_attack_damage)
	var atk_len := 0.5
	if atk != "" and anim != null and anim.has_animation(atk):
		atk_len = anim.get_animation(atk).length
	# 动画放完才结束本次攻击：避免 _update_anim 在 0.45s 处把攻击动作切回待机（表现为只打一半/反复重启）
	var end_t := get_tree().create_timer(maxf(atk_len, 0.5))
	end_t.timeout.connect(_end_attack)

func _deal_attack_damage() -> void:
	# 注意：这里只结算伤害，不置 attacking=false（结束由 _end_attack 在动画放完后处理）
	if dead or target == null or not is_instance_valid(target):
		return
	if target.get("is_dead") == true:
		return
	if global_position.distance_to(target.global_position) <= attack_range + 0.5:
		if target == GameManager.player:
			EventBus.player_damaged.emit(attack_damage)
		elif target.has_method("take_damage"):
			target.take_damage(attack_damage)
			EventBus.damage_popup.emit(target.global_position + Vector3(0, 2.4, 0), attack_damage, "enemy")

func _end_attack() -> void:
	attacking = false
	attack_cooldown = attack_interval   # 本次攻击结束后，再等一个间隔才出手（防连击被切断/连续重启）
	if is_boss:
		_jump_cd = jump_attack_cooldown  # BOSS 普通攻击/跳击结束后，重置跳击冷却

## 攻营模式（夜袭怪 is_sieger=true 专用）：玩家/伙伴不在侦测范围内时，主动寻路至最近栅栏并攻击它，
## 把原本「隐形计时器砸栅栏」变成可见的真实围攻。玩家一旦进入侦测范围，仍优先去打玩家（见 _physics_process）。
func _siege_step() -> void:
	if _siege_target == null or not is_instance_valid(_siege_target) or _siege_target.hp <= 0.0:
		_siege_target = Fences.nearest(global_position)
	if _siege_target == null or not is_instance_valid(_siege_target):
		state = State.IDLE
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var to := _siege_target.global_position - global_position
	var dist := to.length()
	if dist > attack_range:
		state = State.CHASE
		var flat := Vector3(to.x, 0, to.z)
		if flat.length() > 0.001:
			flat = flat.normalized()
		velocity.x = flat.x * enemy_speed
		velocity.z = flat.z * enemy_speed
		_face(flat)
		_facing = flat
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if attack_cooldown <= 0.0 and not attacking:
			_start_fence_attack()

## 攻营攻击：与玩家攻击同套挥击动画，命中帧对最近栅栏结算伤害（复用 Fences.damage_nearest）。
func _start_fence_attack() -> void:
	attacking = true
	state = State.ATTACK
	var atk := ""
	if anim != null:
		atk = _current_attack_anim()
		_active_attack = atk
		_attack_toggle += 1   # 下次换另一招
		if atk != "" and anim.has_animation(atk):
			anim.play(atk, 0.1)
			var dmg_t := get_tree().create_timer(0.45)
			dmg_t.timeout.connect(_deal_fence_damage)
	var atk_len := 0.5
	if atk != "" and anim != null and anim.has_animation(atk):
		atk_len = anim.get_animation(atk).length
	var end_t := get_tree().create_timer(maxf(atk_len, 0.5))
	end_t.timeout.connect(_end_attack)

func _deal_fence_damage() -> void:
	if dead:
		return
	if _siege_target == null or not is_instance_valid(_siege_target):
		return
	if global_position.distance_to(_siege_target.global_position) <= attack_range + 0.5:
		Fences.damage_nearest(global_position, attack_damage)

## ============================================================
## BOSS 跳击（跳+劈）：脚本驱动抛物线扑向目标，落地前下劈结算伤害。
## 跳击动画（Jump_Attack）是 Mixamo「in-place」动作，无根位移，故由脚本补上水平冲刺+竖直抛物线，
## 形成「跃起→扑向玩家→落地重击」的观感。
func _start_jump_attack() -> void:
	attacking = true
	state = State.ATTACK
	_jumping = true
	var atk: String = jump_attack_anim
	_active_attack = atk
	if anim != null and atk != "" and anim.has_animation(atk):
		anim.play(atk, 0.1)
	_jump_from = global_position
	_jump_to = target.global_position if (target != null and is_instance_valid(target)) else global_position
	_jump_t = 0.0
	_jump_dur = 1.2
	if atk != "" and anim != null and anim.has_animation(atk):
		_jump_dur = anim.get_animation(atk).length
	# 下劈命中帧（落地前约 60% 处）结算伤害
	var dmg_t := get_tree().create_timer(_jump_dur * 0.6)
	dmg_t.timeout.connect(_deal_jump_damage)
	var end_t := get_tree().create_timer(_jump_dur)
	end_t.timeout.connect(_end_attack)

func _tick_jump_attack(delta: float, ground_y: float) -> void:
	_jump_t += delta
	var u := clampf(_jump_t / _jump_dur, 0.0, 1.0)
	# 水平插值冲向落点 + 竖直抛物线
	var flat := _jump_from.lerp(_jump_to, u)
	var arc := sin(u * PI) * _jump_height
	global_position = Vector3(flat.x, ground_y + arc, flat.z)
	velocity = Vector3.ZERO
	if body_mesh != null:
		var d := _jump_to - _jump_from
		d.y = 0.0
		if d.length() > 0.001:
			body_mesh.rotation.y = lerp_angle(body_mesh.rotation.y, atan2(d.x, d.z), 0.2)
	if u >= 1.0:
		_jumping = false
		global_position.y = ground_y
		velocity = Vector3.ZERO

func _deal_jump_damage() -> void:
	if dead:
		return
	if target == null or not is_instance_valid(target):
		return
	# 落地附近才命中（落点就是起跳时玩家所在，扑过去应当贴脸）
	if global_position.distance_to(target.global_position) <= attack_range + 4.0:
		if target == GameManager.player:
			EventBus.player_damaged.emit(jump_attack_damage)
		elif target.has_method("take_damage"):
			target.take_damage(jump_attack_damage)
		EventBus.damage_popup.emit(target.global_position + Vector3(0, 2.4, 0), jump_attack_damage, "enemy")


func _update_anim() -> void:
	if dead or anim == null or anim_map.is_empty():
		return
	var want: String
	if state == State.ATTACK and attacking:
		# 用本次实际选中的攻击动画，别每帧强制切回 attack（否则会把 attack2 顶掉）
		want = _active_attack
		if want != "" and anim.current_animation != want:
			anim.play(want, 0.1)
		return
	if state == State.CHASE or state == State.FLEE:
		want = anim_map.get("walk", anim_map.get("run", anim_map.get("idle", "")))
	else:
		want = anim_map.get("idle", "")
	if want != "" and anim.has_animation(want) and anim.current_animation != want:
		anim.play(want, 0.15)
