@tool
# =============================================================================
# IslandEcosystemGenerator.gd  (Godot 4.7 stable + Terrain3D v1.0.2)
# 三阶段程序化孤岛生态生成器 —— @tool 脚本
# -----------------------------------------------------------------------------
# 用法：
#   1) 在场景中放一个 Terrain3D 节点（双击 Hierarchy 里的 Terrain3D，或新建）。
#   2) 把本脚本挂到一个 Node3D 上，在检视面板把 terrain 指到上面的 Terrain3D 节点
#      （或给 Terrain3D 节点加 group "terrain"）。
#   3) 按"前置资源"要求配好 Terrain3D 的纹理槽与 Instancer 网格库。
#   4) 点检视面板里的按钮：① 生成地形 → ② 绘制纹理+热力图 → ③ 散布生态。
#      或一次点 "▶ 全流程生成"。
#
# ============================ 前置资源（必须） ===============================
# ① Terrain3D 纹理槽（资产管理面板，按顺序填 0~9，代码里用 TEX_* 常量引用）：
#      0 sand        沙滩        4 camp_dirt     营地泥地
#      1 forest      森林地表    5 cliff         瀑布崖壁
#      2 rock        岩石        6 lake_mud      湖底淤泥
#      3 water_bed   水底/河床    7 cave_floor    洞穴地面
#      8 ore_vein    矿脉贴图     9 berry        浆果灌丛
# ② Terrain3D Instancer 网格库（资产管理面板，配置 4 个 Terrain3DMeshAsset，
#    代码里用 mesh_tree_id / mesh_stone_id / mesh_ore_id / mesh_berry_id 引用）：
#      0 树   1 石头   2 矿脉(矿石簇)   3 浆果灌丛
# ③ 怪物巢穴 Marker 预制体 den_marker_scene（一个 Marker3D 或带图标的 Node3D），
#    生成器会在每个洞穴平台中心放一个，供怪物 AI 寻路锚点使用。
#
# ====================== 本脚本负责 / 需手动完成 的分界 ========================
# 【地形生成（本脚本 Phase 1）】大岛高度场：海滩、营地台地、内陆丘陵、瀑布崖壁、
#      湖盆、溪流、怪物洞穴深坑。地形孔洞(hole)若需要另用 set_control_hole 处理。
# 【纹理+资源热力图（本脚本 Phase 2）】自动按规则绘制 control 贴图（沙/林/岩/水底/
#      营地/崖/洞），并产出 iron / berry / tree_density / stone_density 四张热力图
#      （同时存为 PNG 到 heatmap_output_dir，供肉眼检查 / 调参）。
# 【Instancer 生态散布（本脚本 Phase 3）】按热力图+地形查询批量种树/石/矿脉/浆果，
#      并在每个洞穴平台中心放一个 den Marker3D。
# 【需手动完成】营地建筑（用 camp_center 坐标自行摆放）、水面 Shader/水面平面
#      （sea_level 高度）、怪物 AI 行为（读 den Marker）、以及所有数值的二次打磨。
#
# ====================== 与用户原始 API 假设的偏差（重要） ====================
# 用户原话要求：单次 begin/end_data_edit() 块、storage.validate()+instancer.validate()。
# 经对 Terrain3D v1.0.2 的 DLL 符号扫描 + 官方文档核对，这些名字在本版本【不存在】：
#   · begin_data_edit / end_data_edit            -> 0 处出现，已废弃/未实现
#   · force_update_maps / update_height_range     -> 0 处出现，本构建无此方法
#   · storage.validate() / instancer.validate()  -> 无此方法
# 本脚本采用的真实 API：
#   · 地形/纹理编辑后调用  data.update_maps(Terrain3DRegion.TYPE_*, all_regions=true)
#   · Instancer 批量写入用 instancer.add_transforms(id, transforms, PackedColorArray(), false)
#     全部加完再 instancer.update_mmis(-1, Vector2i.MAX, true) 一次性重建。
#   · 控制图(纹理)不手填打包 int，改用安全的粒度 setter：
#      set_control_base_id / set_control_overlay_id / set_control_blend 。
#   · Terrain3D 没有"任意浮点热力图通道"，资源热力图用独立 Image（另存 PNG）承载，
#     仅作为 Phase 3 的放置依据，不写回地形（这是设计取舍，已在头部说明）。
# =============================================================================

