/**
 * Hono 应用：聚合 /api 路由，与 Flutter 模块一一对应。
 */

import { Hono } from "hono";
import { hashPassword, verifyPassword } from "./auth/password";
import { signJwt, verifyJwt } from "./auth/jwt";
import {
  generateRefreshToken,
  sha256Hex,
  uuid,
  REFRESH_TOKEN_EXPIRY_SECONDS,
} from "./auth/refresh";

export interface Env {
  molian_db: D1Database;
  ASSETS: R2Bucket;
  CHAT: DurableObjectNamespace;
  JWT_SECRET: string;
}

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

function corsHeaders(): HeadersInit {
  return { ...CORS_HEADERS };
}

async function getUserIdFromRequest(c: { req: Request; env: Env }): Promise<string | null> {
  const auth = c.req.header("Authorization");
  const token = auth?.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) return null;
  const secret = c.env.JWT_SECRET || "dev-secret-change-in-production";
  const payload = await verifyJwt(token, secret);
  return payload ? payload.sub : null;
}

function getSecret(env: Env): string {
  return env.JWT_SECRET || "dev-secret-change-in-production";
}

const app = new Hono<{ Bindings: Env }>();

app.use("*", async (c, next) => {
  if (c.req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }
  await next();
});

app.get("/", (c) => c.json({ ok: true }, 200, corsHeaders()));
app.get("/health", (c) => c.json({ ok: true }, 200, corsHeaders()));

// ----- Auth -----
app.post("/api/auth/register", async (c) => {
  const env = c.env;
  const secret = getSecret(env);
  try {
    const body = (await c.req.json()) as { username?: string; password?: string; displayName?: string };
    const username = String(body?.username ?? "").trim().toLowerCase();
    const password = String(body?.password ?? "");
    const displayName = (body?.displayName as string)?.trim() || username;
    if (!username || username.length < 2) return c.json({ error: "用户名至少 2 个字符" }, 400, corsHeaders());
    if (!password || password.length < 6) return c.json({ error: "密码至少 6 个字符" }, 400, corsHeaders());
    const { hashHex, saltBase64 } = await hashPassword(password);
    const id = uuid();
    await env.molian_db.prepare(
      "INSERT INTO users (id, username, password_hash, salt, display_name) VALUES (?, ?, ?, ?, ?)"
    )
      .bind(id, username, hashHex, saltBase64, displayName)
      .run();
    const token = await signJwt({ sub: id }, secret);
    const refreshToken = generateRefreshToken();
    const tokenHash = await sha256Hex(refreshToken);
    const expiresAt = new Date(Date.now() + REFRESH_TOKEN_EXPIRY_SECONDS * 1000).toISOString().replace("T", " ").slice(0, 19);
    await env.molian_db.prepare(
      "INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)"
    )
      .bind(uuid(), id, tokenHash, expiresAt)
      .run();
    const row = await env.molian_db.prepare(
      "SELECT id, username, display_name, avatar_url, bio, created_at FROM users WHERE id = ?"
    )
      .bind(id)
      .first();
    return c.json({ token, refresh_token: refreshToken, user: row }, 200, corsHeaders());
  } catch (e: unknown) {
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    console.error("Register error:", msg);
    if (msg.includes("UNIQUE") || msg.includes("unique")) return c.json({ error: "用户名已存在" }, 409, corsHeaders());
    return c.json({ error: "注册失败: " + msg }, 500, corsHeaders());
  }
});

app.post("/api/auth/login", async (c) => {
  const env = c.env;
  const secret = getSecret(env);
  try {
    const body = (await c.req.json()) as { username?: string; password?: string };
    const username = String(body?.username ?? "").trim().toLowerCase();
    const password = String(body?.password ?? "");
    if (!username || !password) return c.json({ error: "用户名和密码必填" }, 400, corsHeaders());
    const row = await env.molian_db.prepare(
      "SELECT id, username, password_hash, salt, display_name, avatar_url, bio, created_at FROM users WHERE username = ?"
    )
      .bind(username)
      .first();
    if (!row || typeof row !== "object") return c.json({ error: "用户名或密码错误" }, 401, corsHeaders());
    const r = row as Record<string, unknown>;
    const ok = await verifyPassword(password, String(r.salt), String(r.password_hash));
    if (!ok) return c.json({ error: "用户名或密码错误" }, 401, corsHeaders());
    const token = await signJwt({ sub: String(r.id) }, secret);
    const refreshToken = generateRefreshToken();
    const tokenHash = await sha256Hex(refreshToken);
    const expiresAt = new Date(Date.now() + REFRESH_TOKEN_EXPIRY_SECONDS * 1000).toISOString().replace("T", " ").slice(0, 19);
    await env.molian_db.prepare(
      "INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)"
    )
      .bind(uuid(), String(r.id), tokenHash, expiresAt)
      .run();
    const user = {
      id: r.id,
      username: r.username,
      display_name: r.display_name,
      avatar_url: r.avatar_url,
      bio: r.bio,
      created_at: r.created_at,
    };
    return c.json({ token, refresh_token: refreshToken, user }, 200, corsHeaders());
  } catch {
    return c.json({ error: "登录失败" }, 500, corsHeaders());
  }
});

