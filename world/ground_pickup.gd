extends "res://inventory/interactable.gd"
## 地面拾取物 / 可挖点（一次性）。用于：
##  - 散落的树枝、石头：无需工具，是开局唯一的木材/石材来源；
##  - 可挖土堆：需铲子，挖出燧石 + 可食用根茎（食物）。
## 采集后从世界移除（queue_free）。
##
## 外观：石头用项目内的真实岩石模型（megakit 鹅卵石/小石），树枝用程序化生成的树枝网格，
## 都按统一目标尺寸归一化、落地、随机朝向。碰撞盒放大到 ~1m，便于交互射线命中（修「捡不起来」）。

@export var drops := {"stick": 1}        # 掉落（支持单物品或多物品）
@export var required_tool: String = ""    # 所需工具 id（空 = 无需工具）
@export var tool_name: String = ""        # 工具显示名
@export var visual: String = "stick"      # stick | stone | mound
@export var model_override: String = ""   # 可选：强制指定模型路径（覆盖默认池）

# 模型和场景缓存（同路径只 load 一次）
static var _model_cache: Dictionary = {}
static var _rng := RandomNumberGenerator.new()

# 石头模型池（项目内真实岩石模型，单位约 0.3~1m，加载时统一缩放到 STONE_TARGET）
const STONE_MODELS := [
	"res://assets/megakit/RockPath_Round_Small_1.gltf",
	"res://assets/megakit/RockPath_Round_Small_2.gltf",
	"res://assets/megakit/RockPath_Round_Small_3.gltf",
	"res://assets/megakit/Pebble_Round_1.gltf",
	"res://assets/megakit/Pebble_Round_2.gltf",
	"res://assets/megakit/Pebble_Round_4.gltf",
]
# 树枝模型（项目内无现成树枝模型 -> 默认走程序化树枝；若日后生成 branch.glb 则自动启用）
const STICK_MODEL := "res://assets/props/branch.glb"

const STONE_TARGET := 0.5    # 石头归一化后最长边 ≈ 0.5m
const STICK_TARGET := 0.95   # 树枝归一化后最长边 ≈ 0.95m
const MOUND_TARGET := 0.7    # 土堆归一化后最长边 ≈ 0.7m

func _ready() -> void:
	_rng.randomize()
	_build_visual()

func _build_visual() -> void:
	var model_path := model_override
	if model_path == "":
		if visual == "stone":
			model_path = STONE_MODELS[_rng.randi_range(0, STONE_MODELS.size() - 1)]
		elif visual == "stick":
			model_path = STICK_MODEL

	var center_y := 0.0
	var radius := 0.4

	var scene: PackedScene = _load_model(model_path) if model_path != "" else null
	if scene != null:
		var inst := scene.instantiate()
		add_child(inst)
		inst.rotation.y = _rng.randf() * TAU
		var info := _normalize(inst, _target_for(visual))
		center_y = info.center_y
		radius = info.radius
	elif visual == "stick":
		# 项目内无现成树枝模型 -> 程序化树枝（主干 + 三根侧枝），比原圆柱更像「树枝」
		var branch := _make_branch()
		add_child(branch)
		branch.rotation = Vector3(0.0, _rng.randf() * TAU, 1.45)  # 倒地 + 随机朝向
		var info := _normalize(branch, STICK_TARGET)
		center_y = info.center_y
		radius = info.radius
	else:
		# 石头/土堆缺模型时退回基础图元，保证不崩、仍可读
		var info := _build_primitive(visual)
		center_y = info.center_y
		radius = info.radius

	_add_collision(center_y, radius)

## 程序化树枝：一根上细下粗的主干 + 三根不同高度斜出的侧枝，统一放倒贴地。
func _make_branch() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.24, 0.13)
	mat.roughness = 1.0
	mat.metallic = 0.0
	# 主干（沿 +Y，长 0.95）
	root.add_child(_cyl_inst(mat, 0.055, 0.026, 0.95, Vector3(0.0, 0.475, 0.0)))
	# 侧枝：[高度, 长度, 与竖直夹角, 水平方位]
	var specs := [
		[0.30, 0.34, 1.05, 0.0],
		[0.52, 0.28, 1.25, 2.1],
		[0.70, 0.24, 1.15, 4.0],
	]
	for s in specs:
		var y: float = s[0]
		var ln: float = s[1]
		var ang: float = s[2]
		var ph: float = s[3]
		var outward := Vector3(cos(ph), 0.0, sin(ph))
		var d := (Vector3.UP * cos(ang) + outward * sin(ang)).normalized()
		var base := Vector3(0.0, y, 0.0)
		var mi := _cyl_inst(mat, 0.020, 0.008, ln, Vector3.ZERO)
		mi.transform = Transform3D(_basis_from_dir(d), base + d * (ln * 0.5))
		root.add_child(mi)
	return root