extends Node3D
class_name IslandEcosystemGenerator

# ----------------------------- 纹理槽位常量 --------------------------------
const TEX_SAND       : int = 0
const TEX_FOREST     : int = 1
const TEX_ROCK       : int = 2
const TEX_WATER_BED  : int = 3
const TEX_CAMP_DIRT  : int = 4
const TEX_CLIFF      : int = 5
const TEX_LAKE_MUD   : int = 6
const TEX_CAVE_FLOOR : int = 7
const TEX_ORE_VEIN   : int = 8
const TEX_BERRY      : int = 9

# ----------------------------- ① 地形参数 ----------------------------------
@export_group("Phase 1 - 地形 (Terrain)")
@export var terrain: Terrain3D
@export var island_length   : float = 1024.0   # 椭圆长轴(米)，1K 左右；可下调加速生成
@export var island_width    : float = 569.0    # 椭圆短轴(米)，≈长轴/1.8
@export var seed            : int   = 1337
@export var sea_level       : float = 0.0
@export var ocean_depth     : float = 12.0     # 岛外海水深度(负向)
@export var beach_height_max: float = 4.0      # 海滩最高 0~4m
@export var beach_band      : float = 0.10     # 归一化海岸带宽度(随曲率变化)
@export var camp_level      : float = 8.0      # 营地台地高度 5~10m
@export var hill_max_height : float = 60.0     # 丘陵上限 ≤60m
@export var hill_freq       : float = 0.004
@export var coast_freq      : float = 0.006    # 海岸 Worley/扰动噪声频率
@export var coast_perturb   : float = 0.10     # 海岸线扰动幅度(椭圆比 1.8:1 已体现在轴长)
@export var cliff_width     : float = 25.0     # 瀑布崖壁水平厚度(米)，>55° 陡坡
@export var lake_floor      : float = 1.5      # 湖底相对海平面的高度
@export var stream_width    : float = 3.0      # 溪流宽 3m
@export var stream_depth    : float = 0.8      # 溪流深 0.8m
@export var stream_warp     : float = 18.0     # 溪流 domain-warp 强度
@export var den_count       : int   = 3        # 怪物洞穴数 2~3
@export var den_radius      : float = 18.0     # 洞穴口径 15~20m
@export var den_depth       : float = 10.0     # 洞穴深坑 8~12m

# ----------------------------- ② 纹理/热力图参数 ---------------------------
@export_group("Phase 2 - 纹理与资源热力图 (Texture + Heatmap)")
@export var texture_sample_step : float = 1.0  # 纹理绘制采样步长(米)；必须≤control图分辨率，否则回读点落在未绘texel导致纹理缺失
@export var heatmap_resolution  : int   = 512
@export var heatmap_output_dir  : String = "res://island_heatmaps"

# ----------------------------- ③ Instancer 散布参数 ------------------------
@export_group("Phase 3 - Instancer 生态散布 (Scatter)")
@export var mesh_tree_id  : int = 0
@export var mesh_stone_id : int = 1
@export var mesh_ore_id   : int = 2
@export var mesh_berry_id : int = 3
@export var den_marker_scene: PackedScene
@export var scatter_step  : float = 2.5
@export var tree_rate     : float = 0.5
@export var stone_rate    : float = 0.4
@export var ore_rate      : float = 0.5
@export var berry_rate    : float = 0.6
@export var buffer_m          : float = 3.0    # 营地/洞穴/溪流 3m 缓冲带内不种树
@export var streambank_buffer : float = 4.0    # 河岸浆果/树缓冲
@export var tree_scale_min : float = 0.8
@export var tree_scale_max : float = 1.6
@export var stone_scale_min: float = 0.5
@export var stone_scale_max: float = 1.2
@export var ore_scale_min  : float = 0.6
@export var ore_scale_max  : float = 1.4
@export var berry_scale_min: float = 0.7
@export var berry_scale_max: float = 1.3