app.get("/api/auth/me", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const row = await c.env.molian_db.prepare(
    "SELECT id, username, display_name, avatar_url, bio, created_at FROM users WHERE id = ?"
  )
    .bind(userId)
    .first();
  if (!row || typeof row !== "object") return c.json({ error: "用户不存在" }, 404, corsHeaders());
  return c.json({ user: row }, 200, corsHeaders());
});

app.post("/api/auth/refresh", async (c) => {
  const env = c.env;
  const secret = getSecret(env);
  try {
    const body = (await c.req.json()) as { refresh_token?: string };
    const refreshToken = String(body?.refresh_token ?? "").trim();
    if (!refreshToken) return c.json({ error: "refresh_token 必填" }, 400, corsHeaders());
    const tokenHash = await sha256Hex(refreshToken);
    const row = await env.molian_db.prepare(
      "SELECT id, user_id FROM refresh_tokens WHERE token_hash = ? AND expires_at > datetime('now')"
    )
      .bind(tokenHash)
      .first();
    if (!row || typeof row !== "object") return c.json({ error: "refresh token 无效或已过期" }, 401, corsHeaders());
    const r = row as { id: string; user_id: string };
    await env.molian_db.prepare("DELETE FROM refresh_tokens WHERE id = ?").bind(r.id).run();
    const token = await signJwt({ sub: r.user_id }, secret);
    const newRefreshToken = generateRefreshToken();
    const newHash = await sha256Hex(newRefreshToken);
    const expiresAt = new Date(Date.now() + REFRESH_TOKEN_EXPIRY_SECONDS * 1000).toISOString().replace("T", " ").slice(0, 19);
    await env.molian_db.prepare(
      "INSERT INTO refresh_tokens (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)"
    )
      .bind(uuid(), r.user_id, newHash, expiresAt)
      .run();
    const userRow = await env.molian_db.prepare(
      "SELECT id, username, display_name, avatar_url, bio, created_at FROM users WHERE id = ?"
    )
      .bind(r.user_id)
      .first();
    return c.json({ token, refresh_token: newRefreshToken, user: userRow }, 200, corsHeaders());
  } catch (e) {
    console.error("Refresh error:", e);
    return c.json({ error: "刷新失败" }, 500, corsHeaders());
  }
});

// ----- Users -----
app.patch("/api/users/me", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  try {
    const body = (await c.req.json()) as { display_name?: string; bio?: string; avatar_url?: string };
    const updates: string[] = [];
    const values: unknown[] = [];
    if (body?.display_name !== undefined) {
      updates.push("display_name = ?");
      values.push(String(body.display_name).trim());
    }
    if (body?.bio !== undefined) {
      updates.push("bio = ?");
      values.push(String(body.bio).trim());
    }
    if (body?.avatar_url !== undefined) {
      updates.push("avatar_url = ?");
      values.push(String(body.avatar_url).trim());
    }
    if (updates.length === 0) return c.json({ error: "无有效字段" }, 400, corsHeaders());
    values.push(userId);
    await c.env.molian_db.prepare(`UPDATE users SET ${updates.join(", ")} WHERE id = ?`).bind(...values).run();
    const row = await c.env.molian_db.prepare(
      "SELECT id, username, display_name, avatar_url, bio, created_at FROM users WHERE id = ?"
    )
      .bind(userId)
      .first();
    return c.json({ user: row }, 200, corsHeaders());
  } catch {
    return c.json({ error: "更新失败" }, 500, corsHeaders());
  }
});

app.get("/api/users/me/following", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const { results } = await c.env.molian_db.prepare(
    "SELECT u.id, u.username, u.display_name, u.avatar_url FROM users u INNER JOIN follows f ON f.following_id = u.id WHERE f.follower_id = ?"
  )
    .bind(userId)
    .all();
  return c.json({ users: results }, 200, corsHeaders());
});

app.get("/api/users/me/followers", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const { results } = await c.env.molian_db.prepare(
    "SELECT u.id, u.username, u.display_name, u.avatar_url FROM users u INNER JOIN follows f ON f.follower_id = u.id WHERE f.following_id = ?"
  )
    .bind(userId)
    .all();
  return c.json({ users: results }, 200, corsHeaders());
});

app.get("/api/users/search", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const q = String(c.req.query("q") ?? "").trim();
  if (!q) return c.json({ users: [] }, 200, corsHeaders());
  try {
    const pattern = `%${q}%`;
    const { results } = await c.env.molian_db.prepare(
      "SELECT id, username, display_name, avatar_url FROM users WHERE (username LIKE ? OR display_name LIKE ?) AND id != ? LIMIT 30"
    )
      .bind(pattern, pattern, userId)
      .all();
    return c.json({ users: results }, 200, corsHeaders());
  } catch (e) {
    console.error("users/search error:", e);
    return c.json({ error: "搜索失败，请稍后重试" }, 500, corsHeaders());
  }
});

