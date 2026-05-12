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

## 7. YAML 桌面配置

YAML 桌面配置是新版牌桌设计的补充层，不替代 `GameTableViewModel`、`GameActionItem` 或 Flutter 组件实现。它只描述新版桌面上有哪些元素、元素在哪、尺寸如何随屏幕变化、层级顺序和可复用样式 token。

兼容关系：

- `GameTableExperience.immersive` 仍然是新版牌桌入口，YAML 通过 `targetExperience: immersive` 绑定，不影响经典牌桌。
- `GameTableViewModel` 仍然提供牌局状态，YAML 不保存玩家、手牌、当前出牌者、比分和联机状态。
- `GameActionItem` 仍然提供动作列表和启用条件，YAML 只决定动作区域，例如顶栏、右侧操作栏、左下辅助区或竖屏底部栏。
- `GameTableThemeData` 和资源 manifest 可以逐步迁移为 YAML 的 `styles` / `assets` 区块，但皮肤不能改变业务规则。
- 布局日志应显示 YAML 的 `layer id`、`debugName` 和实际渲染出来的矩形，方便按配置回调参数。

边界规则：

- YAML 可以写 `component: HandDock`、`component: SeatStage` 这类组件名，但它们必须映射到 Dart 代码里的白名单组件。
- YAML 不允许直接执行表达式代码。第一版可以只支持固定字段、简单比例、`min/max` 和少量明确的公式名。
- 牌局规则、按钮是否可点、出牌校验、联机协议和动画状态不进入 YAML。
- 第一版只配置新版牌桌 `immersive`，不改经典牌桌。
- 布局计算以 Flutter 逻辑像素为准，不以手机物理像素为准。`devicePixelRatio` 只用于日志诊断。

建议文件路径：

```text
assets/config/table_layouts/immersive_tianjin_table.yaml
```

落地时需要把目录加入 `pubspec.yaml`：

```yaml
flutter:
  assets:
    - assets/config/table_layouts/
```

代码层建议新增：

```text
lib/widgets/game_table_v2/config/
├── game_table_layout_config.dart
├── game_table_layout_loader.dart
└── game_table_layout_resolver.dart
```

职责划分：

| 模块 | 职责 |
| --- | --- |
| `GameTableLayoutConfig` | YAML 解析后的强类型配置 |
| `GameTableLayoutLoader` | 从 assets 读取 YAML，校验 schema 和必填字段 |
| `GameTableLayoutResolver` | 根据屏幕方向、逻辑尺寸和 compact 规则计算实际布局参数 |
| `GameTableShell` | 只消费 resolver 输出，不直接解析 YAML |

### 7.1 网格桶定位

桌面元素可以支持 `bucket` 定位模式：把父容器平均切成固定数量的横向桶和纵向桶，元素用桶坐标描述位置和尺寸。

桶定位不是物理像素定位。它按当前 Flutter 逻辑尺寸换算：

```text
bucketWidth = parentLogicalWidth / columns
bucketHeight = parentLogicalHeight / rows
left = x * bucketWidth
top = y * bucketHeight
width = bucketWidthCount * bucketWidth
height = bucketHeightCount * bucketHeight
```

桶数越多，位置越精细；桶数越少，配置越容易读。建议默认使用 `100 x 100`，需要细调时优先允许小数桶坐标，而不是把桶数无限增大。

推荐规则：

| 桶网格 | 适用场景 | 说明 |
| --- | --- | --- |
| `100 x 100` | 默认人工调布局 | 接近百分比，读起来最直观 |
| `200 x 200` | 需要更细位置 | 精度提高，仍可手写维护 |
| `1000 x 1000` | 不推荐 | 基本等同另一种像素坐标 |

示例：

```yaml
layoutGrid:
  # 横向切成 100 个桶。
  columns: 100

  # 纵向切成 100 个桶。
  rows: 100

layers:
  - id: action_column
    component: ActionColumn
    position:
      # 使用网格桶定位。
      mode: bucket

      # 从父容器横向第 86 个桶开始。
      x: 86

      # 从父容器纵向第 66 个桶开始。
      y: 66

      # 宽度占 12 个横向桶。
      width: 12

      # 高度占 24 个纵向桶。
      height: 24

      # x/y 表示元素左上角。
      anchor: topLeft
```

