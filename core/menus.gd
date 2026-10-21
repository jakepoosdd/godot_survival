extends Node
## 菜单系统（Autoload: Menus）：主菜单 / 暂停 / 设置。
## 用 get_tree().paused 冻结游戏逻辑；菜单控件 process_mode=ALWAYS 仍可交互。
## 接管 Esc：游戏中按 Esc 打开暂停菜单；对话/烹饪进行中时让位给对应系统。

var _layer: CanvasLayer
var _main: Control
var _pause: Control
var _settings: Control
var _char_panel: Control
var _char_vbox: VBoxContainer
var _char_label: Label
var _pause_status: Label
var _saves: Control
var _saves_list: VBoxContainer
var _saves_status: Label
var _saves_mode: String = "pause"
var _started := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_layer.layer = 128
	add_child(_layer)

	_main = _panel("主菜单")
	_pause = _panel("已暂停")
	_settings = _panel("设置")
	_char_panel = _panel("选择角色")
	_saves = _panel("存档栏")
	_layer.add_child(_main)
	_layer.add_child(_pause)
	_layer.add_child(_settings)
	_layer.add_child(_char_panel)
	_layer.add_child(_saves)
	_main.visible = false
	_pause.visible = false
	_settings.visible = false
	_char_panel.visible = false
	_saves.visible = false

	_build_main()
	_build_pause()
	_build_settings()
	_build_char_select()
	_build_saves()

func _panel(title_text: String) -> Control:
	var c := Control.new()
	c.process_mode = Node.PROCESS_MODE_ALWAYS
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(bg)
	var title := Label.new()
	title.text = title_text
	title.add_theme_color_override("font_color", Color(0.95, 0.92, 0.8))
	title.add_theme_font_size_override("font_size", 34)
	title.anchor_left = 0.5
	title.anchor_right = 0.5
	title.position = Vector2(-80, 70)
	title.add_theme_constant_override("offset_left", -200)
	c.add_child(title)
	return c

## 居中竖向按钮容器
func _vbox(parent: Control, top: float) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.position = Vector2(-120, top)
	vb.size = Vector2(240, 0)
	vb.add_theme_constant_override("separation", 10)
	parent.add_child(vb)
	return vb

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 44)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	return b

func _build_main() -> void:
	var vb := _vbox(_main, 160)
	vb.add_child(_button("开始游戏", _on_start))
	vb.add_child(_button("选择存档", func(): _open_saves("main")))
	vb.add_child(_button("选择角色", _open_char_select))
	vb.add_child(_button("设置", _open_settings))
	var hint := Label.new()
	hint.text = "WASD 移动 | 左键攻击 | E 交互 | C 制作 | B 建造 | I 背包 | L 技能 | U 任务 | K 成就"
	hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	hint.add_theme_font_size_override("font_size", 13)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(520, 0)
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.position = Vector2(-260, 360)
	_main.add_child(hint)

func _build_pause() -> void:
	var vb := _vbox(_pause, 150)
	vb.add_child(_button("继续游戏", _resume))
	vb.add_child(_button("存档管理", func(): _open_saves("pause")))
	vb.add_child(_button("设置", _open_settings))
	vb.add_child(_button("退出到主菜单", _to_main))
	vb.add_child(_button("退出游戏", _on_quit))
	_pause_status = Label.new()
	_pause_status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_pause_status.add_theme_font_size_override("font_size", 15)
	_pause_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_status.anchor_left = 0.5
	_pause_status.anchor_right = 0.5
	_pause_status.position = Vector2(-120, 430)
	_pause_status.size = Vector2(240, 24)
	_pause.add_child(_pause_status)

func _build_settings() -> void:
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.position = Vector2(-200, 140)
	vb.size = Vector2(400, 0)
	vb.add_theme_constant_override("separation", 14)
	_settings.add_child(vb)

	vb.add_child(_slider("主音量", AudioManager.master_volume, AudioManager.set_master))
	vb.add_child(_slider("音效音量", AudioManager.sfx_volume, AudioManager.set_sfx))
	vb.add_child(_slider("音乐音量", AudioManager.music_volume, AudioManager.set_music))

	var fs_btn := _button("切换全屏", _toggle_fullscreen)
	vb.add_child(fs_btn)
	var back := _button("返回", _close_settings)
	vb.add_child(back)

func _slider(label_text: String, value: float, setter: Callable) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var lab := Label.new()
	lab.text = label_text
	lab.custom_minimum_size = Vector2(110, 0)
	lab.add_theme_color_override("font_color", Color.WHITE)
	hb.add_child(lab)
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.value = value
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sl)
	var val := Label.new()
	val.custom_minimum_size = Vector2(42, 0)
	val.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	val.text = "%d%%" % int(value * 100.0)
	hb.add_child(val)
	sl.value_changed.connect(func(v: float):
		setter.call(v)
		val.text = "%d%%" % int(v * 100.0)
	)
	return hb

