# Afterlight：Orangeville 多楼层 MVP

Godot 4.7.2 单机 3D 灰盒生存原型。两栋两层住宅、一栋三层商店；玩家、僵尸和 NPC 共用真实分层通行与楼梯路径。无需外部美术资源。

用 Godot 打开本目录，按 F6/F5 运行场景/项目，或在此目录执行：

```bash
flatpak run org.godotengine.Godot --path .
```

## 操作

| 输入 | 操作 |
| --- | --- |
| WASD / Shift | 按画面方向移动 / 冲刺 |
| 右键按住 / 左键 | 面向鼠标准备；武器攻击，或切换手持开关设备；无武器时推击 |
| 中键水平拖动 / 滚轮 | 旋转相机 / 缩放 |
| 沿楼梯方向走入端部平台 | 上下楼；途中可停下或反向 |
| E | 搜索、收取已知物资；疲劳低于 70 时在床边睡眠；动作中再次按 E 取消 |
| F / V / R | 吃 / 喝 / 整理背包 |
| 移动、瞄准、攻击、Esc、受伤 | 中断动作；搜索进度保留 |
| Space / 1 / 2 | 暂停 / 正常 / 3 倍速；HUD 也有按钮 |
| Inventory、Help 按钮 | 展开物品栏 / 操作帮助 |
| C / Character 按钮 | 打开人物状态；Health 页处理伤病，Skills & Traits 页查看职业、力量/体能、技能与特质 |
| 游戏窗口内 F5 / F9 | 快速保存 / 读档后暂停 |
| 死亡后 Enter | 新开一局 |

## 试玩路线

1. 从出生点进入附近住宅的地面门洞。紫色标记是床；木色楼梯连接上层，站到端部再顺着踏步走。
2. 前往商店，从地面门洞进入。蓝色标记是容器；E 搜索会消耗游戏时间，移动可立即取消。
3. 商店内两段楼梯分别连接一至二层、二至三层，每层有独立物资和墙体。僵尸能沿楼梯追击，血条只在对应僵尸可见时出现。
4. 疲劳低于 70 后回住宅床边睡眠；世界会统一加速，危险接近或疲劳恢复会唤醒玩家。
5. 橙色碎玻璃是可选的伤病验证点。人物页可处理流血、普通伤口感染、骨折与烧伤；隐藏的僵尸病毒状态始终独立。

地图尚为小型占位街区；屋顶不可行走，当前不支持跳窗坠落、电梯或结构破坏。NPC 会寻找已知有限物资、吃喝、上楼休息与避险；完整社交不在此版本内。

详见 [当前进度与多楼层设计](docs/MVP_BLUEPRINT.md)。

建筑显示使用独立楼层组件进行室内剖切，后侧墙保持可见；室外挡住玩家的建筑也会自动剖切，移出视线后恢复。路牌、树木在玩家投影附近局部抖动淡化。组件接口和适用范围见 [建筑可见性说明](docs/BUILDING_VISIBILITY.md)。

## 验证

```bash
flatpak run org.godotengine.Godot --headless --path . --editor --quit
flatpak run org.godotengine.Godot --headless --path . res://tests/mvp_smoke_test.tscn
```

测试覆盖分层碰撞、全部楼梯、跨层 AI、近战隔离、血条隐藏、需求/库存、动作取消、倍速及存档恢复。可选真实画面检查（短暂打开窗口，截图写入被忽略的 .godot 目录）：

```bash
flatpak run org.godotengine.Godot --path . res://tests/mvp_smoke_test.tscn -- --capture
```

新游戏先按 PZ 42.21 规则选择职业与特质；世界额外自由点默认为 0，Custom Occupation 提供 8 点。完整数据来源、已接入效果和待接入项见 [角色属性、技能、职业与特质](docs/CHARACTER_SYSTEM.md)。

保存文件位于 Godot 的项目用户数据目录，槽名为 `afterlight_mvp_v7.save`。版本 7 额外保存有限僵尸种群账本、感知/搜索记忆和迁移状态；没有 v7 时会读取并迁移 v6/v5/v4/v3。

僵尸只在世界初始化时按区域压力分配，总量上限仍为 7；死亡后不会刷新。存量僵尸可以在相邻区域间实际行走迁移，视觉记忆、匿名声音调查和松散聚集规则见 [僵尸感知与局部压力](docs/ZOMBIE_PERCEPTION_SYSTEM.md)。

背包现使用纯体积容量。出生点附近 `(5.7, 7.0)` 有背包测试箱；打开 Pack / health，选择箱子后 Search，可检查小背包、登山包和破损背包。展开物品组可查看单件口味、体积和重量。选择单件后 Use / resume、Equip 或 Move one；Transfer all 按顺序逐件转移，装不下下一件即停止。详见 [背包与物品系统](docs/BACKPACK_SYSTEM.md)。

出生点旁的 Test wardrobe 提供九类样衣、Needle、Thread、Rag 和 Flashlight。已穿衣物显示在 All carried 中，但身体部位和穿戴槽不会伪装成物品容器；按 C 打开独立角色状态栏。双击或右键可换装、按身体部位修理或切换手持设备。分区保护、耐久、温暖和销毁掉落规则见 [衣物与手持设备](docs/CLOTHING_SYSTEM.md)。