app.get("/api/users/me/friends", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  try {
    const { results } = await c.env.molian_db.prepare(
      `SELECT u.id, u.username, u.display_name, u.avatar_url
       FROM friend_requests fr
       JOIN users u ON u.id = CASE WHEN fr.requester_id = ? THEN fr.target_id ELSE fr.requester_id END
       WHERE (fr.requester_id = ? OR fr.target_id = ?) AND fr.status = 'accepted'`
    )
      .bind(userId, userId, userId)
      .all();
    return c.json({ friends: results }, 200, corsHeaders());
  } catch (e) {
    console.error("users/me/friends GET error:", e);
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table") || msg.includes("friend_requests")) return c.json({ error: "服务未就绪" }, 503, corsHeaders());
    return c.json({ error: "获取失败" }, 500, corsHeaders());
  }
});

app.delete("/api/users/me/friends/:id", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const friendId = c.req.param("id");
  try {
    const result = await c.env.molian_db.prepare(
      "UPDATE friend_requests SET status = 'removed' WHERE ((requester_id = ? AND target_id = ?) OR (requester_id = ? AND target_id = ?)) AND status = 'accepted'"
    )
      .bind(userId, friendId, friendId, userId)
      .run();
    const rowsWritten = (result as { meta?: { rows_written?: number } }).meta?.rows_written ?? 0;
    if (rowsWritten === 0) return c.json({ error: "不是好友或已删除" }, 404, corsHeaders());
    return c.json({}, 200, corsHeaders());
  } catch (e) {
    console.error("users/me/friends DELETE error:", e);
    return c.json({ error: "删除失败" }, 500, corsHeaders());
  }
});

// ----- Posts -----
app.get("/api/posts", async (c) => {
  const env = c.env;
  const secret = getSecret(env);
  const limit = Math.min(Number(c.req.query("limit")) || 20, 100);
  const cursor = c.req.query("cursor") ?? "";
  const userId = await getUserIdFromRequest(c);
  let results: Record<string, unknown>[];
  if (cursor) {
    const cursorRow = await env.molian_db.prepare("SELECT created_at FROM posts WHERE id = ?").bind(cursor).first();
    const cursorCreated = cursorRow && typeof cursorRow === "object" ? (cursorRow as Record<string, unknown>).created_at : null;
    if (cursorCreated) {
      const s = await env.molian_db.prepare(
        "SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id WHERE p.created_at < ? ORDER BY p.created_at DESC LIMIT ?"
      )
        .bind(cursorCreated, limit)
        .all();
      results = s.results as Record<string, unknown>[];
    } else {
      const s = await env.molian_db.prepare(
        "SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id ORDER BY p.created_at DESC LIMIT ?"
      )
        .bind(limit)
        .all();
      results = s.results as Record<string, unknown>[];
    }
  } else {
    const s = await env.molian_db.prepare(
      "SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id ORDER BY p.created_at DESC LIMIT ?"
    )
      .bind(limit)
      .all();
    results = s.results as Record<string, unknown>[];
  }
  const posts = await Promise.all(
    results.map(async (r) => {
      const postId = r.id as string;
      const likeCount = (await env.molian_db.prepare("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?").bind(postId).first()) as { c: number };
      let liked = false;
      if (userId) {
        const l = await env.molian_db.prepare("SELECT 1 FROM post_likes WHERE post_id = ? AND user_id = ?").bind(postId, userId).first();
        liked = !!l;
      }
      const commentCount = (await env.molian_db.prepare("SELECT COUNT(*) as c FROM comments WHERE post_id = ?").bind(postId).first()) as { c: number };
      return {
        id: r.id,
        user_id: r.user_id,
        content: r.content,
        image_urls: r.image_urls,
        created_at: r.created_at,
        updated_at: r.updated_at,
        like_count: likeCount?.c ?? 0,
        liked,
        comment_count: commentCount?.c ?? 0,
        user: { username: r.username, display_name: r.display_name, avatar_url: r.avatar_url },
      };
    })
  );
  const nextCursor = posts.length === limit && posts.length > 0 ? (posts[posts.length - 1] as { id?: unknown }).id : null;
  return c.json({ posts, nextCursor }, 200, corsHeaders());
});

app.post("/api/posts", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  try {
    const body = (await c.req.json()) as { content?: string; image_urls?: string[] };
    const content = String(body?.content ?? "").trim();
    if (!content) return c.json({ error: "内容不能为空" }, 400, corsHeaders());
    const imageUrls = Array.isArray(body?.image_urls) ? (body.image_urls as string[]) : [];
    const imageUrlsJson = JSON.stringify(imageUrls);
    const id = uuid();
    await c.env.molian_db.prepare(
      "INSERT INTO posts (id, user_id, content, image_urls, created_at, updated_at) VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))"
    )
      .bind(id, userId, content, imageUrlsJson)
      .run();
    const row = await c.env.molian_db.prepare(
      "SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id WHERE p.id = ?"
    )
      .bind(id)
      .first();
    return c.json({ post: row }, 200, corsHeaders());
  } catch {
    return c.json({ error: "发布失败" }, 500, corsHeaders());
  }
});

