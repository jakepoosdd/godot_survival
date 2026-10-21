extends Node
## 对话系统（Autoload: Dialogue）。start(npc, lines, opts) 开始；advance() 推进到下一句；end() 结束。
## HUD 监听 dialogue_started / dialogue_line / dialogue_ended 渲染对话框。对话期间释放鼠标以便点击推进。

signal dialogue_started(npc_name: String, lines: Array, options: Array)
signal dialogue_line(npc_name: String, text: String)
signal dialogue_ended()

var active := false
var _npc := ""
var _lines: Array = []
var _opts: Array = []
var _idx := 0

func start(npc_name: String, lines: Array, options: Array = []) -> void:
	if active:
		return
	active = true
	_npc = npc_name
	_lines = lines
	_opts = options
	_idx = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	dialogue_started.emit(_npc, _lines, _opts)

## 推进到下一句。返回 false 表示对话已结束。
func advance() -> bool:
	if not active:
		return false
	_idx += 1
	if _idx >= _lines.size():
		end()
		return false
	dialogue_line.emit(_npc, str(_lines[_idx]))
	return true

func end() -> void:
	if not active:
		return
	active = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	dialogue_ended.emit()

func current_line() -> String:
	if _idx < _lines.size():
		return str(_lines[_idx])
	return ""
