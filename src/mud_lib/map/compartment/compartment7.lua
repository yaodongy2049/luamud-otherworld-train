---@module "mud_lib/map/compartment7"
---@description COC跑团7号车厢场景（神秘车厢）

local log = require("mud_os/log")
local Room = require("mud_lib/room")

-- 创建7号车厢房间（神秘车厢，无法正常进入）
local compartment7 = Room.New({
    id = "Compartment7",
    title = "7号车厢",
    desc = "这里是无尽的黑暗...你什么也看不见，什么也听不到...只有一种令人窒息的存在感...",
    exits = {
        east = "Compartment6"
    },
    listeners = {
        after_go = function(event_name, room, player)
            player:reply("你进入了无尽的黑暗...")
            player:reply("一股巨大的压力从四面八方袭来...")
            player:modify_san(-math.random(1, 6))

            -- 强制返回6号车厢
            player:fly_to("Compartment6", "你被一股无形的力量推出了车厢！")
        end,
        look = function(event_name, room, player)
            player:reply("黑暗...无尽的黑暗...")
            player:reply("你感到有什么东西在注视着你...")
        end
    }
})

return compartment7.title .. " 加载完成"
