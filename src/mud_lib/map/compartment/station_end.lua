---@module "mud_lib/map/station_end"
---@description 终点站和疯人院场景

local log = require("mud_os/log")
local timer = require("mud_os/timer")
local EventSystem = require("mud_os/event_system")
local Npc = require("mud_lib/npc")
local Room = require("mud_lib/room")
local Item = require("mud_lib/item")


-- 创建火车币
local train_coin = Item.New(
    "train_coin",
    "列车票硬币",
    "一枚用作列车车票的的塑料硬票，上面刻着「墨田电车」的标记",
    false
)

train_coin.listeners = {
    ---@param player Investigator
    look = function(event_name, target, player)
        local naiya_info = {
            "硬币表面浮现出模糊的纹路，似乎是某种古老的符文...",
            "你感到一阵寒意，硬币上隐约刻着'诺亚'二字",
            "硬币发出微弱的光芒，一个声音在你脑海中响起：'回到我身边...'",
            "硬币背面刻着一艘方舟，方舟上站着一个模糊的人影",
            "你突然发现，硬币上的图案似乎在缓缓变化...",
            "一股莫名的力量从硬币中涌出，你感到自己的理智正在流失...",
            "硬币上的纹路组成了一张扭曲的面孔，仿佛在对你微笑"
        }
        local random_info = naiya_info[math.random(#naiya_info)]
        player:reply("当你盯着它看一会后，" .. random_info)
        return true
    end
}

-- 创建终点站房间
local terminal_station = Room.New({
    id = "TerminalStation",
    title = "终点站",
    desc = "这是一个温暖而安全的终点站。明亮的灯光照亮了整个大厅，人来人往，充满了生活气息。几个乘客坐在长椅上休息，远处传来广播的声音。空气中弥漫着咖啡的香气，让人感到安心。",
    exits = {
        north = "CustomsHall"
    },
    spown_list = {},
    listeners = {
        before_go = function(event_name, target_room, player, direction, target_id)
            log.DEBUG("before_go", event_name, target_room, player, direction, target_id)
            if direction == "north" then -- 从《常暗》进入终点站
                player:reply("嘈杂拥挤的人群，把你从噩梦拉回到现实....\n你在一个角落慢慢站起身，脑子里一片混乱。\n")
            end
        end,
        ---监听玩家进入车站事件
        ---@param event_name string
        ---@param direction string
        ---@param target_id string
        ---@return boolean
        after_go  = function(event_name, target_room, player, direction, target_id)
            -- 移除玩家的死亡回调函数
            if player.game_tags and player.game_tags.die then
                for k, v in pairs(player.game_tags.die) do
                    local room = Room.get_world().rooms[k] --[[@class table]]
                    if room and room.logic_funcs then
                        local die_cb = room.logic_funcs[v]
                        EventSystem:remove_listener("die", die_cb, player)
                        player.game_tags.die = nil
                        if player.san > 0 then
                            player:reply("你感到一阵轻松。")
                        end
                    end
                end
                player.game_tags.die = nil
                player:save()
            end
            if player.game_tags.is_touch_naiya then
                -- 延迟 1 秒出提示
                local naya_say = {
                    heart_beat = function(now)
                        player:reply("你忽然听到奈亚的低语：...回来...回来...")
                        timer:del(player.naya_say_id)
                        player.naya_say_id = nil
                        local has_coin = player:search("id", "train_coin")
                        if not has_coin or #has_coin == 0 then
                            player:add_obj(train_coin)
                            player:reply("你下意识的摸了下口袋，好像有一个硬币在里面")
                        end
                    end
                }
                player.naya_say_id = timer:add(naya_say)
            end
            if player.san <= 0 then
                player:fly_to("MentalHospital", "你一下车，周围的乘客满脸惊恐的看着你...不多会，一群穿着白大褂的人冲过来，将你五花大绑地送进了疯人院。")
                return true
            end

            player:reply("【系统】恭喜你完成入门流程，欢迎来到 COC 的世界！")
            return true
        end
    }
})

-- 创建男护士NPC
local male_nurse = Npc.New("male_nurse", "男护士", "一位穿着白色制服的中年男子，眼神呆滞，嘴角挂着诡异的微笑。")
local patient = Npc.New("patient", "患者", "一位精神病患者，他嘟嘟囔囔着不知道在说什么，双手时不时的胡乱挥舞。")

-- 创建疯人院房间
local mental_hospital = Room.New({
    id = "MentalHospital",
    title = "疯人院",
    desc = "这里是一间阴暗潮湿的病房。墙壁上布满了斑驳的污渍，一股刺鼻的消毒水气味扑面而来。房间里只有一张简陋的病床和一个破旧的床头柜。窗外传来阵阵诡异的笑声。",
    exits = {},
    spown_list = { male_nurse },
    avg_cmds_desc = {
        escape = "尝试逃跑，格式：escape"
    },
    avg_cmds = {
        ---@param player Investigator
        ---@param cmds string[]
        escape = function(player, cmds)
            player:reply("你趁男护士不注意，拼命跑出了疯人院...")
            patient.name = "疯狂的" .. player.name
            player.environment:add_obj(patient)
            local mad_you = player.environment:search("name", patient.name)[1] --[[@class Npc]]
            mad_you:say("求求你收下我吧，奈亚大神...")
            player:set_san(10)
            player:fly_to("TerminalStation", "你成功逃到了终点站！")
            player:reply("【系统】恭喜你完成入门流程，欢迎来到 COC 的世界！")
        end
    },
    listeners = {
        ---监听玩家进入事件
        after_go = function(event_name, target_room, player, direction, target_id)
            if target_room.id == "MentalHospital" then
                -- 男护士说话
                local bed_number = math.random(100, 999)
                player:reply("男护士看到你进来，露出诡异的笑容")
                male_nurse:say("又疯一个，" .. player.name .. "，你的床号是 " .. bed_number .. "，不要乱跑哦。")
            end
            return true
        end
    }
})

return terminal_station.title .. "/" .. mental_hospital.title .. " 加载完成"
