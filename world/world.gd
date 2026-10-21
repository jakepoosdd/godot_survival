extends Node3D
## 荒岛求生 · 大地图（剧情版 v1.0）
## 按剧情分区：营地(栅栏+破帐篷+篝火+女主) / 营地外不远处沙滩(钓鱼) /
##            周边资源森林(Stylized Nature MEGAKIT 吉卜力植被) / 岛心深处野怪巢穴(枯树+暗石+祭坛)。
## 资产：Slavica 包(地形/栅栏/沙/水/天空) + Stylized Nature MEGAKIT(树石花草) + Fantasy Props(家具/工具)。
## 外部依赖接口（勿改签名）：terrain_height / get_ground_height / get_spawn_position。

# 当前世界：本项目「剧情岛」，已在 2026-10-10 由扩岛工作放大到 1km×1km（WORLD_SIZE=1000, ISLAND_R=347.8），
# 并非原版 460m。营地/女主/巢穴等剧情设施在此路径下。（吉卜力备用大地图分支已移除，仅保留此主线地图。）

const Sky3DScript := preload("res://addons/sky_3d/src/Sky3D.gd")
const WaterTex := preload("res://world/water_textures.gd")   # Tidewater 海面贴图的 CPU 烘焙器
var sky3d: Sky3D
const USE_SKY3D := false   # 关：Sky3D 在 Godot 4.7 下不提供光照/天空，整图会变灰黑；改用 _add_fallback_lighting 的蓝天+太阳。改 true 可重开。

# ---- 世界规模 ----
const WORLD_SIZE := 1000.0                      # 2026-10-10 扩岛：460 -> 1000m（高度图同步重生成 1024²）
const TERRAIN_SPAN := 1000.0                    # 地形网格边长（与 WORLD_SIZE 保持一致）
const WATER_SPAN := 12000.0                     # （仅留作参考）旧全铺海面跨度；现为盘+环方案，环外缘 2600m 靠雾融入地平线
const SUB := 400                                # 1000m / 400 = 2.5m 每格（约 32 万三角面）
const SEA_LEVEL := 0.0
const LAKE_DEPTH := 16.0

# ---- 剧情关键坐标（世界 XZ）----
const CAMP_CENTER := Vector2(340.4, 72.4)       # 营地：12° 方位临海平台，离水线 58m，地形 5.08m，R22 起伏仅 2.6m
const CAMP_HALF := 12.5                         # 栅栏正方形半幅（25x25m）
const ISLAND_R := 347.8                        # 岛屿半径（陆地边缘）原 160 ×2.174
const BEACH_R := 287.0                         # 沙滩内缘 原 132 ×2.174
const NEST_CENTER := Vector2(-152.2, -195.7)   # 岛心深处 · 野怪巢穴（原 (-70,-90) ×2.174）
const MOUNTAIN_R := 130.4                       # 原 60 ×2.174
const MOUNTAIN_H := 74.0

# 女主开放空地 + 钓点（均位于临海开阔沙滩：半径 >122 已避开林地，且离营地栅栏 >30）
const HEROINE_OPEN := CAMP_CENTER                # 女主移到栅栏正中（营地中心）
const FISHING_OPEN := Vector2(384.2, 124.8)     # 钓点：同侧沙滩水线内侧（地形 +0.91m，浪花在脚边）；栈桥末端入水，深钓位水深 5.1m

# ---- TRELLIS2 生成的环境道具 GLB（缺失时各 _add_* 自动回退程序化图元）----
const GLB_TENT := "res://assets/props/tent.glb"       # 帐篷（穹顶）
const GLB_BONFIRE := "res://assets/props/bonfire.glb" # 营地篝火（柴堆+火）
const GLB_DOCK := "res://assets/props/dock.glb"       # 钓点木栈台
const GLB_ROD := "res://assets/props/fishing_rod.glb" # 鱼竿（靠栈台摆放）

var _noise: FastNoiseLite
var _noise2: FastNoiseLite
var _rng := RandomNumberGenerator.new()
var _prefab_cache: Dictionary = {}

# ---- 吉卜力自然（Stylized Nature MEGAKIT）----
const P_TREES := [
	"res://assets/megakit/CommonTree_1.gltf",
	"res://assets/megakit/CommonTree_2.gltf",
	"res://assets/megakit/CommonTree_3.gltf",
	"res://assets/megakit/CommonTree_4.gltf",
	"res://assets/megakit/CommonTree_5.gltf",
	"res://assets/megakit/Pine_1.gltf",
	"res://assets/megakit/Pine_2.gltf",
	"res://assets/megakit/TwistedTree_1.gltf",
	"res://assets/megakit/TwistedTree_2.gltf",
]
const P_DEAD := [
	"res://assets/megakit/DeadTree_1.gltf",
	"res://assets/megakit/DeadTree_2.gltf",
	"res://assets/megakit/DeadTree_3.gltf",
	"res://assets/megakit/DeadTree_4.gltf",
	"res://assets/megakit/DeadTree_5.gltf",
	"res://assets/megakit/TwistedTree_3.gltf",
	"res://assets/megakit/TwistedTree_4.gltf",
	"res://assets/megakit/TwistedTree_5.gltf",
]
const P_BUSHES := [
	"res://assets/megakit/Bush_Common.gltf",
	"res://assets/megakit/Bush_Common_Flowers.gltf",
	"res://assets/megakit/Plant_1.gltf",
	"res://assets/megakit/Plant_1_Big.gltf",
	"res://assets/megakit/Plant_7.gltf",
	"res://assets/megakit/Fern_1.gltf",
]
const P_GRASS := [
	"res://assets/megakit/Grass_Common_Short.gltf",
	"res://assets/megakit/Grass_Common_Tall.gltf",
	"res://assets/megakit/Grass_Wispy_Short.gltf",
	"res://assets/megakit/Grass_Wispy_Tall.gltf",
]
const P_FLOWERS := [
	"res://assets/megakit/Flower_3_Group.gltf",
	"res://assets/megakit/Flower_4_Group.gltf",
	"res://assets/megakit/Petal_1.gltf",
	"res://assets/megakit/Petal_2.gltf",
	"res://assets/megakit/Clover_1.gltf",
	"res://assets/megakit/Mushroom_Common.gltf",
]
const P_ROCKS := [
	"res://assets/megakit/Rock_Medium_1.gltf",
	"res://assets/megakit/Rock_Medium_2.gltf",
	"res://assets/megakit/Rock_Medium_3.gltf",
	"res://assets/megakit/Pebble_Round_1.gltf",
	"res://assets/megakit/Pebble_Round_2.gltf",
	"res://assets/megakit/Pebble_Square_1.gltf",
]
# ---- 建筑（Slavica）----
const P_FENCE := [
	"res://Prefabs/Fence/Plank2/EA03_Fence_Plank_02a_PRE.prefab.scn",
	"res://Prefabs/Fence/Plank2/EA03_Fence_Plank_02b_PRE.prefab.scn",
	"res://Prefabs/Fence/Wall/EA03_Fence_Wall_01b_PRE.prefab.scn",
]
const P_GATE := "res://Prefabs/Fence/RockGate/EA03_Fence_RockGate_01a_PRE.prefab.scn"  # 大门（石材拱门，素材包自带材质）
const P_SAND := [
	"res://Prefabs/Environment/Sand/EA03_Env_Sand_Flat_01a_PRE.prefab.scn",
	"res://Prefabs/Environment/Sand/EA03_Env_Sand_Flat_01b_PRE.prefab.scn",
	"res://Prefabs/Environment/Sand/EA03_Environment_Sand_01b_PRE.prefab.scn",
]
# ---- 家具/道具（Fantasy Props MEGAKIT）：床/柜子/锅/工作台/桶/箱/椅/桌 ----
const P_FURNITURE := [
	"res://assets/fantasy_props/Bed_Twin1.gltf",
	"res://assets/fantasy_props/Bookcase_2.gltf",
	"res://assets/fantasy_props/Cauldron.gltf",
	"res://assets/fantasy_props/Workbench.gltf",
	"res://assets/fantasy_props/Barrel.gltf",
	"res://assets/fantasy_props/Chest_Wood.gltf",
	"res://assets/fantasy_props/Chair_1.gltf",
	"res://assets/fantasy_props/Table_Large.gltf",
]
const HEROINE := "res://assets/girl.tscn"

var _built := false

func _ready() -> void:
	ensure_built()

## 同步构建世界（供 main.gd 在取出生点/地面高度前显式调用，避免依赖 deferred _ready 与 await 时序）。
## Godot 4 中 add_child 后子节点 _ready 延迟到本帧末尾才执行，且 `await node.ready` 在 --scene 直接运行模式下不会恢复，
## 会导致 main.gd 卡在 await、玩家/相机/菜单永不创建（表现为「灰黑空屏」）。改为显式同步构建，彻底消除时序依赖。
func ensure_built() -> void:
	if _built:
		return
	_built = true
	_build_legacy_world()

## 主线剧情岛（巢穴/女主/营地家具等）。
func _build_legacy_world() -> void:
	_rng.seed = 20261006
	GameManager.camp_center = CAMP_CENTER
	_add_sky()
	_build_terrain()
	_scatter_rocks()
	_scatter_forest()
	_build_camp()
	_build_beach()
	_build_nest()
	_spawn_resource_nodes()
	_spawn_sign()
	_spawn_heroine()
	_spawn_bulletin_board()
	_mm_flush()

# =========================================================
# 天空 / 大气（Sky3D 接管昼夜 + 吉卜力暖雾）
# =========================================================
# 昼夜动态光照引用（随 DayNightCycle 调整环境；USE_SKY3D=false 时这是唯一世界环境）
var _fb_sun: DirectionalLight3D = null
var _fb_env: Environment = null
var _fb_psm: ProceduralSkyMaterial = null

func _add_sky() -> void:
	if not USE_SKY3D:
		_add_fallback_lighting()
		return
	sky3d = Sky3DScript.new()
	sky3d.name = "Sky3D"
	add_child(sky3d)
	sky3d.current_time = 9.5
	sky3d.minutes_per_day = 24.0
	sky3d.sun_energy = 1.25
	sky3d.cloud_intensity = 0.45
	sky3d.wind_speed = 1.8
	sky3d.wind_direction = deg_to_rad(35.0)
	sky3d.fog_enabled = false                      # 关掉插件自带 SS 雾，改用环境雾
	if sky3d.environment == null:
		sky3d.environment = Environment.new()
	sky3d.environment.fog_enabled = true
	sky3d.environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	sky3d.environment.fog_density = 0.0065
	sky3d.environment.fog_light_color = Color(0.80, 0.86, 0.80)
	sky3d.environment.fog_sky_affect = 0.5
	sky3d.environment.ambient_light_color = Color(0.92, 0.95, 0.86)
	sky3d.environment.ambient_light_energy = 0.45
	sky3d.environment.tonemap_exposure = 1.05
	sky3d.add_to_group("sky3d")
	_add_fallback_lighting()

