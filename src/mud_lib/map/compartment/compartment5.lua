---@module "mud_lib/map/compartment5"
---@description COC跑团5号车厢场景（过渡车厢）

local log = require("mud_os/log")
local Room = require("mud_lib/room")
local Item = require("mud_lib/item")
local cmds = require("mud_lib/cmds")
local llm_cmd = require("mud_lib/llm_cmd")

-- 创建水渍线索（不可移动道具）
local water_stain = Item.New(
    "water_stain",
    "水渍",
    "地面上有一滩可疑的水渍，散发着淡淡的铁锈味。",
    false
)
water_stain.is_unmov = true
water_stain.listeners = {
    ---监听玩家在5号车厢的 look 命令
    ---@param player Investigator
    look = function(event_name, item, player)
        player:reply("你仔细观察这滩水渍：")

        local roll = math.random(1, 100)
        if roll <= player.skill["侦查"] then
            player:reply("水渍中似乎混杂着血迹和某种粘稠的液体...")
            if player.exclusive == "消防员身份" then
                player:reply("你认出这是消防水与某种粘稠液体的混合物！这让你想起了当年的火灾现场...")
            end
        else
            player:reply("看起来只是普通的漏水痕迹。")
        end
    end
}

-- 创建泛黄报纸（可移动道具）
local newspaper = Item.New(
    "newspaper",
    "泛黄报纸",
    "一张日期不明的旧报纸，标题模糊不清。",
    false
)
newspaper.listeners = {
    ---监听玩家在5号车厢的 look 命令
    ---@param player Investigator
    look = function(event_name, item, player)
        player:reply("你展开报纸：")

        local roll = math.random(1, 100)
        if roll <= player.skill["侦查"] then
            player:reply("报纸的日期竟然是「明天」！上面报道的正是你现在经历的电车恐怖事件...")
            player:modify_san(-1)
            if player.exclusive == "记者身份" then
                player:reply("你注意到报道中提到所有失踪者都提到了「巨嘴」...")
            end
        else
            player:reply("报纸上的内容太过模糊，无法辨认。")
        end
    end
}

-- 创建5号车厢房间
local compartment5 = Room.New({
    id = "Compartment5",
    title = "5号车厢",
    desc = "这节车厢比6号车厢更加破旧，空气中弥漫着铁锈和潮湿的气息。地面上有一滩可疑的水渍，角落里散落着一张泛黄的报纸。",
    exits = {
        east = "Compartment4",
        west = "Compartment6"
    },
    listeners = {
        ---监听玩家在5号车厢的 look 命令
        ---@param player Investigator
        look = function(event_name, room, player, target_id)
            player:reply("你仔细观察车厢：")
            if not room:has_obj("id", water_stain.id) then
                room:add_obj(water_stain)
                player:reply("- 地面上有一滩可疑的水渍")
            end
            if not player:has_obj("id", newspaper.id) and not room:has_obj("id", newspaper.id) then
                player:reply("- 角落里似乎散落着什么")
                cmds.show_action_hint(player, "你可以使用技能，如'侦查'", "perform 侦查", "侦查")
                cmds.show_action_hint(player, "查看自己的技能及血量", "hp", "查看状态")
            end
            player:reply("- 前方通往4号车厢，后方是来时的6号车厢")
        end,
        ---监听玩家在5号车厢的 perform 命令
        ---@param player Investigator
        perform = function(event_name, target, player, skill_name, skill_level)
            local roll = math.random(1, 100)
            if skill_name == "聆听" then
                if roll <= player.skill["聆听"] then
                    player:reply("你听到前方4号车厢传来微弱的吟声...")
                else
                    player:reply("你只听到电车行驶的单调声音。")
                end
                return true
            end

            if skill_name == "侦查" then
                if not player:has_obj("id", newspaper.id) then
                    local threshold = player.skill["侦查"]
                    local context = "玩家在破旧的5号车厢中仔细搜索，尝试在角落里找到有用的线索，线索是一张泛黄报纸"
                    local desc = llm_cmd.describe_skill_result(roll, threshold, context, player.user_id)
                    if roll <= threshold then
                        player:reply(desc or "你成功地搜索到了一张泛黄的报纸！")
                        player:reply("你捡起它放入了背包。")
                        player:add_obj(newspaper)
                        cmds.show_action_hint(player, "查看背包里有什么", "inv", "背包")
                        cmds.show_action_hint(player, "查看在背包中的物品，如报纸", "look newspaper", "看看报纸")
                        return true
                    else
                        player:reply(desc or "你瞎摸一通但啥都没发现。")
                        return true
                    end
                end
                player:reply("你没有再找到任何有用的东西。")
                return true
            end

            -- 当玩家在这个房间使用 perform 命令时触发
            player:reply("你尝试了" .. skill_name .. "技能，但是失败了，什么都没有发生。")
            return true
        end,
        ---监听返回6号车厢的尝试（回头）
        ---@param player Investigator
        before_go = function(event_name, room, player, direction, target_id)
            if direction == "west" then
                player:reply("身后的车厢似乎在收缩...")
                local roll = math.random(1, 100)
                if roll <= player.core_attrs.dex then
                    player:reply("你勉强稳住身形，退回了5号车厢。")
                    player:modify_san(-math.random(1, 2))
                else
                    player:reply("黑暗吞噬了你的一部分身体！")
                    player:modify_san(-math.random(1, 6))
                    player:modify_hp(-5)
                    player:fly_to("Compartment4", "你被强制向前推进！")
                end
                return false -- 阻止正常移动
            end
            return true
        end
    }
})

return compartment5.title .. " 加载完成"
