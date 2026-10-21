extends Node3D
## 引导脚本（唯一手写 .tscn 的根）。职责：
## 1) 注册输入动作（避免手写 project.godot 的 [input_map]，更稳）
## 2) 实例化各块：World / Player / HUD
## 各块之间是独立脚本 + 通过 EventBus 通信，增删块不动这里以外的代码。

func _ready() -> void:
	_setup_input()

	var world = Node3D.new()
	world.name = "World"
	world.set_script(load("res://world/world.gd"))
	add_child(world)
	GameManager.world = world
	world.ensure_built()   # 同步铺好世界（地形/营地等），再取出生点，避免 await 卡死导致灰黑空屏

	var player := CharacterBody3D.new()
	player.name = "Player"
	player.set_script(load("res://player/player.gd"))
	player.position = world.call("get_spawn_position")
	add_child(player)
	GameManager.player = player

	# 钓鱼测试起步装备：鱼竿 + 鱼饵（方便立刻试玩新钓鱼；已有则不再重复给）
	if not Inventory.has("fishing_rod", 1):
		Inventory.add_item("fishing_rod", 1)
	if not Inventory.has("bait", 1):
		Inventory.add_item("bait", 8)
	# 注：木门已移出可建造列表；房子(house)取而代之，作为营地居所。

	var hud := Control.new()
	hud.name = "HUD"
	hud.set_script(load("res://ui/hud.gd"))
	add_child(hud)

	# 动物由 CreatureSpawner 统一管理（初始种群 + 定时补员）。
	# 复用 RPG_Character 身体，物种/体型/属性/掉落均数据驱动。
	CreatureSpawner.initial_populate()

	# 开局先进入主菜单（冻结游戏，点击开始后再放开）
	if Menus.has_method("show_main_menu"):
		Menus.show_main_menu()

func _setup_input() -> void:
	_add_action("move_forward", KEY_W)
	_add_action("move_back", KEY_S)
	_add_action("move_left", KEY_A)
	_add_action("move_right", KEY_D)
	_add_action("jump", KEY_SPACE)
	_add_action("sprint", KEY_SHIFT)
	_add_action("interact", KEY_E)

func _add_action(name: String, keycode: int) -> void:
	if InputMap.has_action(name):
		return
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	InputMap.add_action(name)
	InputMap.action_add_event(name, ev)
