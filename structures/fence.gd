extends Node3D
class_name Fence
## 可破坏栅栏（营地防御核心）。带 HP，可被夜袭攻击、玩家修复/升级。
## 视觉用 Slavica 栅栏预制体作子节点；自身作为交互与状态载体（interaction_system 沿父链找到本节点的 interact）。
## 受损时头顶显示 3D 浮动血条（ui/health_bar.gd），满血时自动隐藏以减少杂乱。

const HealthBarScript := preload("res://ui/health_bar.gd")

var seg_index: int = -1
var level: int = 1
var hp: float = 100.0
var maxhp: float = 100.0
var damaged := false                         # 生成时标记为破损（需修复）
var indestructible := false                  # 营地支柱：不可破坏、无血条，HP=0 也不消失
const HP_BY_LEVEL := [0.0, 100.0, 200.0, 400.0]
var prompt := "栅栏"
var _hp_bar: Node = null                     # 头顶血条

func _ready() -> void:
	add_to_group("fence")
	maxhp = HP_BY_LEVEL[level]
	hp = maxhp
	if damaged:
		# 出生即破损：血量降至 35%，并轻微歪斜以呈现"破损需修复"观感
		hp = maxhp * 0.35
		rotation.z = _rand_lean()
		rotation.x = _rand_lean() * 0.5
	Fences.register_fence(self)
	if indestructible:
		hp = maxhp                  # 支柱恒满血
		prompt = "营地支柱（坚固）"
	else:
		_setup_health_bar()
		Fences.fence_damaged.connect(_on_fence_damaged)
		Fences.fence_broken.connect(_on_fence_broken)
		Fences.fence_upgraded.connect(_on_fence_upgraded)
	_refresh_prompt()

## 头顶血条：放在栅栏上方，跟随生命值缩放；仅在受损（hp<maxhp）时显示。
func _setup_health_bar() -> void:
	var hb := HealthBarScript.new()
	hb.name = "HealthBar"
	add_child(hb)
	hb.position = Vector3(0.0, 2.3, 0.0)
	hb.set_fraction(hp / maxhp)
	_hp_bar = hb
	_refresh_bar()

## 同步血条比例与可见性（满血隐藏）。
func _refresh_bar() -> void:
	if _hp_bar == null:
		return
	_hp_bar.set_fraction(hp / maxhp)
	_hp_bar.visible = hp < maxhp and hp > 0.0

func _on_fence_damaged(seg: int, _hp_left: float) -> void:
	if seg == seg_index:
		_refresh_bar()

func _on_fence_broken(seg: int) -> void:
	if seg == seg_index:
		_refresh_bar()

func _on_fence_upgraded(_level: int) -> void:
	_refresh_bar()

func _rand_lean() -> float:
	return (randf() * 2.0 - 1.0) * 0.10

func interact(_p) -> void:
	if indestructible:
		EventBus.toast.emit("营地支柱无法破坏")
		return
	if hp < maxhp:
		Fences.repair(self)
	elif level < 3:
		Fences.try_upgrade(self)
	else:
		EventBus.toast.emit("栅栏已是最高级（Lv3）")
	_refresh_bar()
	_refresh_prompt()

func _refresh_prompt() -> void:
	if indestructible:
		prompt = "营地支柱（坚固）"
		return
	if hp <= 0.0:
		prompt = "栅栏（已破损）"
	elif hp < maxhp:
		prompt = "栅栏 Lv%d（按 E 修复 %d/%d）" % [level, int(hp), int(maxhp)]
	elif level < 3:
		prompt = "栅栏 Lv%d（按 E 升级）" % level
	else:
		prompt = "栅栏 Lv3（坚固）"

## 被摧毁（HP=0）：从世界彻底移除，血条随节点一起消失。
func destroy() -> void:
	_hp_bar = null
	if is_instance_valid(self):
		queue_free()
