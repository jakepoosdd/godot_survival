extends Control
## 底部快捷栏中的单个快捷槽（1 / 2）。大小与热栏按钮一致（64×64）。
## 把背包里的物品（如食物）右键放进这里，按对应数字键或左键即可快速使用；右键本槽清空。

signal use_pressed
signal clear_pressed

var slot_index: int = 0
var key_text: String = "1"
var item_id: String = ""

var _icon: TextureRect
var _name: Label
var _count: Label
var _key: Label
var _hint: Label

const BG := Color(0.1, 0.12, 0.18, 0.92)
const BG_FILL := Color(0.15, 0.18, 0.28, 0.96)
const BORDER := Color(0.32, 0.37, 0.48, 0.85)
const BORDER_FILL := Color(1.0, 0.85, 0.3, 1.0)
const KEY_COLOR := Color(1.0, 0.85, 0.3)
const COUNT_COLOR := Color(1.0, 0.9, 0.35)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(64, 64)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(34, 34)
	_icon.position = Vector2(15, 6)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_icon)

	_name = Label.new()
	_name.position = Vector2(2, 42)
	_name.size = Vector2(60, 14)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_font_size_override("font_size", 10)
	_name.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	add_child(_name)

	_count = Label.new()
	_count.position = Vector2(2, 54)
	_count.size = Vector2(60, 10)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.add_theme_font_size_override("font_size", 11)
	_count.add_theme_color_override("font_color", COUNT_COLOR)
	add_child(_count)

	_key = Label.new()
	_key.text = key_text
	_key.position = Vector2(44, 2)
	_key.size = Vector2(16, 16)
	_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_key.add_theme_font_size_override("font_size", 12)
	_key.add_theme_color_override("font_color", KEY_COLOR)
	add_child(_key)

	_hint = Label.new()
	_hint.text = "空"
	_hint.position = Vector2(0, 22)
	_hint.size = Vector2(64, 18)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	add_child(_hint)

	# 子控件设为 IGNORE，让点击落到本槽的 gui_input
	for c in get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	gui_input.connect(_on_gui)
	refresh()

func _on_gui(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			use_pressed.emit()
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			clear_pressed.emit()

func assign(id: String) -> void:
	item_id = id
	refresh()

func refresh() -> void:
	if item_id == "" or item_id == null:
		_icon.visible = false
		_name.visible = false
		_count.visible = false
		_hint.visible = true
		queue_redraw()
		return
	var it = ItemDatabase.get_item(item_id)
	var nm: String = it.display_name if it != null else item_id
	if nm.length() > 5:
		nm = nm.substr(0, 5) + "…"
	_name.text = nm
	var cnt: int = Inventory.count(item_id)
	_count.text = "×%d" % cnt
	if it != null and it.icon != null:
		_icon.texture = it.icon
	else:
		_icon.texture = ItemIcons.icon_for(item_id)
	_icon.visible = true
	_name.visible = true
	_count.visible = true
	_hint.visible = false
	queue_redraw()

func _draw() -> void:
	var filled: bool = (item_id != "" and item_id != null)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_FILL if filled else BG
	sb.set_corner_radius_all(9)
	sb.border_color = BORDER_FILL if filled else BORDER
	sb.set_border_width_all(2 if filled else 1)
	draw_style_box(sb, Rect2(0, 0, size.x, size.y))
