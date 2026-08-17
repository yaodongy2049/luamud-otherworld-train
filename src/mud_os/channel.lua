---@module "mud_os/channel"
---@description 广播频道模块

local network = require("mud_os/network")
local class = require("mud_os/class")

---代表一个可广播的频道
---@class Channel 
---@field members table<string, Player> 成员列表
---@field New fun():Channel 新创建一个频道
local Channel = {
  __name = "Channel",
  members = {}
}

---将成员加入频道
---@param user_id string 用户ID
---@param member Player 成员对象
function Channel:join(user_id, member)
  if not self.members[user_id] then
    self.members[user_id] = member
  end
end

---将成员从频道移除
---@param user_id string 用户ID
function Channel:leave(user_id)
  if self.members[user_id] then
    self.members[user_id] = nil
  end
end

---向频道中的成员广播消息
---@param message string 消息内容
---@param ... Charactor 要忽略的发送者列表
function Channel:say(message, ...)
  for user_id, member in pairs(self.members) do
    local ignore = false
    for i, sender in ipairs { ... } do
      if member == sender then
        ignore = true
      end
    end

    if ignore == false then
      network.TcpServer:send_to(user_id, message)
    end
  end
end

class.define_class(Channel)

return Channel