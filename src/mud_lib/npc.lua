---@module 'mud_lib/npc'

local class          = require('mud_os/class')
local log            = require("mud_os/log")
local Charactor      = require("mud_lib/char")
local heart_of_world = require("mud_os/timer")
local semantic_match = require("mud_os/semantic_match")


---NPC
---@class Npc:Charactor, HeartBeatObject
---@field fright_list table 战斗对象列表
---@field topics table 聊天主题列表
---@field New fun(id:string, name:string, desc:string):Npc 构造函数
Npc = {
  __name = "Npc",
  topics = {},
  is_invulnerable = true,
}

---创建NPC实例
---@param id string NPC的唯一标识，相同的角色应该使用不同的 id，否则指令无法明确指定角色
---@param name string NPC的名称
---@param desc string NPC的描述
function Npc:init(id, name, desc)
  self.id = id
  self.name = name
  semantic_match.add_match_src(self.name)
  semantic_match.add_match_src(self.id)
  self.desc = desc
end

---启动NPC，被刷新出来后调用
function Npc:start()
  Npc.super.start(self) -- 注册监听事件
  self.heart_id = heart_of_world:add(self)
  -- log.DEBUG("NPC " .. self.name .. " 启动") 
  if self.topics then
    for k, _ in pairs(self.topics) do
      semantic_match.add_match_src(k)
    end
  end
end

class.define_class(Npc, Charactor)
return Npc
