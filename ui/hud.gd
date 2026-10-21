extends Control
## HUD（Layer 6）：只读 EventBus + 少量输入，不主动查任何块。
## 三值条 + 背包文本 + 交互提示；新增：制作菜单(C/数字键)、建造模式横幅、进食提示、toast。

const HotbarButtonCls = preload("res://ui/hotbar_button.gd")
const QuickSlotCls = preload("res://ui/quick_slot.gd")
## 菜单面板内边距（面板背景与内容之间留白，避免文字贴边）
const PANEL_PAD := 12.0

var hunger_bar: ProgressBar
var health_bar: ProgressBar
var sanity_bar: ProgressBar
var inv_label: Label
var prompt_panel: PanelContainer
var prompt_label: Label
var _prompt_text := ""

# NPC 交互菜单（交谈 / 送礼）：按 E 弹出
var npc_menu: PanelContainer
var npc_menu_title: Label
var npc_menu_list: VBoxContainer
var _npc_target: Node = null
# 送礼面板：列出背包 + 营地仓库物品，点击「赠送」
var gift_panel: PanelContainer
var gift_label: Label
var gift_list: VBoxContainer
var gift_hint: Label

var craft_panel: Panel
var craft_list: VBoxContainer
var craft_labels: Array = []          # 与 Crafting.recipes 同序
var build_label: Label
var eat_hint: Label
var toast_label: Label
var _toast_timer: float = 0.0
var _craft_built := false

var task_panel: Panel
var task_label: Label
var _task_visible := true

var backpack_panel: Panel
var backpack_grid: GridContainer
var backpack_vbox: VBoxContainer
var _bp_cells: Array = []

# 昼夜时钟
var clock_label: Label
# 经验 / 等级
var xp_bar: ProgressBar
var xp_label: Label
var level_label: Label
# 技能面板（L 键）
var skill_panel: Panel
var skill_list: VBoxContainer
var skill_labels: Array = []
var _skill_built := false
# 伤害浮字层
var popup_layer: CanvasLayer
var popup_container: Control
var _popups: Array = []

# 底部快捷栏 + 建造选择菜单
var hotbar: HBoxContainer
var _hb_buttons: Dictionary = {}   # kind -> HotbarButton
var quick_slots: Array = ["", ""]  # 两个快捷栏存放的物品 id（与背包共享同一堆叠）
var _qs_nodes: Array = []          # 对应的 QuickSlot 控件
var build_menu: Panel
var build_menu_list: VBoxContainer
var _bm_built := false

# 烹饪菜单（靠近营火等触发，数字键烹饪 / ESC 关闭）
var cook_panel: PanelContainer
var cook_list: VBoxContainer
var cook_title: Label
var cook_progress: ProgressBar
var cook_hint: Label
var _cook_built := false
var _cooking_raw: String = ""
var _cook_timer: Timer
var _cook_recipes: Array = []   # 当前可烹饪列表：[{raw_id, raw_name, cooked_id, cooked_name, time, have}]
var _stats_vbox: VBoxContainer = null   # 左上状态条容器（用于把 toast 摆到它下方，避免遮挡）

# 好感 / 心情条（女主，见 RelationshipManager）
var aff_bar: ProgressBar
var mood_bar: ProgressBar
# 伙伴计数标签
var partner_label: Label
var _partner_t := 0.0

# 伙伴指令面板（T 全员广播 / E 走近单人）
var party_panel: PanelContainer
var party_title: Label
var party_list: VBoxContainer
var _cmd_target: Node = null
var party_prompt_label: Label

# 营地仓库面板（柜子交互打开）
var camp_panel: Panel
var camp_list: VBoxContainer
var camp_label: Label
# 结局分支面板（巢穴通关打开）
var end_panel: Panel
var end_label: Label

# 任务树面板（U 键开关）
var mission_panel: Panel
var mission_label: Label
var _mission_visible := false

# 对话框（Dialogue 系统驱动，回车/空格/点击推进）
var dlg_panel: Panel
var dlg_name: Label
var dlg_text: Label
var dlg_hint: Label

# 负重条（底部偏左）
var weight_bar: ProgressBar
var weight_label: Label

# 装备快捷栏（底部居中）
var equip_bar: HBoxContainer
var _equip_cells: Array = []          # [{style, name, icon}]
# 商店面板
var shop_panel: Panel
var shop_gold: Label
var shop_buy_list: VBoxContainer
var shop_sell_list: VBoxContainer
var shop_buy_btn: Button
var shop_sell_btn: Button
var shop_tab: int = 0   # 0 买 1 卖
# 公告面板
var bulletin_panel: Panel
var bulletin_label: Label
var bulletin_scroll: ScrollContainer
# 成就面板
var ach_panel: Panel
var ach_label: Label
# 阶段标签（时钟旁）
var stage_label: Label

# 准星（屏幕正中心）：第三人称下交互射线从相机正前发射，准星给出明确瞄准点；
# 瞄准到可交互物时变金色高亮，帮助玩家定位拾取/交互目标。
var crosshair: Control

