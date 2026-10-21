extends Control
## 底部快捷栏按钮：自绘矢量图标 + 名称 + 快捷键提示，不依赖任何外部图片资源。
## 用法：设置 icon_kind / key_hint / label_text，connect pressed 信号即可。

signal pressed

var icon_kind: String = "inventory"   # inventory | build | tasks | skills | craft
var key_hint: String = "I"
var label_text: String = "背包"

var _active := false

var _name_label: Label
var _key_label: Label

# 配色
const BG_NORMAL := Color(0.1, 0.12, 0.18, 0.92)
const BG_ACTIVE := Color(0.2, 0.24, 0.34, 0.97)
const BORDER_NORMAL := Color(0.32, 0.37, 0.48, 0.85)
const BORDER_ACTIVE := Color(1.0, 0.85, 0.3, 1.0)
const ICON_NORMAL := Color(0.82, 0.86, 0.96)
const ICON_ACTIVE := Color(1.0, 0.92, 0.6)
const KEY_COLOR := Color(1.0, 0.85, 0.3)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(64, 64)
	_name_label = Label.new()
	_name_label.text = label_text
	_name_label.position = Vector2(0, 44)
	_name_label.size = Vector2(64, 18)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 11)
	add_child(_name_label)
	_key_label = Label.new()
	_key_label.text = key_hint
	_key_label.position = Vector2(46, 2)
	_key_label.add_theme_color_override("font_color", KEY_COLOR)
	_key_label.add_theme_font_size_override("font_size", 12)
	add_child(_key_label)
	_refresh_label_colors()
	gui_input.connect(_on_gui)

func _on_gui(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()

func set_active(b: bool) -> void:
	if _active != b:
		_active = b
		queue_redraw()
		_refresh_label_colors()

func _refresh_label_colors() -> void:
	if _name_label == null:
		return
	var c := ICON_ACTIVE if _active else ICON_NORMAL
	_name_label.add_theme_color_override("font_color", c)

func _draw() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_ACTIVE if _active else BG_NORMAL
	sb.set_corner_radius_all(9)
	sb.border_color = BORDER_ACTIVE if _active else BORDER_NORMAL
	sb.set_border_width_all(2 if _active else 1)
	draw_style_box(sb, Rect2(0, 0, size.x, size.y))
	var col := ICON_ACTIVE if _active else ICON_NORMAL
	_draw_icon(icon_kind, col)

func _draw_icon(kind: String, col: Color) -> void:
	match kind:
		"inventory": _draw_backpack(col)
		"build": _draw_hammer(col)
		"tasks": _draw_clipboard(col)
		"skills": _draw_star(col)
		"craft": _draw_gear(col)
		_: draw_circle(Vector2(32, 22), 10, col)

# 背包：主体 + 顶盖 + 搭扣
func _draw_backpack(col: Color) -> void:
	draw_rect(Rect2(19, 17, 26, 22), col, true)
	draw_rect(Rect2(19, 11, 26, 8), col * 0.7, true)
	draw_rect(Rect2(29, 17, 6, 7), Color(0.15, 0.16, 0.2), true)
	draw_line(Vector2(32, 19), Vector2(32, 39), Color(0.15, 0.16, 0.2), 2.0)

# 建造：锤子
func _draw_hammer(col: Color) -> void:
	draw_line(Vector2(22, 40), Vector2(43, 18), col, 4.0)
	draw_rect(Rect2(37, 11, 15, 8), col, true)
	draw_rect(Rect2(37, 11, 5, 12), col, true)

# 任务：剪贴板 + 横线
func _draw_clipboard(col: Color) -> void:
	draw_rect(Rect2(18, 14, 28, 26), col, true)
	draw_rect(Rect2(26, 8, 12, 8), col * 0.8, true)
	draw_line(Vector2(23, 22), Vector2(41, 22), BG_NORMAL, 2.0)
	draw_line(Vector2(23, 28), Vector2(41, 28), BG_NORMAL, 2.0)
	draw_line(Vector2(23, 34), Vector2(35, 34), BG_NORMAL, 2.0)

# 技能：五角星
func _draw_star(col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 10
	for i in n:
		var r := 15.0 if i % 2 == 0 else 6.5
		var a := -PI / 2.0 + float(i) * PI / float(n)
		pts.append(Vector2(32 + cos(a) * r, 23 + sin(a) * r))
	draw_polygon(pts, [col])

# 制作：齿轮（中心圆 + 8 颗齿）
func _draw_gear(col: Color) -> void:
	var c := Vector2(32, 23)
	draw_circle(c, 10, col)
	for i in 8:
		var a := float(i) * TAU / 8.0
		var p := c + Vector2(cos(a), sin(a)) * 14.0
		draw_circle(p, 3.2, col)
	draw_circle(c, 4, BG_NORMAL)
