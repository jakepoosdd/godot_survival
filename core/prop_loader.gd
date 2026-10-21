extends Node
## 程序化道具加载器（Autoload: PropLoader）。
##
## 用途：把 TRELLIS2 生成的道具 GLB 在运行时导入并规范化（缩放到目标高度、落到地面、居中），
## 供 world.gd 的环境物件（帐篷/篝火/码头）与手持物（鱼竿）复用。
##
## 为什么既用 load() 也保留 GLTFDocument 回退：
##   PCK 内 .glb 已被导入成 .scn，load() 走 import remap 最稳且自带贴图；
##   GLTFDocument 仅作为 user:// MOD 等未预导入 glb 的磁盘兜底。
##
## 用法：
##   var node := PropLoader.spawn("res://assets/props/tent.glb", 2.4, true)
##   if node != null: add_child(node)

var _CACHE: Dictionary = {}

## 用资源管线 load() 导入 GLB（PCK 内 .glb 已被导入成 .scn，带贴图，最稳），失败回退 GLTFDocument。
func _import(scene_path: String) -> PackedScene:
	if _CACHE.has(scene_path):
		return _CACHE[scene_path]
	var res := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if res is PackedScene:
		_CACHE[scene_path] = res
		return res
	# 回退：GLTFDocument 运行时导入（user:// MOD 等未预导入的 glb，磁盘可用）
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := _gltf_load(gltf, state, scene_path)
	if err != OK:
		push_warning("[PropLoader] GLB 导入失败: " + scene_path)
		return null
	var root: Node = gltf.generate_scene(state)
	if root == null:
		push_warning("[PropLoader] GLB 生成场景失败: " + scene_path)
		return null
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_warning("[PropLoader] GLB 打包失败: " + scene_path)
		return null
	_CACHE[scene_path] = packed
	return packed

## GLTFDocument 兜底加载入口（仅当 load() 失败时调用，例如 user:// MOD 未预导入的磁盘 glb）。
## ⚠️ 导出包(PCK)内 .glb 源文件并不以可读字节存在，必须先由 load() 走 import remap 加载。
func _gltf_load(gltf: GLTFDocument, state: GLTFState, scene_path: String) -> int:
	var err := gltf.append_from_file(scene_path, state)
	if err == OK:
		return OK
	if FileAccess.file_exists(scene_path):
		var bytes := FileAccess.get_file_as_bytes(scene_path)
		if bytes.size() > 0:
			return gltf.append_from_buffer(bytes, scene_path, state)
	return err

## 实例化道具并规范化几何。
##   target_height > 0: 把模型等比缩放到该世界高度（米）
##   drop_to_ground: 把「最低点」对齐到 y=0（实例根的原点即落脚点，方便调用方直接放地面）
##   center_xz: 把水平包围盒中心对齐到原点
##   brighten > 0: 给所有材质叠加 albedo 提亮（TRELLIS 生成的贴图普遍偏暗，户外阳光下会糊成剪影）
## 返回 Node3D（内含实际网格），失败返回 null。
func spawn(scene_path: String, target_height: float = 0.0,
		drop_to_ground: bool = true, center_xz: bool = true,
		brighten: float = 0.0) -> Node3D:
	var packed := _import(scene_path)
	if packed == null:
		return null
	var holder := Node3D.new()
	holder.name = scene_path.get_file().get_basename()
	var inst: Node = packed.instantiate()
	holder.add_child(inst)
	_normalize(holder, target_height, drop_to_ground, center_xz)
	if brighten > 0.0:
		_brighten(holder, brighten)
	return holder

## 遍历所有 MeshInstance3D，给其材质做提亮。
## TRELLIS 生成的 GLB 通常是「白 albedo_color + 偏暗的 albedo_texture」，所以单纯乘 albedo_color 无效；
## 这里改用 emission_texture（复用 albedo 贴图）给材质加一点自发光，把阴影面也抬起来，暗贴图才不会糊成剪影。
## 复制材质再改，避免污染 PackedScene 缓存里共享的资源。
func _brighten(root: Node, amount: float) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			for si in range(mi.mesh.get_surface_count()):
				var src: Material = mi.get_active_material(si)
				if src is StandardMaterial3D:
					var sm := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
					# 1) albedo_color 也提一点（对无贴图/浅色部分有效）
					var c := sm.albedo_color
					sm.albedo_color = Color(
						min(c.r + amount * 0.15, 1.0),
						min(c.g + amount * 0.15, 1.0),
						min(c.b + amount * 0.15, 1.0), c.a)
					# 2) 自发光：复用 albedo 贴图（有则用贴图，无则用 albedo_color），给暗贴图补光
					sm.emission_enabled = true
					sm.emission = Color(1, 1, 1)
					sm.emission_energy_multiplier = amount * 0.45
					if sm.albedo_texture != null:
						sm.emission_texture = sm.albedo_texture
					# 3) 降金属度、抬粗糙度，避免暗金属变成黑镜
					sm.metallic = max(sm.metallic - amount * 0.6, 0.0)
					sm.roughness = max(sm.roughness, 0.7)
					mi.set_surface_override_material(si, sm)

## 对一个已摆放好的节点做包围盒规范化（就地修改 inst 的 transform）。
func _normalize(node: Node3D, target_height: float,
		drop_to_ground: bool, center_xz: bool) -> void:
	var aabb := _mesh_aabb(node)
	if aabb.size == Vector3.ZERO:
		return
	var size := aabb.size
	# 等比缩放到目标高度
	if target_height > 0.0 and size.y > 0.0001:
		var s := target_height / size.y
		node.scale = Vector3(s, s, s)
		aabb = _mesh_aabb(node)
		size = aabb.size
	# 水平居中
	var offset := Vector3.ZERO
	if center_xz:
		offset.x = -(aabb.position.x + aabb.size.x * 0.5)
		offset.z = -(aabb.position.z + aabb.size.z * 0.5)
	# 落地面：最低点抬到 0
	if drop_to_ground:
		offset.y = -aabb.position.y
	node.position += offset

## 递归求所有 MeshInstance3D 的合并 AABB（世界变换后的）。
func _mesh_aabb(root: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var box := mi.get_aabb()
			var xf := _global_xf(mi, root)
			var wbox := xf * box
			if first:
				out = wbox
				first = false
			else:
				out = out.merge(wbox)
	return out

## 计算 child 相对 root 的累计变换（root 自身视为单位）。
func _global_xf(child: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = child
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
