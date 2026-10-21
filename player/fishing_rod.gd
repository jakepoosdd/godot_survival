extends Node3D
class_name FishingRod
## 程序化纺车竿 + 渔轮（无需外部资源），对标 Tidewater 的 Spinning Rod & Reel：
##   - 竿身由多段组成，承重(tension)越大越弯（set_load）。
##   - 渔轮含 转子(rotor) + 摇臂(crank)，收线时持续旋转（set_reeling）。
##   - 导环(guides)沿竿分布。
##   - 抛投/咬钩/收线/脱钩 通过 play(action) 驱动 _pivot 姿态 + 渔轮动画。
## action ∈ "start" | "cast" | "bite" | "reel" | "escape" | "end"
##
## 该节点挂在相机(Camera3D)下做第一人称视图模型，所以强制第一人称钓鱼时始终可见。

const ROD_LEN := 1.7
const SEG_COUNT := 6
const GRIP_LEN := 0.42

var _pivot: Node3D
var _blank_root: Node3D
var _segs: Array[Node3D] = []
var _guides: Array[MeshInstance3D] = []
var _reel_housing: MeshInstance3D
var _rotor: Node3D
var _crank: Node3D
var _line: MeshInstance3D = null   # 视图模型内不再画线（鱼线改由 player.gd 画成世界空间线段）
var _tip: Node3D = null            # 竿尖节点（供 player.gd 取世界坐标连线）

var _tween: Tween = null
var _reeling: bool = false
var _load: float = 0.0
var _base_seg_x: Array[float] = []

func _ready() -> void:
	_build()
	# 默认持竿姿态：竿向前上方倾斜（相机本地 -Z 为前方）
	_pivot.rotation.x = -0.5

func _build() -> void:
	_pivot = Node3D.new()
	_pivot.name = "RodPivot"
	_pivot.position = Vector3(0.0, 0.0, 0.0)
	add_child(_pivot)

	# ---- 握把（深色） ----
	var handle := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.052
	hm.bottom_radius = 0.055
	hm.height = GRIP_LEN
	handle.mesh = hm
	handle.position = Vector3(0, GRIP_LEN * 0.5, 0)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.10, 0.10, 0.12)
	handle.material_override = hmat
	_pivot.add_child(handle)

	# ---- 竿身（多段，可弯曲） ----
	_blank_root = Node3D.new()
	_blank_root.name = "BlankRoot"
	_blank_root.position = Vector3(0, GRIP_LEN, 0)
	_pivot.add_child(_blank_root)

	var seg_len: float = (ROD_LEN - GRIP_LEN) / float(SEG_COUNT)
	var parent: Node3D = _blank_root
	for i in SEG_COUNT:
		var seg := Node3D.new()
		seg.name = "Seg%d" % i
		# 段底放在父节点顶端
		if i == 0:
			seg.position = Vector3(0, 0.0, 0.0)
		else:
			seg.position = Vector3(0, seg_len, 0.0)
		parent.add_child(seg)

		var shaft := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		# 上细下粗，越靠竿尖越细
		var t0: float = float(i) / float(SEG_COUNT)
		cm.bottom_radius = lerp(0.045, 0.012, t0)
		cm.top_radius = lerp(0.040, 0.009, t0)
		cm.height = seg_len
		cm.radial_segments = 8
		shaft.mesh = cm
		shaft.position = Vector3(0, seg_len * 0.5, 0)
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.55, 0.38, 0.20)
		sm.roughness = 0.55
		shaft.material_override = sm
		seg.add_child(shaft)

		_base_seg_x.append(0.0)
		_segs.append(seg)
		parent = seg

	# 竿尖节点（鱼线从此垂下）
	var tip := Node3D.new()
	tip.name = "Tip"
	tip.position = Vector3(0, seg_len, 0.0)
	parent.add_child(tip)
	_tip = tip
	_blank_root.set_meta("tip", tip)

	# ---- 导环（沿竿分布的小圆环） ----
	for i in (SEG_COUNT - 1):
		var g := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.018
		tm.outer_radius = 0.028
		g.mesh = tm
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color(0.85, 0.85, 0.9)
		gmat.metallic = 0.6
		g.material_override = gmat
		# 放在第 i 段顶端外侧
		var host: Node3D = _segs[i]
		g.position = Vector3(0.03, seg_len, 0.0)
		host.add_child(g)
		_guides.append(g)

	# ---- 渔轮（纺车型） ----
	_build_reel()

	# ---- 鱼线 + 浮标 ----
	# 注意：这里**不再**把浮标挂到竿尖垂下来。之前那样做，鱼线太细几乎看不见，
	# 玩家会看到"一颗红球粘在竿上"（用户反馈的"一个球是啥"）。
	# 现在浮标/鱼线改由 player.gd 抛到水面、画成世界空间线段（见 _cast_bobber_to / _update_cast_line）。

