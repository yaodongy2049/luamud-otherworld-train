from __future__ import print_function

import os
import sys
import time
import uuid

import requests

API_URL = os.getenv("LUAMUD_AGENT_TEST_URL", "http://127.0.0.1:8808")
TOKEN_FILE = os.getenv("LUAMUD_AGENT_TEST_TOKEN_FILE", "/etc/luamud-agent/token")


def main():
    with open(TOKEN_FILE, "r") as handle:
        token = handle.read().strip()
    username = "llmtest_" + uuid.uuid4().hex[:10]
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
            print("game_llm_test=failed create_status={0}".format(created.status_code))
            return 1
        session_id = created.json()["session_id"]
        # Account creation logs the player into the starting room. This is intentionally not a built-in
        # command, so it must traverse the LLM command bridge as a single request.
        command = requests.post(
            API_URL + "/v1/sessions/{0}/command".format(session_id),
            headers=headers,
            json={"command": "看看周围"},
            timeout=45,
        )
        if command.status_code != 200:
            print("game_llm_test=failed command_status={0}".format(command.status_code))
            return 1
        initial_output = command.json().get("output", "")
        # LuaMUD runs the model request in a coroutine. The Agent API's first response can return
        # before that coroutine writes its result to the Telnet socket, so wait and issue a built-in
        # non-LLM command to drain the pending output. `help` cannot itself create a room description.
        time.sleep(3.0)
        readback = requests.post(
            API_URL + "/v1/sessions/{0}/command".format(session_id),
            headers=headers,
            json={"command": "help"},
            timeout=15,
        )
        if readback.status_code != 200:
            print("game_llm_test=failed readback_status={0}".format(readback.status_code))
            return 1
        payload = readback.json()
        output = initial_output + "\n" + payload.get("output", "")
        state = payload.get("state", {})
        blocked_markers = ("不知道您想做什么", "手足无措", "无法作出这个动作")
        if not state.get("connected") or any(marker in output for marker in blocked_markers):
            print("game_llm_test=failed llm_fallback_not_observed")
            return 1
        if "--" not in output and "这里" not in output:
            print("game_llm_test=failed scene_not_returned")
            return 1
        print("game_llm_test=ok command=natural_look")
        return 0
    finally:
        if session_id:
            try:
                requests.delete(API_URL + "/v1/sessions/{0}".format(session_id), headers=headers, timeout=8)
            except Exception:
                pass


if __name__ == "__main__":
    sys.exit(main())
