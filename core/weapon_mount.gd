extends RefCounted
## =========================================================================
##  WeaponMount —— 运行时武器挂载（一个角色 GLB × N 把武器，随时秒换）
## =========================================================================
## 为什么需要它：
##   之前把斧「烘焙」进 Kachujin_Axe.glb（Blender 里绑定到手骨再导出）确实是对的
##   ——但那意味着 **一个角色 × 一把武器就得重新导一次 GLB**，9 个动作全部重烤。
##   主角要能「1~6 键秒换武器」，就必须把「装到手上」这件事挪到运行时。
##
## 关键实测结论（tools/_probe_proj 下隔离工程验证，用完即删）：
##   1) Godot 的 GLTFDocument 会把「父节点是骨骼节点」的子节点**自动升级成
##      BoneAttachment3D**（Skeleton3D > mixamorig_RightHand > 武器 MeshInstance3D）。
##      => 「Blender 烘焙法」和「运行时挂载法」在运行时是**同一套节点结构**。
##   2) 该 BoneAttachment3D **逐帧跟随手骨**：40 个采样点「实际位置 vs 由当前骨骼
##      姿势解析出的应有位置」误差恒为 0.000000 m，斧心到手骨距离恒为 0.0970 m。
##      （只是比 seek 晚一帧更新，属更新顺序，游戏里看不出来。）
##   3) 手部解剖轴（2026-10-12 用骨架手指关节实测，非假设）：
##      用 Index1/Middle1/Ring1/Pinky1 四个指节 MCP 实测（手骨局部空间）：
##        F = 腕->指节均值          ≈ 手骨 +Y（手指伸出方向）
##        K = 食指MCP -> 小指MCP    ≈ 手骨 -X（指节线方向）
##        掌面法线                  ≈ 手骨 -Z（指尖蜷曲分量证实）
##      Idle 姿态下（手臂下垂）：世界下方 ≈ 手骨 -X（小指侧）。
##      => 单手武器正确挂法：柄沿 F 从拳里向前伸出（握刀式），
##         刃面沿 _axB = 「世界下方」投影到 ⊥柄平面（Idle 实测，满足「斧刃朝下」），
##         握点 = 腕与四指指节均值的中点（真实掌心）。
##      旧规则「柄沿手骨 X」会让柄竖着压在手背上（用户截图实锤），废除。
## =========================================================================

const RIGHT_HAND_BONE := "mixamorig:RightHand"

## ⚠️ 挂点的语义支点 = **掌心（掌骨）**，不是腕。
##   Godot 的 BoneAttachment3D 挂在骨上时，支点恒为该骨的**原点（head）**；
##   mixamorig:RightHand 的 head 在**腕**，直接把武器挂上去 = 「武器绕腕转」。
##   所以这里统一再垫一层 PalmPoint（平移到实测掌心、并把链上缩放补偿掉），
##   武器挂在 PalmPoint 下 —— 支点、换手、握持微调都落在掌心这个语义点上。
##   （2026-10-12 用户口径：「握住武器应该挂在掌骨上」）

## 真正的「掌骨」优先：有独立掌骨的骨架（Rigify / UE / Vroid 等）先用它，
## 它比 hand 骨更靠近握持点，手指弯曲动画也不会带歪武器。
const PALM_BONE_CANDIDATES: Array[String] = [
	"mixamorig:RightHandPalm",
	"RightHandPalm",
	"palm.R",
	"palm_r",
	"Palm_R",
	"hand_palm_r",
	"RightPalm",
]

## 不同来源角色的右手骨命名兜底表。实测覆盖率：
##   mixamorig 系可选主角（ch23/maria/erika/arissa/kachujin/ch46）
##   命中首项；RPG_Character.glb 用 Blender 默认命名 "hand.r"，靠第 3 项兜住。
## ⚠️ Mixamo 没有独立掌骨（实测 Kachujin_Axe.glb 68 根骨里 0 个 palm），
##    此时 RightHand 骨本身就是「腕->掌指关节」的掌段，配合 PalmPoint 偏移即可等效。
const HAND_BONE_CANDIDATES: Array[String] = [
	"mixamorig:RightHand",
	"RightHand",
	"hand.r",
	"Hand_R",
	"RightHandIndex1",
]

## 指节 MCP 骨命名兜底（用于实测掌心与解剖轴；缺骨时退回近似锚点）。
const KNUCKLE_BONES: Array[String] = [
	"mixamorig:RightHandIndex1",
	"mixamorig:RightHandMiddle1",
	"mixamorig:RightHandRing1",
	"mixamorig:RightHandPinky1",
]

