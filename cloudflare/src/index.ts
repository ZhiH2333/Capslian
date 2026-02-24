/**
 * Capslian API Worker
 * REST：健康检查、认证（注册/登录/me）；WebSocket/DM 由 Durable Object 处理（V1 实现）。
 */

import { hashPassword, verifyPassword } from "./auth/password";
import { signJwt, verifyJwt } from "./auth/jwt";

export interface Env {
  capslian_db: D1Database;
  ASSETS: R2Bucket;
  CHAT: DurableObjectNamespace;
  JWT_SECRET: string;
}

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

function jsonResponse(body: object, status: number = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

function uuid(): string {
  return crypto.randomUUID();
}

async function getUserIdFromRequest(request: Request, secret: string): Promise<string | null> {
  const auth = request.headers.get("Authorization");
  const token = auth?.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) return null;
  const payload = await verifyJwt(token, secret);
  return payload ? payload.sub : null;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }
    const url = new URL(request.url);
    const pathname = url.pathname.replace(/\/$/, "") || "/";
    const secret = env.JWT_SECRET || "dev-secret-change-in-production";

    if (pathname === "/" || pathname === "/health") {
      return jsonResponse({ ok: true });
    }

    if (pathname === "/auth/register" && request.method === "POST") {
      try {
        const body = (await request.json()) as { username?: string; password?: string; displayName?: string };
        const username = String(body?.username ?? "").trim().toLowerCase();
        const password = String(body?.password ?? "");
        const displayName = (body?.displayName as string)?.trim() || username;
        if (!username || username.length < 2) return jsonResponse({ error: "用户名至少 2 个字符" }, 400);
        if (!password || password.length < 6) return jsonResponse({ error: "密码至少 6 个字符" }, 400);
        const { hashHex, saltBase64 } = await hashPassword(password);
        const id = uuid();
        await env.capslian_db.prepare(
          "INSERT INTO users (id, username, password_hash, salt, display_name) VALUES (?, ?, ?, ?, ?)"
        )
          .bind(id, username, hashHex, saltBase64, displayName)
          .run();
        const token = await signJwt({ sub: id }, secret);
        const row = await env.capslian_db.prepare(
          "SELECT id, username, display_name, avatar_url, bio, created_at FROM users WHERE id = ?"
        )
          .bind(id)
          .first();
        return jsonResponse({ token, user: row });
      } catch (e: unknown) {
        const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
        console.error("Register error:", msg);
        if (msg.includes("UNIQUE") || msg.includes("unique")) return jsonResponse({ error: "用户名已存在" }, 409);
        return jsonResponse({ error: "注册失败: " + msg }, 500);
      }
    }

    if (pathname === "/auth/login" && request.method === "POST") {
      try {
        const body = (await request.json()) as { username?: string; password?: string };
        const username = String(body?.username ?? "").trim().toLowerCase();
        const password = String(body?.password ?? "");
        if (!username || !password) return jsonResponse({ error: "用户名和密码必填" }, 400);
        const row = await env.capslian_db.prepare(
          "SELECT id, username, password_hash, salt, display_name, avatar_url, bio, created_at FROM users WHERE username = ?"
        )
          .bind(username)
          .first();
        if (!row || typeof row !== "object") return jsonResponse({ error: "用户名或密码错误" }, 401);
        const r = row as Record<string, unknown>;
        const ok = await verifyPassword(
          password,
          String(r.salt),
          String(r.password_hash)
        );
        if (!ok) return jsonResponse({ error: "用户名或密码错误" }, 401);
        const token = await signJwt({ sub: String(r.id) }, secret);
        const user = {
          id: r.id,
          username: r.username,
          display_name: r.display_name,
          avatar_url: r.avatar_url,
          bio: r.bio,
          created_at: r.created_at,
        };
        return jsonResponse({ token, user });
      } catch {
        return jsonResponse({ error: "登录失败" }, 500);
      }
    }

    if (pathname === "/auth/me" && request.method === "GET") {
      const userId = await getUserIdFromRequest(request, secret);
      if (!userId) return jsonResponse({ error: "未登录" }, 401);
      const row = await env.capslian_db.prepare(
        "SELECT id, username, display_name, avatar_url, bio, created_at FROM users WHERE id = ?"
      )
        .bind(userId)
        .first();
      if (!row || typeof row !== "object") return jsonResponse({ error: "用户不存在" }, 404);
      return jsonResponse({ user: row });
    }

    if (pathname === "/users/me" && request.method === "PATCH") {
      const userId = await getUserIdFromRequest(request, secret);
      if (!userId) return jsonResponse({ error: "未登录" }, 401);
      try {
        const body = (await request.json()) as { display_name?: string; bio?: string; avatar_url?: string };
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
        if (updates.length === 0) return jsonResponse({ error: "无有效字段" }, 400);
        values.push(userId);
        await env.capslian_db.prepare(`UPDATE users SET ${updates.join(", ")} WHERE id = ?`).bind(...values).run();
        const row = await env.capslian_db.prepare(
          "SELECT id, username, display_name, avatar_url, bio, created_at FROM users WHERE id = ?"
        )
          .bind(userId)
          .first();
        return jsonResponse({ user: row });
      } catch {
        return jsonResponse({ error: "更新失败" }, 500);
      }
    }

    if (pathname === "/posts" && request.method === "GET") {
      const limit = Math.min(Number(url.searchParams.get("limit")) || 20, 100);
      const cursor = url.searchParams.get("cursor") ?? "";
      const userId = await getUserIdFromRequest(request, secret);
      let results: Record<string, unknown>[];
      if (cursor) {
        const cursorRow = await env.capslian_db.prepare("SELECT created_at FROM posts WHERE id = ?").bind(cursor).first();
        const cursorCreated = cursorRow && typeof cursorRow === "object" ? (cursorRow as Record<string, unknown>).created_at : null;
        if (cursorCreated) {
          const s = await env.capslian_db.prepare("SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id WHERE p.created_at < ? ORDER BY p.created_at DESC LIMIT ?").bind(cursorCreated, limit).all();
          results = s.results as Record<string, unknown>[];
        } else {
          const s = await env.capslian_db.prepare("SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id ORDER BY p.created_at DESC LIMIT ?").bind(limit).all();
          results = s.results as Record<string, unknown>[];
        }
      } else {
        const s = await env.capslian_db.prepare("SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id ORDER BY p.created_at DESC LIMIT ?").bind(limit).all();
        results = s.results as Record<string, unknown>[];
      }
      const posts = await Promise.all(
        results.map(async (r) => {
          const postId = r.id as string;
          const likeCount = (await env.capslian_db.prepare("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?").bind(postId).first()) as { c: number };
          let liked = false;
          if (userId) {
            const l = await env.capslian_db.prepare("SELECT 1 FROM post_likes WHERE post_id = ? AND user_id = ?").bind(postId, userId).first();
            liked = !!l;
          }
          const commentCount = (await env.capslian_db.prepare("SELECT COUNT(*) as c FROM comments WHERE post_id = ?").bind(postId).first()) as { c: number };
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
      return jsonResponse({ posts, nextCursor });
    }

    if (pathname === "/posts" && request.method === "POST") {
      const userId = await getUserIdFromRequest(request, secret);
      if (!userId) return jsonResponse({ error: "未登录" }, 401);
      try {
        const body = (await request.json()) as { content?: string; image_urls?: string[] };
        const content = String(body?.content ?? "").trim();
        if (!content) return jsonResponse({ error: "内容不能为空" }, 400);
        const imageUrls = Array.isArray(body?.image_urls) ? (body.image_urls as string[]) : [];
        const imageUrlsJson = JSON.stringify(imageUrls);
        const id = uuid();
        await env.capslian_db.prepare(
          "INSERT INTO posts (id, user_id, content, image_urls, created_at, updated_at) VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))"
        )
          .bind(id, userId, content, imageUrlsJson)
          .run();
        const row = await env.capslian_db.prepare(
          "SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id WHERE p.id = ?"
        )
          .bind(id)
          .first();
        return jsonResponse({ post: row });
      } catch {
        return jsonResponse({ error: "发布失败" }, 500);
      }
    }

    const postIdMatch = pathname.match(/^\/posts\/([^/]+)$/);
    if (postIdMatch) {
      const id = postIdMatch[1];
      if (request.method === "GET") {
        const row = await env.capslian_db.prepare(
          "SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id WHERE p.id = ?"
        )
          .bind(id)
          .first();
        if (!row || typeof row !== "object") return jsonResponse({ error: "帖子不存在" }, 404);
        const r = row as Record<string, unknown>;
        return jsonResponse({
          post: {
            id: r.id,
            user_id: r.user_id,
            content: r.content,
            image_urls: r.image_urls,
            created_at: r.created_at,
            updated_at: r.updated_at,
            user: { username: r.username, display_name: r.display_name, avatar_url: r.avatar_url },
          },
        });
      }
      if (request.method === "DELETE") {
        const userId = await getUserIdFromRequest(request, secret);
        if (!userId) return jsonResponse({ error: "未登录" }, 401);
        const row = await env.capslian_db.prepare("SELECT user_id FROM posts WHERE id = ?").bind(id).first() as { user_id: string } | null;
        if (!row) return jsonResponse({ error: "帖子不存在" }, 404);
        if (row.user_id !== userId) return jsonResponse({ error: "只能删除自己的帖子" }, 403);
        await env.capslian_db.prepare("DELETE FROM post_likes WHERE post_id = ?").bind(id).run();
        await env.capslian_db.prepare("DELETE FROM comments WHERE post_id = ?").bind(id).run();
        await env.capslian_db.prepare("DELETE FROM posts WHERE id = ?").bind(id).run();
        return jsonResponse({ deleted: true });
      }
    }

    if (pathname === "/upload" && request.method === "POST") {
      const userId = await getUserIdFromRequest(request, secret);
      if (!userId) return jsonResponse({ error: "未登录" }, 401);
      const contentType = request.headers.get("Content-Type") ?? "";
      if (!contentType.includes("multipart/form-data")) return jsonResponse({ error: "需要 multipart/form-data" }, 400);
      try {
        const formData = await request.formData();
        const file = formData.get("file") as unknown as File | null;
        if (!file) return jsonResponse({ error: "缺少 file 字段" }, 400);
        const ext = (file.name.split(".").pop() || "bin").slice(0, 4);
        const key = `assets/${userId}/${uuid()}.${ext}`;
        await env.ASSETS.put(key, file.stream(), { httpMetadata: { contentType: file.type || "application/octet-stream" } });
        const base = new URL(request.url).origin;
        return jsonResponse({ url: `${base}/asset/${encodeURIComponent(key)}` });
      } catch {
        return jsonResponse({ error: "上传失败" }, 500);
      }
    }

    const likePostMatch = pathname.match(/^\/posts\/([^/]+)\/like$/);
    if (likePostMatch) {
      const postId = likePostMatch[1];
      const userId = await getUserIdFromRequest(request, secret);
      if (!userId) return jsonResponse({ error: "未登录" }, 401);
      if (request.method === "POST") {
        await env.capslian_db.prepare("INSERT OR IGNORE INTO post_likes (post_id, user_id) VALUES (?, ?)").bind(postId, userId).run();
        const count = (await env.capslian_db.prepare("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?").bind(postId).first()) as { c: number };
        return jsonResponse({ liked: true, count: count?.c ?? 0 });
      }
      if (request.method === "DELETE") {
        await env.capslian_db.prepare("DELETE FROM post_likes WHERE post_id = ? AND user_id = ?").bind(postId, userId).run();
        const count = (await env.capslian_db.prepare("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?").bind(postId).first()) as { c: number };
        return jsonResponse({ liked: false, count: count?.c ?? 0 });
      }
    }

    const postLikesMatch = pathname.match(/^\/posts\/([^/]+)\/likes$/);
    if (postLikesMatch && request.method === "GET") {
      const postId = postLikesMatch[1];
      const userId = await getUserIdFromRequest(request, secret);
      const count = (await env.capslian_db.prepare("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?").bind(postId).first()) as { c: number };
      const liked = userId ? (await env.capslian_db.prepare("SELECT 1 FROM post_likes WHERE post_id = ? AND user_id = ?").bind(postId, userId).first()) : null;
      return jsonResponse({ count: count?.c ?? 0, liked: !!liked });
    }

    const commentsPostMatch = pathname.match(/^\/posts\/([^/]+)\/comments$/);
    if (commentsPostMatch) {
      const postId = commentsPostMatch[1];
      if (request.method === "GET") {
        const limit = Math.min(Number(url.searchParams.get("limit")) || 20, 100);
        const { results } = await env.capslian_db.prepare(
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
        return jsonResponse({ comments });
      }
      if (request.method === "POST") {
        const uid = await getUserIdFromRequest(request, secret);
        if (!uid) return jsonResponse({ error: "未登录" }, 401);
        const body = (await request.json()) as { content?: string };
        const content = String(body?.content ?? "").trim();
        if (!content) return jsonResponse({ error: "内容不能为空" }, 400);
        const id = uuid();
        await env.capslian_db.prepare("INSERT INTO comments (id, post_id, user_id, content) VALUES (?, ?, ?, ?)").bind(id, postId, uid, content).run();
        const row = await env.capslian_db.prepare(
          "SELECT c.id, c.post_id, c.user_id, c.content, c.created_at, u.username, u.display_name, u.avatar_url FROM comments c JOIN users u ON c.user_id = u.id WHERE c.id = ?"
        )
          .bind(id)
          .first() as Record<string, unknown> | null;
        const comment = row
          ? {
              id: row.id,
              post_id: row.post_id,
              user_id: row.user_id,
              content: row.content,
              created_at: row.created_at,
              user: {
                username: row.username,
                display_name: row.display_name,
                avatar_url: row.avatar_url,
              },
            }
          : null;
        return jsonResponse({ comment });
      }
    }

    if (pathname === "/follows" && request.method === "POST") {
      const userId = await getUserIdFromRequest(request, secret);
      if (!userId) return jsonResponse({ error: "未登录" }, 401);
      const body = (await request.json()) as { following_id?: string };
      const followingId = String(body?.following_id ?? "").trim();
      if (!followingId || followingId === userId) return jsonResponse({ error: "无效的 following_id" }, 400);
      await env.capslian_db.prepare("INSERT OR IGNORE INTO follows (follower_id, following_id) VALUES (?, ?)").bind(userId, followingId).run();
      return jsonResponse({ followed: true });
    }

    const unfollowMatch = pathname.match(/^\/follows\/([^/]+)$/);
    if (unfollowMatch && request.method === "DELETE") {
      const followingId = unfollowMatch[1];
      const userId = await getUserIdFromRequest(request, secret);
      if (!userId) return jsonResponse({ error: "未登录" }, 401);
      await env.capslian_db.prepare("DELETE FROM follows WHERE follower_id = ? AND following_id = ?").bind(userId, followingId).run();
      return jsonResponse({ followed: false });
    }

    if (pathname === "/users/me/following" && request.method === "GET") {
      const userId = await getUserIdFromRequest(request, secret);
      if (!userId) return jsonResponse({ error: "未登录" }, 401);
      const { results } = await env.capslian_db.prepare(
        "SELECT u.id, u.username, u.display_name, u.avatar_url FROM users u INNER JOIN follows f ON f.following_id = u.id WHERE f.follower_id = ?"
      )
        .bind(userId)
        .all();
      return jsonResponse({ users: results });
    }

    if (pathname === "/users/me/followers" && request.method === "GET") {
      const userId = await getUserIdFromRequest(request, secret);
      if (!userId) return jsonResponse({ error: "未登录" }, 401);
      const { results } = await env.capslian_db.prepare(
        "SELECT u.id, u.username, u.display_name, u.avatar_url FROM users u INNER JOIN follows f ON f.follower_id = u.id WHERE f.following_id = ?"
      )
        .bind(userId)
        .all();
      return jsonResponse({ users: results });
    }

    if (pathname === "/users/search" && request.method === "GET") {
      const userId = await getUserIdFromRequest(request, secret);
      if (!userId) return jsonResponse({ error: "未登录" }, 401);
      const q = String(url.searchParams.get("q") ?? "").trim();
      if (!q) return jsonResponse({ users: [] });
      try {
        const pattern = `%${q}%`;
        const { results } = await env.capslian_db.prepare(
          "SELECT id, username, display_name, avatar_url FROM users WHERE (username LIKE ? OR display_name LIKE ?) AND id != ? LIMIT 30"
        )
          .bind(pattern, pattern, userId)
          .all();
        return jsonResponse({ users: results });
      } catch (e) {
        console.error("users/search error:", e);
        return jsonResponse({ error: "搜索失败，请稍后重试" }, 500);
      }
    }

    if (pathname === "/friend-requests" && request.method === "GET") {
      const userId = await getUserIdFromRequest(request, secret);
      if (!userId) return jsonResponse({ error: "未登录" }, 401);
      try {
        const { results } = await env.capslian_db.prepare(
          "SELECT fr.id, fr.requester_id, fr.target_id, fr.status, fr.created_at, u.username, u.display_name, u.avatar_url FROM friend_requests fr JOIN users u ON fr.requester_id = u.id WHERE fr.target_id = ? AND fr.status = 'pending' ORDER BY fr.created_at DESC"
        )
          .bind(userId)
          .all();
        return jsonResponse({ friend_requests: results });
      } catch (e) {
        console.error("friend-requests GET error:", e);
        const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
        if (msg.includes("no such table") || msg.includes("friend_requests")) {
          return jsonResponse({ error: "服务未就绪" }, 503);
        }
        return jsonResponse({ error: "获取失败" }, 500);
      }
    }

    if (pathname === "/friend-requests" && request.method === "POST") {
      const userId = await getUserIdFromRequest(request, secret);
      if (!userId) return jsonResponse({ error: "未登录" }, 401);
      let body: { target_id?: string };
      try {
        body = (await request.json()) as { target_id?: string };
      } catch {
        return jsonResponse({ error: "请求体无效" }, 400);
      }
      const targetId = String(body?.target_id ?? "").trim();
      if (!targetId || targetId === userId) return jsonResponse({ error: "无效的 target_id" }, 400);
      try {
        const existing = await env.capslian_db.prepare(
          "SELECT id, status FROM friend_requests WHERE requester_id = ? AND target_id = ?"
        )
          .bind(userId, targetId)
          .first();
        if (existing && typeof existing === "object") {
          const status = (existing as { status: string }).status;
          if (status === "pending") return jsonResponse({ error: "已发送过好友申请" }, 409);
          if (status === "accepted") return jsonResponse({ error: "已是好友" }, 409);
        }
        const id = uuid();
        await env.capslian_db.prepare(
          "INSERT INTO friend_requests (id, requester_id, target_id, status) VALUES (?, ?, ?, 'pending')"
        )
          .bind(id, userId, targetId)
          .run();
        const row = await env.capslian_db.prepare(
          "SELECT id, requester_id, target_id, status, created_at FROM friend_requests WHERE id = ?"
        )
          .bind(id)
          .first();
        return jsonResponse({ friend_request: row }, 201);
      } catch (e) {
        const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
        console.error("friend-requests POST error:", msg);
        if (msg.includes("no such table") || msg.includes("friend_requests")) {
          return jsonResponse({ error: "服务未就绪，请先执行数据库迁移：wrangler d1 migrations apply capslian-db --remote" }, 503);
        }
        return jsonResponse({ error: "发送失败，请稍后重试" }, 500);
      }
    }

    const friendRequestAcceptMatch = pathname.match(/^\/friend-requests\/([^/]+)\/accept$/);
    if (friendRequestAcceptMatch && request.method === "POST") {
      const requestId = friendRequestAcceptMatch[1];
      const userId = await getUserIdFromRequest(request, secret);
      if (!userId) return jsonResponse({ error: "未登录" }, 401);
      try {
        const row = await env.capslian_db.prepare(
          "SELECT id, requester_id, target_id, status FROM friend_requests WHERE id = ? AND target_id = ? AND status = 'pending'"
        )
          .bind(requestId, userId)
          .first();
        if (!row || typeof row !== "object") return jsonResponse({ error: "申请不存在或已处理" }, 404);
        const r = row as { requester_id: string; target_id: string };
        await env.capslian_db.prepare("UPDATE friend_requests SET status = 'accepted' WHERE id = ?").bind(requestId).run();
        await env.capslian_db.prepare("INSERT OR IGNORE INTO follows (follower_id, following_id) VALUES (?, ?)").bind(r.requester_id, r.target_id).run();
        await env.capslian_db.prepare("INSERT OR IGNORE INTO follows (follower_id, following_id) VALUES (?, ?)").bind(r.target_id, r.requester_id).run();
        return jsonResponse({ accepted: true });
      } catch (e) {
        console.error("friend-requests accept error:", e);
        return jsonResponse({ error: "操作失败" }, 500);
      }
    }

    const friendRequestRejectMatch = pathname.match(/^\/friend-requests\/([^/]+)\/reject$/);
    if (friendRequestRejectMatch && request.method === "POST") {
      const requestId = friendRequestRejectMatch[1];
      const userId = await getUserIdFromRequest(request, secret);
      if (!userId) return jsonResponse({ error: "未登录" }, 401);
      try {
        const row = await env.capslian_db.prepare(
          "SELECT id FROM friend_requests WHERE id = ? AND target_id = ? AND status = 'pending'"
        )
          .bind(requestId, userId)
          .first();
        if (!row || typeof row !== "object") return jsonResponse({ error: "申请不存在或已处理" }, 404);
        await env.capslian_db.prepare("UPDATE friend_requests SET status = 'rejected' WHERE id = ?").bind(requestId).run();
        return jsonResponse({ rejected: true });
      } catch (e) {
        console.error("friend-requests reject error:", e);
        return jsonResponse({ error: "操作失败" }, 500);
      }
    }

    if (pathname === "/users/me/friends" && request.method === "GET") {
      const userId = await getUserIdFromRequest(request, secret);
      if (!userId) return jsonResponse({ error: "未登录" }, 401);
      try {
        const { results } = await env.capslian_db.prepare(
          `SELECT u.id, u.username, u.display_name, u.avatar_url
           FROM friend_requests fr
           JOIN users u ON u.id = CASE WHEN fr.requester_id = ? THEN fr.target_id ELSE fr.requester_id END
           WHERE (fr.requester_id = ? OR fr.target_id = ?) AND fr.status = 'accepted'`
        )
          .bind(userId, userId, userId)
          .all();
        return jsonResponse({ friends: results });
      } catch (e) {
        console.error("users/me/friends GET error:", e);
        const msg = e && typeof (e as { message?: string }).message === "string" ? (e as { message: string }).message : String(e);
        if (msg.includes("no such table") || msg.includes("friend_requests")) {
          return jsonResponse({ error: "服务未就绪" }, 503);
        }
        return jsonResponse({ error: "获取失败" }, 500);
      }
    }

    if (pathname === "/messages" && request.method === "GET") {
      const userId = await getUserIdFromRequest(request, secret);
      if (!userId) return jsonResponse({ error: "未登录" }, 401);
      const withUser = url.searchParams.get("with_user") ?? "";
      const limit = Math.min(Number(url.searchParams.get("limit")) || 50, 100);
      const cursor = url.searchParams.get("cursor") ?? "";
      if (withUser) {
        const sql = cursor
          ? "SELECT id, sender_id, receiver_id, content, created_at, read FROM messages WHERE ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)) AND created_at < ? ORDER BY created_at DESC LIMIT ?"
          : "SELECT id, sender_id, receiver_id, content, created_at, read FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) ORDER BY created_at DESC LIMIT ?";
        const bind = cursor ? [userId, withUser, withUser, userId, cursor, limit] : [userId, withUser, withUser, userId, limit];
        const { results } = await env.capslian_db.prepare(sql).bind(...bind).all();
        return jsonResponse({ messages: results });
      }
      const { results: convList } = await env.capslian_db.prepare(
        "SELECT DISTINCT CASE WHEN sender_id = ? THEN receiver_id ELSE sender_id END as peer_id FROM messages WHERE sender_id = ? OR receiver_id = ?"
      )
        .bind(userId, userId, userId)
        .all();
      const withLast = await Promise.all(
        (convList as { peer_id: string }[]).map(async (row) => {
          const peerId = row.peer_id;
          const last = await env.capslian_db.prepare(
            "SELECT content, created_at FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) ORDER BY created_at DESC LIMIT 1"
          )
            .bind(userId, peerId, peerId, userId)
            .first();
          return { peer_id: peerId, last_content: (last as Record<string, unknown>)?.content, last_at: (last as Record<string, unknown>)?.created_at };
        })
      );
      return jsonResponse({ conversations: withLast });
    }

    if (pathname === "/messages" && request.method === "POST") {
      const userId = await getUserIdFromRequest(request, secret);
      if (!userId) return jsonResponse({ error: "未登录" }, 401);
      const body = (await request.json()) as { receiver_id?: string; content?: string };
      const receiverId = String(body?.receiver_id ?? "").trim();
      const content = String(body?.content ?? "").trim();
      if (!receiverId || !content) return jsonResponse({ error: "receiver_id 和 content 必填" }, 400);
      const id = uuid();
      await env.capslian_db.prepare("INSERT INTO messages (id, sender_id, receiver_id, content, read) VALUES (?, ?, ?, ?, 0)").bind(id, userId, receiverId, content).run();
      const row = await env.capslian_db.prepare("SELECT id, sender_id, receiver_id, content, created_at, read FROM messages WHERE id = ?").bind(id).first();
      return jsonResponse({ message: row });
    }

    const assetMatch = pathname.match(/^\/asset\/(.+)$/);
    if (assetMatch && request.method === "GET") {
      const key = decodeURIComponent(assetMatch[1]);
      const obj = await env.ASSETS.get(key);
      if (!obj) return new Response("Not Found", { status: 404, headers: CORS_HEADERS });
      const headers = new Headers(CORS_HEADERS);
      if (obj.httpMetadata?.contentType) headers.set("Content-Type", obj.httpMetadata.contentType);
      return new Response(obj.body, { status: 200, headers });
    }

    return jsonResponse({ error: "Not Found" }, 404);
  },
};

/**
 * 聊天室 Durable Object（V1 DM 实现时补全 WebSocket 与 D1 落库）。
 */
export class ChatRoom implements DurableObject {
  constructor(private ctx: DurableObjectState, private env: Env) {}

  async fetch(request: Request): Promise<Response> {
    return new Response(JSON.stringify({ message: "ChatRoom placeholder" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }
}