# =========================================================
# 保底光照与环境（不依赖 Sky3D 是否工作）
# 某些 Godot 版本下 Sky3D 可能不提供全局光照，导致所有 PBR/Shader
# 材质在无光时渲染为黑色（现象："一片灰黑"）。这里加一盏方向光(太阳)
# + 一个低优先级基础环境(蓝天背景 + 环境光)，保证世界始终可见有颜色。
# 现在 Sky3D 默认关闭(USE_SKY3D=false)，本环境即为唯一世界环境，保证蓝天+太阳始终生效。
func _add_fallback_lighting() -> void:
	# ⚠️ 排障开关：怀疑哪个新特性导致花屏就先关哪个（逐项二分定位）。
	const EN_SKY := true          # 程序化天空
	const EN_FOG := true          # 指数雾（大气透视：Tidewater 画质的关键一项）
	const EN_VFOG := false        # 体积雾（Forward+ 大平面掠射可疑）
	const EN_GLOW := true         # Bloom 辉光（太阳盘 + 海面闪光的柔和泛光）
	const EN_SSAO := true         # SSAO（树石/营地接地，对标 tidewater GTAO）
	const EN_ACES := true         # ACES 色调映射
	const EN_ADJ := true          # 调色

	# 太阳：暖色平行光 + 软阴影（4 分裂级联远近距离都柔和）
	var sun := DirectionalLight3D.new()
	sun.name = "SunFallback"
	_fb_sun = sun
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.02
	sun.shadow_enabled = true
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.04
	sun.shadow_blur = 1.6
	# 4 split → 2 split：远/中/近重分级联在 280m 内收益递减，却让每个 cascade 都
	# 重渲一遍场景几何。实测再省 74 万 prims，近处阴影质量几乎无感。
	# 阴影距离 280 → 160m：阴影贴图只覆盖相机 160m 内，更远的物体不再进阴影 pass，
	# 每帧阴影级联重渲的几何量进一步下降（代价是 160m 外无投影，海面/远山无感）。
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 160.0
	sun.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	if EN_VFOG:
		sun.light_volumetric_fog_energy = 0.25
	add_child(sun)

	var env := Environment.new()
	_fb_env = env
	if EN_SKY:
		# 程序化天空（对标 tidewater 明亮热带天空：蓝顶 + 暖白地平线 + 明亮太阳盘）
		var sky := Sky.new()
		var psm := ProceduralSkyMaterial.new()
		_fb_psm = psm
		psm.sky_top_color = Color(0.24, 0.47, 0.82)
		psm.sky_horizon_color = Color(0.52, 0.68, 0.86)
		# 地面色改成海雾色：海域收缩后天空「地面区」会在水环边缘外露一条，
		# 把它的地平线色调成与雾/海面一致，接缝就看不见了
		psm.ground_horizon_color = Color(0.72, 0.81, 0.89)
		psm.ground_bottom_color = Color(0.30, 0.48, 0.62)
		# 太阳光晕半径：18° 会渲染成一颗巨大的白斑（用户反馈的「一大块」之一），压到 6°
		psm.sun_angle_max = 6.0
		psm.sun_curve = 0.35
		sky.sky_material = psm
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.32, 0.52, 0.78)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_sky_contribution = 0.6
	env.ambient_light_color = Color(0.72, 0.78, 0.86)
	env.ambient_light_energy = 0.30
	if EN_FOG:
		# 海上大气透视（指数雾，冷蓝，远景地形/海面融入天空）—— Tidewater 雾山远景的核心
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		# 0.0011 是按 460m 小岛调的；岛放大到 1km 后 1km 处雾量会从 40% 涨到 67%，整岛发灰。
		# 改 0.0008：1km ≈ 55%（保留大气透视层次），2600m 海环边缘 ≈ 87% 仍能融进地平线。
		env.fog_density = 0.0008
		env.fog_light_color = Color(0.68, 0.78, 0.86)
		env.fog_sky_affect = 0.12
		env.fog_height = 60.0
		env.fog_height_density = 0.003    # 低海拔雾更浓 → 远山下部朦胧、峰顶清晰（航拍雾山层次）
	if EN_VFOG:
		# 体积雾（轻薄海雾，Godot 4 原生，对标 tidewater aerial perspective）
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.0008
		env.volumetric_fog_albedo = Color(0.58, 0.65, 0.73)
		env.volumetric_fog_length = 130.0
		env.volumetric_fog_ambient_inject = 0.2
	if EN_ACES:
		# 色调映射（tidewater 用 ACES 电影曲线）
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 0.56
	if EN_GLOW:
		# 辉光 / Bloom（太阳盘 + 海面闪光的柔和泛光）
		env.glow_enabled = true
		env.glow_intensity = 0.12
		env.glow_strength = 0.5
		env.glow_bloom = 0.08
		env.glow_hdr_threshold = 1.15
	if EN_ADJ:
		# 调色（对标 tidewater grading：轻微提饱和/对比）
		env.adjustment_enabled = true
		env.adjustment_saturation = 0.95
		env.adjustment_contrast = 1.12
		env.adjustment_brightness = 1.0
	if EN_SSAO:
		# SSAO（树石/营地接地，对标 tidewater GTAO）
		env.ssao_enabled = true
		env.ssao_intensity = 1.2
		env.ssao_radius = 2.0
		env.ssao_power = 1.5
		# 关键：默认 ssao_light_affect=0.0 → SSAO 只压环境光，直射阳光下 AO 几乎不可见。
		# 提到 0.4 让树石/营地接地的接触阴影在阳光下也显形（scenario-godot-rendering 实测坑）。
		env.ssao_light_affect = 0.4
	var we := WorldEnvironment.new()
	we.name = "EnvFallback"
	we.environment = env
	add_child(we)
	# 昼夜动态光照：初次按当前游戏时间设定，并订阅时间变化事件
	_update_daynight(DayNightCycle.hour / 24.0)
	if not EventBus.time_of_day_changed.is_connected(_on_time_changed):
		EventBus.time_of_day_changed.connect(_on_time_changed)

# 随归一化时间 t01(0=午夜, 0.5=正午) 动态调节环境亮度：夜晚明显变暗、天空转深蓝。
func _update_daynight(t01: float) -> void:
	if _fb_env == null:
		return
	var day := 0.5 - 0.5 * cos(t01 * 2.0 * PI)   # 0=午夜最黑, 1=正午最亮
	if _fb_sun != null:
		_fb_sun.light_energy = lerp(0.06, 1.02, day)
		_fb_sun.light_color = Color(0.55, 0.62, 0.85).lerp(Color(1.0, 0.95, 0.85), day)
	if _fb_psm != null:
		_fb_psm.sky_top_color = Color(0.02, 0.03, 0.08).lerp(Color(0.24, 0.47, 0.82), day)
		_fb_psm.sky_horizon_color = Color(0.06, 0.09, 0.18).lerp(Color(0.52, 0.68, 0.86), day)
		_fb_psm.ground_horizon_color = Color(0.03, 0.05, 0.10).lerp(Color(0.72, 0.81, 0.89), day)
		_fb_psm.ground_bottom_color = Color(0.02, 0.03, 0.06).lerp(Color(0.30, 0.48, 0.62), day)
	_fb_env.ambient_light_color = Color(0.12, 0.16, 0.30).lerp(Color(0.72, 0.78, 0.86), day)
	_fb_env.ambient_light_energy = lerp(0.14, 0.30, day)
	_fb_env.tonemap_exposure = lerp(0.30, 0.56, day)
	if _fb_env.fog_enabled:
		_fb_env.fog_light_color = Color(0.20, 0.26, 0.40).lerp(Color(0.68, 0.78, 0.86), day)

func _on_time_changed(t01: float) -> void:
	_update_daynight(t01)

# =========================================================
# 地形高度场（真实海岛形态：高度图驱动）
# 参考真实海岛地理——中心雪山主峰 + 放射状海岸/海湾 + 环岛深海 + 多倍频细节。
# 高度图由 tools/gen_island_tidewater.py 生成（移植自 tidewater 山脊骨架算法, 512² R8）。
# 旧版 tools/gen_island_height.py 为早期"平滑海岛"版本, 已弃用。
# 世界高度区间 = [HM_HMIN, HM_HMIN+HM_HAMP] = [-16, 80] 米。
# =========================================================
const HM_SIZE := 1024                           # 1000m / 1024 ≈ 1m 每采样（tools/gen_island_height.py 重生成）
const HM_WORLD := 1000.0
const HM_HMIN := -16.0
const HM_HAMP := 96.0
var _height_img: Image

func _get_height_image() -> Image:
	if _height_img == null:
		# ⚠️ 优先加载原生 .res 高度图：Godot 导出器会跳过 `.bin` 扩展名（即使 export_filter="all"，
		# 该文件也进不了 PCK），而 .res 是原生资源、必定随包发布。转换脚本见 tools/make_height_res.gd。
		var img: Image = load("res://assets/terrain/island_height_img.res") as Image
		if img == null:
			# 编辑器兜底：直接读原始 .bin（仅 res:// 磁盘映射下有效，导出包内不可用）
			var f: FileAccess = FileAccess.open("res://assets/terrain/island_height.bin", FileAccess.READ)
			if f == null:
				push_error("WORLD: 无法打开高度图（res://assets/terrain/island_height_img.res 缺失，且 .bin 回退失败）")
				return null
			var buf: PackedByteArray = f.get_buffer(HM_SIZE * HM_SIZE)
			f.close()
			img = Image.create_from_data(HM_SIZE, HM_SIZE, false, Image.FORMAT_R8, buf)
		_height_img = img
	return _height_img

## 双线性采样高度图, 返回世界高度(米)。边缘 clamp 到海洋边界值。
func _sample_heightmap(wx: float, wz: float) -> float:
	var img: Image = _get_height_image()
	if img == null:
		return 0.0
	var u: float = (wx / HM_WORLD + 0.5) * float(HM_SIZE - 1)
	var v: float = (wz / HM_WORLD + 0.5) * float(HM_SIZE - 1)
	u = clamp(u, 0.0, float(HM_SIZE - 1))
	v = clamp(v, 0.0, float(HM_SIZE - 1))
	var x0: int = int(floor(u))
	var y0: int = int(floor(v))
	var x1: int = mini(x0 + 1, HM_SIZE - 1)
	var y1: int = mini(y0 + 1, HM_SIZE - 1)
	var fx: float = u - float(x0)
	var fy: float = v - float(y0)
	var h00: float = img.get_pixel(x0, y0).r
	var h10: float = img.get_pixel(x1, y0).r
	var h01: float = img.get_pixel(x0, y1).r
	var h11: float = img.get_pixel(x1, y1).r
	var h0: float = lerp(h00, h10, fx)
	var h1: float = lerp(h01, h11, fx)
	var hn: float = lerp(h0, h1, fy)
	return HM_HMIN + hn * HM_HAMP

