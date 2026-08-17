#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
ROOT_DIR="$(cd .. && pwd)"
SAVE_DIR="${LUA_MUD_SAVE_PATH:-$ROOT_DIR/data/players}"
mkdir -p "$SAVE_DIR"
export LUA_MUD_SAVE_PATH="$SAVE_DIR"

cd "$ROOT_DIR/src"
lua -e "MUD_LIB_PATH='$ROOT_DIR/src/mud_lib/'" "$ROOT_DIR/src/main.lua"