## 指节骨缺失时的退路（Mixamo rest 实测近似，单位=挂点空间 0.01m）。
const FALLBACK_F := Vector3(0, 1, 0)
const FALLBACK_K := Vector3(-1, 0, 0)
const FALLBACK_PALM := Vector3(0, 4.5, 0)   # 腕前方 4.5cm

## 武器参数表。新增一把武器 = 加一条数据，不改任何逻辑。
##   ⚠️ 所有向量都是「武器根节点空间」（gltf 资产节点可能自带旋转，
##      Axe_Bronze 就是网格 X 轴 = 节点 -Y 轴，别拿网格空间的数据直接填！）
##   handle : 节点空间里「由工作端指向柄尾」的单位向量
##   flare  : 节点空间里「刃口展开方向」的单位向量（需垂直于 handle）
##   grip   : 节点空间里「掌心应落在」的坐标（米），必须落在柄部（2026-10-12 用户口径：
##            单手武器一律握柄部，距柄尾约一个拳位 ≈ 7cm；剑握在护手与配重之间）
##   2026-10-12 全部条目经「Chop 劈砍方向 + 刃面朝外」判据自动验证（头端劈砍时触最低点、
##   水平前移大于柄端、刃面·面向 > 0），见探针 zz_auto/zz_verify 输出。
const WEAPON_TABLE := {
	"axe": {
		"path": "res://assets/fantasy_props/Axe_Bronze_Rigged.tscn",
		# 节点空间：长轴 Y，斧头重端 +Y，柄尾 -Y（Gator 搭骨版，xform 已烤进顶点，
		# 根节点空间与原始 Axe_Bronze.gltf 一致，故 handle/flare/grip 仍成立）
		"handle": Vector3(0, -1, 0),
		"flare": Vector3(1, 0, 0),
		"grip": Vector3(0.02, -0.33, 0),  # 更靠柄尾(-0.381)，约 5cm，握在斧柄底部
		"verified": true,
	},
	"pickaxe": {
		"path": "res://assets/fantasy_props/Pickaxe_Bronze.gltf",
		# 节点=网格空间：长轴 Y，镐头重端 +Y，柄尾 -Y
		"handle": Vector3(0, -1, 0),
		"flare": Vector3(1, 0, 0),
		"grip": Vector3(0, -0.42, 0),     # 柄尾(-0.494)上方约 7cm
		"verified": true,
	},
	"sword": {
		"path": "res://assets/fantasy_props/Sword_Bronze.gltf",
		# 节点=网格空间：长轴 Y，剑尖 +Y，柄尾 -0.208；握在护手与配重之间
		"handle": Vector3(0, -1, 0),
		"flare": Vector3(1, 0, 0),
		"grip": Vector3(0, -0.08, 0),
		"verified": true,
	},
	"knife": {
		"path": "res://assets/fantasy_props/Table_Knife.gltf",
		# 节点=网格空间：长轴 Z，刀刃 -Z，柄 +Z；刃口朝外需 flare=-X
		"handle": Vector3(0, 0, 1),
		"flare": Vector3(-1, 0, 0),
		"grip": Vector3(0, 0, 0.04),
		"verified": true,
	},
}

const PALM_POINT_NAME := "PalmPoint"

var _skel: Skeleton3D = null
var _attach: BoneAttachment3D = null
var _pivot: Node3D = null          # 掌心枢轴（挂在 _attach 下，支点=实测掌心）
var _owner_root: Node = null
var _axF := Vector3(0, 1, 0)        # 腕->指节（手骨局部）
var _axK := Vector3(-1, 0, 0)       # 食指MCP->小指MCP（手骨局部）
var _axB := Vector3(-1, 0, 0)       # 刃面目标方向（手骨局部；=「世界下方」投影到⊥柄平面）
var _palm_world := Vector3.ZERO     # 掌心世界坐标（bind 时由腕骨/MCP 世界位置实测）
var _hand_idx := -1                 # 右手骨 index（换算掌心局部用）
var _cur_id: String = ""
var _cur_node: Node3D = null
var _hidden_baked: Array = []

