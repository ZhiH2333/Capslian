import { Hono } from "hono";
import { cors } from "hono/cors";
import mysql from "mysql2/promise";
import { hashPassword, verifyPassword } from "./auth/password.js";
import { signJwt, verifyJwt } from "./auth/jwt.js";
import { v4 as uuidv4 } from "uuid";
import multer from "multer";
import path from "path";
import fs from "fs";
import { WebSocketServer, WebSocket } from "ws";

const app = new Hono();

const CORS_ORIGIN = "*";

app.use("*", cors({ origin: CORS_ORIGIN }));

let pool: mysql.Pool;

function getDb() {
  if (!pool) {
    pool = mysql.createPool({
      host: process.env.DB_HOST || "localhost",
      user: process.env.DB_USER || "root",
      password: process.env.DB_PASSWORD || "",
      database: process.env.DB_NAME || "molian",
      waitForConnections: true,
      connectionLimit: 10,
    });
  }
  return pool;
}

const JWT_SECRET = process.env.JWT_SECRET || "dev-secret-change-in-production";
const PORT = parseInt(process.env.PORT || "8787");

const uploadDir = "./uploads";
if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });
const storage = multer.diskStorage({
  destination: (_, __, cb) => cb(null, uploadDir),
  filename: (_, file, cb) => cb(null, `${Date.now()}-${file.originalname}`),
});
const upload = multer({ storage });

function jsonResponse(c: any, body: any, status: number = 200) {
  return c.json(body, status);
}

async function getUserIdFromRequest(authHeader: string | null): Promise<string | null> {
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token) return null;
  const payload = verifyJwt(token, JWT_SECRET);
  return payload ? payload.sub : null;
}

app.get("/", (c) => c.json({ ok: true }));
app.get("/health", (c) => c.json({ ok: true }));

app.post("/auth/register", async (c) => {
  try {
    const body = await c.req.json();
    const username = String(body?.username ?? "").trim().toLowerCase();
    const password = String(body?.password ?? "");
    const displayName = (body?.displayName as string)?.trim() || username;
    if (!username || username.length < 2) return jsonResponse(c, { error: "用户名至少 2 个字符" }, 400);
    if (!password || password.length < 6) return jsonResponse(c, { error: "密码至少 6 个字符" }, 400);
    const { hashHex, saltBase64 } = await hashPassword(password);
    const id = uuidv4();
    const db = getDb();
    await db.execute(
      "INSERT INTO users (id, username, password_hash, salt, display_name) VALUES (?, ?, ?, ?, ?)",
      [id, username, hashHex, saltBase64, displayName]
    );
    const token = signJwt({ sub: id }, JWT_SECRET);
    const [rows]: any = await db.execute("SELECT id, username, display_name, avatar_url, bio, created_at FROM users WHERE id = ?", [id]);
    return jsonResponse(c, { token, user: rows[0] });
  } catch (e: any) {
    console.error("Register error:", e.message);
    if (e.message.includes("UNIQUE") || e.message.includes("unique")) return jsonResponse(c, { error: "用户名已存在" }, 409);
    return jsonResponse(c, { error: "注册失败: " + e.message }, 500);
  }
});

app.post("/auth/login", async (c) => {
  try {
    const body = await c.req.json();
    const username = String(body?.username ?? "").trim().toLowerCase();
    const password = String(body?.password ?? "");
    if (!username || !password) return jsonResponse(c, { error: "用户名和密码必填" }, 400);
    const db = getDb();
    const [rows]: any = await db.execute(
      "SELECT id, username, password_hash, salt, display_name, avatar_url, bio, created_at FROM users WHERE username = ?",
      [username]
    );
    if (!rows || rows.length === 0) return jsonResponse(c, { error: "用户名或密码错误" }, 401);
    const r = rows[0];
    const ok = await verifyPassword(password, r.salt, r.password_hash);
    if (!ok) return jsonResponse(c, { error: "用户名或密码错误" }, 401);
    const token = signJwt({ sub: r.id }, JWT_SECRET);
    const user = { id: r.id, username: r.username, display_name: r.display_name, avatar_url: r.avatar_url, bio: r.bio, created_at: r.created_at };
    return jsonResponse(c, { token, user });
  } catch {
    return jsonResponse(c, { error: "登录失败" }, 500);
  }
});

app.get("/auth/me", async (c) => {
  const userId = await getUserIdFromRequest(c.req.header("Authorization"));
  if (!userId) return jsonResponse(c, { error: "未登录" }, 401);
  const db = getDb();
  const [rows]: any = await db.execute("SELECT id, username, display_name, avatar_url, bio, created_at FROM users WHERE id = ?", [userId]);
  if (!rows || rows.length === 0) return jsonResponse(c, { error: "用户不存在" }, 404);
  return jsonResponse(c, { user: rows[0] });
});

