---@module 'mud_lib/monster'

local log = require("mud_os/log")

local class = require('mud_os/class')
local Npc = require("mud_lib/npc")
local Character = require("mud_lib/char")
local EventSystem = require("mud_os/event_system")
local Player = require("mud_lib/player")

---怪物类
---@class Monster:Npc
Monster = {
  __name = "Monster",
  after_go_callback = nil, -- 怪物进入房间后的回调函数
}

---覆盖put方法，在被放入新房间后注册after_go事件监听
---@param env SpaceObject 目标环境
function Monster:put(env)

  -- 先调用父类的put方法
  Monster.super.put(self, env)
  
  -- 获取当前房间
  local current_room = self.environment --[[@as Room]]
  
  -- 如果之前有注册过监听器，先移除旧的监听
  if self.after_go_callback then
    EventSystem:remove_listener("after_go", self.after_go_callback)
    self.after_go_callback = nil
  end
  
  -- 如果当前房间有效，注册after_go事件监听
  if not class.is_empty(current_room) then
    -- 创建回调函数
    self.after_go_callback = function(event_name, target_room, player, direction, target_id)
      -- 检查进入的是否是玩家
      if class.is_instance(player, Player) then
        -- 检查玩家是否和怪物在同一个房间
        local monster_room = self.environment --[[@as Room]]
        if monster_room and monster_room.id == target_room.id then
          -- 开始攻击玩家
          monster_room.channel:say(self.name .. "向" .. player.name .. "扑了过去！", player)
          player:reply("你眼看着" .. self.name .. "向你扑了过来！")
          self:attack(player)
        end
      end
    end
    
    -- 注册事件监听，监听所有after_go事件，在回调中判断是否是自己所在房间
    EventSystem:register_listener("after_go", self.after_go_callback, current_room)
  end
end

---销毁怪物
function Monster:dispose()
  -- 移除事件监听
  if self.after_go_callback then
    EventSystem:remove_listener("after_go", self.after_go_callback)
    self.after_go_callback = nil
  end
  Character.dispose(self)
end

class.define_class(Monster, Npc)

return Monster