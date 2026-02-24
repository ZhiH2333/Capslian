#!/bin/bash
# 从 D1 导出数据的步骤

echo "=== 1. 导出 D1 数据库 ==="
wrangler d1 export molian_db --output-name export.sql

echo ""
echo "=== 2. 数据已导出到 export.sql ==="
echo "现在你需要手动转换或使用以下方式导入到 MySQL"