# GAME OVER 覆盖层（营地失守等终局失败）
var _game_over_layer: CanvasLayer = null
var _game_over_reason: Label = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 左上：需求条 + 背包 + 交互提示
	var vb := VBoxContainer.new()
	vb.position = Vector2(16, 16)
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	_stats_vbox = vb
	hunger_bar = _make_bar(vb, "饥饿", Color(0.95, 0.75, 0.2))
	health_bar = _make_bar(vb, "生命", Color(0.95, 0.25, 0.25))
	sanity_bar = _make_bar(vb, "精神", Color(0.55, 0.45, 0.95))
	aff_bar = _make_bar(vb, "好感", Color(1.0, 0.5, 0.7))
	mood_bar = _make_bar(vb, "心情", Color(0.5, 0.9, 1.0))
	aff_bar.max_value = 100.0
	aff_bar.value = 0.0
	mood_bar.max_value = 100.0
	mood_bar.value = 60.0

	inv_label = Label.new()
	inv_label.position = Vector2(16, 150)
	inv_label.add_theme_color_override("font_color", Color.WHITE)
	add_child(inv_label)

	# 交互提示：屏幕中下方「醒目横幅」（深色圆角底 + 金色描边 + 大字号），替代原先草地上的小黄字
	prompt_panel = PanelContainer.new()
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.05, 0.06, 0.10, 0.9)
	pstyle.set_corner_radius_all(10)
	pstyle.content_margin_left = 20.0
	pstyle.content_margin_right = 20.0
	pstyle.content_margin_top = 9.0
	pstyle.content_margin_bottom = 9.0
	pstyle.border_color = Color(1.0, 0.86, 0.34, 0.92)
	pstyle.set_border_width_all(2)
	prompt_panel.add_theme_stylebox_override("panel", pstyle)
	add_child(prompt_panel)
	prompt_label = Label.new()
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.72))
	prompt_label.add_theme_font_size_override("font_size", 20)
	prompt_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	prompt_label.add_theme_constant_override("shadow_offset_x", 1)
	prompt_label.add_theme_constant_override("shadow_offset_y", 1)
	prompt_panel.add_child(prompt_label)
	prompt_panel.visible = false

	# 右上：制作菜单
	craft_panel = Panel.new()
	craft_panel.position = Vector2(0, 16)
	craft_panel.visible = false
	add_child(craft_panel)
	var crstyle := StyleBoxFlat.new()
	crstyle.bg_color = Color(0.08, 0.1, 0.16, 0.94)
	crstyle.set_corner_radius_all(8)
	crstyle.set_border_width_all(1)
	crstyle.border_color = Color(0.95, 0.85, 0.55, 0.35)
	craft_panel.add_theme_stylebox_override("panel", crstyle)
	craft_list = VBoxContainer.new()
	craft_list.add_theme_constant_override("separation", 2)
	craft_list.size = Vector2(260, 0)
	craft_panel.add_child(craft_list)
	var title := Label.new()
	title.text = "制作 (C 开关 / 数字键制作)"
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	craft_list.add_child(title)
	# 等布局后把面板贴到右上角
	craft_panel.position = Vector2(get_viewport().size.x - 290, 16) if get_viewport() else Vector2(1100, 16)

	# 建造横幅：改为屏幕中上方居中（原写死「底部 -60」会压进热栏/物品栏被遮住）
	build_label = Label.new()
	build_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.7))
	build_label.add_theme_font_size_override("font_size", 18)
	build_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	build_label.custom_minimum_size = Vector2(640, 0)
	build_label.size = Vector2(640, 0)
	add_child(build_label)
	build_label.visible = false

	# 底部：进食提示
	eat_hint = Label.new()
	eat_hint.text = "F 进食   B 建造模式   C 制作菜单"
	eat_hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	eat_hint.position = Vector2(16, 640)
	add_child(eat_hint)

	# toast
	toast_label = Label.new()
	toast_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	toast_label.add_theme_font_size_override("font_size", 20)
	toast_label.position = Vector2(16, 110)
	add_child(toast_label)
	toast_label.visible = false

	# 顶部居中：任务指引面板
	task_panel = Panel.new()
	task_panel.position = Vector2((get_viewport().size.x - 560) * 0.5 if get_viewport() else 320, 12)
	add_child(task_panel)
	task_label = Label.new()
	task_label.position = Vector2(12, 8)
	task_label.custom_minimum_size = Vector2(536, 0)
	task_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	task_label.add_theme_font_size_override("font_size", 15)
	task_panel.add_child(task_label)
	# 任务指引改为「无背景纯文字」，去掉之前贴在最下居中时那块空白黑框
	var tstyle := StyleBoxFlat.new()
	tstyle.bg_color = Color(0, 0, 0, 0)
	tstyle.set_corner_radius_all(8)
	task_panel.add_theme_stylebox_override("panel", tstyle)
	task_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	TaskGuide.task_changed.connect(_on_task)

	# 背包网格面板（I 键开关）
	backpack_panel = Panel.new()
	backpack_panel.position = Vector2(16, 230)
	backpack_panel.visible = false
	add_child(backpack_panel)
	var bvbox := VBoxContainer.new()
	bvbox.position = Vector2(10, 8)
	backpack_panel.add_child(bvbox)
	backpack_vbox = bvbox
	var btitle := Label.new()
	btitle.text = "背包 (I 开关)"
	btitle.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	bvbox.add_child(btitle)
	backpack_grid = GridContainer.new()
	backpack_grid.columns = 4
	backpack_grid.add_theme_constant_override("hseparation", 6)
	backpack_grid.add_theme_constant_override("vseparation", 6)
	bvbox.add_child(backpack_grid)
	var bstyle := StyleBoxFlat.new()
	bstyle.bg_color = Color(0.08, 0.1, 0.16, 0.8)
	bstyle.set_corner_radius_all(8)
	backpack_panel.add_theme_stylebox_override("panel", bstyle)

	# 时钟（右上角，紧邻制作菜单上方）
	clock_label = Label.new()
	clock_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	clock_label.add_theme_font_size_override("font_size", 16)
	clock_label.position = Vector2(get_viewport().size.x - 160 if get_viewport() else 1100, 16)
	add_child(clock_label)

	# 经验条 + 等级（底部偏左）
	var xv := VBoxContainer.new()
	xv.position = Vector2(16, 590)
	xv.add_theme_constant_override("separation", 2)
	add_child(xv)
	level_label = Label.new()
	level_label.text = "Lv.1"
	level_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
	xv.add_child(level_label)
	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(240, 14)
	xp_bar.max_value = 100.0
	xp_bar.value = 0.0
	xp_bar.modulate = Color(0.4, 0.85, 1.0)
	xv.add_child(xp_bar)
	xp_label = Label.new()
	xp_label.text = "经验 0 / 0 (可花 0)"
	xp_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	xp_label.add_theme_font_size_override("font_size", 12)
	xv.add_child(xp_label)

	# 负重条（底部偏左，XP 下方）
	var wv := VBoxContainer.new()
	wv.position = Vector2(16, 668)
	wv.add_theme_constant_override("separation", 2)
	add_child(wv)
	weight_label = Label.new()
	weight_label.text = "负重 0.0 / 0.0 kg"
	weight_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	weight_label.add_theme_font_size_override("font_size", 12)
	wv.add_child(weight_label)
	weight_bar = ProgressBar.new()
	weight_bar.custom_minimum_size = Vector2(240, 12)
	weight_bar.max_value = 1.0
	weight_bar.value = 0.0
	weight_bar.modulate = Color(0.6, 0.9, 0.5)
	wv.add_child(weight_bar)

	# 技能面板（L 键开关），样式同制作菜单
	skill_panel = Panel.new()
	skill_panel.position = Vector2(get_viewport().size.x - 290 if get_viewport() else 1100, 60)
	skill_panel.visible = false
	add_child(skill_panel)
	skill_list = VBoxContainer.new()
	skill_list.add_theme_constant_override("separation", 2)
	skill_list.size = Vector2(270, 0)
	skill_panel.add_child(skill_list)
	var stitle := Label.new()
	stitle.text = "技能 (L 开关 / 数字键解锁)"
	stitle.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	skill_list.add_child(stitle)
	var sstyle := StyleBoxFlat.new()
	sstyle.bg_color = Color(0.08, 0.1, 0.16, 0.94)
	sstyle.set_corner_radius_all(8)
	sstyle.set_border_width_all(1)
	sstyle.border_color = Color(0.55, 0.7, 0.95, 0.35)
	skill_panel.add_theme_stylebox_override("panel", sstyle)

	# 伤害浮字层
	popup_layer = CanvasLayer.new()
	add_child(popup_layer)
	popup_container = Control.new()
	popup_layer.add_child(popup_container)

	# 烹饪菜单（顶部居中，默认隐藏；数字键烹饪 / ESC 关闭，鼠标保持捕获不影响操作）
	# ⚠️ 必须用 PanelContainer + 单个 VBox 纵向排布：普通 Panel 的子节点默认全在 (0,0)，
	#    标题 / 列表 / 进度条会互相叠住，导致中间那团字完全看不清。
	cook_panel = PanelContainer.new()
	cook_panel.visible = false
	cook_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	cook_panel.custom_minimum_size = Vector2(360, 0)
	add_child(cook_panel)
	var cstyle := StyleBoxFlat.new()
	cstyle.bg_color = Color(0.08, 0.1, 0.16, 0.94)
	cstyle.set_corner_radius_all(8)
	cstyle.set_border_width_all(1)
	cstyle.border_color = Color(0.95, 0.85, 0.55, 0.35)
	cstyle.content_margin_left = 14.0
	cstyle.content_margin_right = 14.0
	cstyle.content_margin_top = 10.0
	cstyle.content_margin_bottom = 12.0
	cook_panel.add_theme_stylebox_override("panel", cstyle)
	var cook_vbox := VBoxContainer.new()
	cook_vbox.add_theme_constant_override("separation", 6)
	cook_vbox.custom_minimum_size = Vector2(332, 0)
	cook_panel.add_child(cook_vbox)
	cook_title = Label.new()
	cook_title.text = "烹饪 (数字键烹饪 / ESC 关闭)"
	cook_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	cook_vbox.add_child(cook_title)
	cook_list = VBoxContainer.new()
	cook_list.add_theme_constant_override("separation", 4)
	cook_vbox.add_child(cook_list)
	cook_progress = ProgressBar.new()
	cook_progress.custom_minimum_size = Vector2(332, 14)
	cook_progress.max_value = 100.0
	cook_progress.value = 0.0
	cook_progress.visible = false
	cook_progress.modulate = Color(1.0, 0.7, 0.3)
	cook_vbox.add_child(cook_progress)
	cook_hint = Label.new()
	cook_hint.text = "（没有可烹饪的食材）"
	cook_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	cook_vbox.add_child(cook_hint)
	_cook_timer = Timer.new()
	_cook_timer.one_shot = true
	_cook_timer.timeout.connect(_on_cook_done)
	add_child(_cook_timer)
	EventBus.cooking_menu_requested.connect(_open_cooking)

	# 任务树面板（底部居中，默认隐藏，U 键开关）
	mission_panel = Panel.new()
	mission_panel.visible = false
	mission_panel.position = Vector2((get_viewport().size.x - 420) * 0.5 if get_viewport() else 300, 500)
	mission_panel.custom_minimum_size = Vector2(420, 0)
	add_child(mission_panel)
	var mstyle := StyleBoxFlat.new()
	mstyle.bg_color = Color(0.1, 0.12, 0.2, 0.82)
	mstyle.set_corner_radius_all(8)
	mission_panel.add_theme_stylebox_override("panel", mstyle)
	mission_label = Label.new()
	mission_label.position = Vector2(10, 8)
	mission_label.size = Vector2(400, 0)
	mission_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	mission_label.add_theme_font_size_override("font_size", 14)
	mission_panel.add_child(mission_label)
	Missions.missions_changed.connect(_refresh_missions)
	Missions.mission_completed.connect(_on_mission_done)

	# 对话框（底部居中，默认隐藏；回车/空格/点击推进，对话时释放鼠标）
	dlg_panel = Panel.new()
	dlg_panel.visible = false
	dlg_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	dlg_panel.position = Vector2((get_viewport().size.x - 600) * 0.5 if get_viewport() else 100, (get_viewport().size.y - 200) if get_viewport() else 520)
	dlg_panel.custom_minimum_size = Vector2(600, 0)
	add_child(dlg_panel)
	var dstyle := StyleBoxFlat.new()
	dstyle.bg_color = Color(0.06, 0.08, 0.14, 0.92)
	dstyle.set_corner_radius_all(10)
	dlg_panel.add_theme_stylebox_override("panel", dstyle)
	dlg_name = Label.new()
	dlg_name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	dlg_name.add_theme_font_size_override("font_size", 16)
	dlg_panel.add_child(dlg_name)
	dlg_text = Label.new()
	dlg_text.position = Vector2(0, 30)
	dlg_text.size = Vector2(580, 0)
	dlg_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dlg_text.add_theme_color_override("font_color", Color.WHITE)
	dlg_text.add_theme_font_size_override("font_size", 15)
	dlg_panel.add_child(dlg_text)
	dlg_hint = Label.new()
	dlg_hint.text = "（回车 / 空格 / 点击 继续）"
	dlg_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	dlg_hint.add_theme_font_size_override("font_size", 12)
	dlg_panel.add_child(dlg_hint)
	Dialogue.dialogue_started.connect(_on_dlg_start)
	Dialogue.dialogue_line.connect(_on_dlg_line)
	Dialogue.dialogue_ended.connect(_on_dlg_end)
	dlg_panel.gui_input.connect(_on_dlg_click)

	EventBus.needs_changed.connect(_on_needs)
	EventBus.inventory_changed.connect(_refresh_inv)
	EventBus.interactable_changed.connect(_on_prompt)
	EventBus.toast.connect(_on_toast)
	EventBus.xp_changed.connect(_on_xp)
	EventBus.leveled_up.connect(_on_level)
	EventBus.damage_popup.connect(_on_damage_popup)
	EventBus.skill_unlocked.connect(_on_skill_unlocked)
	Inventory.weight_changed.connect(_on_weight)
	Inventory.overburdened_changed.connect(_on_overburdened)

	# —— 新系统 UI：装备快捷栏 / 商店 / 公告 / 成就 / 阶段 ——
	_build_equip_bar()
	_build_shop()
	_build_bulletin()
	_build_achievements()
	_build_stage_label()
	Equipment.hotbar_changed.connect(_on_hotbar_changed)
	Equipment.equipped_changed.connect(_on_equipped_changed)
	Economy.gold_changed.connect(_on_gold_changed)
	Bulletin.bulletin_changed.connect(_refresh_bulletin)
	Achievements.achievement_unlocked.connect(_on_ach_unlocked)
	EventBus.stage_changed.connect(_on_stage)
	EventBus.shop_requested.connect(_on_shop_opened)
	EventBus.bulletin_opened.connect(_on_bulletin_opened)

	# —— 新系统 UI：好感/心情 + 伙伴 + 营地仓库 + 结局 ——
	_build_partner_label()
	_build_camp_storage()
	_build_ending()
	EventBus.affection_changed.connect(_on_affection)
	EventBus.mood_changed.connect(_on_mood)
	EventBus.load_requested.connect(func(_d): _sync_rel_bars())
	_sync_rel_bars()
	EventBus.camp_storage_requested.connect(_open_camp_storage)
	CampStorage.storage_changed.connect(_refresh_camp_storage)
	EventBus.nest_cleared.connect(_on_nest_cleared)
	EventBus.game_over.connect(_on_game_over)

	# —— NPC 交互菜单 + 送礼面板 ——
	_build_npc_menu()
	_build_gift_panel()
	EventBus.npc_menu_requested.connect(_on_npc_menu_requested)
	# —— 伙伴指令面板（T 全员 / E 单人）——
	_build_party_panel()
	_build_party_prompt()

	_refresh_inv()
	_on_weight(Inventory.total_weight, Inventory.max_weight)
	_on_time()

	# 底部快捷栏（带图标的快捷键：背包/建造/任务/技能/制作）
	_build_hotbar()
	_build_build_menu()
	EventBus.build_menu_requested.connect(_set_build_menu)

	# 屏幕中心准星（游玩时显示，帮助第三人称定位交互/拾取目标）
	_build_crosshair()
	# GAME OVER 覆盖层（营地失守等终局失败）
	_build_game_over()

func _make_bar(parent: Control, label_text: String, col: Color) -> ProgressBar:
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var lab := Label.new()
	lab.text = label_text
	lab.custom_minimum_size = Vector2(44, 0)
	lab.add_theme_color_override("font_color", Color.WHITE)
	hb.add_child(lab)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(200, 18)
	bar.max_value = 100.0
	bar.value = 100.0
	bar.modulate = col
	hb.add_child(bar)
	return bar

func _on_needs(stat: String, v: float) -> void:
	if stat == "hunger":
		hunger_bar.value = v * 100.0
	elif stat == "health":
		health_bar.value = v * 100.0
	elif stat == "sanity":
		sanity_bar.value = v * 100.0

func _on_prompt(p: String) -> void:
	_prompt_text = p

func _refresh_inv() -> void:
	_refresh_backpack()
	_refresh_craft_list()

