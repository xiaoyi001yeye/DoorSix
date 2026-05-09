# DoorSix 开发上下文

## 项目背景

DoorSix 是一个 Flutter App 原型，主题是天津一带流行的扑克牌游戏 `砸六家`。

命名说明：

- 项目早期曾使用过 `砸六门` 这个说法。
- 当前确认的实际玩法是 `砸六家`，不是点击六扇门的小游戏。
- `DoorSix` 是 App 和项目名称，`砸六家` 是真实游戏题材。

## 出处与玩法来源

`砸六家` 通常被理解为天津及周边地区流行的民间扑克牌游戏。公开规则资料和民间说法中，它常被描述为六人、两队、隔位坐的团队扑克玩法。

需要注意：砸六家的地方版本差异很大。天津通用玩法、塘沽路玩法、线上版本和私人牌桌约定都可能不完全一样，所以不要把某一个版本直接当成唯一标准规则。

当前项目采用的基础口径：

- 游戏流行于天津及周边地区。
- 使用扑克牌。
- 6 人参与。
- 分为 2 队，每队 3 人。
- 队友隔位坐。
- 玩家按顺序出牌或过牌。
- 玩家出完手牌后记录出完名次。
- 单局结果按出完顺序、被逮情况和当前规则版本结算。

本项目参考资料：

- `docs/app-ui-prototype.md`
- `docs/init-design.md`
- `docs/server-design.md`
- 公开资料中的 `砸六家竞赛规则2024版`
- 网络公开片段中关于砸六家“天津、六人、两队、扑克牌、按出完顺序结算”的描述

由于规则版本不统一，开发时遇到规则争议，应先保留可配置能力，并向用户确认具体玩法。

## 核心玩法

当前 App 使用的稳定玩法模型：

1. 六名玩家围坐一桌。
2. 玩家分为 A 队和 B 队。
3. 每队三名玩家。
4. 队友隔位坐，左右相邻通常是对手。
5. 按当前规则版本发牌。
6. 玩家依次出牌或过牌。
7. 出牌必须组成有效牌型。
8. 跟牌时，出的牌需要能压过当前桌面最大牌型。
9. 不能压过或策略上不想出时，可以选择过牌。
10. 一圈足够多玩家过牌后，桌面进入新一轮领出。
11. 玩家手牌出完后，记录其出完名次。
12. 单局按当前规则版本判断何时结算。
13. 结算可能依赖出完顺序、被逮玩家、进贡、接风和本地桌规。

## 规则版本

App 长期需要保留规则版本能力。当前 Flutter 原型中的展示版本包括：

- `天津通用`
- `塘沽路`
- `自定义`

## 项目唯一基准规则

从本文件更新日起，DoorSix 项目采用 `zha_liujia_tianjin_basic_v1` 作为“天津砸六家基础规则”的唯一无歧义基准数据。

规则数据文件：

- `assets/config/rules/zha_liujia_tianjin_basic_v1.json`

开发、文案、AI 解释、测试和后续规则引擎实现遇到冲突时，优先级固定为：

1. `assets/config/rules/zha_liujia_tianjin_basic_v1.json`
2. 本文件中的文字说明
3. 其他设计文档
4. 当前代码中的临时原型实现

如果代码、页面文案或旧文档与该 JSON 配置冲突，必须认为 JSON 配置正确，并同步修正其他位置。不要再把“天津通用”解释成两副牌简化原型；两副牌只能用于其他规则版本、实验玩法或明确命名的自定义玩法。

`zha_liujia_tianjin_basic_v1` 的基础口径：

- 6 名玩家参与。
- 2 队对抗，每队 3 人。
- 队友隔位坐。
- 使用 1 副标准扑克牌，共 54 张。
- 每名玩家 9 张手牌。
- 抓到红桃 4 的玩家先出。
- 首出可以出单张、对子、三张或四张，不强制包含红桃 4。
- 有效牌型只包括单张、对子、三张、四张。
- 跟牌必须同牌型、同张数相压，不能跨牌型比较。
- 牌点大小从大到小为：大王、小王、3、2、A、K、Q、J、10、9、8、7、6、5、4。
- 大王、小王、3、2 是混儿，组对子、三张、四张时可以代替其他牌点。
- 混儿单出时按自身原始牌点大小比较。
- 先出完牌的人记为“贡”。
- 最后未走完或最后出完的人记为“留在家里”。
- 基础胜负：一队拿到“贡”，且本队无人“留在家里”，则该队获胜。
- 如果拿“贡”的队伍也有人“留在家里”，则对方获胜。