func terrain_height(wx: float, wz: float) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_noise.frequency = 0.012
		_noise.fractal_octaves = 3
		_noise2 = FastNoiseLite.new()
		_noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_noise2.frequency = 0.03
		_noise2.fractal_octaves = 2

	var h := _sample_heightmap(wx, wz)
	# 叠加轻量细节噪声, 消解高度图分辨率带来的阶梯感
	h += _noise.get_noise_2d(wx, wz) * 1.4
	h += _noise2.get_noise_2d(wx, wz) * 0.5

	var cd := Vector2(wx, wz).distance_to(CAMP_CENTER)
	if cd < 46.0:                                     # 营地空地压平
		var ct: float = clamp(1.0 - cd / 46.0, 0.0, 1.0)
		h = lerp(h, 2.2, ct * 0.85)

	return h

func get_spawn_position() -> Vector3:
	# 玩家在栅栏南门内侧苏醒（女主居中，避免重叠）
	var y := terrain_height(CAMP_CENTER.x, CAMP_CENTER.y + CAMP_HALF - 1.5)
	return Vector3(CAMP_CENTER.x, y + 0.2, CAMP_CENTER.y + CAMP_HALF - 1.5)

func get_ground_height(x: float, z: float) -> float:
	return terrain_height(x, z)

## 地表法线（有限差分），用于把角色/物体对齐到坡面，避免斜插进山坡。
func _terrain_normal(x: float, z: float) -> Vector3:
	var e := 0.6
	var hl := terrain_height(x - e, z)
	var hr := terrain_height(x + e, z)
	var hd := terrain_height(x, z - e)
	var hu := terrain_height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()

# =========================================================
# 构建
# =========================================================
func _build_terrain() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(WORLD_SIZE, WORLD_SIZE)
	pm.subdivide_width = SUB
	pm.subdivide_depth = SUB
	var arrays := pm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i]
		verts[i] = Vector3(v.x, terrain_height(v.x, v.z), v.z)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(am, 0)
	st.generate_normals()
	am = st.commit()

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = am
	mi.material_override = _make_terrain_material()
	# ⚠️ 性能实测：地形是单个 32 万三角的大网格，投影会让它在每个 shadow cascade
	#    里各渲染一遍（4 split = 128 万 prims，占总 prims 的 32%）。地形只「接收」
	#    阴影（树/岩的影子照样打在地面上），自阴影交给法线着色 + 雾 + SSAO，
	#    视觉差异很小但省下整整 1/3 的几何量。
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_add_terrain_collision(am)
	_add_water()

## 高度+坡度着色：沙 → 草 → 深草 → 岩 → 峰顶；坡度露岩、近岸湿沙带、
## 多尺度纹理细节噪声（对标 tidewater 的自然地形质感，告别平涂色块）。
func _make_terrain_material() -> Material:
	# 地形材质 = 程序化底色（高度/坡度/噪声，负责远观配色） × 三图层真实贴图细节。
	# ⚠️ 贴图只做「乘性细节」：先除以各自**线性空间均值**归一到 ~1.0 再混入，
	#    这样既有真实纹理结构，又不会把整体亮度推飞（增益 >1.25 会被太阳+ACES 顶成纯白）。
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform sampler2D flowers_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D dirt_tex    : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_tex    : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_nm    : repeat_enable, filter_linear_mipmap;
uniform float sea_level = 0.0;
uniform float u_tex_scale = 0.0625;   // 1/0.0625 = 16m 一格贴图
uniform float u_detail = 0.70;        // 贴图细节强度
uniform float u_nm_depth = 0.60;      // 法线强度
uniform float u_debug = 0.0;         // 0=正常 1=albedo 2=层权重 3=高度带 4=世界法线 5=坡度 6=贴图细节 7=正常但跳过法线
varying vec3 wpos;
varying vec3 wn;
varying float vdist;

float thash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float tnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(thash(i), thash(i + vec2(1.0, 0.0)), u.x),
	           mix(thash(i + vec2(0.0, 1.0)), thash(i + vec2(1.0, 1.0)), u.x), u.y);
}
// 三平面权重：平地≈单平面 XZ，峭壁自动切侧投影，避免贴图竖向拉伸
vec3 tri_blend(vec3 n) {
	vec3 b = pow(abs(n), vec3(4.0));
	return b / max(b.x + b.y + b.z, 0.0001);
}
vec3 tri_sample(sampler2D t, vec3 p, vec3 b, float s) {
	return texture(t, p.zy * s).rgb * b.x
	     + texture(t, p.xz * s).rgb * b.y
	     + texture(t, p.xy * s).rgb * b.z;
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vdist = length(wpos - CAMERA_POSITION_WORLD);
}
void fragment() {
	float h  = wpos.y;
	float hs = h - sea_level;
	vec3 n = normalize(wn);
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);   // 0=平地 1=峭壁

	if (hs < -0.4) {
		// ===== 水下：近岸浅水透底 =====
		float d = -hs;
		vec3 sh_sand = vec3(0.55, 0.60, 0.46);
		vec3 sh_mid  = vec3(0.05, 0.42, 0.52);
		vec3 sh_deep = vec3(0.01, 0.06, 0.20);
		ALBEDO = d < 2.5 ? mix(sh_sand, sh_mid, clamp(d / 2.5, 0.0, 1.0))
		                 : mix(sh_mid, sh_deep, clamp((d - 2.5) / 12.0, 0.0, 1.0));
		ROUGHNESS = 0.90;
	} else {
		// ===== 程序化底色（远观配色，已对标调过，别乱动） =====
		vec3 sand  = vec3(0.66, 0.545, 0.33);  // 提暖压亮：原 0.74/0.66/0.47 会在日光下被顶到 lum182/sat0.06 发白
		vec3 grass = vec3(0.30, 0.47, 0.20);
		vec3 dgrass= vec3(0.20, 0.34, 0.15);
		vec3 rock  = vec3(0.40, 0.34, 0.27);   // 暖褐岩（原纯灰是"环境发灰"主因）
		vec3 peak  = vec3(0.56, 0.51, 0.44);

		float macro = tnoise(wpos.xz * 0.020);
		float meso  = tnoise(wpos.xz * 0.075 + 13.7);
		float patch = clamp(macro * 0.65 + meso * 0.35, 0.0, 1.0);

		// 高度带（用噪声扰动，避免拉出等高线）
		float g_h = hs + (patch - 0.5) * 6.0;
		vec3 alt_col;
		if (g_h < 20.0)      alt_col = mix(grass, dgrass, clamp((g_h - 1.2) / 18.8, 0.0, 1.0));
		else if (g_h < 55.0) alt_col = mix(dgrass, rock,  clamp((g_h - 20.0) / 35.0, 0.0, 1.0));
		else                 alt_col = mix(rock, peak,   clamp((g_h - 55.0) / 25.0, 0.0, 1.0));

		// ===== 四层权重：沙 / 草 / 砾石土 / 岩 =====
		// 新高度图海岸是 130m 宽的缓坡（5.5m→-1m），阈值太窄沙滩就只剩一条线
		float beach_h = mix(3.0, 6.5, patch);
		float w_sand = 1.0 - smoothstep(0.3, beach_h, hs);
		float w_rock = clamp(max(smoothstep(0.30 + patch * 0.10, 0.62, slope),
		                         smoothstep(40.0, 64.0, hs) * 0.90), 0.0, 1.0);
		float w_dirt = clamp(smoothstep(0.10, 0.34, slope) * 0.85
		                   + smoothstep(0.45, 0.80, patch) * 0.40, 0.0, 1.0);
		w_dirt *= (1.0 - w_rock);
		w_sand *= (1.0 - w_rock);
		float w_grass = max(1.0 - w_sand - w_dirt - w_rock, 0.0);
		float tot = max(w_sand + w_dirt + w_rock + w_grass, 0.0001);
		w_sand /= tot; w_dirt /= tot; w_rock /= tot; w_grass /= tot;

		vec3 base = sand * w_sand
		          + alt_col * w_grass
		          + mix(dgrass * 1.35, rock * 0.95, 0.5) * w_dirt
		          + mix(rock, peak, smoothstep(45.0, 70.0, hs)) * w_rock;

		// ===== 贴图细节（乘性，先除各自线性均值归一到 ~1） =====
		vec3 b = tri_blend(n);
		float s1 = u_tex_scale;
		float far = smoothstep(40.0, 300.0, vdist);          // 远处偏大尺度，防摩尔纹
		float fade = 1.0 - smoothstep(90.0, 340.0, vdist);   // 远处细节淡出
		float amt = u_detail * mix(0.35, 1.0, fade);

		// 线性均值：flowers(0.177,0.223,0.050) dirt(0.142,0.091,0.037) rock(0.084,0.104,0.068)
		vec3 d_flow = mix(tri_sample(flowers_tex, wpos, b, s1),
		                  tri_sample(flowers_tex, wpos, b, s1 * 0.29), mix(0.30, 0.72, far))
		              / vec3(0.177, 0.223, 0.050);
		vec3 d_dirt = tri_sample(dirt_tex, wpos, b, s1 * 0.85) / vec3(0.142, 0.091, 0.037);
		vec3 d_rock = tri_sample(rock_tex, wpos, b, s1 * 0.55) / vec3(0.084, 0.104, 0.068);
		vec3 d_sand = texture(dirt_tex, wpos.xz * s1 * 2.6).rgb / vec3(0.142, 0.091, 0.037);

		vec3 det = d_flow * w_grass + d_dirt * w_dirt + d_rock * w_rock + d_sand * w_sand;
		// ⚠️ 增益必须夹住：>1.25 会被太阳 + ACES 顶成纯白（以前踩过）
		vec3 mod3 = clamp(mix(vec3(1.0), det, amt), vec3(0.72), vec3(1.24));
		vec3 col = base * mod3;

		// 大区块色相漂移（极小幅度，打破平涂）
		col *= mix(vec3(0.97, 0.99, 0.95), vec3(1.03, 1.01, 0.97), macro);

		// 近岸湿沙带：潮线附近压暗一圈
		float wet = (1.0 - smoothstep(sea_level + 0.15, sea_level + 0.9, h)) * step(sea_level - 0.2, h);
		col *= mix(1.0, 0.74, wet);

		// ===== 法线细节 =====
		// ⚠️ 大坑：地形网格没有切线属性，直接用 Godot 的 NORMAL_MAP 会拿到错误的切线基，
		//    实测整岛亮度被砍一半（139→76）且偏青。故自己构建切空间、世界空间扰动后写 NORMAL。
		//    切空间：贴图按 wpos.xz 平面映射 → T=世界+X 在切面的投影，B=世界+Z 的投影。
		vec3 nm_raw = texture(grass_nm, wpos.xz * s1 * 1.6).rgb;
		vec3 nt = nm_raw * 2.0 - 1.0;
		// u_debug==7：跳过法线扰动，用于 A/B 排查
		if (u_debug < 6.5 || u_debug > 7.5) {
			vec3 nw = normalize(wn);
			vec3 T = normalize(vec3(1.0, 0.0, 0.0) - nw * nw.x);
			vec3 B = normalize(vec3(0.0, 0.0, 1.0) - nw * nw.z);
			float nm_w = (1.0 - smoothstep(0.25, 0.55, slope)) * w_grass * fade;
			float d = u_nm_depth * nm_w;
			vec3 pnv = normalize(T * nt.x * d + B * nt.y * d + nw * max(nt.z, 0.20));
			NORMAL = (VIEW_MATRIX * vec4(pnv, 0.0)).xyz;
		}

		if ((u_debug > 0.5 && u_debug < 6.5) || u_debug > 7.5) {
			// 探针模式：ALBEDO 置黑，只看 EMISSION，排除光照干扰
			vec3 probe = col;
			if (u_debug > 1.5) probe = vec3(w_sand, w_dirt, w_rock);
			if (u_debug > 2.5) probe = alt_col;
			if (u_debug > 3.5) probe = normalize(wn) * 0.5 + 0.5;
			if (u_debug > 4.5) probe = vec3(slope);
			if (u_debug > 5.5) probe = det * 0.25;
			if (u_debug > 6.5) probe = nm_raw;                 // 8 = 法线贴图原始采样
			if (u_debug > 7.5) probe = nt * 0.5 + 0.5;         // 9 = 解码后的法线
			ALBEDO = vec3(0.0);
			EMISSION = probe;
			ROUGHNESS = 1.0;
		} else {
			ALBEDO = col;
			ROUGHNESS = mix(0.95, 0.74, clamp((hs - 25.0) / 35.0, 0.0, 1.0)) * (1.0 - w_rock * 0.10);
		}
	}
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("flowers_tex", load("res://Textures/Flower_Grass.png"))
	mat.set_shader_parameter("dirt_tex", load("res://Textures/Pobbles_Sand_Dirt.png"))
	mat.set_shader_parameter("rock_tex", load("res://assets/megakit/Rocks_Diffuse.png"))
	mat.set_shader_parameter("grass_nm", load("res://Textures/Flower_Grass_NM.png"))
	mat.set_shader_parameter("sea_level", SEA_LEVEL)
	mat.set_shader_parameter("u_tex_scale", 0.0625)
	mat.set_shader_parameter("u_detail", 0.70)
	mat.set_shader_parameter("u_nm_depth", 0.60)
	return mat

