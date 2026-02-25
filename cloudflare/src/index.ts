/**
 * Molian API Worker
 * 入口：将请求交给 Hono 应用（/api/* 与 /messager/*）；/ws 转发至 ChatRoom Durable Object。
 */

import { verifyJwt } from "./auth/jwt";
import app from "./app";
import type { Env } from "./app";

export type { Env };

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const pathname = url.pathname.replace(/\/$/, "") || "/";
    if (pathname === "/ws" || pathname === "/api/ws") {
      const id = env.CHAT.idFromName("default");
      const stub = env.CHAT.get(id);
      return stub.fetch(request);
    }
    // /messager/chat/:roomId/broadcast 由 app.ts 内部调用，转发到 DO
    if (pathname.startsWith("/internal/chat/broadcast/")) {
      const roomId = pathname.replace("/internal/chat/broadcast/", "");
      const id = env.CHAT.idFromName("default");
      const stub = env.CHAT.get(id);
      return stub.fetch(request);
    }
    return app.fetch(request, env, ctx);
  },
};

/**
 * 聊天室 Durable Object：
 *   - 接受 WebSocket（URL 带 token），按用户维护连接
 *   - 支持 1:1 DM（type: "dm"）
 *   - 支持房间订阅（type: "messages.subscribe" / "messages.unsubscribe"）
 *   - 收到 HTTP POST /broadcast/:roomId 时向所有订阅者推送消息
 *   - 支持输入状态（type: "messages.typing"）房间内广播
 */
export class ChatRoom implements DurableObject {
  private wsToUser = new Map<WebSocket, string>();
  private userToWs = new Map<string, WebSocket>();
  /** 房间订阅：roomId → 订阅的 WebSocket 集合 */
  private roomSubscriptions = new Map<string, Set<WebSocket>>();

  constructor(private ctx: DurableObjectState, private env: Env) {}

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    // 内部广播接口：POST /broadcast/:roomId
    if (request.method === "POST" && url.pathname.startsWith("/broadcast/")) {
      const roomId = decodeURIComponent(url.pathname.replace("/broadcast/", ""));
      const payload = await request.json() as Record<string, unknown>;
      this.broadcastToRoom(roomId, payload);
      return Response.json({ ok: true });
    }

    const token = url.searchParams.get("token")?.trim();
    const secret = this.env.JWT_SECRET || "dev-secret-change-in-production";
    if (!token) {
      return new Response(JSON.stringify({ error: "缺少 token" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }
    const payload = await verifyJwt(token, secret);
    if (!payload?.sub) {
      return new Response(JSON.stringify({ error: "token 无效" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }
    const userId = payload.sub;
    const upgrade = request.headers.get("Upgrade");
    if (upgrade !== "websocket") {
      return new Response(JSON.stringify({ message: "ChatRoom WS" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
    this.ctx.acceptWebSocket(server, [userId]);
    this.userToWs.set(userId, server);
    this.wsToUser.set(server, userId);
    return new Response(null, {
      status: 101,
      webSocket: client,
      headers: { Upgrade: "websocket", Connection: "Upgrade" },
    });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const userId = this.wsToUser.get(ws);
    if (!userId) return;
    const raw = typeof message === "string" ? message : new TextDecoder().decode(message);
    let data: {
      type?: string;
      to?: string;
      content?: string;
      chat_room_id?: string;
      is_typing?: boolean;
    };
    try {
      data = JSON.parse(raw) as typeof data;
    } catch {
      return;
    }

    switch (data.type) {
      case "dm":
        await this.handleDm(ws, userId, data as { to?: string; content?: string });
        break;
      case "messages.subscribe":
        this.handleSubscribe(ws, data.chat_room_id ?? "");
        break;
      case "messages.unsubscribe":
        this.handleUnsubscribe(ws, data.chat_room_id ?? "");
        break;
      case "messages.typing":
        this.handleTyping(ws, userId, data.chat_room_id ?? "", data.is_typing ?? true);
        break;
      case "ping":
        ws.send(JSON.stringify({ type: "pong" }));
        break;
    }
  }

  private async handleDm(
    ws: WebSocket,
    userId: string,
    data: { to?: string; content?: string }
  ): Promise<void> {
    const toId = String(data.to ?? "").trim();
    const content = String(data.content ?? "").trim();
    if (!toId || !content) return;
    const id = crypto.randomUUID();
    try {
      await this.env.molian_db
        .prepare("INSERT INTO messages (id, sender_id, receiver_id, content, read) VALUES (?, ?, ?, ?, 0)")
        .bind(id, userId, toId, content)
        .run();
    } catch (e) {
      console.error("ChatRoom D1 insert message error:", e);
    }
    const created_at = new Date().toISOString();
    const payloadStr = JSON.stringify({
      type: "dm",
      id,
      sender_id: userId,
      receiver_id: toId,
      content,
      created_at,
      read: 0,
    });
    const peerWs = this.userToWs.get(toId);
    if (peerWs && peerWs.readyState === WebSocket.OPEN) {
      peerWs.send(payloadStr);
    }
    ws.send(payloadStr);
  }

  private handleSubscribe(ws: WebSocket, roomId: string): void {
    if (!roomId) return;
    if (!this.roomSubscriptions.has(roomId)) {
      this.roomSubscriptions.set(roomId, new Set());
    }
    this.roomSubscriptions.get(roomId)!.add(ws);
  }

  private handleUnsubscribe(ws: WebSocket, roomId: string): void {
    if (!roomId) return;
    this.roomSubscriptions.get(roomId)?.delete(ws);
  }

  private handleTyping(
    ws: WebSocket,
    userId: string,
    roomId: string,
    isTyping: boolean
  ): void {
    if (!roomId) return;
    const subscribers = this.roomSubscriptions.get(roomId);
    if (!subscribers) return;
    const payload = JSON.stringify({
      type: "messages.typing",
      chat_room_id: roomId,
      user_id: userId,
      is_typing: isTyping,
    });
    for (const sub of subscribers) {
      if (sub !== ws && sub.readyState === WebSocket.OPEN) {
        sub.send(payload);
      }
    }
  }

  /** 向指定房间的所有订阅者广播消息。 */
  broadcastToRoom(roomId: string, payload: Record<string, unknown>): void {
    const subscribers = this.roomSubscriptions.get(roomId);
    if (!subscribers) return;
    const msg = JSON.stringify(payload);
    for (const ws of subscribers) {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(msg);
      }
    }
  }

  async webSocketClose(ws: WebSocket): Promise<void> {
    this.cleanupWs(ws);
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    this.cleanupWs(ws);
  }

  private cleanupWs(ws: WebSocket): void {
    const userId = this.wsToUser.get(ws);
    if (userId) {
      if (this.userToWs.get(userId) === ws) this.userToWs.delete(userId);
      this.wsToUser.delete(ws);
    }
    for (const subs of this.roomSubscriptions.values()) {
      subs.delete(ws);
    }
  }
}
