extends CharacterBody3D
class_name SpiritCompanion
## 岛灵化形伙伴（多实例）。类型为 gather / fighter / versatile，由 RelationshipManager.companion_bred 触发、
## 经 Companions 单例生成在营地附近。
##   - fighter：跟随主角，自动攻击靠近的猛兽/野怪（反向复用 enemy.gd 的追击/攻击逻辑）。
##   - gather：在营地附近游荡，周期性把采集到的材料送进营地仓库（CampStorage）。
##   - versatile：兼顾跟随与采集，数值中庸。
## 视觉：青色发光胶囊 + 漂浮的灵光球（不依赖外部网格，保证工程始终能跑）。

@export var companion_type: String = "gather"   # "gather" | "fighter" | "versatile"
@export var companion_name: String = "岛灵"

const SPEED := {
	"gather": 4.0,
	"fighter": 5.6,
	"versatile": 4.8,
}
const ATK_DMG := {"fighter": 18.0, "versatile": 12.0, "gather": 0.0}
const ATK_RANGE := {"fighter": 2.2, "versatile": 2.0, "gather": 0.0}
const ATK_INTERVAL := {"fighter": 1.0, "versatile": 1.3, "gather": 0.0}
const DETECT := {"fighter": 16.0, "versatile": 12.0, "gather": 0.0}
const HARVEST_INTERVAL := {"gather": 7.0, "versatile": 12.0, "fighter": 0.0}

var _speed: float = 4.0
var _atk_dmg: float = 0.0
var _atk_range: float = 0.0
var _atk_interval: float = 0.0
var _detect: float = 0.0
var _harvest_interval: float = 0.0

var _attack_cd := 0.0
var _harvest_cd := 0.0
var _body: Node3D = null
var _orb: MeshInstance3D = null
var _t := 0.0

func _ready() -> void:
	add_to_group("companion")
	_speed = SPEED.get(companion_type, 4.0)
	_atk_dmg = ATK_DMG.get(companion_type, 0.0)
	_atk_range = ATK_RANGE.get(companion_type, 0.0)
	_atk_interval = ATK_INTERVAL.get(companion_type, 0.0)
	_detect = DETECT.get(companion_type, 0.0)
	_harvest_interval = HARVEST_INTERVAL.get(companion_type, 0.0)
	_harvest_cd = _harvest_interval * 0.5
	_build_visual()
	_build_collision()
	if Companions != null:
		Companions.register(self)

func _build_collision() -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 0      # 不参与射线/物理，避免挡住交互射线
	sb.collision_mask = 0
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.6
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	sb.add_child(col)
	add_child(sb)

## 青色发光体 + 漂浮灵光球，颜色按类型区分。
func _build_visual() -> void:
	var col := Color(0.3, 0.9, 0.8)   # 采集型：青
	if companion_type == "fighter":
		col = Color(0.35, 0.7, 1.0)   # 战斗型：蓝
	elif companion_type == "versatile":
		col = Color(0.8, 0.7, 1.0)    # 全能型：紫
	_body = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.35
	cyl.height = 1.7
	_body.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy = 0.9
	mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.85
	_body.material_override = mat
	_body.position = Vector3(0, 0.9, 0)
	add_child(_body)
	# 标记（类型首字）
	var marker := MeshInstance3D.new()
	marker.name = "CompanionMarker"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.16
	cone.height = 0.35
	marker.mesh = cone
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = col
	mmat.emission = col
	mmat.emission_energy = 0.8
	marker.material_override = mmat
	marker.position = Vector3(0, 2.3, 0)
	add_child(marker)
	# 灵光球
	_orb = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.22
	sph.height = 0.44
	_orb.mesh = sph
	var omat := StandardMaterial3D.new()
	omat.albedo_color = col
	omat.emission = col
	omat.emission_energy = 1.6
	omat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
	omat.albedo_color.a = 0.9
	_orb.material_override = omat
	_orb.position = Vector3(0, 2.7, 0)
	add_child(_orb)