# =========================================================
# 角色选择（老滚式：选了 MOD 主角就变）
# =========================================================
func _build_char_select() -> void:
	var scroll := ScrollContainer.new()
	scroll.anchor_left = 0.5
	scroll.anchor_right = 0.5
	scroll.position = Vector2(-180, 120)
	scroll.size = Vector2(360, 380)
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_char_panel.add_child(scroll)
	_char_vbox = VBoxContainer.new()
	_char_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_char_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_char_vbox)
	var back := _button("返回", _close_char_select)
	back.position = Vector2(-120, 520)
	_char_panel.add_child(back)

## 该角色是否可在「换角色」中切换：
##   - 男主(ch23)及玩家自导入 MOD 始终可选；
##   - 伙伴(maria/erika/arissa/kachujin/ch46)需已招募/召唤才能选。
func _char_selectable(def: Dictionary) -> bool:
	var id: String = str(def.get("id", ""))
	if PartyManager.PARTNER_IDS.has(id):
		return PartyManager.is_recruited(id)
	return true

func _refresh_char_list() -> void:
	for c in _char_vbox.get_children():
		c.queue_free()
	_char_label = Label.new()
	_char_label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.8))
	_char_label.add_theme_font_size_override("font_size", 16)
	_char_vbox.add_child(_char_label)
	var sel := CharacterRegistry.get_selected_index()
	for i in CharacterRegistry.get_characters().size():
		var ch: Dictionary = CharacterRegistry.get_character(i)
		var ok := _char_selectable(ch)
		var mark := "✓ " if i == sel else ""
		if not ok:
			mark += "■ "
		var label := mark + str(ch["name"]) + ("" if ok else "（未召唤）")
		var b := _button(label, func(): _select_char(i))
		if not ok:
			b.disabled = true   # 未召唤的伙伴置灰不可点
		_char_vbox.add_child(b)
	_refresh_char_label()

func _refresh_char_label() -> void:
	var ch: Dictionary = CharacterRegistry.get_character(CharacterRegistry.get_selected_index())
	_char_label.text = "当前角色：" + str(ch["name"])

func _select_char(i: int) -> void:
	var ch: Dictionary = CharacterRegistry.get_character(i)
	if not _char_selectable(ch):
		EventBus.toast.emit("%s 尚未召唤，无法切换角色" % str(ch.get("name", "该角色")))
		return
	CharacterRegistry.set_selected(i)
	_refresh_char_list()
	# 即时换皮预览（主菜单背后已存在的 Player）
	if GameManager.player != null and GameManager.player.has_method("set_character"):
		GameManager.player.set_character(i)

func _open_char_select() -> void:
	CharacterRegistry.rescan()   # 拾取运行中新放入的 MOD
	# 安全兜底：若当前选中角色已不可切换（如未召唤的伙伴），回退到男主(ch23)
	var cur := CharacterRegistry.get_character(CharacterRegistry.get_selected_index())
	if not _char_selectable(cur):
		CharacterRegistry.set_selected(0)   # _all[0] 恒为 ch23（男主），始终可选
	_refresh_char_list()
	_main.visible = false
	_char_panel.visible = true

func _close_char_select() -> void:
	_char_panel.visible = false
	_main.visible = true

# =========================================================
# 控制
# =========================================================
func show_main_menu() -> void:
	_main.visible = true
	# 注意：不要在此重置 _started —— 否则从「退出到主菜单」回来再点开始会重新读档，
	# 覆盖掉本次会话中未存档的进度。_started 仅在首次「开始游戏」时由 _on_start 置真一次。
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true

func _on_start() -> void:
	# 仅在本次会话「首次开始」时读取存档栏 0，恢复进度；
	# 之后从「退出到主菜单」再点开始只会恢复内存中的会话，不会覆盖未存档的进度。
	if not _started:
		_started = true
		if SaveManager.has_slot(0) and not SaveManager.load_slot(0):
			EventBus.toast.emit("读取存档失败，开始新游戏")
	_start_game()

# =========================================================
# 存档栏（多存档选择）
# =========================================================
func _build_saves() -> void:
	var outer := VBoxContainer.new()
	outer.anchor_left = 0.5
	outer.anchor_right = 0.5
	outer.position = Vector2(-290, 140)
	outer.size = Vector2(580, 0)
	outer.add_theme_constant_override("separation", 12)
	_saves.add_child(outer)

	var hint := Label.new()
	hint.text = "选择存档栏：读取可继续进度，存档可覆盖该栏。暂停时也能随时存。"
	hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	hint.add_theme_font_size_override("font_size", 13)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(580, 36)
	outer.add_child(hint)

	_saves_list = VBoxContainer.new()
	_saves_list.add_theme_constant_override("separation", 8)
	outer.add_child(_saves_list)

	_saves_status = Label.new()
	_saves_status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_saves_status.add_theme_font_size_override("font_size", 15)
	_saves_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_saves_status.custom_minimum_size = Vector2(580, 24)
	outer.add_child(_saves_status)

	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(240, 44)
	back.pressed.connect(_close_saves)
	outer.add_child(back)

func _open_saves(mode: String) -> void:
	_saves_mode = mode
	_saves_status.text = ""
	_main.visible = false
	_pause.visible = false
	_settings.visible = false
	_char_panel.visible = false
	_saves.visible = true
	_refresh_saves()