app.patch("/users/me", async (c) => {
  const userId = await getUserIdFromRequest(c.req.header("Authorization"));
  if (!userId) return jsonResponse(c, { error: "未登录" }, 401);
  try {
    const body = await c.req.json();
    const updates: string[] = [];
    const values: any[] = [];
    if (body?.display_name !== undefined) { updates.push("display_name = ?"); values.push(String(body.display_name).trim()); }
    if (body?.bio !== undefined) { updates.push("bio = ?"); values.push(String(body.bio).trim()); }
    if (body?.avatar_url !== undefined) { updates.push("avatar_url = ?"); values.push(String(body.avatar_url).trim()); }
    if (updates.length === 0) return jsonResponse(c, { error: "无有效字段" }, 400);
    values.push(userId);
    const db = getDb();
    await db.execute(`UPDATE users SET ${updates.join(", ")} WHERE id = ?`, values);
    const [rows]: any = await db.execute("SELECT id, username, display_name, avatar_url, bio, created_at FROM users WHERE id = ?", [userId]);
    return jsonResponse(c, { user: rows[0] });
  } catch { return jsonResponse(c, { error: "更新失败" }, 500); }
});

app.get("/posts", async (c) => {
  const limit = Math.min(Number(c.req.query("limit")) || 20, 100);
  const cursor = c.req.query("cursor") || "";
  const userId = await getUserIdFromRequest(c.req.header("Authorization"));
  const db = getDb();
  let results: any[];
  if (cursor) {
    const [cursorRows]: any = await db.execute("SELECT created_at FROM posts WHERE id = ?", [cursor]);
    if (cursorRows.length > 0) {
      const [posts]: any = await db.execute(
        "SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id WHERE p.created_at < ? ORDER BY p.created_at DESC LIMIT ?",
        [cursorRows[0].created_at, limit]
      );
      results = posts;
    } else {
      const [posts]: any = await db.execute(
        "SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id ORDER BY p.created_at DESC LIMIT ?",
        [limit]
      );
      results = posts;
    }
  } else {
    const [posts]: any = await db.execute(
      "SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id ORDER BY p.created_at DESC LIMIT ?",
      [limit]
    );
    results = posts;
  }
  const posts = await Promise.all(
    results.map(async (r) => {
      const [likeCount]: any = await db.execute("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?", [r.id]);
      let liked = false;
      if (userId) {
        const [likes]: any = await db.execute("SELECT 1 FROM post_likes WHERE post_id = ? AND user_id = ?", [r.id, userId]);
        liked = likes.length > 0;
      }
      const [commentCount]: any = await db.execute("SELECT COUNT(*) as c FROM comments WHERE post_id = ?", [r.id]);
      return {
        id: r.id,
        user_id: r.user_id,
        content: r.content,
        image_urls: r.image_urls,
        created_at: r.created_at,
        updated_at: r.updated_at,
        like_count: likeCount[0]?.c ?? 0,
        liked,
        comment_count: commentCount[0]?.c ?? 0,
        user: { username: r.username, display_name: r.display_name, avatar_url: r.avatar_url },
      };
    })
  );
  const nextCursor = posts.length === limit && posts.length > 0 ? posts[posts.length - 1].id : null;
  return jsonResponse(c, { posts, nextCursor });
});

app.post("/posts", async (c) => {
  const userId = await getUserIdFromRequest(c.req.header("Authorization"));
  if (!userId) return jsonResponse(c, { error: "未登录" }, 401);
  try {
    const body = await c.req.json();
    const content = String(body?.content ?? "").trim();
    if (!content) return jsonResponse(c, { error: "内容不能为空" }, 400);
    const imageUrls = Array.isArray(body?.image_urls) ? body.image_urls : [];
    const imageUrlsJson = JSON.stringify(imageUrls);
    const id = uuidv4();
    const db = getDb();
    await db.execute(
      "INSERT INTO posts (id, user_id, content, image_urls, created_at, updated_at) VALUES (?, ?, ?, ?, NOW(), NOW())",
      [id, userId, content, imageUrlsJson]
    );
    const [rows]: any = await db.execute(
      "SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id WHERE p.id = ?",
      [id]
    );
    return jsonResponse(c, { post: rows[0] });
  } catch { return jsonResponse(c, { error: "发布失败" }, 500); }
});

