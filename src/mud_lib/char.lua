---@module "mud_lib/char"

local log = require("mud_os/log")
local class = require("mud_os/class")
local heart_of_world = require("mud_os/timer")
local EventSystem = require("mud_os/event_system")

local SpaceObject = require("mud_lib/space")
local base_combat = require("mud_lib/combat")

---战斗函数
---@alias CombatFunc fun(self: Charactor, enemy: Charactor)


---角色类
---@class Charactor : SpaceObject, HeartBeatObject
---@field id string 角色id
---@field name string 角色名称
---@field hp number 生命值
---@field max_hp number 最大生命值
---@field desc string 角色的描述
---@field combat CombatFunc 战斗函数
---@field heart_id number 心跳定时器id
---@field New fun(name:string):Charactor 构造函数
---@field equipment table<string, Item> 装备物品列表，key为装备位置，value为装备物品
---@field attack_msg string[]? 攻击消息列表
---@field hurt_msg string[]? 伤害消息列表，伤害越高，选择越往后的消息
---@field miss_msg string[]? 未命中消息列表
---@field is_invulnerable boolean 是否为无敌角色，不可攻击
---@field is_in_combat boolean 是否处于战斗状态
local Charactor = {
  __name = "Charactor",
  id = "somebody",
  name = "某人",
  desc = "一个普通的人",
  hp = 100,     -- 角色的HP
  max_hp = 100, --角色的最大HP
  combat = base_combat,
  equipment = {},
  fright_list = {}, ---@type Charactor[] 战斗对象列表
  heart_id = 0,
  is_invulnerable = false,
  is_in_combat = false,
  interval = 5, -- 战斗心跳降低
}

---角色说话
---@param msg string 说话内容
function Charactor:say(msg)
  local this_place = self.environment --[[@as Room]]
  if not class.is_empty(this_place) then
    this_place.channel:say(string.format("%s说道：\"%s\"", self.name, msg), self)
  end
end

---角色进入房间
---@param room Room 目标房间
function Charactor:enter(room)
  local in_msg = "%s走了进来"
  local out_msg = "%s往%s的方向走了出去"
  local old_loc = self.environment --[[@as Room]]
  if not class.is_empty(old_loc) then
    self:say(string.format(out_msg, self.name, room.title))
  end

  self:put(room)
  local new_loc = self.environment --[[@as Room]]
  new_loc.channel:say(string.format(in_msg, self.name), self)
end

---返回角色的描述
---@return string #角色的描述
function Charactor:to_str()
  local desc_str = "-%s[%s]-\n%s\n%s\n%s"
  local equipment_str = self:equipment_str()

  return string.format(desc_str, self.name, self.id, self.desc, equipment_str, self:description())
end

---返回角色的装备描述
---@return string #角色的装备描述
function Charactor:equipment_str()
  local equipment_str = ""

  if self.equipment and next(self.equipment) ~= nil then
    equipment_str = "穿戴装备：\n"
    for pos, item in pairs(self.equipment) do
      equipment_str = equipment_str .. string.format(" * ⌈%s⌋ → %s\n", item.name, item:pos_str())
    end
  end
  return equipment_str
end

---检查角色是否活着
---@return boolean #是否活着
function Charactor:is_alive()
  return self.hp > 0
end

---设置角色的HP值
---@param value number HP值
function Charactor:set_hp(value)
  local was_alive = self:is_alive()
  local old_hp = self.hp
  self.hp = math.max(0, math.min(value, self.max_hp))
  local delta = self.hp - old_hp

  local this_player = self --[[@as Player]]
  if delta ~= 0 and this_player.reply then
    if not self.is_in_combat then
      local color = "\27[35m"
      local reset = "\27[0m"
      this_player:reply(string.format("%s【系统】HP %+d%s", color, delta, reset))
    end
  end

  if was_alive and not self:is_alive() then
    EventSystem:trigger("die", self)
  end
end

---修改角色的HP值（增减）
---@param delta number HP变化量（正数增加，负数减少）
function Charactor:modify_hp(delta)
  self:set_hp(self.hp + delta)
end

---清理死亡的敌人
function Charactor:clean_dead_enemies()
  for i = #self.fright_list, 1, -1 do
    local enemy = self.fright_list[i]
    if not enemy:is_alive() then
      table.remove(self.fright_list, i)
    end
  end
end

---战斗控制：检查并攻击本地敌人
function Charactor:combat_control()
  if not self:is_alive() then
    self.is_in_combat = false
    return
  end

  if #(self.fright_list) == 0 then
    self.is_in_combat = false
    return
  end

  if not self.combat then
    self.is_in_combat = false
    return
  end

  self:clean_dead_enemies()

  if #(self.fright_list) == 0 then
    self.is_in_combat = false
    return
  end

  local enemies = self:get_local_enemies()

  if #enemies > 0 then
    self.is_in_combat = true
    local random = math.random(1, #enemies)
    local target = enemies[random]
    self.combat(self, target)
  else
    self.is_in_combat = false
  end
end

---获取当前房间内的敌人列表
---@return Charactor[] #当前房间内的敌人列表
function Charactor:get_local_enemies()
  local enemies = {}
  local this_place = self.environment --[[@as Room]]

  for i, enemy in ipairs(self.fright_list) do
    local enemy_place = enemy.environment --[[@as Room]]
    if enemy:is_alive() and this_place.id == enemy_place.id then
      table.insert(enemies, enemy)
    end
  end

  return enemies
end

---角色心跳，每秒调用一次。
---@param now number 当前时间
function Charactor:heart_beat(now)
  self:combat_control() --攻击敌人
end

---销毁角色
function Charactor:dispose()
  SpaceObject.dispose(self)
  heart_of_world:del(self.heart_id)
end

---返回角色的详细描述
---@return string #角色的详细描述
function Charactor:description()
  --根据游戏内容设置玩家的详细描述
  local hp_msg = "一动不动，看起来没有生命气息。"
  local hp_rate = self.hp / self.max_hp
  if hp_rate == 1 then
    hp_msg = "看起来非常健康。"
  elseif hp_rate > 0.8 then
    hp_msg = "身上有几处淤青，可以忽略。"
  elseif hp_rate > 0.6 then
    hp_msg = "手脚有点小擦伤，但无大碍。"
  elseif hp_rate > 0.4 then
    hp_msg = "身上有个明显的伤口，正在流血，不过不危及生命。"
  elseif hp_rate > 0.2 then
    hp_msg = "伤痕累累，行动吃力。"
  elseif hp_rate > 0 then
    hp_msg = "就如风中残烛，眼看就要支持不下去了。"
  end
  return hp_msg
end

function Charactor:attack(target)
  table.insert(self.fright_list, target)
  table.insert(target.fright_list, self)
  self.is_in_combat = true
  target.is_in_combat = true
end

class.define_class(Charactor, SpaceObject)
return Charactor