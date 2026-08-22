#!/usr/bin/env python3
"""A loopback-only Ollama-compatible bridge for LuaMUD.

This process deliberately implements only POST /api/chat and /api/generate. It
accepts no client credentials, keeps the OpenRouter credential server-private,
and returns a narrow JSON result compatible with LuaMUD's existing client.
"""

from __future__ import print_function

import json
import logging
import os
import threading
import time
import uuid
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn

import requests

HOST = os.getenv("LUAMUD_LLM_BRIDGE_HOST", "127.0.0.1")
PORT = int(os.getenv("LUAMUD_LLM_BRIDGE_PORT", "11435"))
OPENROUTER_URL = os.getenv(
    "OPENROUTER_API_URL", "https://openrouter.ai/api/v1/chat/completions"
)
MODEL = os.getenv("LUAMUD_OPENROUTER_MODEL", "qwen/qwen3-30b-a3b-instruct-2507")
API_KEY = os.getenv("OPENROUTER_API_KEY", "")
TIMEOUT_SECONDS = int(os.getenv("LUAMUD_LLM_TIMEOUT_SECONDS", "25"))
MAX_REQUEST_BYTES = int(os.getenv("LUAMUD_LLM_MAX_REQUEST_BYTES", "12288"))
MAX_INPUT_CHARS = int(os.getenv("LUAMUD_LLM_MAX_INPUT_CHARS", "6000"))
MAX_OUTPUT_TOKENS = int(os.getenv("LUAMUD_LLM_MAX_OUTPUT_TOKENS", "180"))
DAILY_CALL_LIMIT = int(os.getenv("LUAMUD_LLM_DAILY_CALL_LIMIT", "24"))
STATE_FILE = os.getenv("LUAMUD_LLM_STATE_FILE", "/var/lib/luamud-openrouter-bridge/usage.json")

LOGGER = logging.getLogger("luamud_openrouter_bridge")

SAFE_COMMANDS = {
    "unknown": 0,
    "help": 1,
    "look": 1,
    "go": 1,
    "say": 2,
    "get": 1,
    "inv": 0,
    "hp": 0,
    "perform": 2,
    "kill": 1,
    "flee": 0,
    "save": 0,
    "journal": 1,
    "bye": 0,
}


class DailyLimiter(object):
    """Counts attempts by UTC day without retaining prompts or answers."""

    def __init__(self, path, limit):
        self.path = path
        self.limit = limit
        self.lock = threading.Lock()

    @staticmethod
    def _today():
        return datetime.utcnow().strftime("%Y-%m-%d")

    def _read(self):
        try:
            with open(self.path, "r") as handle:
                state = json.load(handle)
            if not isinstance(state, dict):
                return {}
            return state
        except (IOError, ValueError):
            return {}

    def _write(self, state):
        directory = os.path.dirname(self.path)
        if directory and not os.path.isdir(directory):
            os.makedirs(directory)
        temporary = self.path + ".tmp"
        with open(temporary, "w") as handle:
            json.dump(state, handle, sort_keys=True)
        os.rename(temporary, self.path)

    def reserve(self):
        with self.lock:
            today = self._today()
            state = self._read()
            if state.get("date") != today:
                state = {"date": today, "attempts": 0}
            attempts = int(state.get("attempts", 0))
            if attempts >= self.limit:
                return False, attempts
            state["attempts"] = attempts + 1
            self._write(state)
            return True, state["attempts"]


LIMITER = DailyLimiter(STATE_FILE, DAILY_CALL_LIMIT)
IN_FLIGHT = threading.BoundedSemaphore(value=1)


def compact_json(value):
    """Guarantee a valid, compact JSON string for LuaMUD's cjson parser."""
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def unknown_result():
    return {"results": [{"func": "unknown", "args": []}]}


def has_control_char(value):
    return any(ord(character) < 32 or ord(character) == 127 for character in value)


def valid_command_result(value):
    if not isinstance(value, dict):
        return None
    results = value.get("results")
    if not isinstance(results, list) or len(results) != 1:
        return None
    call = results[0]
    if not isinstance(call, dict):
        return None
    func = call.get("func")
    args = call.get("args", [])
    if not isinstance(func, str):
        return None
    func = func.lower()
    if func not in SAFE_COMMANDS or not isinstance(args, list) or len(args) > SAFE_COMMANDS[func]:
        return None
    for arg in args:
        if not isinstance(arg, str) or not arg or len(arg) > 96 or has_control_char(arg):
            return None
    return {"results": [{"func": func, "args": args}]}


def valid_narrative_result(value):
    if not isinstance(value, dict):
        return None
    results = value.get("results")
    if not isinstance(results, list) or len(results) != 1:
        return None
    text = results[0]
    if not isinstance(text, str) or not text or len(text) > 120 or has_control_char(text):
        return None
    return {"results": [text]}


def route_is_command(messages):
    for message in messages:
        if message.get("role") == "system" and "自然语言转游戏指令Agent" in message.get("content", ""):
            return True
    return False