func _add_terrain_collision(mesh: Mesh) -> void:
	var sb := StaticBody3D.new()
	sb.name = "TerrainCollision"
	var col := CollisionShape3D.new()
	col.name = "TerrainShape"
	col.shape = mesh.create_trimesh_shape()
	sb.add_child(col)
	add_child(sb)

func _add_water() -> void:
	# ⚠️ 历史大坑：PlaneMesh 默认就躺在 XZ 平面（水平），再加 rotation_degrees.x = -90
	# 会把水面/海床变成一面 1400×1400 的**竖直巨墙**立在 z=0 —— 这就是「一大块」半透明色块
	# 和「竖直条纹」的真正来源（WaterSimple 的正弦波打在竖墙上就是竖条）。现在一律不旋转。
	_add_ocean_tidewater()

# =====================================================================================
# Tidewater 风格海面（见 Shaders/OceanTidewater.gdshader）
# 双层网格：
#   · 近层 ±350m / 224 细分（≈3.1m 每格）：承载真正看得见的波形
#   · 远层 12000m / 96 细分：一路铺到地平线，避免远处露出程序化天空的「地面色」大色块
# 两层用同一个着色器，且波幅在 240~300m 之外衰减到 0 —— 拼接处两侧都是纯平面，
# 高度/法线完全一致，因此接缝不可见（等价于 Tidewater 的 CDLOD 远端。
# =====================================================================================
const USE_TIDEWATER_OCEAN := true
const NEAR_RADIUS := 760.0                      # 扩岛后岸线到 348m，近盘需盖住并留出缓冲

func _ocean_uniforms(cell: float, far_layer: bool) -> ShaderMaterial:
	var smat := ShaderMaterial.new()
	smat.shader = load("res://Shaders/OceanTidewater.gdshader")
	# 地形 / 图案
	smat.set_shader_parameter("hmap", _get_synth_height_texture())
	smat.set_shader_parameter("hmap_meta", Vector2(HM_WORLD, float(HM_SIZE)))
	smat.set_shader_parameter("sea_noise", WaterTex.make_sea_noise_texture(256))
	smat.set_shader_parameter("lace_tex", WaterTex.make_lace_texture(512, 16))
	# 光照 / 大气：与 _add_fallback_lighting 的太阳 + 程序化天空保持一致
	smat.set_shader_parameter("u_sun_dir", Vector3(0.36, 0.70, -0.62).normalized())
	smat.set_shader_parameter("u_sun_color", Color(2.30, 2.16, 1.94))
	smat.set_shader_parameter("u_sky_irr", Color(0.30, 0.42, 0.62))
	smat.set_shader_parameter("u_horizon", Color(0.60, 0.71, 0.86))
	smat.set_shader_parameter("u_zenith", Color(0.16, 0.36, 0.82))
	# 水体光学（Tidewater 的数值）
	smat.set_shader_parameter("u_absorption", Vector3(0.42, 0.075, 0.035))
	smat.set_shader_parameter("u_scattering", Vector3(0.012, 0.018, 0.024))
	smat.set_shader_parameter("u_wind_dir", Vector2(0.86, 0.51).normalized())
	smat.set_shader_parameter("u_wind_speed", 6.5)
	smat.set_shader_parameter("u_sea_level", SEA_LEVEL)
	smat.set_shader_parameter("u_wave_scale", 0.60)
	smat.set_shader_parameter("u_shore_amp", 0.42)
	smat.set_shader_parameter("u_exposure", 0.85)
	# 本层网格精度（顶点级 band-limit）/ 远层关掉 fbm+花边采样省带宽
	smat.set_shader_parameter("u_mesh_cell", cell)
	var detail: float = 1.0
	if far_layer:
		detail = 0.0
	smat.set_shader_parameter("u_use_detail", detail)
	return smat

func _add_ocean_tidewater() -> void:
	if not USE_TIDEWATER_OCEAN:
		return
	# 远层：圆环，从近层盘缘(重叠 2m)铺到 2600m。波幅在 300m 外归零，
	# 拼合处两侧都是 y=0 纯平面 → 接缝不可见；下沉 2cm 防重叠区 z-fighting。
	# 海域收缩到 2600m：按 fog_density=0.0011，环缘透射率仅 ~6%，边缘被大气透视
	# 完全融进地平线（配合天空 ground_horizon 匹配雾色），视觉上没有「水到头了」的截断感。
	var fp := MeshInstance3D.new()
	fp.name = "OceanFar"
	fp.mesh = WaterTex.make_ring_mesh(NEAR_RADIUS - 2.0, 2600.0, 512)
	var fmat := _ocean_uniforms(4.0, false)
	fmat.render_priority = -8
	fp.material_override = fmat
	fp.position.y = SEA_LEVEL - 0.02
	add_child(fp)

	# 近层：圆盘（中心密、边缘约 3m 网格）
	var np := MeshInstance3D.new()
	np.name = "OceanNear"
	np.mesh = WaterTex.make_disc_mesh(NEAR_RADIUS, 720)
	var nmat := _ocean_uniforms(NEAR_RADIUS / 6.0, false)
	nmat.render_priority = 0
	np.material_override = nmat
	np.position.y = SEA_LEVEL
	add_child(np)

# 合成地形贴图：高度图 + 细节噪声 + 营地压平，让着色器在 GPU 上取到的海床高度
# 与 land mesh 完全一致（否则折射/水深/拍岸线会和真地形错位）。烘一次缓存。
var _synth_h: ImageTexture = null

func _get_synth_height_texture() -> ImageTexture:
	if _synth_h != null:
		return _synth_h
	var half: float = HM_WORLD * 0.5
	var vals := PackedFloat32Array()
	vals.resize(HM_SIZE * HM_SIZE)
	var y: int = 0
	while y < HM_SIZE:
		var z: float = (float(y) / float(HM_SIZE - 1) - 0.5) * HM_WORLD
		var x: int = 0
		while x < HM_SIZE:
			var wx: float = (float(x) / float(HM_SIZE - 1) - 0.5) * HM_WORLD
			vals[y * HM_SIZE + x] = terrain_height(wx, z)
			x += 1
		y += 1
	# 取边界环的自然平均深度，作为「图外深海」值
	var deep: float = 0.0
	var cnt: int = 0
	var x2: int = 0
	while x2 < HM_SIZE:
		deep += vals[0 * HM_SIZE + x2] + vals[(HM_SIZE - 1) * HM_SIZE + x2]
		deep += vals[x2 * HM_SIZE + 0] + vals[x2 * HM_SIZE + HM_SIZE - 1]
		cnt += 4
		x2 += 1
	deep /= float(maxi(cnt, 1))
	# 外圈 20% 平滑混向 deep：着色器 clamp 采样图外时与图内无缝衔接（否则水深出现台阶、
	# 在水面上显示为一条横贯的暗线）
	var yy: int = 0
	while yy < HM_SIZE:
		var zz: float = absf((float(yy) / float(HM_SIZE - 1) - 0.5) * 2.0)
		var xx: int = 0
		while xx < HM_SIZE:
			var wx2: float = absf((float(xx) / float(HM_SIZE - 1) - 0.5) * 2.0)
			var rn: float = maxf(zz, wx2)
			if rn > 0.8:
				var tt: float = clampf((rn - 0.8) / 0.2, 0.0, 1.0)
				tt = tt * tt * (3.0 - 2.0 * tt)
				var i: int = yy * HM_SIZE + xx
				vals[i] = lerp(vals[i], deep, tt)
			xx += 1
		yy += 1
	_synth_h = WaterTex.make_height_texture(vals, HM_SIZE)
	return _synth_h

func _get_prefab(path: String) -> PackedScene:
	if _prefab_cache.has(path):
		return _prefab_cache[path]
	var sc := load(path) as PackedScene
	_prefab_cache[path] = sc
	return sc

func _place(path: String, x: float, z: float, scale_mul: float = 1.0, y_off: float = 0.0, yaw: float = -999.0) -> Node3D:
	var sc := _get_prefab(path)
	if sc == null:
		return null
	var holder := Node3D.new()
	holder.add_child(sc.instantiate())
	var gy := terrain_height(x, z)
	holder.position = Vector3(x, gy + y_off, z)
	holder.rotation.y = yaw if yaw > -900.0 else _rng.randf() * TAU
	var s := scale_mul * (0.85 + _rng.randf() * 0.3)
	holder.scale = Vector3.ONE * s
	add_child(holder)
	return holder

