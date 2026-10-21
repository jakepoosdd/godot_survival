extends SceneTree
## Godot headless 校验 GLB 角色：加载、动画数、骨骼直立校验。
## 用法: godot --headless --script verify_godot.gd -- res://player/Xxx_Lead.glb
## 注意：-- 之后的参数要从 OS.get_cmdline_user_args() 取（get_cmdline_args() 取不到）。
func _init() -> void:
	var target := "res://player/UrbanMan_Lead.glb"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	for a in args:
		if a.ends_with(".glb"):
			target = a
	print("TARGET=", target)
	await _check(target)
	quit(0)

func _check(p: String) -> void:
	print("==== ", p)
	var fpath := ProjectSettings.globalize_path(p)
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_file(fpath, state)
	if err != OK:
		printerr("  IMPORT_FAIL err=", err); return
	var scene = gltf.generate_scene(state)
	if scene == null:
		printerr("  GEN_FAIL"); return
	root.add_child(scene)
	await process_frame
	var ap: AnimationPlayer = _find_ap(scene)
	var sk: Skeleton3D = _find_skeleton(scene)
	if sk == null:
		printerr("  NO_SKELETON"); scene.queue_free(); return
	var names = []
	if ap != null:
		names = ap.get_animation_list()
	print("  bones=", sk.get_bone_count(), " anims=", names.size())
	for n in names:
		print("    anim: ", n)

	var hips_idx := -1; var head_idx := -1
	for i in range(sk.get_bone_count()):
		var bn := sk.get_bone_name(i).to_lower()
		if hips_idx < 0 and ("hips" in bn or "pelvis" in bn or "root" in bn): hips_idx = i
		if head_idx < 0 and "head" in bn: head_idx = i

	var rest_lo := 1e9; var rest_hi := -1e9
	for i in range(sk.get_bone_count()):
		var y := (sk.global_transform * sk.get_bone_global_pose(i)).origin.y
		rest_lo = min(rest_lo, y); rest_hi = max(rest_hi, y)
	print("  REST bone Y: %.3f .. %.3f" % [rest_lo, rest_hi])
	if hips_idx >= 0:
		print("  REST hips Y = %.3f" % (sk.global_transform * sk.get_bone_global_pose(hips_idx)).origin.y)
	if head_idx >= 0:
		print("  REST head Y = %.3f" % (sk.global_transform * sk.get_bone_global_pose(head_idx)).origin.y)

	if ap == null:
		scene.queue_free(); return
	var ns := ap.get_animation_list()
	var lo := 1e9; var hi := -1e9
	for an in ns:
		var anim := ap.get_animation(an)
		var dur: float = anim.length
		var steps := 8
		for s in range(steps):
			var t: float = dur * float(s) / float(steps)
			ap.play(an)
			ap.seek(t, true)
			await create_timer(0.004).timeout
			for i in range(sk.get_bone_count()):
				var y := (sk.global_transform * sk.get_bone_global_pose(i)).origin.y
				lo = min(lo, y); hi = max(hi, y)
	print("  ANIM bone Y: %.3f .. %.3f  (height=%.3f)" % [lo, hi, hi - lo])
	if hi > 1.2 and lo > -1.0:
		print("  BONE_VERIFY_OK")
	else:
		print("  BONE_VERIFY_SUSPECT")
	scene.queue_free()
	await process_frame

func _find_ap(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node
	for c in node.get_children():
		var r := _find_ap(c)
		if r != null: return r
	return null

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for c in node.get_children():
		var r := _find_skeleton(c)
		if r != null: return r
	return null
