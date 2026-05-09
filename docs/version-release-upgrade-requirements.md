# DoorSix 自动发布与安卓版本升级需求文档

## 1. 文档目的

本文定义 DoorSix 的版本发布和安卓端升级发现能力。

目标是形成一个完整闭环：

- 代码侧在版本变更后可以自动构建、发布安卓安装包。
- 服务端可以提供稳定的最新版本信息。
- 安卓端启动或回到前台时可以自动发现新版本。
- 安卓端可以向用户展示升级提示，并根据版本策略引导用户升级。

当 CI、服务端接口、安卓端构建方式或版本策略发生变化时，必须同步更新本文。

## 2. 背景与现状

DoorSix 当前是 Flutter App，`pubspec.yaml` 中维护应用版本：

```yaml
version: 0.1.0+1
```

其中：

- `0.1.0` 是用户可见版本号，对应 Android `versionName`。
- `1` 是构建号，对应 Android `versionCode`。

仓库当前不提交 Android 平台目录，CI 构建安卓包前需要先执行：

```bash
./scripts/prepare_android.sh
flutter build apk --release
```

服务端当前已有健康检查、房间、牌桌和 WebSocket 接口，但还没有版本信息接口。

## 3. 目标

### 3.1 产品目标

- 用户安装旧版本后，可以在 App 内收到新版本提示。
- 普通升级由用户决定是否立即升级。
- 对于协议不兼容、严重 bug 或安全问题，可以强制升级。
- 升级提示需要清楚说明版本号、更新内容和安装包大小。
- 用户取消普通升级后，不应在同一个版本上被频繁打扰。

### 3.2 工程目标

- 发布流程尽量自动化，减少手工打包和手工改服务端配置。
- 每个发布版本必须可以追溯到 Git tag、commit、构建产物和发布说明。
- APK 构建完成后必须自动上传到指定服务器 `39.104.67.175`，并生成可被安卓端打开的下载地址。
- 安卓端只依赖服务端版本接口发现更新，不把最新版本写死在客户端。
- 版本接口必须支持灰度、强制升级、最低可用版本和多环境配置。
- 发布失败时不能污染线上最新版本信息。

## 4. 非目标

以下能力不在第一阶段范围内：

| 能力 | 说明 |
| --- | --- |
| 应用商店内更新 | 第一阶段优先支持 APK 直链下载，后续再接入应用商店或 Google Play In-App Updates |
| iOS 自动升级 | 本文仅覆盖 Android |
| 增量热更新 | 不做代码热更新、补丁包或动态下发 Dart 代码 |
| 用户账号级精准推送 | 第一阶段使用设备本地状态和版本接口策略 |
| 复杂 A/B 实验平台 | 只保留灰度百分比、渠道和环境维度 |

## 5. 角色与场景

| 角色 | 场景 |
| --- | --- |
| 开发者 | 执行发布脚本或推送版本递增的 `main/master` 提交，CI 自动构建 APK 并发布 |
| 测试人员 | 安装测试渠道包，验证版本检查、普通升级和强制升级 |
| 普通用户 | 打开 App 后发现新版本，自主选择稍后或立即升级 |
| 运维/发布负责人 | 查看发布结果，必要时回滚版本清单 |

## 6. 版本规则

### 6.1 版本字段

| 字段 | 示例 | 说明 |
| --- | --- | --- |
| `versionName` | `0.2.0` | 展示给用户看的版本号 |
| `versionCode` | `2` | 安卓系统用于判断新旧的整数版本号，只能递增 |
| `gitTag` | `android-v0.2.0+2` | 发布 tag |
| `commitSha` | `abc1234` | 构建来源 commit |
| `channel` | `stable` | 发布渠道 |
| `environment` | `prod` | 环境，例如 `dev`、`staging`、`prod` |

### 6.2 版本递增规则

- 每次发布正式 APK 时，`versionCode` 必须大于线上所有已发布 APK。
- 修复 bug 但不改变功能时，递增补丁版本，例如 `0.1.1+2`。
- 增加用户可见功能时，递增次版本，例如 `0.2.0+3`。
- 出现协议不兼容或大规模能力变化时，递增主版本，例如 `1.0.0+10`。
- CI 必须校验 tag、`pubspec.yaml` 版本和发布清单中的版本一致。

