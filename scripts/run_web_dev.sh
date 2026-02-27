#!/usr/bin/env bash
# 本地 Web 开发：使用 workers.dev 避免 api.molian.app 的 CORS/522 问题
# 若 api.molian.app 已修复，可改用 --dart-define=API_BASE_URL=https://api.molian.app
set -e
cd "$(dirname "$0")/.."
flutter run -d chrome \
  --dart-define=API_BASE_URL=https://molian-api.zhih2333.workers.dev \
  --dart-define=WS_BASE_URL=wss://molian-api.zhih2333.workers.dev
