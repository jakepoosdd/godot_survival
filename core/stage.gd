extends Node
## 阶段进度（Autoload: Stage）。随天数推进阶段，阶段切换时提示并调整刷怪上限。

const STAGES := [
	{"name": "开拓期", "min_day": 1, "desc": "初到荒岛——采集、生火、活下来。"},
	{"name": "定居期", "min_day": 3, "desc": "建立据点，储备木料与石材。"},
	{"name": "发展期", "min_day": 6, "desc": "驯服野兽，强化装备与工具。"},
	{"name": "繁荣期", "min_day": 10, "desc": "称霸荒岛，成为幸存之王。"},
]
var index := 0

func _ready() -> void:
	EventBus.day_changed.connect(_on_day)
	_refresh(false)

func _on_day(_day: int) -> void:
	_refresh(true)

func _refresh(announce: bool) -> void:
	var d := GameManager.day_count
	var new_idx := 0
	for i in STAGES.size():
		if d >= int(STAGES[i]["min_day"]):
			new_idx = i
	if new_idx != index:
		index = new_idx
		var s: Dictionary = STAGES[index]
		# 注意：必须发到 EventBus.stage_changed（监听器都连在 EventBus 上），
		# Stage 本身不再声明同名 signal，否则会被遮蔽成只属于 Stage 的死信号。
		EventBus.stage_changed.emit(index, s["name"], s["desc"])
		if announce:
			EventBus.toast.emit("阶段变化：%s — %s" % [s["name"], s["desc"]])
		# 随阶段提升刷怪上限，难度循序渐进
		if CreatureSpawner.has_method("set_cap"):
			CreatureSpawner.set_cap(18 + index * 3)

func current_name() -> String:
	return STAGES[index]["name"]