## 刷新背包格子面板 + 顶部负重摘要。格子数与 Inventory.max_slots 同步（扩容后自动加格）。
func _refresh_backpack() -> void:
	if backpack_panel == null:
		return
	var n: int = Inventory.max_slots
	if _bp_cells.size() != n:
		for c in backpack_grid.get_children():
			c.queue_free()
		_bp_cells.clear()
		for i in n:
			var cell := Panel.new()
			var cstyle := StyleBoxFlat.new()
			cstyle.bg_color = Color(0.12, 0.14, 0.2, 0.85)
			cstyle.set_corner_radius_all(6)
			cell.add_theme_stylebox_override("panel", cstyle)
			cell.custom_minimum_size = Vector2(112, 96)
			var vb := VBoxContainer.new()
			vb.add_theme_constant_override("separation", 2)
			vb.alignment = BoxContainer.ALIGNMENT_CENTER
			cell.add_child(vb)
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(56, 56)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			vb.add_child(icon)
			var nm := Label.new()
			nm.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
			nm.add_theme_font_size_override("font_size", 12)
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vb.add_child(nm)
			var cnt := Label.new()
			cnt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
			cnt.add_theme_font_size_override("font_size", 13)
			cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(cnt)
			backpack_grid.add_child(cell)
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			cell.tooltip_text = "左键使用 · 右键放入快捷栏"
			cell.gui_input.connect(_on_bp_cell_input.bind(i))
			# 子控件（VBox/图标/文字）默认 mouse_filter=STOP，会吃掉点击导致 Panel 的 gui_input 永不触发
			# → 全部设为 IGNORE，让点击落回格子 Panel 上（「背包物品点不动」的真因之一）。
			_set_mouse_ignore_recursive(cell)
			_bp_cells.append({"icon": icon, "name": nm, "count": cnt})
	var used := 0
	for i in n:
		var s = Inventory.slots[i] if i < Inventory.slots.size() else null
		var cell: Dictionary = _bp_cells[i]
		if s != null:
			var it: ItemResource = ItemDatabase.get_item(s.id)
			var nm: String = it.display_name if it != null else s.id
			cell["name"].text = nm
			cell["count"].text = "×%d" % s.count
			if it != null and it.icon != null:
				cell["icon"].texture = it.icon
				cell["icon"].visible = true
			else:
				cell["icon"].texture = ItemIcons.icon_for(s.id)
				cell["icon"].visible = true
			used += 1
		else:
			cell["name"].text = ""
			cell["count"].text = ""
			cell["icon"].visible = false
	inv_label.text = "负重 %.1fkg  |  %d/%d 格  |  按 I 打开背包" % [Inventory.total_weight, used, Inventory.max_slots]
	_refresh_quick_slots()

## 把某控件的所有子孙控件设为 MOUSE_FILTER_IGNORE（自身不动），让点击穿透到宿主控件。
func _set_mouse_ignore_recursive(root: Node) -> void:
	for c in root.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_mouse_ignore_recursive(c)

## 背包格子点击：左键使用其中物品（消耗品→进食，其余给出提示）；右键放入快捷栏。
func _on_bp_cell_input(ev: InputEvent, idx: int) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if idx < 0 or idx >= Inventory.slots.size():
			return
		var s = Inventory.slots[idx]
		if s == null or not s.has("id"):
			return
		if ev.button_index == MOUSE_BUTTON_LEFT:
			_use_inv_item(str(s["id"]))
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			_assign_to_quickslot(str(s["id"]))

## 使用背包里的一件物品。
func _use_inv_item(id: String) -> void:
	var it: ItemResource = ItemDatabase.get_item(id)
	if it == null:
		return
	if it.category == ItemResource.Category.CONSUMABLE:
		if GameManager.player != null and GameManager.player.has_method("eat_item"):
			if GameManager.player.eat_item(id):
				return
			EventBus.toast.emit("背包里没有 %s 了" % it.display_name)
			return
		EventBus.toast.emit("无法使用 %s" % it.display_name)
		return
	EventBus.toast.emit("%s 不能在背包里直接使用（可在对应配方/建造处使用）" % it.display_name)

func _on_toast(text: String) -> void:
	toast_label.text = text
	toast_label.visible = true
	_toast_timer = 2.5

func _on_task(_idx: int, text: String, all_done: bool) -> void:
	task_label.text = "目标：" + text
	task_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if all_done else Color(1.0, 0.95, 0.7))

# =========================================================
# 昼夜 / 经验 / 技能 / 伤害浮字
# =========================================================
func _on_time() -> void:
	if clock_label == null:
		return
	var s := "白昼"
	if DayNightCycle.is_nighttime():
		s = "夜晚"
	clock_label.text = "%s  %s" % [DayNightCycle.get_time_string(), s]

func _on_xp(total: int, available: int, level: int, xp_into: int, xp_needed: int) -> void:
	level_label.text = "Lv.%d" % level
	var pct := 0.0
	if xp_needed > 0:
		pct = clamp(float(xp_into) / float(xp_needed), 0.0, 1.0) * 100.0
	xp_bar.value = pct
	xp_label.text = "经验 %d/%d (可花 %d)" % [xp_into, xp_needed, available]
	if skill_panel != null and skill_panel.visible:
		_refresh_skill_list()

func _on_level(level: int) -> void:
	EventBus.toast.emit("升级！等级 %d" % level)

func _on_skill_unlocked(_id: String) -> void:
	_refresh_skill_list()

# =========================================================
# 负重
# =========================================================
func _on_weight(cur: float, mx: float) -> void:
	if weight_bar == null:
		return
	var ratio := (cur / mx) if mx > 0.0 else 0.0
	weight_bar.value = clampf(ratio, 0.0, 1.0)
	weight_label.text = "负重 %.1f / %.1f kg" % [cur, mx]
	if ratio > 1.0:
		weight_bar.modulate = Color(1.0, 0.3, 0.3)
	elif ratio > 0.8:
		weight_bar.modulate = Color(1.0, 0.8, 0.3)
	else:
		weight_bar.modulate = Color(0.6, 0.9, 0.5)

func _on_overburdened(b: bool) -> void:
	if b:
		EventBus.toast.emit("背包超重！移动变慢")

func _toggle_skill() -> void:
	skill_panel.visible = not skill_panel.visible
	if skill_panel.visible and not _skill_built:
		_build_skill_list()
	_center_panel(skill_panel)
	if skill_panel.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_restore_mouse()

func _build_skill_list() -> void:
	_skill_built = true
	for c in skill_list.get_children():
		if c != skill_list.get_child(0):
			c.queue_free()
	skill_labels.clear()
	var sk: Array = Skills.get_list()
	for i in sk.size():
		var s: Dictionary = sk[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(270, 34)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 14)
		# 点击即解锁（鼠标也能用，不再只靠数字键）
		btn.pressed.connect(_on_skill_row_pressed.bind(s["id"]))
		skill_list.add_child(btn)
		skill_labels.append(btn)
	_refresh_skill_list()

## 鼠标点击技能行：尝试解锁；成功/失败都会有 toast 反馈。
func _on_skill_row_pressed(id: String) -> void:
	Skills.try_unlock(id)
	_refresh_skill_list()

func _refresh_skill_list() -> void:
	if not _skill_built:
		return
	var sk: Array = Skills.get_list()
	for i in skill_labels.size():
		if i >= sk.size():
			break
		var s: Dictionary = sk[i]
		var ok := Skills.can_unlock(s["id"])
		var status: String = "已解锁" if s["unlocked"] else ("[可解锁]" if ok else "[经验不足]")
		skill_labels[i].text = "[%d] %s (%d经验) — %s" % [i + 1, s["name"], int(s["cost"]), status]
		skill_labels[i].add_theme_color_override("font_color",
			Color(0.5, 1.0, 0.5) if s["unlocked"] else (Color(1.0, 0.95, 0.6) if ok else Color(0.6, 0.6, 0.6)))
		# 已解锁的行禁用按钮（点不动），未解锁保持可点
		skill_labels[i].disabled = bool(s["unlocked"])

func _on_damage_popup(pos: Vector3, amount: float, kind: String) -> void:
	if popup_container == null:
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	var screen := Vector2.ZERO
	if cam != null:
		screen = cam.unproject_position(pos)
	else:
		screen = Vector2(get_viewport().size.x * 0.5, get_viewport().size.y * 0.4)
	var lab := Label.new()
	if kind == "heal":
		lab.text = "+%d" % int(amount)
		lab.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	else:
		lab.text = "-%d" % int(amount)
		lab.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4) if kind == "enemy" else Color(1.0, 0.3, 0.3))
	lab.add_theme_font_size_override("font_size", 22)
	lab.position = screen
	popup_container.add_child(lab)
	_popups.append({"label": lab, "life": 0.9, "vy": -40.0})

# =========================================================
# 制作菜单
# =========================================================
func _toggle_craft() -> void:
	craft_panel.visible = not craft_panel.visible
	if craft_panel.visible and not _craft_built:
		_build_craft_list()
	_center_panel(craft_panel)
	# 与背包一致：菜单打开时释放鼠标（避免与其它弹窗叠加后鼠标模式错乱），关闭时统一恢复。
	if craft_panel.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_restore_mouse()

func _build_craft_list() -> void:
	_craft_built = true
	# 清掉除 title 外的条目
	for c in craft_list.get_children():
		if c != craft_list.get_child(0):
			c.queue_free()
	craft_labels.clear()
	var recipes: Array = Crafting.recipes
	if recipes.is_empty():
		var empty := Label.new()
		empty.text = "(暂无配方)"
		craft_list.add_child(empty)
		return
	for i in recipes.size():
		var r: Dictionary = recipes[i]
		var lab := Label.new()
		lab.add_theme_color_override("font_color", Color.WHITE)
		craft_list.add_child(lab)
		craft_labels.append(lab)
	_refresh_craft_list()

func _refresh_craft_list() -> void:
	if not _craft_built:
		return
	var recipes: Array = Crafting.recipes
	for i in craft_labels.size():
		if i >= recipes.size():
			break
		var r: Dictionary = recipes[i]
		var ok := Crafting.can_craft(r["id"])
		var txt := "[%d] %s" % [i + 1, Crafting.recipe_text(r["id"])]
		craft_labels[i].text = txt
		craft_labels[i].add_theme_color_override("font_color", Color(0.5, 1.0, 0.5) if ok else Color(0.6, 0.6, 0.6))

# =========================================================
# 烹饪菜单
# =========================================================
func _open_cooking() -> void:
	EventBus.cooking_menu_open = true
	cook_panel.visible = true
	_build_cook_list()
	_layout_cook_panel()

## 把烹饪面板按内容自适应高度，水平居中、顶部留 110px，避免盖住准星与角色。
## 列表增删后需延迟一帧再调（容器要等子节点排序完才有正确最小尺寸）。
func _layout_cook_panel() -> void:
	if cook_panel == null or not cook_panel.visible:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var need: Vector2 = cook_panel.get_combined_minimum_size()
	need.x = maxf(need.x, 360.0)
	cook_panel.size = need
	cook_panel.position = Vector2((vp.size.x - need.x) * 0.5, 110.0)

func _close_cooking() -> void:
	cook_panel.visible = false
	EventBus.cooking_menu_open = false
	_cooking_raw = ""
	_cook_timer.stop()
	cook_progress.visible = false