所有新增规则字段必须先加入 JSON 配置，再由代码读取或映射，避免只在代码里口头写死。

后续可能需要配置的规则项：

- 使用几副牌
- 每人发多少张
- 首出规则
- 可用牌型
- 牌点大小顺序
- 混牌或万能牌扩展项
- 进贡
- 还贡
- 抗贡
- 接风
- 单局结算方式
- 积分计算方式

如果规则细节没有确认，优先实现保守的简化规则引擎，并在界面和文档中明确当前版本是原型。

多人服务端最小版本先不做自定义规则，固定使用 `zha_liujia_tianjin_basic_v1`。不要在最小后端接口里加入规则列表、自定义规则或规则编辑能力。

多人服务端最小版本允许真人不足 6 人时开局。房主发起开局后，服务端用 AI 补齐空座位，始终形成 6 个参赛席位。

## 当前实现范围

当前 Flutter 代码实现的是可试玩原型，不是完整地方规则模拟器。

已经实现：

- Flutter 根目录项目。
- 首页。
- 规则选择页。
- 六人牌桌页。
- A 队 / B 队座位颜色。
- 用户固定坐在底部。
- 天津基础规则 1 副牌发牌，每人 9 张。
- 用户手牌展示。
- 选牌。
- 提示。
- 出牌。
- 过牌。
- 简化 AI 自动出牌。
- 多人服务端第一版 AI 补位与最简单出牌策略。
- 简化牌型识别：
  - 单张
  - 对子
  - 三张
  - 四张
- 大王、小王、3、2 作为混儿参与对子、三张、四张识别。
- 简化出完顺序记录。
- 简化单局结算弹层。
- GitHub Actions APK 构建。
- 安卓端创建/加入房间入口。
- 最小联机房间：准备、房主开局、服务端快照同步、出牌/过牌。

尚未完整实现：

- 完整天津规则。
- 完整塘沽路规则。
- 进贡、还贡、抗贡流程。
- 接风流程。
- 更复杂的混牌争议桌规。
- 完整在线多人体验。
- 聊天、邀请分享、后台自动重连体验。
- 大厅、观战、自定义规则和账号体系。
- Redis 运行态状态存储。
- 基于结构化日志文件的历史战绩。
- 自定义扑克牌美术。
- 正式 Android 包名、图标、签名和发版配置。

## Flutter 与构建

本项目是 Flutter 根目录项目，不要再创建嵌套的 Flutter 应用目录。

CI 推荐版本：

- Flutter `3.41.9`
- Dart `3.11.5`

关键文件：

- `pubspec.yaml`
- `lib/main.dart`
- `lib/pages/game_table_page.dart`
- `lib/services/rule_engine.dart`
- `lib/models/card_model.dart`
- `docs/app-ui-prototype.md`
- `docs/server-design.md`
- `.github/workflows/build-doorsix-apk.yml`

Flutter 可用时运行：

```bash
flutter pub get
flutter analyze
flutter test
```

## 安卓发布说明

自动发布与安卓版本升级设计记录在：

- `docs/version-release-upgrade-requirements.md`
- `docs/version-release-upgrade-technical-design.md`

每个安卓发布版本必须维护一份面向用户的固定发布说明文件，路径约定为：

```text
docs/release-notes/android/<versionName>+<versionCode>.md
```

例如：

```text
docs/release-notes/android/0.2.0+2.md
```

发布前必须提交对应版本的 release notes。CI 发布时读取该文件生成发布清单中的 `releaseNotes`，并用于 GitHub Release 或等价发布记录。不要只依赖 commit 自动摘要或临时 workflow 输入生成用户可见更新内容；如果缺少对应版本的 release notes，正式发布应失败并提示补充。

