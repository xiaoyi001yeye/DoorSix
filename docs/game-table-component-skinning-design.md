# 牌桌换肤与资源规范

## 1. 目标

新版牌桌要在不破坏当前稳定牌桌的前提下逐步接入。本文只定义必须稳定下来的实现契约、切换方式、文案规则和图片资源标准。

核心目标：

- 保留当前牌桌，新增新版牌桌，通过设置切换。
- 本地练习桌和联机桌共用新版牌桌组件。
- 皮肤资源可替换，替换图片时尽量不改组件代码。
- 按钮可增减，文案不会因屏幕或皮肤变化而溢出。

非目标：

- 不在第一版重写当前 `GameTableLayout`、`TableCenter`、`HandArea`、`GameActionBar`。
- 不把回放、语音、表情等远期能力一次性做完。
- 不把动态文字画死进图片资源。

## 2. 新旧牌桌并行

新增牌桌体验配置：

```dart
enum GameTableExperience {
  legacy,
  immersive,
}
```

| 模式 | 说明 |
| --- | --- |
| `legacy` | 当前稳定牌桌，继续使用现有组件。默认值。 |
| `immersive` | 新版牌桌，使用新的组件、布局和皮肤资源。 |

设置入口复用当前配置按钮，在显示设置中增加：

```text
牌桌样式
[ 经典牌桌 ] [ 新版牌桌 ]
```

配置持久化到 `SharedPreferences`。本地模式和联机模式读取同一份配置。切换只改变 UI，不重置对局，不触发出牌、过牌、同步或重连。

页面层只做分流：

```dart
switch (settings.experience) {
  case GameTableExperience.legacy:
    return buildLegacyTable();
  case GameTableExperience.immersive:
    return GameTableShell(
      theme: theme,
      state: viewModel,
      actions: actions,
    );
}
```

新版牌桌建议放在独立目录：

```text
lib/widgets/game_table_v2/
├── game_table_shell.dart
├── game_table_theme.dart
├── game_table_view_model.dart
├── game_table_actions.dart
├── game_table_top_bar.dart
├── game_table_player_seat.dart
├── game_table_center.dart
├── game_table_hand_area.dart
├── game_table_action_panel.dart
└── adapters/
    ├── local_game_table_adapter.dart
    └── online_game_table_adapter.dart
```

## 3. 统一数据模型

新版牌桌不直接读取本地状态或联机快照。两种模式先转成统一模型：

```text
本地练习状态 ─┐
              ├─> GameTableViewModel + List<GameActionItem> ─> GameTableShell
联机快照    ─┘
```

最小展示模型：

```dart
class GameTableViewModel {
  final String? roomCode;
  final int roundNo;
  final int teamAScore;
  final int teamBScore;
  final NetworkQuality? networkQuality;
  final int? turnSecondsRemaining;
  final int? currentTrickIndex;
  final int? totalTrickCount;
  final List<GamePlayerViewModel> players;
  final TableCenterViewModel center;
  final HandViewModel hand;
}
```

兼容规则：

- 本地模式没有房间号和网络状态时传 `null`，顶栏隐藏对应区域。
- 联机模式用服务端 deadline 推导 `turnSecondsRemaining`。
- 本地模式用本地 timer 填同一个 `turnSecondsRemaining`。
- `currentTrickIndex / totalTrickCount` 暂时没有稳定来源时可以为空。

## 4. 按钮与文案

操作区由动作列表驱动，不写死固定按钮。

```dart
class GameActionItem {
  final GameActionKind kind;
  final String label;
  final IconData icon;
  final GameActionPlacement placement;
  final bool enabled;
  final bool visible;
  final String? disabledReason;
  final VoidCallback? onPressed;
}
```

```dart
enum GameActionPlacement {
  primary,
  secondary,
  utility,
  topBar,
}
```

横屏主操作区最多放 3 个按钮：

- `整理`
- `不出`
- `出牌`

更多动作进入左下辅助区、顶栏或更多菜单。

常用动作文案：

| 业务动作 | 横屏文案 | 竖屏文案 | 说明 |
| --- | --- | --- | --- |
| hint | 提示 | 提示 | 辅助区优先 |
| sort | 整理 | 整理 | 主操作区 |
| play | 出牌 | 出牌 | 主按钮 |
| pass | 不出 | 过 | 同一业务动作，不同展示文案 |
| replay | 回放 | 回放 | 顶栏 |
| settings | 设置 | 设置 | 顶栏 |

文案规则：

