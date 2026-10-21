extends Control
## 钓鱼界面（Autoload: FishingUI）。对标 Tidewater 的钓鱼交互层。
## 只读 EventBus 信号，不主动查任何块：
##   - 搏鱼 HUD：张力条 + 收线进度条（fighting 时显示）
##   - 入护卡：钓到时弹出鱼名/体长/体重/价值/体色，数秒后自动消失
##   - 钓鱼手册（P 键开/关）：图鉴（已发现/未发现）+ 冷藏箱计数 + 装备升级按钮
## 第一人称由 player.gd 在 fishing_started/ended 时强制/还原。

const GEAR_NAMES := {
	"rod": "鱼竿",
	"reel": "渔轮",
	"line": "鱼线",
	"hold": "冷藏箱",
	"fishfinder": "探鱼器",
	"nightlight": "夜钓灯",
}

const HAB_NAMES := {
	"shallows": "浅滩",
	"bay": "海湾",
	"reef": "礁区",
	"pier": "码头",
	"deep": "深水",
}

var fight_panel: Panel
var fight_label: Label
var fight_size: Label
var fight_state_label: Label
var fish_stamina_bar: ProgressBar
var tension_bar: ProgressBar
var tension_hint: Label
var progress_bar: ProgressBar

var card_panel: Panel
var card_title: Label
var card_info: Label
var card_fish_view: SubViewport      # 内嵌 3D 鱼预览渲染目标
var card_fish_mesh: MeshInstance3D   # 程序化鱼模型（按 species 生成）
var card_fish_rect: TextureRect      # SubViewport 纹理承载
var _fish_spin: float = 0.0          # 鱼缓慢自转角度
var card_cooler: Label
var _card_timer: float = 0.0

var book_panel: Panel
var book_stats: Label
var book_list: VBoxContainer
var _book_open: bool = false

var hint_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# FishingUI 是 autoload，比主场景（含背包/快捷栏）先入树；抬高 z 保证搏鱼面板始终画在 HUD 之上，不被背包挡住。
	z_index = 100
	_build_fight()
	_build_card()
	_build_book()
	_build_hint()
	EventBus.fishing_fight_started.connect(_on_fight_start)
	EventBus.fishing_fight_state.connect(_on_fight_state)
	EventBus.fishing_tension.connect(_on_tension)
	EventBus.fishing_catch_card.connect(_on_catch_card)
	EventBus.fishing_ended.connect(_on_ended)
	EventBus.fishing_log_updated.connect(_refresh_book_if_open)
	EventBus.fishing_gear_changed.connect(_refresh_book_if_open)
	EventBus.fishing_xp_changed.connect(_refresh_book_if_open)

# =========================================================
# 构建
# =========================================================
func _build_fight() -> void:
	fight_panel = Panel.new()
	fight_panel.visible = false
	fight_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fight_panel.z_index = 1   # 相对 FishingUI(z=100) 仍在上层
	add_child(fight_panel)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.07, 0.12, 0.85)
	st.set_corner_radius_all(10)
	fight_panel.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.position = Vector2(12, 10)
	v.add_theme_constant_override("separation", 4)
	fight_panel.add_child(v)
	# 标题：拉力对决 · 鱼名
	fight_label = Label.new()
	fight_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	fight_label.add_theme_font_size_override("font_size", 16)
	v.add_child(fight_label)
	# 鱼的状态信息：体长 / 体重 / 离竿距离 / 水域（单行，宽度收敛避免被裁剪）
	fight_size = Label.new()
	fight_size.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	fight_size.add_theme_font_size_override("font_size", 13)
	fight_size.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fight_size.text = "体长 -- 米  |  -- kg  |  离竿 -- 米  |  水域 --"
	v.add_child(fight_size)
	# 鱼的状态（冲刺中 / 歇息中）——对标原版的鱼类状态显示
	fight_state_label = Label.new()
	fight_state_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	fight_state_label.add_theme_font_size_override("font_size", 15)
	fight_state_label.text = "鱼状态：观察中……"
	v.add_child(fight_state_label)
	# 鱼的体力条（越低越容易被拉近）
	var sl := Label.new(); sl.text = "鱼的体力"
	sl.add_theme_color_override("font_color", Color(0.85, 0.8, 1.0))
	sl.add_theme_font_size_override("font_size", 12); v.add_child(sl)
	fish_stamina_bar = ProgressBar.new()
	fish_stamina_bar.custom_minimum_size = Vector2(340, 9)
	fish_stamina_bar.max_value = 1.0; fish_stamina_bar.value = 1.0
	fish_stamina_bar.modulate = Color(0.75, 0.6, 1.0)
	v.add_child(fish_stamina_bar)
	var tl := Label.new(); tl.text = "张力（过高会断线！）"
	tl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
	tl.add_theme_font_size_override("font_size", 12); v.add_child(tl)
	tension_bar = ProgressBar.new()
	tension_bar.custom_minimum_size = Vector2(340, 13)
	tension_bar.max_value = 1.0; tension_bar.value = 0.0
	tension_bar.modulate = Color(0.95, 0.35, 0.3)
	v.add_child(tension_bar)
	# 张力绿区提示：绿=适中（保持），黄=偏高，红=将断线（松手）
	tension_hint = Label.new()
	tension_hint.add_theme_font_size_override("font_size", 13)
	tension_hint.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	tension_hint.text = "绿区安全，红区断线：鱼冲刺或张力变红时松开左键"
	v.add_child(tension_hint)
	var pl := Label.new(); pl.text = "收线进度（按住左键收线，鱼冲刺时松开）"
	pl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	pl.add_theme_font_size_override("font_size", 12); v.add_child(pl)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(340, 13)
	progress_bar.max_value = 1.0; progress_bar.value = 0.0
	progress_bar.modulate = Color(0.4, 0.9, 0.5)
	v.add_child(progress_bar)
	fight_panel.custom_minimum_size = Vector2(364, 0)