func _physics_process(delta: float) -> void:
	_t += delta
	if _orb != null:
		_orb.position.y = 2.7 + sin(_t * 2.0) * 0.15
	if _attack_cd > 0.0:
		_attack_cd -= delta
	if _harvest_cd > 0.0:
		_harvest_cd -= delta

	var ground_y := _ground_height(global_position.x, global_position.z)

	# 战斗型/全能型：跟随主角并自动攻击 nearby 敌人（全能型同时也会采集）
	if _atk_dmg > 0.0:
		_combat_step(delta)
	else:
		velocity = Vector3.ZERO
	# 采集型/全能型：定时把材料送进营地仓库（采集型额外在营地内游荡）
	if _harvest_interval > 0.0:
		_gather_step(delta)

	velocity.y = 0.0
	move_and_slide()
	global_position.y = ground_y

## 战斗型：找最近敌人 -> 追击/攻击。
func _combat_step(_delta: float) -> void:
	var target := _nearest_enemy()
	if target == null and GameManager.player != null:
		# 无敌人时跟随主角（保持 3m 距离）
		var p: Node3D = GameManager.player as Node3D
		var to: Vector3 = p.global_position - global_position
		to.y = 0.0
		var d: float = to.length()
		if d > 3.2:
			velocity.x = to.normalized().x * _speed
			velocity.z = to.normalized().z * _speed
		else:
			velocity.x = 0.0
			velocity.z = 0.0
		_face(velocity)
		return
	if target == null:
		velocity = Vector3.ZERO
		return
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	var d: float = to.length()
	if d > _atk_range:
		velocity.x = to.normalized().x * _speed
		velocity.z = to.normalized().z * _speed
		_face(velocity)
	elif _attack_cd <= 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		_attack(target)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

func _attack(enemy: Node) -> void:
	_attack_cd = _atk_interval
	if enemy != null and enemy.has_method("take_damage"):
		enemy.take_damage(_atk_dmg, self)
		EventBus.damage_popup.emit(enemy.global_position + Vector3(0, 2.4, 0), _atk_dmg, "enemy")

func _nearest_enemy() -> Node:
	var best: Node = null
	var best_d := _detect
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == null or not is_instance_valid(e):
			continue
		if bool(e.get("dead")):
			continue
		var d := global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

## 采集型：营地附近游荡 + 周期把材料送进营地仓库。全能型的 _gather_step 只负责交付（移动由 _combat_step 接管）。
func _gather_step(delta: float) -> void:
	if _harvest_cd <= 0.0:
		_harvest_cd = _harvest_interval
		_deliver_harvest()
	# 仅采集型在营地内缓慢游荡；全能型跟随主角，不额外游荡
	if companion_type == "gather":
		var c: Vector2 = GameManager.camp_center
		var to: Vector3 = Vector3(c.x, global_position.y, c.y) - global_position
		to.y = 0.0
		var d: float = to.length()
		if d > 9.0:
			velocity.x = to.normalized().x * _speed * 0.6
			velocity.z = to.normalized().z * _speed * 0.6
			_face(velocity)

func _deliver_harvest() -> void:
	var pool: PackedStringArray = ["log", "stick", "stone", "berry", "bait", "flintstone"]
	var id := pool[randi() % pool.size()]
	var amt := randi_range(1, 2)
	CampStorage.add_item(id, amt)
	var it: ItemResource = ItemDatabase.get_item(id)
	var nm: String = it.display_name if it != null else id
	EventBus.toast.emit("%s 带回了 %s ×%d，存入营地仓库" % [companion_name, nm, amt])

func _face(v: Vector3) -> void:
	if _body == null or v.length_squared() < 1e-4:
		return
	var yaw := atan2(v.x, v.z)
	_body.rotation.y = lerp_angle(_body.rotation.y, yaw, 0.2)

func _ground_height(x: float, z: float) -> float:
	if GameManager.world != null and GameManager.world.has_method("get_ground_height"):
		return float(GameManager.world.call("get_ground_height", x, z))
	return 0.0

func get_companion_type() -> String:
	return companion_type
