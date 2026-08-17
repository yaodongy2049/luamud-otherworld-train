---@module 'mud_lib/weapon'

local class = require('mud_os/class')
local Item = require('mud_lib/item')
local semantic_match = require('mud_lib/semantic_match')

---代表武器
---@class Weapon : Item
---@field New fun(id:string|table, name:string?, desc:string?, damage:number?, wear_pos:string?):Weapon 创建武器实例，会调用 Init 方法
---@field damage number 增加的攻击力
---@field attack_msg string[] 攻击消息列表
---@field hurt_msg string[] 伤害消息列表，伤害越高，选择越往后的消息
---@field miss_msg string[] 未命中消息列表
Weapon = {
    id = 'weapon',
    name = '武器',
    desc = '这是一把武器',
    damage = 0,
    wear_pos = "weapon",
    __name = "Weapon",
}

---初始化武器
---@param id string|table 武器id
---@param name? string 武器名称
---@param desc? string 武器描述
---@param atk? number 攻击力
---@param wear_pos? string 装备位置
---@return boolean
function Weapon:init(id, name, desc, atk, wear_pos)
    -- 如果 id 是表，直接赋值
    if type(id) == "table" then
        class.copy_property(id, self)
        semantic_match.add_match_src(self.name)
        semantic_match.add_match_src(self.id)
        return true
    end
    -- 调用父类初始化
    Item.init(self, id, name, desc)
    self.damage = atk or 0
    self.wear_pos = wear_pos or "right_hand"
    return true
end

---@override
---@return string #武器的字符串表示
function Weapon:to_str()
    return string.format("%s\n攻击力：%d", Item.to_str(self), self.damage)
end

class.define_class(Weapon, Item)
return Weapon