# =========================================================
# 实例化加速：装饰物走「分块 MultiMesh」
# ⚠️ 实测（改前）营地朝内陆看 objects=5428 / drawcalls=965 / prims=645 万：
#    每个装饰物一个 Node3D+MeshInstance3D，2500+ 个独立实例让视锥剔除几乎失效，
#    一帧几乎把整岛装饰全提交。改为按 128m 网格分块，每块每种 prefab 合并成
#    一个 MultiMeshInstance3D —— 视锥外的整块直接跳过，draw call 只与
#    「视锥内块数 × 种类」相关。需要挡人的（树/岩）另建纯碰撞 StaticBody3D
#    （无视觉子节点，不产生 draw call）。
# =========================================================
const CHUNK := 256.0                            # 树/灌/岩的分块边长（米）
const CHUNK_WHOLE := 100000.0                    # 草/花：整岛合成一个批次
var _mm_parts := {}
var _mm_chunks := {}
var _mm_aabb_cache := {}

func _prefab_parts(path: String) -> Array:
	if _mm_parts.has(path):
		return _mm_parts[path]
	var parts := []
	var sc := _get_prefab(path)
	if sc != null:
		var inst := sc.instantiate()
		var stack: Array = [[inst, Transform3D.IDENTITY]]
		while not stack.is_empty():
			var it = stack.pop_back()
			var n = it[0]
			var pt: Transform3D = it[1]
			if n is Node3D:
				pt = (it[1] as Transform3D) * (n as Node3D).transform
				if n is MeshInstance3D:
					var mi := n as MeshInstance3D
					if mi.mesh != null:
						parts.append({"t": pt, "mesh": mi.mesh, "ov": mi.material_override})
			for c in n.get_children():
				stack.append([c, pt])
	_mm_parts[path] = parts
	return parts

func _prefab_aabb(path: String) -> AABB:
	if _mm_aabb_cache.has(path):
		return _mm_aabb_cache[path]
	var merged := AABB()
	var has := false
	for p in _prefab_parts(path):
		var a: AABB = (p["t"] as Transform3D) * (p["mesh"] as Mesh).get_aabb()
		if has:
			merged = merged.merge(a)
		else:
			merged = a
			has = true
	if not has:
		merged = AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.0, 1.0))
	_mm_aabb_cache[path] = merged
	return merged

## 把一个装饰实例塞进所属区块批次（不立即建节点）。
## shadow=false 用于草/花/灌/鹅卵石：不进阴影 pass，省一大截几何量。
func _mm_add(path: String, x: float, z: float, y: float, yaw: float, s: float, shadow: bool, chunk: float = CHUNK) -> void:
	var parts := _prefab_parts(path)
	if parts.is_empty():
		return
	var ix := int(floor(x / chunk))
	var iz := int(floor(z / chunk))
	var base := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(x, y, z))
	for i in parts.size():
		var p = parts[i]
		var key := "%s|%d|%d|%d" % [path, ix, iz, i]
		if not _mm_chunks.has(key):
			_mm_chunks[key] = {"mesh": p["mesh"], "ov": p["ov"], "shadow": shadow, "list": []}
		(_mm_chunks[key]["list"] as Array).append(base * (p["t"] as Transform3D))

## 所有散布跑完后统一落地成 MultiMeshInstance3D。
func _mm_flush() -> void:
	var nmm := 0
	var ninst := 0
	for key in _mm_chunks:
		var e = _mm_chunks[key]
		var list: Array = e["list"]
		if list.is_empty():
			continue
		var mesh: Mesh = e["mesh"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		var merged := AABB()
		var first := true
		for i in list.size():
			var t: Transform3D = list[i]
			mm.set_instance_transform(i, t)
			var wa: AABB = t * mesh.get_aabb()
			if first:
				merged = wa
				first = false
			else:
				merged = merged.merge(wa)
		mm.custom_aabb = merged            # 显式给 AABB，避免按 mesh 本地盒误剔除
		var mi := MultiMeshInstance3D.new()
		mi.name = "MM"
		mi.multimesh = mm
		if e["ov"] != null:
			mi.material_override = e["ov"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (e["shadow"] as bool) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		nmm += 1
		ninst += list.size()
	_mm_chunks.clear()
	print("MMFLUSH blocks=%d instances=%d" % [nmm, ninst])

## 纯碰撞体（无视觉）：装饰树/岩用。逻辑与 _add_fitted_body 一致，只是盒子尺寸
## 改从 prefab 的单位尺度 AABB 推算（视觉已合并进 MultiMesh，不再有 vis 节点）。
func _mm_body(path: String, x: float, z: float, y: float, s: float, max_half: float) -> void:
	var sz := _prefab_aabb(path).size * s
	var body := StaticBody3D.new()
	body.name = "DecoBody"
	body.position = Vector3(x, y, z)
	var hy := maxf(sz.y * 0.5, 0.3)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.extents = Vector3(
		clampf(sz.x * 0.5 * 0.9, 0.2, max_half), hy,
		clampf(sz.z * 0.5 * 0.9, 0.2, max_half))
	col.shape = bs
	col.position.y = hy
	body.add_child(col)
	body.collision_mask = 0
	if maxf(sz.x, sz.z) > 2.5:
		body.collision_layer = 1
	else:
		body.collision_layer = 2
	add_child(body)

## 沙滩沙块专用：把「水平平板」贴合到坡面（对齐地形法线）+ 缩小 + 略沉入。
## ⚠️ 历史坑：原先用 _place() 把平整沙块按「中心点高度」水平摆放，斜坡上必然
## 一侧翘出地面、一侧陷进去 → 就是用户看到的「褐色平板穿模」。沙块本就是一整片
## 平坦面，必须顺着坡面铺，才不会与地形相交。
func _place_sand(path: String, x: float, z: float) -> Node3D:
	var sc := _get_prefab(path)
	if sc == null:
		return null
	var holder := Node3D.new()
	holder.add_child(sc.instantiate())
	var gy := terrain_height(x, z)
	var up := _terrain_normal(x, z)
	if up.length() < 0.001:
		up = Vector3.UP
	up = up.normalized()
	var yaw := _rng.randf() * TAU
	# 在坡面内取一个随机朝向，正交化后作基；平板局部 +Y 即为地形法线 → 贴坡。
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	fwd = fwd - up * fwd.dot(up)
	if fwd.length() < 0.001:
		fwd = Vector3(0.0, 0.0, 1.0)
	fwd = fwd.normalized()
	var right := up.cross(fwd).normalized()
	var s := _rng.randf_range(0.34, 0.55)
	var basis := Basis(right, up, fwd).scaled(Vector3.ONE * s)
	holder.transform = Transform3D(basis, Vector3(x, gy - 0.2, z))
	add_child(holder)
	return holder

## 家具专用：在入树前挂上 furniture.gd 并指定 kind，确保 _ready 用正确类型初始化。
func _place_furniture(path: String, x: float, z: float, kind: String, scale_mul: float = 1.0, y_off: float = 0.0) -> Node3D:
	var sc := _get_prefab(path)
	if sc == null:
		return null
	var holder := Node3D.new()
	holder.set_script(load("res://structures/furniture.gd"))
	holder.kind = kind
	holder.add_child(sc.instantiate())
	var gy := terrain_height(x, z)
	holder.position = Vector3(x, gy + y_off, z)
	holder.rotation.y = _rng.randf() * TAU
	var s := scale_mul * (0.85 + _rng.randf() * 0.3)
	holder.scale = Vector3.ONE * s
	add_child(holder)
	return holder

## 是否落在营地范围（含缓冲）内 —— 散布岩石/资源/拾取物时用于避开营地，
## 否则会与栅栏/帐篷/篝火穿模（大树直接长穿栅栏就是此因：旧代码只按「离世界原点距离」过滤，
## 而营地在 (70,95) 距原点≈118m 落在散布环内，于是资源点被撒进营地）。
func _inside_camp(x: float, z: float, margin: float) -> bool:
	return Vector2(x, z).distance_to(CAMP_CENTER) < CAMP_HALF + margin

## 岩石：林间与坡地；巢穴区另布暗石。
func _scatter_rocks() -> void:
	var placed := 0
	var attempts := 0
	while placed < 210 and attempts < 6000:   # 扩岛后陆地外缘已到 r≈330~480，半径/数量同步外扩
		attempts += 1
		var x := _rng.randf_range(-440.0, 440.0)
		var z := _rng.randf_range(-440.0, 440.0)
		var r := Vector2(x, z).length()
		if r < 87.0 or r > 440.0:
			continue
		var h := terrain_height(x, z)
		if h < 1.0:
			continue
		if Vector2(x, z).distance_to(NEST_CENTER) < MOUNTAIN_R:
			continue
		if _inside_camp(x, z, 8.0):
			continue                       # 营地/院子内不放岩石（会与栅栏/帐篷穿模）
		var rp: String = P_ROCKS[_rng.randi() % P_ROCKS.size()]
		var rs: float = _rng.randf_range(0.8, 2.2)
		var ry: float = h - 0.2
		# 鹅卵石不投影（省阴影 pass）；大岩保留投影
		_mm_add(rp, x, z, ry, _rng.randf() * TAU, rs, rp.find("Pebble") < 0)
		_mm_body(rp, x, z, ry, rs, 4.0)
		placed += 1

## 装饰岩石：包围盒贴合的实心碰撞（大石挡人、小石放第 2 层不挡人）。
## 原来 _place() 不加碰撞 → 玩家能直接穿进石头（穿模）；这里补上贴合碰撞，
## 水平方向按真实足迹（上限 4m），不会像树那样出现「隐形大墙」。
func _place_rock(path: String, x: float, z: float, scale_mul: float, y_off: float) -> void:
	var sc := _get_prefab(path)
	if sc == null:
		return
	var body := StaticBody3D.new()
	body.name = "Rock"
	var vis: Node3D = sc.instantiate() as Node3D
	if vis == null:
		return
	body.add_child(vis)
	var s := scale_mul * (0.85 + _rng.randf() * 0.3)
	vis.scale = Vector3.ONE * s
	var gy := terrain_height(x, z)
	body.position = Vector3(x, gy + y_off, z)
	body.rotation.y = _rng.randf() * TAU
	add_child(body)
	_add_fitted_body(body, vis, s, 4.0)

## 依据可见模型包围盒，给静态体加一个贴合的碰撞盒。
## max_half 为水平半宽上限：树取 1.5（收成树干粗细），岩石取真实足迹（上限 4m）。
func _add_fitted_body(body: StaticBody3D, vis: Node, s: float, max_half: float) -> void:
	var aabb := _node_aabb(vis)
	var sz := aabb.size * s
	var hy := maxf(sz.y * 0.5, 0.3)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.extents = Vector3(
		clampf(sz.x * 0.5 * 0.9, 0.2, max_half), hy,
		clampf(sz.z * 0.5 * 0.9, 0.2, max_half))
	col.shape = bs
	col.position.y = hy
	body.add_child(col)
	body.collision_mask = 0
	# 大物体实心挡人；小物体（鹅卵石等）放第 2 层，玩家可走过、不再「卡石头」。
	if maxf(sz.x, sz.z) > 2.5:
		body.collision_layer = 1
	else:
		body.collision_layer = 2

## 装饰森林树 / 枯树：视觉 + 贴合树干的实心碰撞。
## ⚠️ 历史坑：装饰树原走 _place() 完全不带碰撞 → 玩家能直接走进树干里（穿模）。
## 树干碰撞用贴合包围盒、水平半宽封顶 1.5m（与可采集树一致），既挡玩家又不会形成「隐形大墙」。
func _place_tree(path: String, x: float, z: float, scale_mul: float, y_off: float) -> void:
	var sc := _get_prefab(path)
	if sc == null:
		return
	var vis: Node3D = sc.instantiate() as Node3D
	if vis == null:
		return
	var body := StaticBody3D.new()
	body.name = "Tree"
	body.add_child(vis)
	var s := scale_mul * (0.85 + _rng.randf() * 0.3)
	vis.scale = Vector3.ONE * s
	var gy := terrain_height(x, z)
	body.position = Vector3(x, gy + y_off, z)
	body.rotation.y = _rng.randf() * TAU
	add_child(body)
	_add_fitted_body(body, vis, s, 1.5)

## 递归合并节点下所有 MeshInstance3D 的包围盒（本地空间）。
func _node_aabb(root: Node) -> AABB:
	var merged := AABB()
	var has := false
	var stack: Array = [root]
	while not stack.is_empty():
		var cur = stack.pop_back()
		if cur is MeshInstance3D and cur.mesh != null:
			var mi: MeshInstance3D = cur
			var a: AABB = mi.transform * mi.get_aabb()
			if has:
				merged = merged.merge(a)
			else:
				merged = a
				has = true
		for c in cur.get_children():
			stack.append(c)
	if not has:
		return AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.0, 1.0))
	return merged