# ---------------------------------------------------------------- 生命周期
func bind(character_root: Node, bone_hint: String = RIGHT_HAND_BONE) -> bool:
	## 把挂点绑到角色的右手骨。返回 false = 该角色没有 Skeleton3D（胶囊体回退等）。
	clear()
	if character_root == null:
		return false
	_owner_root = character_root
	_skel = _find_skeleton(character_root)
	if _skel == null:
		return false
	var bidx: int = _pick_hand_bone(_skel, bone_hint)
	if bidx < 0:
		return false
	_attach = _ensure_attachment(_skel, bidx)
	if _attach == null:
		return false
	_measure_hand_anatomy(bidx)
	_ensure_palm_point()
	return true

func _ensure_palm_point() -> void:
	## 掌心枢轴：位置=实测掌心（世界坐标换算到骨局部），缩放=抵消整条父链累计缩放。
	## 武器挂在这里 => 旋转支点落在掌心，而不是腕（用户口径「挂在掌骨上」）。
	## ⚠️ 关键坑（Kachujin 实测踩过）：骨架 rest 空间是 cm 制（坐标动辄 -162），
	##   而节点局部是米；若把「手骨局部算出的 _palm」直接当节点局部坐标，
	##   父链 0.01 缩放又没正确抵消，PalmPoint 会被顶到肩膀（偏移 0.74m）。
	##   所以掌心一律用「世界坐标」给定，再乘骨世界变换的逆换算到骨局部，单位与缩放自动抵消。
	_pivot = null
	for c in _attach.get_children():
		if c is Node3D and c.name == PALM_POINT_NAME:
			_pivot = c as Node3D
			break
	if _pivot == null:
		_pivot = Node3D.new()
		_pivot.name = PALM_POINT_NAME
		_attach.add_child(_pivot)
	var k: float = 1.0 / _parent_chain_scale()
	var bone_w := _skel.global_transform * _skel.get_bone_global_rest(_hand_idx)
	var palm_local := bone_w.affine_inverse() * _palm_world
	_pivot.transform = Transform3D(Basis().scaled(Vector3.ONE * k), palm_local)

func _measure_hand_anatomy(hand_idx: int) -> void:
	## 用指节 MCP 骨实测解剖轴与掌心（rest 姿态）。
	## 方向(_axF/_axK/_axB)是单位向量，归一化后不受骨架 cm/米 尺度影响，正确；
	## 唯独「掌心位置」必须用世界坐标给出（见 _ensure_palm_point 注释），这里先算好。
	_hand_idx = hand_idx
	var hand_rest := _skel.get_bone_global_rest(hand_idx)
	var inv := hand_rest.affine_inverse()
	var pts: Array[Vector3] = []
	# 同时收集「世界坐标」用于掌心定位，与「手骨局部」用于方向，互不影响。
	var wrist_w := (_skel.global_transform * hand_rest).origin
	var mcp_w := Vector3.ZERO
	var mcp_n := 0
	for kb in KNUCKLE_BONES:
		var i := _fuzzy_bone(_skel, kb)
		if i >= 0:
			pts.append(inv * _skel.get_bone_global_rest(i).origin)
			mcp_w += (_skel.global_transform * _skel.get_bone_global_rest(i)).origin
			mcp_n += 1
	if mcp_n > 0:
		_palm_world = wrist_w.lerp(mcp_w / float(mcp_n), 0.5)   # 腕 与 指节平均 的中点 = 掌心(世界)
	if pts.size() < 2:
		_axF = FALLBACK_F
		_axK = FALLBACK_K
		if mcp_n == 0:
			_palm_world = wrist_w + (_skel.global_transform * hand_rest).basis * FALLBACK_PALM
		return
	var knuck := Vector3.ZERO
	for p in pts:
		knuck += p
	knuck /= float(pts.size())
	_axF = knuck.normalized()                       # 腕->指节
	if pts.size() >= 4:
		# 最外侧两枚 MCP 定指节线：按 x 升序后 [0]=小指侧、[-1]=食指侧，
		# K = 食指->小指（Idle 时 K·世界下 ≈ +0.9，刃面沿 K 即「斧刃朝下」）
		var sorted := pts.duplicate()
		sorted.sort_custom(func(a, b): return a.x < b.x)
		_axK = (sorted[0] - sorted[sorted.size() - 1]).normalized()
	_axK = (_axK - _axF * _axK.dot(_axF)).normalized()
	_sample_blade_dir(hand_idx)

