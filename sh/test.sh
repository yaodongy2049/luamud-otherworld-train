#!/bin/bash
cd "$(dirname "$0")/.."
echo "=== LuaMUD 自动化测试 ==="
echo
lua tests/run.lua
exit $?
