# Molian API (Cloudflare Workers)

- **D1**：用户、帖子、关注、私信等表，见 `migrations/0000_initial.sql`。
- **R2**：`molian-assets` 存储头像、帖子图片。
- **Durable Objects**：`ChatRoom` 用于 DM 实时会话（V1 实现）。

## 首次部署

1. 创建 D1 数据库并写入 `wrangler.toml` 中的 `database_id`：
   ```bash
   npm run db:create
   ```
2. （可选）创建 R2 桶：`wrangler r2 bucket create molian-assets`
3. 本地应用迁移：`npm run db:migrate:local`
4. 部署：`npm run deploy`

## 本地开发

```bash
npm install
npm run dev
```

API 基础地址示例：`http://localhost:8787`。Flutter 端可通过 `--dart-define=API_BASE_URL=http://localhost:8787` 指定。