func _build_reel() -> void:
	var reel := Node3D.new()
	reel.name = "Reel"
	# 装在握把上方、竿身一侧（+X）
	reel.position = Vector3(0.07, GRIP_LEN + 0.04, 0.0)
	_pivot.add_child(reel)

	var housing := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.075
	hm.bottom_radius = 0.075
	hm.height = 0.07
	hm.radial_segments = 16
	housing.mesh = hm
	# 渔轮轴线沿 X（侧向），所以转 90°
	# CylinderMesh 默认沿 Y，转为沿 X：
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.18, 0.18, 0.22)
	hmat.metallic = 0.5
	housing.material_override = hmat
	reel.add_child(housing)
	_reel_housing = housing

	# 转子（旋转部件：一个十字臂 + 线杯）
	_rotor = Node3D.new()
	_rotor.name = "Rotor"
	_rotor.rotation.z = PI / 2.0   # 让转子绕 X 轴转（渔轮侧面朝向 +X）
	reel.add_child(_rotor)
	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.13, 0.02, 0.02)
	arm.mesh = am
	var amat := StandardMaterial3D.new()
	amat.albedo_color = Color(0.7, 0.7, 0.75)
	amat.metallic = 0.7
	arm.material_override = amat
	_rotor.add_child(arm)
	var arm2 := arm.duplicate()
	arm2.rotation.x = PI / 2.0
	_rotor.add_child(arm2)
	var cup := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.05
	cm.height = 0.04
	cm.radial_segments = 12
	cup.mesh = cm
	cup.rotation.z = PI / 2.0
	cup.position = Vector3(0.02, 0.0, 0.0)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.3, 0.3, 0.35)
	cmat.metallic = 0.6
	cup.material_override = cmat
	_rotor.add_child(cup)

	# 摇臂（曲柄 + 握把），独立于转子绕 X 旋转
	_crank = Node3D.new()
	_crank.name = "Crank"
	_crank.position = Vector3(0.09, 0.0, 0.0)
	reel.add_child(_crank)
	var arm3 := MeshInstance3D.new()
	var am3 := BoxMesh.new()
	am3.size = Vector3(0.02, 0.11, 0.02)
	arm3.mesh = am3
	var amat3 := StandardMaterial3D.new()
	amat3.albedo_color = Color(0.5, 0.5, 0.55)
	amat3.metallic = 0.7
	arm3.material_override = amat3
	arm3.position = Vector3(0.0, 0.055, 0.0)
	_crank.add_child(arm3)
	var knob := MeshInstance3D.new()
	var km := CylinderMesh.new()
	km.top_radius = 0.022
	km.bottom_radius = 0.022
	km.height = 0.05
	knob.mesh = km
	knob.rotation.z = PI / 2.0
	knob.position = Vector3(0.0, 0.11, 0.0)
	var kmat := StandardMaterial3D.new()
	kmat.albedo_color = Color(0.12, 0.12, 0.12)
	knob.material_override = kmat
	_crank.add_child(knob)

func _set_line_length(l: float) -> void:
	# 视图模型内已不画鱼线；保留此方法兼容 play() 里的调用（_line 为 null 时安全跳过）。
	if _line != null:
		_line.scale.y = l
		_line.position.y = -l * 0.5

## 竿尖世界坐标（player.gd 用它牵引世界空间鱼线）。
func tip_global() -> Vector3:
	if _tip != null and is_instance_valid(_tip):
		return _tip.global_position
	return global_position

# =========================================================
# 外部接口
# =========================================================
## 承重弯曲：t∈[0,1]，越大竿越弯（鱼拉力/张力）。
func set_load(t: float) -> void:
	_load = clampf(t, 0.0, 1.0)
	var n := float(_segs.size())
	for i in _segs.size():
		# 越靠竿尖弯曲贡献越大，形成弧线
		var w: float = (_load) * 0.42 * ((float(i) + 1.0) / n)
		_segs[i].rotation.x = -w   # 向 -Z（前方/水下）弯

## 收线时渔轮持续旋转。
func set_reeling(b: bool) -> void:
	_reeling = b

func play(action: String) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	match action:
		"start":
			_reeling = false
			_set_line_length(2.2)
			_tween_pose(0.0, -0.5, 0.35)
		"cast":
			_cast()
		"bite":
			_set_line_length(1.7)
			_tween_pose(0.0, -0.85, 0.2)
		"reel":
			_reeling = true
			_reel_in()
		"escape":
			_reeling = true
			_reel_in()
		"end":
			_reeling = false
			_set_line_length(2.2)
			set_load(0.0)
			_tween_pose(0.0, -0.5, 0.3)

func _tween_pose(z_target: float, x_target: float, dur: float) -> void:
	_tween = get_tree().create_tween()
	_tween.tween_property(_pivot, "rotation:z", z_target, dur)
	_tween.parallel().tween_property(_pivot, "rotation:x", x_target, dur)

func _cast() -> void:
	_tween = get_tree().create_tween()
	_tween.tween_property(_pivot, "rotation:z", -0.8, 0.22).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_pivot, "rotation:z", 0.6, 0.18).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_pivot, "rotation:z", 0.0, 0.35).set_ease(Tween.EASE_IN_OUT)
	_tween.parallel().tween_property(_pivot, "rotation:x", -0.5, 0.35)

func _reel_in() -> void:
	_tween = get_tree().create_tween()
	# 收线时浮标上提（线变短）
	_tween.tween_callback(func(): _set_line_length(0.7))

func _process(delta: float) -> void:
	if _reeling and _rotor != null and _crank != null:
		# 转子与摇臂持续旋转，模拟收线
		_rotor.rotation.x += delta * 9.0
		_crank.rotation.x += delta * 9.0
