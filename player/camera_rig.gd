extends Node3D
## 第一/第三人称相机支架。Player 写 yaw/pitch，这里做平滑 + 模式切换 + 第三人称碰撞。
##
## 第三人称：相机挂在 SpringArm3D > CamMount 之下，由 SpringArm3D 每帧做碰撞检测并
##   自动回缩（撞墙/撞地时把相机拉近），不要再手动设 camera.position（会被覆盖）。
## 第一人称：把相机 reparent 回本节点(CameraPivot) 并固定在眼前位置，同时隐藏 SpringArm
##   的碰撞（相机已贴头，无需回缩）。

var target_yaw := 0.0
var target_pitch := 0.0
var first_person := false

# 第一人称相机相对 pivot 的本地坐标（眼前、略低于头顶）
const FP_POS := Vector3(0, 0.25, 0.0)
# 第三人称时相机相对 CamMount 的抬高量（与 player.gd 创建时一致）
const TP_MOUNT_OFFSET := Vector3(0, 0.6, 0.0)
# 第三人称视线「上抬」偏置（弧度，≈4°）。
# 作用：把角色压到画面下半部，使屏幕正中心的准星落在角色「前方」，而不是压在头顶。
# 因为准星与交互射线都取自「相机正前(-Z)」，这里抬的是视线本身 → 不破坏「所见即所瞄」。
# 调参：0.0=不抬、0.035≈2°、0.0698≈4°、0.105≈6°（越大角色越靠下）。
const TP_VIEW_LIFT := 0.0698

var _camera: Camera3D = null
var _spring: SpringArm3D = null
var _mount: Node3D = null
var _was_fp := false

func _ready() -> void:
	_spring = get_node_or_null("SpringArm3D")
	_mount = get_node_or_null("SpringArm3D/CamMount")
	_camera = get_node_or_null("SpringArm3D/CamMount/Camera3D")
	# 默认第三人称：应用视线上抬偏置（第一人称由模式切换分支清零）。
	if _camera != null and not first_person:
		_camera.rotation = Vector3(TP_VIEW_LIFT, 0.0, 0.0)

func _process(delta: float) -> void:
	# 跟随玩家：XZ 精确（角色居中），Y 平滑吸收地形抖动，避免镜头上下晃。
	var pl := get_tree().get_first_node_in_group("player")
	if pl != null:
		global_position.x = pl.global_position.x
		global_position.z = pl.global_position.z
		var target_y: float = pl.global_position.y + 1.4
		global_position.y = lerp(global_position.y, target_y, 1.0 - exp(-12.0 * delta))
	# 旋转跟随收紧（速率 14→22），消除“飘忽/晃动”的迟滞感。
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-22.0 * delta))
	rotation.x = lerp_angle(rotation.x, target_pitch, 1.0 - exp(-22.0 * delta))
	if _camera == null:
		return

	# 仅在模式切换瞬间处理相机父子关系 / SpringArm 可见性，避免每帧 reparent。
	if first_person != _was_fp:
		_was_fp = first_person
		if first_person:
			if _camera.get_parent() != self:
				_camera.reparent(self, false)
			_camera.rotation = Vector3.ZERO          # 第一人称：视线不抬，正对前方
			if _spring != null:
				_spring.visible = false
		else:
			if _mount != null and _camera.get_parent() != _mount:
				_camera.reparent(_mount, false)
				_camera.position = TP_MOUNT_OFFSET   # 还原第三人称抬高
			_camera.rotation = Vector3(TP_VIEW_LIFT, 0.0, 0.0)   # 第三人称：视线上抬，角色落到画面下半部
			if _spring != null:
				_spring.visible = true

	# 第一人称：手动把相机固定在眼前；第三人称：交给 SpringArm3D 管理（不碰 position）。
	if first_person:
		_camera.position = FP_POS