### 6.3 Tag 命名

推荐格式：

```text
android-v<versionName>+<versionCode>
```

示例：

```text
android-v0.2.0+2
```

## 7. 自动发布需求

### 7.1 触发方式

第一阶段支持以下触发方式：

| 触发方式 | 是否必需 | 说明 |
| --- | --- | --- |
| 分支 push 触发 | 必需 | 推送 `main/master` 后，如果 `pubspec.yaml` 版本递增且 release notes 存在，CI 自动发布 |
| 手动触发 | 必需 | CI 页面输入版本后手动发布；如果对应 `android-v*` tag 不存在，CI 自动创建并推送 tag |
| Git tag 触发 | 不启用 | `android-v*` tag 只作为发布追溯记录，tag push 不触发发布，避免重复发布 |
| 普通分支自动发布 | 不建议 | 非 `main/master` 分支不更新正式版本 |

第一阶段只支持 `stable/prod` 发布。`internal`、`beta`、`staging` 等渠道和环境字段作为后续扩展预留，不作为第一阶段发布隔离能力。

普通 push 如果 `pubspec.yaml` 版本没有递增，CI 只执行分析、测试和构建验证，不发布 APK，并在 CI summary 中说明跳过原因。

### 7.2 发布流水线步骤

自动发布流水线必须按以下顺序执行：

1. 检出代码。
2. 读取 `pubspec.yaml` 中的 `version`。
3. 校验或自动创建 `android-v<versionName>+<versionCode>` tag；tag 只用于追溯，不作为发布触发源。
4. 校验 `versionName` 和 `versionCode` 与 tag 一致。
5. 读取 `docs/release-notes/android/<versionName>+<versionCode>.md`。
6. 安装 Flutter 依赖。
7. 执行 `flutter analyze`。
8. 执行 `flutter test`。
9. 执行 `./scripts/prepare_android.sh`。
10. 构建 release APK。
11. 计算 APK 文件大小和 SHA-256。
12. 通过 SSH/SCP 上传 APK 和 SHA-256 文件到 `39.104.67.175`。
13. 在服务器上写入或更新发布清单。
14. 校验服务器上的 APK 下载地址可访问。
15. 更新服务端可读取的最新版本信息。
16. 尝试创建 GitHub Release 或等价发布记录；失败时标记 warning，不阻塞安卓发布。
17. 输出发布结果摘要。

### 7.3 发布产物

每次发布至少生成以下产物：

| 产物 | 示例 | 说明 |
| --- | --- | --- |
| APK | `door_six-0.2.0+2-stable.apk` | 安卓安装包 |
| 校验文件 | `door_six-0.2.0+2-stable.sha256` | APK SHA-256 |
| 发布清单 | `release-android-0.2.0+2.json` | 服务端版本信息来源 |
| 发布说明 | `docs/release-notes/android/0.2.0+2.md` | 展示给用户和测试人员，并作为清单 `releaseNotes` 来源 |

发布前必须提交对应版本的发布说明文件。如果缺少该文件，CI 发布必须失败。

### 7.4 APK 上传服务器

第一阶段 APK 发布存储使用指定服务器：

| 配置 | 值 |
| --- | --- |
| 服务器地址 | `39.104.67.175` |
| 推荐上传协议 | SSH/SCP |
| 推荐远程目录 | `/opt/doorsix/releases/android` |
| 推荐公开访问前缀 | `http://39.104.67.175/downloads/android` |
| 推荐发布清单目录 | `/opt/doorsix/releases/manifests` |

CI 构建完成后必须执行：

1. 创建远程目录 `/opt/doorsix/releases/android/<versionName>+<versionCode>/`。
2. 上传 APK 到该版本目录。
3. 上传 SHA-256 文件到同一版本目录。
4. 上传发布清单到 `/opt/doorsix/releases/manifests/`。
5. 更新 `latest-android-stable.json` 指向最新 `active` 版本。
6. 通过 HTTP 校验 APK 下载地址可访问。