单个动作按钮也可以提供桶坐标覆写，但建议作为特殊能力使用，默认仍由操作栏自动排列：

```yaml
actionOverrides:
  play:
    position:
      # 出牌按钮使用桶定位覆写。
      mode: bucket

      # 支持小数桶，便于微调，不必把全局桶数开到很大。
      x: 88.5
      y: 80.25

      # 按钮宽高同样用桶数描述。
      width: 10
      height: 8

      # x/y 表示按钮中心点。
      anchor: center
```

桶定位适合描述“大概在桌面哪个区域”，比绝对像素更适合跨设备；但它仍需要配合横屏、竖屏、紧凑模式分别配置，避免在小屏上和安全区、手牌区或操作栏互相遮挡。

### 7.2 带注释 YAML 草案

带注释的 YAML 草案如下。它是桌面说明书，不是最终实现约束；落地前可以继续删减字段，避免第一版解析器过重。

```yaml
# 配置文件格式版本，用来让代码知道该按哪套规则解析。
schema: door_six.game_table_layout.v1

# 当前布局配置的唯一 ID，后续可以支持多套桌面布局时用于选择。
id: immersive_tianjin_table

# 给人看的名称，主要用于调试、设置页或布局日志。
name: 新版沉浸式牌桌

# 这个配置只作用于新版牌桌，不影响经典牌桌。
targetExperience: immersive

# 设计基准信息，帮助理解坐标、尺寸和缩放规则。
design:
  # 设计稿基准尺寸。它不是手机真实分辨率，只是设计参考画布。
  baseSize:
    # 设计稿宽度。
    width: 1800

    # 设计稿高度。
    height: 900

  # 坐标模式。
  # absolute 表示主要用逻辑像素。
  # normalized 表示用 0-1 的比例坐标。
  # hybrid 表示外层区域用像素 token，座位等可用 alignment。
  coordinateMode: hybrid

  # 是否尊重系统安全区，比如刘海屏、底部手势条。
  safeArea:
    # 顶部是否避开安全区。
    top: true

    # 底部是否避开安全区。
    bottom: true

    # 左侧是否避开安全区。
    left: true

    # 右侧是否避开安全区。
    right: true

# 默认网格桶。bucket 定位模式会用这里的桶数换算逻辑坐标。
layoutGrid:
  # 横向切成 100 个桶，接近百分比，方便人工理解。
  columns: 100

  # 纵向切成 100 个桶，接近百分比，方便人工理解。
  rows: 100

# 响应式断点。代码根据屏幕尺寸选择 landscape / portrait / compact 布局。
breakpoints:
  # 横屏布局规则。
  landscape:
    # 满足这个条件时使用横屏布局。
    when:
      # 屏幕宽度大于高度时视为横屏。
      widthGreaterThanHeight: true

    # 横屏下进入紧凑模式的条件。
    compactWhen:
      # 逻辑高度小于这个值时进入紧凑横屏。
      maxLogicalHeight: 430

      # 逻辑宽度小于这个值时进入紧凑横屏。
      maxLogicalWidth: 900

  # 竖屏布局规则。
  portrait:
    # 满足这个条件时使用竖屏布局。
    when:
      # 屏幕宽度不大于高度时视为竖屏。
      widthGreaterThanHeight: false

# 桌面元素列表。每个 layer 对应牌桌上的一类可布局元素。
layers:
  # 背景层，放在最底下。
  - id: backdrop
    # 层级顺序，数字越小越靠后。
    zIndex: 0

    # 绑定到 Flutter 里的组件名称，必须是代码白名单里的组件。
    component: InkWashBackdrop

    # 背景铺满整个牌桌。
    bounds:
      # fill 表示填满父容器。
      mode: fill

  # 顶栏：返回、房间号、局数、比分、网络、设置、布局日志等。
  - id: top_bar
    # 顶栏在背景之上。
    zIndex: 10

    # 绑定到新版牌桌的顶栏组件。
    component: GameTopBar

    # 布局日志里显示的名称。
    debugName: 顶栏

    # 哪些屏幕方向显示这个元素。
    visibleIn:
      - landscape
      - portrait

    # 横屏下的布局参数。
    landscape:
      # 距离左边 12 逻辑像素。
      left: 12

      # 距离右边 12 逻辑像素。
      right: 12

      # 距离顶部 8 逻辑像素。
      top: 8

      # 顶栏高度。
      height: 54

    # 竖屏下的布局参数。
    portrait:
      # 竖屏顶栏外边距。
      padding:
        # 左边距。
        left: 10

        # 右边距。
        right: 10

        # 上边距。
        top: 6

        # 下边距。
        bottom: 6

      # 顶栏高度。
      height: 54

    # 顶栏内部样式和行为参数。
    style:
      # 使用 styles.bluePanel 这套面板样式。
      panel: bluePanel

      # 房间号最多显示一行，超出省略。
      roomTextMaxLines: 1

      # 屏幕宽度达到这个值才显示倒计时徽章。
      showTimerWhenWidthAtLeast: 700

      # 紧凑模式下顶栏只保留这些操作按钮。
      compactTopActions:
        - settings
        - layoutLog

  # 座位舞台：中央出牌区和其他玩家座位所在的大区域。
  - id: seat_stage
    # 位于顶栏和背景之上。
    zIndex: 20

    # 绑定座位舞台组件。
    component: SeatStage

    # 布局日志名称。
    debugName: 座位舞台

    # 横屏和竖屏都显示。
    visibleIn:
      - landscape
      - portrait

    # 横屏布局。
    landscape:
      # 普通横屏参数。
      regular:
        # 左边距。
        left: 18

        # 右边距。
        right: 18

        # 顶部要给顶栏留空间。
        top: 82

        # 底部要给手牌区留空间。
        bottom: 154

      # 紧凑横屏参数。
      compact:
        # 左边距。
        left: 18

        # 右侧要避开操作栏。
        rightFromActionColumn: 32

        # 紧凑时座位舞台更靠上。
        top: 74

        # 紧凑时给底部手牌留更大空间。
        bottom: 174

    # 竖屏布局。
    portrait:
      # expanded 表示在 Column 中占满剩余空间。
      layout: expanded

      # 竖屏左右留白。
      padding:
        # 左边距。
        left: 10

        # 右边距。
        right: 10

    # 座位舞台包含的子元素。
    children:
      # 中央出牌区。
      - center_play_panel

      # 玩家座位组。
      - player_seats

  # 中央出牌区：上一手牌、当前轮次、过牌数等。
  - id: center_play_panel
    # 位于座位舞台内，比舞台背景靠前。
    zIndex: 30

    # 绑定中央出牌区组件。
    component: CenterPlayPanel

    # 布局日志名称。
    debugName: 中央出牌区

    # 父元素是座位舞台，位置相对 seat_stage 计算。
    parent: seat_stage

    # 横屏布局。
    landscape:
      # 普通横屏布局。
      regular:
        # 锚点，0.5/0.5 表示放在父容器中心。
        anchor:
          # 水平居中。
          x: 0.5

          # 垂直居中。
          y: 0.5

        # 宽度规则。
        width:
          # 最大宽度。
          max: 340

          # 父容器宽度的 36%。
          ratioOfParentWidth: 0.36

      # 紧凑横屏布局。
      compact:
        # 锚点。
        anchor:
          # 水平居中。
          x: 0.5

          # 靠近底部。
          y: 1.0

        # 宽度规则。
        width:
          # 最小宽度。
          min: 118

          # 受普通中心区宽度缩放影响。
          ratioOfRegular: 0.58

        # 紧凑模式中心区高度参考值。
        height: 48

        # 额外偏移规则。
        offset:
          # 尽量和底部座位在垂直方向对齐。
          yAlignWithSeatBottom: true

    # 竖屏布局。
    portrait:
      # 竖屏中心区锚点。
      anchor:
        # 水平居中。
        x: 0.5

        # 垂直居中。
        y: 0.5

      # 竖屏宽度规则。
      width:
        # 最大宽度。
        max: 340

        # 父容器宽度的 72%。
        ratioOfParentWidth: 0.72

  # 玩家座位组：6 个玩家座位的位置、大小和显示规则。
  - id: player_seats
    # 座位在中央出牌区之上，避免被遮住。
    zIndex: 40

    # 绑定玩家座位组组件。
    component: PlayerSeatGroup

    # 父元素是座位舞台。
    parent: seat_stage

    # 总座位数。
    seatCount: 6

    # 座位索引模式。relativeToSelfSeat 表示以自己为 display0，其他座位相对旋转。
    seatIndexMode: relativeToSelfSeat

    # 普通布局下的座位配置。
    regular:
      # 普通座位尺寸。
      seatSize:
        # 座位宽度。
        width: 212

        # 座位高度。
        height: 76

      # display0-display5 是相对视角下的六个位置。
      positions:
        # display0 通常是自己，靠下居中。
        display0:
          # Flutter Alignment 坐标，x/y 范围通常是 -1 到 1。
          alignment:
            # 水平居中。
            x: 0.0

            # 靠下。
            y: 0.9

        # display1 左下。
        display1:
          alignment:
            x: -0.96
            y: 0.5

        # display2 左上。
        display2:
          alignment:
            x: -0.96
            y: -0.5

        # display3 上方居中。
        display3:
          alignment:
            x: 0.0
            y: -0.9

        # display4 右上。
        display4:
          alignment:
            x: 0.96
            y: -0.5

        # display5 右下。
        display5:
          alignment:
            x: 0.96
            y: 0.5

    # 紧凑布局下的座位配置。
    compact:
      # 紧凑模式下隐藏自己的座位，因为自己信息主要由手牌区体现。
      hideDisplaySeats:
        - 0

      # 紧凑座位尺寸。
      seatSize:
        # 宽度规则。
        width:
          # 最小宽度。
          min: 112

          # 最大宽度。
          max: 154

          # 宽度公式。当前代码逻辑等价于 (父宽 - 24) / 3，再限制 min/max。
          formula: "(parentWidth - 24) / 3"

        # 高度与宽度的比例，54 / 154 约等于 0.3506。
        heightRatio: 0.3506

      # 紧凑座位锚点。
      positions:
        # display1 放左下角。
        display1:
          anchor: bottomLeft

        # display2 放左上角。
        display2:
          anchor: topLeft

        # display3 放上方居中。
        display3:
          anchor: topCenter

        # display4 放右上角。
        display4:
          anchor: topRight

        # display5 放右下角。
        display5:
          anchor: bottomRight

  # 手牌区：自己的手牌横向滚动区域。
  - id: hand_dock
    # 手牌区在主要内容之上。
    zIndex: 50

    # 绑定手牌区组件。
    component: HandDock

    # 布局日志名称。
    debugName: 手牌区

    # 横屏竖屏都显示。
    visibleIn:
      - landscape
      - portrait

    # 横屏布局。
    landscape:
      # 普通横屏布局。
      regular:
        # 左边距，给左下辅助操作和桌面空间让位。
        left: 230

        # 右边距，给右侧操作栏让位。
        right: 252

        # 底部距离。
        bottom: 18

        # 横屏不显示“我的手牌/牌型状态”文字，节省高度。
        showStatus: false

      # 紧凑横屏布局。
      compact:
        # 左边距规则，取 160 和屏幕宽度 28% 里的较大值。
        left:
          maxOf:
            - 160
            - ratioOfScreenWidth: 0.28

        # 右边距基于操作栏宽度再加 40。
        rightFromActionColumn: 40

        # 底部距离。
        bottom: 10

        # 紧凑横屏也不显示状态文字。
        showStatus: false

    # 竖屏布局。
    portrait:
      # 竖屏手牌区外边距。
      padding:
        # 左边距。
        left: 10

        # 右边距。
        right: 10

        # 上边距。
        top: 0

        # 下边距。
        bottom: 8

      # 竖屏显示手牌数量和牌型状态。
      showStatus: true

    # 手牌内部卡牌排布。
    cardLayout:
      # 普通尺寸。
      regular:
        # 单张牌宽度。
        cardWidth: 68

        # 单张牌高度。
        cardHeight: 98

        # 选中牌上移距离。
        selectedLift: 18

        # 牌之间最小步进，避免重叠太狠。
        minStep: 30

        # 牌之间理想步进。
        preferredStep: 48

      # 紧凑尺寸。
      compact:
        # 紧凑牌宽度。
        cardWidth: 52

        # 紧凑牌高度。
        cardHeight: 75

        # 紧凑选中上移距离。
        selectedLift: 12

        # 紧凑最小步进。
        minStep: 24

        # 紧凑理想步进。
        preferredStep: 36

  # 横屏右侧操作栏：不出、出牌等主操作。
  - id: action_column
    # 操作栏放在最上层，保证可点击。
    zIndex: 60

    # 绑定右侧操作栏组件。
    component: ActionColumn

    # 布局日志名称。
    debugName: 右侧操作栏

    # 只在横屏显示。
    visibleIn:
      - landscape

    # 接收哪些动作分组。
    acceptsPlacements:
      # 主按钮。
      - primary

      # 次按钮。
      - secondary

    # 排除哪些动作。
    excludeKinds:
      # 当前横屏右侧栏不放“整理”。
      - sort

    # 横屏位置。
    landscape:
      # 普通横屏。
      regular:
        # 操作栏宽度。
        width: 148

        # 距离右侧。
        right: 28

        # 距离底部。
        bottom: 48

        # 按钮之间的间距。
        buttonGap: 10

        # 可选：用桶坐标描述操作栏位置。第一版可以先不用，保留给后续精调。
        bucketPosition:
          # 使用网格桶定位。
          mode: bucket

          # 从横向第 84 个桶开始。
          x: 84

          # 从纵向第 67 个桶开始。
          y: 67

          # 宽度占 12 个横向桶。
          width: 12

          # 高度占 22 个纵向桶。
          height: 22

          # x/y 表示左上角。
          anchor: topLeft

      # 紧凑横屏。
      compact:
        # 紧凑操作栏宽度。
        width: 132

        # 紧凑右边距。
        right: 16

        # 紧凑底部距离。
        bottom: 42

        # 紧凑按钮间距。
        buttonGap: 8

    # 可选：单个动作按钮的精确位置覆写。
    # 默认仍建议让 ActionColumn 自动排列按钮；只有特殊皮肤需要时才使用。
    actionOverrides:
      # 出牌按钮覆写。
      play:
        position:
          # 使用网格桶定位。
          mode: bucket

          # 支持小数桶，便于细调。
          x: 91.5

          # 支持小数桶，便于细调。
          y: 78.0

          # 按钮宽度占 8 个横向桶。
          width: 8

          # 按钮高度占 6 个纵向桶。
          height: 6

          # x/y 表示按钮中心点。
          anchor: center

  # 横屏左下辅助操作：提示等。
  - id: utility_actions
    # 和右侧操作栏同层。
    zIndex: 60

    # 绑定辅助操作组件。
    component: UtilityActions

    # 布局日志名称。
    debugName: 左下辅助操作

    # 只在横屏显示。
    visibleIn:
      - landscape

    # 接收 utility 类型动作。
    acceptsPlacements:
      - utility

    # 横屏位置。
    landscape:
      # 普通横屏。
      regular:
        # 辅助操作宽度。
        width: 96

        # 距离左侧。
        left: 132

        # 距离底部。
        bottom: 78

      # 紧凑横屏。
      compact:
        # 紧凑宽度。
        width: 88

        # 紧凑左边距。
        left: 86

        # 紧凑底部距离。
        bottom: 58

  # 竖屏底部操作栏：提示、不出、出牌等。
  - id: bottom_actions
    # 操作栏放在上层。
    zIndex: 60

    # 绑定竖屏底部操作栏组件。
    component: BottomActions

    # 布局日志名称。
    debugName: 竖屏底部操作栏

    # 只在竖屏显示。
    visibleIn:
      - portrait

    # 竖屏底部栏接收这些动作分组。
    acceptsPlacements:
      - primary
      - secondary
      - utility

    # 竖屏位置。
    portrait:
      # 外边距。
      padding:
        # 左边距。
        left: 10

        # 右边距。
        right: 10

        # 上边距。
        top: 0

        # 下边距。
        bottom: 12

# 可复用样式 token。元素通过 style.panel 等字段引用这里。
styles:
  # 蓝色面板，用于顶栏。
  bluePanel:
    # 圆角半径。
    radius: 18

    # 背景色。
    backgroundColor: "#0C4380"

    # 边框色。
    borderColor: "#FFECA8"

    # 主要文字颜色。
    textPrimary: "#FFECA8"

  # 玩家座位样式。
  playerSeat:
    # 普通座位样式。
    regular:
      # 宽度。
      width: 212

      # 高度。
      height: 76

      # 圆角。
      radius: 20

    # 紧凑座位样式。
    compact:
      # 宽度。
      width: 154

      # 高度。
      height: 54

      # 圆角。
      radius: 16

  # 操作按钮样式。
  actionButton:
    # 普通按钮。
    regular:
      # 按钮高度。
      height: 46

      # 圆角。
      radius: 16

    # 紧凑按钮。
    compact:
      # 按钮高度。
      height: 40

      # 圆角。
      radius: 14
```