app.get("/api/posts/:id", async (c) => {
  const id = c.req.param("id");
  const row = await c.env.molian_db.prepare(
    "SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id WHERE p.id = ?"
  )
    .bind(id)
    .first();
  if (!row || typeof row !== "object") return c.json({ error: "帖子不存在" }, 404, corsHeaders());
  const r = row as Record<string, unknown>;
  return c.json(
    {
      post: {
        id: r.id,
        user_id: r.user_id,
        content: r.content,
        image_urls: r.image_urls,
        created_at: r.created_at,
        updated_at: r.updated_at,
        user: { username: r.username, display_name: r.display_name, avatar_url: r.avatar_url },
      },
    },
    200,
    corsHeaders()
  );
});

app.delete("/api/posts/:id", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const id = c.req.param("id");
  const row = (await c.env.molian_db.prepare("SELECT user_id FROM posts WHERE id = ?").bind(id).first()) as { user_id: string } | null;
  if (!row) return c.json({ error: "帖子不存在" }, 404, corsHeaders());
  if (row.user_id !== userId) return c.json({ error: "只能删除自己的帖子" }, 403, corsHeaders());
  await c.env.molian_db.prepare("DELETE FROM post_likes WHERE post_id = ?").bind(id).run();
  await c.env.molian_db.prepare("DELETE FROM comments WHERE post_id = ?").bind(id).run();
  await c.env.molian_db.prepare("DELETE FROM posts WHERE id = ?").bind(id).run();
  return c.json({ deleted: true }, 200, corsHeaders());
});

app.post("/api/posts/:id/like", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const postId = c.req.param("id");
  await c.env.molian_db.prepare("INSERT OR IGNORE INTO post_likes (post_id, user_id) VALUES (?, ?)").bind(postId, userId).run();
  const count = (await c.env.molian_db.prepare("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?").bind(postId).first()) as { c: number };
  return c.json({ liked: true, count: count?.c ?? 0 }, 200, corsHeaders());
});

app.delete("/api/posts/:id/like", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const postId = c.req.param("id");
  await c.env.molian_db.prepare("DELETE FROM post_likes WHERE post_id = ? AND user_id = ?").bind(postId, userId).run();
  const count = (await c.env.molian_db.prepare("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?").bind(postId).first()) as { c: number };
  return c.json({ liked: false, count: count?.c ?? 0 }, 200, corsHeaders());
});

app.get("/api/posts/:id/likes", async (c) => {
  const userId = await getUserIdFromRequest(c);
  const postId = c.req.param("id");
  const count = (await c.env.molian_db.prepare("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?").bind(postId).first()) as { c: number };
  const liked = userId
    ? await c.env.molian_db.prepare("SELECT 1 FROM post_likes WHERE post_id = ? AND user_id = ?").bind(postId, userId).first()
    : null;
  return c.json({ count: count?.c ?? 0, liked: !!liked }, 200, corsHeaders());
});

app.get("/api/posts/:id/comments", async (c) => {
  const postId = c.req.param("id");
  const limit = Math.min(Number(c.req.query("limit")) || 20, 100);
  const { results } = await c.env.molian_db.prepare(
    "SELECT c.id, c.post_id, c.user_id, c.content, c.created_at, u.username, u.display_name, u.avatar_url FROM comments c JOIN users u ON c.user_id = u.id WHERE c.post_id = ? ORDER BY c.created_at ASC LIMIT ?"
  )
    .bind(postId, limit)
    .all();
  const comments = (results as Record<string, unknown>[]).map((r) => ({
    id: r.id,
    post_id: r.post_id,
    user_id: r.user_id,
    content: r.content,
    created_at: r.created_at,
    user: { username: r.username, display_name: r.display_name, avatar_url: r.avatar_url },
  }));
  return c.json({ comments }, 200, corsHeaders());
});

app.post("/api/posts/:id/comments", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const postId = c.req.param("id");
  const body = (await c.req.json()) as { content?: string };
  const content = String(body?.content ?? "").trim();
  if (!content) return c.json({ error: "内容不能为空" }, 400, corsHeaders());
  const id = uuid();
  await c.env.molian_db.prepare("INSERT INTO comments (id, post_id, user_id, content) VALUES (?, ?, ?, ?)").bind(id, postId, userId, content).run();
  const row = (await c.env.molian_db.prepare(
    "SELECT c.id, c.post_id, c.user_id, c.content, c.created_at, u.username, u.display_name, u.avatar_url FROM comments c JOIN users u ON c.user_id = u.id WHERE c.id = ?"
  )
    .bind(id)
    .first()) as Record<string, unknown> | null;
  const comment = row
    ? {
        id: row.id,
        post_id: row.post_id,
        user_id: row.user_id,
        content: row.content,
        created_at: row.created_at,
        user: { username: row.username, display_name: row.display_name, avatar_url: row.avatar_url },
      }
    : null;
  return c.json({ comment }, 200, corsHeaders());
});

