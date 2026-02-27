# EC2 部署指南

## 1. 创建 RDS MySQL

1. AWS Console → RDS → 创建数据库
2. 选择 MySQL，Free Tier (db.t3.micro)
3. 设置用户名密码
4. 记下 endpoint

## 2. 配置安全组

在 EC2 安全组中添加：
- 入站：3306 (MySQL) 来自 EC2 安全组

## 3. 部署服务器

SSH 到 EC2：

```bash
# 安装 Bun
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc

# 上传代码
cd ~
git clone <your-repo> server
cd server

# 创建 .env
cp .env.example .env
nano .env  # 填写数据库信息

# 运行迁移
bun run migrate

# 用 PM2 启动
bun add -g pm2
pm2 start src/index.ts --name molian
pm2 save

# 配置 Nginx 反向代理
sudo apt install nginx
sudo nano /etc/nginx/sites-available/molian
```

Nginx 配置：
```nginx
server {
    listen 80;
    server_name your-domain-or-ip;

    location / {
        proxy_pass http://127.0.0.1:8787;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
    }
}
```

启用：
```bash
sudo ln -s /etc/nginx/sites-available/molian /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

## 4. 更新 Flutter App

在 `lib/core/constants/api_constants.dart` 中修改：

```dart
static const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://your-ec2-ip',  // 或你的域名
);
```

重新编译：
```bash
flutter build web
```
