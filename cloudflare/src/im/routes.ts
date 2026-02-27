/**
 * IM REST：/cgi/im/channels/:scope/:alias 下的 channel 解析与 events/messages 接口。
 * 与协议说明对齐：scope/alias → channel_id，返回 SnChatMessage 兼容结构。
 */

import { Hono } from "hono";
import { verifyJwt } from "../auth/jwt";
import { uuid } from "../auth/refresh";
import type { Env } from "../app";
import { resolveChannel, channelKeyPath } from "./resolve";
import { buildEventResponse, type EventRow } from "./eventResponse";

const CORS: HeadersInit = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

function getSecret(env: Env): string {
  return env.JWT_SECRET || "dev-secret-change-in-production";
}

async function getUserIdFromRequest(c: { req: Request; env: Env }): Promise<string | null> {
  const auth = c.req.headers.get("Authorization");
  let token = auth?.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!token) {
    const url = new URL(c.req.url);
    token = url.searchParams.get("tk")?.trim() ?? "";
  }
  if (!token) return null;
  const secret = getSecret(c.env);
  const payload = await verifyJwt(token, secret);
  return payload ? payload.sub : null;
}

async function ensureChannelMember(
  db: D1Database,
  channelId: number,
  accountId: string
): Promise<boolean> {
  const row = await db
    .prepare("SELECT 1 FROM im_channel_members WHERE channel_id = ? AND account_id = ?")
    .bind(channelId, accountId)
    .first();
  return !!row;
}

const im = new Hono<{ Bindings: Env }>();

// POST /cgi/im/channels — 创建频道（body: scope, alias, name?, type?, member_ids?）
im.post("/channels", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, { headers: CORS });
  const body = (await c.req.json()) as {
    scope?: string;
    alias?: string;
    name?: string;
    type?: string;
    member_ids?: string[];
  };
  const scope = String(body?.scope ?? "").trim() || "global";
  const alias = String(body?.alias ?? "").trim();
  const name = String(body?.name ?? "").trim() || alias;
  const type = String(body?.type ?? "direct").trim() || "direct";
  if (!alias) return c.json({ error: "alias 必填" }, 400, { headers: CORS });
  let realmId: string | null = null;
  if (scope !== "global") {
    const realm = await c.env.molian_db
      .prepare("SELECT id FROM realms WHERE slug = ?")
      .bind(scope)
      .first() as { id: string } | null;
    if (!realm) return c.json({ error: "scope 对应圈子不存在" }, 404, { headers: CORS });
    realmId = realm.id;
  }
  const existing = await resolveChannel(c.env.molian_db, scope, alias);
  if (existing) {
    const isMember = await ensureChannelMember(c.env.molian_db, existing.id, userId);
    if (!isMember) return c.json({ error: "频道已存在且您不是成员" }, 403, { headers: CORS });
    const key = existing.realm_id === null ? `global:${existing.alias}` : `${scope}:${existing.alias}`;
    return c.json(
      {
        id: existing.id,
        key,
        keyPath: channelKeyPath(scope, alias),
        realm_id: existing.realm_id,
        alias: existing.alias,
        name: existing.name,
        type: existing.type,
        description: existing.description,
        avatar_url: existing.avatar_url,
        created_at: existing.created_at,
      },
      200,
      { headers: CORS }
    );
  }
  try {
    const insert = await c.env.molian_db
      .prepare(
        "INSERT INTO im_channels (realm_id, alias, name, type) VALUES (?, ?, ?, ?)"
      )
      .bind(realmId, alias, name, type)
      .run();
    const channelId = (insert.meta as { last_row_id?: number })?.last_row_id;
    if (channelId == null) return c.json({ error: "创建失败" }, 500, { headers: CORS });
    const memberIds = Array.isArray(body?.member_ids) ? body.member_ids : [];
    const allAccountIds = [userId, ...memberIds].filter((id) => id && id !== userId);
    const uniqueIds = [...new Set(allAccountIds)];
    for (const accountId of uniqueIds) {
      await c.env.molian_db
        .prepare(
          "INSERT OR IGNORE INTO im_channel_members (id, channel_id, account_id, role) VALUES (?, ?, ?, 'member')"
        )
        .bind(uuid(), channelId, accountId)
        .run();
    }
    const channel = await resolveChannel(c.env.molian_db, scope, alias);
    if (!channel) return c.json({ error: "创建失败" }, 500, { headers: CORS });
    const key = channel.realm_id === null ? `global:${channel.alias}` : `${scope}:${channel.alias}`;
    return c.json(
      {
        id: channel.id,
        key,
        keyPath: channelKeyPath(scope, alias),
        realm_id: channel.realm_id,
        alias: channel.alias,
        name: channel.name,
        type: channel.type,
        description: channel.description,
        avatar_url: channel.avatar_url,
        created_at: channel.created_at,
      },
      201,
      { headers: CORS }
    );
  } catch (e) {
    console.error("im POST channels error:", e);
    return c.json({ error: "创建失败" }, 500, { headers: CORS });
  }
});