安卓发布能力必须支持“提交代码并 push 后可以发布一个新版本”。普通 push 如果 `pubspec.yaml` 中的 `version` 没有递增，CI 只运行分析、测试和构建验证，不发布新 APK，并在 CI summary 中说明“版本未递增，跳过发布”。当本次提交已经递增 `pubspec.yaml` 中的 `version`，并提交了对应 `docs/release-notes/android/<versionName>+<versionCode>.md` 时，CI 应自动创建或复用 `android-v<versionName>+<versionCode>` tag，构建 APK，上传到 `39.104.67.175`，更新 `latest-android-stable.json`，让旧版安卓端在启动或回到前台检查版本接口时收到新版本提示。不要要求人工预先创建 tag；tag 不存在时由 CI 自动创建。安卓发布只由分支 push 或 `workflow_dispatch` 手动触发执行；`android-v*` tag 只作为发布追溯记录，tag push 本身不得触发发布 workflow，避免同一版本重复发布。若 release notes 缺失、tag 指向其他 commit、构建失败、上传失败或下载地址校验失败，发布必须失败并给出明确原因，不能静默跳过或污染线上 latest 清单。

GitHub Release 是非阻塞发布记录。只要 APK 上传成功、下载地址校验成功、`latest-android-stable.json` 更新成功，就认为安卓发布成功。GitHub Release 创建或更新失败时，CI 应在 summary 中标记 warning 并提示后续补建，不得回滚已经成功的安卓发布。

项目必须提供一个本地发布脚本，用于在用户明确想发布新版本时由人或 AI 工具执行：

```bash
scripts/release_android_version.sh <versionName+versionCode> "<release note>"
```

示例：

```bash
scripts/release_android_version.sh 0.2.0+2 "优化联机稳定性；修复重连后状态不同步"
```

该脚本负责把 `pubspec.yaml` 更新到目标版本，创建或更新 `docs/release-notes/android/<versionName>+<versionCode>.md`，运行必要的本地检查，提交并 push 当前分支。脚本允许把当前工作区已有未提交改动、版本号更新和 release notes 一起提交并发布；执行前必须打印 `git status --short` 供操作者确认，提交信息使用 `release: android <versionName>+<versionCode>`。push 后由 CI 完成自动 tag、APK 构建、上传服务器、更新 latest 清单和 GitHub Release。脚本必须校验目标 `versionCode` 大于当前版本，必须拒绝缺少发布说明的发布，必须在失败时给出明确原因。AI 工具需要发布新版本时，应优先执行这个脚本，不手工改版本号、不手工建 tag、不手工上传 APK。

## 自动提交与推送

每次修改代码后，在完成必要检查或说明无法检查的原因后，必须使用项目脚本自动提交并推送当前分支：

```bash
scripts/auto_commit_push.sh "type: concise commit message"
```

脚本位置：

- `scripts/auto_commit_push.sh`

脚本行为：

- 进入项目根目录。
- 如没有改动，直接退出。
- 运行 `git diff --check` 检查空白错误。
- 执行 `git add -A`。
- 使用传入的提交信息执行 `git commit -m`。
- 推送当前分支；如果当前分支没有 upstream，则执行 `git push -u origin <branch>`。

提交信息必须简短、清晰，优先使用常见前缀，例如 `feat:`、`fix:`、`chore:`、`docs:`、`test:`。如果当前环境无法推送，必须在最终回复里明确说明失败原因和当前提交状态。

## 编码约定

