from __future__ import print_function

import os
import sys
import unittest
from unittest.mock import patch

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "openrouter_bridge"))
import bridge  # noqa: E402


class FakeResponse(object):
    status_code = 200

    def json(self):
        return {
            "choices": [{"message": {"content": '{"results":[{"func":"go","args":["east"]}]}'}}]
        }


class BridgeContractTests(unittest.TestCase):
    def test_accepts_single_safe_command(self):
        result = bridge.valid_command_result(
            {"results": [{"func": "GO", "args": ["east"]}]}
        )
        self.assertEqual(result, {"results": [{"func": "go", "args": ["east"]}]})

    def test_rejects_gm_command_and_multiple_commands(self):
        self.assertIsNone(
            bridge.valid_command_result({"results": [{"func": "reload", "args": []}]})
        )
        self.assertIsNone(
            bridge.valid_command_result({
                "results": [
                    {"func": "go", "args": ["east"]},
                    {"func": "kill", "args": ["enemy"]},
                ]
            })
        )

    def test_rejects_extra_or_control_arguments(self):
        self.assertIsNone(
            bridge.valid_command_result({"results": [{"func": "go", "args": ["east", "now"]}]})
        )
        self.assertIsNone(
            bridge.valid_command_result({"results": [{"func": "look", "args": ["x\nbye"]}]})
        )

    def test_accepts_short_narrative_only(self):
        self.assertEqual(
            bridge.valid_narrative_result({"results": ["你在摇晃的车厢里稳住了呼吸。"]}),
            {"results": ["你在摇晃的车厢里稳住了呼吸。"]},
        )
        self.assertIsNone(bridge.valid_narrative_result({"results": [{"func": "go", "args": ["east"]}]}))

    def test_normalizes_ollama_chat_payload(self):
        messages = bridge.normalize_messages(
            {
                "messages": [
                    {"role": "system", "content": "仅 JSON"},
                    {"role": "user", "content": "向东走"},
                ]
            },
            "/api/chat",
        )
        self.assertEqual(messages[1]["content"], "向东走")

    def test_rejects_non_ollama_or_oversized_input(self):
        with self.assertRaises(ValueError):
            bridge.normalize_messages({"messages": [{"role": "assistant", "content": "x"}]}, "/api/chat")
        with self.assertRaises(ValueError):
            bridge.normalize_messages({"prompt": "x" * (bridge.MAX_INPUT_CHARS + 1)}, "/api/generate")

    @patch("bridge.requests.post")
    def test_upstream_call_uses_server_bearer_token(self, mocked_post):
        prior_key = bridge.API_KEY
        bridge.API_KEY = "test-secret-not-logged"
        mocked_post.return_value = FakeResponse()
        try:
            content = bridge.call_openrouter([{"role": "user", "content": "向东走"}])
        finally:
            bridge.API_KEY = prior_key
        self.assertIn("go", content)
        _, kwargs = mocked_post.call_args
        self.assertEqual(kwargs["headers"]["Authorization"], "Bearer test-secret-not-logged")
        self.assertEqual(kwargs["json"]["model"], bridge.MODEL)
        self.assertEqual(kwargs["json"]["response_format"], {"type": "json_object"})


if __name__ == "__main__":
    unittest.main()