func _close_saves() -> void:
	_saves.visible = false
	if _saves_mode == "main":
		_main.visible = true
	else:
		_pause.visible = true

func _time_str(t: float) -> String:
	var total := int(t * 24.0)
	var hh := total % 24
	var mm := int((t * 24.0 - float(total)) * 60.0)
	return "%02d:%02d" % [hh, mm]

func _refresh_saves() -> void:
	for c in _saves_list.get_children():
		c.queue_free()
	for i in SaveManager.SAVE_SLOTS:
		var meta: Dictionary = SaveManager.slot_meta(i)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lab := Label.new()
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.add_theme_color_override("font_color", Color.WHITE)
		if meta["exists"]:
			lab.text = "存档栏 %d  —  第 %d 天  %s" % [i + 1, int(meta["day"]), _time_str(float(meta["time"]))]
		else:
			lab.text = "存档栏 %d  —  空" % (i + 1)
		row.add_child(lab)

		var load_btn := Button.new()
		load_btn.text = "读取" if _saves_mode == "pause" else "开始"
		load_btn.custom_minimum_size = Vector2(72, 36)
		load_btn.disabled = not meta["exists"]
		load_btn.pressed.connect(func(idx: int = i): _saves_load(idx))
		row.add_child(load_btn)

		var save_btn := Button.new()
		save_btn.text = "存档"
		save_btn.custom_minimum_size = Vector2(72, 36)
		save_btn.visible = (_saves_mode == "pause")
		save_btn.pressed.connect(func(idx: int = i): _saves_save(idx))
		row.add_child(save_btn)

		var del_btn := Button.new()
		del_btn.text = "删除"
		del_btn.custom_minimum_size = Vector2(72, 36)
		del_btn.disabled = not meta["exists"]
		del_btn.pressed.connect(func(idx: int = i): _saves_delete(idx))
		row.add_child(del_btn)

		_saves_list.add_child(row)

	if _saves_mode == "main":
		var ng := Button.new()
		ng.text = "新游戏（从初始状态开始）"
		ng.custom_minimum_size = Vector2(560, 44)
		ng.pressed.connect(_start_new_game)
		_saves_list.add_child(ng)

func _saves_save(i: int) -> void:
	var ok := SaveManager.save_slot(i)
	_saves_status.text = ("已存档到存档栏 %d ✓" % (i + 1)) if ok else "存档失败 ×"
	_refresh_saves()

func _saves_load(i: int) -> void:
	if not SaveManager.load_slot(i):
		_saves_status.text = "读取存档栏 %d 失败" % (i + 1)
		return
	if _saves_mode == "main":
		_start_game()
	else:
		_resume()

func _saves_delete(i: int) -> void:
	SaveManager.delete_slot(i)
	_saves_status.text = "已删除存档栏 %d" % (i + 1)
	_refresh_saves()

func _start_game() -> void:
	_main.visible = false
	_saves.visible = false
	get_tree().paused = false
	_started = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# 进入游戏即播放无版权循环背景音乐（文件缺失则静默跳过）
	AudioManager.play_music("feel_good_island_loop")

func _start_new_game() -> void:
	_start_game()

## 退出游戏：先自动存档，再完全退出进程。
func _on_quit() -> void:
	SaveManager.save_game()
	get_tree().quit()

func _open_pause() -> void:
	_pause.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true

func _resume() -> void:
	_pause.visible = false
	_settings.visible = false
	_saves.visible = false
	get_tree().paused = false
	if Dialogue == null or not Dialogue.active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _to_main() -> void:
	_pause.visible = false
	_settings.visible = false
	_saves.visible = false
	get_tree().paused = false
	show_main_menu()

func _open_settings() -> void:
	_settings.visible = true

func _close_settings() -> void:
	_settings.visible = false

func _toggle_fullscreen() -> void:
	var wm := DisplayServer.window_get_mode()
	if wm == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _unhandled_input(event) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# 设置面板优先关闭
		if _settings.visible:
			_close_settings()
			get_viewport().set_input_as_handled()
			return
		# 角色选择面板关闭
		if _char_panel.visible:
			_close_char_select()
			get_viewport().set_input_as_handled()
			return
		# 存档栏面板关闭（返回来源菜单）
		if _saves.visible:
			_close_saves()
			get_viewport().set_input_as_handled()
			return
		# 主菜单不响应 Esc
		if _main.visible:
			get_viewport().set_input_as_handled()
			return
		# 烹饪菜单打开时让位给 HUD
		if EventBus.cooking_menu_open:
			return
		# 商店/公告/成就面板打开时让位给 HUD 自行关闭
		if GameManager.shop_open or GameManager.bulletin_open or GameManager.ach_open:
			return
		# 对话进行中不打断（由 Dialogue 自行消费）
		if Dialogue != null and Dialogue.active:
			return
		# NPC 交互菜单/送礼面板打开时让位给 HUD 自行关闭
		if GameManager.interact_menu_open:
			return
		# 暂停 <-> 继续
		if _pause.visible:
			_resume()
		else:
			_open_pause()
		get_viewport().set_input_as_handled()
