extends Node
## 任务指引（Autoload: TaskGuide）。清单式目标：每步独立完成，对应事件触发后打勾；
## 界面始终显示「下一个未完成目标」。只监听 EventBus 现有信号，不持有节点引用，保持解耦。

signal task_changed(current_idx: int, text: String, all_done: bool)

var _steps: Array = []
var _idx := 0
var _all_done := false
var _final_awarded := false

func _ready() -> void:
	_build_steps()
	EventBus.resource_harvested.connect(_on_harvest)
	EventBus.recipe_crafted.connect(_on_craft)
	EventBus.structure_placed.connect(_on_placed)
	EventBus.food_cooked.connect(_on_cooked)
	EventBus.food_eaten.connect(_on_eaten)
	EventBus.creature_died.connect(_on_creature_died)
	EventBus.skill_unlocked.connect(_on_skill)
	_emit_current()

func _build_steps() -> void:
	_steps = [
		{"id": "scavenge", "text": "① 拾荒起步：捡散落的树枝/石头、采浆果（无需工具，按 E）", "done": false},
		{"text": "② 制作工具：按 C 制作 斧头(3树枝+1石头) / 镐(2树枝+2石头) / 镰刀(1树枝+1石头)", "done": false},
		{"text": "③ 进阶采集：持斧头砍树得木材、持镐挖矿、持镰刀采浆果翻倍", "done": false},
		{"text": "④ 制作营火：按 C 制作「营火」(5木材+3石头，木材来自砍树)", "done": false},
		{"text": "⑤ 放置营火：按 B 进建造模式 → TAB 选营火 → E 放置", "done": false},
		{"text": "⑥ 烹饪食物：手持生肉靠近营火按 E 烤熟", "done": false},
		{"text": "⑦ 进食维生：饥饿按 F 进食；也可直接吃浆果/根茎", "done": false},
		{"text": "⑧ 挖地：制作铲子后，用铲子挖掘土堆得燧石+根茎（可升级背包扩容）", "done": false},
		{"text": "⑨ 狩猎：猎杀一只野生动物（狼会主动攻击，鹿会逃跑）；获取生肉与经验", "done": false},
		{"text": "⑩ 成长：按 L 打开技能面板，用经验解锁一个技能（生命/攻击/移速/背包/精神）", "done": false},
		{"text": "✓ 教程完成！留意饥饿/生命/精神与昼夜，继续探索与成长（J 隐藏本面板 / L 技能）", "done": false},
	]

func _emit_current() -> void:
	if _all_done:
		task_changed.emit(_idx, _steps[_idx]["text"], true)
		return
	# 找到第一个未完成的步骤作为当前目标
	var cur := -1
	for i in _steps.size() - 1:
		if not _steps[i]["done"]:
			cur = i
			break
	if cur == -1:
		cur = _steps.size() - 1
		_all_done = true
		_award_final()
	_idx = cur
	task_changed.emit(cur, _steps[cur]["text"], _all_done)

func _mark_done(text_sub: String) -> void:
	for s in _steps:
		if not s["done"] and text_sub in s["text"]:
			s["done"] = true
			EventBus.toast.emit("✓ 完成：" + s["text"])
			_award_step()
			_emit_current()
			return

# ---- 事件处理 ----
func _on_harvest(_src, drops) -> void:
	# 第一次采集（浆果/散落物）即完成「拾荒起步」
	if not _steps[0]["done"]:
		_steps[0]["done"] = true
		EventBus.toast.emit("✓ 完成：" + _steps[0]["text"])
		_award_step()
	# 砍树（掉木材）完成「进阶采集」
	if typeof(drops) == TYPE_DICTIONARY and drops.has("log"):
		_mark_done("③")
	# 挖地（掉根茎）完成「挖地」
	if typeof(drops) == TYPE_DICTIONARY and drops.has("root"):
		_mark_done("⑧")

func _on_craft(id: String) -> void:
	# 制作任意工具 → 完成「制作工具」
	if id in ["axe", "pickaxe", "sickle", "shovel"]:
		_mark_done("②")
	# 制作营火 → 完成「制作营火」
	if id == "campfire":
		_mark_done("④")

func _on_placed(id: String, _at) -> void:
	if id == "campfire":
		_mark_done("⑤")

func _on_cooked(_item: String) -> void:
	_mark_done("⑥")

func _on_eaten(_item: String) -> void:
	_mark_done("⑦")

func _on_creature_died(_c, _d) -> void:
	_mark_done("⑨")

func _on_skill(_id: String) -> void:
	_mark_done("⑩")

# ---- 任务完成奖励 ----
## 每完成一个引导步骤：女主好感 +3，并获赠一份食物（熟肉）。
func _award_step() -> void:
	RelationshipManager.add_affection(3.0, "完成任务")
	Inventory.add_item("cookedmeat", 1)
	EventBus.toast.emit("任务奖励：熟肉×1，女主好感 +3")

## 全部引导步骤完成（教程通关）：额外大礼包 + 女主好感提升至 80。
func _award_final() -> void:
	if _final_awarded:
		return
	_final_awarded = true
	RelationshipManager.raise_affection_to(80.0, "教程通关")
	Inventory.add_item("cookedmeat", 3)
	Inventory.add_item("cooked_fish", 2)
	Inventory.add_item("berry", 5)
	EventBus.toast.emit("教程通关奖励：熟肉×3 烤鱼×2 浆果×5，女主好感提升至 80！")
