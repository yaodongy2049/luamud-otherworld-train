from __future__ import print_function

import os
import sys
import uuid

import requests

API_URL = os.getenv("LUAMUD_AGENT_TEST_URL", "http://127.0.0.1:8808")
TOKEN_FILE = os.getenv("LUAMUD_AGENT_TEST_TOKEN_FILE", "/etc/luamud-agent/token")


def request_command(session_id, headers, command):
    response = requests.post(
        API_URL + "/v1/sessions/{0}/command".format(session_id),
        headers=headers,
        json={"command": command},
        timeout=20,
    )
    if response.status_code != 200:
        raise RuntimeError("command status {0}".format(response.status_code))
    return response.json().get("output", "")


def main():
    with open(TOKEN_FILE, "r") as handle:
        token = handle.read().strip()
    username = "hinttest_" + uuid.uuid4().hex[:10]
    password = "T" + uuid.uuid4().hex + "a9"
    headers = {"Authorization": "Bearer " + token, "Content-Type": "application/json"}
    session_id = None
    try:
        created = requests.post(
            API_URL + "/v1/sessions",
            headers=headers,
            json={"username": username, "password": password, "confirm_password": password},
            timeout=15,
        )
        if created.status_code != 201:
            raise RuntimeError("create status {0}".format(created.status_code))
        session_id = created.json()["session_id"]
        # Enter the train entirely through ordinary player actions. The first action uses the
        # station's visible Chinese hint, then the clerk dialogue collects a name and profession.
        onboarding = (
            ("对售票员说 你好", "你叫什么名字"),
            ("提示测试者", "你的职业是什么"),
            ("列车员", "身份已确认"),
            ("去月台", "月台"),
            ("go east", "睡意席卷"),
        )
        for command, expected in onboarding:
            output = request_command(session_id, headers, command)
            if expected not in output:
                raise RuntimeError("onboarding action failed: " + command)
        # Entering the train uses a one-second timer before the player wakes in Compartment 6.
        import time
        time.sleep(2.0)
        output = request_command(session_id, headers, "look")
        if "6号车厢" not in output:
            raise RuntimeError("did not reach Compartment6")
        checks = (
            ("看示意图", "3号车厢的电路开关"),
            # The NPC reply can be naturally rewritten when LLM is enabled; target resolution is
            # proven by the addressed NPC name rather than an implementation-specific keyword.
            ("问问玛拉", "玛拉·维恩"),
            ("get mysterious_note", "神秘便签"),
            ("look", "便签"),
            ("读便签", "只管前进吧"),
        )
        for command, expected in checks:
            output = request_command(session_id, headers, command)
            if expected not in output:
                raise RuntimeError("expected result missing for action hint: " + command)
        print("game_hint_alias_test=ok actions=map_mara_note")
        return 0
    except Exception as exc:
        print("game_hint_alias_test=failed reason={0}".format(str(exc)))
        return 1
    finally:
        if session_id:
            try:
                requests.delete(API_URL + "/v1/sessions/{0}".format(session_id), headers=headers, timeout=8)
            except Exception:
                pass


if __name__ == "__main__":
    sys.exit(main())