app.get("/posts/:id", async (c) => {
  const id = c.req.param("id");
  const db = getDb();
  const [rows]: any = await db.execute(
    "SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id WHERE p.id = ?",
    [id]
  );
  if (!rows || rows.length === 0) return jsonResponse(c, { error: "帖子不存在" }, 404);
  const r = rows[0];
  return jsonResponse(c, {
    post: { id: r.id, user_id: r.user_id, content: r.content, image_urls: r.image_urls, created_at: r.created_at, updated_at: r.updated_at, user: { username: r.username, display_name: r.display_name, avatar_url: r.avatar_url } },
  });
});

app.patch("/posts/:id", async (c) => {
  const postId = c.req.param("id");
  const userId = await getUserIdFromRequest(c.req.header("Authorization"));
  if (!userId) return jsonResponse(c, { error: "未登录" }, 401);
  const body = await c.req.json();
  const content = body?.content !== undefined ? String(body.content).trim() : null;
  const imageUrls = Array.isArray(body?.image_urls) ? body.image_urls : null;
  if (content === null && imageUrls === null) return jsonResponse(c, { error: "无有效更新字段" }, 400);
  if (content !== null && !content) return jsonResponse(c, { error: "内容不能为空" }, 400);

  const db = getDb();
  const [postRows]: any = await db.execute("SELECT user_id FROM posts WHERE id = ?", [postId]);
  if (!postRows || postRows.length === 0) return jsonResponse(c, { error: "帖子不存在" }, 404);
  if (postRows[0].user_id !== userId) return jsonResponse(c, { error: "只能编辑自己的帖子" }, 403);

  const updates: string[] = ["updated_at = NOW()"];
  const values: any[] = [];
  if (content !== null) {
    updates.push("content = ?");
    values.push(content);
  }
  if (imageUrls !== null) {
    updates.push("image_urls = ?");
    values.push(JSON.stringify(imageUrls));
  }
  values.push(postId);
  await db.execute(`UPDATE posts SET ${updates.join(", ")} WHERE id = ?`, values);

  const [rows]: any = await db.execute(
    "SELECT p.id, p.user_id, p.content, p.image_urls, p.created_at, p.updated_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON p.user_id = u.id WHERE p.id = ?",
    [postId]
  );
  if (!rows || rows.length === 0) return jsonResponse(c, { error: "更新失败" }, 500);
  return jsonResponse(c, { post: rows[0] });
});

app.post("/posts/:id/like", async (c) => {
  const postId = c.req.param("id");
  const userId = await getUserIdFromRequest(c.req.header("Authorization"));
  if (!userId) return jsonResponse(c, { error: "未登录" }, 401);
  const db = getDb();
  await db.execute("INSERT IGNORE INTO post_likes (post_id, user_id) VALUES (?, ?)", [postId, userId]);
  const [count]: any = await db.execute("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?", [postId]);
  return jsonResponse(c, { liked: true, count: count[0]?.c ?? 0 });
});

app.delete("/posts/:id/like", async (c) => {
  const postId = c.req.param("id");
  const userId = await getUserIdFromRequest(c.req.header("Authorization"));
  if (!userId) return jsonResponse(c, { error: "未登录" }, 401);
  const db = getDb();
  await db.execute("DELETE FROM post_likes WHERE post_id = ? AND user_id = ?", [postId, userId]);
  const [count]: any = await db.execute("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?", [postId]);
  return jsonResponse(c, { liked: false, count: count[0]?.c ?? 0 });
});

app.get("/posts/:id/likes", async (c) => {
  const postId = c.req.param("id");
  const userId = await getUserIdFromRequest(c.req.header("Authorization"));
  const db = getDb();
  const [count]: any = await db.execute("SELECT COUNT(*) as c FROM post_likes WHERE post_id = ?", [postId]);
  const [likedRows]: any = userId ? await db.execute("SELECT 1 FROM post_likes WHERE post_id = ? AND user_id = ?", [postId, userId]) : [[]];
  return jsonResponse(c, { count: count[0]?.c ?? 0, liked: likedRows.length > 0 });
});

app.get("/posts/:id/comments", async (c) => {
  const postId = c.req.param("id");
  const limit = Math.min(Number(c.req.query("limit")) || 20, 100);
  const db = getDb();
  const [rows]: any = await db.execute(
    "SELECT c.id, c.post_id, c.user_id, c.content, c.created_at, c.parent_id, u.username, u.display_name, u.avatar_url FROM comments c JOIN users u ON c.user_id = u.id WHERE c.post_id = ? ORDER BY c.created_at ASC LIMIT ?",
    [postId, limit]
  );
  const comments = rows.map((r: any) => ({
    id: r.id,
    post_id: r.post_id,
    user_id: r.user_id,
    content: r.content,
    created_at: r.created_at,
    parent_id: r.parent_id ?? null,
    user: { username: r.username, display_name: r.display_name, avatar_url: r.avatar_url },
  }));
  return jsonResponse(c, { comments });
});

