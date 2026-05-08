# DoorSix Web 端免 nginx 部署设计

## 1. 背景

DoorSix 当前已有一套多人服务端，远端服务监听 `80` 端口，并提供 HTTP API 与 WebSocket。为支持 iPhone 用户在没有 iOS App 发布渠道的情况下加入游戏，需要增加一个浏览器可访问的 Web 端。

本阶段目标是最小化部署复杂度：不新增 nginx，直接由现有 Node/Express 服务同时托管 API、WebSocket 和 Flutter Web 静态资源。

## 2. 目标

- iPhone、Android、桌面浏览器都可以通过 URL 打开 Web 端。
- Web 端与安卓端共用同一套服务端 API 和 WebSocket 协议。
- Web 端路径与现有接口明确隔离，避免影响线上 API。
- 不引入 nginx、额外反向代理或新端口。
- 后续仍然可以平滑升级到 nginx + HTTPS。

## 3. 产品命名

部署在服务器上的浏览器游玩版本命名为：

```text
云牌桌
```

Web 端浏览器页面标题必须显示“云牌桌”，例如 `web/index.html` 中的 `<title>` 使用：

```html
<title>云牌桌</title>
```

安卓端继续保持现有 App 命名，不显示“云牌桌”。

## 4. 路径规划

现有服务端路径保持不变：

| 路径 | 用途 |
| --- | --- |
| `/health` | 服务健康检查 |
| `/api/v1/...` | HTTP API |
| `/ws/v1/tables/:roomId` | WebSocket 对局通道 |

新增 Web 端路径：

| 路径 | 用途 |
| --- | --- |
| `/play/` | Flutter Web 首页入口 |
| `/play/*` | Flutter Web 静态资源或前端路由 fallback |

玩家访问地址：

```text
http://39.104.67.175/play/
```

## 5. 服务端托管方式

Express 服务继续监听当前端口。新增静态文件目录，例如：

```text
server/public/play/
```

Flutter Web 构建产物放入该目录：

```text
server/public/play/index.html
server/public/play/main.dart.js
server/public/play/assets/...
```

Express 路由规则：

1. `/api/v1/...` 优先命中 API。
2. `/ws/v1/tables/:roomId` 仍由 HTTP upgrade 处理。
3. `/play/` 静态托管 `server/public/play`。
4. `/play/*` 如果不是实际静态文件，则返回 `/play/index.html`，支持 Flutter Web 前端路由。

## 6. Flutter Web 构建要求

Web 端需要使用 `/play/` 作为 base href：

```bash
flutter build web --release --base-href /play/
```

这样浏览器加载资源时会从 `/play/` 下寻找 `main.dart.js`、assets 和 Flutter runtime 文件。

## 7. 客户端网络要求

Flutter Web 不能使用 `dart:io`。Web 适配时需要把当前网络层改成跨平台实现：

| 能力 | 当前实现 | Web 适配目标 |
| --- | --- | --- |
| HTTP | `dart:io` `HttpClient` | `package:http` |
| WebSocket | `dart:io` `WebSocket` | `web_socket_channel` |

安卓端和 Web 端应共用同一套业务接口封装，只在底层网络实现上使用浏览器兼容库。

## 8. 配置来源

对局出牌时间等运行配置继续由服务端权威下发。Web 端与安卓端一样，从服务端快照读取：

```json
{
  "turnDurationSeconds": 15
}
```

客户端不在联机场景中自行定义出牌时间。

## 9. 部署流程

建议部署流程：

1. 构建 Flutter Web：

   ```bash
   flutter build web --release --base-href /play/
   ```

2. 清空旧 Web 静态目录：

   ```bash
   rm -rf server/public/play
   ```

3. 拷贝新构建产物：

   ```bash
   mkdir -p server/public/play
   cp -R build/web/* server/public/play/
   ```

4. 执行现有 server 部署脚本。

部署脚本后续应把 `server/public` 一并打包到远端。

## 10. 为什么暂不使用 nginx

当前远端只有一个 DoorSix 服务占用 `80` 端口，Express 已经可以同时处理：

- HTTP API
- WebSocket upgrade
- Flutter Web 静态文件

因此第一版不需要 nginx，能减少部署复杂度和故障点。

## 11. 何时升级到 nginx

出现以下需求时，再引入 nginx：

- 绑定正式域名。
- 开启 HTTPS 证书。
- 多个服务共用 `80` / `443`。
- 需要更强的静态资源缓存、压缩或 CDN 配置。
- 需要蓝绿发布、灰度发布或多版本 Web 前端。
- 需要统一反向代理多个后端服务。

## 12. 后续实现清单

- 增加 Flutter Web 工程目录。
- Web 端 `title` 设置为“云牌桌”，安卓端标题保持不变。
- 将网络层改为 Web/Android 兼容实现。
- 服务端新增 `/play/` 静态托管。
- 部署脚本打包 `server/public`。
- 构建并部署 Flutter Web 到 `/play/`。
- 在 iPhone Safari、微信浏览器和 Android Chrome 上做联机验证。