func _build_cook_list() -> void:
	_cook_built = true
	for c in cook_list.get_children():
		c.queue_free()
	_cook_recipes.clear()
	for id in Inventory.items:
		var it: ItemResource = ItemDatabase.get_item(id)
		if it != null and it.cooked_result != "" and Inventory.count(id) > 0:
			var cit: ItemResource = ItemDatabase.get_item(it.cooked_result)
			_cook_recipes.append({
				"raw_id": id,
				"raw_name": it.display_name,
				"cooked_id": it.cooked_result,
				"cooked_name": (cit.display_name if cit != null else it.cooked_result),
				"time": it.cook_time,
				"have": Inventory.count(id)
			})
	if _cook_recipes.is_empty():
		cook_hint.text = "（没有可烹饪的食材）"
		cook_hint.visible = true
		return
	cook_hint.visible = false
	for i in _cook_recipes.size():
		var r: Dictionary = _cook_recipes[i]
		var lab := Label.new()
		lab.add_theme_color_override("font_color", Color.WHITE)
		lab.text = "[%d] 烤 %s ×%d → %s  (%.1f秒)" % [i + 1, r["raw_name"], int(r["have"]), r["cooked_name"], float(r["time"])]
		cook_list.add_child(lab)

func _start_cook(idx: int) -> void:
	if _cooking_raw != "":
		EventBus.toast.emit("正在烹饪中…")
		return
	if idx < 0 or idx >= _cook_recipes.size():
		return
	var r: Dictionary = _cook_recipes[idx]
	if not Inventory.has(r["raw_id"], 1):
		_build_cook_list()
		return
	Inventory.consume(r["raw_id"], 1)
	_cooking_raw = r["raw_id"]
	_cook_timer.wait_time = float(r["time"])
	_cook_timer.start()
	cook_progress.visible = true
	cook_progress.value = 0.0
	cook_hint.visible = false
	_build_cook_list()
	call_deferred("_layout_cook_panel")

func _on_cook_done() -> void:
	var raw_id: String = _cooking_raw
	_cooking_raw = ""
	cook_progress.visible = false
	if raw_id == "":
		return
	var it: ItemResource = ItemDatabase.get_item(raw_id)
	if it == null or it.cooked_result == "":
		return
	var cooked: String = it.cooked_result
	Inventory.add_item(cooked, 1)
	EventBus.food_cooked.emit(cooked)
	var nm: String = cooked
	var cit: ItemResource = ItemDatabase.get_item(cooked)
	if cit != null:
		nm = cit.display_name
	EventBus.toast.emit("烤好了：%s" % nm)
	_build_cook_list()
	call_deferred("_layout_cook_panel")

# =========================================================
# 任务树面板
# =========================================================
func _toggle_missions() -> void:
	_mission_visible = not _mission_visible
	mission_panel.visible = _mission_visible
	if _mission_visible:
		_refresh_missions()
		_center_panel(mission_panel)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_restore_mouse()

func _item_name(id: String) -> String:
	var it: ItemResource = ItemDatabase.get_item(id)
	return it.display_name if it != null else id

func _refresh_missions() -> void:
	if mission_label == null:
		return
	var active: Array = Missions.get_active_list()
	var lines: Array = []
	if active.is_empty():
		lines.append("（暂无可接任务）")
	else:
		for m in active:
			var objs: Array = m["objs"]
			var prog: Array = m["prog"]
			var parts: Array = []
			for i in objs.size():
				var o: Dictionary = objs[i]
				var cur: int = int(prog[i]) if i < prog.size() else 0
				if o["type"] == "collect":
					parts.append("%s %d/%d" % [_item_name(o["item"]), mini(cur, int(o["amount"])), int(o["amount"])])
				elif o["type"] == "kill":
					parts.append("击杀 %d/%d" % [mini(cur, int(o["amount"])), int(o["amount"])])
				else:
					parts.append("%s %s" % [_item_name(o["item"]), "✓" if cur >= 1 else "…"])
			lines.append("▪ [%s] %s：%s" % [m["cat"], m["name"], "、".join(parts)])
	mission_label.text = "任务树 (U 开关)\n" + "\n".join(lines)

func _on_mission_done(key: String, xp: int) -> void:
	var d: Dictionary = Missions.get_mission_def(key)
	var nm: String = d.get("name", key) if not d.is_empty() else key
	EventBus.toast.emit("任务完成：%s (+%d 经验)" % [nm, xp])

# =========================================================
# 对话框
# =========================================================
func _on_dlg_start(npc: String, lines: Array, _opts: Array) -> void:
	dlg_name.text = npc
	dlg_text.text = str(lines[0]) if lines.size() > 0 else ""
	dlg_panel.visible = true

func _on_dlg_line(npc: String, text: String) -> void:
	dlg_name.text = npc
	dlg_text.text = text

func _on_dlg_end() -> void:
	dlg_panel.visible = false

func _on_dlg_click(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		Dialogue.advance()

# =========================================================
# 装备快捷栏
# =========================================================
func _build_equip_bar() -> void:
	equip_bar = HBoxContainer.new()
	equip_bar.add_theme_constant_override("separation", 6)
	equip_bar.anchor_left = 0.5
	equip_bar.anchor_right = 0.5
	equip_bar.position = Vector2(-200, 700)
	add_child(equip_bar)
	_refresh_equip_bar()

func _refresh_equip_bar() -> void:
	if equip_bar == null:
		return
	var hb: Array = Equipment.hotbar
	if _equip_cells.size() != hb.size():
		for c in equip_bar.get_children():
			c.queue_free()
		_equip_cells.clear()
		for i in hb.size():
			var cell := Panel.new()
			var st := StyleBoxFlat.new()
			st.bg_color = Color(0.1, 0.12, 0.18, 0.85)
			st.set_corner_radius_all(6)
			cell.add_theme_stylebox_override("panel", st)
			cell.custom_minimum_size = Vector2(92, 86)
			var v := VBoxContainer.new()
			v.add_theme_constant_override("separation", 2)
			v.alignment = BoxContainer.ALIGNMENT_CENTER
			cell.add_child(v)
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(44, 44)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			v.add_child(icon)
			var key := Label.new()
			key.text = "[%d]" % (i + 1)
			key.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
			key.add_theme_font_size_override("font_size", 12)
			key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(key)
			var nm := Label.new()
			nm.add_theme_color_override("font_color", Color.WHITE)
			nm.add_theme_font_size_override("font_size", 13)
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(nm)
			equip_bar.add_child(cell)
			_equip_cells.append({"style": st, "name": nm, "icon": icon})
	for i in _equip_cells.size():
		var cell: Dictionary = _equip_cells[i]
		var id: String = hb[i] if i < hb.size() else ""
		var it: ItemResource = ItemDatabase.get_item(id)
		cell["name"].text = it.display_name if it != null else id
		if it != null and it.icon != null:
			cell["icon"].texture = it.icon
			cell["icon"].visible = true
		else:
			cell["icon"].visible = false
		var is_active := (i == Equipment.equipped_index)
		cell["style"].border_color = Color(1.0, 0.85, 0.3) if is_active else Color(0, 0, 0, 0)
		cell["style"].set_border_width_all(2 if is_active else 0)

func _on_hotbar_changed(_h: Array) -> void:
	_refresh_equip_bar()

func _on_equipped_changed(_id: String, _idx: int) -> void:
	_refresh_equip_bar()

# =========================================================
# 商店
# =========================================================
func _build_shop() -> void:
	shop_panel = Panel.new()
	shop_panel.visible = false
	shop_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	shop_panel.position = Vector2((get_viewport().size.x - 420) * 0.5 if get_viewport() else 300, 90)
	shop_panel.custom_minimum_size = Vector2(420, 470)
	add_child(shop_panel)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.1, 0.16, 0.95)
	st.set_corner_radius_all(10)
	shop_panel.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.position = Vector2(12, 10)
	v.add_theme_constant_override("separation", 6)
	shop_panel.add_child(v)
	shop_gold = Label.new()
	shop_gold.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	shop_gold.add_theme_font_size_override("font_size", 18)
	v.add_child(shop_gold)
	var tabs := HBoxContainer.new()
	shop_buy_btn = Button.new(); shop_buy_btn.text = "购买"
	shop_sell_btn = Button.new(); shop_sell_btn.text = "出售"
	shop_buy_btn.custom_minimum_size = Vector2(90, 32)
	shop_sell_btn.custom_minimum_size = Vector2(90, 32)
	shop_buy_btn.pressed.connect(func(): _set_shop_tab(0))
	shop_sell_btn.pressed.connect(func(): _set_shop_tab(1))
	tabs.add_child(shop_buy_btn); tabs.add_child(shop_sell_btn)
	v.add_child(tabs)
	shop_buy_list = VBoxContainer.new(); v.add_child(shop_buy_list)
	shop_sell_list = VBoxContainer.new(); v.add_child(shop_sell_list)

func _set_shop_tab(t: int) -> void:
	shop_tab = t
	_refresh_shop()

func _refresh_shop() -> void:
	if shop_panel == null or not shop_panel.visible:
		return
	shop_gold.text = "金币：%d" % Economy.gold
	shop_buy_btn.modulate = Color(1.0, 0.9, 0.4) if shop_tab == 0 else Color(0.7, 0.7, 0.7)
	shop_sell_btn.modulate = Color(1.0, 0.9, 0.4) if shop_tab == 1 else Color(0.7, 0.7, 0.7)
	for c in shop_buy_list.get_children():
		c.queue_free()
	for c in shop_sell_list.get_children():
		c.queue_free()
	if shop_tab == 0:
		shop_buy_list.visible = true; shop_sell_list.visible = false
		for it in ItemDatabase.all_items():
			if Economy.is_buyable(it):
				_add_shop_row(shop_buy_list, it, true)
	else:
		shop_buy_list.visible = false; shop_sell_list.visible = true
		for id in Inventory.items:
			var it: ItemResource = ItemDatabase.get_item(id)
			if it != null and Economy.is_sellable(it) and Inventory.count(id) > 0:
				_add_shop_row(shop_sell_list, it, false)

func _add_shop_row(list: VBoxContainer, it: ItemResource, is_buy: bool) -> void:
	var row := HBoxContainer.new()
	var name_l := Label.new()
	var price := Economy.effective_buy(it) if is_buy else Economy.effective_sell(it)
	name_l.text = "%s  (%d 金币)" % [it.display_name, price]
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(name_l)
	var btn := Button.new()
	btn.text = "买" if is_buy else "卖"
	btn.custom_minimum_size = Vector2(48, 30)
	btn.pressed.connect(func():
		if is_buy: Economy.buy(it.id) else: Economy.sell(it.id)
		_refresh_shop()
	)
	row.add_child(btn)
	list.add_child(row)

func _on_shop_opened() -> void:
	GameManager.shop_open = true
	shop_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	shop_tab = 0
	_refresh_shop()

func _close_shop() -> void:
	GameManager.shop_open = false
	shop_panel.visible = false
	if Dialogue == null or not Dialogue.active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# =========================================================
# 公告板
# =========================================================
func _build_bulletin() -> void:
	bulletin_panel = Panel.new()
	bulletin_panel.visible = false
	bulletin_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var _vw: float = get_viewport().size.x if get_viewport() else 1080.0
	bulletin_panel.position = Vector2(maxf(16.0, (_vw - 560.0) * 0.5), 90.0)
	bulletin_panel.custom_minimum_size = Vector2(560, 480)
	add_child(bulletin_panel)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.09, 0.15, 0.95); st.set_corner_radius_all(10)
	bulletin_panel.add_theme_stylebox_override("panel", st)
	var title := Label.new()
	title.text = "公告板"
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	title.add_theme_font_size_override("font_size", 20)
	title.position = Vector2(12, 8)
	bulletin_panel.add_child(title)
	# 可滚动容器：公告会随阶段推进不断累积，避免文字超出面板被截断
	bulletin_scroll = ScrollContainer.new()
	bulletin_scroll.position = Vector2(14, 44)
	bulletin_scroll.size = Vector2(532, 424)
	bulletin_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bulletin_panel.add_child(bulletin_scroll)
	bulletin_label = Label.new()
	bulletin_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bulletin_label.custom_minimum_size = Vector2(516, 0)
	bulletin_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bulletin_label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	bulletin_label.add_theme_font_size_override("font_size", 13)
	bulletin_scroll.add_child(bulletin_label)
	_refresh_bulletin()