func _build_card() -> void:
	card_panel = Panel.new()
	card_panel.visible = false
	card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card_panel)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.12, 0.2, 0.96); st.set_corner_radius_all(12)
	card_panel.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.position = Vector2(20, 16); v.add_theme_constant_override("separation", 8)
	card_panel.add_child(v)
	card_title = Label.new()
	card_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	card_title.add_theme_font_size_override("font_size", 22)
	v.add_child(card_title)
	card_info = Label.new()
	card_info.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	card_info.add_theme_font_size_override("font_size", 16)
	card_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(card_info)
	# 3D 鱼预览（对标 Tidewater 渔获卡内嵌模型）：SubViewport 渲染缓慢自转的程序化鱼
	var hb := HBoxContainer.new(); v.add_child(hb)
	card_fish_view = SubViewport.new()
	card_fish_view.size = Vector2(150, 150)
	card_fish_view.transparent_bg = true
	card_fish_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	card_fish_view.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	# 独立 3D 世界：否则预览里的 key 方向光(1.5)+补光会泄漏进主世界，
	# 等于给全场景多加一盏 1.5 倍太阳 → 整体发白过曝
	card_fish_view.own_world_3d = true
	# 关键：SubViewport 必须挂到场景树上才会渲染，否则其纹理永远是空的（鱼不可见）
	add_child(card_fish_view)
	var cam_root := Node3D.new()
	card_fish_view.add_child(cam_root)
	var key := DirectionalLight3D.new()
	key.position = Vector3(1.2, 2.0, 1.5)
	key.look_at_from_position(Vector3.ZERO, key.position)
	key.light_color = Color(1.0, 0.98, 0.92)
	key.light_energy = 1.5
	cam_root.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.0, 0.4, 0.8)
	fill.light_color = Color(0.75, 0.85, 1.0)
	fill.light_energy = 0.55
	cam_root.add_child(fill)
	card_fish_mesh = MeshInstance3D.new()
	cam_root.add_child(card_fish_mesh)
	var cam := Camera3D.new()
	cam.position = Vector3(1.5, 0.35, 1.4)
	cam.look_at_from_position(Vector3.ZERO, cam.position)
	cam.fov = 32.0
	cam.near = 0.1
	cam.far = 20.0
	cam_root.add_child(cam)
	card_fish_rect = TextureRect.new()
	card_fish_rect.custom_minimum_size = Vector2(150, 150)
	card_fish_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_fish_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_fish_rect.texture = card_fish_view.get_texture()
	hb.add_child(card_fish_rect)
	card_cooler = Label.new()
	card_cooler.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	card_cooler.add_theme_font_size_override("font_size", 14)
	card_cooler.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_cooler.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(card_cooler)
	card_panel.custom_minimum_size = Vector2(420, 0)

func _build_book() -> void:
	book_panel = Panel.new()
	book_panel.visible = false
	book_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(book_panel)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.07, 0.09, 0.15, 0.96); st.set_corner_radius_all(12)
	book_panel.add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.position = Vector2(14, 12); v.add_theme_constant_override("separation", 6)
	book_panel.add_child(v)
	var title := Label.new(); title.text = "钓鱼手册（P 关闭）"
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	title.add_theme_font_size_override("font_size", 20)
	v.add_child(title)
	book_stats = Label.new()
	book_stats.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	book_stats.add_theme_font_size_override("font_size", 14)
	v.add_child(book_stats)
	book_list = VBoxContainer.new()
	book_list.add_theme_constant_override("separation", 4)
	book_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(book_list)
	v.add_child(scroll)
	book_panel.custom_minimum_size = Vector2(588, 520)

