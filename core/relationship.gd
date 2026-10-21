extends Node
## 关系系统（Autoload: RelationshipManager）。管理女主「好感」与「心情」。
## 好感 = 繁衍门槛；心情 = 女主状态（饱食/被照顾程度），影响产出与每日结算。
## 设计见 玩法与剧情设计文档 3.7 / 3.8 / 3.9。

const AFF_MAX := 100.0
const MOOD_MAX := 100.0

var affection := 0.0
var mood := 60.0          # 开局心情尚可
var bred_count := 0

# 送礼好感表（item_id -> 好感增量）。鱼按价值/稀有度给好感（取代原来的卖钱）。
const GIFT_AFFECTION := {
	"fish_marlin": 20.0,    # 传说级旗鱼
	"fish_tuna": 14.0,
	"fish_trevally": 9.0,
	"fish_grouper": 8.0,
	"fish_snapper": 6.0,
	"fish_eel": 7.0,
	"fish_mackerel": 5.0,
	"fish_bass": 4.0,
	"fish_sardine": 2.0,
	"fish_snook": 8.0,
	"fish_tarpon": 20.0,
	"fish_bonefish": 7.0,
	"fish_permit": 12.0,
	"fish_barracuda": 11.0,
	"fish_yellowtail": 13.0,
	"fish_hogfish": 9.0,
	"fish_parrotfish": 8.0,
	"fish_kingfish": 14.0,
	"fish_rare": 12.0,
	"fish_big": 8.0,
	"cooked_fish": 5.0,
	"cookedmeat": 5.0,
	"fish_small": 4.0,
	"berry": 2.0,
	"rawmeat": -1.0,
}
# 食物类礼物额外加心情（饱食）
const GIFT_MOOD := {
	"fish_marlin": 12.0,
	"fish_tuna": 10.0,
	"fish_trevally": 7.0,
	"fish_grouper": 7.0,
	"fish_snapper": 6.0,
	"fish_eel": 6.0,
	"fish_mackerel": 5.0,
	"fish_bass": 5.0,
	"fish_sardine": 3.0,
	"fish_snook": 7.0,
	"fish_tarpon": 14.0,
	"fish_bonefish": 6.0,
	"fish_permit": 10.0,
	"fish_barracuda": 9.0,
	"fish_yellowtail": 11.0,
	"fish_hogfish": 8.0,
	"fish_parrotfish": 7.0,
	"fish_kingfish": 12.0,
	"fish_rare": 10.0,
	"fish_big": 8.0,
	"cooked_fish": 10.0,
	"cookedmeat": 8.0,
	"fish_small": 5.0,
	"berry": 3.0,
}

# 注意：好感/心情/化形三个信号统一由 EventBus 持有（EventBus.affection_changed /
# mood_changed / companion_bred）。此处**不得**再重复声明同名 signal —— 否则会变成
# 只在本节点内部广播的「死信号」，HUD 挂在 EventBus 上永远收不到（详情见 MEMORY）。

func _ready() -> void:
	EventBus.day_changed.connect(_on_day)
	EventBus.player_died.connect(_on_player_died)
	EventBus.fence_broken.connect(func(_s): add_mood(-30.0, "栅栏被破，女主担惊"))
	EventBus.raid_wave_ended.connect(func(): add_affection(5.0, "成功守夜"))

func _on_day(day: int) -> void:
	# 繁衍判定：好感满 + 心情(饱食)满 -> 感召岛灵化形（先于每日心情结算，
	# 因为玩家在白天把两项喂满后睡觉到天亮，此处即触发；触发后好感/心情清零，衰减不再有意义）。
	if affection >= AFF_MAX and mood >= MOOD_MAX:
		_breed()
		return
	# 每日结算：心情随饥饿自然下降
	add_mood(-15.0, "")

func _on_player_died() -> void:
	# 主角死亡：好感清零、心情受挫（见 3.9）
	affection = 0.0
	mood = maxf(0.0, mood - 20.0)
	EventBus.affection_changed.emit(affection)
	EventBus.mood_changed.emit(mood)

## 送礼：返回好感增量（调用方负责消耗物品）
func gift(item_id: String) -> float:
	var da: float = GIFT_AFFECTION.get(item_id, 0.0)
	if da != 0.0:
		add_affection(da, "")
	var dm: float = GIFT_MOOD.get(item_id, 0.0)
	if dm != 0.0:
		add_mood(dm, "")
	return da

func add_affection(delta: float, _why: String) -> void:
	affection = clampf(affection + delta, 0.0, AFF_MAX)
	EventBus.affection_changed.emit(affection)

## 把女主好感提升到 target（仅在当前低于 target 时补差，绝不降低，避免误触繁衍）。
func raise_affection_to(target: float, why: String) -> void:
	if affection < target:
		add_affection(target - affection, why)

func add_mood(delta: float, _why: String) -> void:
	mood = clampf(mood + delta, 0.0, MOOD_MAX)
	EventBus.mood_changed.emit(mood)

func _breed() -> void:
	var types := ["gather", "fighter", "versatile"]
	var t: String = types[randi() % types.size()]
	bred_count += 1
	affection = 0.0
	mood = 0.0
	EventBus.affection_changed.emit(affection)
	EventBus.mood_changed.emit(mood)
	EventBus.toast.emit("岛灵受感召，化形为新的伙伴！")
	EventBus.companion_bred.emit(t)

func get_status() -> Dictionary:
	return {
		"affection": affection,
		"mood": mood,
		"affection_max": AFF_MAX,
		"mood_max": MOOD_MAX,
		"bred_count": bred_count,
		"can_breed": affection >= AFF_MAX and mood >= MOOD_MAX,
	}
