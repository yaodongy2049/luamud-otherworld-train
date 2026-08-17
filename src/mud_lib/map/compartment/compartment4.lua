---@module "mud_lib/map/compartment4"
---@description COC跑团4号车厢场景（关键车厢）

local log = require("mud_os/log")
local Room = require("mud_lib/room")
local Npc = require("mud_lib/npc")
local Item = require("mud_lib/item")
local timer = require("mud_os/timer")
local cmds = require("mud_lib/cmds")
local llm_cmd = require("mud_lib/llm_cmd")
local conductor_key = require("mud_lib/item/conductor_key")


-- 创建濒死乘务员NPC
local dying_conductor = Npc.New("dying_conductor", "濒死的乘务员", "一位身受重伤的乘务员，靠在座椅上，气息微弱。")
---@diagnostic disable-next-line: inject-field
dying_conductor.is_dying = true
dying_conductor.max_hp = 100
dying_conductor:set_hp(1)
dying_conductor.listeners = {
    ask_about = function(event_name, npc, player, topic, content)
        if npc.is_dead then
            player:reply("死去的乘务员一动不动没有任何反应。")
            return false
        end
        if npc.is_dying then
            player:reply("乘务员微弱地睁开眼睛：'你...你是来救我的吗...' 然后无力说出后面的字句。")
        else
            player:reply("乘务员感激地看着你：'谢谢你救了我...' 然后虚弱的闭上了眼睛。")
        end
        return false
    end,
    ---监听玩家在5号车厢的 perform 命令
    ---@param player Investigator
    perform = function(event_name, npc, player, skill_name, skill_level)
        if not npc.id or npc.id ~= "dying_conductor" then
            player:reply("你不能对其他对象使用技能。")
            return false
        end
        -- 当玩家在这个房间使用 perform 命令时触发
        if skill_name == "急救" and not npc.is_dead and npc.is_dying then
            local roll = math.random(1, 100)
            local success = false

            -- 乘务员专属：直接成功
            if player.exclusive == "乘务员身份" then
                success = true
                local context = "玩家对奄奄一息的乘务员进行专业急救"
                local desc = llm_cmd.describe_skill_result(1, 100, context, player.user_id)
                player:reply(desc or "你凭借专业的急救知识，迅速稳定了他的伤势。")
            else
                -- 常规急救判定
                local threshold = player.skill["急救"]
                local context = "玩家在摇晃的车厢中对躺在地上奄奄一息的乘务员进行急救"
                local desc = llm_cmd.describe_skill_result(roll, threshold, context, player.user_id)
                
                if roll <= threshold then
                    success = true
                    player:reply(desc or "你成功对他进行了急救！")
                else
                    player:reply(desc or "你的急救尝试失败了...")
                end
            end

            if success then
                npc.is_dying = false
                player:reply("乘务员缓缓睁开眼睛：'别...别开驾驶舱门...那东西不是我们能碰的...钥匙在我口袋里...'")
                if not player:has_obj("id", conductor_key.id) then
                    player:add_obj(conductor_key)
                    player:reply("你获得了「乘务员钥匙」！")
                    cmds.show_action_hint(player, "使用背包里的物品(如'乘务员钥匙')", "use conductor_key", "使用钥匙")
                end

                if player.exclusive == "乘务员身份" then
                    player:reply("乘务员补充道：'驾驶舱控制台也可以强制解锁...'")
                end
                if player.exclusive == "消防员身份" then
                    player:reply("你认出他正是你失踪的战友！")
                end
                npc.is_dying = false
                npc:set_hp(100)
                npc.name = "虚弱的乘务员"
            else
                npc.is_dying = false
                npc.is_dead = true
                player:reply("乘务员永远闭上了眼睛...")
                player:modify_san(-math.random(1, 2))
                npc:set_hp(0)
                npc.name = "死亡的乘务员"
            end

            if npc.reset_timer_id then
                timer:del(npc.reset_timer_id)
            end
            local reset_task = {
                st_time = os.time()
            }
            reset_task.heart_beat = function(self, now)
                if now - reset_task.st_time < 30 then
                    return
                end
                if npc.environment and npc.environment.channel then
                    if npc.is_dead then
                        npc.environment.channel:say("乘务员的身体开始微微颤抖，似乎又有了气息...")
                    else
                        npc.environment.channel:say("乘务员的身体一阵抽搐，感觉他又快不行了...")
                    end
                end
                npc.is_dying = true
                npc.is_dead = false
                npc:set_hp(1)
                npc.name = "濒死的乘务员"

                timer:del(npc.reset_timer_id)
                npc.reset_timer_id = nil
            end
            npc.reset_timer_id = timer:add(reset_task)

            return true
        end
        player:reply("你尝试了" .. skill_name .. "技能，但是失败了，什么改变都没有发生。")
        return true
    end,
}

-- 创建黑屏电视（不可移动）
local broken_tv = Item.New(
    "broken_tv",
    "黑屏电视",
    "一台老式电视机，屏幕一片漆黑。"
)
broken_tv.is_unmov = true
broken_tv.listeners = {
    look = function(event_name, item, player)
        local roll = math.random(1, 100)
        if roll <= player.skill["灵感"] then
            player:reply("屏幕上闪过一张模糊的人脸...他张嘴在说着什么")
            player:modify_san(-1)
            player:reply("你似乎明白了什么：怪物没有视力，靠听觉追踪！")
        else
            player:reply("电视屏幕一片漆黑，只有雪花点闪烁。")
        end
    end
}

-- 创建4号车厢房间
local compartment4 = Room.New({
    id = "Compartment4",
    title = "4号车厢",
    desc = "这是乘务员室所在的车厢。一位身受重伤的乘务员靠在座椅上。车厢深处似乎通向乘务员休息室。",
    exits = {
        east = "Compartment3",
        west = "Compartment5"
    },
    spown_list = { dying_conductor },
    listeners = {
        look = function(event_name, room, player)
            player:reply("你仔细观察车厢：")
            player:reply("- 前方是通往3号车厢的门")
            if not room:has_obj("id", broken_tv.id) then
                room:add_obj(broken_tv)
                player:reply("- 一台黑屏的电视机放在角落")
                cmds.show_action_hint(player, "对乘务员使用急救技能", "perform 急救 dying_conductor", "对乘务员进行急救")
            end
        end,
        -- 监听返回5号车厢的尝试（回头）
        before_go = function(event_name, room, player, direction, target_id)
            if direction == "west" then
                player:reply("一股巨大的压力从背后传来，车厢开始收缩！")
                player:modify_hp(-3)
                player:modify_san(-math.random(1, 3))
                player:reply("你被强制留在了4号车厢！")
                return false -- 阻止移动
            end
            return true
        end
    }
})

return compartment4.title .. " 加载完成"