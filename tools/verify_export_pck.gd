extends SceneTree
## 验证导出的 PCK 里关键资源是否可被游戏代码按「原路径」读出来。
## 原理：用 --main-pack 把导出的 IslandSurvival.pck 作为主包加载（此时 res:// 指向包内，
##       与双击 EXE 等价），然后复刻各加载器在运行时做的事：
##         - load("res://assets/terrain/island_height_img.res")   (world.gd)
##         - load("res://...glb")                                  (character_registry / prop_loader / enemy / weapon_mount)
##         - load("res://assets/animals/<sp>.glb")                 (enemy.gd 动物)
##       若都能成功返回 PackedScene，说明导出包内资源路径可用，修复生效。
## 运行：Godot_v4.7-stable_win64_console.exe --headless \
##         --main-pack D:/AI_WORK/godot_survival_export/IslandSurvival.pck \
##         --script tools/verify_export_pck.gd

const PCK := "D:/AI_WORK/godot_survival_export/IslandSurvival.pck"

func _initialize() -> void:
	print("[verify] start, main-pack=%s" % PCK)

	# 1) 高度图 .res（world.gd 现加载此文件）
	var img: Resource = load("res://assets/terrain/island_height_img.res")
	if img is Image:
		var im: Image = img
		print("[verify] height .res OK  size=%s fmt=%d" % [im.get_size(), im.get_format()])
	else:
		printerr("[verify] FAIL: height .res 未加载 (img=%s)" % img)

	# 2) 角色/怪物/道具 GLB（各加载器现走 load() -> import remap -> .scn）
	var glbs := PackedStringArray([
		"res://player/Ch23_Lead.glb",
		"res://player/Kachujin_Sword.glb",
		"res://player/Maria_Companion.glb",
		"res://player/Erika_Archer.glb",
		"res://player/Arissa_Mage.glb",
		"res://player/Ch46_Child.glb",
		"res://assets/props/tent.glb",
		"res://assets/props/bonfire.glb",
		"res://assets/props/dock.glb",
		"res://assets/props/fishing_rod.glb",
		"res://player/RPG_Character.glb",
		"res://assets/monsters/Demon.glb",
		"res://assets/monsters/SkeletonZombie.glb",
		"res://assets/monsters/Warrok.glb",
		"res://assets/monsters/Maw.glb"
	])
	var all_ok := true
	for g in glbs:
		var res: Resource = load(g)
		if res is PackedScene:
			print("[verify] GLB OK  %s" % g)
		else:
			all_ok = false
			printerr("[verify] FAIL GLB %s -> %s" % [g, res])
	print("[verify] ALL GLB OK = %s" % all_ok)

	# 3) 动物模型（enemy.gd 现走 load()）
	#    ⚠️ deer/boar/bear 指向「带骨骼动画」的新资源，不再是静态网格
	var animals := PackedStringArray([
		"res://assets/animals/wolf.glb",
		"res://assets/animals/stag.gltf",
		"res://assets/animals/boar_anim.glb",
		"res://assets/animals/fox.glb",
		"res://assets/animals/bear_anim.glb"
	])
	var animals_ok := true
	for a in animals:
		var res: Resource = load(a)
		if res is PackedScene:
			print("[verify] ANIMAL OK  %s" % a)
		else:
			animals_ok = false
			printerr("[verify] FAIL ANIMAL %s -> %s" % [a, res])
	print("[verify] ALL ANIMAL OK = %s" % animals_ok)

	quit()