- 业务文字由 Flutter 绘制，不画进按钮或面板图片。
- 同一语义准备 `full / short / compact` 三档文案。
- 空间不足时降级顺序为：图标+完整文字、图标+短文字、纯图标+tooltip、更多菜单。
- 按钮文字不换两行，最小字号低于 12 时改为纯图标。
- 玩家名最多显示 4 到 6 个中文字符，超出截断。
- 倒计时、比分、房间号使用固定宽度容器，避免数字变化造成布局跳动。

## 5. 皮肤主题

皮肤通过主题对象和资源清单接入，不在组件中硬编码图片路径。

```dart
class GameTableThemeData {
  final String themeId;
  final Color textPrimary;
  final Color textSecondary;
  final Color teamAColor;
  final Color teamBColor;
  final Color panelColor;
  final Color accentColor;
  final GameTableAssets assets;
  final GameTableTypeScale typeScale;
}
```

首批建议保留两套：

- `classic_green`：当前深绿牌桌的轻量复刻。
- `tianjin_ink`：宣纸、水墨地图、蓝金按钮、天津装饰。

皮肤可以改变背景、按钮、头像、颜色、面板纹理和文案长短。皮肤不能改变出牌规则、按钮启用条件、结算逻辑和联机协议。

装饰层必须使用 `IgnorePointer`，不能遮挡手牌和按钮点击。

## 6. 布局标准

新版横屏按 `1800 x 900` 作为设计基准，比例为 `2:1`。Flutter 布局按设备尺寸等比和约束缩放，不要求设备真实分辨率等于基准尺寸。

```text
设计基准：1800 x 900
安全区：左右 48，上 32，下 32
顶部栏高度：88
底部手牌区高度：280
右侧操作区宽度：250
中心出牌区：x 720-1080, y 230-520
```

横屏布局区域：

```text
顶部：返回、房间号、局数、比分、网络、规则、回放、设置
中央：6 个玩家座位、上一手牌、当前轮次
底部：我的手牌横铺
右侧：整理 / 不出 / 出牌
左下：提示等辅助按钮
```

竖屏继续使用上下结构，但复用同一套 `GameTableViewModel`、动作模型和皮肤 token。

## 7. 图片资源标准

### 7.1 路径

每套皮肤一个目录，使用小写英文、数字和下划线。

```text
assets/images/themes/{theme_id}/
├── table_bg.webp
├── table_bg_portrait.webp
├── top_bar_panel.png
├── hand_panel.png
├── center_panel.png
├── seat_panel_self.png
├── seat_panel_ally.png
├── seat_panel_opponent.png
├── seat_panel_current.png
├── button_primary.png
├── button_secondary.png
├── button_disabled.png
├── button_utility.png
├── icon_circle.png
├── badge_timer.png
├── card_stack_icon.png
├── avatar_player.png
├── avatar_ai.png
├── manifest.json
└── decorations/
    ├── tianjin_title.png
    ├── food_jianbing.png
    ├── food_baozi.png
    ├── landmark_bridge.png
    └── label_jiefang_bridge.png
```

倍率目录按 Flutter 标准：

```text
assets/images/themes/tianjin_ink/table_bg.webp
assets/images/themes/tianjin_ink/2.0x/table_bg.webp
assets/images/themes/tianjin_ink/3.0x/table_bg.webp
```

大背景可以只提供 `1.0x / 2.0x`。按钮、头像、座位面板建议提供到 `3.0x`。

### 7.2 尺寸

| 元素 | 文件名 | 逻辑尺寸 | 格式 | 备注 |
| --- | --- | ---: | --- | --- |
| 横屏背景 | `table_bg.webp` | `1800 x 900` | WebP/PNG | 全屏底图 |
| 竖屏背景 | `table_bg_portrait.webp` | `900 x 1800` | WebP/PNG | 可选 |
| 顶部状态栏底板 | `top_bar_panel.png` | `760 x 64` | PNG | 文字由 Flutter 绘制 |
| 倒计时徽章 | `badge_timer.png` | `150 x 54` | PNG | 数字由 Flutter 绘制 |
| 玩家座位底板 | `seat_panel_*.png` | `320 x 112` | PNG | 按状态区分 |
| 玩家头像 | `avatar_player.png` | `144 x 144` | PNG | 透明背景 |
| AI 头像 | `avatar_ai.png` | `144 x 144` | PNG | 透明背景 |
| 中央出牌面板 | `center_panel.png` | `360 x 260` | PNG | 可半透明 |
| 手牌底板 | `hand_panel.png` | `980 x 270` | PNG | 建议可拉伸 |
| 主按钮 | `button_primary.png` | `176 x 72` | PNG | 出牌 |
| 次按钮 | `button_secondary.png` | `176 x 72` | PNG | 整理 / 不出 |
| 工具按钮 | `button_utility.png` | `132 x 58` | PNG | 提示 |
| 顶部圆形图标底 | `icon_circle.png` | `64 x 64` | PNG | 规则 / 回放 / 设置 |
| 牌背小图标 | `card_stack_icon.png` | `56 x 48` | PNG | 余牌图标 |
| 竖排标签 | `decorations/label_*.png` | `72 x 180` | PNG | 装饰文字可选 |

