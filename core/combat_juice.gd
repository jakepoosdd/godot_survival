extends Node
## 打击感反馈中枢（阶段1：定格 + 击退）。
## 订阅 EventBus.hit_registered：仅「玩家近战命中」触发全套反馈；
## 远程/伙伴命中不触发（用户确认远程不加这效果好），但信号照常发出，
## 以便后续飘字/粒子等订阅者按需取用。

var _stopping := false
var _stop_deadline_ms: int = 0   # 定格兜底截止时刻（真实毫秒）；>0 表示正在定格

const HITSTOP_DUR := 0.06        # 定格时长（秒，约 3-4 帧，克制）
const KNOCKBACK_STRENGTH := 6.0  # 击退初速度（单位/秒）

func _ready() -> void:
	# 定格靠真实时间计时，本节点必须在暂停态下也能跑
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 兜底：万一上次定格异常未复位，开局强制复位，避免一进游戏就是"时间静止"。
	Engine.time_scale = 1.0
	EventBus.hit_registered.connect(_on_hit)

func _on_hit(victim: Node, dir: Vector3, damage: float, by_player: bool) -> void:
	if not by_player:
		return                     # 远程/伙伴命中：不加打击反馈
	if not is_instance_valid(victim):
		return
	if victim.has_method("apply_knockback"):
		victim.apply_knockback(dir, KNOCKBACK_STRENGTH)
	hitstop(HITSTOP_DUR)

func hitstop(dur: float) -> void:
	if _stopping:
		return                     # 防止连击把游戏永久冻住
	_stopping = true
	_stop_deadline_ms = Time.get_ticks_msec() + int(dur * 1000.0) + 50   # 兜底：真实时间限时
	Engine.time_scale = 0.0
	# ⚠️ 坑（曾导致「突然卡住什么都动不了」的全局永久冻结）：
	#   create_timer 的签名是 (time_sec, process_always, process_in_physics, ignore_time_scale)，
	#   第 2 个参数是 process_always，**不是** ignore_time_scale！
	#   只传 (dur, true) → ignore_time_scale 仍为 false → 该计时器按「被缩放的时间」倒计时；
	#   而此刻 time_scale 被我们置 0，计时器永远走不到头 → 协程永不恢复 → time_scale 永远是 0
	#   → 画面照常 60FPS、但所有节点 delta=0，输入/移动/动画全停（表现为"卡死"）。
	#   必须显式传第 4 个参数 true 才会按真实时间倒计时。
	await get_tree().create_timer(dur, true, false, true).timeout
	_end_hitstop()

func _end_hitstop() -> void:
	if not _stopping:
		return
	_stopping = false
	_stop_deadline_ms = 0
	Engine.time_scale = 1.0

## 真实时间兜底：即使计时器因任何原因没回调，也绝不让全局时间停在 0。
## （time_scale=0 时 delta≈0，但 _process 仍每帧被调用，故用真实时钟判断。）
func _process(_delta: float) -> void:
	if _stopping and _stop_deadline_ms > 0 and Time.get_ticks_msec() >= _stop_deadline_ms:
		push_warning("[CombatJuice] hitstop 计时器未回调，已强制恢复 time_scale（兜底）")
		_end_hitstop()