func _on_bulletin_opened() -> void:
	GameManager.bulletin_open = true
	bulletin_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_bulletin()
	if bulletin_scroll != null:
		bulletin_scroll.scroll_vertical = 0

func _close_bulletin() -> void:
	GameManager.bulletin_open = false
	bulletin_panel.visible = false
	if Dialogue == null or not Dialogue.active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _refresh_bulletin() -> void:
	if bulletin_label == null:
		return
	var lines := PackedStringArray()
	for e in Bulletin.get_entries():
		lines.append("▪ %s\n   %s" % [e["title"], e["body"]])
	bulletin_label.text = "\n\n".join(lines)

# =========================================================
# 成就
# =========================================================
func _build_achievements() -> void:
	ach_panel = Panel.new()
	ach_panel.visible = false
	ach_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ach_panel.position = Vector2((get_viewport().size.x - 420) * 0.5 if get_viewport() else 300, 120)
	ach_panel.custom_minimum_size = Vector2(420, 380)
	add_child(ach_panel)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.1, 0.16, 0.95); st.set_corner_radius_all(10)
	ach_panel.add_theme_stylebox_override("panel", st)
	var title := Label.new()
	title.text = "成就 (K 开关)"
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	title.add_theme_font_size_override("font_size", 20)
	title.position = Vector2(12, 8)
	ach_panel.add_child(title)
	ach_label = Label.new()
	ach_label.position = Vector2(12, 44)
	ach_label.size = Vector2(396, 320)
	ach_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ach_label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	ach_label.add_theme_font_size_override("font_size", 15)
	ach_panel.add_child(ach_label)
	_refresh_achievements()

func _toggle_achievements() -> void:
	GameManager.ach_open = not GameManager.ach_open
	ach_panel.visible = GameManager.ach_open
	if GameManager.ach_open:
		_refresh_achievements()

func _refresh_achievements() -> void:
	if ach_label == null:
		return
	var lines := PackedStringArray()
	for d in Achievements.get_defs():
		var ok := Achievements.is_unlocked(d["id"])
		lines.append("%s %s — %s" % ["[x]" if ok else "[ ]", d["name"], d["desc"]])
	ach_label.text = "\n".join(lines)

func _on_ach_unlocked(_id: String, _name: String, _desc: String) -> void:
	if ach_panel != null and ach_panel.visible:
		_refresh_achievements()

# =========================================================

# =========================================================
# 阶段标签
# =========================================================
func _build_stage_label() -> void:
	stage_label = Label.new()
	stage_label.add_theme_color_override("font_color", Color(0.8, 0.95, 1.0))
	stage_label.add_theme_font_size_override("font_size", 14)
	stage_label.position = Vector2(get_viewport().size.x - 160 if get_viewport() else 1100, 44)
	add_child(stage_label)
	stage_label.text = "阶段：%s" % Stage.current_name()

func _on_stage(_idx: int, name: String, _desc: String) -> void:
	if stage_label != null:
		stage_label.text = "阶段：%s" % name

func _on_gold_changed(_g: int) -> void:
	if shop_panel != null and shop_panel.visible:
		_refresh_shop()

# =========================================================
# 好感 / 心情 / 伙伴
# =========================================================
func _on_affection(v: float) -> void:
	if aff_bar != null:
		aff_bar.value = clampf(v, 0.0, 100.0)

func _on_mood(v: float) -> void:
	if mood_bar != null:
		mood_bar.value = clampf(v, 0.0, 100.0)

## 启动 / 读档后把好感、心情条同步到 RelationshipManager 的真实值（避免显示为 0）。
func _sync_rel_bars() -> void:
	var st: Dictionary = RelationshipManager.get_status()
	if aff_bar != null:
		aff_bar.value = clampf(float(st.get("affection", 0.0)), 0.0, 100.0)
	if mood_bar != null:
		mood_bar.value = clampf(float(st.get("mood", 60.0)), 0.0, 100.0)

func _build_partner_label() -> void:
	partner_label = Label.new()
	partner_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.9))
	partner_label.add_theme_font_size_override("font_size", 13)
	partner_label.position = Vector2((get_viewport().size.x - 260) if get_viewport() else 900, 72)
	add_child(partner_label)
	_refresh_partner()

func _refresh_partner() -> void:
	if partner_label == null:
		return
	if PartyManager == null:
		return
	var s: Dictionary = PartyManager.get_status()
	partner_label.text = "伙伴 %d（倒下%d）｜ 跟随%d 采集%d 战斗%d 待命%d" % [s["total"], s["dead"], s["follow"], s["gather"], s["fight"], s["idle"]]

# =========================================================
# 营地仓库面板（柜子交互打开）
# =========================================================
func _build_camp_storage() -> void:
	camp_panel = Panel.new()
	camp_panel.visible = false
	camp_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	camp_panel.position = Vector2((get_viewport().size.x - 360) * 0.5 if get_viewport() else 320, 120)
	camp_panel.custom_minimum_size = Vector2(360, 420)
	add_child(camp_panel)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.1, 0.16, 0.95); st.set_corner_radius_all(10)
	camp_panel.add_theme_stylebox_override("panel", st)
	var vb := VBoxContainer.new()
	vb.position = Vector2(12, 10); vb.add_theme_constant_override("separation", 6)
	camp_panel.add_child(vb)
	camp_label = Label.new()
	camp_label.text = "营地仓库"
	camp_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	camp_label.add_theme_font_size_override("font_size", 20)
	vb.add_child(camp_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(336, 330)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	camp_list = VBoxContainer.new()
	camp_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camp_list.add_theme_constant_override("separation", 4)
	scroll.add_child(camp_list)
	var hint := Label.new()
	hint.text = "（ESC 关闭）"
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vb.add_child(hint)

func _open_camp_storage() -> void:
	if camp_panel == null:
		return
	camp_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_camp_storage()

func _close_camp_storage() -> void:
	camp_panel.visible = false
	if Dialogue == null or not Dialogue.active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _refresh_camp_storage() -> void:
	if camp_panel == null or not camp_panel.visible:
		return
	for c in camp_list.get_children():
		c.queue_free()
	# 区块一：营地仓库（取出）
	var h1 := Label.new()
	h1.text = "营地仓库（取出）"
	h1.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	h1.add_theme_font_size_override("font_size", 16)
	camp_list.add_child(h1)
	var all: Dictionary = CampStorage.get_all()
	if all.is_empty():
		var e := Label.new()
		e.text = "（空空如也）"
		e.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		camp_list.add_child(e)
	else:
		for id in all.keys():
			camp_list.add_child(_camp_row(id, false))
	# 分隔
	var sep := HSeparator.new()
	camp_list.add_child(sep)
	# 区块二：我的背包（存入）
	var h2 := Label.new()
	h2.text = "我的背包（存入）"
	h2.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
	h2.add_theme_font_size_override("font_size", 16)
	camp_list.add_child(h2)
	var inv: Dictionary = Inventory.items
	if inv.is_empty():
		var e2 := Label.new()
		e2.text = "（背包空）"
		e2.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		camp_list.add_child(e2)
	else:
		for id in inv.keys():
			camp_list.add_child(_camp_row(id, true))

## 生成仓库面板的一行：to_store=true 时为背包物品（存入），否则为仓库物品（取出）。
func _camp_row(id: String, to_store: bool) -> HBoxContainer:
	var it: ItemResource = ItemDatabase.get_item(id)
	var nm: String = it.display_name if it != null else id
	var cnt: int = CampStorage.get_count(id) if not to_store else int(Inventory.items.get(id, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = "%s ×%d" % [nm, cnt]
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(l)
	var btn := Button.new()
	btn.text = "存入" if to_store else "取出"
	btn.custom_minimum_size = Vector2(64, 30)
	if to_store:
		btn.pressed.connect(_store_to_camp.bind(id))
	else:
		btn.pressed.connect(_take_from_camp.bind(id))
	row.add_child(btn)
	return row

## 从营地仓库取出该物品：尽量整堆取出，背包放不下时保留剩余在仓库（不丢物品）。
func _take_from_camp(id: String) -> void:
	if not CampStorage.has(id, 1):
		return
	var moved := 0
	while CampStorage.get_count(id) > 0:
		if not Inventory.can_hold(id):
			break
		CampStorage.consume(id, 1)
		Inventory.add_item(id, 1)
		moved += 1
	var nm: String = _item_name(id)
	if moved <= 0:
		EventBus.toast.emit("背包已满，无法取出 %s（先清出空间）" % nm)
		return
	EventBus.toast.emit("从营地仓库取出：%s ×%d" % [nm, moved])
	var remain: int = CampStorage.get_count(id)
	if remain > 0:
		EventBus.toast.emit("背包放不下，%s ×%d 仍留在仓库" % [nm, remain])
	_refresh_camp_storage()

## 把背包中的某物品整堆存入营地仓库（负重中转）。
func _store_to_camp(id: String) -> void:
	if not Inventory.has(id, 1):
		return
	var have: int = Inventory.count(id)
	Inventory.consume(id, have)
	CampStorage.add_item(id, have)
	EventBus.toast.emit("已存入营地仓库：%s ×%d" % [_item_name(id), have])
	_refresh_camp_storage()

# =========================================================
# 结局分支面板（巢穴通关打开）
# =========================================================
func _build_ending() -> void:
	end_panel = Panel.new()
	end_panel.visible = false
	end_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	end_panel.position = Vector2((get_viewport().size.x - 460) * 0.5 if get_viewport() else 280, 200)
	end_panel.custom_minimum_size = Vector2(460, 280)
	add_child(end_panel)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.12, 0.2, 0.96); st.set_corner_radius_all(10)
	end_panel.add_theme_stylebox_override("panel", st)
	var vb := VBoxContainer.new()
	vb.position = Vector2(16, 14); vb.add_theme_constant_override("separation", 10)
	end_panel.add_child(vb)
	var title := Label.new()
	title.text = "雾散之后"
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	title.add_theme_font_size_override("font_size", 22)
	vb.add_child(title)
	end_label = Label.new()
	end_label.text = "祭坛已碎，黑雾退去。你与女主、岛灵伙伴面临抉择——"
	end_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_label.custom_minimum_size = Vector2(420, 56)
	end_label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	end_label.add_theme_font_size_override("font_size", 15)
	vb.add_child(end_label)
	var leave := Button.new(); leave.text = "离开荒岛（真结局）"
	leave.custom_minimum_size = Vector2(420, 40)
	leave.pressed.connect(func():
		NestRaid.leave_island()
		end_panel.visible = false
		if Dialogue == null or not Dialogue.active:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	)
	vb.add_child(leave)
	var stay := Button.new(); stay.text = "继续留下（自由模式）"
	stay.custom_minimum_size = Vector2(420, 40)
	stay.pressed.connect(func():
		NestRaid.enter_sandbox()
		end_panel.visible = false
		if Dialogue == null or not Dialogue.active:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	)
	vb.add_child(stay)

func _on_nest_cleared() -> void:
	if end_panel == null:
		return
	end_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# =========================================================
# 底部快捷栏 + 建造选择菜单
# =========================================================
func _build_hotbar() -> void:
	hotbar = HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 10)
	add_child(hotbar)

	# 两个快捷栏（1 / 2），放在背包按钮左侧，大小与热栏按钮一致（64×64）
	for i in 2:
		var qs = QuickSlotCls.new()
		qs.slot_index = i
		qs.key_text = str(i + 1)
		qs.use_pressed.connect(_on_qs_use.bind(i))
		qs.clear_pressed.connect(_on_qs_clear.bind(i))
		hotbar.add_child(qs)
		_qs_nodes.append(qs)

	var defs := [
		{"kind": "inventory", "key": "I", "name": "背包", "cb": func(): _toggle_backpack()},
		{"kind": "build", "key": "B", "name": "建造", "cb": func(): _on_build_btn()},
		{"kind": "tasks", "key": "U", "name": "任务", "cb": func(): _toggle_missions()},
		{"kind": "skills", "key": "L", "name": "技能", "cb": func(): _toggle_skill()},
		{"kind": "craft", "key": "C", "name": "制作", "cb": func(): _toggle_craft()},
	]
	for d in defs:
		var b = HotbarButtonCls.new()
		b.icon_kind = d["kind"]
		b.key_hint = d["key"]
		b.label_text = d["name"]
		b.pressed.connect(d["cb"])
		hotbar.add_child(b)
		_hb_buttons[d["kind"]] = b
	_align_hotbar()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_align_hotbar)

