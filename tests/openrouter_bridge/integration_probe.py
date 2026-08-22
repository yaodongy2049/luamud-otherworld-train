from __future__ import print_function

import json
import os
import sys

import requests

BASE_URL = os.getenv("LUAMUD_LLM_TEST_URL", "http://127.0.0.1:11436")
PROMPT = """你是自然语言转游戏指令Agent，仅输出严格标准JSON，无多余文字，格式固定：
{"results":[{"func":"动词","args":[参数1,...]}]}
当用户输入为“向东走”时，必须且只能输出：{"results":[{"func":"go","args":["east"]}]}
不得输出解释、Markdown、代码块或其它动作。
"""

payload = {
    "model": "ignored-by-bridge",
    "stream": False,
    "messages": [
        {"role": "system", "content": PROMPT},
        {"role": "user", "content": "用户输入：向东走"},
    ],
}
response = requests.post(BASE_URL + "/api/chat", json=payload, timeout=40)
if response.status_code != 200:
    print("integration_status=failed http_status={0}".format(response.status_code))
    sys.exit(1)
outer = response.json()
content = outer.get("message", {}).get("content", "")
inner = json.loads(content)
results = inner.get("results", [])
if len(results) != 1 or not isinstance(results[0], dict):
    print("integration_status=failed result_shape")
    sys.exit(1)
call = results[0]
func = call.get("func")
args = call.get("args")
if func != "go" or args != ["east"]:
    print("integration_status=failed unexpected_safe_result")
    sys.exit(1)
print("integration_status=ok func=go args=east")
