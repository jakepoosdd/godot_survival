extends Node
## 性能基准自动加载（优化技能配套）。正常运行完全无开销；
## 仅当用 `-- --bench` 启动时才记录每帧 cpu/gpu 时间、draw call、管线编译数到 user://bench.csv。
## 用法（在带真实 GPU 的机器上，例如你的 2080Ti）：
##   Godot_v4.7...exe --path "D:/AI_WORK/godot_survival" --rendering-driver vulkan -- --bench
## 日志首行会打印 BENCH adapter=...（确认跑在独显而非集显上）。

var _rows := PackedStringArray(["frame_ms,render_cpu_ms,gpu_ms,draw_calls,pipelines_total"])
var _vp: RID

func _ready() -> void:
	if not "--bench" in OS.get_cmdline_user_args():
		set_process(false)
		return
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	Performance.add_custom_monitor("game/bench_active", _bench_active)
	print("BENCH adapter=", RenderingServer.get_video_adapter_name())

func _bench_active() -> float:
	return 1.0

func _process(_delta: float) -> void:
	var pipes := Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE) \
		+ Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)
	_rows.append("%.2f,%.3f,%.3f,%d,%d" % [
		_delta * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(_vp),
		RenderingServer.viewport_get_measured_render_time_gpu(_vp),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		pipes])

func _exit_tree() -> void:
	if is_processing():
		Performance.remove_custom_monitor("game/bench_active")
		var f := FileAccess.open("user://bench.csv", FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(_rows))
			f.close()
			print("BENCH wrote user://bench.csv  rows=", _rows.size())
