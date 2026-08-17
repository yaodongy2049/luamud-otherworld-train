---@module "mud_lib/map/station_hall"
---@description COC跑团车站入口大厅场景

local log = require("mud_os/log")
local Npc = require("mud_lib/npc")
local Room = require("mud_lib/room")
local cmds = require("mud_lib/cmds")

-- 玩家状态枚举
local PlayerState = {
    IDLE = "idle",
    ASKED_NAME = "asked_name",
    ASKED_JOB = "asked_job",
    COMPLETED = "completed"
}

-- 职业数据（根据文档设定）
local job_data = {
    ["消防员"] = {
        job = "退役消防员",
        str = 75,
        con = 70,
        dex = 65,
        int = 45,
        pow = 60,
        app = 45,
        edu = 40,
        san = 60,
        skill = {
            ["侦查"] = 50,
            ["聆听"] = 55,
            ["急救"] = 60,
            ["潜行"] = 65,
            ["话术"] = 35,
            ["灵感"] = 35,
            ["格斗"] = 70
        },
        exclusive = "消防员身份",
        desc = "一位身材魁梧的退役消防员，眼神坚毅，经历过无数生死考验。"
    },
    ["列车员"] = {
        job = "末班电车乘务员",
        str = 40,
        con = 65,
        dex = 55,
        int = 50,
        pow = 45,
        app = 60,
        edu = 55,
        san = 55,
        skill = {
            ["侦查"] = 40,
            ["聆听"] = 60,
            ["急救"] = 70,
            ["潜行"] = 35,
            ["话术"] = 45,
            ["灵感"] = 40,
            ["电车知识"] = 80
        },
        exclusive = "乘务员身份",
        desc = "一位年轻的电车乘务员，眼神中带着疲惫，似乎经历了很多事情。"
    },
    ["记者"] = {
        job = "自由记者",
        str = 50,
        con = 45,
        dex = 60,
        int = 70,
        pow = 55,
        app = 50,
        edu = 65,
        san = 50,
        skill = {
            ["侦查"] = 75,
            ["聆听"] = 50,
            ["急救"] = 30,
            ["潜行"] = 55,
            ["话术"] = 60,
            ["灵感"] = 70,
            ["摄影"] = 65
        },
        exclusive = "记者身份",
        desc = "一位精明干练的记者，眼神敏锐，似乎一直在寻找着什么。"
    }
}

local function handle_idle_state(player)
    player.game_tags.ticket_clerk_state = PlayerState.ASKED_NAME
    player:reply("售票员抬起头，打量了你一番：'啊，是新的乘客...在回答你任何问题前，我需要确认你的身份。你叫什么名字？'")
    return false
end

local function handle_asked_name_state(player, topic)
    local invalid_topics = { ["车票"] = true, ["时间"] = true, ["这里"] = true }
    if invalid_topics[topic] then
        player:reply("售票员皱了皱眉：'请输入你的真实姓名，不要使用这些关键词。'")
        return false
    end
    player.name = topic
    player.game_tags.ticket_clerk_state = PlayerState.ASKED_JOB
    player:reply("售票员记下你的名字：'好的，" .. topic .. "。那么，你的职业是什么？可选的有：消防员、列车员、记者。'")
    return false
end

local function handle_asked_job_state(player, topic)
    local job = topic
    local job_info = job_data[job]

    if not job_info then
        player:reply("售票员皱了皱眉：'抱歉，我没听过这个职业。请从消防员、列车员、记者中选择一个。'")
        return false
    end

    player.core_attrs = {
        str = job_info.str,
        con = job_info.con,
        dex = job_info.dex,
        int = job_info.int,
        pow = job_info.pow,
        app = job_info.app,
        edu = job_info.edu
    }
    player.game_tags.attrs = {
        STR = job_info.str,
        CON = job_info.con,
        DEX = job_info.dex,
        INT = job_info.int,
        POW = job_info.pow,
        APP = job_info.app,
        EDU = job_info.edu,
        SIZ = player.game_tags.attrs and player.game_tags.attrs.SIZ or 50,
        LUK = player.game_tags.attrs and player.game_tags.attrs.LUK or 50
    }
    player.skill = job_info.skill
    player.exclusive = job_info.exclusive
    player.desc = job_info.desc

    player.max_hp = math.floor((job_info.con + job_info.pow) / 2)
    player:set_hp(player.max_hp)

    player:set_san(job_info.san)

    player.game_tags.ticket_clerk_state = PlayerState.COMPLETED

    local tips = {
        ["消防员"] = "售票员若有所思地说：'消防员...在这趟车上，勇气比什么都重要。记住，遇到危险时，不要只顾着自己。'",
        ["列车员"] = "售票员压低声音：'同为列车工作者，我得提醒你，这趟车的路线...不太正常。注意看时刻表，别坐过了站。'",
        ["记者"] = "售票员眼神闪烁：'记者啊...也许你能发现这趟车背后的真相。但有些事情，知道了反而更危险。小心记录。'"
    }
    player:reply(tips[job])
    player:reply("'有时候疯狂的人才能知道真相...'，他的声音后面越来越小。")
    player:reply("【系统】你的身份已确认！你现在是：" .. player.name .. "，" .. job_info.job.. "。输入 hp 可查看技能和状态")
    cmds.show_action_hint(player, "去下一个地点“月台”", "go east", "去月台")

    player:save()
    cmds.exit_dialog_mode(player)

    return false
