#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""LuaMUD Agent API.

Runs only on loopback. Nginx exposes it over HTTPS at /luamud/agent/.
The API forwards normal game traffic to the local Telnet listener without
exposing port 7777 to the public internet.
"""
from __future__ import print_function

import base64
import collections
import hashlib
import hmac
import json
import logging
import os
import re
import select
import socket
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn

HOST = os.environ.get("LUAMUD_AGENT_HOST", "127.0.0.1")
PORT = int(os.environ.get("LUAMUD_AGENT_PORT", "8808"))
MUD_HOST = os.environ.get("LUAMUD_HOST", "127.0.0.1")
MUD_PORT = int(os.environ.get("LUAMUD_PORT", "7777"))
TOKEN_FILE = os.environ.get("LUAMUD_AGENT_TOKEN_FILE", "/etc/luamud-agent/token")
MAX_SESSIONS = int(os.environ.get("LUAMUD_AGENT_MAX_SESSIONS", "4"))
MAX_BODY = 65536
MAX_OUTPUT = 49152
IDLE_SECONDS = int(os.environ.get("LUAMUD_AGENT_IDLE_SECONDS", "1800"))
MIN_COMMAND_INTERVAL = float(os.environ.get("LUAMUD_AGENT_MIN_INTERVAL", "0.15"))
MAX_COMMANDS_PER_MINUTE = int(os.environ.get("LUAMUD_AGENT_MAX_COMMANDS_PER_MINUTE", "240"))

LOG = logging.getLogger("luamud_agent_api")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

ANSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
TELNET_IAC = 255


def read_token():
    with open(TOKEN_FILE, "r") as fh:
        token = fh.read().strip()
    if len(token) < 32:
        raise RuntimeError("Agent token must contain at least 32 characters")
    return token


MASTER_TOKEN = read_token()
MASTER_TOKEN_FINGERPRINT = hashlib.sha256(MASTER_TOKEN.encode("utf-8")).hexdigest()[:12]


def _b64url_decode(value):
    padding = "=" * ((4 - len(value) % 4) % 4)
    return base64.urlsafe_b64decode((value + padding).encode("ascii"))


def token_fingerprint(token):
    return hashlib.sha256(token.encode("utf-8")).hexdigest()[:12]


def verify_agent_token(supplied):
    """Return a non-secret audit fingerprint if a token is valid, otherwise None."""
    if hmac.compare_digest(supplied, MASTER_TOKEN):
        return "master-" + MASTER_TOKEN_FINGERPRINT
    parts = supplied.split(".")
    if len(parts) != 3 or parts[0] != "lm1":
        return None
    signed = parts[0] + "." + parts[1]
    expected = base64.urlsafe_b64encode(
        hmac.new(MASTER_TOKEN.encode("utf-8"), signed.encode("ascii"), hashlib.sha256).digest()
    ).decode("ascii").rstrip("=")
    if not hmac.compare_digest(parts[2], expected):
        return None
    try:
        payload = json.loads(_b64url_decode(parts[1]).decode("utf-8"))
        expiry = int(payload["exp"])
    except Exception:
        return None
    now = int(time.time())
    # Temporary bearer tokens are deliberately capped to one day by the server.
    if expiry <= now or expiry > now + 86400:
        return None
    return "temporary-" + token_fingerprint(supplied)


def sanitize_telnet(data):
    """Remove Telnet negotiation bytes and terminal escape sequences for JSON."""
    output = bytearray()
    idx = 0
    while idx < len(data):
        current = data[idx]
        if current == TELNET_IAC:
            if idx + 1 >= len(data):
                break
            command = data[idx + 1]
            if command in (251, 252, 253, 254):  # WILL/WONT/DO/DONT + option
                idx += 3
                continue
            if command == TELNET_IAC:
                output.append(TELNET_IAC)
                idx += 2
                continue
            if command == 250:  # subnegotiation, consume through IAC SE
                idx += 2
                while idx + 1 < len(data):
                    if data[idx] == TELNET_IAC and data[idx + 1] == 240:
                        idx += 2
                        break
                    idx += 1
                continue
            idx += 2
            continue
        output.append(current)
        idx += 1
    text = output.decode("utf-8", "replace").replace("\r\n", "\n").replace("\r", "\n")
    return ANSI_RE.sub("", text)


def parse_state(text):
    rooms = re.findall(r"--([^\n-]{1,80})--", text)
    exits = []
    for direction, title in re.findall(r"(?:➡️|->)\s*([A-Za-z_]+)\s*通往\s*([^\n]+)", text):
        exits.append({"direction": direction.strip(), "title": title.strip()})
    object_ids = re.findall(r"\[([A-Za-z0-9_]+)\]", text)
    hp = re.search(r"(?:^|\n)\s*HP\s*[:：]?\s*(\d+)\s*/\s*(\d+)", text)
    san = re.search(r"(?:^|\n)\s*SAN\s*[:：]?\s*(\d+)\s*/\s*(\d+)", text)
    lowered = text.lower()
    return {
        "room": rooms[-1].strip() if rooms else None,
        "exits": exits,
        "visible_ids": object_ids[-32:],
        "hp": {"current": int(hp.group(1)), "max": int(hp.group(2))} if hp else None,
        "san": {"current": int(san.group(1)), "max": int(san.group(2))} if san else None,
        "login_prompt": ("请输入用户名" in text or "请输入密码" in text or "请创建用户" in text),
        "connected": "连接已断开" not in text and "connection lost" not in lowered,
    }


class MudSession(object):
    def __init__(self, username):
        self.id = uuid.uuid4().hex
        self.username = username
        self.sock = socket.create_connection((MUD_HOST, MUD_PORT), timeout=6)
        self.sock.setblocking(False)
        self.lock = threading.Lock()
        self.created_at = time.time()
        self.last_activity = self.created_at
        self.last_command_at = 0.0
        self.command_times = collections.deque()
        self.last_output = self._drain(timeout=1.2, quiet=0.18)
        self.closed = False

    def _drain(self, timeout=0.7, quiet=0.12):
        chunks = []
        started = time.time()
        last_data = started
        while time.time() - started < timeout:
            wait_for = min(quiet, max(0.01, timeout - (time.time() - started)))
            readable, _, _ = select.select([self.sock], [], [], wait_for)
            if not readable:
                if chunks and time.time() - last_data >= quiet:
                    break
                continue
            data = self.sock.recv(8192)
            if not data:
                self.closed = True
                break
            chunks.append(data)
            last_data = time.time()
            if sum(len(piece) for piece in chunks) > MAX_OUTPUT:
                break
        raw = b"".join(chunks)
        truncated = len(raw) > MAX_OUTPUT
        raw = raw[:MAX_OUTPUT]
        text = sanitize_telnet(raw)
        if truncated:
            text += "\n[Agent API: output truncated]"
        return text

    def _rate_limit(self):
        now = time.time()
        if now - self.last_command_at < MIN_COMMAND_INTERVAL:
            time.sleep(MIN_COMMAND_INTERVAL - (now - self.last_command_at))
        while self.command_times and now - self.command_times[0] > 60:
            self.command_times.popleft()
        if len(self.command_times) >= MAX_COMMANDS_PER_MINUTE:
            raise ValueError("session command rate limit exceeded")
        self.command_times.append(time.time())

    def command(self, text):
        if self.closed:
            raise ValueError("session is closed")
        if not isinstance(text, str) or not text.strip():
            raise ValueError("command must be a non-empty string")
        if len(text.encode("utf-8")) > 4096:
            raise ValueError("command is too long")
        if "\x00" in text:
            raise ValueError("command contains a null byte")
        with self.lock:
            self._rate_limit()
            self.sock.sendall(text.strip().encode("utf-8") + b"\n")
            self.last_command_at = time.time()
            self.last_activity = self.last_command_at
            self.last_output = self._drain()
            return self.last_output

    def close(self, graceful=True):
        if self.closed:
            return
        try:
            if graceful:
                self.sock.setblocking(True)
                self.sock.settimeout(1)
                self.sock.sendall(b"bye\n")
        except Exception:
            pass
        try:
            self.sock.close()
        finally:
            self.closed = True


SESSIONS = {}
SESSIONS_LOCK = threading.Lock()


def expire_sessions():
    now = time.time()
    stale = []
    with SESSIONS_LOCK:
        for session_id, session in list(SESSIONS.items()):
            if session.closed or now - session.last_activity > IDLE_SECONDS:
                stale.append((session_id, session))
        for session_id, _ in stale:
            del SESSIONS[session_id]
    for _, session in stale:
        session.close()


def get_session(session_id):
    expire_sessions()
    with SESSIONS_LOCK:
        session = SESSIONS.get(session_id)
    if not session:
        raise KeyError("session not found or expired")
    return session


def response_for(session, output):
    return {
        "session_id": session.id,
        "username": session.username,
        "output": output,
        "state": parse_state(output),
        "idle_timeout_seconds": IDLE_SECONDS,
    }


class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


class AgentHandler(BaseHTTPRequestHandler):
    server_version = "LuaMUDAgentAPI/1.0"

    def log_message(self, fmt, *args):
        LOG.info("http %s - %s", self.address_string(), fmt % args)

    def _json(self, status, payload):
        encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(encoded)

    def _read_json(self):
        raw_length = self.headers.get("Content-Length", "0")
        try:
            length = int(raw_length)
        except ValueError:
            raise ValueError("invalid Content-Length")
        if length <= 0 or length > MAX_BODY:
            raise ValueError("request body must be between 1 and 65536 bytes")
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except Exception:
            raise ValueError("request body must be valid UTF-8 JSON")

    def _authorized(self):
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return False
        supplied = header[7:].strip()
        fingerprint = verify_agent_token(supplied)
        if not fingerprint:
            return False
        self.auth_fingerprint = fingerprint
        return True

    def _token_fingerprint(self):
        return getattr(self, "auth_fingerprint", "unknown")

    def _require_auth(self):
        if not self._authorized():
            self._json(401, {"error": "unauthorized"})
            return False
        return True

    def do_GET(self):
        if self.path == "/v1/health":
            game_reachable = False
            try:
                probe = socket.create_connection((MUD_HOST, MUD_PORT), timeout=2)
                probe.close()
                game_reachable = True
            except Exception:
                pass
            self._json(200 if game_reachable else 503, {
                "service": "luamud-agent-api",
                "status": "ok" if game_reachable else "degraded",
                "game_reachable": game_reachable,
                "active_sessions": len(SESSIONS),
            })
            return
        if self.path.startswith("/v1/sessions/"):
            if not self._require_auth():
                return
            session_id = self.path.rsplit("/", 1)[-1]
            try:
                session = get_session(session_id)
                self._json(200, response_for(session, session.last_output))
            except KeyError as exc:
                self._json(404, {"error": str(exc)})
            return
        self._json(404, {"error": "not found"})

    def do_POST(self):
        if not self._require_auth():
            return
        try:
            payload = self._read_json()
            if self.path == "/v1/sessions":
                username = payload.get("username", "")
                password = payload.get("password", "")
                confirm_password = payload.get("confirm_password")
                if not re.match(r"^[A-Za-z0-9_]{3,32}$", username):
                    raise ValueError("username must match [A-Za-z0-9_]{3,32}")
                if not isinstance(password, str) or not password or len(password) > 128:
                    raise ValueError("password must be a non-empty string up to 128 characters")
                expire_sessions()
                with SESSIONS_LOCK:
                    if len(SESSIONS) >= MAX_SESSIONS:
                        raise ValueError("maximum active Agent API sessions reached")
                session = MudSession(username)
                initial = session.command(username)
                created = "设置密码" in initial or "请创建用户" in initial
                if "请输入密码" in initial:
                    output = session.command(password)
                elif created:
                    output = session.command(password)
                else:
                    output = initial
                if "请再次输入密码" in output:
                    if confirm_password is None:
                        session.close()
                        self._json(409, {
                            "error": "new account requires confirm_password",
                            "registration_required": True,
                            "output": output,
                        })
                        return
                    output = session.command(confirm_password)
                with SESSIONS_LOCK:
                    SESSIONS[session.id] = session
                LOG.info("open token=%s session=%s user=%s created=%s output_bytes=%d",
                         self._token_fingerprint(), session.id[:12], username, created, len(output.encode("utf-8")))
                self._json(201, response_for(session, output))
                return
            if self.path.startswith("/v1/sessions/") and self.path.endswith("/command"):
                session_id = self.path.split("/")[3]
                command = payload.get("command")
                session = get_session(session_id)
                output = session.command(command)
                LOG.info("command token=%s session=%s user=%s command_bytes=%d output_bytes=%d",
                         self._token_fingerprint(), session.id[:12], session.username,
                         len(command.encode("utf-8")), len(output.encode("utf-8")))
                self._json(200, response_for(session, output))
                return
            self._json(404, {"error": "not found"})
        except (ValueError, KeyError) as exc:
            self._json(400, {"error": str(exc)})
        except Exception as exc:
            LOG.exception("agent api request failed")
            self._json(502, {"error": "upstream game interaction failed", "detail": str(exc)})

    def do_DELETE(self):
        if not self._require_auth():
            return
        if not self.path.startswith("/v1/sessions/"):
            self._json(404, {"error": "not found"})
            return
        session_id = self.path.rsplit("/", 1)[-1]
        try:
            with SESSIONS_LOCK:
                session = SESSIONS.pop(session_id)
            session.close(graceful=True)
            LOG.info("close token=%s session=%s user=%s", self._token_fingerprint(), session_id[:12], session.username)
            self._json(200, {"closed": True, "session_id": session_id})
        except KeyError:
            self._json(404, {"error": "session not found or expired"})


def main():
    LOG.info("starting Agent API host=%s port=%s token=%s", HOST, PORT, MASTER_TOKEN_FINGERPRINT)
    server = ThreadingHTTPServer((HOST, PORT), AgentHandler)
    try:
        server.serve_forever(poll_interval=0.5)
    finally:
        with SESSIONS_LOCK:
            live = list(SESSIONS.values())
            SESSIONS.clear()
        for session in live:
            session.close()
        server.server_close()


if __name__ == "__main__":
    main()