func _sample_blade_dir(hand_idx: int) -> void:
	## 刃面目标 = 「世界下方」投影到 ⊥柄(F) 平面，在手骨局部空间实测。
	## 用户口径「斧刃朝下」：滚转角不再对准指节线（不同角色 idle 姿势的
	## 指节线朝向差异很大），直接对准世界下方，与姿势无关地满足需求。
	_axB = _axK                                     # 兜底：指节线
	var ap: AnimationPlayer = null
	if _owner_root is Node:
		ap = (_owner_root as Node).find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		return
	# 临时播 idle 取「世界下方」的手骨局部方向，量完恢复原状态
	var prev_anim := ap.current_animation
	# ⚠️ 角色刚 spawn 时 AnimationPlayer 可能还没有当前动画，
	#    此时读 current_animation_position 会报 "has no current animation"。
	var prev_pos: float = ap.current_animation_position if prev_anim != "" else 0.0
	var idle := ""
	for a in ap.get_animation_list():
		var al := a.to_lower()
		if al.contains("idle") and not al.contains("block"):
			idle = a
			break
	if idle == "":
		return
	# 整个 idle 循环取平均（手在 idle 里是摆动的，单帧取样会锁死在某个相位）
	ap.play(idle)
	var len_s: float = ap.get_animation(idle).length
	var acc := Vector3.ZERO
	var n := 0
	for i in 6:
		ap.advance(len_s / 6.0)
		var hb: Transform3D = _skel.global_transform * _skel.get_bone_global_pose(hand_idx)
		var dl: Vector3 = (hb.basis.inverse() * Vector3(0, -1, 0)).normalized()
		dl = dl - _axF * dl.dot(_axF)               # 投影到 ⊥柄 平面
		if dl.length() > 0.25:
			acc += dl.normalized()
			n += 1
	if n > 0:
		var avg := acc / float(n)
		avg = avg - _axF * avg.dot(_axF)
		if avg.length() > 0.25:
			_axB = avg.normalized()
	ap.stop()
	if prev_anim != "":
		ap.play(prev_anim)
		ap.seek(prev_pos, true)

func clear() -> void:
	unequip()
	_skel = null
	_attach = null
	_pivot = null
	_owner_root = null

func is_bound() -> bool:
	return _attach != null and is_instance_valid(_attach)

func current_id() -> String:
	return _cur_id

func current_node() -> Node3D:
	return _cur_node

# ---------------------------------------------------------------- 换武器
func equip(item_id: String) -> bool:
	## 手上看得见的换武器入口。item_id 为空或表里没有 -> 收起当前武器。
	if item_id == _cur_id:
		return true
	if not is_bound():
		return false
	if item_id == "" or not WEAPON_TABLE.has(item_id):
		unequip()
		return false
	var cfg: Dictionary = WEAPON_TABLE[item_id]
	var node := _load_weapon_node(str(cfg.get("path", "")))
	if node == null:
		unequip()
		return false

	unequip()
	# 挂在掌心枢轴下（不是直接挂在骨原点=腕上）
	if _pivot == null:
		_ensure_palm_point()
	_pivot.add_child(node)
	node.transform = _mount_transform(cfg)
	_hide_baked(node)
	_cur_id = item_id
	_cur_node = node
	return true

func unequip() -> void:
	if _cur_node != null and is_instance_valid(_cur_node):
		_cur_node.queue_free()
	_cur_node = null
	_cur_id = ""
	for n in _hidden_baked:
		if is_instance_valid(n):
			n.visible = true
	_hidden_baked.clear()

# ---------------------------------------------------------------- 核心：姿态
func _mount_transform(cfg: Dictionary) -> Transform3D:
	var h: Vector3 = cfg["handle"].normalized()   # 工作端 -> 柄尾（节点空间）
	var f: Vector3 = cfg["flare"].normalized()    # 刃口展开方向（节点空间）
	# 找出柄轴/刃轴各自的节点空间主轴
	var si := 0
	var fi := 0
	for i in 3:
		if abs(h[i]) > abs(h[si]):
			si = i
		if abs(f[i]) > abs(f[fi]):
			fi = i
	# 柄轴：工作端方向（-h）沿 F（从拳里向指尖伸出） => h 方向映到 -F
	var img_h: Vector3 = _axF * float(-signf(h[si]))
	# 刃轴：刃口展开沿 _axB（= 世界下方投影，用户口径「斧刃朝下」）
	var img_f: Vector3 = _axB * signf(f[fi])
	img_f = (img_f - img_h * img_f.dot(img_h)).normalized()
	var img_t: Vector3 = img_h.cross(img_f)       # t = h×f，右手系自动保持
	var img: Array = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	img[si] = img_h
	img[fi] = img_f
	var ti := 0
	for i in 3:
		if i != si and i != fi:
			ti = i
	img[ti] = img_t
	var b := Basis(img[0], img[1], img[2])
	# ⚠️ 缩放/掌心的补偿已由 PalmPoint 枢轴完成（它把父链累计缩放抵平、并把原点
	#    搬到实测掌心），这里只管「纯旋转 + 把资产自身的 grip 点挪到枢轴原点」。
	var grip: Vector3 = cfg["grip"]
	# ⚠️ 别写 `-b * grip`：GDScript 的单目负号会先作用在 Basis 上（Parse Error）。
	return Transform3D(b, -(b * grip))

