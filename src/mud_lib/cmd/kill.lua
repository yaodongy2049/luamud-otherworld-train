---@module "mud_lib/cmd/kill"

local class = require("mud_os/class")
local cmd_sys = require("mud_lib/cmds")

cmd_sys.command_desc_list.kill = "kill：攻击/杀死XX，args=[目标]"
cmd_sys.command_list.kill = function(this_player, cmds)
  cmd_sys.exit_dialog_mode(this_player)  
  
  local target = nil
  local target_id = cmds[2] -- cmds[1]是指令本身，cmds[2]才是参数
  if not target_id then
    this_player:reply("你怒气冲冲的瞪着空气，不知道要攻击谁。")
    return
  else
    if target_id == this_player.id then
      this_player:reply("你狠狠用左脚踢了一下自己的右脚，发现这个行为很傻，于是就停止了。")
      return
    end
    local this_place = this_player.environment --[[@as Room]]
    if class.is_empty(this_place) then
      this_player:reply('你周围什么都没有')
      return
    end
    local targets = this_place:resolve_content(target_id) --[[@as Charactor[] ]]
    if #targets == 0 then
      this_player:reply(string.format("没有%s这个东西", target_id))
      return
    elseif targets[1].is_invulnerable then
      this_player:reply("你不能攻击这个角色")
      return
    elseif targets[1].hp and targets[1].hp > 0 then
      target = targets[1]
    else
      this_player:reply("你不能攻击一个死物。")
      return
    end
  end

  if target then
    this_player:attack(target)
    this_player:reply(string.format("你对着%s大喝一声：“納命来！”",target.name))

    --反击
    this_player:reply(string.format("%s对你一瞪眼，一跺脚，狠狠道：“竟敢在太岁头上动土？”", target.name))

    local player = target  --[[@as Player]]
    if player.user_id then -- 只有玩家才会有 user_id
      player:reply(string.format("%s向你发起了攻击！", this_player.name))
    end

  end
end