推荐远程文件结构：

```text
/opt/doorsix/releases/
  android/
    0.2.0+2/
      door_six-0.2.0+2-stable.apk
      door_six-0.2.0+2-stable.sha256
  manifests/
    release-android-0.2.0+2.json
    latest-android-stable.json
```

推荐公开下载地址：

```text
http://39.104.67.175/downloads/android/0.2.0+2/door_six-0.2.0+2-stable.apk
```

服务器需要由 Nginx、Caddy 或 Node 静态文件服务将 `/opt/doorsix/releases/android` 暴露为 `/downloads/android`。

### 7.5 发布清单格式

CI 生成的发布清单建议使用 JSON：

```json
{
  "platform": "android",
  "channel": "stable",
  "environment": "prod",
  "versionName": "0.2.0",
  "versionCode": 2,
  "minSupportedVersionCode": 1,
  "forceUpdate": false,
  "title": "发现新版本 0.2.0",
  "releaseNotes": [
    "优化联机房间连接稳定性",
    "修复重连后牌桌状态不同步的问题"
  ],
  "downloadUrl": "http://39.104.67.175/downloads/android/0.2.0+2/door_six-0.2.0+2-stable.apk",
  "fileSizeBytes": 32100000,
  "sha256": "replace-with-real-sha256",
  "publishedAt": "2026-05-09T12:00:00+08:00",
  "gitTag": "android-v0.2.0+2",
  "commitSha": "replace-with-real-commit-sha",
  "rollout": {
    "enabled": true,
    "percentage": 100
  }
}
```

### 7.6 发布状态

发布记录必须包含状态字段：

| 状态 | 说明 |
| --- | --- |
| `draft` | 构建完成但未对客户端可见 |
| `active` | 当前可被客户端发现 |
| `paused` | 暂停灰度或暂停升级提示 |
| `recalled` | 已撤回，不应继续展示 |

只有 `active` 状态的版本可以被安卓端发现。

### 7.7 失败处理

- 测试失败时不得构建和发布正式 APK。
- APK 上传失败时不得更新服务端最新版本信息。
- APK 上传成功但下载地址校验失败时，不得更新最新版本信息。
- 服务端版本信息更新失败时，CI 必须将发布标记为失败。
- GitHub Release 或等价发布记录创建失败不阻塞安卓发布；CI 需要标记 warning 并提示后续补建。
- 发布失败必须保留日志和失败原因。
- 重跑同一个 tag 时，如果产物已存在，必须校验 SHA-256 一致；不一致则失败。

## 8. 服务端版本发现需求

### 8.1 接口列表