// GET /cgi/im/channels/:scope/:alias — 解析 channel，返回 channel 信息（含 id、key、keyPath）
im.get("/channels/:scope/:alias", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, { headers: CORS });
  const scope = decodeURIComponent(c.req.param("scope"));
  const alias = decodeURIComponent(c.req.param("alias"));
  const channel = await resolveChannel(c.env.molian_db, scope, alias);
  if (!channel) return c.json({ error: "频道不存在" }, 404, { headers: CORS });
  const isMember = await ensureChannelMember(c.env.molian_db, channel.id, userId);
  if (!isMember) return c.json({ error: "无权限" }, 403, { headers: CORS });
  const key = channel.realm_id === null ? `global:${channel.alias}` : `${scope}:${channel.alias}`;
  return c.json(
    {
      id: channel.id,
      key,
      keyPath: channelKeyPath(scope, alias),
      realm_id: channel.realm_id,
      alias: channel.alias,
      name: channel.name,
      type: channel.type,
      description: channel.description,
      avatar_url: channel.avatar_url,
      created_at: channel.created_at,
    },
    200,
    { headers: CORS }
  );
});

// GET /cgi/im/channels/:scope/:alias/events?take=20&offset=0
im.get("/channels/:scope/:alias/events", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, { headers: CORS });
  const scope = decodeURIComponent(c.req.param("scope"));
  const alias = decodeURIComponent(c.req.param("alias"));
  const channel = await resolveChannel(c.env.molian_db, scope, alias);
  if (!channel) return c.json({ error: "频道不存在" }, 404, { headers: CORS });
  const isMember = await ensureChannelMember(c.env.molian_db, channel.id, userId);
  if (!isMember) return c.json({ error: "无权限" }, 403, { headers: CORS });
  const take = Math.min(100, Math.max(1, Number(c.req.query("take")) || 20));
  const offset = Math.max(0, Number(c.req.query("offset")) || 0);
  try {
    const { results } = await c.env.molian_db
      .prepare(
        "SELECT id, channel_id, sender_id, type, uuid, body, created_at, updated_at, deleted_at, quote_event_id, related_event_id FROM im_events WHERE channel_id = ? ORDER BY created_at ASC LIMIT ? OFFSET ?"
      )
      .bind(channel.id, take, offset)
      .all();
    const list = results as EventRow[];
    const countRow = await c.env.molian_db
      .prepare("SELECT COUNT(*) as total FROM im_events WHERE channel_id = ?")
      .bind(channel.id)
      .first() as { total: number } | null;
    const total = countRow?.total ?? 0;
    const data = await Promise.all(
      list.map(async (r) => {
        const sender = await c.env.molian_db
          .prepare("SELECT id, username, display_name, avatar_url FROM users WHERE id = ?")
          .bind(r.sender_id)
          .first() as Record<string, unknown> | null;
        return buildEventResponse(c.env, r, sender);
      })
    );
    return c.json({ count: total, data }, 200, { headers: CORS });
  } catch (e) {
    console.error("im events list error:", e);
    return c.json({ error: "获取失败" }, 500, { headers: CORS });
  }
});

