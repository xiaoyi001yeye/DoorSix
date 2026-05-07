# DoorSix Flutter 初始化设计文档

## 1. 背景

`DoorSix` 是一个 Flutter App，用来实现天津一带的扑克牌游戏“砸六家”。当前核心玩法口径：

- 6 人参与
- 两队对抗，每队 3 人
- 队友隔位坐
- 玩家轮流出牌、过牌
- 玩家出完后记录名次
- 单局按出完顺序、被逮人数和规则版本结算
- 天津通用、塘沽路等不同地区规则存在差异，需要保留规则配置能力

项目代码直接放在仓库根目录 `/Users/wyn/code/DoorSix`，不再创建 Flutter 应用子目录。

## 2. 初始化目标

首轮初始化完成一个可试玩的人机练习桌原型：

- Flutter 根目录项目骨架
- 首页、规则选择、6 人牌桌、结算弹层
- 天津基础规则 1 副牌发牌、每人 9 张和底部手牌区
- 用户选牌、提示、出牌、过牌
- 简化 AI 出牌
- 出完顺序和基础胜负结算
- GitHub Actions APK 构建

首版规则引擎只覆盖 UI 原型需要的最小能力，不一次性实现所有天津/塘沽路细则。

## 3. 项目命名

- Flutter 工程目录：`/Users/wyn/code/DoorSix`
- Dart package name：`door_six`
- 应用显示名：`DoorSix`
- APK artifact：`doorsix-release.apk`
- Release tag 前缀：`doorsix-v*.*.*`

## 4. 目录结构

```text
DoorSix/
├── .github/
│   └── workflows/
│       └── build-doorsix-apk.yml
├── assets/
│   ├── images/
│   └── sound/
├── docs/
│   ├── init-design.md
│   └── app-ui-prototype.md
├── lib/
│   ├── main.dart
│   ├── models/
│   │   ├── card_model.dart
│   │   ├── player_model.dart
│   │   ├── round_result.dart
│   │   └── rule_set.dart
│   ├── pages/
│   │   ├── home_page.dart
│   │   ├── rule_select_page.dart
│   │   ├── game_table_page.dart
│   │   └── scoreboard_page.dart
│   ├── services/
│   │   └── rule_engine.dart
│   ├── utils/
│   │   └── app_theme.dart
│   └── widgets/
│       ├── action_bar.dart
│       ├── hand_area.dart
│       ├── hand_card.dart
│       ├── player_seat.dart
│       ├── rule_badge.dart
│       └── table_center.dart
├── test/
│   └── widget_test.dart
├── .gitignore
├── analysis_options.yaml
├── pubspec.yaml
└── README.md
```

## 5. Flutter 与依赖

本机当前没有 `flutter` 命令，CI 固定使用官方 stable：

- Flutter：`3.41.9`
- Dart：`3.11.5`

首版依赖：

```yaml
environment:
  sdk: ^3.11.0

dependencies:
  flutter:
    sdk: flutter
  audioplayers: ^6.6.0
  flutter_animate: ^4.5.2
  go_router: ^17.2.3
  playing_cards: ^0.4.1+11
  shared_preferences: ^2.5.5
```

说明：

- `playing_cards`：渲染标准扑克牌牌面和 Joker
- `flutter_animate`：当前玩家高亮、选牌和出牌反馈
- `go_router`：首页、规则选择、牌桌等页面路由
- `audioplayers`：后续接入发牌、出牌、结算音效
- `shared_preferences`：后续保存默认规则、音效开关和简单战绩

## 6. 首版应用形态

首版默认竖屏，用户固定坐在底部：

- 首页：快速开始、练习桌、创建房间、加入房间入口
- 规则选择：天津通用、塘沽路、自定义
- 对局牌桌：6 个座位、中央出牌区、底部手牌区、操作栏
- 结算弹层：胜负、出完顺序、被逮玩家、本局积分

在线多人最小房间已接入后端，用于创建/加入房间、准备、开局和牌桌同步；好友房邀请、语音和完整战绩系统仍先不做。

## 7. 规则引擎范围

首版实现：

- 1 副 54 张牌
- 6 人平均发牌
- 手牌排序
- 单张、对子、三张、四张识别
- 大王、小王、3、2 作为混儿参与对子、三张、四张识别
- 简化压牌判断
- 简化 AI 出牌建议
- 最后一家明确后，按“贡”和“留在家里”判定基础胜负

暂不实现：

- 完整天津/塘沽路全部细则
- 进贡、还贡、抗贡的完整流程
- 接风的完整规则链路
- 更复杂的混牌争议桌规
- 在线同步和断线恢复

## 8. 平台策略

仓库根目录先不提交完整 `android/`、`ios/` 平台目录。CI 构建 APK 前自动执行：

```bash
flutter create --platforms=android --project-name door_six .
```

等需要正式发版、自定义包名、图标、签名、权限或启动页时，再把 `android/` 纳入版本管理。

## 9. GitHub Actions

`.github/workflows/build-doorsix-apk.yml` 负责：

1. Checkout
2. Setup Java 17
3. Setup Flutter `3.41.9`
4. 自动生成 Android scaffold
5. `flutter pub get`
6. `flutter analyze`
7. `flutter test`
8. `flutter build apk --release`
9. 上传 `doorsix-release.apk`
10. tag `doorsix-v*.*.*` 时创建 GitHub Release

## 10. 本地开发命令

```bash
cd /Users/wyn/code/DoorSix
flutter pub get
flutter run
```

检查：

```bash
flutter analyze
flutter test
```

## 11. 初始化验收标准

- `pubspec.yaml` 配置正确
- 首页能显示“砸六家”和快速开始入口
- 能进入规则选择页
- 能进入 6 人牌桌
- 牌桌显示 6 个座位和队伍关系
- 底部手牌由扑克牌组件渲染
- 用户可选牌、提示、出牌、过牌
- AI 能简化出牌
- 有玩家出完后能显示出完顺序
- 单局结束后能展示结算弹层
- CI 可构建 APK

## 12. 后续待确认

1. 是否优先补完整进贡、还贡、抗贡、接风？
2. 基础混儿以外的复杂混牌桌规是否是首版必需？
3. 单局积分是否按本地习惯调整？
4. 是否接受首版使用 `playing_cards` 默认牌面，后续再换自定义美术？
