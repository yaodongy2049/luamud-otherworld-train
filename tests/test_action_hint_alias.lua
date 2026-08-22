IS_LLM_ENABLED = true
IS_SEMANTIC_MATCH_ENABLED = false
OLLAMA_HOST = "http://127.0.0.1:1"
package.path = "./src/?.lua;./src/?/init.lua;" .. package.path

local cmds = require("mud_lib/cmds")
require("mud_lib/cmd/common")
require("mud_lib/cmd/get")
require("mud_lib/cmd/say")

local replies = {}
local player = {
  environment = { id = "Compartment6" },
  temp_status = {},
  reply = function(_, message)
    table.insert(replies, message)
  end,
}

cmds.show_action_hint(player, "查看电车示意图", "look train_map", "看示意图")
cmds.show_action_hint(player, "向玛拉询问列车规则", "say 理智 mara_vane", "问问玛拉")
cmds.show_action_hint(player, "阅读神秘便签", "look mysterious_note", "读便签")

local map_cmd = cmds.resolve_action_hint(player, { "看示意图" })
assert(map_cmd and map_cmd[1] == "look" and map_cmd[2] == "train_map", "map hint must resolve to look train_map")
local mara_cmd = cmds.resolve_action_hint(player, { "问问玛拉" })
assert(mara_cmd and mara_cmd[1] == "say" and mara_cmd[2] == "理智" and mara_cmd[3] == "mara_vane", "Mara hint must resolve to say 理智 mara_vane")
local note_cmd = cmds.resolve_action_hint(player, { "读便签" })
assert(note_cmd and note_cmd[1] == "look" and note_cmd[2] == "mysterious_note", "note hint must resolve to look mysterious_note")

cmds.show_action_hint(player, "不应登记", "dev anything", "开发命令")
assert(cmds.resolve_action_hint(player, { "开发命令" }) == nil, "non-normal commands must not become action hints")

player.environment = { id = "Compartment5" }
assert(cmds.resolve_action_hint(player, { "看示意图" }) == nil, "action hint must expire outside its source room")

print("test_action_hint_alias: ok")