func _cyl_inst(mat: Material, r_top: float, r_bot: float, h: float, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 8
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	return mi

## 构造把 +Y 旋到方向 d 的基（用于让圆柱沿任意方向摆放）。
func _basis_from_dir(d: Vector3) -> Basis:
	var ref := Vector3.UP
	if absf(d.dot(ref)) > 0.99:
		ref = Vector3.RIGHT
	var x := ref.cross(d).normalized()
	var z := x.cross(d).normalized()
	return Basis(x, d, z)

func _target_for(v: String) -> float:
	if v == "stone": return STONE_TARGET
	if v == "stick": return STICK_TARGET
	if v == "mound": return MOUND_TARGET
	return 0.5

func _load_model(path: String) -> PackedScene:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if _model_cache.has(path):
		return _model_cache[path]
	var scn := load(path)
	if scn is PackedScene:
		_model_cache[path] = scn
		return scn
	return null

## 把模型归一化到目标尺寸、底部落到 pickup 本地 y=0（= 地形面），返回中心高度与水平半径。
func _normalize(inst: Node3D, target: float) -> Dictionary:
	var L := _local_aabb(inst)
	if L.size.length() < 0.0001 or target <= 0.0:
		return {"center_y": 0.2, "radius": 0.4}
	var max_dim := maxf(maxf(L.size.x, L.size.y), L.size.z)
	var s := target / max_dim
	inst.scale = Vector3(s, s, s)
	# 缩放后底部（最低点）回到 y=0
	inst.position.y = -L.position.y * s
	var center_y := L.size.y * 0.5 * s
	var radius := maxf(L.size.x, L.size.z) * 0.5 * s
	return {"center_y": center_y, "radius": radius}

## 递归求 root 下所有 MeshInstance3D 的合并包围盒（root 本地空间）。
func _local_aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var has := false
	var stack: Array = [root]
	var root_inv := root.global_transform.affine_inverse()
	while not stack.is_empty():
		var cur = stack.pop_back()
		if cur is MeshInstance3D and (cur as MeshInstance3D).mesh != null:
			var mi := cur as MeshInstance3D
			var ba := mi.get_aabb()
			if ba.size.length() < 0.0001:
				continue
			var world_a := mi.global_transform * ba
			var local_a := root_inv * world_a
			if has:
				merged = merged.merge(local_a)
			else:
				merged = local_a
				has = true
		for c in cur.get_children():
			stack.append(c)
	if not has:
		return AABB(Vector3.ZERO, Vector3(1, 1, 1))
	return merged

## 基础图元兜底（模型缺失时）：复刻原外观，但碰撞盒仍放大（见 _add_collision）。
func _build_primitive(v: String) -> Dictionary:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	var center_y := 0.2
	var radius := 0.4
	if v == "stick":
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05; cm.bottom_radius = 0.07; cm.height = 0.8
		mi.mesh = cm
		mat.albedo_color = Color(0.45, 0.30, 0.16)
		mi.rotation_degrees.z = 80.0
		mi.position.y = 0.12
		center_y = 0.12; radius = 0.4
	elif v == "mound":
		var sm := SphereMesh.new()
		sm.radius = 0.45; sm.height = 0.9
		mi.mesh = sm
		mat.albedo_color = Color(0.40, 0.30, 0.20)
		mi.scale = Vector3(1.0, 0.5, 1.0)
		mi.position.y = 0.18
		center_y = 0.18; radius = 0.45
	else:  # stone
		var sm := SphereMesh.new()
		sm.radius = 0.25; sm.height = 0.5
		mi.mesh = sm
		mat.albedo_color = Color(0.50, 0.50, 0.52)
		mi.position.y = 0.2
		center_y = 0.2; radius = 0.35
	mi.material_override = mat
	add_child(mi)
	return {"center_y": center_y, "radius": radius}

## 放大碰撞盒：从地面略下到 ~0.8m 高、水平 ~1m，便于交互射线命中（修「捡不起来」）。
## 仍放第 2 层（玩家 mask 只含第 1 层）-> 不阻挡玩家，但射线能命中、按 E 能拾取。
func _add_collision(center_y: float, radius: float) -> void:
	var half := maxf(radius, 0.5)
	var box_bottom := -0.1
	var box_top := maxf(center_y + 0.35, 0.8)
	var hh := (box_top - box_bottom) * 0.5
	var bs := BoxShape3D.new()
	bs.extents = Vector3(half, hh, half)
	var col := CollisionShape3D.new()
	col.shape = bs
	col.position.y = box_bottom + hh
	collision_layer = 2
	collision_mask = 0
	add_child(col)

func _get(property: StringName):
	if property == &"prompt":
		if required_tool != "" and not Inventory.has(required_tool, 1):
			return "需要【%s】才能挖取" % tool_name
		return prompt
	return null

func interact(_player) -> void:
	if required_tool != "" and not Inventory.has(required_tool, 1):
		EventBus.toast.emit("需要【%s】才能挖取" % tool_name)
		return
	for id in drops:
		Inventory.add_item(id, int(drops[id]))
	EventBus.resource_harvested.emit(self, drops)
	EventBus.toast.emit("拾取了 %s" % _drops_text())
	queue_free()

func _drops_text() -> String:
	var parts: Array = []
	for id in drops:
		var it: ItemResource = ItemDatabase.get_item(id)
		var nm: String = it.display_name if it != null else id
		parts.append("%s×%d" % [nm, int(drops[id])])
	return "  ".join(parts)