func _build_hint() -> void:
	hint_label = Label.new()
	hint_label.text = "P 钓鱼手册"
	hint_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	hint_label.add_theme_font_size_override("font_size", 13)
	add_child(hint_label)

# =========================================================
# 信号回调
# =========================================================
func _on_fight_start(data: Dictionary) -> void:
	fight_panel.visible = true
	fight_label.text = "拉力对决 · %s" % str(data.get("name", "鱼"))
	fight_size.text = "体长 %.2f 米  |  %.2f kg  |  离竿 -- 米" % [
		float(data.get("length_cm", 0.0)) / 100.0,
		float(data.get("weight_kg", 0.0))
	]
	fight_state_label.text = "鱼状态：观察中……"
	fight_state_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	fish_stamina_bar.value = 1.0
	_refresh_tension(0.35, 0.0)

## 每帧刷新"鱼的状态"（对标原版搏鱼面板的鱼类状态显示）
func _on_fight_state(info: Dictionary) -> void:
	if not fight_panel.visible or info.is_empty():
		return
	fight_size.text = "体长 %.2f 米  |  %.2f kg  |  离竿 %.1f 米  |  水域 %s" % [
		float(info.get("length_m", 0.0)),
		float(info.get("weight_kg", 0.0)),
		float(info.get("distance_m", 0.0)),
		str(HAB_NAMES.get(str(info.get("habitat", "")), "未知"))
	]
	fish_stamina_bar.value = clampf(float(info.get("stamina", 1.0)), 0.0, 1.0)
	var running: bool = bool(info.get("running", false))
	var exhausted: bool = bool(info.get("exhausted", false))
	if exhausted:
		fight_state_label.text = "鱼状态：力竭了！自动收线入护…"
		fight_state_label.add_theme_color_override("font_color", Color(0.5, 1.0, 1.0))
		fish_stamina_bar.modulate = Color(0.4, 1.0, 1.0)
	elif running:
		fight_state_label.text = "鱼状态：冲刺中！松开左键泄力"
		fight_state_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		fish_stamina_bar.modulate = Color(0.75, 0.6, 1.0)
	else:
		fight_state_label.text = "鱼状态：歇息中 · 按住左键收线"
		fight_state_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
		fish_stamina_bar.modulate = Color(0.75, 0.6, 1.0)

func _on_tension(t: float, p: float, _n: String) -> void:
	if fight_panel.visible:
		_refresh_tension(t, p)

func _refresh_tension(t: float, p: float) -> void:
	tension_bar.value = clampf(t, 0.0, 1.0)
	progress_bar.value = clampf(p, 0.0, 1.0)
	# 张力配色（与 FishingGear.break_threshold 对齐）：
	#   绿 0.0~0.62（安全）/ 黄 0.62~0.80（偏高，准备松手）
	#   红 >0.80（危险，即将断线）/ 断线阈值 0.92+（见 Gear）。红区给足可见缓冲。
	if t > 0.80:
		tension_bar.modulate = Color(1.0, 0.25, 0.2)
		tension_hint.text = "⚠ 张力过高！松开左键泄力，否则断线！"
		tension_hint.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
	elif t > 0.62:
		tension_bar.modulate = Color(1.0, 0.8, 0.2)
		tension_hint.text = "张力偏高：准备松手（鱼可能冲刺）"
		tension_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	elif t < 0.18:
		tension_bar.modulate = Color(0.6, 0.7, 0.9)
		tension_hint.text = "张力偏低：按住左键收线"
		tension_hint.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	else:
		tension_bar.modulate = Color(0.35, 0.95, 0.45)
		tension_hint.text = "✓ 张力适中（绿区）：保持住，鱼冲刺时再松手"
		tension_hint.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))

func _on_catch_card(data: Dictionary) -> void:
	card_panel.visible = true
	card_title.text = "钓到：%s！" % str(data.get("name", "鱼"))
	card_info.text = "体长 %.0f cm  |  体重 %.2f kg  |  +%d 钓鱼经验" % [
		float(data.get("length_cm", 0.0)),
		float(data.get("weight_kg", 0.0)),
		int(data.get("xp", 0))
	]
	# 程序化鱼模型预览：species -> anatomy_id 取 Tidewater 外形原型，实时生成带顶点色的鱼网格
	var sid: String = str(data.get("species", ""))
	var aid: String = "silverside"
	var sp: FishSpecies = FishDatabase.species_by_id(sid)
	if sp != null and sp.anatomy_id != "":
		aid = sp.anatomy_id
	var gen := FishMeshGen.new()
	var mesh: ArrayMesh = gen.build_by_id(aid)
	if mesh != null:
		card_fish_mesh.mesh = mesh
		_fish_spin = 0.0
		card_fish_mesh.rotation = Vector3(0.12, 0.0, 0.0)
	card_cooler.text = "  已入营地仓库  |  按 P 打开钓鱼手册看图鉴"
	_card_timer = 4.5