end

-- 创建售票员NPC
local ticket_clerk = Npc.New("ticket_clerk", "售票员", "一位面容憔悴的中年男子，穿着陈旧的制服，眼神中透着一丝不安。")
ticket_clerk.topics = {
    ["车票"] = "今晚只有一趟末班车了...你确定要上车吗？",
    ["时间"] = "已经是深夜了，下一班车...不知道还会不会来。",
    ["这里"] = "这个车站...已经很久没有正常运营了。"
}
ticket_clerk.listeners = {
    --- 监听ask_about事件，处理售票员问答流程
    ---@param player Investigator 玩家实例
    ask_about = function(event_name, target, player, topic, content)
        if not player.game_tags.ticket_clerk_state then
            player.game_tags.ticket_clerk_state = PlayerState.IDLE
        end

        if player.game_tags.ticket_clerk_state == PlayerState.COMPLETED then
            return true
        end

        if player.game_tags.ticket_clerk_state == PlayerState.IDLE then
            return handle_idle_state(player)
        end

        if player.game_tags.ticket_clerk_state == PlayerState.ASKED_NAME then
            return handle_asked_name_state(player, topic)
        end

        if player.game_tags.ticket_clerk_state == PlayerState.ASKED_JOB then
            return handle_asked_job_state(player, topic)
        end

        return true
    end,
}

-- 创建入口大厅房间
local station_hall = Room.New({
    id = "StationHall",
    title = "车站入口大厅",
    desc = "这是一个老旧的车站大厅，墙壁上的油漆已经斑驳脱落，空气中弥漫着灰尘和铁锈的味道。一盏昏暗的吊灯在天花板上摇晃，发出令人不安的吱呀声。大厅中央有一个售票窗口，里面坐着一位神情疲惫的售票员。大厅东侧有一扇通往月台的门。",
    exits = {
        east = "Platform"
    },
    spown_list = { ticket_clerk },
    listeners = {
        look = function(event_name, room, player, id)
            if player.game_tags.ticket_clerk_state then
                return
            end
            cmds.show_action_hint(player, "和售票员说话", "say 你好 ticket_clerk", "对售票员说 你好")
        end
    }
})

-- 创建月台房间
local platform = Room.New({
    id = "Platform",
    title = "月台",
    desc = "长长的月台延伸向黑暗中，看不到尽头。一列老旧的电车停靠在轨道旁，车窗漆黑一片，不知里面是否有人。月台上空无一人，只有风吹过的声音和远处传来的奇怪声响。",
    exits = {
        west = "StationHall",
        east = "CompartmentSleep" -- 进入后一秒，传送到6号车厢：从睡眠中醒来
    },
    listeners = {
        -- 监听玩家进入月台事件
        after_go = function(event_name, target_room, player, direction, target_id)
            if target_room.id == "Platform" then
                if player.game_tags.ticket_clerk_state ~= PlayerState.COMPLETED then
                    -- 强制返回大厅
                    player:fly_to("StationHall", "售票员的声音从背后传来：'请先到售票窗口确认身份！'\n你老老实实的返回了大厅。")
                    return false
                else
                    player:reply("你踏上了月台，老旧的木板发出令人不安的吱呀声...")
                end
            end
            return true
        end
    }
})

return station_hall.title .. "/" .. platform.title .. " 加载完成"