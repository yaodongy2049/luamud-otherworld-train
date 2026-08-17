#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Minimal standard-library client for the LuaMUD Agent API."""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

DEFAULT_BASE = "https://47-253-226-173.nip.io/luamud/agent/v1"


def request(base, token, method, path, payload=None):
    data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        base.rstrip("/") + path,
        data=data,
        method=method,
        headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=25) as response:
            print(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        print(body, file=sys.stderr)
        sys.exit(exc.code)


def main():
    parser = argparse.ArgumentParser(description="LuaMUD Agent API client")
    parser.add_argument("--base", default=os.environ.get("LUAMUD_AGENT_BASE", DEFAULT_BASE))
    parser.add_argument("--token", default=os.environ.get("LUAMUD_AGENT_TOKEN"), required=os.environ.get("LUAMUD_AGENT_TOKEN") is None)
    sub = parser.add_subparsers(dest="action")

    open_cmd = sub.add_parser("open")
    open_cmd.add_argument("--username", required=True)
    open_cmd.add_argument("--password", required=True)
    open_cmd.add_argument("--confirm-password")

    state_cmd = sub.add_parser("state")
    state_cmd.add_argument("--session", required=True)

    command_cmd = sub.add_parser("command")
    command_cmd.add_argument("--session", required=True)
    command_cmd.add_argument("--command", required=True)

    close_cmd = sub.add_parser("close")
    close_cmd.add_argument("--session", required=True)
    sub.add_parser("health")

    args = parser.parse_args()
    if not args.action:
        parser.error("an action is required")
    if args.action == "health":
        request(args.base, args.token, "GET", "/health")
    elif args.action == "open":
        payload = {"username": args.username, "password": args.password}
        if args.confirm_password is not None:
            payload["confirm_password"] = args.confirm_password
        request(args.base, args.token, "POST", "/sessions", payload)
    elif args.action == "state":
        request(args.base, args.token, "GET", "/sessions/" + args.session)
    elif args.action == "command":
        request(args.base, args.token, "POST", "/sessions/" + args.session + "/command", {"command": args.command})
    elif args.action == "close":
        request(args.base, args.token, "DELETE", "/sessions/" + args.session)


if __name__ == "__main__":
    main()
