extends "res://inventory/interactable.gd"
## 可采集资源节点（树/石/灌木通用）。数据驱动：visual_scene 决定外观（复用地图同款 Slavic 预制体），
## drops 决定产出。交互系统射线命中本 StaticBody3D 后调用 interact() 给玩家物品。

@export var visual_scene: PackedScene
@export var drops := {"log": 1, "stick": 1}
@export var scale_mul := 1.0
@export var required_tool: String = ""       # 采集所需工具 id（空 = 无需工具）
@export var tool_name: String = ""           # 工具显示名（用于提示，如 "斧头"）
@export var bonus_tool: String = ""          # 增益工具（如镰刀），持有则额外产出 bonus_drops
@export var bonus_drops: Dictionary = {}     # 持有 bonus_tool 时额外掉落的物品

# 按 prefab 路径缓存包围盒尺寸：资源节点只复用 world 的 _mm_add 合批视觉，
# 这里只取尺寸生成贴合碰撞，避免每个节点都把整 GLB 实例化一次（省启动开销）。
var _aabb_cache := {}

func _ready() -> void:
	# 视觉不在这里实例化：改由 world 的 _mm_add 分块 MultiMesh 合批渲染
	# （见 world.gd _spawn_resource_group），这里只取包围盒尺寸用于生成贴合碰撞。
	# 省掉每棵树/石头的十几个 MeshInstance3D draw call，节点只保留 StaticBody3D + 碰撞供采集。
	var vis_size := Vector3(2.0, 4.0, 2.0)
	if visual_scene != null:
		var rp := visual_scene.resource_path
		if _aabb_cache.has(rp):
			vis_size = (_aabb_cache[rp] as Vector3) * scale_mul
		else:
			var v = visual_scene.instantiate()
			var sz := _mesh_aabb_size(v)
			v.free()
			_aabb_cache[rp] = sz
			vis_size = sz * scale_mul
	# —— 碰撞体 ——
	# 关键：碰撞必须贴合可见模型，否则出现「隐形墙」→ 玩家「卡石头」。
	# 原先是固定 2.8×6×2.8 的大盒子：小石头/浆果丛周围也套一圈看不见的墙，一步一卡。
	# 现在按真实包围盒分两档：
	# · 大障碍（树 / 大石，水平 > 2.5m）：实心碰撞，玩家撞得到；水平方向收 0.8 并限制在
	#   1.5m 半宽内，保证贴着它走也能绕开，不会被凭空挡住。
	# · 小物件（鹅卵石 / 小石 / 浆果丛）：放到第 2 层（玩家 mask 只含第 1 层）→ 不再阻挡
	#   玩家，但碰撞体仍在，交互射线照样能命中、按 E 照样能采集 —— 从根上消除「卡石头」。
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var hy := maxf(vis_size.y * 0.5, 0.5)
	if maxf(vis_size.x, vis_size.z) > 2.5:
		bs.extents = Vector3(
			clampf(vis_size.x * 0.5 * 0.8, 0.25, 1.5), hy,
			clampf(vis_size.z * 0.5 * 0.8, 0.25, 1.5))
		collision_layer = 1
	else:
		bs.extents = Vector3(
			clampf(vis_size.x * 0.5, 0.15, 1.0), hy,
			clampf(vis_size.z * 0.5, 0.15, 1.0))
		collision_layer = 2          # 可交互但不阻挡玩家
	collision_mask = 0
	col.shape = bs
	col.position.y = hy
	add_child(col)

## 递归求节点下所有 MeshInstance3D 的合并包围盒尺寸（本地空间，用于生成贴合碰撞）。
func _mesh_aabb_size(root: Node) -> Vector3:
	var merged := AABB()
	var has := false
	var stack: Array = [root]
	while not stack.is_empty():
		var cur = stack.pop_back()
		if cur is MeshInstance3D and cur.mesh != null:
			var mi: MeshInstance3D = cur
			var a: AABB = mi.transform * mi.get_aabb()
			if has:
				merged = merged.merge(a)
			else:
				merged = a
				has = true
		for c in cur.get_children():
			stack.append(c)
	if not has:
		return Vector3(2.0, 4.0, 2.0)
	return merged.size

func _get(property: StringName):
	# 动态提示：缺工具时直接告诉玩家需要什么
	if property == &"prompt":
		if required_tool != "" and not Inventory.has(required_tool, 1):
			return "需要【%s】才能采集" % tool_name
		return prompt
	return null

func interact(_player) -> void:
	if required_tool != "" and not Inventory.has(required_tool, 1):
		EventBus.toast.emit("需要【%s】才能采集" % tool_name)
		return
	for id in drops:
		Inventory.add_item(id, int(drops[id]))
	if bonus_tool != "" and Inventory.has(bonus_tool, 1):
		for id in bonus_drops:
			Inventory.add_item(id, int(bonus_drops[id]))
	EventBus.resource_harvested.emit(self, drops)
	# 采集反馈：轻微缩小再弹回
	var t := create_tween()
	t.tween_property(self, "scale", Vector3(0.85, 0.85, 0.85), 0.1).set_trans(Tween.TRANS_BACK)
	t.tween_property(self, "scale", Vector3.ONE, 0.22)
