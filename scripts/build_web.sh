#!/usr/bin/env bash
# 构建 Flutter Web，使用远端 API。产物：build/web/
set -e
cd "$(dirname "$0")/.."
flutter build web \
  --dart-define=API_BASE_URL=https://api.molian.app \
  --dart-define=WS_BASE_URL=wss://api.molian.app
echo "Done. Output: build/web/"
