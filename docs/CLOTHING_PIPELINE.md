# 服装与角色外观

## 游戏内使用

玩家默认使用 Universal Base 男性基础模型及其原始外观，穿 T 恤、牛仔裤、运动鞋、袜子和男式内衣。NPC 出生时随机性别及发型；僵尸继续使用原有 `Zombie.fbx`，按该男性身体穿戴内衣。NPC／僵尸初始服装优先从 CasualWear、Park Ranger、Medical Lite 中选一套，缺少的基础上衣、鞋和内衣用其他目录补足。

示例地图卧室衣柜包含 `assets/Clothes` 的全部 35 件独立衣物与配饰。搜索衣柜后，通过物品栏的穿戴／移除操作换装。男女目录下的内衣限制穿戴性别，其余服装不限性别；拒绝不兼容的换装不会先脱掉原衣物。

同一文件中的独立网格拆成物品；相同衣物的 FBX 和 glTF 导出不重复登记。除原有槽位外，新增 `underwear_top`、`underwear_bottom`、`socks`、`belt`、`neck`、`badge`、`medical_support`。医疗资源中的拐杖、固定器等也作为配饰登记，暂不提供独立治疗效果。

NPC／僵尸共享 `ClothingSystem.wear(uid)`、`remove(slot)` 和 `InventoryGrid`。这些命令更新实际库存，渲染随后读取槽位；没有第二套“外观装备”。当前没有对其他角色的换装 UI 或尸体搜刮，死亡处理仍沿用现有逻辑。

## 预览

打开 `scenes/characters/character_preview.tscn`，按 F6：

- C：切换三组资源套装。
- R：脱下全部衣物／穿回套装。
- B：显示独立的身体判定框；鼠标点击检查部位。

预览同时显示男性、女性与原僵尸，正常播放行走或攻击动画。此场景中的衣物切换不修改主游戏存档。

## 数据和动画

- `ClothingCatalog` 保存稳定物品 ID、源文件、网格名称、槽位、性别和套装分组。物品的重量、防护、保暖等暂用原型默认值。
- `CharacterAppearance` 保存性别与发型。基础模型本身没有额外发型网格，`original` 表示保留基础模型原貌；其他发型取自资源包的独立 Hair 文件。
- `MixamoCharacterVisual` 将现有人类动作的旋转从 Mixamo 静止骨架转换到 Universal 骨架；不是仅修改骨骼名称。根位移和人体长度仍由目标骨架及游戏模拟决定。僵尸保留原有动作重定向路径。
- `CharacterClothingVisual` 只在装备 ID 变化时替换网格。衣物直接引用角色骨架，不创建额外动画播放器。外衣遮住内层时隐藏内层显示，装备与防护数据仍保留；帽子隐藏头发，脱帽后恢复。
- 身体遮罩只删去被遮挡的渲染三角形，脱衣恢复原网格；不修改伤害判定框。网格、动画和有限数量的身体遮罩组合共享缓存。

## 重建绑定资源

原服装没有权重，且采用 A 姿势。以下离线场景将源网格变换、原始材质和源姿势标记转换到三种目标身体，再插值目标身体表面的骨骼权重；贴身手套按实际手指表面重新适配。原始资源不被覆盖。

```text
godot --headless --path . res://tools/bake_clothing.tscn
godot --headless --path . res://tools/bake_clothing.tscn -- --body=female --item=medical_shirt
```

输出为 `resources/clothing/{male,female,zombie}/*.res`，包括绑定网格、材质引用与身体遮罩。运行时直接加载这些资源。新增衣物时登记 `ClothingCatalog.SOURCES`，重建后检查静止、行走和攻击姿势。现有骨架或源模型尺寸发生变化时，也需要重建。

该流程不等同于逐件人工蒙皮。肩部、袖口、长发、鞋裤接缝及跨套装组合仍可能局部穿模；没有布料模拟、头发物理或远距离服装 LOD。

## 保存与验证

存档格式 v13 保存玩家外观以及 NPC／僵尸的外观、独立库存、装备槽和衣物实例。旧 v3–v12 存档在副本上迁移，保留玩家已有物品；旧 NPC／僵尸使用原始男性外观和空装备，避免凭空重置历史物资。新默认槽为 `user://afterlight_mvp_v13.save`，旧文件不改写。

```text
godot --headless --path . res://tests/wardrobe_tests.tscn
godot --headless --path . res://tests/mvp_smoke_test.tscn
godot --path . res://scenes/characters/character_preview.tscn -- --benchmark
```

换装专项覆盖资源完整性、权重、性别限制、三类角色实时穿脱、缓存复用、存档恢复及旧档迁移。完整旧回归目前有 3 项声音／NPC 行为失败，已用改动前最新提交的代码复现，未在本任务中修改这些行为。

2026-10-06，RTX 4070 SUPER、D3D12 Forward+、1280×720 的 64 个穿衣且播放动画的混合角色场景（含肩部／鞋靴内衬）：远距离角色以 30／15 Hz 展示层姿势更新后，帧时间中位数 6.07 ms、P95 7.13 ms，渲染 CPU P95 0.89 ms、GPU P95 1.68 ms，671 次 draw call，视频内存约 970 MiB。该测量不包含 AI 或完整地图；现有源贴图分辨率较高，不能将这个结果当作完整游戏规模的性能保证。
