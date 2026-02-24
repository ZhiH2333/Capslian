/**
 * Molian API Worker
 * 入口：将请求交给 Hono 应用（/api/*）；/ws 转发至 ChatRoom Durable Object。
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
    return app.fetch(request, env, ctx);
  },
};

/**
 * 聊天室 Durable Object：接受 WebSocket（URL 带 token），按用户转发 DM，并落库 D1。
 */
export class ChatRoom implements DurableObject {
  private wsToUser = new Map<WebSocket, string>();
  private userToWs = new Map<string, WebSocket>();

  constructor(private ctx: DurableObjectState, private env: Env) {}

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const token = url.searchParams.get("token")?.trim();
    const secret = this.env.JWT_SECRET || "dev-secret-change-in-production";
    if (!token) {
      return new Response(JSON.stringify({ error: "缺少 token" }), { status: 401, headers: { "Content-Type": "application/json" } });
    }
    const payload = await verifyJwt(token, secret);
    if (!payload?.sub) {
      return new Response(JSON.stringify({ error: "token 无效" }), { status: 401, headers: { "Content-Type": "application/json" } });
    }
    const userId = payload.sub;
    const upgrade = request.headers.get("Upgrade");
    if (upgrade !== "websocket") {
      return new Response(JSON.stringify({ message: "ChatRoom WS" }), { status: 200, headers: { "Content-Type": "application/json" } });
    }
    const pair = new WebSocketPair();
    const [client, server] = pair;
    this.ctx.acceptWebSocket(server, [userId]);
    this.userToWs.set(userId, server);
    this.wsToUser.set(server, userId);
    return new Response(null, { status: 101, webSocket: client, headers: { Upgrade: "websocket", Connection: "Upgrade" } });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const userId = this.wsToUser.get(ws);
    if (!userId) return;
    const raw = typeof message === "string" ? message : new TextDecoder().decode(message);
    let data: { type?: string; to?: string; content?: string };
    try {
      data = JSON.parse(raw) as { type?: string; to?: string; content?: string };
    } catch {
      return;
    }
    if (data.type === "dm" && data.to && data.content) {
      const toId = String(data.to).trim();
      const content = String(data.content).trim();
      if (!toId || !content) return;
      const id = crypto.randomUUID();
      try {
        await this.env.molian_db.prepare(
          "INSERT INTO messages (id, sender_id, receiver_id, content, read) VALUES (?, ?, ?, ?, 0)"
        )
          .bind(id, userId, toId, content)
          .run();
      } catch (e) {
        console.error("ChatRoom D1 insert message error:", e);
      }
      const created_at = new Date().toISOString();
      const payload = JSON.stringify({
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
        peerWs.send(payload);
      }
      ws.send(payload);
    }
  }

  async webSocketClose(ws: WebSocket): Promise<void> {
    const userId = this.wsToUser.get(ws);
    if (userId) {
      if (this.userToWs.get(userId) === ws) this.userToWs.delete(userId);
      this.wsToUser.delete(ws);
    }
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    const userId = this.wsToUser.get(ws);
    if (userId) {
      if (this.userToWs.get(userId) === ws) this.userToWs.delete(userId);
      this.wsToUser.delete(ws);
    }
  }
}
