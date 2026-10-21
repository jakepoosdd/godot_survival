extends Node
## 角色注册表（Autoload: CharacterRegistry）。
## 数据驱动的角色来源：
##   1) 内置角色：下面的 BUILTIN 数组（直接复用 player.gd 原来的 CHARACTERS 结构）。
##   2) 外部 MOD：扫描 user://mods/characters/ 下的 *.glb / *.gltf，
##      用 GLTFDocument 在运行时导入（无需编辑器预导入，社区任意 GLB 都能用），
##      并自动按 idle/walk/run/fall/attack 子串匹配动画名。
##
## 用法：
##   - player.gd 通过 get_character(index) 取可视体来源与动画映射；
##   - 主菜单通过 get_characters() 列出、set_selected(i) 选择并持久化。

const MOD_DIR := "user://mods/characters/"
const SEL_PATH := "user://character_selection.cfg"

## 内置角色（与 player.gd 原 CHARACTERS 一致）。scene_path 为 res:// 下的 GLB。
## ch23 = 男主（D 盘 Ch23 模型 + 项目通用人物动作 UAL_Standard 重定向），默认使用。
const BUILTIN: Array = [
	{
		"id": "ch23", "name": "男主(Ch23)", "scene_path": "res://player/Ch23_Lead.glb",
		"scale": 1.0, "y_offset": 0.0, "yaw_offset": 0.0, "walk_speed": 1.06, "run_speed": 2.60,
		"anim": {"idle": "Idle_Loop", "walk": "Walk_Loop", "run": "Sprint_Loop",
		         "fall": "Jump_Loop", "attack": ["Punch_Jab", "Punch_Cross", "Sword_Attack"]}
	},
	# ⚠️ 原「探险者(RPG)」条目（id=rpg, RPG_Character.glb）已被用户判定为做坏的模型，
	#    于 2026-10-14 从可选角色列表移除。注意：RPG_Character.glb **文件保留**——
	#    enemy/enemy.gd 的 visual_path 默认仍指向它（人形野怪 Raider/Boss 复用该网格），
	#    删除文件会让敌人失去可视体。
	{
		"id": "maria", "name": "大剑女(Maria)", "scene_path": "res://player/Maria_Companion.glb",
		"scale": 1.0, "y_offset": 0.0, "yaw_offset": 0.0, "walk_speed": 1.54, "run_speed": 2.57,
		"anim": {"idle": "Idle_Loop", "walk": "Walk_Loop", "run": "Sprint_Loop",
		         "attack": ["Sword_Attack", "Sword_Slash"], "block": "Block_Idle",
		         "turn": "Turn_180", "die": "Die"}
	},
	{
		"id": "erika", "name": "弓箭手(Erika)", "scene_path": "res://player/Erika_Archer.glb",
		"scale": 1.0, "y_offset": 0.0, "yaw_offset": 0.0, "walk_speed": 1.44, "run_speed": 3.18,
		"anim": {"idle": "Idle_Loop", "walk": "Walk_Loop", "run": "Sprint_Loop",
		         "fall": "Jump_Loop", "attack": ["Bow_Draw", "Bow_Aim"],
		         "block": "Block_Idle", "turn": "Turn_L_90", "die": "Die"}
	},
	{
		"id": "arissa", "name": "魔法师(Arissa)", "scene_path": "res://player/Arissa_Mage.glb",
		"scale": 1.0, "y_offset": 0.0, "yaw_offset": 0.0, "walk_speed": 1.90, "run_speed": 5.82,
		"anim": {"idle": "Idle_Loop", "walk": "Walk_Loop", "run": "Sprint_Loop",
		         "fall": "Jump_Loop", "cast": "Cast_Heal",
		         "attack": ["Magic_Attack", "Magic_Attack2"],
		         "block": "Block_Idle", "turn": "Turn_L_90", "die": "Die"}
	},
	{
		# 剑士：由持剑 Kachujin（右手握拳姿态已烤进 rest pose）替换原斧战兵。
		# 攻击动画**复用斧招** Axe_Chop/Axe_Swing（用户定夺：最快/零风险，不新做剑招）。
		# 青铜剑运行时经 weapon_mount 挂到右手（WEAPON_BY_CHAR kachujin->sword）。
		"id": "kachujin", "name": "剑士(Kachujin)", "scene_path": "res://player/Kachujin_Sword.glb",
		"scale": 1.0, "y_offset": 0.0, "yaw_offset": 0.0, "walk_speed": 1.50, "run_speed": 2.29,
		# ⚠️ Kachujin_Sword.glb 实测动画名（glTF chunk 直读，与旧 Axe 版完全一致）：
		#   Axe_Chop / Axe_Swing / Block_Idle / Die / Idle_Loop / Jump_Loop /
		#   Sprint_Loop / Turn_L_90 / Walk_Loop
		#   即**带 _Loop 后缀**——与其它角色命名一致。曾误改成无后缀的 Idle/Walk/Sprint
		#   → 四个 locomotion 全部 has_animation()=false，角色站着不动/滑步（飘逸）。
		"anim": {"idle": "Idle_Loop", "walk": "Walk_Loop", "run": "Sprint_Loop",
		         "fall": "Jump_Loop", "attack": ["Axe_Chop", "Axe_Swing"],
		         "block": "Block_Idle", "turn": "Turn_L_90", "die": "Die"}
	},
	{
		"id": "ch46", "name": "小孩(Ch46)", "scene_path": "res://player/Ch46_Child.glb",
		"scale": 1.0, "y_offset": 0.0, "yaw_offset": 0.0, "walk_speed": 0.96, "run_speed": 1.53,
		"anim": {"idle": "Idle_Loop", "walk": "Walk_Loop", "run": "Sprint_Loop",
		         "fall": "Jump_Loop", "attack": ["Hurricane_Kick"], "die": "Die"}
	}
]