## 8. 图片资源标准

### 8.1 路径

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

### 8.2 尺寸

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

### 8.3 可拉伸规则

需要适配不同宽度的资源使用九宫格拉伸，图片只承担边框、纹理、阴影和底色。

| 资源 | 固定边距 | 拉伸区域 |
| --- | ---: | --- |
| `top_bar_panel.png` | 左右 32，上下 16 | 中间横向 |
| `seat_panel_*.png` | 左右 36，上下 24 | 中间横向 |
| `hand_panel.png` | 左右 48，上下 36 | 中心双向 |
| `button_*.png` | 左右 28，上下 18 | 中间横向 |

实现优先用 `DecorationImage.centerSlice`。如果图片拉伸效果不稳定，改用 Flutter `BoxDecoration` 绘制面板，图片只作为纹理叠层。

### 8.4 背景避让区

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

### 8.5 图片文字边界

图片资源不要包含动态文字：

- 房间号、局数、比分。
- 网络状态、倒计时。
- 玩家名、余牌数。
- 按钮文案。
- 当前轮次。
- 牌型说明。

图片可以包含固定装饰字，例如背景里的“天津”或地标题签，但这些文字不作为唯一信息来源。

### 8.6 Manifest

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

## 9. 迁移步骤

1. 新增 `GameTableExperience` 设置，默认 `legacy`。
2. 配置弹层增加“经典牌桌 / 新版牌桌”切换。
3. 新建 `game_table_v2` 目录和空壳 `GameTableShell`。
4. 新增本地和联机 adapter，输出统一 `GameTableViewModel`。
5. 实现新版横屏布局：顶栏、座位、中央、手牌、右侧按钮。
6. 接入 `tianjin_ink` 资源和 manifest。
7. 增加 YAML 布局配置 loader 和 resolver，只接管新版牌桌布局 token。
8. 布局日志展示 YAML layer id、debugName、实际位置、逻辑尺寸和设备像素比。
9. 验收通过后再考虑把默认值从 `legacy` 改为 `immersive`。

## 10. 验收标准

- 本地练习桌和联机桌都可以切换老牌桌 / 新牌桌。
- 切换牌桌不重置当前对局，不丢失已选手牌。
- 新牌桌出问题时可以通过设置退回 `legacy`。
- 新皮肤按固定路径和命名交付，替换图片不需要改组件代码。
- YAML 配置只影响新版牌桌，不影响经典牌桌。
- YAML 中的组件名只能映射到 Dart 白名单组件。
- YAML 解析失败时可以回退到内置默认布局，并在日志中给出错误信息。
- 图片不包含动态业务文字。
- 小屏横屏下玩家名、房间号、比分、倒计时和按钮文案不溢出。
- 横屏下 6 个座位、手牌、中央出牌区和右侧按钮互不遮挡。
- 装饰层不拦截点击。
- manifest 中声明的文件都实际存在。