# ----------------------------- 运行期状态 ----------------------------------
var _noise := FastNoiseLite.new()
var _den_centers  : Array[Vector3] = []
var _camp_center  : Vector3 = Vector3.ZERO
var _lake_center  : Vector3 = Vector3.ZERO
var _lake_radius  : float   = 30.0
var _camp_radius  : float   = 22.0
var _hill_top     : Vector3 = Vector3.ZERO
var _stream_points: Array[Vector3] = []
var _heatmaps     : Dictionary = {}   # String -> Image (FORMAT_RF)
var _hm_origin    : Vector2 = Vector2.ZERO
var _hm_span      : Vector2 = Vector2.ZERO
var _hm_size      : int = 512
var _marker_nodes : Array[Node] = []

# ============================== 执行触发器 ==================================
# 在检视面板勾选对应开关即可运行该阶段（@tool 下于编辑器内触发，触发后自动复位）。
# 用开关代替 @export_tool_button 以兼容本项目 Godot 4.7 解析器。
@export_group("执行 (勾选即运行对应阶段，运行后自动复位)")
@export var run_generate_terrain: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_generate_terrain()
		run_generate_terrain = false
@export var run_paint_textures: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_paint_textures()
		run_paint_textures = false
@export var run_scatter: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_scatter_ecosystem()
		run_scatter = false
@export var run_all: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			generate_all()
		run_all = false

func generate_all() -> void:
	_generate_terrain()
	_paint_textures()
	_scatter_ecosystem()

# ============================== 通用辅助 ====================================
func _get_terrain() -> Terrain3D:
	if is_instance_valid(terrain):
		return terrain
	if get_tree() != null:
		var nodes := get_tree().get_nodes_in_group("terrain")
		if nodes.size() > 0:
			return nodes[0] as Terrain3D
	return null

func _get_data() -> Terrain3DData:
	var t := _get_terrain()
	if t == null:
		push_error("IslandEcosystemGenerator: 未设置 terrain（也没有 group 'terrain' 的 Terrain3D 节点）。")
		return null
	return t.data

func _get_instancer() -> Terrain3DInstancer:
	var t := _get_terrain()
	if t == null:
		push_error("IslandEcosystemGenerator: 未设置 terrain。")
		return null
	return t.instancer

func _get_vertex_spacing() -> float:
	var t := _get_terrain()
	if t != null and t.has_method("get_vertex_spacing"):
		return t.get_vertex_spacing()
	var d := _get_data()
	if d != null and d.has_method("get_vertex_spacing"):
		return d.get_vertex_spacing()
	return 1.0

func _get_region_size() -> int:
	var t := _get_terrain()
	if t != null and t.has_method("get_region_size"):
		return t.get_region_size()
	var d := _get_data()
	if d != null and d.has_method("get_region_size"):
		return d.get_region_size()
	return 512

func _fmax(a: float, b: float) -> float:
	if a > b:
		return a
	return b

func _fmin(a: float, b: float) -> float:
	if a < b:
		return a
	return b

func _norm_r(p: Vector3) -> float:
	var nx := p.x / (island_length * 0.5)
	var nz := p.z / (island_width  * 0.5)
	return sqrt(nx * nx + nz * nz)

func _coast_edge(p: Vector3) -> float:
	var n := _noise.get_noise_2d(p.x * coast_freq, p.z * coast_freq)
	return 1.0 + n * coast_perturb