app.post("/posts/:id/comments", async (c) => {
  const postId = c.req.param("id");
  const userId = await getUserIdFromRequest(c.req.header("Authorization"));
  if (!userId) return jsonResponse(c, { error: "未登录" }, 401);
  const body = await c.req.json();
  const content = String(body?.content ?? "").trim();
  if (!content) return jsonResponse(c, { error: "内容不能为空" }, 400);
  const parentId = body?.parent_comment_id ? String(body.parent_comment_id).trim() || null : null;
  const id = uuidv4();
  const db = getDb();
  if (parentId) {
    const [parentRows]: any = await db.execute("SELECT id FROM comments WHERE id = ? AND post_id = ?", [parentId, postId]);
    if (!parentRows || parentRows.length === 0) return jsonResponse(c, { error: "被回复的评论不存在" }, 400);
  }
  await db.execute("INSERT INTO comments (id, post_id, user_id, content, parent_id) VALUES (?, ?, ?, ?, ?)", [id, postId, userId, content, parentId]);
  const [rows]: any = await db.execute(
    "SELECT c.id, c.post_id, c.user_id, c.content, c.created_at, c.parent_id, u.username, u.display_name, u.avatar_url FROM comments c JOIN users u ON c.user_id = u.id WHERE c.id = ?",
    [id]
  );
  const r = rows[0];
  return jsonResponse(c, {
    comment: {
      id: r.id,
      post_id: r.post_id,
      user_id: r.user_id,
      content: r.content,
      created_at: r.created_at,
      parent_id: r.parent_id ?? null,
      user: { username: r.username, display_name: r.display_name, avatar_url: r.avatar_url },
    },
  });
});

app.patch("/posts/:postId/comments/:commentId", async (c) => {
  const postId = c.req.param("postId");
  const commentId = c.req.param("commentId");
  const userId = await getUserIdFromRequest(c.req.header("Authorization"));
  if (!userId) return jsonResponse(c, { error: "未登录" }, 401);

  const db = getDb();
  const [commentRows]: any = await db.execute("SELECT user_id FROM comments WHERE id = ? AND post_id = ?", [commentId, postId]);
  if (!commentRows || commentRows.length === 0) return jsonResponse(c, { error: "评论不存在" }, 404);
  if (commentRows[0].user_id !== userId) return jsonResponse(c, { error: "只能编辑自己的评论" }, 403);

  const body = await c.req.json();
  const content = String(body?.content ?? "").trim();
  if (!content) return jsonResponse(c, { error: "内容不能为空" }, 400);
  await db.execute("UPDATE comments SET content = ? WHERE id = ?", [content, commentId]);

  const [rows]: any = await db.execute(
    "SELECT c.id, c.post_id, c.user_id, c.content, c.created_at, c.parent_id, u.username, u.display_name, u.avatar_url FROM comments c JOIN users u ON c.user_id = u.id WHERE c.id = ?",
    [commentId]
  );
  if (!rows || rows.length === 0) return jsonResponse(c, { error: "更新失败" }, 500);
  const r = rows[0];
  return jsonResponse(c, {
    comment: {
      id: r.id,
      post_id: r.post_id,
      user_id: r.user_id,
      content: r.content,
      created_at: r.created_at,
      parent_id: r.parent_id ?? null,
      user: { username: r.username, display_name: r.display_name, avatar_url: r.avatar_url },
    },
  });
});

app.post("/follows", async (c) => {
  const userId = await getUserIdFromRequest(c.req.header("Authorization"));
  if (!userId) return jsonResponse(c, { error: "未登录" }, 401);
  const body = await c.req.json();
  const followingId = String(body?.following_id ?? "").trim();
  if (!followingId || followingId === userId) return jsonResponse(c, { error: "无效的 following_id" }, 400);
  const db = getDb();
  await db.execute("INSERT IGNORE INTO follows (follower_id, following_id) VALUES (?, ?)", [userId, followingId]);
  return jsonResponse(c, { followed: true });
});

app.delete("/follows/:followingId", async (c) => {
  const followingId = c.req.param("followingId");
  const userId = await getUserIdFromRequest(c.req.header("Authorization"));
  if (!userId) return jsonResponse(c, { error: "未登录" }, 401);
  const db = getDb();
  await db.execute("DELETE FROM follows WHERE follower_id = ? AND following_id = ?", [userId, followingId]);
  return jsonResponse(c, { followed: false });
});