服务端新增版本接口：

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/api/v1/app-updates/latest` | 查询当前客户端是否有可用更新 |
| `GET` | `/api/v1/app-updates/releases/:platform/:versionCode` | 查询指定版本详情，可用于排查 |

### 8.2 最新版本查询请求

请求示例：

```http
GET /api/v1/app-updates/latest?platform=android&channel=stable&versionCode=1&versionName=0.1.0&deviceId=local-device-id
```

查询参数：

| 参数 | 必需 | 说明 |
| --- | --- | --- |
| `platform` | 是 | 固定为 `android` |
| `channel` | 是 | 第一阶段固定为 `stable`；`beta`、`internal` 后续扩展 |
| `versionCode` | 是 | 当前客户端构建号 |
| `versionName` | 否 | 当前客户端展示版本 |
| `deviceId` | 否 | 用于稳定灰度命中，不需要是真实硬件 ID |

### 8.3 最新版本查询响应

无更新：

```json
{
  "hasUpdate": false,
  "serverTime": "2026-05-09T12:00:00+08:00"
}
```

有普通更新：

```json
{
  "hasUpdate": true,
  "updateType": "optional",
  "latest": {
    "versionName": "0.2.0",
    "versionCode": 2,
    "title": "发现新版本 0.2.0",
    "releaseNotes": [
      "优化联机房间连接稳定性",
      "修复重连后牌桌状态不同步的问题"
    ],
    "downloadUrl": "http://39.104.67.175/downloads/android/0.2.0+2/door_six-0.2.0+2-stable.apk",
    "fileSizeBytes": 32100000,
    "sha256": "replace-with-real-sha256",
    "publishedAt": "2026-05-09T12:00:00+08:00"
  },
  "serverTime": "2026-05-09T12:00:00+08:00"
}
```

有强制更新：

```json
{
  "hasUpdate": true,
  "updateType": "force",
  "latest": {
    "versionName": "0.2.0",
    "versionCode": 2,
    "title": "必须升级后继续使用",
    "releaseNotes": [
      "修复当前版本无法兼容新联机协议的问题"
    ],
    "downloadUrl": "http://39.104.67.175/downloads/android/0.2.0+2/door_six-0.2.0+2-stable.apk",
    "fileSizeBytes": 32100000,
    "sha256": "replace-with-real-sha256",
    "publishedAt": "2026-05-09T12:00:00+08:00"
  },
  "serverTime": "2026-05-09T12:00:00+08:00"
}
```

### 8.4 更新判断规则

服务端按以下规则判断：

1. 第一阶段固定读取 `stable/prod` 的 `latest-android-stable.json`，并确认发布记录状态为 `active`。
2. 如果没有可用版本，返回 `hasUpdate=false`。
3. 如果客户端 `versionCode` 大于等于最新 `versionCode`，返回 `hasUpdate=false`。
4. 如果客户端 `versionCode` 小于 `minSupportedVersionCode`，返回 `updateType=force`。
5. 如果发布记录的 `forceUpdate=true`，返回 `updateType=force`。
6. 如果灰度未命中，返回 `hasUpdate=false`。
7. 其他情况返回 `updateType=optional`。

### 8.5 灰度规则

- `rollout.enabled=false` 时，不向任何客户端展示。
- `rollout.percentage=100` 时，全部客户端可见。
- `rollout.percentage` 小于 100 时，服务端基于 `deviceId` 或稳定匿名 ID 做哈希分桶。
- 同一设备对同一版本的命中结果必须稳定。
- 灰度参数可以由发布清单更新，不要求重新构建 APK。

### 8.6 缓存与可用性

- 版本查询接口允许客户端缓存，但缓存时间不得超过 30 分钟。
- 服务端响应应包含 `Cache-Control: no-cache` 或短缓存策略，避免撤回版本后客户端长时间继续展示。
- 版本接口失败时，安卓端不得阻断用户进入 App，除非本地已经处于强制升级锁定状态。

## 9. 安卓端升级发现需求

### 9.1 检查时机

安卓端需要在以下时机检查更新：

| 时机 | 是否必需 | 说明 |
| --- | --- | --- |
| App 冷启动后 | 必需 | 首页加载完成后异步检查 |
| App 从后台回到前台 | 必需 | 距离上次检查超过 30 分钟时检查 |
| 用户手动点击检查更新 | 必需 | 后续可放在设置页 |
| 联机接口返回版本不兼容错误 | 必需 | 立即触发强制检查 |

### 9.2 客户端请求参数

安卓端每次请求版本接口时至少传入：

- 当前 `versionCode`。
- 当前 `versionName`。
- `platform=android`。
- 当前渠道，例如 `stable`。
- 稳定匿名设备 ID。

设备 ID 只用于灰度分桶，不应上传手机号、通讯录、IMEI、Android ID 等敏感标识。

### 9.3 本地状态

安卓端需要保存以下本地状态：

| 字段 | 说明 |
| --- | --- |
| `lastUpdateCheckAt` | 上次检查时间 |
| `dismissedVersionCode` | 用户已选择稍后提醒的版本 |
| `dismissedAt` | 用户选择稍后提醒的时间 |
| `forceUpdateLockedVersionCode` | 当前被强制升级锁定的版本 |

普通更新被用户选择“稍后”后：

- 24 小时内不再自动弹同一个版本。
- 用户手动检查更新时仍可展示。
- 如果服务端发布了更高版本，可以再次展示。

强制更新：

- 不允许选择“稍后”。
- 不允许关闭弹窗后继续使用 App。
- 强制升级锁定整个 App，包括首页、人机练习、创建房间、加入房间和联机牌桌。
- 可以允许用户退出 App 或跳转下载。

### 9.4 普通升级弹窗

普通升级弹窗需要包含：

- 标题，例如“发现新版本 0.2.0”。
- 更新内容列表。
- 安装包大小。
- “稍后”按钮。
- “立即升级”按钮。

交互规则：

- 点击“稍后”：关闭弹窗，记录 `dismissedVersionCode` 和 `dismissedAt`。
- 点击“立即升级”：打开下载链接或系统浏览器。
- 下载链接无法打开时，展示错误提示，不影响继续使用 App。

### 9.5 强制升级弹窗

强制升级弹窗需要包含：

- 标题，例如“必须升级后继续使用”。
- 强制升级原因或更新内容。
- 安装包大小。
- “立即升级”按钮。

交互规则：

- 不展示“稍后”按钮。
- 点击系统返回或关闭弹窗时，仍停留在强制升级遮罩。
- 点击“立即升级”：打开下载链接或系统浏览器。
- 如果下载失败，允许用户重试。

### 9.6 下载与安装

第一阶段推荐使用外部浏览器打开 APK 下载地址：

- 实现简单。
- 不需要在 App 内处理下载进度、存储权限和安装权限。
- 避免 Flutter 端额外引入下载器和安装器依赖。

后续如果需要 App 内下载和安装，需要补充以下能力：

- 下载进度展示。
- 断点续传。
- APK SHA-256 校验。
- Android 8.0+ 未知来源安装权限引导。
- 下载失败重试。
- 安装完成后的状态恢复。

## 10. 兼容性与协议约束

当服务端接口发生不兼容变更时，必须同步更新版本策略：

- 服务端保留旧接口一段兼容期，优先避免强制升级。
- 如果无法兼容，设置 `minSupportedVersionCode`，使旧版本进入强制升级。
- 联机相关接口可以返回明确错误码，例如 `APP_VERSION_UNSUPPORTED`。
- 安卓端收到该错误码后立即请求版本接口，并展示强制升级弹窗。

推荐错误响应：

```json
{
  "error": {
    "code": "APP_VERSION_UNSUPPORTED",
    "message": "当前版本过低，请升级后继续使用。",
    "minSupportedVersionCode": 2
  }
}
```

## 11. 安全要求

- 第一阶段允许使用 `http://39.104.67.175` 下载 APK；后续具备域名和证书后再切换 HTTPS。
- 发布清单必须包含 SHA-256。
- CI 上传产物后必须计算并记录 SHA-256。
- 服务端不得返回状态为 `recalled` 的版本。
- 下载域名应由服务端控制，不允许客户端拼接下载地址。
- 版本接口不得泄露未发布版本的内部说明、密钥或构建配置。
- 如果使用对象存储，APK 文件应只开放只读下载权限。

