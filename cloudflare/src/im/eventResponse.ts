/**
 * 将 im_events 行与 sender 信息组装成与 SnChatMessage 兼容的 JSON。
 */

import type { Env } from "../app";

export interface EventRow {
  id: string;
  channel_id: number;
  sender_id: string;
  type: string;
  uuid: string | null;
  body: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  quote_event_id: string | null;
  related_event_id: string | null;
}

export async function buildEventResponse(
  env: Env,
  row: EventRow,
  sender?: Record<string, unknown> | null
): Promise<Record<string, unknown>> {
  const body = (() => {
    try {
      return (JSON.parse(row.body || "{}") as Record<string, unknown>) || {};
    } catch {
      return {};
    }
  })();
  const content = (body.text as string) ?? (body.content as string) ?? "";
  const attachments = (body.attachments as Record<string, unknown>[] | undefined) ?? [];
  const reactions = (body.reactions as Record<string, string[]>) ?? {};
  let replyMessage: Record<string, unknown> | null = null;
  if (row.quote_event_id) {
    const q = await env.molian_db
      .prepare("SELECT * FROM im_events WHERE id = ?")
      .bind(row.quote_event_id)
      .first() as EventRow | null;
    if (q) {
      const qSender = await env.molian_db
        .prepare("SELECT id, username, display_name, avatar_url FROM users WHERE id = ?")
        .bind(q.sender_id)
        .first() as Record<string, unknown> | null;
      replyMessage = await buildEventResponse(env, q as EventRow, qSender);
    }
  }
  let forwardedMessage: Record<string, unknown> | null = null;
  if (row.related_event_id) {
    const f = await env.molian_db
      .prepare("SELECT * FROM im_events WHERE id = ?")
      .bind(row.related_event_id)
      .first() as EventRow | null;
    if (f) {
      const fSender = await env.molian_db
        .prepare("SELECT id, username, display_name, avatar_url FROM users WHERE id = ?")
        .bind(f.sender_id)
        .first() as Record<string, unknown> | null;
      forwardedMessage = await buildEventResponse(env, f as EventRow, fSender);
    }
  }
  const senderPayload = sender
    ? {
        id: sender.id,
        username: sender.username,
        display_name: sender.display_name,
        avatar_url: sender.avatar_url,
      }
    : null;
  return {
    id: row.id,
    room_id: String(row.channel_id),
    channel_id: row.channel_id,
    sender_id: row.sender_id,
    content,
    created_at: row.created_at,
    updated_at: row.updated_at,
    deleted_at: row.deleted_at,
    nonce: row.uuid,
    attachments: Array.isArray(attachments) ? attachments : [],
    reply_message: replyMessage,
    forwarded_message: forwardedMessage,
    reactions: typeof reactions === "object" ? reactions : {},
    meta: (body.meta as Record<string, unknown>) ?? null,
    sender: senderPayload,
  };
}
