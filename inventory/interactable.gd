extends StaticBody3D
## 可交互物基类契约。任何能被交互的节点都 extends 它，并实现 interact(player)。
## 交互系统靠 has_method("interact") 识别，不依赖具体类型 -> 可任意替换/新增。

class_name Interactable

@export var prompt := "交互"

func interact(_player) -> void:
	pass
