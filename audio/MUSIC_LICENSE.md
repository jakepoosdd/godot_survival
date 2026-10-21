# 背景音乐 / Background Music

| 文件 | 来源 | 作者 | 许可 |
|---|---|---|---|
| `feel_good_island_loop.ogg` | OpenGameArt：[Feel Good Island Loop](https://opengameart.org/content/feel-good-island-loop) | Brandon Morris（原曲）；AntumDeluge 裁剪并做无缝循环 | **CC0 公共领域（无版权，无需署名）** |

## 许可说明
该曲在 OpenGameArt 上同时列有 **OGA-BY 3.0** 与 **CC0** 两种许可；本项目采用其中的 **CC0（Public Domain）** 授权：
可任意使用、修改、再分发，**无需署名、无版权顾虑**，符合「不要版权」的要求。

## 技术对接
- 已做无缝循环（loop），作为第三人称荒岛生存游戏的常驻 BGM。
- 由 `AudioManager.play_music("feel_good_island_loop")` 在 `core/menus.gd` 的 `_start_game()`（开始游戏/新游戏/读档）处触发，`_music_player.loop = true` 保证循环。
- 音量：`AudioManager.music_volume`（默认 0.6），由设置面板的「音乐音量」滑块控制；总线为 `Master`。
- 资源缺失时 `AudioManager` 静默跳过，不会影响游戏运行（数据驱动，放入文件即生效）。
