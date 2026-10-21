extends MeshInstance3D
## 飞箭定向：每帧让箭面朝相机（看得见箭的贴图），同时让箭尖（本地 +Y，即贴图顶端）
## 指向目标，形成一个“飞出去指向敌人”的 3D 箭头，而不是跟着镜头翻转的纸片。
## 材质里已关闭 billboard，由这里手动构造朝向基。

var _target: Vector3 = Vector3.ZERO

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_cam := (cam.global_position - global_position)
	if to_cam.length_squared() < 0.0001:
		return
	to_cam = to_cam.normalized()
	# 目标方向，投影到与视线垂直的平面上，作为箭尖（本地 +Y）朝向
	var y_dir := (_target - global_position).normalized()
	y_dir = y_dir - to_cam * y_dir.dot(to_cam)   # 去掉视线方向分量
	if y_dir.length_squared() < 0.0001:
		y_dir = cam.global_transform.basis.y        # 退化时退回相机上方
	y_dir = y_dir.normalized()
	var x_dir := y_dir.cross(to_cam).normalized()   # 右 = 上 × 前
	# 本地基：X=x_dir, Y=y_dir(箭尖), Z=to_cam(面朝相机)
	basis = Basis(x_dir, y_dir, to_cam).orthonormalized()