var _all: Array = []
var _selected_id: String = "ch23"

func _ready() -> void:
	_load_selection()
	_scan()

# =========================================================
# 扫描
# =========================================================
func _scan() -> void:
	_all = BUILTIN.duplicate(true)
	# 内置角色若带 scene_path（res:// 下的 GLB），优先用引擎 load() 走 import remap 导入
	# （PCK 内 .glb 已被导入成 .scn，带贴图，最稳）；load 失败才回退 GLTFDocument（user:// MOD）。
	for def in _all:
		if def.has("scene_path") and not def.has("packed"):
			var pk := _import_as_packed(def["scene_path"])
			if pk != null:
				def["packed"] = pk
	var dir := DirAccess.open(MOD_DIR)
	if dir == null:
		var base := DirAccess.open("user://")
		if base != null:
			base.make_dir_recursive("mods/characters/")
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and (fname.ends_with(".glb") or fname.ends_with(".gltf")):
			_add_mod(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	# 保证选中项仍存在，否则回退到内置第一个
	if not _has_id(_selected_id):
		_selected_id = _all[0]["id"]

## 重新扫描（例如游戏运行中放入了新 MOD 后调用）。
func rescan() -> void:
	_scan()

func _add_mod(fname: String) -> void:
	var path := MOD_DIR + fname
	var packed := _import_as_packed(path)
	if packed == null:
		return
	var root: Node = packed.instantiate()
	var anim := _auto_anim(root)
	var id := fname.get_basename()
	var meta := _load_meta(fname)
	var def := {
		"id": id,
		"name": meta.get("name", fname.get_basename()),
		"packed": packed,
		"scale": float(meta.get("scale", 1.0)),
		"y_offset": float(meta.get("y_offset", 0.0)),
		"yaw_offset": float(meta.get("yaw_offset", PI)),
		"anim": anim
	}
	_all.append(def)

## GLTFDocument 兜底加载入口（仅当上层 load() 失败时调用，例如 user:// MOD 未预导入的磁盘 glb）。
## ⚠️ 导出包(PCK)内 .glb 的「源文件」并不以可读字节存在，必须先由 load() 走 import remap 加载；
##    此函数只用于磁盘上的 glb（user:// MOD），用 append_from_file 即可。
func _gltf_load(gltf: GLTFDocument, state: GLTFState, scene_path: String) -> int:
	var err := gltf.append_from_file(scene_path, state)
	if err == OK:
		return OK
	# 回退：FileAccess 是 PCK 感知的，res:// 在包内可正常读字节
	if FileAccess.file_exists(scene_path):
		var bytes := FileAccess.get_file_as_bytes(scene_path)
		if bytes.size() > 0:
			return gltf.append_from_buffer(bytes, scene_path, state)
	return err

## 用 GLTFDocument 在运行时直接导入 GLB（res:// 或 user:// 路径均可），返回打包好的 PackedScene。
## 不依赖编辑器 .import 缓存，headless 下也稳。失败返回 null。
##
## ⚠️ 关键：导出包(PCK)内 .glb 的「源文件」并不会以可读字节存在，Godot 只打包了导入后的 .scn/.ctex，
##    并用 import remap 把 res://x.glb → res://.godot/imported/x.scn。因此：
##      - 必须用引擎资源管线 load()（走 remap，PCK 内正确拿到带贴图的场景）；
##      - 绝不能用 GLTFDocument.append_from_file / FileAccess 直接读 .glb 源（PCK 内读不到，必失败）。
##    GLTFDocument 仅作为「user:// MOD 等未预导入 glb」的磁盘回退。
func _import_as_packed(scene_path: String) -> PackedScene:
	# 优先 load()（PCK 内最稳，带贴图）
	var res := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if res is PackedScene:
		var inst := (res as PackedScene).instantiate()
		_ensure_reset(inst)
		var packed := PackedScene.new()
		if packed.pack(inst) != OK:
			inst.free()
			printerr("[CharacterRegistry] GLB 重新打包失败: ", scene_path, "（退回原导入场景）")
			return res as PackedScene
		inst.free()
		return packed
	# 回退：GLTFDocument 运行时导入（user:// MOD 等未预导入的 glb，磁盘可用）
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := _gltf_load(gltf, state, scene_path)
	if err != OK:
		printerr("[CharacterRegistry] GLB 导入失败: ", scene_path, " err=", err)
		return null
	var root: Node = gltf.generate_scene(state)
	if root == null:
		printerr("[CharacterRegistry] GLB 生成场景失败: ", scene_path)
		return null
	# 运行时补 RESET 动画（GLTFDocument 导入不带 .import 的 import_rest_as_RESET，
	# 缺失 RESET 会让一次性动画结束后骨头停在上一姿势、武器挂点错位）。
	_ensure_reset(root)
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		printerr("[CharacterRegistry] GLB 打包失败: ", scene_path)
		return null
	return packed

## 自动识别动画：按关键子串在 AnimationPlayer 的动画列表里挑。
func _auto_anim(root: Node) -> Dictionary:
	var ap: AnimationPlayer = _find_anim_player(root)
	var out := {}
	if ap == null:
		return out
	var names := ap.get_animation_list()
	out["idle"] = _pick(names, ["idle"])
	out["walk"] = _pick(names, ["walk"])
	out["run"]  = _pick(names, ["run", "sprint"])
	out["fall"] = _pick(names, ["fall", "jump", "falling"])
	out["attack"] = _pick_multi(names, ["attack", "atk", "slash", "hit", "combo"])
	return out

## 把「期望动画名」解析为 AnimationPlayer 里**真实存在**的名字。
## 容忍：精确命中 → 补/去 `_Loop` 后缀 → 大小写 → 前缀子串（唯一命中才采纳）。
## 目的：GLB 重新导出后动画名是否带 `_Loop` 变化，都不会再让角色「站着不动/滑步」。
## 解析不到返回 ""（调用方保持原值或跳过）。
static func resolve_anim_name(ap: AnimationPlayer, want: String) -> String:
	if ap == null:
		return ""
	var w := want.strip_edges()
	if w == "":
		return ""
	if ap.has_animation(w):
		return w
	var cands: Array = [w + "_Loop", w + "_loop"]
	if w.ends_with("_Loop"):
		cands.append(w.substr(0, w.length() - 5))
	if w.ends_with("_loop"):
		cands.append(w.substr(0, w.length() - 5))
	for c in cands:
		if ap.has_animation(c):
			return c
	var lw := w.to_lower()
	# 唯一前缀命中才采纳，避免 Idle 错配到 Idle_Talking_Loop
	var hit := ""
	for n in ap.get_animation_list():
		var ln := String(n).to_lower()
		if ln == lw:
			return String(n)
		if ln.begins_with(lw) or lw.begins_with(ln):
			if hit != "":
				return ""
			hit = String(n)
	return hit

## 批量解析一张 anim 表；值可为 String 或 Array[String]。
static func resolve_anim_map(ap: AnimationPlayer, raw: Dictionary) -> Dictionary:
	if ap == null:
		return raw
	var out := {}
	for k in raw.keys():
		var v = raw[k]
		if v is Array:
			var arr: Array = []
			for nm in v:
				var r := resolve_anim_name(ap, String(nm))
				if r != "":
					arr.append(r)
			out[k] = arr if not arr.is_empty() else v
		else:
			var r2 := resolve_anim_name(ap, String(v))
			out[k] = r2 if r2 != "" else v
	return out

func _pick(names: PackedStringArray, keys: Array) -> String:
	for k in keys:
		for n in names:
			if n.to_lower().contains(k):
				return n
	return ""

func _pick_multi(names: PackedStringArray, keys: Array) -> Array:
	var res: Array = []
	for n in names:
		for k in keys:
			if n.to_lower().contains(k):
				res.append(n)
				break
	return res

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null

## 运行时给导入的 GLB 补一个 RESET 动画：把每条骨骼轨道路径设为该骨骼的 rest 局部变换。
## Godot 在混合/一次性动画结束、或 stop() 时会自动用 RESET 把未覆盖的骨头拉回静止姿态，
## 否则骨头会停在上一动作的姿势（攻击手收不回、武器挂点偏移）。
## 若已存在 RESET（部分导出带）则跳过；rest 取不到时退化为全 identity，等同无操作、不报错。
func _ensure_reset(root: Node) -> void:
	var ap: AnimationPlayer = _find_anim_player(root)
	if ap == null:
		return
	var skel: Skeleton3D = _find_skeleton(root)
	if skel == null:
		return
	if ap.has_animation("RESET"):
		return
	# 骨骼轨道路径相对 AnimationPlayer 的父节点（root_node 默认为空 = 取父节点）。
	var anchor: Node = ap.get_parent()
	if anchor == null:
		anchor = ap
	var skel_path: String = anchor.get_path_to(skel)
	var reset := Animation.new()
	reset.length = 0.0
	for i in skel.get_bone_count():
		var bname: String = skel.get_bone_name(i)
		var rest: Transform3D = skel.get_bone_rest(i)
		# ⚠️ 一条骨骼的「静止姿态」需拆成三条**独立类型**的轨道各插一帧：
		#    Godot 4.7 轨道类型枚举为 1=POSITION_3D / 2=ROTATION_3D / 3=SCALE_3D，
		#   且 position/rotation/scale_track_insert_key 只接受各自对应类型的轨道。
		#    原代码 add_track(1) 实为位置轨道，却在同一轨道上又调 rotation/scale 插入 →
		#    触发 t->type 断言失败、写入无效 key → RESET 轨道数据损坏（headless 遍历段错误，
		#    真实游戏 RESET 动画也会异常）。正确做法是分别建 1/2/3 三类轨道。
		var tp := reset.add_track(1)  # TYPE_POSITION_3D
		reset.track_set_path(tp, "%s:%s" % [skel_path, bname])
		reset.position_track_insert_key(tp, 0.0, rest.origin)
		var tr := reset.add_track(2)  # TYPE_ROTATION_3D
		reset.track_set_path(tr, "%s:%s" % [skel_path, bname])
		reset.rotation_track_insert_key(tr, 0.0, rest.basis.get_rotation_quaternion())
		var ts := reset.add_track(3)  # TYPE_SCALE_3D
		reset.track_set_path(ts, "%s:%s" % [skel_path, bname])
		reset.scale_track_insert_key(ts, 0.0, rest.basis.get_scale())
	# Godot 4：动画存在 AnimationLibrary 里，默认库名为空字符串 ""。
	# 不能调 AnimationPlayer.add_animation（该方法不存在）。
	var lib = ap.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		ap.add_animation_library("", lib)
	lib.add_animation("RESET", reset)

func _load_meta(fname: String) -> Dictionary:
	var mpath := MOD_DIR + fname.get_basename() + ".json"
	if not FileAccess.file_exists(mpath):
		return {}
	var f := FileAccess.open(mpath, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	return {}

# =========================================================
# 查询 / 选择
# =========================================================
func get_characters() -> Array:
	return _all

func get_character(index: int) -> Dictionary:
	if index < 0 or index >= _all.size():
		return _all[0]
	return _all[index]

## 按 id 查角色定义（供伙伴系统取 GLB / 动画映射）。
func find_by_id(id: String) -> Dictionary:
	for c in _all:
		if c["id"] == id:
			return c
	return {}

func get_selected_index() -> int:
	for i in _all.size():
		if _all[i]["id"] == _selected_id:
			return i
	return 0

func set_selected(index: int) -> void:
	if index < 0 or index >= _all.size():
		return
	_selected_id = _all[index]["id"]
	_save_selection()

func _has_id(id: String) -> bool:
	for c in _all:
		if c["id"] == id:
			return true
	return false

func _load_selection() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SEL_PATH) == OK:
		_selected_id = cfg.get_value("char", "selected", "ch23")

func _save_selection() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("char", "selected", _selected_id)
	cfg.save(SEL_PATH)