func _dist_point_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var t: float = clamp((p - a).dot(ab) / _fmax(ab.length_squared(), 0.000001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _dist_to_stream(p: Vector3) -> float:
	if _stream_points.size() < 2:
		return INF
	var best := INF
	for i: int in _stream_points.size() - 1:
		var d := _dist_point_segment(p, _stream_points[i], _stream_points[i + 1])
		if d < best:
			best = d
	return best

func _is_beach(p: Vector3) -> bool:
	var r := _norm_r(p)
	var edge := _coast_edge(p)
	var inland := edge - r
	return inland >= 0.0 and inland < beach_band

# ============================== 特征布局 ====================================
func _layout_features() -> void:
	_den_centers.clear()
	_stream_points.clear()
	_noise.seed = seed

	# 营地台地：前部(正 z)居中
	_camp_center = Vector3(0.0, 0.0, island_width * 0.5 * 0.45)
	_camp_radius = clamp(island_width * 0.06, 15.0, 28.0)

	# 湖泊：后侧偏右
	_lake_center = Vector3(island_length * 0.18, 0.0, -island_width * 0.5 * 0.5)
	_lake_radius = clamp(_fmin(island_length, island_width) * 0.10, 25.0, 60.0)

	# 山顶：湖后方更靠后
	_hill_top = Vector3(-island_length * 0.05, 0.0, -island_width * 0.5 * 0.78)

	# 怪物洞穴：背坡(负 z 半区)分散 2~3 个
	var n := int(clamp(den_count, 2, 3))
	for i: int in n:
		var frac := 0.0 if n <= 1 else float(i) / float(n - 1)
		var ang := PI * (0.55 + 0.35 * frac)        # 背坡扇区
		var rx: float = cos(ang) * island_length * 0.30
		var rz_off: float = -abs(sin(ang)) * island_width * 0.42
		_den_centers.append(Vector3(rx, 0.0, rz_off))

	# 溪流折线：山顶 -> 湖心，带 domain warp
	var segs := 24
	for i: int in segs + 1:
		var t := float(i) / float(segs)
		var bx: float = lerp(_hill_top.x, _lake_center.x, t)
		var bz: float = lerp(_hill_top.z, _lake_center.z, t)
		var warp := _noise.get_noise_2d(bx * 0.02, bz * 0.02) * stream_warp
		_stream_points.append(Vector3(bx + warp, 0.0, bz))

# ============================== Phase 1：高度场 =============================
func _compute_height(p: Vector3) -> float:
	var r := _norm_r(p)
	var edge := _coast_edge(p)
	if r > edge:
		return sea_level - ocean_depth * smoothstep(edge, edge + 0.12, r)

	var inland := edge - r
	if inland < beach_band:
		var t: float = clamp(inland / beach_band, 0.0, 1.0)
		return sea_level + t * beach_height_max

	# 基础内陆：轻微抬升 + 后坡噪声丘陵
	var h := sea_level + beach_height_max
	var hill := (_noise.get_noise_2d(p.x * hill_freq, p.z * hill_freq) * 0.5 + 0.5)
	var rear: float = clamp(-p.z / (island_width * 0.5), 0.0, 1.0)
	h += hill * hill_max_height * rear

	# 营地台地（压平）
	var dc := p.distance_to(_camp_center)
	if dc < _camp_radius:
		var ct := smoothstep(_camp_radius, _camp_radius * 0.6, dc)
		h = lerp(h, sea_level + camp_level, ct)

	# 湖盆（下凹）
	var dl := p.distance_to(_lake_center)
	if dl < _lake_radius:
		var lt := smoothstep(_lake_radius, _lake_radius * 0.4, dl)
		h = lerp(h, sea_level + lake_floor, lt)

	# 瀑布崖壁：湖后方一条陡墙（z < lake.z），制造 >55° 落差
	if p.z < _lake_center.z:
		var back := _lake_center.z - p.z
		var lat: float = abs(p.x - _lake_center.x)
		if lat < _lake_radius * 1.2 and back > 0.0 and back < cliff_width:
			var cw := smoothstep(0.0, cliff_width, back)
			var cliff_top := sea_level + hill_max_height * 0.7
			var cliff_h: float = lerp(sea_level + lake_floor, cliff_top, cw)
			h = _fmax(h, cliff_h)

	# 溪流下切
	var ds := _dist_to_stream(p)
	if ds < stream_width * 0.5:
		var st := smoothstep(stream_width * 0.5, 0.0, ds)
		h = lerp(h, sea_level + lake_floor - stream_depth, st * 0.9)

	# 怪物洞穴深坑（平台底）
	for dpos: Vector3 in _den_centers:
		var dd := p.distance_to(dpos)
		if dd < den_radius:
			var pt := smoothstep(den_radius, den_radius * 0.35, dd)
			var den_h := sea_level + lake_floor - den_depth
			h = lerp(h, den_h, pt)

	return h

func _ensure_regions(data: Terrain3DData) -> void:
	var vs: float = _get_vertex_spacing()
	var rsize_verts: int = _get_region_size()
	var rsize_m: float = float(rsize_verts) * vs
	var pad: float = _fmax(island_length, island_width) * 0.5 + 50.0
	var min_x: float = -pad; var max_x: float = pad
	var min_z: float = -pad; var max_z: float = pad
	var rx0 := int(floor(min_x / rsize_m)); var rx1 := int(ceil(max_x / rsize_m))
	var rz0 := int(floor(min_z / rsize_m)); var rz1 := int(ceil(max_z / rsize_m))
	for rx: int in range(rx0, rx1 + 1):
		for rz: int in range(rz0, rz1 + 1):
			var cx := float(rx) * rsize_m
			var cz := float(rz) * rsize_m
			var wp := Vector3(cx, 0.0, cz)
			if not data.has_regionp(wp):
				data.add_region_blankp(wp, true)

func _generate_terrain() -> void:
	var t0 := Time.get_ticks_usec()
	var data := _get_data()
	if data == null:
		return

	_layout_features()
	_ensure_regions(data)
	# 关键：先给所有区域分配 control 贴图内存，否则 set_control_base_id 在
	# 未分配 control 图的区域上会静默失败（表现为只有原点附近区域能绘上纹理）。
	data.update_maps(Terrain3DRegion.TYPE_CONTROL, true)

	var vs: float = _get_vertex_spacing()
	var step: float = _fmax(vs, 1.0)   # 与地形顶点对齐，避免空洞
	var half_l := island_length * 0.5
	var half_w := island_width * 0.5
	var x := -half_l
	while x <= half_l:
		var z := -half_w
		while z <= half_w:
			data.set_height(Vector3(x, 0.0, z), _compute_height(Vector3(x, 0.0, z)))
			z += step
		x += step

	# 真实批量刷新：单次 update_maps（替代不存在的 begin/end_data_edit）
	data.update_maps(Terrain3DRegion.TYPE_HEIGHT, true)

	var sec := (Time.get_ticks_usec() - t0) / 1e6
	print("Phase 1 地形生成完成：%.2f s | 洞穴数=%d 湖半径=%.1f 营地(%s)" % [sec, _den_centers.size(), _lake_radius, str(_camp_center)])

# ============================== Phase 2：纹理 + 热力图 ======================
func _paint_point(data: Terrain3DData, pos: Vector3) -> void:
	var n := data.get_normal(pos)
	var slope_deg := rad_to_deg(acos(clamp(n.y, -1.0, 1.0)))

	var base: int = TEX_FOREST
	if _is_beach(pos):
		base = TEX_SAND
	if pos.distance_to(_camp_center) < _camp_radius:
		base = TEX_CAMP_DIRT
	if pos.distance_to(_lake_center) < _lake_radius:
		base = TEX_WATER_BED
	if _dist_to_stream(pos) < stream_width * 0.5:
		base = TEX_WATER_BED
	# 瀑布崖壁（陡坡且靠近湖后）
	if slope_deg > 55.0 * 0.7 and pos.distance_to(_lake_center) < _lake_radius * 2.0:
		base = TEX_CLIFF
	for dc: Vector3 in _den_centers:
		if pos.distance_to(dc) < den_radius * 0.5:
			base = TEX_CAVE_FLOOR

	data.set_control_base_id(pos, base)

	# 坡度 > 35° 叠加岩石(overlay=2)
	if slope_deg > 35.0:
		data.set_control_overlay_id(pos, TEX_ROCK)
		data.set_control_blend(pos, clamp((slope_deg - 35.0) / 30.0, 0.0, 1.0))

func _paint_textures() -> void:
	var t0 := Time.get_ticks_usec()
	var data := _get_data()
	if data == null:
		return
	if _den_centers.is_empty():
		push_warning("IslandEcosystemGenerator: 未检测到洞穴布局，请先跑 Phase 1。")

	var step: float = _fmax(texture_sample_step, 1.0)
	var half_l := island_length * 0.5
	var half_w := island_width * 0.5
	var x := -half_l
	while x <= half_l:
		var z := -half_w
		while z <= half_w:
			_paint_point(data, Vector3(x, 0.0, z))
			z += step
		x += step

	# 注意：不要调用 update_maps(TYPE_CONTROL) —— 本版它会按 autoshader 重算/清空手动绘制的
	# control 图，导致绘制丢失。控制图已在内存中写好，由 save_directory() 直接落盘即可。
	_build_heatmaps(data)

	var sec := (Time.get_ticks_usec() - t0) / 1e6
	print("Phase 2 纹理+热力图完成：%.2f s | 热力图已存至 %s" % [sec, heatmap_output_dir])

func _base_tex_id(data: Terrain3DData, pos: Vector3) -> int:
	# get_texture_id 返回 Vector3：x=基础纹理id, y=叠加id, z=混合。这里取基础id用于资源规则。
	var v: Vector3 = data.get_texture_id(pos)
	return int(v.x)

func _tree_density(data: Terrain3DData, pos: Vector3) -> float:
	var bt: int = _base_tex_id(data, pos)
	if bt == TEX_SAND or bt == TEX_WATER_BED or bt == TEX_CAMP_DIRT \
		or bt == TEX_LAKE_MUD or bt == TEX_CAVE_FLOOR:
		return 0.0
	if _in_buffer(pos):
		return 0.0
	if _dist_to_stream(pos) < stream_width * 0.5 + streambank_buffer:
		return 0.3
	if bt == TEX_FOREST:
		return 1.0
	return 0.0

func _stone_density(data: Terrain3DData, pos: Vector3) -> float:
	var bt: int = _base_tex_id(data, pos)
	if bt == TEX_ROCK:
		return 0.8
	if bt == TEX_FOREST:
		return 0.2
	return 0.0

func _iron_density(data: Terrain3DData, pos: Vector3) -> float:
	var bt: int = _base_tex_id(data, pos)
	if bt != TEX_ROCK:
		return 0.0
	var n := data.get_normal(pos)
	var slope := rad_to_deg(acos(clamp(n.y, -1.0, 1.0)))
	if slope < 20.0 or slope > 45.0:
		return 0.0
	var c := (_noise.get_noise_2d(pos.x * 0.05, pos.z * 0.05) * 0.5 + 0.5)
	return clamp(c, 0.0, 1.0)

func _berry_density(data: Terrain3DData, pos: Vector3) -> float:
	var bt: int = _base_tex_id(data, pos)
	if bt != TEX_FOREST:
		return 0.0
	var near_stream := _dist_to_stream(pos) < 8.0
	var near_den := false
	for dc: Vector3 in _den_centers:
		if pos.distance_to(dc) < 10.0 + den_radius:
			near_den = true
	if near_stream or near_den:
		return clamp(_noise.get_noise_2d(pos.x * 0.08, pos.z * 0.08) * 0.5 + 0.5, 0.0, 1.0)
	return 0.0

func _build_heatmaps(data: Terrain3DData) -> void:
	var size: int = heatmap_resolution
	var half_l := island_length * 0.5
	var half_w := island_width * 0.5
	_hm_origin = Vector2(-half_l, -half_w)
	_hm_span = Vector2(island_length, island_width)
	_hm_size = size

	var iron  := Image.create(size, size, 1, Image.FORMAT_RF)
	var berry := Image.create(size, size, 1, Image.FORMAT_RF)
	var tree  := Image.create(size, size, 1, Image.FORMAT_RF)
	var stone := Image.create(size, size, 1, Image.FORMAT_RF)

	for py: int in size:
		for px: int in size:
			var wx := _hm_origin.x + (float(px) / float(size - 1)) * _hm_span.x
			var wz := _hm_origin.y + (float(py) / float(size - 1)) * _hm_span.y
			var pos := Vector3(wx, 0.0, wz)
			var td := _tree_density(data, pos)
			var sd := _stone_density(data, pos)
			var iod := _iron_density(data, pos)
			var bd := _berry_density(data, pos)
			tree.set_pixel(px, py, Color(td, 0.0, 0.0))
			stone.set_pixel(px, py, Color(sd, 0.0, 0.0))
			iron.set_pixel(px, py, Color(iod, 0.0, 0.0))
			berry.set_pixel(px, py, Color(bd, 0.0, 0.0))

	# 落盘（best-effort，便于肉眼调参）
	var dir := DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive(heatmap_output_dir.replace("res://", ""))
	iron.save_png(heatmap_output_dir.path_join("heat_iron.png"))
	berry.save_png(heatmap_output_dir.path_join("heat_berry.png"))
	tree.save_png(heatmap_output_dir.path_join("heat_tree.png"))
	stone.save_png(heatmap_output_dir.path_join("heat_stone.png"))

	_heatmaps.clear()
	_heatmaps["iron"] = iron
	_heatmaps["berry"] = berry
	_heatmaps["tree"] = tree
	_heatmaps["stone"] = stone

func _sample_heatmap(name: String, wx: float, wz: float) -> float:
	if not _heatmaps.has(name):
		return 0.0
	var img: Image = _heatmaps[name]
	var u: float = clamp((wx - _hm_origin.x) / _hm_span.x, 0.0, 1.0)
	var v: float = clamp((wz - _hm_origin.y) / _hm_span.y, 0.0, 1.0)
	var px := int(u * float(_hm_size - 1))
	var py := int(v * float(_hm_size - 1))
	return img.get_pixel(px, py).r

# ============================== Phase 3：Instancer 散布 =====================
func _in_buffer(pos: Vector3) -> bool:
	if pos.distance_to(_camp_center) < _camp_radius + buffer_m:
		return true
	for dc: Vector3 in _den_centers:
		if pos.distance_to(dc) < den_radius + buffer_m:
			return true
	if _dist_to_stream(pos) < stream_width * 0.5 + buffer_m:
		return true
	return false

func _make_transform(pos: Vector3, h: float, smin: float, smax: float) -> Transform3D:
	var s := randf_range(smin, smax)
	var rot := randf_range(0.0, TAU)
	var b := Basis.from_euler(Vector3(0.0, rot, 0.0)) * Basis.from_scale(Vector3(s, s, s))
	return Transform3D(b, Vector3(pos.x, h, pos.z))

func _clear_den_markers() -> void:
	for m: Node in _marker_nodes:
		if is_instance_valid(m):
			m.queue_free()
	_marker_nodes.clear()

func _scatter_ecosystem() -> void:
	var t0 := Time.get_ticks_usec()
	var data := _get_data()
	var inst := _get_instancer()
	if data == null or inst == null:
		return
	# 安全地判断 Instancer 网格库是否为空（不同版本方法名不同）
	var mesh_count: int = 0
	if inst.has_method("get_meshes"):
		mesh_count = inst.get_meshes().size()
	elif inst.has_method("get_mesh_count"):
		mesh_count = inst.get_mesh_count()
	if mesh_count <= 0:
		push_warning("IslandEcosystemGenerator: Instancer 网格库为空（未配置 tree/stone/ore/berry 网格）。跳过散布，地图地形+纹理已就绪；请在 Terrain3D 资产管理面板配置网格库后重跑 Phase 3。")
		return
	if _heatmaps.is_empty():
		push_warning("IslandEcosystemGenerator: 未检测到热力图，请先跑 Phase 2。")

	# 清旧（真实批量清空接口）
	inst.clear_by_mesh(mesh_tree_id)
	inst.clear_by_mesh(mesh_stone_id)
	inst.clear_by_mesh(mesh_ore_id)
	inst.clear_by_mesh(mesh_berry_id)
	_clear_den_markers()

	var step: float = _fmax(scatter_step, 1.0)
	var half_l := island_length * 0.5
	var half_w := island_width * 0.5
	var tree_t: Array[Transform3D] = []
	var stone_t: Array[Transform3D] = []
	var ore_t: Array[Transform3D] = []
	var berry_t: Array[Transform3D] = []

	var x := -half_l
	while x <= half_l:
		var z := -half_w
		while z <= half_w:
			var pos := Vector3(x, 0.0, z)
			var h := data.get_height(pos)
			if h < sea_level + 0.5:
				z += step
				continue

			var td := _sample_heatmap("tree", x, z)
			if td > 0.0 and randf() < td * tree_rate and not _in_buffer(pos):
				tree_t.append(_make_transform(pos, h, tree_scale_min, tree_scale_max))

			var sd := _sample_heatmap("stone", x, z)
			if sd > 0.0 and randf() < sd * stone_rate:
				stone_t.append(_make_transform(pos, h, stone_scale_min, stone_scale_max))

			var iod := _sample_heatmap("iron", x, z)
			if iod > 0.0 and randf() < iod * ore_rate:
				var cnt := randi_range(3, 5)   # 每簇 3~5 个矿点
				for k: int in cnt:
					var off := Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
					var op := pos + off
					ore_t.append(_make_transform(op, data.get_height(op), ore_scale_min, ore_scale_max))

			var bd := _sample_heatmap("berry", x, z)
			if bd > 0.0 and randf() < bd * berry_rate:
				berry_t.append(_make_transform(pos, h, berry_scale_min, berry_scale_max))

			z += step
		x += step

	# 真实批量写入：update=false 攒批，最后一次性重建
	inst.add_transforms(mesh_tree_id, tree_t, PackedColorArray(), false)
	inst.add_transforms(mesh_stone_id, stone_t, PackedColorArray(), false)
	inst.add_transforms(mesh_ore_id, ore_t, PackedColorArray(), false)
	inst.add_transforms(mesh_berry_id, berry_t, PackedColorArray(), false)
	inst.update_mmis(-1)

	_place_den_markers()

	var sec := (Time.get_ticks_usec() - t0) / 1e6
	print("Phase 3 生态散布完成：%.2f s | 树=%d 石=%d 矿=%d 浆果=%d 巢穴Marker=%d"
		% [sec, tree_t.size(), stone_t.size(), ore_t.size(), berry_t.size(), _den_centers.size()])

func _place_den_markers() -> void:
	if den_marker_scene == null:
		push_warning("IslandEcosystemGenerator: 未指派 den_marker_scene，跳过巢穴 Marker（手动完成项）。")
		return
	for dc: Vector3 in _den_centers:
		var m: Node3D = den_marker_scene.instantiate()
		m.global_position = dc
		add_child(m)
		if m.owner == null and get_tree() != null and get_tree().edited_scene_root != null:
			m.owner = get_tree().edited_scene_root
		_marker_nodes.append(m)