- 项目根目录固定为 `/Users/wyn/code/DoorSix`。
- 不要创建 `DoorSixApp/`、`TimerFlow/` 这类应用子目录。
- 优先拆分小而清晰的 Flutter 组件，避免页面文件无限膨胀。
- 牌局规则逻辑放在 `lib/services/rule_engine.dart` 或新的 service 文件中。
- 数据结构放在 `lib/models/`。
- 牌桌视觉组件放在 `lib/widgets/`。
- 修改核心玩法假设时，必须同步更新文档。
- 不要把当前简化规则引擎描述成完整天津或塘沽路规则。
- 能保留规则配置能力时，优先保留配置能力。
- 涉及多人房间、服务端接口、WebSocket 事件、牌桌同步、出牌/过牌、结算或客户端模型的变更时，必须核对 `docs/server-design.md` 与代码是否一致。
- 如果代码实现和 `docs/server-design.md` 不一致，要么同步修改代码，要么同步修改文档，不能留下过期接口说明。
- 多人服务端最小版已明确砍掉大厅、观战、自定义规则和账号体系，保留房间号组局、6 座牌桌、AI 补位、Redis 运行态状态、结构化战绩日志和服务端权威出牌校验。
- 不要在最小后端接口里重新加入大厅列表、观战、账号登录或自定义规则，除非用户明确改变范围并同步更新 `docs/server-design.md`。
- Redis 负责房间、牌桌、手牌、连接状态、`playerToken`、锁、事件序号和 TTL。
- 历史战绩必须以结构化日志文件保存，不能先引入数据库；玩家战绩和房间历史从日志中读取和聚合。
- 真人不足 6 人也可以开局，空座由服务端 AI 补齐。第一版 AI 策略：新一轮出最小单张，跟牌时出最小可压牌，否则过牌。

## 产品方向

近期目标是做一个清晰、可用的单机练习桌：

- 打开 App。
- 选择规则版本。
- 进入六人牌桌。
- 与简化 AI 对局。
- 一眼看清队友和对手。
- 看清当前桌面牌型和当前出牌者。
- 在底部选择手牌。
- 可以出牌、过牌或使用提示。
- 可以看到出完顺序和单局结果。

在线多人和完整地方规则细节，应在基础牌桌体验稳定之后继续推进。

## 多人服务端设计

多人同时在一张桌子上打牌需要服务端作为权威状态源。服务端核心功能、HTTP 接口、WebSocket 事件、参数、返回值、错误码和一致性要求记录在：

- `docs/server-design.md`

后续如果新增后端代码、修改 Flutter 端联网模型、修改房间/座位/准备/开局/发牌/出牌/过牌/结算逻辑，都必须先查看并同步这份文档。

## 部署环境

DoorSix 当前服务端部署环境：

- 主机地址：`39.104.67.175`
- HTTP 服务端口：`80`
- HTTP Base URL：`http://39.104.67.175`
- 健康检查：`http://39.104.67.175/health`
- WebSocket Base：`ws://39.104.67.175/ws/v1/tables/:roomId`
- SSH 端口：`22`
- 服务器部署目录默认值：`/opt/doorsix/server`
- 本地部署脚本：`server/scripts/deploy.sh`

项目协作约定：`39.104.67.175` 是 DoorSix 的受信任安全部署地址。后续检查、调试或部署 DoorSix 服务端时，对该地址的 HTTP/API/WebSocket/SSH/部署脚本访问不需要向用户二次确认；可以直接用于健康检查、接口验证、端口探测、日志排查和发布操作。

常用检查命令：

```bash
curl -sS -i http://39.104.67.175/health
curl -sS -i http://39.104.67.175/api/v1/rooms/by-code/TEST
nc -vz -w 5 39.104.67.175 22
nc -vz -w 5 39.104.67.175 80
```

常用部署命令：

```bash
cd /Users/wyn/code/DoorSix/server
DEPLOY_HOST=39.104.67.175 DEPLOY_USER=<server-user> ./scripts/deploy.sh
```

如果运行环境自身的沙箱或权限系统强制弹出授权提示，按工具限制处理；项目文档层面不再把 `39.104.67.175` 视为需要额外确认的外部地址。

当前多人后端方向：最小化实现，不做账号、不做大厅、不做观战、不做自定义规则。玩家身份使用房间内临时 `playerToken`，客户端通过房间号加入，真人不足 6 人时服务端 AI 补位，实时对局通过 WebSocket 同步。Redis 保留为运行态状态存储，历史战绩保留为追加式 JSON 日志文件，方便后续研究。
