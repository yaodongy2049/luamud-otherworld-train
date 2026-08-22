#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
echo "=== LuaMUD OpenRouter LLM 侧车测试 ==="
lua tests/test_llm_safety.lua
lua tests/test_semantic_match_disabled.lua
lua tests/test_llm_startup_guard.lua
python3 tests/openrouter_bridge/test_bridge.py