// GET /cgi/im/channels/:scope/:alias/events/update?pivot=<messageId>
im.get("/channels/:scope/:alias/events/update", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, { headers: CORS });
  const scope = decodeURIComponent(c.req.param("scope"));
  const alias = decodeURIComponent(c.req.param("alias"));
  const channel = await resolveChannel(c.env.molian_db, scope, alias);
  if (!channel) return c.json({ error: "频道不存在" }, 404, { headers: CORS });
  const isMember = await ensureChannelMember(c.env.molian_db, channel.id, userId);
  if (!isMember) return c.json({ error: "无权限" }, 403, { headers: CORS });
  const pivot = c.req.query("pivot")?.trim();
  if (!pivot) return c.json({ up_to_date: true, count: 0 }, 200, { headers: CORS });
  try {
    const pivotRow = await c.env.molian_db
      .prepare("SELECT created_at FROM im_events WHERE id = ? AND channel_id = ?")
      .bind(pivot, channel.id)
      .first() as { created_at: string } | null;
    if (!pivotRow) return c.json({ up_to_date: true, count: 0 }, 200, { headers: CORS });
    const countRow = await c.env.molian_db
      .prepare(
        "SELECT COUNT(*) as c FROM im_events WHERE channel_id = ? AND created_at > ?"
      )
      .bind(channel.id, pivotRow.created_at)
      .first() as { c: number } | null;
    const count = countRow?.c ?? 0;
    return c.json({ up_to_date: count === 0, count }, 200, { headers: CORS });
  } catch (e) {
    console.error("im events/update error:", e);
    return c.json({ error: "获取失败" }, 500, { headers: CORS });
  }
});

// GET /cgi/im/channels/:scope/:alias/events/:eventId
im.get("/channels/:scope/:alias/events/:eventId", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, { headers: CORS });
  const scope = decodeURIComponent(c.req.param("scope"));
  const alias = decodeURIComponent(c.req.param("alias"));
  const eventId = c.req.param("eventId");
  const channel = await resolveChannel(c.env.molian_db, scope, alias);
  if (!channel) return c.json({ error: "频道不存在" }, 404, { headers: CORS });
  const isMember = await ensureChannelMember(c.env.molian_db, channel.id, userId);
  if (!isMember) return c.json({ error: "无权限" }, 403, { headers: CORS });
  const row = await c.env.molian_db
    .prepare(
      "SELECT id, channel_id, sender_id, type, uuid, body, created_at, updated_at, deleted_at, quote_event_id, related_event_id FROM im_events WHERE id = ? AND channel_id = ?"
    )
    .bind(eventId, channel.id)
    .first() as EventRow | null;
  if (!row) return c.json({ error: "事件不存在" }, 404, { headers: CORS });
  const sender = await c.env.molian_db
    .prepare("SELECT id, username, display_name, avatar_url FROM users WHERE id = ?")
    .bind(row.sender_id)
    .first() as Record<string, unknown> | null;
  const data = await buildEventResponse(c.env, row, sender);
  return c.json(data, 200, { headers: CORS });
});

// POST /cgi/im/channels/:scope/:alias/messages — body: { type, uuid, body }
im.post("/channels/:scope/:alias/messages", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, { headers: CORS });
  const scope = decodeURIComponent(c.req.param("scope"));
  const alias = decodeURIComponent(c.req.param("alias"));
  const channel = await resolveChannel(c.env.molian_db, scope, alias);
  if (!channel) return c.json({ error: "频道不存在" }, 404, { headers: CORS });
  const isMember = await ensureChannelMember(c.env.molian_db, channel.id, userId);
  if (!isMember) return c.json({ error: "无权限" }, 403, { headers: CORS });
  const body = (await c.req.json()) as { type?: string; uuid?: string; body?: unknown };
  const type = String(body?.type ?? "text").trim() || "text";
  const clientUuid = typeof body?.uuid === "string" ? body.uuid.trim() : null;
  const bodyJson = body?.body != null ? JSON.stringify(body.body) : "{}";
  const eventId = uuid();
  try {
    await c.env.molian_db
      .prepare(
        "INSERT INTO im_events (id, channel_id, sender_id, type, uuid, body) VALUES (?, ?, ?, ?, ?, ?)"
      )
      .bind(eventId, channel.id, userId, type, clientUuid, bodyJson)
      .run();
    const row = await c.env.molian_db
      .prepare(
        "SELECT id, channel_id, sender_id, type, uuid, body, created_at, updated_at, deleted_at, quote_event_id, related_event_id FROM im_events WHERE id = ?"
      )
      .bind(eventId)
      .first() as EventRow | null;
    if (!row) return c.json({ error: "发送失败" }, 500, { headers: CORS });
    const sender = await c.env.molian_db
      .prepare("SELECT id, username, display_name, avatar_url FROM users WHERE id = ?")
      .bind(userId)
      .first() as Record<string, unknown> | null;
    const data = await buildEventResponse(c.env, row, sender);
    return c.json(data, 200, { headers: CORS });
  } catch (e) {
    console.error("im POST messages error:", e);
    return c.json({ error: "发送失败" }, 500, { headers: CORS });
  }
});

