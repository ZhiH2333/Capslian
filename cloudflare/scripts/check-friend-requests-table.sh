#!/bin/sh
# 检查远程 D1 是否存在 friend_requests 表
cd "$(dirname "$0")/.."
npx wrangler d1 execute molian-db --remote --command "SELECT name FROM sqlite_master WHERE type='table' AND name='friend_requests';"