def normalize_messages(payload, endpoint):
    if endpoint == "/api/chat":
        messages = payload.get("messages")
        if not isinstance(messages, list) or len(messages) < 1 or len(messages) > 4:
            raise ValueError("invalid messages")
        normalized = []
        total = 0
        for message in messages:
            if not isinstance(message, dict):
                raise ValueError("invalid message")
            role = message.get("role")
            content = message.get("content")
            if role not in ("system", "user") or not isinstance(content, str):
                raise ValueError("invalid message fields")
            total += len(content)
            normalized.append({"role": role, "content": content})
    else:
        prompt = payload.get("prompt")
        if not isinstance(prompt, str):
            raise ValueError("invalid prompt")
        total = len(prompt)
        normalized = [{"role": "user", "content": prompt}]
    if total < 1 or total > MAX_INPUT_CHARS:
        raise ValueError("input too large")
    return normalized


def call_openrouter(messages):
    if not API_KEY:
        raise RuntimeError("missing server credential")
    payload = {
        "model": MODEL,
        "messages": messages,
        "temperature": 0,
        "max_tokens": MAX_OUTPUT_TOKENS,
        "response_format": {"type": "json_object"},
    }
    headers = {
        "Authorization": "Bearer " + API_KEY,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://github.com/yaodongy2049/luamud-otherworld-train",
        "X-OpenRouter-Title": "LuaMUD Otherworld Train",
    }
    response = requests.post(OPENROUTER_URL, json=payload, headers=headers,
                             timeout=(5, TIMEOUT_SECONDS))
    if response.status_code != 200:
        raise RuntimeError("upstream status {0}".format(response.status_code))
    body = response.json()
    choices = body.get("choices", [])
    if not choices or not isinstance(choices[0], dict):
        raise RuntimeError("upstream response missing choice")
    message = choices[0].get("message", {})
    content = message.get("content") if isinstance(message, dict) else None
    if not isinstance(content, str):
        raise RuntimeError("upstream response missing content")
    return content


class LoopbackHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


class BridgeHandler(BaseHTTPRequestHandler):
    server_version = "LuaMUDOpenRouterBridge/1.0"

    def log_message(self, _format, *_args):
        # BaseHTTPRequestHandler logs request paths; use structured, content-free logs below.
        return

    def _send_json(self, status, value):
        encoded = compact_json(value).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(encoded)

    def _error(self, status, code):
        self._send_json(status, {"error": code})

    def do_GET(self):
        if self.path == "/healthz":
            self._send_json(200, {"status": "ok", "model": MODEL, "key_configured": bool(API_KEY)})
            return
        self._error(404, "not_found")

    def do_POST(self):
        request_id = uuid.uuid4().hex
        started = time.time()
        if self.path not in ("/api/chat", "/api/generate"):
            self._error(404, "not_found")
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length < 1 or length > MAX_REQUEST_BYTES:
            self._error(413, "request_too_large")
            return
        try:
            raw_body = self.rfile.read(length)
            payload = json.loads(raw_body.decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("invalid body")
            messages = normalize_messages(payload, self.path)
        except (UnicodeDecodeError, ValueError, TypeError):
            LOGGER.warning("request_id=%s outcome=invalid_request", request_id)
            self._error(400, "invalid_request")
            return

        allowed, used = LIMITER.reserve()
        if not allowed:
            LOGGER.warning("request_id=%s outcome=daily_limit attempts=%s", request_id, used)
            self._error(429, "daily_limit")
            return
        if not IN_FLIGHT.acquire(False):
            LOGGER.warning("request_id=%s outcome=busy", request_id)
            self._error(429, "busy")
            return

        try:
            content = call_openrouter(messages)
            parsed = json.loads(content)
            result = valid_command_result(parsed) if route_is_command(messages) else valid_narrative_result(parsed)
            if result is None:
                result = unknown_result() if route_is_command(messages) else {"results": []}
                outcome = "invalid_model_json"
            else:
                outcome = "ok"
            if self.path == "/api/chat":
                response = {"model": "openrouter-bridge", "message": {"role": "assistant", "content": compact_json(result)}, "done": True}
            else:
                response = {"model": "openrouter-bridge", "response": compact_json(result), "done": True}
            self._send_json(200, response)
            LOGGER.info("request_id=%s endpoint=%s outcome=%s elapsed_ms=%d", request_id, self.path, outcome, int((time.time() - started) * 1000))
        except (requests.RequestException, ValueError, RuntimeError) as error:
            LOGGER.warning("request_id=%s endpoint=%s outcome=upstream_error reason=%s elapsed_ms=%d", request_id, self.path, str(error)[:80], int((time.time() - started) * 1000))
            self._error(503, "upstream_unavailable")
        finally:
            IN_FLIGHT.release()


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    if HOST not in ("127.0.0.1", "::1", "localhost"):
        raise SystemExit("LUAMUD_LLM_BRIDGE_HOST must remain loopback-only")
    server = LoopbackHTTPServer((HOST, PORT), BridgeHandler)
    LOGGER.info("bridge_started host=%s port=%s model=%s key_configured=%s", HOST, PORT, MODEL, bool(API_KEY))
    server.serve_forever()


if __name__ == "__main__":
    main()
