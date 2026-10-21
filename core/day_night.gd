extends Node
## 昼夜循环（Autoload: DayNightCycle）。
## 推进 Sky3D 的 current_time（world.gd 已创建 Sky3D 并加入 "sky3d" 组）。
## 0..1 的归一化时间在 GameManager.time_of_day 保存，供 needs_system 夜间加速 sanity 衰减、
## 敌人夜间行为等使用。HUD 读取 get_time_string() 显示时钟。

var hour: float = 9.0          # 0..24
var day: int = 1
var time_speed: float = 1.0
var real_seconds_per_game_hour: float = 30.0   # 约 12 分钟/天
var _last_minute := -1
var _sky: Node = null
var _sleeping := false
var _sleep_target := 0.0      # 睡眠目标时刻（小时，可能 >24 表示次日）

func _process(delta: float) -> void:
	if _sleeping:
		# 睡眠快进：以约 40 倍速推进到天亮
		hour += delta * time_speed * 40.0 / real_seconds_per_game_hour
		if hour >= _sleep_target:
			hour = fmod(_sleep_target, 24.0)
			if _sleep_target >= 24.0:
				day += 1
				EventBus.day_changed.emit(day)
				GameManager.day_count = day
			_sleeping = false
			_on_woke()
			EventBus.toast.emit("天亮了")
	else:
		hour += delta * time_speed / real_seconds_per_game_hour
		if hour >= 24.0:
			hour = fmod(hour, 24.0)
			day += 1
			EventBus.toast.emit("第 %d 天" % day)
			EventBus.day_changed.emit(day)
			GameManager.day_count = day

	if _sky == null:
		_sky = get_tree().get_first_node_in_group("sky3d")
	if _sky != null:
		_sky.current_time = hour

	var minute := int(hour * 60.0)
	if minute != _last_minute:
		_last_minute = minute
		var t01 := hour / 24.0
		GameManager.time_of_day = t01
		GameManager.day_count = day
		EventBus.time_of_day_changed.emit(t01)

## 夜晚：18:00 - 次日 6:00
func is_nighttime() -> bool:
	return hour < 6.0 or hour >= 18.0

## 黄昏/黎明过渡带（用于光照柔和变化判断，可选）
func is_dusk_dawn() -> bool:
	return (hour >= 17.0 and hour < 19.0) or (hour >= 5.0 and hour < 7.0)

func get_time_string() -> String:
	var h := int(hour)
	var m := int((hour - h) * 60.0)
	return "第%d天 %02d:%02d" % [day, h, m]

## 钻进帐篷睡到天亮：快进时间至下一个 06:00，醒来恢复状态。
func sleep_until_dawn() -> void:
	if _sleeping:
		return
	if hour < 6.0:
		_sleep_target = 6.0
	else:
		_sleep_target = 30.0   # 次日 06:00
	_sleeping = true
	EventBus.toast.emit("你钻进帐篷，沉沉睡去……")

func _on_woke() -> void:
	var p = GameManager.player
	if p != null:
		var ns = p.get_node_or_null("NeedsSystem")
		if ns != null:
			ns.apply_effects(25.0, -12.0, 35.0)   # 回血、掉点饥饿、大幅回精神