## 森林：环营地成林（吉卜力阔叶/松/扭曲树 + 灌木 + 草 + 花）。
func _scatter_forest() -> void:
	var placed := 0
	var attempts := 0
	while placed < 880 and attempts < 26000:
		attempts += 1
		var x := _rng.randf_range(-430.0, 430.0)
		var z := _rng.randf_range(-430.0, 430.0)
		var r := Vector2(x, z).length()
		if r < 104.3 or r > 430.0:
			continue
		if Vector2(x, z).distance_to(CAMP_CENTER) < CAMP_HALF + 15.0:
			continue                       # 营地外留足空地不种树（栅栏预制体宽~5m，外围视觉边≈15m，须让大树冠也不贴栅栏）
		var h := terrain_height(x, z)
		# 下限提到 2.0：海岸沙带（h<2）不长大树，树线自然停在沙滩后缘
		if h < 2.0 or h > 34.0:
			continue
		if Vector2(x, z).distance_to(NEST_CENTER) < MOUNTAIN_R + 8.0:
			continue
		var tp: String = P_TREES[_rng.randi() % P_TREES.size()]
		var ts: float = _rng.randf_range(0.9, 1.7)
		var ty: float = h - 0.15
		_mm_add(tp, x, z, ty, _rng.randf() * TAU, ts, true)
		_mm_body(tp, x, z, ty, ts, 1.5)
		placed += 1

	placed = 0; attempts = 0
	while placed < 430 and attempts < 14000:
		attempts += 1
		var x := _rng.randf_range(-430.0, 430.0)
		var z := _rng.randf_range(-430.0, 430.0)
		var r := Vector2(x, z).length()
		if r < 95.7 or r > 430.0:
			continue
		if Vector2(x, z).distance_to(CAMP_CENTER) < CAMP_HALF + 6.0:
			continue                       # 营地及院子范围不种灌木
		var h := terrain_height(x, z)
		if h < 1.5 or h > 24.0:
			continue
		_mm_add(P_BUSHES[_rng.randi() % P_BUSHES.size()], x, z, h - 0.1, _rng.randf() * TAU, _rng.randf_range(0.8, 1.4), false)
		placed += 1

	placed = 0; attempts = 0
	while placed < 1400 and attempts < 26000:
		attempts += 1
		var x := _rng.randf_range(-430.0, 430.0)
		var z := _rng.randf_range(-430.0, 430.0)
		var r := Vector2(x, z).length()
		if r < 91.3 or r > 430.0:
			continue
		var h := terrain_height(x, z)
		if h < 1.2 or h > 22.0:
			continue
		_mm_add(P_GRASS[_rng.randi() % P_GRASS.size()], x, z, h - 0.05, _rng.randf() * TAU, _rng.randf_range(0.9, 1.8), false, CHUNK_WHOLE)
		placed += 1

	placed = 0; attempts = 0
	while placed < 500 and attempts < 14000:
		attempts += 1
		var x := _rng.randf_range(-430.0, 430.0)
		var z := _rng.randf_range(-430.0, 430.0)
		var r := Vector2(x, z).length()
		if r < 95.7 or r > 430.0:
			continue
		if Vector2(x, z).distance_to(CAMP_CENTER) < CAMP_HALF + 6.0:
			continue                       # 营地及院子范围不种花
		var h := terrain_height(x, z)
		if h < 1.5 or h > 20.0:
			continue
		_mm_add(P_FLOWERS[_rng.randi() % P_FLOWERS.size()], x, z, h - 0.05, _rng.randf() * TAU, _rng.randf_range(0.8, 1.3), false, CHUNK_WHOLE)
		placed += 1

# =========================================================
# 营地（栅栏 + 破帐篷 + 篝火 + 女主）——家具/树等留作后续任务，不在此堆放
# =========================================================
func _build_camp() -> void:
	var cx := CAMP_CENTER.x
	var cz := CAMP_CENTER.y
	# 栅栏：40x40 正方形（半幅 CAMP_HALF），南向（+z）留大门
	_build_fence_square(cx, cz, CAMP_HALF)
	# 破帐篷（程序化 A 字帐）——置于栅栏内西南角，不挡正中女主和南门
	_add_tent(cx - 6.0, cz - 6.0)
	# 篝火——东北，居中偏侧，给钓鱼/烹饪链用；不压正中间女主
	_add_campfire(cx + 5.0, cz + 5.0)
	# 营地仓库（储物箱）——东南角（帐篷在西南、篝火在东南偏中），靠近南门方便回营卸货
	_add_camp_storage(cx + 7.0, cz - 6.5)
	# 房子（营地居所）——西南区，离栅栏角与帐篷/篝火都有余量；房门朝营地中心
	_add_house(cx - 6.5, cz + 5.5)

## 在营地预摆放一个「房子」（营地居所）。复用可建造物同一场景，保证与玩家自建的一致。
func _add_house(x: float, z: float) -> void:
	var ps := load("res://structures/house.tscn") as PackedScene
	if ps == null:
		push_warning("world: 未能加载 res://structures/house.tscn")
		return
	var n := ps.instantiate() as Node3D
	if n == null:
		return
	n.name = "House"
	var gy := terrain_height(x, z)
	n.position = Vector3(x, gy, z)
	# 房门严格轴对齐（与营地栅栏同向，最贴「摆正」）：正对正南（+z = 玩家南门进场方向）。
	# 想改正东（+x，朝营地内部）只需把目标方向从 (0.0, 1.0) 换成 (1.0, 0.0)。
	# FBX 默认门朝 +Z，原始 atan2 公式门仍贴栅栏，实测需翻 PI，故沿用 atan2(dx, dz) + PI。
	var face_dir := Vector2(0.0, 1.0)   # (dx, dz)：+z 为南
	n.rotation.y = atan2(face_dir.x, face_dir.y) + PI
	add_child(n)

## 在营地预摆放一个「营地仓库」（储物箱）。复用可建造物同一场景，保证与玩家自建的一致。
func _add_camp_storage(x: float, z: float) -> void:
	var ps := load("res://structures/camp_storage.tscn") as PackedScene
	if ps == null:
		push_warning("world: 未能加载 res://structures/camp_storage.tscn")
		return
	var n := ps.instantiate() as Node3D
	if n == null:
		return
	n.name = "CampStorage"
	var gy := terrain_height(x, z)
	n.position = Vector3(x, gy, z)
	n.rotation.y = -PI * 0.5      # 箱口朝营地中心
	add_child(n)

# 沿正方形四边铺设栅栏段；南边（+z）中央留大门开口。
func _build_fence_square(cx: float, cz: float, half: float) -> void:
	var step := 2.0
	var gate_half := 3.5                       # 大门开口半宽（南向留约 7~9m 空位，供玩家自建木质大门）
	var corners: Array[Vector2] = [
		Vector2(cx - half, cz + half),          # 0 西南
		Vector2(cx + half, cz + half),          # 1 东南
		Vector2(cx + half, cz - half),          # 2 东北
		Vector2(cx - half, cz - half),          # 3 西北
	]
	# 先按边收集栅栏段，便于每边指定「营地支柱」（不可破坏、无血条）。
	var edges: Array[Array] = [[], [], [], []]
	for ei in 4:
		var s: Vector2 = corners[ei]
		var e: Vector2 = corners[(ei + 1) % 4]
		var dir: Vector2 = e - s
		var n := int(round(dir.length() / step))
		var is_south := (ei == 0)              # 0 号边为南（+z）
		for k in n:                            # k=0..n-1，末端角点由下一边起点放置
			var t := float(k) / float(n)
			var p: Vector2 = s + dir * t
			if is_south and abs(p.x - cx) < gate_half:
				continue                       # 让出大门
			var ry := 0.0
			if ei == 1 or ei == 3:             # 东/西边沿 z 方向
				ry = -PI / 2.0
			edges[ei].append({"x": p.x, "z": p.y, "ry": ry})
	# 每边选约 1/3、2/3 处各一段作为「营地支柱」：不可破坏、无血条，保营地框架不消失
	for ei in 4:
		var cnt := edges[ei].size()
		if cnt == 0:
			continue
		var idxs := [int(cnt * 0.34), int(cnt * 0.67)]
		if idxs[0] == idxs[1]:
			idxs = [int(cnt * 0.5)]
		for ix in idxs:
			if ix >= 0 and ix < cnt:
				edges[ei][ix]["anchor"] = true
	# 展开为全局列表（保持原顺序，破损标记按全局 index）
	var fence_list := []
	for ei in 4:
		for pl in edges[ei]:
			fence_list.append(pl)
	# 标记若干段为破损（沿周长均匀分布，确定性），需玩家修复（支柱除外）
	var total := fence_list.size()
	var dmg_frac: Array[float] = [0.05, 0.30, 0.52, 0.74, 0.93]
	var dmg := {}
	for fr in dmg_frac:
		dmg[int(total * fr)] = true
	var pi := 0
	for pl in fence_list:
		var f := Node3D.new()
		f.set_script(load("res://structures/fence.gd"))
		f.name = "Fence"
		if pl.get("anchor", false):
			f.indestructible = true
		if not f.indestructible and dmg.get(pi, false):
			f.damaged = true
		var fvis := _get_prefab(P_FENCE[_rng.randi() % P_FENCE.size()])
		if fvis != null:
			f.add_child(fvis.instantiate())
		var gy := terrain_height(pl["x"], pl["z"])
		f.position = Vector3(pl["x"], gy - 0.1, pl["z"])
		f.rotation.y = pl["ry"]
		f.scale = Vector3.ONE * (0.9 + _rng.randf() * 0.2)
		add_child(f)
		pi += 1
	# 南向留空位（不放自动门），由玩家用建造模式自建大号木质大门。

