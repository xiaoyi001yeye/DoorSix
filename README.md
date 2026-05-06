# DoorSix

DoorSix 是一个基于 Flutter 的“砸六家”App 原型。当前版本聚焦 6 人两队牌桌、人机练习、手牌选择、出牌/过牌、出完名次和单局结算 UI。

## 运行

```bash
flutter pub get
flutter run
```

如果本机还没有 Flutter SDK，需要先安装并把 `flutter` 加入 `PATH`。

## 检查

```bash
flutter analyze
flutter test
```

## 构建 APK

当前仓库不提交 Android 平台目录。CI 会在构建时自动执行：

```bash
flutter create --platforms=android --project-name door_six .
flutter build apk --release
```

## 文档

- [初始化设计](docs/init-design.md)
- [App UI 原型](docs/app-ui-prototype.md)
