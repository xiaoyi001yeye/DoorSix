# DoorSix

DoorSix 是一个基于 Flutter 的“砸六家”App 原型。当前版本聚焦 6 人两队牌桌、人机练习、手牌选择、出牌/过牌、出完名次和单局结算 UI，并已根据后端接口测试报告重新开放安卓端联机入口。

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

后端接口测试报告 `server/test-reports/backend-interface-test-20260508-013643.md` 显示 HTTP、WebSocket、准备、开局、出牌/过牌和重连共 33 项通过，未发现阻断性问题。安卓端首页的“创建房间 / 加入房间”已接入远程后端 `http://39.104.67.175`，本地构建可通过 `--dart-define=DOORSIX_API_BASE_URL=...` 切换后端地址。

当前仓库不提交 Android 平台目录。CI 会在构建时自动执行：

```bash
./scripts/prepare_android.sh
flutter build apk --release
```

`prepare_android.sh` 会在生成 Android scaffold 后补上 release 包需要的 `INTERNET` / `ACCESS_NETWORK_STATE` 权限，并打开 `usesCleartextTraffic` 用于当前 HTTP 后端；后续切到 HTTPS 后可以移除明文流量开关。

## 文档

- [初始化设计](docs/init-design.md)
- [App UI 原型](docs/app-ui-prototype.md)
- [自动发布与安卓版本升级需求](docs/version-release-upgrade-requirements.md)
- [自动发布与安卓版本升级技术设计](docs/version-release-upgrade-technical-design.md)
- [用户场景测试方案](docs/test-plan.md)
