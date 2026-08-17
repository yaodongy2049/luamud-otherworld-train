---@module "mud_lib/item/conductor_key"
---@description 乘务员钥匙物品模块

local Item = require("mud_lib/item")

local conductor_key = Item.New(
    "conductor_key",
    "乘务员钥匙",
    "这是一把铜制钥匙，上面刻着「墨田电车」的标志。"
)
conductor_key.listeners = {
    look = function(event_name, item, player)
        if player.exclusive == "记者身份" then
            player:reply("你注意到钥匙柄上有一个微小的扭曲眼睛图案...")
            player:modify_san(-1)
        end
        if player.exclusive == "消防员身份" then
            player:reply("钥匙上有熟悉的刻字...这是你失踪战友的物品！")
        end
    end
}

---@param this_player Investigator
conductor_key.use = function(self, this_player, target)
    local this_place = this_player.environment --[[@as Room]]
    if not this_place or this_place.id ~= "Compartment1" then
        return this_player:reply("这把钥匙似乎在这里没用。")
    end

    if this_place:has_obj("id", "mysterious_entity") then
        return this_player:reply("驾驶舱门已经开着。")
    end

    local roll = math.random(1, 100)
    if roll <= this_player.skill["侦查"] then
        this_player:reply("你用钥匙打开了驾驶舱门！")

        this_player:reply("门后是一片无尽的黑暗...")
        this_player:reply("一团无法形容的存在出现在你面前...你忍不住的想去触摸(touch)它...")

        local Npc = require("mud_lib/npc")
        local mysterious_entity = Npc.New(
            "mysterious_entity",
            "神秘存在",
            "一团无法形容的黑暗"
        )
        mysterious_entity.listeners = {
            look = function(event_name, npc, player)
                player:reply("你试图看清眼前的存在...")
                player:reply("那是一团无法形容的黑暗，其中闪烁着无数眼睛...")
                player:modify_san(-math.random(1, 4))
            end
        }
        this_place:add_obj(mysterious_entity)
    else
        this_player:reply("钥匙卡在锁眼里，你使劲扭动，差点弄断了才重新拔出来。")
    end
end

return conductor_key