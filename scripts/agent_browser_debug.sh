#!/usr/bin/env bash
# agent-browser 调试 Flutter Web 聊天发送消息
# 用法：
#   1. 先在一个终端运行: flutter run -d web-server
#   2. 记下输出的 URL，例如 http://localhost:60271
#   3. 本脚本默认 URL 为 http://localhost:60271，可通过环境变量覆盖:
#      APP_URL=http://localhost:49524 ./scripts/agent_browser_debug.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BROWSERS_PATH="${PROJECT_DIR}/.playwright_browsers"
APP_URL="${APP_URL:-http://localhost:60271}"

if [[ ! -d "$BROWSERS_PATH" ]]; then
  echo "未找到 .playwright_browsers，正在安装 Chromium..."
  PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH" npx playwright install chromium
fi

export PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH"
echo "使用应用 URL: $APP_URL"
echo ""

echo "=== 1. 打开页面 ==="
npx agent-browser open "$APP_URL/"
echo ""

echo "=== 2. 获取可交互元素快照（带 ref） ==="
npx agent-browser snapshot -i
echo ""

echo "=== 接下来可手动执行（将 @eX 替换为快照中的输入框/发送按钮 ref） ==="
echo "  # 若有「Enable accessibility」按钮，先点击:"
echo "  npx agent-browser click @e1"
echo "  npx agent-browser snapshot -i"
echo ""
echo "  # 在聊天页找到输入框 ref（如 @e3），填写并发送:"
echo "  npx agent-browser fill @e3 \"测试消息\""
echo "  npx agent-browser click @e4   # 发送按钮的 ref"
echo ""
echo "  # 或使用语义定位:"
echo "  npx agent-browser find placeholder 输入消息 fill \"测试消息\""
echo "  npx agent-browser find role button click --name \"发送\""
echo ""
