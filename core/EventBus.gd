extends Node
## 全局信号总线。块之间只通过这里通信，互不持有节点引用。
## 改这里 = 加跨块信号，其它块只在 _ready 里 connect，互不影响。

# 生存 / 需求
signal needs_changed(stat: String, value: float)   # stat: "hunger"|"health"|"sanity"
signal player_died()
# 背包 / 采集
signal inventory_changed()
signal item_picked_up(item_id: String, amount: int)
signal resource_harvested(source, drops: Dictionary)
signal interactable_changed(prompt: String)         # 当前可交互物提示（""=无）
signal npc_menu_requested(npc_name: String, options: Array, target)  # NPC 交互菜单（交谈/送礼…）：options=[{id,label,hint}]，target=NPC 节点
# 制作 / 建造
signal recipe_crafted(recipe_id: String)
signal structure_placed(structure_id: String, at: Vector3)
signal build_menu_requested(open: bool)             # B / 建造热键：打开/关闭建造选择菜单
var build_menu_open: bool = false                   # HUD 建造菜单打开时置 true
# 烹饪 / 进食
signal food_cooked(item_id: String)        # 在营火上烤好食物
signal food_eaten(item_id: String)         # 玩家进食某消耗品
signal cooking_menu_requested()            # 靠近烹饪设施且持有可烹饪食材时请求打开烹饪菜单
signal camp_storage_requested()            # 靠近柜子时请求打开营地仓库面板
var cooking_menu_open: bool = false        # HUD 打开烹饪菜单时置 true，供交互物避免重复触发
signal structure_damaged(structure_id: String, hp_left: float)
# 生物 / 战斗
signal creature_spawned(creature)
signal creature_died(creature, drops: Dictionary)   # creature 为死亡敌人节点，其 _killer 字段记录最后一击来源（玩家/伙伴）
signal player_attacked(target, damage: float)   # 玩家击中某敌人(target) 造成 damage
signal player_damaged(amount: float)            # 敌人击中玩家，扣 amount 血（由 NeedsSystem 消费）
signal damage_popup(pos: Vector3, amount: float, kind: String)  # kind: "enemy" | "player"
# 经验 / 等级 / 技能
signal xp_awarded(amount: int)
signal xp_changed(total: int, available: int, level: int, xp_into: int, xp_needed: int)
signal leveled_up(level: int)
signal skill_unlocked(skill_id: String)
# 世界 / 系统
signal time_of_day_changed(t: float)                # 0..1
signal weather_changed(state: String)               # "clear"|"rain"|"storm"|"snow"
signal game_paused(paused: bool)
signal toast(text: String)                          # 一次性提示（HUD 短暂显示）
signal save_requested()
signal load_requested(data: Dictionary)

# 经济 / 商店
signal gold_changed(gold: int)
signal shop_requested()                       # 商人交互：打开商店
signal trade_made()                           # 完成一笔交易（买或卖）
# 阶段 / 公告 / 成就
signal stage_changed(index: int, name: String, desc: String)
signal day_changed(day: int)
signal bulletin_opened()                      # 公告板交互：打开公告
signal achievement_unlocked(id: String, name: String, desc: String)

# 战斗打击感（阶段1：定格 + 击退；仅玩家近战命中触发反馈）
signal hit_registered(victim: Node, dir: Vector3, damage: float, by_player: bool)

# 防御 / 栅栏
signal fence_damaged(seg: int, hp_left: float)
signal fence_broken(seg: int)
signal fence_upgraded(level: int)
# 关系 / 好感 / 心情
signal affection_changed(value: float)
signal mood_changed(value: float)
signal companion_bred(type: String)          # type: "gather"|"fighter"|"versatile"
# 钓鱼 / 巢穴 / 夜袭
signal fishing_caught(fish_id: String, amount: int)
signal fishing_started(spot_pos: Vector3)   # 玩家开始钓鱼会话（面朝钓点、举起竿）
signal fishing_cast()                       # 抛竿动作
signal fishing_bite()                       # 浮标下沉 / 咬钩
signal fishing_result(success: bool)        # 收竿结果（true=钓到, false=鱼跑了）
signal fishing_ended()                      # 会话结束，收竿隐藏
# 全面钓鱼系统（FishingSystem）新增信号：驱动 UI 与装备
signal fishing_gear_changed()               # 装备升级后刷新界面
signal fishing_fight_started(data: Dictionary)   # 进入张力博弈（传递鱼信息）
signal fishing_tension(tension: float, progress: float, name: String)  # 每帧张力/进度
signal fishing_fight_state(info: Dictionary)  # 每帧鱼的状态（名/体长/体重/距离/冲刺/体力），驱动"拉力对决"面板
signal fishing_catch_card(data: Dictionary) # 钓到后展示入护卡
signal fishing_log_updated()                # 图鉴/冷藏箱变更刷新
signal fishing_xp_changed(xp: int)          # 钓鱼经验（用于升级装备的货币）变化
signal nest_available()                       # 满足反攻条件，解锁岛心巢穴
signal nest_cleared()                         # 通关（祭坛被毁、雾散）
signal raid_wave_started(day: int, beasts: int, raiders: int)
signal raid_wave_ended()
signal game_over(reason: String)              # 营地失守等终局失败：弹出 GAME OVER 界面