// ----- Follows -----
app.post("/api/follows", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const body = (await c.req.json()) as { following_id?: string };
  const followingId = String(body?.following_id ?? "").trim();
  if (!followingId || followingId === userId) return c.json({ error: "无效的 following_id" }, 400, corsHeaders());
  await c.env.molian_db.prepare("INSERT OR IGNORE INTO follows (follower_id, following_id) VALUES (?, ?)").bind(userId, followingId).run();
  return c.json({ followed: true }, 200, corsHeaders());
});

app.delete("/api/follows/:id", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const followingId = c.req.param("id");
  await c.env.molian_db.prepare("DELETE FROM follows WHERE follower_id = ? AND following_id = ?").bind(userId, followingId).run();
  return c.json({ followed: false }, 200, corsHeaders());
});

// ----- Friend requests -----
app.get("/api/friend-requests", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  try {
    const { results } = await c.env.molian_db.prepare(
      "SELECT fr.id, fr.requester_id, fr.target_id, fr.status, fr.created_at, u.username, u.display_name, u.avatar_url FROM friend_requests fr JOIN users u ON fr.requester_id = u.id WHERE fr.target_id = ? AND fr.status = 'pending' ORDER BY fr.created_at DESC"
    )
      .bind(userId)
      .all();
    return c.json({ friend_requests: results }, 200, corsHeaders());
  } catch (e) {
    console.error("friend-requests GET error:", e);
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table") || msg.includes("friend_requests")) return c.json({ error: "服务未就绪" }, 503, corsHeaders());
    return c.json({ error: "获取失败" }, 500, corsHeaders());
  }
});

app.post("/api/friend-requests", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  try {
    const body = (await c.req.json()) as { target_id?: string };
    const targetId = String(body?.target_id ?? "").trim();
    if (!targetId || targetId === userId) return c.json({ error: "无效的 target_id" }, 400, corsHeaders());
    const existing = await c.env.molian_db.prepare(
      "SELECT id, status FROM friend_requests WHERE requester_id = ? AND target_id = ?"
    )
      .bind(userId, targetId)
      .first();
    if (existing && typeof existing === "object") {
      const status = (existing as { status: string }).status;
      if (status === "pending") return c.json({ error: "已发送过好友申请" }, 409, corsHeaders());
      if (status === "accepted") return c.json({ error: "已是好友" }, 409, corsHeaders());
    }
    const id = uuid();
    await c.env.molian_db.prepare("INSERT INTO friend_requests (id, requester_id, target_id, status) VALUES (?, ?, ?, 'pending')").bind(id, userId, targetId).run();
    const row = await c.env.molian_db.prepare("SELECT id, requester_id, target_id, status, created_at FROM friend_requests WHERE id = ?").bind(id).first();
    return c.json({ friend_request: row }, 201, corsHeaders());
  } catch (e) {
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    console.error("friend-requests POST error:", msg);
    if (msg.includes("no such table") || msg.includes("friend_requests"))
      return c.json({ error: "服务未就绪，请先执行数据库迁移：wrangler d1 migrations apply molian-db --remote" }, 503, corsHeaders());
    return c.json({ error: "发送失败，请稍后重试" }, 500, corsHeaders());
  }
});

app.post("/api/friend-requests/:id/accept", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const requestId = c.req.param("id");
  try {
    const row = await c.env.molian_db.prepare(
      "SELECT id, requester_id, target_id, status FROM friend_requests WHERE id = ? AND target_id = ? AND status = 'pending'"
    )
      .bind(requestId, userId)
      .first();
    if (!row || typeof row !== "object") return c.json({ error: "申请不存在或已处理" }, 404, corsHeaders());
    const r = row as { requester_id: string; target_id: string };
    await c.env.molian_db.prepare("UPDATE friend_requests SET status = 'accepted' WHERE id = ?").bind(requestId).run();
    await c.env.molian_db.prepare("INSERT OR IGNORE INTO follows (follower_id, following_id) VALUES (?, ?)").bind(r.requester_id, r.target_id).run();
    await c.env.molian_db.prepare("INSERT OR IGNORE INTO follows (follower_id, following_id) VALUES (?, ?)").bind(r.target_id, r.requester_id).run();
    return c.json({ accepted: true }, 200, corsHeaders());
  } catch (e) {
    console.error("friend-requests accept error:", e);
    return c.json({ error: "操作失败" }, 500, corsHeaders());
  }
});

app.post("/api/friend-requests/:id/reject", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const requestId = c.req.param("id");
  try {
    const row = await c.env.molian_db.prepare(
      "SELECT id FROM friend_requests WHERE id = ? AND target_id = ? AND status = 'pending'"
    )
      .bind(requestId, userId)
      .first();
    if (!row || typeof row !== "object") return c.json({ error: "申请不存在或已处理" }, 404, corsHeaders());
    await c.env.molian_db.prepare("UPDATE friend_requests SET status = 'rejected' WHERE id = ?").bind(requestId).run();
    return c.json({ rejected: true }, 200, corsHeaders());
  } catch (e) {
    console.error("friend-requests reject error:", e);
    return c.json({ error: "操作失败" }, 500, corsHeaders());
  }
});