func _align_hotbar() -> void:
	if hotbar == null:
		return
	hotbar.reset_size()
	var vp := get_viewport()
	if vp == null:
		return
	# position 定位（左上角坐标），底边贴屏幕底、水平居中，避免双 anchor=0.5 压成 0 尺寸
	hotbar.anchor_left = 0.0
	hotbar.anchor_right = 0.0
	hotbar.anchor_top = 1.0
	hotbar.anchor_bottom = 1.0
	hotbar.position = Vector2(vp.size.x * 0.5 - hotbar.size.x * 0.5, vp.size.y - 14.0 - hotbar.size.y)

## 左键点快捷栏 → 使用其中物品（与按数字键同效）。
func _on_qs_use(i: int) -> void:
	if i < 0 or i >= quick_slots.size():
		return
	var id: String = quick_slots[i]
	if id == "":
		return
	_use_inv_item(id)

## 右键点快捷栏 → 清空该槽。
func _on_qs_clear(i: int) -> void:
	if i < 0 or i >= quick_slots.size():
		return
	if quick_slots[i] == "":
		return
	var nm: String = _item_name(quick_slots[i])
	quick_slots[i] = ""
	_refresh_quick_slots()
	EventBus.toast.emit("已清空快捷栏 %d（%s）" % [i + 1, nm])

## 把背包物品放入快捷栏：优先填空位；两个都满则覆盖 1 号。
func _assign_to_quickslot(id: String) -> void:
	if id == "":
		return
	var idx := 0
	if quick_slots[0] == "":
		idx = 0
	elif quick_slots[1] == "":
		idx = 1
	else:
		idx = 0
	var nm: String = _item_name(id)
	quick_slots[idx] = id
	_refresh_quick_slots()
	EventBus.toast.emit("已将 %s 放入快捷栏 %d（背包里右键物品可换/数字键使用）" % [nm, idx + 1])

## 刷新两个快捷栏显示；若背包中该物品数量已为 0 则自动清空该槽。
func _refresh_quick_slots() -> void:
	if _qs_nodes.size() < 2:
		return
	for i in 2:
		var id: String = quick_slots[i]
		if id != "" and Inventory.count(id) <= 0:
			id = ""
			quick_slots[i] = ""
		_qs_nodes[i].assign(id)

## 背包状态文本 + 任务指引：贴到屏幕最下居中（热栏上方）。
## 任务指引为无背景纯文字，不再有黑框。各菜单面板统一由 _center_panel 居中到屏幕正中。
func _align_bottom_panels() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vx: float = vp.size.x
	var vy: float = vp.size.y
	var hot_h: float = 78.0   # 热栏估算高度（按钮 64 + 间距）

	# 背包状态文本（一行，热栏正上方居中）
	inv_label.anchor_left = 0.0
	inv_label.anchor_right = 0.0
	inv_label.anchor_top = 0.0
	inv_label.anchor_bottom = 0.0
	inv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_label.custom_minimum_size = Vector2(520, 22)
	inv_label.size = Vector2(520, 22)
	inv_label.position = Vector2(vx * 0.5 - 260.0, vy - hot_h - 26.0)

	# 任务指引：无背景纯文字，热栏上方居中（去掉黑框，仅保留目标文本）
	task_panel.anchor_left = 0.0
	task_panel.anchor_right = 0.0
	task_panel.anchor_top = 0.0
	task_panel.anchor_bottom = 0.0
	if task_label.custom_minimum_size.x < 4:
		task_label.custom_minimum_size = Vector2(536, 0)
	var th: float = max(task_label.size.y, 36.0) + 16.0
	task_panel.custom_minimum_size = Vector2(560, th)
	task_panel.size = Vector2(560, th)
	task_panel.position = Vector2(vx * 0.5 - 280.0, vy - hot_h - 26.0 - 8.0 - th)

	# toast：贴在左上状态条正下方（原来写死 y=110 会压住第4行「好感」和第5行「心情」）
	var stats_h: float = 135.0
	if _stats_vbox != null:
		stats_h = maxf(_stats_vbox.size.y, _stats_vbox.get_combined_minimum_size().y)
	toast_label.position = Vector2(16.0, 16.0 + stats_h + 8.0)

	# 建造横幅：屏幕中上方居中（状态条下方），长文本自动换行，彻底避开底部热栏/负重/任务面板
	var bw: float = minf(640.0, vx - 32.0)
	build_label.custom_minimum_size = Vector2(bw, 0)
	build_label.size = Vector2(bw, 0)
	build_label.position = Vector2((vx - bw) * 0.5, 150.0)

## 把菜单面板居中到屏幕正中（背包 / 建造 / 任务树 / 技能 / 制作），像背包一样呈现在屏幕中间。
## ⚠️ 关键：Godot 的普通 Panel 不会像 PanelContainer 那样按子节点自适应尺寸，它的 size 恒为 0；
## 若直接按 size 居中，会把「面板左上角」放到屏幕正中 → 内容整体偏右下、且背景 0×0 根本看不见。
## 因此这里先依据子节点内容算出面板真实外框（含内边距），再按外框居中。
func _center_panel(p: Control) -> void:
	if p == null or not p.visible:
		return
	var vp := get_viewport()
	if vp == null:
		return
	p.reset_size()
	var sz: Vector2 = p.size
	# 仅当面板缺少尺寸（普通 Panel 的 size 恒为 0 或只有 custom_minimum_size 的宽度）时才按内容补全，
	# PanelContainer 自身尺寸正常 → 完全不动它。
	if sz.x < 2.0 or sz.y < 2.0:
		var need := Vector2.ZERO
		for c in p.get_children():
			var cc := c as Control
			if cc == null or not cc.visible:
				continue
			if cc.position.x < 1.0 and cc.position.y < 1.0:
				cc.position = Vector2(PANEL_PAD, PANEL_PAD)   # 未显式摆放的子节点：补统一内边距
			var m: Vector2 = cc.get_combined_minimum_size()
			var cs := Vector2(maxf(cc.size.x, m.x), maxf(cc.size.y, m.y))
			need.x = maxf(need.x, cc.position.x + cs.x)
			need.y = maxf(need.y, cc.position.y + cs.y)
		if sz.x < 2.0:
			sz.x = need.x + PANEL_PAD
		if sz.y < 2.0:
			sz.y = need.y + PANEL_PAD
	p.size = Vector2(maxf(sz.x, 120.0), maxf(sz.y, 48.0))
	p.anchor_left = 0.0
	p.anchor_right = 0.0
	p.anchor_top = 0.0
	p.anchor_bottom = 0.0
	p.position = Vector2(vp.size.x * 0.5 - p.size.x * 0.5, vp.size.y * 0.5 - p.size.y * 0.5)

func _toggle_backpack() -> void:
	backpack_panel.visible = not backpack_panel.visible
	if backpack_panel.visible:
		_refresh_backpack()
		_center_panel(backpack_panel)
		# 打开背包必须释放鼠标，否则鼠标仍是 CAPTURED（隐藏+锁中心）→ 根本没法点格子。
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_restore_mouse()

func _on_build_btn() -> void:
	if GameManager.build_mode:
		Building.exit_build()
		_set_build_menu(false)
	else:
		_set_build_menu(not EventBus.build_menu_open)
	get_viewport().set_input_as_handled()

func _set_build_menu(open: bool) -> void:
	EventBus.build_menu_open = open
	build_menu.visible = open
	if open:
		_build_build_menu_list()
		_align_build_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if Dialogue == null or not Dialogue.active:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_build_menu() -> void:
	build_menu = Panel.new()
	build_menu.visible = false
	build_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(build_menu)
	var v := VBoxContainer.new()
	v.position = Vector2(12, 10)
	v.add_theme_constant_override("separation", 6)
	build_menu.add_child(v)
	var title := Label.new()
	title.text = "建造菜单（点击选择要造的东西 / ESC 关闭）"
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	title.add_theme_font_size_override("font_size", 16)
	v.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	build_menu_list = VBoxContainer.new()
	build_menu_list.add_theme_constant_override("separation", 4)
	build_menu_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(build_menu_list)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.1, 0.16, 0.97)
	st.set_corner_radius_all(10)
	build_menu.add_theme_stylebox_override("panel", st)

func _build_build_menu_list() -> void:
	_bm_built = true
	for c in build_menu_list.get_children():
		c.queue_free()
	if Building.buildables.is_empty():
		Building._collect()
	if Building.buildables.is_empty():
		var e := Label.new()
		e.text = "（暂无可建造物）"
		e.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		build_menu_list.add_child(e)
		return
	for i in Building.buildables.size():
		var it = Building.buildables[i]
		var cost := Building.buildable_cost_text(i)
		var btn := Button.new()
		btn.text = "%s    %s" % [it.display_name, cost]
		btn.custom_minimum_size = Vector2(296, 36)
		var idx: int = i
		btn.pressed.connect(func():
			Building.enter_with(idx)
			_set_build_menu(false)
		)
		build_menu_list.add_child(btn)

func _align_build_menu() -> void:
	_center_panel(build_menu)

func _sync_hotbar() -> void:
	if hotbar == null:
		return
	for kind in _hb_buttons:
		var b = _hb_buttons[kind]
		var active := false
		match kind:
			"inventory": active = backpack_panel.visible
			"build": active = EventBus.build_menu_open or GameManager.build_mode
			"tasks": active = mission_panel.visible
			"skills": active = skill_panel.visible
			"craft": active = craft_panel.visible
		b.set_active(active)

