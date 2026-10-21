extends Node
## 音频管理（Autoload: AudioManager）。
## 监听游戏事件播放 res://audio/<name>.ogg/.wav/.mp3。
## 资源缺失则优雅跳过——无外部音频文件时静默运行，放入文件即生效（数据驱动）。

var master_volume := 1.0
var sfx_volume := 1.0
var music_volume := 0.6

var _music_player: AudioStreamPlayer
var _sfx_pool: Array = []
var _sfx_idx := 0
var _cache: Dictionary = {}
var _loops: Dictionary = {}   # name -> AudioStreamPlayer（循环音：收线/泄力）
signal volumes_changed()

func _ready() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	add_child(_music_player)
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_sfx_pool.append(p)
	EventBus.player_attacked.connect(func(_t, _d): play_sfx("hit"))
	EventBus.player_damaged.connect(func(_d): play_sfx("hurt"))
	EventBus.food_eaten.connect(func(_i): play_sfx("eat"))
	EventBus.recipe_crafted.connect(func(_r): play_sfx("craft"))
	EventBus.leveled_up.connect(func(_l): play_sfx("level"))
	EventBus.structure_placed.connect(func(_s, _a): play_sfx("build"))
	EventBus.creature_died.connect(func(_c, _d): play_sfx("kill"))
	EventBus.achievement_unlocked.connect(func(_id, _n, _d): play_sfx("achievement"))
	volumes_changed.emit()

func _load(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var res: AudioStream = null
	for ext in ["ogg", "wav", "mp3"]:
		var res_obj = load("res://audio/%s.%s" % [name, ext])
		if res_obj != null and res_obj is AudioStream:
			res = res_obj
			break
	_cache[name] = res
	return res

func play_sfx(name: String) -> void:
	var s: AudioStream = _load(name)
	if s == null:
		return
	var p: AudioStreamPlayer = _sfx_pool[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_pool.size()
	p.stream = s
	p.volume_db = linear_to_db(maxf(0.0001, sfx_volume * master_volume))
	p.play()

func play_music(name: String) -> void:
	var s: AudioStream = _load(name)
	if s == null:
		return
	# 循环播放：loop 是 AudioStream 资源的属性（不是 AudioStreamPlayer 的）
	s.loop = true
	# 已在同一首上播放则不打断（避免从主菜单重新开始时重头播）
	if _music_player.stream == s and _music_player.playing:
		return
	_music_player.stream = s
	_music_player.volume_db = linear_to_db(maxf(0.0001, music_volume * master_volume))
	_music_player.play()

## 循环音（如收线 reel_wind / 泄力 reel_drag）：on=true 时开始循环播放，false 时停止。
## 资源缺失则静默跳过；已播放中重复调用 on=true 不再重启，避免每帧打断。
func set_loop(name: String, on: bool) -> void:
	if on:
		var p: AudioStreamPlayer = _get_loop(name)
		if p.stream == null:
			return
		if not p.playing:
			p.play()
	else:
		if _loops.has(name):
			var p: AudioStreamPlayer = _loops[name]
			if p.playing:
				p.stop()

func _get_loop(name: String) -> AudioStreamPlayer:
	if _loops.has(name):
		return _loops[name]
	var s: AudioStream = _load(name)
	var p := AudioStreamPlayer.new()
	p.bus = "Master"
	# loop 是 AudioStream 资源的属性（不是 AudioStreamPlayer 的）
	if s != null:
		s.loop = true
	p.stream = s
	p.volume_db = linear_to_db(maxf(0.0001, sfx_volume * master_volume))
	add_child(p)
	_loops[name] = p
	return p

func _refresh_loop_volumes() -> void:
	for p in _loops.values():
		if p.stream != null:
			p.volume_db = linear_to_db(maxf(0.0001, sfx_volume * master_volume))

func set_master(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	volumes_changed.emit()

func set_sfx(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_refresh_loop_volumes()
	volumes_changed.emit()

func set_music(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	volumes_changed.emit()