// ----- Messages -----
app.get("/api/messages", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const withUser = c.req.query("with_user") ?? "";
  const limit = Math.min(Number(c.req.query("limit")) || 50, 100);
  const cursor = c.req.query("cursor") ?? "";
  if (withUser) {
    const sql = cursor
      ? "SELECT id, sender_id, receiver_id, content, created_at, read FROM messages WHERE ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)) AND created_at < ? ORDER BY created_at DESC LIMIT ?"
      : "SELECT id, sender_id, receiver_id, content, created_at, read FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) ORDER BY created_at DESC LIMIT ?";
    const bind = cursor ? [userId, withUser, withUser, userId, cursor, limit] : [userId, withUser, withUser, userId, limit];
    const { results } = await c.env.molian_db.prepare(sql).bind(userId, withUser, withUser, userId, ...(cursor ? [cursor, limit] : [limit])).all();
    return c.json({ messages: results }, 200, corsHeaders());
  }
  const { results: convList } = await c.env.molian_db.prepare(
    "SELECT DISTINCT CASE WHEN sender_id = ? THEN receiver_id ELSE sender_id END as peer_id FROM messages WHERE sender_id = ? OR receiver_id = ?"
  )
    .bind(userId, userId, userId)
    .all();
  const withLast = await Promise.all(
    (convList as { peer_id: string }[]).map(async (row) => {
      const peerId = row.peer_id;
      const [last, unread, peerRow] = await Promise.all([
        c.env.molian_db.prepare(
          "SELECT content, created_at FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) ORDER BY created_at DESC LIMIT 1"
        )
          .bind(userId, peerId, peerId, userId)
          .first(),
        c.env.molian_db.prepare("SELECT COUNT(*) as c FROM messages WHERE receiver_id = ? AND sender_id = ? AND read = 0")
          .bind(userId, peerId)
          .first(),
        c.env.molian_db.prepare("SELECT username, display_name FROM users WHERE id = ?").bind(peerId).first(),
      ]);
      const unreadCount = (unread as { c: number })?.c ?? 0;
      const peer = peerRow as { username?: string; display_name?: string } | null;
      return {
        peer_id: peerId,
        peer_username: peer?.username ?? null,
        peer_display_name: peer?.display_name ?? null,
        last_content: (last as Record<string, unknown>)?.content,
        last_at: (last as Record<string, unknown>)?.created_at,
        unread_count: unreadCount,
      };
    })
  );
  return c.json({ conversations: withLast }, 200, corsHeaders());
});

app.post("/api/messages/mark-read", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const body = (await c.req.json()) as { with_user?: string };
  const withUser = String(body?.with_user ?? "").trim();
  if (!withUser) return c.json({ error: "with_user 必填" }, 400, corsHeaders());
  try {
    await c.env.molian_db.prepare("UPDATE messages SET read = 1 WHERE receiver_id = ? AND sender_id = ? AND read = 0")
      .bind(userId, withUser)
      .run();
    return c.json({ marked: true }, 200, corsHeaders());
  } catch (e) {
    console.error("messages/mark-read error:", e);
    return c.json({ error: "操作失败" }, 500, corsHeaders());
  }
});

app.post("/api/messages", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const body = (await c.req.json()) as { receiver_id?: string; content?: string };
  const receiverId = String(body?.receiver_id ?? "").trim();
  const content = String(body?.content ?? "").trim();
  if (!receiverId || !content) return c.json({ error: "receiver_id 和 content 必填" }, 400, corsHeaders());
  const id = uuid();
  await c.env.molian_db.prepare("INSERT INTO messages (id, sender_id, receiver_id, content, read) VALUES (?, ?, ?, ?, 0)").bind(id, userId, receiverId, content).run();
  const row = await c.env.molian_db.prepare("SELECT id, sender_id, receiver_id, content, created_at, read FROM messages WHERE id = ?").bind(id).first();
  return c.json({ message: row }, 200, corsHeaders());
});

// ----- Upload & asset -----
app.post("/api/upload", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const contentType = c.req.header("Content-Type") ?? "";
  if (!contentType.includes("multipart/form-data")) return c.json({ error: "需要 multipart/form-data" }, 400, corsHeaders());
  try {
    const formData = await c.req.formData();
    const file = formData.get("file") as File | null;
    if (!file) return c.json({ error: "缺少 file 字段" }, 400, corsHeaders());
    const ext = (file.name.split(".").pop() || "bin").slice(0, 4);
    const key = `assets/${userId}/${uuid()}.${ext}`;
    await c.env.ASSETS.put(key, file.stream(), { httpMetadata: { contentType: file.type || "application/octet-stream" } });
    const base = new URL(c.req.url).origin;
    return c.json({ url: `${base}/api/asset/${encodeURIComponent(key)}` }, 200, corsHeaders());
  } catch {
    return c.json({ error: "上传失败" }, 500, corsHeaders());
  }
});

