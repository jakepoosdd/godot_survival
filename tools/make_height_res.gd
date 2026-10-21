extends SceneTree
## 一次性工具：把原始 R8 高度图 island_height.bin 转成 Godot 原生 .res 图片资源。
## 用途：Godot 导出器会跳过 .bin 扩展名（即使 export_filter="all" 也进不了 PCK），
##       而 .res 是原生资源、必定随包发布。world.gd 现加载该 .res。
## 运行：Godot_v4.7-stable_win64_console.exe --headless --script tools/make_height_res.gd
## 重跑时机：每次重新生成 island_height.bin 后都需要再跑一次本脚本以保持 .res 同步。

const HM_SIZE := 1024
const SRC := "res://assets/terrain/island_height.bin"
const DST := "res://assets/terrain/island_height_img.res"

func _initialize() -> void:
	var f: FileAccess = FileAccess.open(SRC, FileAccess.READ)
	if f == null:
		printerr("[make_height_res] 无法打开 ", SRC)
		quit(1)
		return
	var buf: PackedByteArray = f.get_buffer(HM_SIZE * HM_SIZE)
	f.close()
	if buf.size() != HM_SIZE * HM_SIZE:
		printerr("[make_height_res] 高度图尺寸异常: got ", buf.size(), " want ", HM_SIZE * HM_SIZE)
		quit(1)
		return
	var img := Image.create_from_data(HM_SIZE, HM_SIZE, false, Image.FORMAT_R8, buf)
	var err := ResourceSaver.save(img, DST)
	if err != OK:
		printerr("[make_height_res] 保存失败 err=", err)
		quit(1)
		return
	print("[make_height_res] OK -> ", DST, " (", buf.size(), " bytes, ", HM_SIZE, "x", HM_SIZE, " R8)")
	quit()
