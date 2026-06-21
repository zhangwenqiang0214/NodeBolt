#!/bin/bash
# 集成测试:启动本地 mock(模拟 Mihomo API)→ 运行 NodeBoltSmoke → 关闭 mock
# 用法: ./run_tests.sh [port]   (默认 19090)
cd "$(dirname "$0")"
PORT="${1:-19090}"
pkill -f "mock_clash.py $PORT" 2>/dev/null
sleep 0.3
python3 Tests/Mock/mock_clash.py "$PORT" > /tmp/nodebolt_mock.log 2>&1 &
MP=$!
sleep 1
echo "mock 已启动 (pid=$MP, port=$PORT)"
MOCK_BASE="http://127.0.0.1:$PORT" swift run NodeBoltSmoke
rc=$?
kill "$MP" 2>/dev/null
exit "$rc"
