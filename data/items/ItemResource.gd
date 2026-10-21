class_name ItemResource
extends Resource
## 物品定义（数据驱动）。对应 IslandSurvival 的 GameItemResource 思想，按 godot_survival 架构重写适配。
## 物品在 data/items/ 下用 .tres 定义，由 ItemDatabase 自动扫描注册。加物品 = 在该目录丢一个 .tres。

enum Category { MATERIAL, WEAPON, TOOL, CONSUMABLE, BUILDING, GEAR }

@export var id: String = ""
@export var display_name: String = "物品"
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var category: Category = Category.MATERIAL
@export_range(1, 999) var stack_size: int = 50
@export var item_weight: float = 1.0

# 消耗品效果（正=恢复，负=扣）
@export var health_change: float = 0.0
@export var hunger_change: float = 0.0
@export var thirst_change: float = 0.0
@export var sanity_change: float = 0.0

# 武器：>0 时该物品可作为武器，攻击时取背包内最高 weapon_damage 作为本次伤害加成
@export var weapon_damage: float = 0.0

# 烹饪：cooked_result 非空表示该物品是可烹饪生食材，烹饪后产出该 id 的物品
@export var cooked_result: String = ""
@export var cook_time: float = 3.0

# 建造/制作
@export var constructable_scene: PackedScene
@export var crafting_costs: Array[Dictionary] = []  # [{"id":"stick","amount":3}] （制造配方：制作该物品消耗的材料）
@export var build_costs: Array[Dictionary] = []     # [{"id":"stick","amount":3}] （建造配方：放置该结构时直接消耗的材料；空则退回耗 1 个成品）
@export var upgrade_slots: int = 0   # >0 时该物品为「背包扩容包」：制作即扩容对应格数，不入背包

# 商店 / 经济（买家/卖家；buy_price/sell_price 为 0 时由 Economy 按类别推导）
@export var purchasable: bool = false
@export var sellable: bool = false
@export var buy_price: int = 0
@export var sell_price: int = 0
@export var buy_disabled: bool = false   # 仅可卖、不可买（如钓到的鱼，防止商人反向倒卖）