// PUT /cgi/im/channels/:scope/:alias/messages/:messageId
im.put("/channels/:scope/:alias/messages/:messageId", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, { headers: CORS });
  const scope = decodeURIComponent(c.req.param("scope"));
  const alias = decodeURIComponent(c.req.param("alias"));
  const messageId = c.req.param("messageId");
  const channel = await resolveChannel(c.env.molian_db, scope, alias);
  if (!channel) return c.json({ error: "频道不存在" }, 404, { headers: CORS });
  const isMember = await ensureChannelMember(c.env.molian_db, channel.id, userId);
  if (!isMember) return c.json({ error: "无权限" }, 403, { headers: CORS });
  const existing = await c.env.molian_db
    .prepare("SELECT sender_id, body FROM im_events WHERE id = ? AND channel_id = ?")
    .bind(messageId, channel.id)
    .first() as { sender_id: string; body: string } | null;
  if (!existing) return c.json({ error: "消息不存在" }, 404, { headers: CORS });
  if (existing.sender_id !== userId) return c.json({ error: "只能编辑自己的消息" }, 403, { headers: CORS });
  const body = (await c.req.json()) as { body?: unknown };
  const bodyJson = body?.body != null ? JSON.stringify(body.body) : existing.body;
  await c.env.molian_db
    .prepare("UPDATE im_events SET body = ?, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?")
    .bind(bodyJson, messageId)
    .run();
  const row = await c.env.molian_db
    .prepare(
      "SELECT id, channel_id, sender_id, type, uuid, body, created_at, updated_at, deleted_at, quote_event_id, related_event_id FROM im_events WHERE id = ?"
    )
    .bind(messageId)
    .first() as EventRow | null;
  if (!row) return c.json({ error: "操作失败" }, 500, { headers: CORS });
  const sender = await c.env.molian_db
    .prepare("SELECT id, username, display_name, avatar_url FROM users WHERE id = ?")
    .bind(userId)
    .first() as Record<string, unknown> | null;
  const data = await buildEventResponse(c.env, row, sender);
  return c.json(data, 200, { headers: CORS });
});

// DELETE /cgi/im/channels/:scope/:alias/messages/:messageId
im.delete("/channels/:scope/:alias/messages/:messageId", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, { headers: CORS });
  const scope = decodeURIComponent(c.req.param("scope"));
  const alias = decodeURIComponent(c.req.param("alias"));
  const messageId = c.req.param("messageId");
  const channel = await resolveChannel(c.env.molian_db, scope, alias);
  if (!channel) return c.json({ error: "频道不存在" }, 404, { headers: CORS });
  const isMember = await ensureChannelMember(c.env.molian_db, channel.id, userId);
  if (!isMember) return c.json({ error: "无权限" }, 403, { headers: CORS });
  const existing = await c.env.molian_db
    .prepare("SELECT sender_id FROM im_events WHERE id = ? AND channel_id = ?")
    .bind(messageId, channel.id)
    .first() as { sender_id: string } | null;
  if (!existing) return c.json({ error: "消息不存在" }, 404, { headers: CORS });
  if (existing.sender_id !== userId) return c.json({ error: "只能撤回自己的消息" }, 403, { headers: CORS });
  await c.env.molian_db
    .prepare("UPDATE im_events SET deleted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = ?")
    .bind(messageId)
    .run();
  return c.json({ deleted: true }, 200, { headers: CORS });
});

export default im;
