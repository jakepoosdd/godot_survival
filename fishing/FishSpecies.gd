class_name FishSpecies
extends Resource
## 鱼种定义（数据驱动）。对应 Tidewater 的 FishSpecies：体长-体重关系、栖息地、水深、
## 时段偏好、稀有度、搏斗强度。长度-体重用 W(kg) = weight_a * L(cm)^weight_b。

# 栖息地（由地形水深+离岸距离推导，见 FishingSystem._detect_water）
const H_SHALLOWS := "shallows"   # 浅滩（近岸 <1.5m）
const H_BAY      := "bay"        # 海湾（近岸缓水）
const H_REEF     := "reef"       # 礁区（岩礁/珊瑚）
const H_PIER     := "pier"       # 码头/栈桥下
const H_DEEP     := "deep"       # 深水（离岸远/深）

@export var id: String = ""
@export var display_name: String = "鱼"
@export var habitats: Array[String] = ["shallows"]
@export var min_depth: float = 0.0      # 可咬钩的最小水深(米)
@export var max_depth: float = 99.0     # 可咬钩的最大水深(米)
@export var min_len: float = 15.0       # 体长下限(cm)
@export var max_len: float = 80.0       # 体长上限(cm)
@export var weight_a: float = 0.00001   # 体长-体重系数
@export var weight_b: float = 3.0       # 体长-体重指数
@export var active_from: float = 0.0    # 活跃时段起点(0..1，0=午夜)
@export var active_to: float = 1.0      # 活跃时段终点(0..1)；from>to 表示跨午夜
@export var rarity: float = 0.5         # 0=常见 1=极稀有（影响被选中权重）
@export var fight_pull: float = 0.25    # 挣扎时张力上升速率
@export var fight_stamina: float = 4.0  # 挣扎持续时间(秒)
@export var value: int = 10             # 基础卖价(金币)
@export var food: float = 8.0           # 食用恢复饥饿值
@export var tint: Color = Color(0.6, 0.7, 0.8)
@export var anatomy_id: String = ""     # 程序化鱼模型原型（对应 tidewater_fish_data.gd 的解剖表 id）

## 当前时刻是否活跃（GameManager.time_of_day 0..1）
func is_active(time01: float) -> bool:
	if active_from <= active_to:
		return time01 >= active_from and time01 <= active_to
	return time01 >= active_from or time01 <= active_to   # 跨午夜

## 给定体长(cm)返回体重(kg)
func weight_kg(len_cm: float) -> float:
	var L := len_cm
	if L < 0.001:
		L = 0.001
	return weight_a * pow(L, weight_b)

## 该栖息地是否适合此鱼
func likes(habitat: String) -> bool:
	return habitats.has(habitat)