func _place_gate(x: float, z: float, ry: float) -> void:
	var gp := _get_prefab(P_GATE)
	if gp == null:
		return
	var g := gp.instantiate()
	g.name = "CampGate"
	var gy := terrain_height(x, z)
	g.position = Vector3(x, gy - 0.1, z)
	g.rotation.y = ry
	add_child(g)

func _add_tent(x: float, z: float) -> void:
	var tent := Node3D.new()
	tent.name = "Tent"
	var gy := terrain_height(x, z)
	# 优先使用 TRELLIS2 生成的帐篷 GLB（assets/props/tent.glb）；缺失则回退程序化 A 字帐。
	var glb := PropLoader.spawn(GLB_TENT, 2.0, true, true, 0.22)
	if glb != null:
		glb.name = "TentMesh"
		tent.add_child(glb)
	else:
		var cloth := StandardMaterial3D.new()
		cloth.albedo_color = Color(0.55, 0.45, 0.33)          # 磨损帆布
		cloth.roughness = 0.95
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 2.4
		cm.height = 3.2
		cm.radial_segments = 4
		cone.mesh = cm
		cone.material_override = cloth
		cone.rotation.y = PI / 4
		cone.position.y = 1.6
		tent.add_child(cone)
	tent.position = Vector3(x, gy, z)
	add_child(tent)

func _add_campfire(x: float, z: float) -> void:
	# 用 campfire.gd（Interactable / StaticBody3D）实例：自带 interact() + 碰撞体，
	# 可被交互系统射线命中并按 E 打开烹饪菜单（或无效时取暖）。
	var fire := preload("res://structures/campfire.gd").new()
	fire.name = "Campfire"
	var gy := terrain_height(x, z)
	# 优先使用 TRELLIS2 生成的篝火 GLB（含柴堆+火焰几何体与贴图）；缺失则回退 campfire.gd 内置图元。
	var glb := PropLoader.spawn(GLB_BONFIRE, 1.2, true, true, 0.25)
	if glb != null:
		# 用外部 GLB 当视觉 -> 跳过 campfire.gd 内置图元/灯光，避免双重视觉。
		fire.use_external_visual = true
		glb.name = "BonfireMesh"
		fire.add_child(glb)
		# 火光：GLB 不带动态灯光，补一盏橙色点光（夜晚照明 + 冷暖对比）。
		var pl := OmniLight3D.new()
		pl.name = "FireLight"
		pl.light_color = Color(1.0, 0.6, 0.3)
		pl.light_energy = 6.0
		pl.omni_range = 14.0
		pl.position.y = 1.0
		fire.add_child(pl)
	else:
		# 无 GLB：交给 campfire.gd 用内置图元（石圈+柴堆+火苗+灯光）拼出，无需额外处理。
		fire.use_external_visual = false
	fire.position = Vector3(x, gy, z)
	add_child(fire)

# =========================================================
# 沙滩（环岛沙地 + 营地朝海钓鱼点）
# =========================================================
func _build_beach() -> void:
	var n := 160   # 扩岛后岸线周长翻倍
	for i in n:
		var a := float(i) / float(n) * TAU
		# ⚠️ 岸线被域扭曲推得远近不一（约 330~430m），按固定半径摆会跑到草坡上。
		#    改为沿半径向外扫，取第一个落在 0.3~4.5m 的位置 = 真正的潮线。
		var found := -1.0
		var r := 250.0
		while r < 470.0:
			var hh := terrain_height(cos(a) * r, sin(a) * r)
			if hh < 0.3:
				break
			if hh < 4.5:
				found = r
				break
			r += 4.0
		if found < 0.0:
			found = _rng.randf_range(310.0, 360.0)
		var rr: float = clamp(found + _rng.randf_range(-16.0, 8.0), 250.0, 470.0)
		var x := cos(a) * rr
		var z := sin(a) * rr
		_place_sand(P_SAND[_rng.randi() % P_SAND.size()], x, z)
	_add_fishing_spot(FISHING_OPEN.x, FISHING_OPEN.y)
	_add_pier(FISHING_OPEN.x, FISHING_OPEN.y)
	# 向海伸出两个更深的钓点，让礁区/深水鱼（鲹/金枪/旗鱼）也能钓到；
	# 玩家走向海中（脚下地形低于海平面）即可到达，FishingSystem 按水深自动判定栖息地。
	var fdir := FISHING_OPEN.normalized()
	_add_fishing_spot(FISHING_OPEN.x + fdir.x * 26.1, FISHING_OPEN.y + fdir.y * 26.1)
	_add_fishing_spot(FISHING_OPEN.x + fdir.x * 60.9, FISHING_OPEN.y + fdir.y * 60.9)

func _add_fishing_spot(x: float, z: float, override_habitat: String = "") -> void:
	var spot := Node3D.new()
	spot.set_script(load("res://structures/fishing_spot.gd"))
	spot.name = "FishingSpot"
	spot.habitat_override = override_habitat
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new(); pm.top_radius = 0.08; pm.bottom_radius = 0.1; pm.height = 1.2
	post.mesh = pm
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.4, 0.28, 0.16)
	post.material_override = m
	post.position.y = 0.6
	spot.add_child(post)
	var gy := terrain_height(x, z)
	spot.position = Vector3(x, gy, z)
	# 碰撞体：供交互射线命中（原先没有碰撞体，射线穿过去导致钓点永远无法被选中）
	var col := StaticBody3D.new()
	var cshape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 4.0, 3.0)
	cshape.shape = box
	cshape.position = Vector3(0.0, 1.5, 0.0)
	col.add_child(cshape)
	spot.add_child(col)
	spot.add_to_group("fishing_spot")
	add_child(spot)

## 女主所在的空旷沙滩：铺一块圆形木平台，让她站得清楚、区域一目了然。
func _add_seaside_deck(x: float, z: float) -> void:
	var deck := MeshInstance3D.new()
	deck.name = "HeroineDeck"
	var dm := CylinderMesh.new()
	dm.top_radius = 4.2
	dm.bottom_radius = 4.2
	dm.height = 0.3
	deck.mesh = dm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.32, 0.20)
	m.roughness = 0.9
	deck.material_override = m
	var gy := terrain_height(x, z)
	deck.position = Vector3(x, gy + 0.16, z)
	add_child(deck)

## 钓点木栈桥：从岸边向海里伸出一段，钓鱼场景更自然。
func _add_pier(x: float, z: float) -> void:
	var dir := Vector2(x, z).normalized()
	var yaw := atan2(dir.x, dir.y)
	# 地形采样（terrain_probe）：水线 d≈7m（h≈0）；d≈8m 起 h≈-0.19m（刚入水浅滩）。
	# 旧代码放在 d=24m（深水 -1.69m）且 y=SEA_LEVEL+0.35 → 平台漂在深水外的高处，玩家根本过不去。
	# 改放 d≈8m 紧贴水线、并把台面压到水面（SEA_LEVEL+0.05），玩家从沙滩走几步就能到；岸上另放一块可踩石头当踏脚。
	var d_off := 8.0
	var pier := Node3D.new()
	pier.name = "FishingPier"
	pier.position = Vector3(x + dir.x * d_off, SEA_LEVEL + 0.05, z + dir.y * d_off)
	pier.rotation.y = yaw
	# 优先使用 TRELLIS2 生成的木栈台 GLB（方形平台）；缺失则回退长方体占位。
	var glb := PropLoader.spawn(GLB_DOCK, 0.6, true, true, 0.18)
	if glb != null:
		glb.name = "DockMesh"
		pier.add_child(glb)
		# spawn 内按世界落地的 y 在挂到 pier 下后已无意义，归零让平台坐在 pier 原点（y 由 pier.position 控制）。
		glb.position = Vector3.ZERO
	else:
		var pm := BoxMesh.new()
		pm.size = Vector3(2.2, 0.3, 9.0)
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.42, 0.30, 0.18)
		m.roughness = 0.9
		mi.material_override = m
		pier.add_child(mi)
	# 靠在栈台边的一支鱼竿（TRELLIS2 生成，细长 1 单位高，立起来≈2.4m）；缺失则跳过。
	var rod := PropLoader.spawn(GLB_ROD, 2.4, true, true, 0.18)
	if rod != null:
		rod.name = "FishingRodProp"
		rod.rotation = Vector3(0.22, yaw + 0.6, 0.0)   # 略斜靠，别正竖
		rod.position = Vector3(1.6, 0.6, 1.6)          # 平台一角
		pier.add_child(rod)
	add_child(pier)
	# 岸边放一块可踩的石头（带碰撞），让玩家能从沙滩跳上去、再上栈台。
	var sdir := Vector2(x, z).normalized()
	_place_rock(P_ROCKS[0], x + sdir.x * 6.0, z + sdir.y * 6.0, 0.5, 0.0)
	# 栈桥末端设一个强制 "pier" 栖息地的钓点（站在桥上钓码头鱼：鲈鱼/鲹鱼）。
	# 与栈台同心（d≈8m，水线附近）——post 从栈台面升起，交互射线能命中。
	_add_fishing_spot(x + dir.x * 8.0, z + dir.y * 8.0, "pier")

## 返回全部钓点的世界坐标（Vector2），供 CreatureSpawner 设「刷怪禁区」，
## 避免野怪刷在钓点旁边（钓鱼时强制第一人称、不便战斗）。
func get_fishing_spot_positions() -> Array:
	var fdir := FISHING_OPEN.normalized()
	return [
		FISHING_OPEN,                                                              # 岸边钓点
		Vector2(FISHING_OPEN.x + fdir.x * 26.1, FISHING_OPEN.y + fdir.y * 26.1),  # 离岸浅钓点
		Vector2(FISHING_OPEN.x + fdir.x * 60.9, FISHING_OPEN.y + fdir.y * 60.9),  # 离岸深钓点
		Vector2(FISHING_OPEN.x + fdir.x * 8.0, FISHING_OPEN.y + fdir.y * 8.0),  # 栈台 pier 钓点（与 _add_pier 同心，水线附近）
	]

# =========================================================
# 岛心深处 · 野怪巢穴（枯树 + 暗石 + 祭坛 + 野怪篝火）
# =========================================================
func _build_nest() -> void:
	var nx := NEST_CENTER.x
	var nz := NEST_CENTER.y
	var placed := 0
	var attempts := 0
	while placed < 40 and attempts < 800:
		attempts += 1
		var a := _rng.randf() * TAU
		var rad := _rng.randf_range(20.0, MOUNTAIN_R - 6.0)
		var x := nx + cos(a) * rad
		var z := nz + sin(a) * rad
		var h := terrain_height(x, z)
		if h < 8.0:
			continue
		_place_tree(P_DEAD[_rng.randi() % P_DEAD.size()], x, z, _rng.randf_range(1.0, 1.8), -0.2)
		placed += 1

	placed = 0; attempts = 0
	while placed < 24 and attempts < 400:
		attempts += 1
		var a := _rng.randf() * TAU
		var rad := _rng.randf_range(8.0, MOUNTAIN_R)
		var x := nx + cos(a) * rad
		var z := nz + sin(a) * rad
		_place_rock(P_ROCKS[_rng.randi() % P_ROCKS.size()], x, z, _rng.randf_range(1.0, 2.4), -0.2)
		placed += 1

	_add_altar(nx, nz + 4.0)
	_add_enemy_fire(nx - 8.0, nz - 6.0)
	var marker := Node3D.new()
	marker.name = "MonsterNest"
	marker.position = Vector3(nx, terrain_height(nx, nz), nz)
	marker.add_to_group("monster_nest")
	add_child(marker)