app.get("/api/asset/:key(*)", async (c) => {
  const key = decodeURIComponent(c.req.param("key"));
  const obj = await c.env.ASSETS.get(key);
  if (!obj) return new Response("Not Found", { status: 404, headers: corsHeaders() });
  const headers = new Headers(corsHeaders());
  if (obj.httpMetadata?.contentType) headers.set("Content-Type", obj.httpMetadata.contentType);
  return new Response(obj.body, { status: 200, headers });
});

// ----- Notifications -----
// 推送发送：可在此处或 Cron 中调 FCM HTTP v1 API（需服务端密钥），从 push_subscriptions 表取 fcm_token 下发。
app.get("/api/notifications", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const limit = Math.min(Number(c.req.query("limit")) || 20, 100);
  const cursor = c.req.query("cursor") ?? "";
  try {
    const sql = cursor
      ? "SELECT id, user_id, type, title, body, data, read, created_at FROM notifications WHERE user_id = ? AND created_at < ? ORDER BY created_at DESC LIMIT ?"
      : "SELECT id, user_id, type, title, body, data, read, created_at FROM notifications WHERE user_id = ? ORDER BY created_at DESC LIMIT ?";
    const bind = cursor ? [userId, cursor, limit] : [userId, limit];
    const { results } = await c.env.molian_db.prepare(sql).bind(...bind).all();
    const nextCursor =
      results.length === limit && results.length > 0 ? (results[results.length - 1] as Record<string, unknown>).created_at : null;
    return c.json({ notifications: results, nextCursor }, 200, corsHeaders());
  } catch (e) {
    console.error("notifications GET error:", e);
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table")) return c.json({ error: "服务未就绪" }, 503, corsHeaders());
    return c.json({ error: "获取失败" }, 500, corsHeaders());
  }
});

app.post("/api/notifications/read", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const body = (await c.req.json()) as { id?: string; ids?: string[] };
  const id = body?.id;
  const ids = body?.ids as string[] | undefined;
  try {
    if (id) {
      await c.env.molian_db.prepare("UPDATE notifications SET read = 1 WHERE id = ? AND user_id = ?").bind(id, userId).run();
    } else if (ids && Array.isArray(ids) && ids.length > 0) {
      const placeholders = ids.map(() => "?").join(",");
      await c.env.molian_db.prepare(`UPDATE notifications SET read = 1 WHERE id IN (${placeholders}) AND user_id = ?`).bind(...ids, userId).run();
    } else {
      await c.env.molian_db.prepare("UPDATE notifications SET read = 1 WHERE user_id = ?").bind(userId).run();
    }
    return c.json({ ok: true }, 200, corsHeaders());
  } catch (e) {
    console.error("notifications read error:", e);
    return c.json({ error: "操作失败" }, 500, corsHeaders());
  }
});

app.post("/api/notifications/subscribe", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const body = (await c.req.json()) as { fcm_token?: string };
  const fcmToken = String(body?.fcm_token ?? "").trim();
  if (!fcmToken) return c.json({ error: "fcm_token 必填" }, 400, corsHeaders());
  try {
    const id = uuid();
    await c.env.molian_db.prepare(
      "INSERT INTO push_subscriptions (id, user_id, fcm_token) VALUES (?, ?, ?) ON CONFLICT(user_id, fcm_token) DO UPDATE SET fcm_token = excluded.fcm_token"
    ).bind(id, userId, fcmToken).run();
    return c.json({ subscribed: true }, 200, corsHeaders());
  } catch (e) {
    console.error("notifications subscribe error:", e);
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table")) return c.json({ error: "服务未就绪" }, 503, corsHeaders());
    return c.json({ error: "订阅失败" }, 500, corsHeaders());
  }
});

// ----- Feeds（发现流，暂与帖子列表一致）-----
app.get("/api/feeds", async (c) => {
  const env = c.env;
  const secret = getSecret(env);
  const limit = Math.min(Number(c.req.query("limit")) || 20, 100);
  const cursor = c.req.query("cursor") ?? "";
  const userId = await getUserIdFromRequest(c);
  let results: Record<string, unknown>[];
  if (cursor) {
    const cursorRow = await env.molian_db.prepare("SELECT created_at FROM posts WHERE id = ?").bind(cursor).first();
    const cursorCreated = cursorRow && typeof cursorRow === "object" ? (cursorRow as Record<string, unknown>).created_at : null;
    if (cursorCreated) {
      const s = await env.molian_db.prepare(
        "SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id WHERE p.created_at < ? ORDER BY p.created_at DESC LIMIT ?"
      )
        .bind(cursorCreated, limit)
        .all();
      results = s.results as Record<string, unknown>[];
    } else {
      const s = await env.molian_db.prepare(
        "SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id ORDER BY p.created_at DESC LIMIT ?"
      )
        .bind(limit)
        .all();
      results = s.results as Record<string, unknown>[];
    }
  } else {
    const s = await env.molian_db.prepare(
      "SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id ORDER BY p.created_at DESC LIMIT ?"
    )
      .bind(limit)
      .all();
    results = s.results as Record<string, unknown>[];
  }
  const posts = await Promise.all(
    results.map(async (r) => {
      const postId = r.id as string;
      const likeCount = (await env.molian_db.prepare("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?").bind(postId).first()) as { c: number };
      let liked = false;
      if (userId) {
        const l = await env.molian_db.prepare("SELECT 1 FROM post_likes WHERE post_id = ? AND user_id = ?").bind(postId, userId).first();
        liked = !!l;
      }
      const commentCount = (await env.molian_db.prepare("SELECT COUNT(*) as c FROM comments WHERE post_id = ?").bind(postId).first()) as { c: number };
      return {
        id: r.id,
        user_id: r.user_id,
        content: r.content,
        image_urls: r.image_urls,
        created_at: r.created_at,
        updated_at: r.updated_at,
        like_count: likeCount?.c ?? 0,
        liked,
        comment_count: commentCount?.c ?? 0,
        user: { username: r.username, display_name: r.display_name, avatar_url: r.avatar_url },
      };
    })
  );
  const nextCursor = posts.length === limit && posts.length > 0 ? (posts[posts.length - 1] as { id?: unknown }).id : null;
  return c.json({ posts, nextCursor }, 200, corsHeaders());
});