# =========================================================
# 输入
# =========================================================
func _unhandled_input(event) -> void:
	if event is InputEventKey and event.pressed:
		# 对话进行中：回车/空格推进，并吞掉输入避免触发其它动作
		if Dialogue != null and Dialogue.active:
			if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
				Dialogue.advance()
				get_viewport().set_input_as_handled()
			return
		# 结局面板打开时强制用按钮选择，吞掉其它按键
		if end_panel != null and end_panel.visible:
			return
		# 其它面板（商店/公告/成就/营地仓库/背包/制作/技能/任务）优先用 Esc 关闭，再让位给烹饪
		if event.keycode == KEY_ESCAPE:
			if gift_panel != null and gift_panel.visible:
				_close_gift_panel(); get_viewport().set_input_as_handled(); return
			if npc_menu != null and npc_menu.visible:
				_close_npc_menu(); get_viewport().set_input_as_handled(); return
			if EventBus.build_menu_open:
				_set_build_menu(false); get_viewport().set_input_as_handled(); return
			if GameManager.build_mode:
				Building.exit_build(); _set_build_menu(false); get_viewport().set_input_as_handled(); return
			if shop_panel.visible:
				_close_shop(); get_viewport().set_input_as_handled(); return
			if bulletin_panel.visible:
				_close_bulletin(); get_viewport().set_input_as_handled(); return
			if camp_panel != null and camp_panel.visible:
				_close_camp_storage(); get_viewport().set_input_as_handled(); return
			if party_panel != null and party_panel.visible:
				_close_party_menu(); get_viewport().set_input_as_handled(); return
			if ach_panel.visible:
				_toggle_achievements(); get_viewport().set_input_as_handled(); return
			if backpack_panel != null and backpack_panel.visible:
				_toggle_backpack(); get_viewport().set_input_as_handled(); return
			if craft_panel != null and craft_panel.visible:
				_toggle_craft(); get_viewport().set_input_as_handled(); return
			if skill_panel != null and skill_panel.visible:
				_toggle_skill(); get_viewport().set_input_as_handled(); return
			if mission_panel != null and mission_panel.visible:
				_toggle_missions(); get_viewport().set_input_as_handled(); return
		# —— 伙伴指令：T 全员广播 / E 走近单人 ——
		if event.keycode == KEY_T:
			if _party_blocked():
				return
			_toggle_party_menu()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_E:
			if _party_blocked():
				return
			var _p = GameManager.player
			if _p != null and PartyManager != null:
				var _comp = PartyManager.nearest_companion(_p.global_position, 3.0)
				if _comp != null:
					_open_party_menu(_comp)
					get_viewport().set_input_as_handled()
					return
		# 烹饪菜单打开：数字键烹饪 / ESC 关闭
		if cook_panel.visible:
			if event.keycode == KEY_ESCAPE:
				_close_cooking()
			elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
				_start_cook(int(event.keycode) - int(KEY_1))
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_B:
			_on_build_btn()
		elif event.keycode == KEY_C:
			_toggle_craft()
		elif event.keycode == KEY_J:
			_task_visible = not _task_visible
			task_panel.visible = _task_visible
		elif event.keycode == KEY_I:
			_toggle_backpack()
		elif event.keycode == KEY_L:
			_toggle_skill()
		elif event.keycode == KEY_U:
			_toggle_missions()
		elif event.keycode == KEY_K:
			_toggle_achievements()
		elif craft_panel.visible and event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var idx: int = int(event.keycode) - int(KEY_1)
			var recipes: Array = Crafting.recipes
			if idx < recipes.size():
				Crafting.craft(recipes[idx]["id"])
		elif skill_panel.visible and event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var idx: int = int(event.keycode) - int(KEY_1)
			var sk: Array = Skills.get_list()
			if idx < sk.size():
				Skills.try_unlock(sk[idx]["id"])
		elif event.keycode >= KEY_1 and event.keycode <= KEY_6:
			var d6: int = int(event.keycode) - int(KEY_1)
			# 1/2 快捷栏：槽内有物品则优先“使用”，否则落回装备热栏（不破坏原 1-6 装备手感）
			if d6 < quick_slots.size() and quick_slots[d6] != "":
				_use_inv_item(quick_slots[d6])
				get_viewport().set_input_as_handled()
				return
			if d6 < Equipment.hotbar.size():
				Equipment.equip_index(d6)
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_sync_hotbar()
	_align_hotbar()
	_align_bottom_panels()
	# 各菜单面板统一居中到屏幕正中（像背包一样）
	_center_panel(backpack_panel)
	_center_panel(build_menu)
	_center_panel(mission_panel)
	_center_panel(skill_panel)
	_center_panel(craft_panel)
	_center_panel(npc_menu)
	_center_panel(gift_panel)
	_center_panel(party_panel)
	_update_prompt()
	_update_party_prompt()
	_align_crosshair()
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			toast_label.visible = false
	if _partner_t > 0.0:
		_partner_t -= delta
		if _partner_t <= 0.0:
			_partner_t = 0.5
			_refresh_partner()
	if _cooking_raw != "" and cook_progress.visible:
		if _cook_timer.is_stopped():
			cook_progress.value = 100.0
		else:
			var total: float = _cook_timer.wait_time
			var left: float = _cook_timer.time_left
			cook_progress.value = clamp((1.0 - left / total) * 100.0, 0.0, 100.0)
	if GameManager.build_mode:
		build_label.visible = true
		var nm := Building.current_name()
		var cost := Building.current_cost_text()
		build_label.text = "建造模式：%s  |  材料：%s  |  E 放置 / TAB 切换 / B 退出" % [nm if nm != "" else "（无可用结构）", cost if cost != "" else "—"]
	else:
		build_label.visible = false
	if DayNightCycle != null:
		_on_time()
	_update_popups(delta)

## 伤害浮字上升 + 淡出
func _update_popups(delta: float) -> void:
	for i in range(_popups.size() - 1, -1, -1):
		var p: Dictionary = _popups[i]
		p["life"] -= delta
		p["label"].position.y += p["vy"] * delta
		p["label"].modulate.a = clamp(p["life"] / 0.9, 0.0, 1.0)
		if p["life"] <= 0.0:
			p["label"].queue_free()
			_popups.remove_at(i)

# =========================================================
# 交互提示（醒目横幅）
# =========================================================
## 每帧：把提示横幅居中到屏幕中下方；菜单/对话打开时隐藏。
func _update_prompt() -> void:
	if prompt_panel == null:
		return
	var show_prompt := _prompt_text != ""
	if npc_menu != null and npc_menu.visible:
		show_prompt = false
	if gift_panel != null and gift_panel.visible:
		show_prompt = false
	if Dialogue != null and Dialogue.active:
		show_prompt = false
	if show_prompt and prompt_label.text != _prompt_text:
		prompt_label.text = _prompt_text
	prompt_panel.visible = show_prompt
	if not show_prompt:
		return
	_align_prompt()

func _align_prompt() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var sz := prompt_panel.get_combined_minimum_size()
	prompt_panel.size = sz
	prompt_panel.position = Vector2(vp.size.x * 0.5 - sz.x * 0.5, vp.size.y * 0.56)

# =========================================================
# 准星（屏幕正中心）
# =========================================================
## 构造屏幕正中心准星：一个固定尺寸的透明 Control，用 _draw 自绘十字 + 中心点。
func _build_crosshair() -> void:
	crosshair = Control.new()
	crosshair.name = "Crosshair"
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.custom_minimum_size = Vector2(30, 30)
	crosshair.size = Vector2(30, 30)
	crosshair.draw.connect(_on_crosshair_draw)
	add_child(crosshair)
	crosshair.queue_redraw()

## 自绘准星：白色细十字 + 中心小圆点；当射线正瞄准可交互物（prompt_text 非空）时变金色高亮。
func _on_crosshair_draw() -> void:
	var c := crosshair.size * 0.5
	# 瞄准到可交互物 -> 金色（与交互提示横幅描边同色），否则柔和白
	var col := Color(1.0, 0.85, 0.34, 0.95) if _prompt_text != "" else Color(0.92, 0.94, 0.98, 0.8)
	var r := 1.8           # 中心圆点半径
	var gap := 5.0         # 中心留空（十字不连到圆心）
	var len := 6.0         # 四向短线长度
	var th := 1.5          # 线宽
	crosshair.draw_circle(c, r, col)
	crosshair.draw_line(c + Vector2(0.0, -gap), c + Vector2(0.0, -gap - len), col, th)
	crosshair.draw_line(c + Vector2(0.0, gap), c + Vector2(0.0, gap + len), col, th)
	crosshair.draw_line(c + Vector2(-gap, 0.0), c + Vector2(-gap - len, 0.0), col, th)
	crosshair.draw_line(c + Vector2(gap, 0.0), c + Vector2(gap + len, 0.0), col, th)

## 每帧：把准星贴到屏幕正中；仅当鼠标被捕获（游玩中）时显示，菜单/对话打开（鼠标释放）则隐藏。
func _align_crosshair() -> void:
	if crosshair == null:
		return
	var vp := get_viewport()
	if vp == null:
		crosshair.visible = false
		return
	crosshair.visible = (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	# 严格贴屏幕正中心：交互射线就是「相机正前」(-cam.global_transform.basis.z)，
	# 准星必须与它重合，否则「看到的准星」和「实际选中的目标」错位（拾取/交互对不准）。
	# 想让它别压在角色身上：不要挪准星，改 camera_rig.gd 的 TP_VIEW_LIFT（抬视线让角色落到画面下方）。
	crosshair.position = vp.size * 0.5 - crosshair.size * 0.5
	crosshair.queue_redraw()

# =========================================================
# NPC 交互菜单（交谈 / 送礼）
# =========================================================
func _build_npc_menu() -> void:
	npc_menu = PanelContainer.new()
	npc_menu.visible = false
	npc_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.08, 0.14, 0.96)
	st.set_corner_radius_all(12)
	st.border_color = Color(1.0, 0.86, 0.36, 0.85)
	st.set_border_width_all(2)
	st.content_margin_left = 18.0
	st.content_margin_right = 18.0
	st.content_margin_top = 12.0
	st.content_margin_bottom = 14.0
	npc_menu.add_theme_stylebox_override("panel", st)
	add_child(npc_menu)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	npc_menu.add_child(vb)
	npc_menu_title = Label.new()
	npc_menu_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
	npc_menu_title.add_theme_font_size_override("font_size", 21)
	vb.add_child(npc_menu_title)
	var sub := Label.new()
	sub.text = "（点击选择 · ESC 关闭）"
	sub.add_theme_color_override("font_color", Color(0.72, 0.74, 0.8))
	sub.add_theme_font_size_override("font_size", 12)
	vb.add_child(sub)
	npc_menu_list = VBoxContainer.new()
	npc_menu_list.add_theme_constant_override("separation", 8)
	vb.add_child(npc_menu_list)

func _on_npc_menu_requested(npc_name: String, options: Array, target) -> void:
	_npc_target = target
	if gift_panel != null:
		gift_panel.visible = false
	for c in npc_menu_list.get_children():
		c.queue_free()
	npc_menu_title.text = str(npc_name)
	# 无选项时给个兜底按钮，避免空面板
	var acts: Array = options
	if acts.is_empty():
		acts = [{"id": "talk", "label": "交谈", "hint": ""}]
	for o in acts:
		var od: Dictionary = o
		var aid := str(od.get("id", ""))
		var lab := str(od.get("label", ""))
		var hnt := str(od.get("hint", ""))
		var btn := Button.new()
		if hnt != "":
			btn.text = "%s　%s" % [lab, hnt]
		else:
			btn.text = lab
		btn.custom_minimum_size = Vector2(300, 40)
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(func(): _on_npc_option(aid))
		npc_menu_list.add_child(btn)
	npc_menu.visible = true
	GameManager.interact_menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_center_panel(npc_menu)