func _add_altar(x: float, z: float) -> void:
	var alt := Node3D.new()
	alt.set_script(load("res://structures/altar.gd"))
	alt.name = "Altar"
	var ped := MeshInstance3D.new()
	var pm := CylinderMesh.new(); pm.top_radius = 1.6; pm.bottom_radius = 2.0; pm.height = 1.4
	ped.mesh = pm
	var sm := StandardMaterial3D.new(); sm.albedo_color = Color(0.30, 0.30, 0.34); sm.roughness = 0.9
	ped.material_override = sm
	ped.position.y = 0.7
	alt.add_child(ped)
	var orb := MeshInstance3D.new()
	var om := SphereMesh.new(); om.radius = 0.7; om.height = 1.4
	orb.mesh = om
	var om_mat := StandardMaterial3D.new()
	om_mat.albedo_color = Color(0.5, 0.8, 0.7, 0.8)
	om_mat.emission_enabled = true
	om_mat.emission = Color(0.3, 0.9, 0.7)
	om_mat.emission_energy = 3.0
	om_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	orb.material_override = om_mat
	orb.position.y = 2.2
	alt.add_child(orb)
	var pl := OmniLight3D.new()
	pl.light_color = Color(0.4, 0.9, 0.7)
	pl.light_energy = 8.0
	pl.omni_range = 22.0
	pl.position.y = 2.5
	alt.add_child(pl)
	var gy := terrain_height(x, z)
	alt.position = Vector3(x, gy, z)
	add_child(alt)

func _add_enemy_fire(x: float, z: float) -> void:
	var fire := Node3D.new()
	fire.name = "EnemyFire"
	var flame := MeshInstance3D.new()
	var fm := CylinderMesh.new(); fm.top_radius = 0.0; fm.bottom_radius = 0.4; fm.height = 1.0; fm.radial_segments = 6
	flame.mesh = fm
	var fl_mat := StandardMaterial3D.new()
	fl_mat.albedo_color = Color(1.0, 0.25, 0.15, 0.85)
	fl_mat.emission_enabled = true
	fl_mat.emission = Color(1.0, 0.2, 0.1)
	fl_mat.emission_energy = 2.0
	fl_mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	flame.material_override = fl_mat
	flame.position.y = 0.6
	fire.add_child(flame)
	var pl := OmniLight3D.new()
	pl.light_color = Color(1.0, 0.3, 0.2)
	pl.light_energy = 5.0
	pl.omni_range = 12.0
	pl.position.y = 1.0
	fire.add_child(pl)
	var gy := terrain_height(x, z)
	fire.position = Vector3(x, gy, z)
	add_child(fire)

# =========================================================
# NPC / 交互物
# =========================================================
func _spawn_heroine() -> void:
	var hero := Node3D.new()
	hero.set_script(load("res://npc/heroine.gd"))
	hero.name = "Heroine"
	var sc = load(HEROINE)
	if sc != null:
		hero.add_child(sc.instantiate())
	var px := HEROINE_OPEN.x
	var pz := HEROINE_OPEN.y
	add_child(hero)
	hero.global_position = Vector3(px, get_ground_height(px, pz), pz)
	# 营地位于坡地，女主是自由节点（无物理），需对齐地表法线避免半边陷进山坡；
	# 再轻微抬升抵消模型脚底与原点间的微小偏差。
	var nrm := _terrain_normal(px, pz)
	hero.quaternion = Quaternion(Vector3.UP, nrm)
	hero.global_position.y += 0.06

func _spawn_bulletin_board() -> void:
	var sc = load("res://world/bulletin_board.gd")
	if sc == null:
		return
	var node := StaticBody3D.new()
	node.name = "BulletinBoard"
	node.set_script(sc)
	var px := CAMP_CENTER.x + 16.0
	var pz := CAMP_CENTER.y + 14.0
	node.position = Vector3(px, get_ground_height(px, pz), pz)
	add_child(node)

func _spawn_sign() -> void:
	var scn = load("res://world/sign.tscn")
	if scn == null:
		return
	var inst = scn.instantiate()
	add_child(inst)
	var px := CAMP_CENTER.x + 24.0
	var pz := CAMP_CENTER.y + 4.0
	inst.global_position = Vector3(px, get_ground_height(px, pz), pz)

# =========================================================
# 可交互资源节点（采集循环入口）
# =========================================================
func _spawn_resource_nodes() -> void:
	# ⚠️ 扩岛前资源按「岛心 r≤125」采样，而营地已搬到 r=348 的海岸台地 —— 玩家出门要往内陆走 220m
	# 才摸到第一棵树。现改为：前 near_count 个强制落在营地周边（开局伸手可及），其余全岛散布。
	_spawn_resource_group(P_TREES, 30, {"log": 2, "stick": 2}, "砍伐树木 (E)", 1.2, Vector2(1.5, 30.0), 48.0, "axe", "斧头", "", {}, 12)
	_spawn_resource_group(P_ROCKS, 18, {"stone": 2, "flintstone": 1}, "采集矿石 (E)", 1.4, Vector2(2.0, 40.0), 44.0, "pickaxe", "镐", "", {}, 8)
	_spawn_resource_group(P_BUSHES, 20, {"berry": 3, "stick": 1, "bait": 1}, "采集浆果 (E)", 1.1, Vector2(1.0, 26.0), 44.0, "", "", "sickle", {"berry": 3}, 9, false)
	_spawn_loose_pickups()

func _spawn_loose_pickups() -> void:
	var pk := load("res://world/ground_pickup.gd")
	for i in 46:
		var p: Variant = _rand_low_ground(2.0, 16.0, 14.0)
		if p != null:
			_spawn_pickup(pk, {"stick": 1}, "", "", "stick", "拾取树枝 (E)", p.x, p.y)
	for i in 34:
		var p: Variant = _rand_low_ground(2.0, 16.0, 14.0)
		if p != null:
			_spawn_pickup(pk, {"stone": 1}, "", "", "stone", "拾取石头 (E)", p.x, p.y)
	for i in 22:
		var p: Variant = _rand_low_ground(1.0, 22.0, 30.0)
		if p != null:
			_spawn_pickup(pk, {"flintstone": 1, "root": 1}, "shovel", "铲子", "mound", "挖掘土堆 (E)", p.x, p.y)

func _rand_low_ground(hmin: float, hmax: float, avoid_camp: float) -> Variant:
	# 同资源节点：以营地为圆心环内采样（原按岛心采样 → 拾取物全在 220m 外的山脚）
	for a in 60:
		var la := _rng.randf() * TAU
		var lr := sqrt(_rng.randf() * (120.0 * 120.0 - avoid_camp * avoid_camp) + avoid_camp * avoid_camp)
		var x := CAMP_CENTER.x + cos(la) * lr
		var z := CAMP_CENTER.y + sin(la) * lr
		if _inside_camp(x, z, 2.5):
			continue                       # 地面拾取物别落在营地/帐篷/篝火里
		var h := terrain_height(x, z)
		if h < hmin or h > hmax:
			continue
		if Vector2(x, z).distance_to(NEST_CENTER) < MOUNTAIN_R + 10.0:
			continue
		return Vector2(x, z)
	return null

func _spawn_pickup(script: Script, drops: Dictionary, required_tool: String, tool_name: String, visual: String, prompt: String, x: float, z: float) -> void:
	var node := StaticBody3D.new()
	node.name = "GroundPickup"
	node.set_script(script)
	node.drops = drops
	node.required_tool = required_tool
	node.tool_name = tool_name
	node.visual = visual
	node.prompt = prompt
	var gy := terrain_height(x, z)
	node.position = Vector3(x, gy, z)
	node.rotation.y = _rng.randf() * TAU
	add_child(node)

func _spawn_resource_group(paths: Array, count: int, drops: Dictionary, prompt: String, scale_mul: float, height_range: Vector2, avoid_camp: float, required_tool: String = "", tool_name: String = "", bonus_tool: String = "", bonus_drops: Dictionary = {}, near_count: int = 0, shadow: bool = true) -> void:
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 40:
		attempts += 1
		# 前 near_count 个：以营地为圆心、[avoid_camp, 130m] 环内均匀（按面积开方采样，避免外疏内密）
		# 其余：全岛陆地随机（h 检查会把海面/沙滩自动剔掉）
		var x: float
		var z: float
		if placed < near_count:
			var na := _rng.randf() * TAU
			var nr := sqrt(_rng.randf() * (130.0 * 130.0 - avoid_camp * avoid_camp) + avoid_camp * avoid_camp)
			x = CAMP_CENTER.x + cos(na) * nr
			z = CAMP_CENTER.y + sin(na) * nr
		else:
			var wa := _rng.randf() * TAU
			var wr := sqrt(_rng.randf() * (430.0 * 430.0 - 60.0 * 60.0) + 60.0 * 60.0)
			x = cos(wa) * wr
			z = sin(wa) * wr
			if Vector2(x, z).distance_to(CAMP_CENTER) < avoid_camp:
				continue
		if _inside_camp(x, z, 15.0):
			continue                       # 营地外留足空地不放树/矿/灌木（否则大树冠贴栅栏像穿模）
		var h := terrain_height(x, z)
		if h < height_range.x or h > height_range.y:
			continue
		if Vector2(x, z).distance_to(NEST_CENTER) < MOUNTAIN_R + 10.0:
			continue
		var rpath: String = paths[_rng.randi() % paths.size()]
		var sc = _get_prefab(rpath)
		if sc == null:
			continue
		var node := StaticBody3D.new()
		node.name = "ResourceNode"
		node.set_script(load("res://world/resource_node.gd"))
		node.visual_scene = sc
		node.drops = drops
		node.prompt = prompt
		node.scale_mul = scale_mul
		node.required_tool = required_tool
		node.tool_name = tool_name
		node.bonus_tool = bonus_tool
		node.bonus_drops = bonus_drops
		var gy := terrain_height(x, z)
		var yaw := _rng.randf() * TAU
		node.position = Vector3(x, gy, z)
		node.rotation.y = yaw
		# 视觉交 world 的 _mm_add 分块 MultiMesh 合批（与散布树/石同套系统），
		# 节点只保留 StaticBody3D + 碰撞供采集，省掉整 GLB 的十几个子 MeshInstance3D draw call。
		_mm_add(rpath, x, z, gy, yaw, scale_mul, shadow)
		add_child(node)
		placed += 1
