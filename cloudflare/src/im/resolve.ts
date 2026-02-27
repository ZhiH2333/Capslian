/**
 * 从 path 的 scope / alias 解析出唯一 channel。
 * scope = 'global' → realm_id 为空；否则用 scope 查 realm（by slug），再查 (realm_id, alias)。
 */

import type { Env } from "../app";

export interface ResolvedChannel {
  id: number;
  realm_id: string | null;
  alias: string;
  name: string;
  type: string;
  description: string | null;
  avatar_url: string | null;
  created_at: string;
}

/**
 * 解析 channel：scope 为 'global' 时 realm_id 为 null；否则用 scope 当作 realm 的 slug 查 realm_id。
 */
export async function resolveChannel(
  db: D1Database,
  scope: string,
  alias: string
): Promise<ResolvedChannel | null> {
  let realmId: string | null = null;
  if (scope !== "global" && scope.length > 0) {
    const realm = await db
      .prepare("SELECT id FROM realms WHERE slug = ?")
      .bind(scope)
      .first() as { id: string } | null;
    if (!realm) return null;
    realmId = realm.id;
  }
  const row =
    realmId === null
      ? await db
          .prepare(
            "SELECT id, realm_id, alias, name, type, description, avatar_url, created_at FROM im_channels WHERE realm_id IS NULL AND alias = ?"
          )
          .bind(alias)
          .first() as Record<string, unknown> | null
      : await db
          .prepare(
            "SELECT id, realm_id, alias, name, type, description, avatar_url, created_at FROM im_channels WHERE realm_id = ? AND alias = ?"
          )
          .bind(realmId, alias)
          .first() as Record<string, unknown> | null;
  if (!row || typeof row.id !== "number") return null;
  return {
    id: row.id as number,
    realm_id: row.realm_id as string | null,
    alias: row.alias as string,
    name: row.name as string,
    type: row.type as string,
    description: row.description as string | null,
    avatar_url: row.avatar_url as string | null,
    created_at: row.created_at as string,
  };
}

/** keyPath = scope/alias，用于 REST path。 */
export function channelKeyPath(scope: string, alias: string): string {
  return `${scope}/${alias}`;
}