## 12. 配置需求

### 12.1 CI 配置

CI 需要支持以下配置项：

| 配置 | 说明 |
| --- | --- |
| `FLUTTER_VERSION` | Flutter SDK 版本 |
| `ANDROID_KEYSTORE_BASE64` | release 签名证书，第一阶段可选 |
| `ANDROID_KEYSTORE_PASSWORD` | 证书密码，第一阶段可选 |
| `ANDROID_KEY_ALIAS` | 签名别名，第一阶段可选 |
| `ANDROID_KEY_PASSWORD` | 签名别名密码，第一阶段可选 |
| `DOORSIX_API_BASE_URL` | 构建包使用的后端地址 |
| `RELEASE_HOST` | APK 上传服务器，第一阶段固定为 `39.104.67.175` |
| `RELEASE_USER` | SSH 登录用户 |
| `RELEASE_SSH_KEY` | SSH 私钥，推荐优先使用 |
| `RELEASE_PASSWORD` | SSH 密码，仅在无法使用私钥时使用 |
| `RELEASE_REMOTE_DIR` | 远程发布目录，默认 `/opt/doorsix/releases` |
| `RELEASE_PUBLIC_BASE_URL` | APK 公开访问前缀，默认 `http://39.104.67.175/downloads/android` |
| `RELEASE_CHANNEL` | 第一阶段固定为 `stable` |