// ----- Realms -----
app.get("/api/realms", async (c) => {
  try {
    const { results } = await c.env.molian_db.prepare(
      "SELECT id, name, slug, description, avatar_url, created_at FROM realms ORDER BY created_at DESC LIMIT 50"
    ).all();
    return c.json({ realms: results }, 200, corsHeaders());
  } catch (e) {
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table")) return c.json({ realms: [] }, 200, corsHeaders());
    return c.json({ error: "获取失败" }, 500, corsHeaders());
  }
});

app.get("/api/realms/:id", async (c) => {
  const id = c.req.param("id");
  const row = await c.env.molian_db.prepare(
    "SELECT id, name, slug, description, avatar_url, created_at FROM realms WHERE id = ? OR slug = ?"
  )
    .bind(id, id)
    .first();
  if (!row || typeof row !== "object") return c.json({ error: "圈子不存在" }, 404, corsHeaders());
  return c.json({ realm: row }, 200, corsHeaders());
});

app.post("/api/realms/:id/join", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const realmId = c.req.param("id");
  try {
    await c.env.molian_db.prepare(
      "INSERT OR IGNORE INTO realm_members (realm_id, user_id, role) VALUES (?, ?, 'member')"
    ).bind(realmId, userId).run();
    return c.json({ joined: true }, 200, corsHeaders());
  } catch (e) {
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table")) return c.json({ error: "服务未就绪" }, 503, corsHeaders());
    return c.json({ error: "加入失败" }, 500, corsHeaders());
  }
});

app.post("/api/realms/:id/leave", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const realmId = c.req.param("id");
  try {
    await c.env.molian_db.prepare("DELETE FROM realm_members WHERE realm_id = ? AND user_id = ?").bind(realmId, userId).run();
    return c.json({ left: true }, 200, corsHeaders());
  } catch (e) {
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table")) return c.json({ error: "服务未就绪" }, 503, corsHeaders());
    return c.json({ error: "退出失败" }, 500, corsHeaders());
  }
});

// ----- Files -----
app.get("/api/files", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  try {
    const { results } = await c.env.molian_db.prepare(
      "SELECT id, user_id, key, name, size, mime_type, created_at FROM files WHERE user_id = ? ORDER BY created_at DESC LIMIT 100"
    )
      .bind(userId)
      .all();
    return c.json({ files: results }, 200, corsHeaders());
  } catch (e) {
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table")) return c.json({ files: [] }, 200, corsHeaders());
    return c.json({ error: "获取失败" }, 500, corsHeaders());
  }
});

app.post("/api/files/confirm", async (c) => {
  const userId = await getUserIdFromRequest(c);
  if (!userId) return c.json({ error: "未登录" }, 401, corsHeaders());
  const body = (await c.req.json()) as { key?: string; name?: string; size?: number; mime_type?: string };
  const key = String(body?.key ?? "").trim();
  const name = String(body?.name ?? "").trim();
  if (!key) return c.json({ error: "key 必填" }, 400, corsHeaders());
  const id = uuid();
  const size = Number(body?.size) || 0;
  const mimeType = (body?.mime_type as string) ?? null;
  const displayName = name || key.split("/").pop() || key;
  try {
    await c.env.molian_db.prepare(
      "INSERT INTO files (id, user_id, key, name, size, mime_type) VALUES (?, ?, ?, ?, ?, ?)"
    )
      .bind(id, userId, key, displayName, size, mimeType)
      .run();
    const row = await c.env.molian_db.prepare(
      "SELECT id, user_id, key, name, size, mime_type, created_at FROM files WHERE id = ?"
    )
      .bind(id)
      .first();
    return c.json({ file: row }, 201, corsHeaders());
  } catch (e) {
    const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
    if (msg.includes("no such table")) return c.json({ error: "服务未就绪" }, 503, corsHeaders());
    return c.json({ error: "登记失败" }, 500, corsHeaders());
  }
});

app.all("*", (c) => c.json({ error: "Not Found" }, 404, corsHeaders()));

export default app;
