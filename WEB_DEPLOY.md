# Flutter Web 构建与部署

## API（api.molian.app）无法访问时的检查清单

- **部署 Worker**：在 `cloudflare/` 目录执行 `npm run deploy` 或 `npx wrangler deploy`，确保 API Worker 已成功部署。
- **DNS**：在 Cloudflare Dashboard → 域名 molian.app → DNS 中确认有 `api` 记录（CNAME 指向 `molian-api.zhih2333.workers.dev`，代理开启）。
- **路由 / 自定义域**：Workers & Pages → `molian-api` → 设置 → 域和路由。若使用「路由」，需为 `api.molian.app/*`；更推荐使用「自定义域」添加 `api.molian.app`，由 Cloudflare 自动处理。
- **522 错误**：若 `curl -I https://api.molian.app` 返回 522，说明请求未正确到达 Worker。请检查路由/自定义域是否指向 `molian-api`，且 zone 与 Worker 在同一账号。
- **本地开发临时方案**：api.molian.app 异常时，可用 workers.dev 直连：`./scripts/run_web_dev.sh` 或手动加 `--dart-define=API_BASE_URL=https://molian-api.zhih2333.workers.dev`。

---

**注意**：`build/web` 是 Flutter 在**项目根目录**下生成的目录。部署 Pages 时必须在**项目根目录**（即 `capslian/`）执行 `wrangler pages deploy build/web`，不要在 `cloudflare/` 下执行，否则会报 `ENOENT: no such file or directory, scandir '.../cloudflare/build/web'`。

## 1. 构建 Web（连远端 API）

Web 为 release 构建，默认使用生产环境 API。在项目根目录执行：

```bash
flutter build web \
  --dart-define=API_BASE_URL=https://api.molian.app \
  --dart-define=WS_BASE_URL=wss://api.molian.app
```

产物在 `build/web/`。

## 2. 本地预览

```bash
flutter run -d chrome --web-port=8080
```

或使用任意静态服务器预览已构建产物，例如：

```bash
cd build/web && npx serve -l 3000
```

## 3. 部署到 Cloudflare Pages

### 首次：创建 Pages 项目

在 [Cloudflare Dashboard](https://dash.cloudflare.com) → Pages → Create project → 选择 “Direct Upload”。

或使用 Wrangler（需先登录 `npx wrangler login`）：

```bash
npx wrangler pages project create molian-web
```

### 部署

**必须先**在项目根目录执行 `flutter build web` 生成 `build/web/`，再在**同一项目根目录**执行：

```bash
# 在 capslian/ 下执行，不要 cd 到 cloudflare/
npx wrangler pages deploy build/web --project-name=molian-web
```

若在 `cloudflare/` 目录下，可写为：`npx wrangler pages deploy ../build/web --project-name=molian-web`。

按提示选择或输入项目名。部署完成后会得到类似 `https://molian-web.pages.dev` 的地址。

### 自定义域名（可选）

在 Cloudflare Pages 项目设置中绑定自己的域名即可。

### 分支部署 vs 生产（web.molian.app）

- 使用 `npx wrangler pages deploy build/web --project-name=molian-web` 时，当前 Git 分支会作为**预览部署**（例如 `feature-v1.molian-web.pages.dev`）。
- **自定义域名 web.molian.app 通常绑定的是「生产」部署**，对应的是默认分支（多为 `main`），不会随 feature 分支的部署而更新。
- **要让 web.molian.app 显示最新内容**：把改动合并到生产分支（如 `main`），在该分支上执行 `flutter build web` 和 `npx wrangler pages deploy build/web --project-name=molian-web`；或在 Pages 项目设置里把「生产分支」改为你用的分支（不推荐长期这样）。
- 若希望本次部署带未提交更改，可加：`--commit-dirty=true`（仅用于临时预览）。