func _on_npc_option(id: String) -> void:
	var t := _npc_target
	if id == "gift":
		_open_gift_panel()
		return
	_close_npc_menu()
	if t != null and t.has_method("do_interact"):
		t.call("do_interact", id)

func _close_npc_menu() -> void:
	if npc_menu != null:
		npc_menu.visible = false
	if gift_panel == null or not gift_panel.visible:
		GameManager.interact_menu_open = false
		_restore_mouse()

# =========================================================
# 送礼面板（从背包/营地仓库点选物品赠送）
# =========================================================
func _build_gift_panel() -> void:
	gift_panel = PanelContainer.new()
	gift_panel.visible = false
	gift_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.09, 0.15, 0.96)
	st.set_corner_radius_all(12)
	st.border_color = Color(1.0, 0.86, 0.36, 0.5)
	st.set_border_width_all(2)
	st.content_margin_left = 18.0
	st.content_margin_right = 18.0
	st.content_margin_top = 12.0
	st.content_margin_bottom = 14.0
	gift_panel.add_theme_stylebox_override("panel", st)
	add_child(gift_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	gift_panel.add_child(vb)
	gift_label = Label.new()
	gift_label.text = "送礼给女主"
	gift_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
	gift_label.add_theme_font_size_override("font_size", 21)
	vb.add_child(gift_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	gift_list = VBoxContainer.new()
	gift_list.custom_minimum_size = Vector2(404, 0)
	gift_list.add_theme_constant_override("separation", 4)
	scroll.add_child(gift_list)
	gift_hint = Label.new()
	gift_hint.text = "（点击「赠送」把物品送给她 · ESC 返回）"
	gift_hint.add_theme_color_override("font_color", Color(0.72, 0.75, 0.8))
	gift_hint.add_theme_font_size_override("font_size", 12)
	vb.add_child(gift_hint)

func _open_gift_panel() -> void:
	if npc_menu != null:
		npc_menu.visible = false
	gift_panel.visible = true
	GameManager.interact_menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_gift_list()
	_center_panel(gift_panel)

func _close_gift_panel() -> void:
	if gift_panel != null:
		gift_panel.visible = false
	if npc_menu == null or not npc_menu.visible:
		GameManager.interact_menu_open = false
		_restore_mouse()

## 列出可送物品：背包优先，其次营地仓库（同 id 只出现一次）。
func _refresh_gift_list() -> void:
	if gift_list == null:
		return
	for c in gift_list.get_children():
		c.queue_free()
	var cands: Array = []
	if _npc_target != null and _npc_target.has_method("gift_list"):
		cands = _npc_target.call("gift_list")
	if cands.is_empty():
		var e := Label.new()
		e.text = "（背包和营地仓库里都没有能送的东西）"
		e.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72))
		gift_list.add_child(e)
		return
	for c in cands:
		var cd: Dictionary = c
		var id := str(cd.get("id", ""))
		var src := str(cd.get("src", "bag"))
		var cnt := int(cd.get("count", 0))
		var it: ItemResource = ItemDatabase.get_item(id)
		var nm: String = it.display_name if it != null else id
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if it != null and it.icon != null:
			icon.texture = it.icon
		else:
			icon.texture = ItemIcons.icon_for(id)
		row.add_child(icon)
		var lab := Label.new()
		var src_txt: String = "背包" if src == "bag" else "仓库"
		lab.text = "%s ×%d　[%s]　%s" % [nm, cnt, src_txt, _gift_value_text(id)]
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.add_theme_color_override("font_color", Color.WHITE)
		row.add_child(lab)
		var btn := Button.new()
		btn.text = "赠送"
		btn.custom_minimum_size = Vector2(66, 34)
		btn.pressed.connect(_on_gift_pressed.bind(id, src))
		row.add_child(btn)
		gift_list.add_child(row)

func _gift_value_text(id: String) -> String:
	var da: float = RelationshipManager.GIFT_AFFECTION.get(id, 0.0)
	if da > 0.0:
		return "好感 +%d" % int(da)
	if da < 0.0:
		return "好感 %d" % int(da)
	return "无好感变化"

func _on_gift_pressed(id: String, src: String) -> void:
	if _npc_target == null or not _npc_target.has_method("give_item"):
		return
	_npc_target.call("give_item", id, src)
	_refresh_gift_list()

# =========================================================
# 伙伴指令面板（T 全员广播 / E 走近单人）
# =========================================================
func _cstr(n: Node, key: String, default_value := "") -> String:
	var v = n.get(key)
	if v == null:
		return default_value
	return str(v)

func _build_party_panel() -> void:
	party_panel = PanelContainer.new()
	party_panel.visible = false
	party_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.08, 0.14, 0.96)
	st.set_corner_radius_all(12)
	st.border_color = Color(0.4, 0.95, 0.7, 0.9)
	st.set_border_width_all(2)
	st.content_margin_left = 18.0
	st.content_margin_right = 18.0
	st.content_margin_top = 12.0
	st.content_margin_bottom = 14.0
	party_panel.add_theme_stylebox_override("panel", st)
	add_child(party_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	party_panel.add_child(vb)
	party_title = Label.new()
	party_title.add_theme_color_override("font_color", Color(0.7, 1.0, 0.85))
	party_title.add_theme_font_size_override("font_size", 21)
	vb.add_child(party_title)
	var sub := Label.new()
	sub.text = "（点击选择 · ESC 关闭）"
	sub.add_theme_color_override("font_color", Color(0.72, 0.74, 0.8))
	sub.add_theme_font_size_override("font_size", 12)
	vb.add_child(sub)
	party_list = VBoxContainer.new()
	party_list.add_theme_constant_override("separation", 8)
	vb.add_child(party_list)
	var defs := [
		{"label": "采集食物", "mode": "gather"},
		{"label": "自己去战斗", "mode": "fight"},
		{"label": "跟随自己战斗", "mode": "follow"},
		{"label": "召集回来", "mode": "return"},
	]
	for d in defs:
		var btn := Button.new()
		btn.text = d["label"]
		btn.custom_minimum_size = Vector2(300, 40)
		btn.add_theme_font_size_override("font_size", 16)
		var md: String = d["mode"]
		btn.pressed.connect(func(): _issue_party(md))
		party_list.add_child(btn)

func _build_party_prompt() -> void:
	party_prompt_label = Label.new()
	party_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.72))
	party_prompt_label.add_theme_font_size_override("font_size", 18)
	party_prompt_label.visible = false
	add_child(party_prompt_label)

func _open_party_menu(target: Node) -> void:
	_cmd_target = target
	if target != null and target.has_method("get"):
		party_title.text = _cstr(target, "char_name", "伙伴") + " 的指令"
	else:
		party_title.text = "全体伙伴指令"
	if party_panel == null:
		return
	party_panel.visible = true
	GameManager.interact_menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_center_panel(party_panel)

func _issue_party(mode: String) -> void:
	if PartyManager == null:
		_close_party_menu()
		return
	if _cmd_target != null and is_instance_valid(_cmd_target):
		PartyManager.command_one(_cmd_target, mode)
	else:
		PartyManager.command_all(mode)
	_close_party_menu()

func _close_party_menu() -> void:
	if party_panel != null:
		party_panel.visible = false
	_cmd_target = null
	GameManager.interact_menu_open = false
	_restore_mouse()

func _toggle_party_menu() -> void:
	if party_panel != null and party_panel.visible:
		_close_party_menu()
	else:
		_open_party_menu(null)

func _party_blocked() -> bool:
	if Dialogue != null and Dialogue.active:
		return true
	if end_panel != null and end_panel.visible:
		return true
	if cook_panel.visible:
		return true
	if npc_menu != null and npc_menu.visible:
		return true
	if gift_panel != null and gift_panel.visible:
		return true
	if shop_panel.visible:
		return true
	if bulletin_panel.visible:
		return true
	if camp_panel != null and camp_panel.visible:
		return true
	if ach_panel.visible:
		return true
	if EventBus.build_menu_open:
		return true
	if GameManager.build_mode:
		return true
	if party_panel != null and party_panel.visible:
		return true
	return false

func _update_party_prompt() -> void:
	if party_prompt_label == null:
		return
	if _party_blocked() or (party_panel != null and party_panel.visible):
		party_prompt_label.visible = false
		return
	var vp := get_viewport()
	if vp == null:
		return
	party_prompt_label.position = Vector2(vp.size.x * 0.5 - 70.0, vp.size.y * 0.66)
	var p = GameManager.player
	if p != null and PartyManager != null:
		var comp = PartyManager.nearest_companion(p.global_position, 3.0)
		if comp != null:
			party_prompt_label.text = "按 E 指挥 %s" % _cstr(comp, "char_name", "伙伴")
			party_prompt_label.visible = true
			return
	party_prompt_label.visible = false

# =========================================================
# 鼠标释放 / 恢复（所有弹窗共用）
# =========================================================
func _any_panel_open() -> bool:
	if backpack_panel != null and backpack_panel.visible:
		return true
	if craft_panel != null and craft_panel.visible:
		return true
	if skill_panel != null and skill_panel.visible:
		return true
	if mission_panel != null and mission_panel.visible:
		return true
	if shop_panel != null and shop_panel.visible:
		return true
	if bulletin_panel != null and bulletin_panel.visible:
		return true
	if camp_panel != null and camp_panel.visible:
		return true
	if ach_panel != null and ach_panel.visible:
		return true
	if end_panel != null and end_panel.visible:
		return true
	if cook_panel != null and cook_panel.visible:
		return true
	if npc_menu != null and npc_menu.visible:
		return true
	if gift_panel != null and gift_panel.visible:
		return true
	if EventBus.build_menu_open:
		return true
	return false

func _restore_mouse() -> void:
	if Dialogue != null and Dialogue.active:
		return
	if _any_panel_open():
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# =========================================================
# GAME OVER 覆盖层（营地失守等终局失败）
# =========================================================
## 构建全屏 GAME OVER 覆盖层：暗红半透明压暗 + 标题 + 失败原因 + 重开按钮。默认隐藏，
## 由 EventBus.game_over 触发显示（此时释放鼠标以便点击按钮）。
func _build_game_over() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GameOverLayer"
	add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.0, 0.0, 0.80)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 20)
	dim.add_child(vb)

	var title := Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	title.add_theme_font_size_override("font_size", 72)
	vb.add_child(title)

	var reason := Label.new()
	reason.name = "GoReason"
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason.custom_minimum_size = Vector2(700, 0)
	reason.add_theme_color_override("font_color", Color(0.9, 0.8, 0.8))
	reason.add_theme_font_size_override("font_size", 20)
	vb.add_child(reason)

	var btn := Button.new()
	btn.text = "重新开始"
	btn.custom_minimum_size = Vector2(240, 52)
	btn.add_theme_font_size_override("font_size", 22)
	btn.pressed.connect(func():
		if GameManager.has_method("restart_game"):
			GameManager.restart_game()
	)
	vb.add_child(btn)

	layer.visible = false
	_game_over_layer = layer
	_game_over_reason = reason

func _on_game_over(reason: String) -> void:
	if _game_over_layer == null:
		return
	_game_over_reason.text = str(reason)
	_game_over_layer.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
