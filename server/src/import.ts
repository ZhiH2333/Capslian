import mysql from "mysql2/promise";
import fs from "fs";
import path from "path";

interface ExportData {
  users: any[];
  posts: any[];
  post_likes: any[];
  comments: any[];
  follows: any[];
  messages: any[];
}

async function importData() {
  const exportFile = path.join(__dirname, "../../cloudflare/scripts/export.json");
  
  if (!fs.existsSync(exportFile)) {
    console.error("export.json not found! Run wrangler d1 export first.");
    return;
  }

  const data: ExportData = JSON.parse(fs.readFileSync(exportFile, "utf-8"));

  const pool = mysql.createPool({
    host: process.env.DB_HOST || "localhost",
    user: process.env.DB_USER || "root",
    password: process.env.DB_PASSWORD || "",
    database: process.env.DB_NAME || "molian",
    waitForConnections: true,
    connectionLimit: 10,
  });

  try {
    console.log("Importing users...");
    for (const user of data.users) {
      await pool.execute(
        "INSERT IGNORE INTO users (id, username, password_hash, salt, display_name, avatar_url, bio, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        [user.id, user.username, user.password_hash, user.salt, user.display_name, user.avatar_url, user.bio, user.created_at]
      );
    }
    console.log(`Imported ${data.users.length} users`);

    console.log("Importing posts...");
    for (const post of data.posts) {
      await pool.execute(
        "INSERT IGNORE INTO posts (id, user_id, content, image_urls, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
        [post.id, post.user_id, post.content, post.image_urls, post.created_at, post.updated_at]
      );
    }
    console.log(`Imported ${data.posts.length} posts`);

    console.log("Importing post_likes...");
    for (const like of data.post_likes) {
      await pool.execute(
        "INSERT IGNORE INTO post_likes (post_id, user_id, created_at) VALUES (?, ?, ?)",
        [like.post_id, like.user_id, like.created_at]
      );
    }
    console.log(`Imported ${data.post_likes.length} post_likes`);

    console.log("Importing comments...");
    for (const comment of data.comments) {
      await pool.execute(
        "INSERT IGNORE INTO comments (id, post_id, user_id, content, created_at) VALUES (?, ?, ?, ?, ?)",
        [comment.id, comment.post_id, comment.user_id, comment.content, comment.created_at]
      );
    }
    console.log(`Imported ${data.comments.length} comments`);

    console.log("Importing follows...");
    for (const follow of data.follows) {
      await pool.execute(
        "INSERT IGNORE INTO follows (follower_id, following_id, created_at) VALUES (?, ?, ?)",
        [follow.follower_id, follow.following_id, follow.created_at]
      );
    }
    console.log(`Imported ${data.follows.length} follows`);

    console.log("Importing messages...");
    for (const msg of data.messages) {
      await pool.execute(
        "INSERT IGNORE INTO messages (id, sender_id, receiver_id, content, created_at, `read`) VALUES (?, ?, ?, ?, ?, ?)",
        [msg.id, msg.sender_id, msg.receiver_id, msg.content, msg.created_at, msg.read]
      );
    }
    console.log(`Imported ${data.messages.length} messages`);

    console.log("\n✅ Import complete!");
  } catch (e) {
    console.error("Import failed:", e);
  } finally {
    await pool.end();
  }
}

importData();
