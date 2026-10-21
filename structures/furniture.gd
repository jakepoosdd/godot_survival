extends Node3D
class_name Furniture
## 营地家具（可交互）。kind = "bed" | "cabinet" | "pot"。
##   - bed      ：睡眠快进至天亮（DayNightCycle.sleep_until_dawn）
##   - cabinet  ：打开营地仓库面板（CampStorage）
##   - pot      ：打开烹饪菜单（复用营火逻辑，需持有可烹饪食材）
## 由 world.gd 在 _build_camp 里按位置挂上本脚本并指定 kind。

@export var kind: String = "bed"
var prompt := "家具"

func _ready() -> void:
	add_to_group("furniture")
	_build_collision()
	_refresh_prompt()

func _build_collision() -> void:
	# 加一个包围盒碰撞体，让交互射线能命中（GLTF 网格默认不带碰撞）。
	var sb := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 2.4, 2.4)
	col.shape = box
	col.position = Vector3(0, 1.2, 0)
	sb.add_child(col)
	add_child(sb)

func interact(_p) -> void:
	match kind:
		"bed":
			EventBus.toast.emit("你在%s旁躺下，沉沉睡去……" % _kind_name())
			DayNightCycle.sleep_until_dawn()
		"cabinet":
			EventBus.camp_storage_requested.emit()
		"pot":
			if Inventory.has_cookable_raw():
				EventBus.cooking_menu_requested.emit()
			else:
				EventBus.toast.emit("锅里空空如也，先去弄点生鱼/生肉吧")
		_:
			EventBus.toast.emit("这是一件家具")

func _kind_name() -> String:
	match kind:
		"bed": return "床"
		"cabinet": return "柜子"
		"pot": return "锅"
		_: return "家具"

func _refresh_prompt() -> void:
	match kind:
		"bed": prompt = "床（按 E 睡觉到天亮）"
		"cabinet": prompt = "柜子（按 E 打开营地仓库）"
		"pot": prompt = "锅（按 E 烹饪）"
		_: prompt = "家具（按 E）"
