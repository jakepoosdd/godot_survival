extends Node
## 公告板（Autoload: Bulletin）。维护公告列表，阶段变化时推送新公告。
## 世界里的公告板可被交互打开查看（EventBus.bulletin_opened）。

var entries: Array[Dictionary] = []   # {id, title, body}
var seen: Dictionary = {}             # id -> bool
signal bulletin_changed()

func _ready() -> void:
	_add("welcome", "欢迎来到荒岛", "你是空难唯一的幸存者。白天采集、夜晚警惕野兽，目标是在荒岛活下去。按 U 查看任务，按 L 用经验解锁技能。")
	_add("keys", "快捷键", "移动 WASD　跳跃 空格　冲刺 Shift　视角 V\n交互/采集/放置 E　建造 B（TAB 切换建筑）\n背包 I　制作 C　技能 L　任务 U　成就 K　伙伴 T\n进食 F　治疗 R（仅魔法师）　钓鱼手册 P\n数字键 1-6 快捷栏/装备　Esc 关闭当前面板")
	_add("party", "伙伴与好感", "送礼或完成任务可提升女主好感。好感与心情全满后，次日黎明会随机感召一位新伙伴加入；好感满时靠近女主按 E，还能从菜单指定召唤或复活伙伴（消耗好感）。伙伴会随你战斗、采集与守夜。")
	_add("siege", "怪物攻城", "入夜后野兽会袭击营地：先造好栅栏，天亮前守住；成功守夜可加好感。第 90 天前务必前往岛心祭坛讨伐 BOSS「巨口魔 Maw」，否则它将率众攻营，栅栏全破即游戏结束。")
	EventBus.stage_changed.connect(_on_stage)

func _add(id: String, title: String, body: String) -> void:
	if _has_id(id):
		return
	entries.append({"id": id, "title": title, "body": body})
	bulletin_changed.emit()

func _has_id(id: String) -> bool:
	for e in entries:
		if e["id"] == id:
			return true
	return false

func _on_stage(idx: int, name: String, desc: String) -> void:
	var id := "stage_%d" % idx
	_add(id, "阶段：%s" % name, desc)
	EventBus.toast.emit("新公告：%s" % name)

func get_entries() -> Array[Dictionary]:
	return entries

func mark_seen(id: String) -> void:
	seen[id] = true