func _on_ended() -> void:
	# 入护卡由 _process 里的计时器自动隐藏；这里先收掉搏鱼 HUD
	fight_panel.visible = false

# =========================================================
# 钓鱼手册
# =========================================================
func toggle_panel() -> void:
	if not FishingSystem.is_idle():
		EventBus.toast.emit("钓鱼中不能翻手册")
		return
	_book_open = not _book_open
	book_panel.visible = _book_open
	if _book_open:
		_refresh_book()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif Dialogue == null or not Dialogue.active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _refresh_book() -> void:
	if book_list == null:
		return
	for c in book_list.get_children():
		c.queue_free()
	var total: int = FishingSystem.total_caught()
	var cooler: int = FishingSystem.cooler_count()
	var cap: int = FishingGear.cooler_capacity()
	book_stats.text = "累计渔获 %d 尾  |  营地仓库渔获 %d / %d  |  钓鱼经验 %d" % [
		total, cooler, cap, FishingSystem.fishing_xp]

	var h1 := Label.new(); h1.text = "— 图鉴 —"
	h1.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	book_list.add_child(h1)
	for sp in FishDatabase.all_species():
		var e: Dictionary = FishingSystem.log_entry(sp.id)
		var line: String
		if e.is_empty():
			line = "? %s  （未发现）" % sp.display_name
		else:
			line = "%s  ×%d  最大 %.0fcm" % [sp.display_name, int(e["count"]), float(e["best_len"])]
		var l := Label.new(); l.text = line
		l.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0) if not e.is_empty() else Color(0.5, 0.5, 0.55))
		l.add_theme_font_size_override("font_size", 14)
		book_list.add_child(l)

	var h2 := Label.new(); h2.text = "— 装备升级（点击升级，扣钓鱼经验）—"
	h2.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	book_list.add_child(h2)
	for kind in GEAR_NAMES.keys():
		var row := HBoxContainer.new(); book_list.add_child(row)
		var lv: int = _gear_level(kind)
		var cost: int = FishingGear.next_cost(kind)
		var info: String = "%s  Lv%d" % [GEAR_NAMES[kind], lv]
		if cost < 0:
			info += "  (已满级)"
		else:
			info += "  → Lv%d  (-%d经验)" % [lv + 1, cost]
		var lab := Label.new(); lab.text = info
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.add_theme_color_override("font_color", Color.WHITE)
		row.add_child(lab)
		var btn := Button.new(); btn.text = "升级"
		btn.disabled = (cost < 0)
		btn.custom_minimum_size = Vector2(64, 30)
		var k: String = kind
		btn.pressed.connect(func(): FishingGear.upgrade(k))
		row.add_child(btn)

func _gear_level(kind: String) -> int:
	match kind:
		"rod": return FishingGear.rod_level
		"reel": return FishingGear.reel_level
		"line": return FishingGear.line_level
		"hold": return FishingGear.hold_level
		"fishfinder": return FishingGear.fishfinder_level
		"nightlight": return FishingGear.nightlight_level
	return 0

func _refresh_book_if_open(_x = null) -> void:
	if _book_open:
		_refresh_book()

# =========================================================
# 输入 / 帧循环
# =========================================================
func _unhandled_input(event) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_P:
			toggle_panel()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and _book_open:
			toggle_panel()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _card_timer > 0.0:
		_card_timer -= delta
		if _card_timer <= 0.0:
			card_panel.visible = false
	if card_panel.visible and card_fish_mesh != null and card_fish_mesh.mesh != null:
		_fish_spin += delta * 0.5
		card_fish_mesh.rotation = Vector3(0.12, _fish_spin, 0.0)
	_position()

func _position() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var vx: float = vp.size.x
	var vy: float = vp.size.y
	if fight_panel.visible:
		fight_panel.reset_size()
		fight_panel.position = Vector2(vx * 0.5 - fight_panel.size.x * 0.5, vy - 320.0)
	if card_panel.visible:
		card_panel.reset_size()
		card_panel.position = Vector2(vx * 0.5 - card_panel.size.x * 0.5, vy * 0.28)
	if book_panel.visible:
		book_panel.reset_size()
		book_panel.position = Vector2(vx * 0.5 - book_panel.size.x * 0.5, vy * 0.5 - book_panel.size.y * 0.5)
	if hint_label != null:
		hint_label.position = Vector2(vx - 120.0, vy - 26.0)
