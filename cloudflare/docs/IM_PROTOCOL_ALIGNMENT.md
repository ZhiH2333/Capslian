# IM 协议与客户端对齐说明

本文档说明「聊天消息同步与聊天室识别」规范与当前 Flutter 客户端、Cloudflare 后端的字段与行为对齐方式，供后端实现与后续客户端迁移参考。

## 一、聊天室识别

| 规范概念 | 说明 | 当前后端 | 客户端 |
|----------|------|----------|--------|
| 逻辑键 | `scope:alias`（如 `global:dm-123`） | 当前使用 `room_id`（UUID 字符串） | 路由 `/:scope/:alias` 未使用，房间用 id 字符串 |
| keyPath | URL 路径形态 `scope/alias` | `/messager/chat/:roomId` | 同左 |
| channel_id | 整数主键，用于 WS 订阅与过滤 | 无，当前为 room_id 字符串 | SnChatMessage 使用 `roomId` 字符串 |

**对齐策略**：新 IM 接口使用 `scope/alias` 解析得到整数 `channel_id`。返回给客户端的消息中同时提供 `channel_id`（int）与 `room_id`（string，即 `String(channel_id)`），便于现有 `SnChatMessage.fromJson` 继续用 `room_id` 解析；新客户端可用 `channel_id` 做 WebSocket 订阅与过滤。

## 二、消息/事件字段对齐

| 规范 | SnChatMessage（当前客户端） | 后端返回建议 |
|------|-----------------------------|--------------|
| 消息主键 | `id` (string) | 事件表主键，字符串 |
| 房间标识 | `roomId` (string) | 与 `channel_id` 一致时返回 `room_id: String(channel_id)` |
| 发送者 | `senderId` (string) | `sender_id`，对应 users.id |
| 内容 | `content` (string) | 从 body 中取 text/content |
| 客户端去重 | 规范用 `uuid` | 客户端当前用 `nonce` | 后端统一用 `nonce` 字段存客户端 uuid，返回 `nonce` 即可 |
| 时间 | `createdAt`, `updatedAt`, `deletedAt` | ISO8601 字符串 |
| 引用/转发 | `reply_message`, `forwarded_message` | 嵌套对象或 id | `quote_event_id` / `related_event_id` 对应 |

客户端已支持：`id`, `room_id`, `sender_id`, `content`, `created_at`, `updated_at`, `deleted_at`, `nonce`, `attachments`, `reply_message`, `forwarded_message`, `reactions`, `meta`, `sender`。新 IM 接口返回的事件对象保持上述字段名与结构即可直接 `SnChatMessage.fromJson(payload)`。

## 三、WebSocket 报文格式

| 规范 | 当前实现 | 对齐方式 |
|------|----------|----------|
| 连接 | `ws(s)://{baseUrl}/ws?tk={accessToken}` | `/ws?token=` | 可同时支持 `tk` 与 `token` |
| 报文 | `w`(method), `e`(endpoint), `m`, `p`(payload) | 当前为扁平 JSON：`type`, `message`, `room_id` | Phase 2 可增加 `w`/`e`/`p` 格式；payload 内保留 `channel_id` 与完整消息对象 |
| 订阅 | `events.subscribe`，payload `{ "channel_id": <int> }` | `messages.subscribe`（当前 no-op） | 新 DO 或扩展现有 DO：按 channel_id 维护订阅集合 |
| 新消息推送 | method `events.new`，payload 含 `channel_id` + 完整消息 | `messages.new`，payload 含 `message`、`room_id` | 新协议下推送 `events.new` 且 payload 含 `channel_id` 与完整事件对象；客户端可按 channel_id 过滤 |

现有客户端根据 `room_id` / `chat_room_id` 路由到对应房间；新协议下可同时带 `channel_id`（int）与 `room_id`（string），便于渐进迁移。

## 四、REST 路径对齐

| 规范 | 实现路径 |
|------|----------|
| 解析 channel | `GET /cgi/im/channels/:scope/:alias` |
| 消息列表 | `GET /cgi/im/channels/:scope/:alias/events?take=&offset=` |
| 增量同步 | `GET /cgi/im/channels/:scope/:alias/events/update?pivot=` |
| 单条事件 | `GET /cgi/im/channels/:scope/:alias/events/:eventId` |
| 发消息 | `POST /cgi/im/channels/:scope/:alias/messages` |
| 编辑/删消息 | `PUT/DELETE .../messages/:messageId` |

鉴权：Header `Authorization: Bearer <token>` 或 query `tk=`，校验后得到 account_id（即 users.id）；channel 操作前校验 im_channel_members。

## 五、与现有 /messager 的关系

- 现有 `/messager/chat`、`/messager/chat/:roomId/messages` 等保留，供当前客户端继续使用。
- 新 IM 协议挂在 `/cgi/im/channels/{scope}/{alias}/...`，与 scope/alias → channel_id 逻辑一致；后续可将客户端逐步迁移到 scope/alias + 新 REST/WS，再考虑是否废弃旧 path。