敏感配置必须存放在 CI Secret 中，不得提交到仓库。

第一阶段为了支持随时发布新版本，不强制要求 release 签名证书。未统一签名的 APK 可能无法覆盖安装旧包，测试或用户安装时可能需要先卸载旧版本；正式长期分发前应补齐稳定 release 签名。

### 12.2 服务端配置

服务端需要支持以下配置项：

| 配置 | 说明 |
| --- | --- |
| `APP_UPDATE_MANIFEST_PATH` | 本地发布清单路径 |
| `APP_UPDATE_MANIFEST_URL` | 远程发布清单 URL，可选 |
| `APP_UPDATE_ENVIRONMENT` | 当前环境 |
| `APP_UPDATE_DEFAULT_CHANNEL` | 默认渠道 |
| `APP_UPDATE_DOWNLOAD_BASE_URL` | APK 下载地址前缀，第一阶段为 `http://39.104.67.175/downloads/android` |

第一阶段可以由服务端读取本地 JSON 文件；后续可迁移到 Redis、数据库或对象存储。

### 12.3 安卓端配置

安卓端需要支持以下构建参数：

| 参数 | 说明 |
| --- | --- |
| `DOORSIX_API_BASE_URL` | 版本接口和业务接口基础地址 |
| `DOORSIX_RELEASE_CHANNEL` | 当前包的发布渠道 |

示例：

```bash
flutter build apk --release \
  --dart-define=DOORSIX_API_BASE_URL=http://39.104.67.175 \
  --dart-define=DOORSIX_RELEASE_CHANNEL=stable
```

## 13. 数据结构建议

### 13.1 服务端发布记录

```json
{
  "id": "android-stable-2",
  "platform": "android",
  "channel": "stable",
  "environment": "prod",
  "versionName": "0.2.0",
  "versionCode": 2,
  "minSupportedVersionCode": 1,
  "forceUpdate": false,
  "status": "active",
  "title": "发现新版本 0.2.0",
  "releaseNotes": [],
  "downloadUrl": "",
  "fileSizeBytes": 0,
  "sha256": "",
  "gitTag": "",
  "commitSha": "",
  "publishedAt": "",
  "rollout": {
    "enabled": true,
    "percentage": 100
  }
}
```

### 13.2 安卓端模型

```dart
enum AppUpdateType {
  optional,
  force,
}

class AppUpdateInfo {
  final AppUpdateType type;
  final String versionName;
  final int versionCode;
  final String title;
  final List<String> releaseNotes;
  final String downloadUrl;
  final int fileSizeBytes;
  final String sha256;
  final DateTime publishedAt;
}
```

## 14. 埋点与日志

第一阶段至少记录服务端日志和客户端本地调试日志。

建议事件：

| 事件 | 触发时机 |
| --- | --- |
| `app_update_check_started` | 开始检查更新 |
| `app_update_check_succeeded` | 检查成功 |
| `app_update_check_failed` | 检查失败 |
| `app_update_prompt_shown` | 展示升级弹窗 |
| `app_update_dismissed` | 用户选择稍后 |
| `app_update_download_clicked` | 用户点击立即升级 |
| `app_update_forced` | 进入强制升级状态 |

日志中不得记录敏感设备标识。

## 15. 验收标准

### 15.1 自动发布验收

- 推送版本递增且包含 release notes 的 `main/master` 提交后，CI 可以自动完成分析、测试、构建和发布。
- 普通 push 如果版本未递增，CI 只构建验证并明确说明跳过发布。
- 自动创建或复用的 tag 与 `pubspec.yaml` 版本不一致时，CI 失败。
- 构建失败时，不更新最新版本信息。
- 发布成功后，可以看到 APK、SHA-256、发布清单和发布说明。
- 发布成功后，APK 已上传到 `39.104.67.175` 的版本目录。
- 发布成功后，CI 可以通过公开下载地址访问 APK。
- 服务端版本接口返回的下载地址、版本号、大小和 SHA-256 与发布产物一致。

### 15.2 服务端验收