倍率示例：

| 逻辑尺寸 | 1.0x | 2.0x | 3.0x |
| --- | --- | --- | --- |
| `1800 x 900` | `1800 x 900` | `3600 x 1800` | `5400 x 2700` |
| `176 x 72` | `176 x 72` | `352 x 144` | `528 x 216` |
| `144 x 144` | `144 x 144` | `288 x 288` | `432 x 432` |

### 7.3 可拉伸规则

需要适配不同宽度的资源使用九宫格拉伸，图片只承担边框、纹理、阴影和底色。

| 资源 | 固定边距 | 拉伸区域 |
| --- | ---: | --- |
| `top_bar_panel.png` | 左右 32，上下 16 | 中间横向 |
| `seat_panel_*.png` | 左右 36，上下 24 | 中间横向 |
| `hand_panel.png` | 左右 48，上下 36 | 中心双向 |
| `button_*.png` | 左右 28，上下 18 | 中间横向 |

实现优先用 `DecorationImage.centerSlice`。如果图片拉伸效果不稳定，改用 Flutter `BoxDecoration` 绘制面板，图片只作为纹理叠层。

### 7.4 背景避让区

背景制作时不要把高对比关键图案放进交互区。

```text
顶部栏避让区：x 0-1800, y 0-110
底部手牌避让区：x 380-1380, y 610-890
右侧按钮避让区：x 1450-1770, y 560-870
左侧提示避让区：x 160-420, y 560-690
中心出牌避让区：x 760-1040, y 220-560
```

适合放装饰的位置：

- 左上标题区。
- 左下食物或地域装饰区。
- 右上食物装饰区。
- 右侧玩家之间的标签区。
- 中远景城市、桥梁、河道背景区。

### 7.5 图片文字边界

图片资源不要包含动态文字：

- 房间号、局数、比分。
- 网络状态、倒计时。
- 玩家名、余牌数。
- 按钮文案。
- 当前轮次。
- 牌型说明。

图片可以包含固定装饰字，例如背景里的“天津”或地标题签，但这些文字不作为唯一信息来源。

### 7.6 Manifest

每套皮肤维护一个清单，方便检查缺失资源：

```json
{
  "themeId": "tianjin_ink",
  "version": 1,
  "baseSize": { "width": 1800, "height": 900 },
  "assets": {
    "tableBackground": "table_bg.webp",
    "topBarPanel": "top_bar_panel.png",
    "handPanel": "hand_panel.png",
    "seatPanelSelf": "seat_panel_self.png",
    "seatPanelAlly": "seat_panel_ally.png",
    "seatPanelOpponent": "seat_panel_opponent.png",
    "buttonPrimary": "button_primary.png",
    "buttonSecondary": "button_secondary.png",
    "avatarPlayer": "avatar_player.png",
    "avatarAi": "avatar_ai.png"
  }
}
```

## 8. 迁移步骤

1. 新增 `GameTableExperience` 设置，默认 `legacy`。
2. 配置弹层增加“经典牌桌 / 新版牌桌”切换。
3. 新建 `game_table_v2` 目录和空壳 `GameTableShell`。
4. 新增本地和联机 adapter，输出统一 `GameTableViewModel`。
5. 实现新版横屏布局：顶栏、座位、中央、手牌、右侧按钮。
6. 接入 `tianjin_ink` 资源和 manifest。
7. 验收通过后再考虑把默认值从 `legacy` 改为 `immersive`。

## 9. 验收标准

- 本地练习桌和联机桌都可以切换老牌桌 / 新牌桌。
- 切换牌桌不重置当前对局，不丢失已选手牌。
- 新牌桌出问题时可以通过设置退回 `legacy`。
- 新皮肤按固定路径和命名交付，替换图片不需要改组件代码。
- 图片不包含动态业务文字。
- 小屏横屏下玩家名、房间号、比分、倒计时和按钮文案不溢出。
- 横屏下 6 个座位、手牌、中央出牌区和右侧按钮互不遮挡。
- 装饰层不拦截点击。
- manifest 中声明的文件都实际存在。
