extends Node
## 交互系统（Layer 2）：从相机向前发射射线，命中带 interact() 的节点时记录为 current。
## 按 E 调用 current.interact(player)。只通过 EventBus.interactable_changed 通知 HUD 显示提示。

@export var reach := 10.0
var current: Node = null
var _had_target := false   # 上一帧是否对准过有效目标（用于失效后补一次清提示）
var _player: Node3D

func _ready() -> void:
	_player = get_parent() as Node3D

func _unhandled_input(event) -> void:
	# 建造模式下由 Building 系统接管 E 键（放置），此处跳过交互
	if GameManager.build_mode:
		return
	# NPC 交互菜单/送礼面板打开时，E 不再重复触发（避免叠加菜单）
	if GameManager.interact_menu_open:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		if current and current.has_method("interact"):
			current.interact(_player)

func _physics_process(_delta: float) -> void:
	# 相机已改为挂在场景根(top_level)，不再位于 player 之下，故用活动相机获取。
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var space_state := _player.get_world_3d().direct_space_state as PhysicsDirectSpaceState3D
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var to := from + dir * reach
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	# 第三人称相机在玩家身后，射线会先穿过玩家自己的碰撞胶囊 -> 排除玩家（及其子碰撞），
	# 否则命中的永远是玩家，导致永远无法选中前方资源/可交互物。
	q.exclude = [_player]
	var hit := space_state.intersect_ray(q) as Dictionary

	var new_target: Node = null
	if hit and hit.collider != null:
		# 射线命中的可能是资源节点的子碰撞体（如 Slavic 树预制体自带的碰撞网格），
		# 它自身没有 interact 方法 -> 沿父链向上找最近的带 interact 的祖先。
		new_target = _find_interactable(hit.collider)

	# ⚠️ Godot 4 坑：已 queue_free 的对象「== null」为 true。
	# 于是「上一帧目标被销毁(如拾取后 queue_free)、这一帧射线没命中」时：
	#   current 指向已释放节点，比较 new_target != current 得到 null != null = false，
	#   分支被跳过 -> interactable_changed("") 永不发射 -> HUD 交互提示残留
	#   （表现为「树枝捡完了，拾取树枝(E) 提示还在」）。
	# 故先用 is_instance_valid 判定失效并置空，失效时强制补发一次清提示。
	if not is_instance_valid(current):
		current = null
	if new_target != current:
		current = new_target
		_had_target = is_instance_valid(current)
		EventBus.interactable_changed.emit(current.get("prompt") if current else "")
	elif current == null and _had_target:
		_had_target = false
		EventBus.interactable_changed.emit("")

## 从命中碰撞体沿父链向上，找到最近的实现了 interact() 的节点。
func _find_interactable(from: Node) -> Node:
	var n: Node = from
	while n != null:
		if n.has_method("interact"):
			return n
		n = n.get_parent()
	return null