# ---------------------------------------------------------------- 工具
func _parent_chain_scale() -> float:
	## 从挂点一路乘到场景根的累计缩放（等价于挂点的世界缩放）。
	var s := 1.0
	var p: Node3D = _attach
	while p != null:
		var sc: Vector3 = p.transform.basis.get_scale()
		s *= sc.x
		p = p.get_parent() as Node3D
	if abs(s) < 0.000001:
		return 1.0
	return abs(s)

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null

func _pick_hand_bone(sk: Skeleton3D, hint: String) -> int:
	## 掌骨 > 调用方提示 > 手骨。有真掌骨时优先用它（支点更贴握持处），
	## Mixamo 之类没有掌骨的会自然落到 hand 骨，再由 PalmPoint 补到掌心。
	var order: Array[String] = []
	order.append_array(PALM_BONE_CANDIDATES)
	if hint != "":
		order.append(hint)
	order.append_array(HAND_BONE_CANDIDATES)
	for cand in order:
		var i := _fuzzy_bone(sk, cand)
		if i >= 0:
			return i
	return -1

func _fuzzy_bone(sk: Skeleton3D, want: String) -> int:
	## Godot 会把 "mixamorig:RightHand" 规范成 "mixamorig_RightHand"，这里两边都认。
	var i := sk.find_bone(want)
	if i >= 0:
		return i
	var w := want.replace(":", "_").to_lower()
	for b in sk.get_bone_count():
		if sk.get_bone_name(b).replace(":", "_").to_lower() == w:
			return b
	return -1

func _ensure_attachment(sk: Skeleton3D, bidx: int) -> BoneAttachment3D:
	for c in sk.get_children():
		if c is BoneAttachment3D:
			var ba := c as BoneAttachment3D
			if ba.get_bone_idx() == bidx:
				return ba
	var ba2 := BoneAttachment3D.new()
	ba2.name = "WeaponPoint"
	ba2.bone_name = sk.get_bone_name(bidx)
	ba2.set_bone_idx(bidx)
	sk.add_child(ba2)
	return ba2

## GLTFDocument 兜底加载入口（仅当上层 load() 失败时调用，例如 user:// MOD 未预导入的磁盘 glb）。
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

func _load_weapon_node(path: String) -> Node3D:
	if path == "":
		return null
	# 优先走 Godot 资源管线（编辑器已生成 .import）；失败则运行时解析 GLTF
	var packed = load(path)
	if packed is PackedScene:
		var inst = packed.instantiate()
		return inst if inst is Node3D else null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := _gltf_load(doc, state, path)
	if err != OK:
		push_warning("[WeaponMount] 武器导入失败: %s err=%d" % [path, err])
		return null
	var root := doc.generate_scene(state)
	return root if root is Node3D else null

func _hide_baked(except: Node3D) -> void:
	## 角色 GLB 里本身就烘焙了武器（如 Kachujin_Axe / 烘焙剑）时，运行时挂上别的武器要藏掉它。
	## ⚠️ 烘焙武器在 Godot 导入后会变成「挂在右手骨上的 BoneAttachment3D」的子节点，
	##    它与运行时 _attach(WeaponPoint) 可能是同一个 BA，也可能是另一个独立的 BA。
	##    所以这里遍历「所有绑定到右手骨的 BA」，隐藏其中非运行时挂点/非刚挂上武器的可见子节点，
	##    无论上面两种结构都成立，都不会出现「烘焙剑 + 运行时剑」双持。
	if _skel == null:
		return
	for ba in _skel.get_children():
		if not (ba is BoneAttachment3D):
			continue
		if _hand_idx >= 0 and ba.get_bone_idx() != _hand_idx:
			continue
		for c in ba.get_children():
			if c == except or c == _pivot or not (c is Node3D):
				continue
			if c.visible:
				c.visible = false
				_hidden_baked.append(c)