- 旧版本请求版本接口时，返回 `hasUpdate=true`。
- 最新版本请求版本接口时，返回 `hasUpdate=false`。
- `versionCode` 小于 `minSupportedVersionCode` 时，返回 `updateType=force`。
- 灰度比例为 0 时，不返回更新。
- 灰度比例为 100 时，所有旧版本都返回更新。
- 撤回版本后，接口不再返回该版本。

### 15.3 安卓端验收

- App 冷启动后可以异步检查更新，不阻塞首页展示。
- 有普通更新时展示弹窗，用户可以选择稍后或立即升级。
- 用户选择稍后后，24 小时内不再自动弹同一版本。
- 有更高版本发布后，即使之前选择过稍后，也能再次提示。
- 有强制更新时不允许继续使用核心功能。
- 点击立即升级可以打开 APK 下载地址。
- 版本接口失败时，普通情况下不影响继续使用 App。

## 16. 测试计划

### 16.1 单元测试

- 服务端版本比较逻辑。
- `minSupportedVersionCode` 强制升级判断。
- 灰度哈希分桶逻辑。
- 发布清单解析和状态过滤。
- 安卓端版本响应解析。
- 安卓端稍后提醒节流逻辑。

### 16.2 集成测试

- 构造多个发布记录，验证服务端返回最高可用版本。
- 模拟 CI 写入发布清单，验证接口立即返回新版本。
- 模拟业务接口返回 `APP_VERSION_UNSUPPORTED`，验证安卓端触发强制升级。

### 16.3 手工测试

- 安装 `0.1.0+1`，服务端发布 `0.2.0+2`，验证普通升级弹窗。
- 点击稍后，重启 App，验证不重复弹窗。
- 将服务端设置为强制升级，验证无法关闭弹窗继续使用。
- 断网启动 App，验证不影响普通使用。
- 下载链接失效，验证错误提示和重试路径。

## 17. 分阶段落地计划

### 阶段一：最小闭环

- 新增服务端版本接口。
- 服务端读取本地发布清单 JSON。
- 安卓端冷启动检查更新。
- 安卓端支持普通升级和强制升级弹窗。
- CI 构建 APK，上传到 `39.104.67.175`，并生成发布清单。

### 阶段二：发布质量增强

- 接入对象存储或 GitHub Release。
- 发布清单支持 `draft`、`active`、`paused`、`recalled`。
- 支持灰度百分比。
- 增加服务端和安卓端测试覆盖。

### 阶段三：体验增强

- 增加设置页“检查更新”入口。
- 支持 App 内下载进度。
- 下载完成后校验 SHA-256。
- 引导用户完成安装权限授权。

## 18. 风险与应对

| 风险 | 应对 |
| --- | --- |
| APK 下载地址被缓存，撤回不及时 | 版本接口短缓存，撤回后不再返回下载地址 |
| `versionCode` 回退导致无法升级 | CI 校验版本号必须递增 |
| 强制升级误配置影响所有用户 | 发布记录先进入 `draft`，人工确认后改为 `active` |
| 灰度命中不稳定 | 使用稳定匿名 ID 做哈希分桶 |
| Android 安装 APK 权限复杂 | 第一阶段使用浏览器下载，后续再做 App 内安装 |
| 未统一签名导致覆盖安装失败 | 第一阶段允许先发布，发布说明和测试报告中提示可能需要卸载旧包；后续补齐稳定 release 签名 |
| 签名证书泄露 | 证书只放 CI Secret，定期检查访问权限 |

## 19. 已确认的一期发布决策

- 第一阶段只支持 `stable/prod`，不做 `internal/beta/staging` 发布隔离。
- 第一阶段允许未统一 release 签名的 APK 先发布，签名能力后续增强。
- 第一阶段支持 HTTP 下载，后续再切 HTTPS。
- 强制升级锁定整个 App。
- 手动发布无 tag 时由 CI 自动创建 `android-v<versionName>+<versionCode>` tag。
- 第一阶段不使用 `/downloads/android-test`，所有 APK 走正式 `/downloads/android` 目录。
- 发布说明固定维护在 `docs/release-notes/android/<versionName>+<versionCode>.md`。
