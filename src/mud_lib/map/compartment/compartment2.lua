---@module "mud_lib/map/compartment2"
---@description COC跑团2号车厢场景（线索车厢）

local log = require("mud_os/log")
local Room = require("mud_lib/room")
local Item = require("mud_lib/item")


-- 创建失踪者日记
local diary = Item.New(
    "missing_persons_diary",
    "失踪者日记",
    "一本破旧的日记本，上面记录着一些令人不安的内容。",
    true
)
diary.listeners = {
    look = function(event_name, item, player)
        player:reply("你翻开日记本：")
        player:reply("「第3天...车厢里越来越冷了...」")
        player:reply("「第7天...我看到了它...那东西...不是人...」")
        player:reply("「第14天...主动接触黑暗...也许能找到真相...」")
        player:modify_san(-1)
    end 
}

-- 创建血迹线索
local bloodstain = Item.New(
    "bloodstain",
    "血迹",
    "地面上有大片的血迹，已经干涸发黑。",
    false
)
bloodstain.is_unmov = true
bloodstain.listeners = {
    look = function(event_name, item, player)
        local roll = math.random(1, 100)
        if roll <= player.skill["侦查"] then
            player:reply("你仔细检查血迹：")
            player:reply("血迹来自多名人类，且混有某种粘稠的液体...")
            if player.exclusive == "消防员身份" then
                player:reply("你认出其中有你战友的血迹...")
            end
        else
            player:reply("你认为这只是普通的血迹。")
        end
    end
}

-- 创建抓痕线索
local scratch_marks = Item.New(
    "scratch_marks",
    "抓痕",
    "扶手上有深深的抓痕，似乎是某种巨大力量造成的。",
    false
)
scratch_marks.is_unmov = true
scratch_marks.listeners = {
    look = function(event_name, item, player)
        local roll = math.random(1, 100)
        if roll <= player.skill["灵感"] then
            player:reply("你仔细观察抓痕：")
            player:reply("这些是人类挣扎时留下的，还混杂着非人类的爪印...")
            if player.exclusive == "记者身份" then
                player:reply("你注意到爪印中有一个扭曲的眼睛图案...")
                player:modify_san(-1)
            end
            if player.exclusive == "乘务员身份" then
                player:reply("这是被巨大力量抓坏的痕迹...")
            end
        else
            player:reply("你认为这只是一些普通的划痕。")
        end
    end
}

-- 创建2号车厢房间
local compartment2 = Room.New({
    id = "Compartment2",
    title = "2号车厢",
    desc = "这节车厢布满了战斗的痕迹。地面上有大片干涸的血迹，扶手上有深深的抓痕。角落里似乎藏着什么东西。",
    exits = {
        east = "Compartment1",
        west = "Compartment3"
    },
    items = { bloodstain, scratch_marks },
    listeners = {
        perform = function(event_name, target, player, skill_name, skill_level)
            local roll = math.random(1, 100)
            if skill_name == "聆听" then
                if roll <= skill_level then
                    player:reply("你听到前方1号车厢传来微弱的低语声...")
                else
                    player:reply("你只听到电车行驶的声音。")
                end
                return true
            end
            if skill_name == "侦查" then
                if roll <= skill_level then
                    if not player:has_obj("id", diary.id) and not target:has_obj("id", diary.id) then
                        player:reply("你在角落里找到了一本破旧的日记本，随后把它放入了你的背包。")
                        player:add_obj(diary)
                    else
                        player:reply("这里似乎没有什么其他特别的东西了。")
                    end
                else
                    player:reply("你没有找到任何有用的东西。")
                end
                return true
            end
            return false
        end,
        -- 监听返回3号车厢的尝试（回头）
        before_go = function(event_name, room, player, direction, target_id)
            if direction == "west" then
                player:reply("一股寒意从背后袭来，你感觉到怪物的气息...")
                player:modify_san(-math.random(1, 2))
                player:reply("3号车厢的怪物似乎重新出现了...")
                return false -- 阻止移动
            end
            return true
        end
    }
})

return compartment2.title .. " 加载完成"