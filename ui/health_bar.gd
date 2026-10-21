class_name HealthBar
extends Node3D
## 3D 浮动血条（始终朝向相机）。outline + bg + fill 三片竖直 QuadMesh，fill 按比例缩放并左对齐。
## 用法：var hb := HealthBar.new(); add_child(hb); hb.position.y = 头顶高度; hb.set_fraction(hp/max_hp)
##
## ⚠️ 两个必须避开的实现坑（曾导致「血条完全看不见 / 填充错位」）：
##  1) 不要用 PlaneMesh + BILLBOARD_ENABLED。
##     PlaneMesh 顶点在 XZ 平面（法线 +Y），而 billboard 会用相机基替换模型基，
##     于是这个平面变成「正对相机的侧面」→ 投影面积≈0 → 血条彻底看不见（会被误判成「太扁」）。
##     改用 QuadMesh（XY 平面、法线 +Z）。
##  2) 不要给「各自独立的子 MeshInstance3D」挂 billboard。
##     billboard 只替换模型的 3x3 基、保留其世界平移，于是 fill 的局部 X 偏移会变成「世界 X 偏移」——
##     相机绕到侧面时填充会镜像/错位。
##     改为「整条血条 Node3D 每帧只绕 Y 轴朝向相机」，子网格用普通竖直四边形，
##     子节点局部 +X 即屏幕左右，填充对齐天然正确。
## 另：no_depth_test 让血条永远画在角色前面，不被身体/地形遮挡。

const BAR_W := 1.15       # 横向长边（用户认可的「缩小一点」尺寸）
const BAR_H := 0.11       # 竖着短边（用户说「宽度」= 这条；由 0.22 减半）
const OUTLINE := 0.03      # 描边厚度（四边）；随短边同比减半，保持边框占比

var _fill: MeshInstance3D = null
var _fill_mat: StandardMaterial3D = null
var _frac := 1.0

func _ready() -> void:
	_build()
	_set_fraction(_frac)
	set_process(true)

## 每帧仅绕世界 Y 轴朝向当前相机（保持血条水平，避免俯视时被压扁）。
func _process(_delta: float) -> void:
	# 不可见（满血隐藏 / 脱战 / 屏外）时跳过每帧相机查询与变换写入，省一批 _process 开销。
	if not visible:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var cam: Camera3D = vp.get_camera_3d()
	if cam == null:
		return
	var to: Vector3 = cam.global_position - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	# 直接写 global_transform 的基（单位旋转）——顺带抵消父节点缩放，使所有血条尺寸一致。
	var gt := global_transform
	gt.basis = Basis(Vector3.UP, atan2(to.x, to.z))
	global_transform = gt

func _build() -> void:
	_add_quad("Outline", Vector2(BAR_W + OUTLINE * 2.0, BAR_H + OUTLINE * 2.0), Color(0.02, 0.02, 0.03, 0.95), 10)
	_add_quad("BG", Vector2(BAR_W, BAR_H), Color(0.10, 0.12, 0.15, 0.92), 11)
	_fill = _add_quad("Fill", Vector2(BAR_W, BAR_H), Color(0.2, 0.85, 0.3), 12)
	_fill_mat = _fill.material_override

## 竖直四边形（XY 平面、法线 +Z），不透明排序由 render_priority 决定。
func _add_quad(nm: String, size: Vector2, col: Color, prio: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.render_priority = prio
	mi.material_override = m
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	add_child(mi)
	return mi

## frac: 0..1。fill 左对齐缩放（绿→红）。
func set_fraction(f: float) -> void:
	_frac = clampf(f, 0.0, 1.0)
	_set_fraction(_frac)

func _set_fraction(f: float) -> void:
	if _fill == null:
		return
	_fill.scale.x = maxf(0.001, f)
	_fill.position.x = -BAR_W * (1.0 - f) * 0.5
	if _fill_mat != null:
		_fill_mat.albedo_color = Color.from_hsv(0.33 * f, 0.70, 0.92)

func set_bar_visible(v: bool) -> void:
	visible = v