app.get("/users/me/following", async (c) => {
  const userId = await getUserIdFromRequest(c.req.header("Authorization"));
  if (!userId) return jsonResponse(c, { error: "未登录" }, 401);
  const db = getDb();
  const [rows]: any = await db.execute(
    "SELECT u.id, u.username, u.display_name, u.avatar_url FROM users u INNER JOIN follows f ON f.following_id = u.id WHERE f.follower_id = ?",
    [userId]
  );
  return jsonResponse(c, { users: rows });
});

app.get("/users/me/followers", async (c) => {
  const userId = await getUserIdFromRequest(c.req.header("Authorization"));
  if (!userId) return jsonResponse(c, { error: "未登录" }, 401);
  const db = getDb();
  const [rows]: any = await db.execute(
    "SELECT u.id, u.username, u.display_name, u.avatar_url FROM users u INNER JOIN follows f ON f.follower_id = u.id WHERE f.following_id = ?",
    [userId]
  );
  return jsonResponse(c, { users: rows });
});

app.get("/messages", async (c) => {
  const userId = await getUserIdFromRequest(c.req.header("Authorization"));
  if (!userId) return jsonResponse(c, { error: "未登录" }, 401);
  const withUser = c.req.query("with_user") || "";
  const limit = Math.min(Number(c.req.query("limit")) || 50, 100);
  const cursor = c.req.query("cursor") || "";
  const db = getDb();
  if (withUser) {
    const sql = cursor
      ? "SELECT id, sender_id, receiver_id, content, created_at, read FROM messages WHERE ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)) AND created_at < ? ORDER BY created_at DESC LIMIT ?"
      : "SELECT id, sender_id, receiver_id, content, created_at, read FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) ORDER BY created_at DESC LIMIT ?";
    const params = cursor ? [userId, withUser, withUser, userId, cursor, limit] : [userId, withUser, withUser, userId, limit];
    const [rows]: any = await db.execute(sql, params);
    return jsonResponse(c, { messages: rows });
  }
  const [convList]: any = await db.execute(
    "SELECT DISTINCT CASE WHEN sender_id = ? THEN receiver_id ELSE sender_id END as peer_id FROM messages WHERE sender_id = ? OR receiver_id = ?",
    [userId, userId, userId]
  );
  const withLast = await Promise.all(
    convList.map(async (row: any) => {
      const peerId = row.peer_id;
      const [last]: any = await db.execute(
        "SELECT content, created_at FROM messages WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?) ORDER BY created_at DESC LIMIT 1",
        [userId, peerId, peerId, userId]
      );
      return { peer_id: peerId, last_content: last[0]?.content, last_at: last[0]?.created_at };
    })
  );
  return jsonResponse(c, { conversations: withLast });
});

app.post("/messages", async (c) => {
  const userId = await getUserIdFromRequest(c.req.header("Authorization"));
  if (!userId) return jsonResponse(c, { error: "未登录" }, 401);
  const body = await c.req.json();
  const receiverId = String(body?.receiver_id ?? "").trim();
  const content = String(body?.content ?? "").trim();
  if (!receiverId || !content) return jsonResponse(c, { error: "receiver_id 和 content 必填" }, 400);
  const id = uuidv4();
  const db = getDb();
  await db.execute("INSERT INTO messages (id, sender_id, receiver_id, content, read) VALUES (?, ?, ?, ?, 0)", [id, userId, receiverId, content]);
  const [rows]: any = await db.execute("SELECT id, sender_id, receiver_id, content, created_at, read FROM messages WHERE id = ?", [id]);
  return jsonResponse(c, { message: rows[0] });
});

app.post("/upload", upload.single("file"), async (c) => {
  const userId = await getUserIdFromRequest(c.req.header("Authorization"));
  if (!userId) return jsonResponse(c, { error: "未登录" }, 401);
  const file = c.req.file();
  if (!file) return jsonResponse(c, { error: "缺少 file 字段" }, 400);
  const url = `/uploads/${file.filename}`;
  return jsonResponse(c, { url });
});

app.get("/uploads/:filename", async (c) => {
  const filename = c.req.param("filename");
  const filePath = path.join(uploadDir, filename);
  if (!fs.existsSync(filePath)) return c.text("Not Found", 404);
  return c.file(filePath);
});

const server = Bun.serve({ port: PORT, fetch: app.fetch });

const wss = new WebSocketServer({ server });
wss.on("connection", (ws) => {
  console.log("WebSocket connected");
  ws.on("message", (data) => {
    ws.send(JSON.stringify({ message: "Chat placeholder" }));
  });
});

console.log(`Server running on http://localhost:${PORT}`);
