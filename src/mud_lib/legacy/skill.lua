---@module "mud_lib/cmd/skill"

local class = require("mud_os/class")
local cmd_sys = require("mud_lib/cmds")

cmd_sys.command_desc_list.skill = 
[[使用招式
   允许招式仅 4 种：tiger、crane、monkey、unknown
   规则：
   - 包含“虎”→ tiger
   - 包含“鹤”→ crane
   - 包含“猴”→ monkey
   - 输入“收招”→ args 为空数组
   - 其他所有招式 → unknown]]

cmd_sys.command_list.skill = function(this_player, cmds)
  local skill_name = cmds[2]
  local cur_player = this_player --[[@as table]]
  local this_place = this_player.environment --[[@as Room]]
  if not skill_name or skill_name == "null" or skill_name == "" then
    if not cur_player.skill then
      this_player:reply("你摆了一个王八拳的姿势，看起来有点滑稽。")
    else
      cur_player.skill = nil
      this_player:reply("你收招吐气，回复了平时的姿势。")
      this_place.channel:say(this_player.name .. "回复了平时的姿势。", this_player)
    end
    return
  end

  if skill_name == "tiger" then
    cur_player.skill = "tiger"
    this_player:reply("你收拳挺胸，摆了一个猛虎式。")
    this_place.channel:say(this_player.name .. "身形一晃，摆出了一个猛虎式。", this_player)
  elseif skill_name == "monkey" then
    cur_player.skill = "monkey"
    this_player:reply("你缩腰弓背，放了一个灵猴式的架子。")
    this_place.channel:say(this_player.name .. "身形一晃，摆出了一个灵猴式。", this_player)
  elseif skill_name == "crane" then
    cur_player.skill = "crane"
    this_player:reply("你伸臂展拳，正是一招白鹤晾翅。")
    this_place.channel:say(this_player.name .. "身形一晃，摆出了一个白鹤式。", this_player)
  else
    this_player:reply("你想使用什么招数？(猛虎式：tiger 白鹤式：crane 灵猴式：monkey)")
  end
end