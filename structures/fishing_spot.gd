extends Node3D
class_name FishingSpot
## 钓点：靠近按 E 触发全面钓鱼系统（FishingSystem）。
## 具体流程（抛竿 → 等待 → 咬钩 → 张力博弈 → 入护/脱钩 → 图鉴/冷藏箱/装备）
## 全部由 FishingSystem 驱动；玩家鱼竿动画由 player.gd 监听 EventBus.fishing_* 播放。
## 想要「码头/栈桥」等特殊栖息地，可在编辑器把 habitat_override 设为 "pier"。

@export var habitat_override: String = ""   # 例："pier" 强制该钓点为码头栖息地

var prompt := "钓鱼点（按 E 抛竿）"

func interact(_p) -> void:
	# 钓鱼中只有当前这一竿在跑，其它钓点点击只给提示，不并行开第二竿
	if not FishingSystem.is_idle():
		EventBus.toast.emit("已经在上竿了，先收竿")
		return
	FishingSystem.begin(global_position, habitat_override)
