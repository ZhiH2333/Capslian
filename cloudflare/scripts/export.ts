import { drizzle } from "drizzle-orm/d1";
import { getOne } from "wrangler";
import fs from "fs";

async function exportData() {
  const db = getOne("molian_db");

  console.log("Exporting users...");
  const users = await db.prepare("SELECT * FROM users").all();
  console.log(`Found ${users.results.length} users`);

  console.log("Exporting posts...");
  const posts = await db.prepare("SELECT * FROM posts").all();
  console.log(`Found ${posts.results.length} posts`);

  console.log("Exporting post_likes...");
  const postLikes = await db.prepare("SELECT * FROM post_likes").all();
  console.log(`Found ${postLikes.results.length} post_likes`);

  console.log("Exporting comments...");
  const comments = await db.prepare("SELECT * FROM comments").all();
  console.log(`Found ${comments.results.length} comments`);

  console.log("Exporting follows...");
  const follows = await db.prepare("SELECT * FROM follows").all();
  console.log(`Found ${follows.results.length} follows`);

  console.log("Exporting messages...");
  const messages = await db.prepare("SELECT * FROM messages").all();
  console.log(`Found ${messages.results.length} messages`);

  const exportData = {
    users: users.results,
    posts: posts.results,
    post_likes: postLikes.results,
    comments: comments.results,
    follows: follows.results,
    messages: messages.results,
  };

  fs.writeFileSync("./export.json", JSON.stringify(exportData, null, 2));
  console.log("Data exported to export.json");
}

exportData();
