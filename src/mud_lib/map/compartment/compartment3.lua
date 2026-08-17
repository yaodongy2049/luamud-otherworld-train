---@module "mud_lib/map/compartment3"
---@description COC跑团3号车厢场景（怪物车厢）

local log = require("mud_os/log")
local timer = require("mud_os/timer")
local Room = require("mud_lib/room")
local Monster = require("mud_lib/monster")
local Item = require("mud_lib/item")
local cmds = require("mud_lib/cmds")
local Casebook = require("mud_lib/casebook")
local command = require("mud_os/command")

local TRAIN_CASE_ID = "otherworld_train"
local function ensure_train_case(player)
    return Casebook.start_case(player, TRAIN_CASE_ID, "通往异世界的列车", "你在一列不该存在的末班列车上醒来。理解规则、收集线索并抵达终点。")
end
local llm_cmd = require("mud_lib/llm_cmd")

-- 创建电路开关
local circuit_switch = Item.New(
    "circuit_switch",
    "电路开关",
    "一个隐藏在扶手下方的电路开关，看起来可以控制车厢灯光。你可以试试拨动它（toggle）。"
)
circuit_switch.is_unmov = true

local clicker = Monster.New("clicker", "盲眼爬行怪物", "它无目白肤畸躯，肢骨外翻，贴地循声蠕行，喉间不断发出咔哒异响") --[[@as Investigator]]
clicker.max_hp = 20
clicker:set_hp(clicker.max_hp)

clicker.core_attrs = {
    str = 60,
    con = 55,
    dex = 70,
    int = 10,
    pow = 40,
    app = 5,
    edu = 0
}

clicker.skill = {
    ["聆听"] = 90,
    ["格斗"] = 30,
    ["潜行"] = 60
}

-- 怪物的攻击命中消息
clicker.attack_msg = {
    "%s猛地扑向%s，狠狠咬住了对方的腿！",
    "%s尖叫着冲向%s，锋利的牙齿深深刺入手臂！",
    "%s凶猛地一跃，爪子狠狠抓向%s的脸！",
    "%s低吠着逼近%s，突然一口咬在脚踝上！"
}

-- 怪物的未命中消息
clicker.miss_msg = {
    "%s扑向%s，却被灵巧地躲开了。",
    "%s尖叫着冲过来，却扑了个空，差点摔倒。",
    "%s张口就咬，但是%s及时后退避开。",
    "%s猛地跃起，却只差一点点就能碰到%s。"
}

-- 怪物的受击消息
clicker.hurt_msg = {
    "%s发出一声呜咽，但看起来毫发无损。",
    "%s被击中，愤怒地咆哮着。",
    "%s惨叫一声，后退了几步。",
    "%s鲜血淋漓，却更加疯狂地扑来。",
    "%s发出一声凄厉的哀嚎，倒在了地上。"
}

clicker.listeners = {
    ---监听死亡事件，打开东门
    die = function(event_name, dead_char)
        local room = dead_char.environment --[[@as Room]]
        room.exits["east"] = "Compartment2"
        room.channel:say("【提示】通向下一个车厢的道路已打开，你可以通过了！")
        room.channel:say("【提示】出口将在30秒后关闭！")

        -- 30秒后关闭出口并清理怪物
        local close_exit = {
            st_time = os.time()
        }
        -- 一次性的定时事件，不放到怪物对象身上了，需要注意 heart_beat 时方法，第一个参数是 self
        close_exit.heart_beat = function(self, now)
            if now - close_exit.st_time < 30 then
                return
            end
            if room.exits["east"] == "Compartment2" then
                room.exits["east"] = nil
                -- 广播消息给房间内的玩家
                if room.channel then
                    room.channel:say("身后的通道开始扭曲，最终关闭了！")
                end
            end
            -- 清理死亡的怪物
            if room:has_obj("id", "clicker") then
                local dead_monster = room:search("id", "clicker")[1]
                dead_monster:leave()
                dead_monster:dispose()
            end
            if close_exit.timer_id then
                timer:del(close_exit.timer_id)
            end
        end
        close_exit.timer_id = timer:add(close_exit) -- 30秒后执行
    end
}

---@param room Room
---@param player Investigator
---@param skill_level number
local perform_search = function(room, player, skill_level)
    ensure_train_case(player)
    local roll = math.random(1, 100)
    if roll <= skill_level - (player.exclusive == "乘务员身份" and 0 or 20) then
        player:reply("你在左侧扶手下方找到了一个电路开关！")
        room:add_obj(circuit_switch)
        Casebook.add_clue(player, TRAIN_CASE_ID, "circuit_switch", "3号车厢电路开关", "左侧扶手下方藏有电路开关；开灯会吸引怪物，但能降低潜行难度。")
        Casebook.set_objective(player, TRAIN_CASE_ID, "可以 toggle circuit_switch 开灯后 perform 潜行；也可保留黑暗，谨慎前进。")
    else
        player.game_tags = player.game_tags or {}
        player.game_tags.dark_carriage_search_attempts = (player.game_tags.dark_carriage_search_attempts or 0) + 1
        if player.game_tags.dark_carriage_search_attempts >= 2 then
            player:reply("你在黑暗里反复摸索，手指终于碰到扶手下方冰冷的金属边缘——一个电路开关。")
            room:add_obj(circuit_switch)
            Casebook.add_clue(player, TRAIN_CASE_ID, "circuit_switch", "3号车厢电路开关", "连续调查后发现开关位于左侧扶手下方；它会提高潜行把握，但会惊动怪物。")
            Casebook.set_objective(player, TRAIN_CASE_ID, "拨动开关（toggle circuit_switch）或直接 perform 潜行。失败不会封死主线，但会付出代价。")
        else
            player:reply("在黑暗中，你什么也没找到。再调查一次，或选择直接 perform 潜行。")
            Casebook.record_setback(player, TRAIN_CASE_ID, "黑暗阻碍调查", "第一次侦查没有找到开关；环境没有封死你。", "可再次 perform 侦查，或直接 perform 潜行。")
        end
    end
end

---@param player Investigator
local perform_flee = function(player)
    ensure_train_case(player)
    local room = player.environment --[[@as Room]]

    if not player.is_in_combat then
        player:reply("你不在战斗状态，不需要逃跑！")
        return
    end

    if not room:has_obj("id", "clicker") then
        player:reply("周围没有活着的怪物，你不需要逃跑。")
        return
    end

    local dex = player.core_attrs and player.core_attrs.dex or 50
    local roll = math.random(1, 100)
    local success_threshold = dex // 2

    player:reply("逃跑判定：" .. roll .. "/" .. success_threshold)

    if roll < success_threshold then
        player:fly_to("Compartment2", "你拼尽全力，成功逃进了2号车厢！")
        command:process_command(player.user_id, "look")
        player.is_in_combat = false
        player.fright_list = {}
        Casebook.record_setback(player, TRAIN_CASE_ID, "从盲眼爬行怪物前脱身", "你放弃了强行穿过3号车厢，保住了生命与已收集的线索。", "恢复后可回看 journal，准备更高的潜行、侦查或战斗方案。")
    else
        player:reply("逃跑失败！怪物挡住了你的去路！")
        Casebook.record_setback(player, TRAIN_CASE_ID, "逃跑失败", "怪物仍在追击；失败不会删除案件进度。", "可再次输入 flee，或使用 kill clicker 正面战斗。")
    end
end

---@param room table
---@param player Investigator
---@param skill_level number
local perform_sneak = function(room, player, skill_level)
    ensure_train_case(player)
    if player.is_in_combat then
        player:reply("战斗中无法使用潜行！")
        player:reply("你可以尝试使用逃跑指令（flee）逃离这里！")
        return
    end

    local roll = math.random(1, 100)
    local difficulty = 60

    -- 根据条件调整难度
    if room.lights_on then
        difficulty = difficulty - 30 -- 灯光吸引怪物，潜行更简单
    end
    if player.exclusive == "乘务员身份" then
        difficulty = difficulty - 30
    elseif player.exclusive == "记者身份" then
        difficulty = difficulty - 15
    elseif player.exclusive == "消防员身份" then
        difficulty = difficulty - 10
    end

    local threshold = skill_level - difficulty
    local context = "玩家在漆黑的3号车厢中尝试尽量不发出声音的潜行穿过，有盲眼怪物"

    if roll <= threshold then
        local desc = llm_cmd.describe_skill_result(roll, threshold, context, player.user_id)
        local message = desc or "你屏住呼吸，小心翼翼地穿过了车厢..."
        player:fly_to("Compartment2", message)
    else
        if not room:has_obj("id", "clicker") then
            local desc = llm_cmd.describe_skill_result(roll, threshold, context, player.user_id)
            local message = desc or "你不小心发出了声响！"
            player:reply(message)
            player:reply("一只盲眼的爬行怪物从黑暗中扑了出来！")
            Casebook.record_setback(player, TRAIN_CASE_ID, "潜行惊动怪物", "潜行失败带来了 SAN 与 HP 代价，但并未终结案件。", "立即 flee 保命，或输入 kill clicker 战斗；之后可通过 journal 调整策略。")
            player:modify_san(-math.random(1, 3))
            player:modify_hp(-3)
            room:add_obj(clicker)
            local enemy = room:search("id", "clicker")[1]
            player:reply("你眼看着" .. enemy.name .. "向你扑了过来！")
            enemy:attack(player)
            cmds.show_action_hint(player, "尝试逃离战斗", "flee", "逃跑")
        else
            local desc = llm_cmd.describe_skill_result(roll, threshold, context, player.user_id)
            player:reply(desc or "你在车厢里瞎摸一气，并没有找到出口。")
        end
    end
end



-- 创建3号车厢房间
local compartment3 = Room.New({
    id = "Compartment3",
    title = "3号车厢",
    desc = "这节车厢一片漆黑，伸手不见五指。你能感觉到空气中弥漫着一股腐臭的气息，耳边传来令人不安的滴答声。",
    exits = {
        west = "Compartment4"
    },
    avg_cmds_desc = {
        toggle = "拨动电路开关，格式：toggle <目标>",
        flee = "逃跑，格式：flee 或 逃跑（战斗中使用）"
    },
    avg_cmds = {
        ---@param player Investigator
        ---@param cmds string[]
        toggle = function(player, cmds)
            if #cmds == 0 then
                player:reply("你需要指定要操作的物品。")
                return
            end
            local room = player.environment --[[@as Room]]
            local targets = room:resolve_content(cmds[2], player.user_id) --[[@as Item[] ]]
            if #targets == 0 or targets[1].id ~= circuit_switch.id then
                player:reply("你没有找到指定的物品。")
                return
            end
            player:reply("你拨动了开关！")
            player:reply("车厢的灯短暂亮起，同时兹拉兹拉作响，随后你听到了远处传来的奇怪声响...")
            room.desc = "这节车厢除了一盏昏黄的灯忽闪忽灭、兹拉作响，其余地方伸手不见五指。你能感觉到空气中弥漫着一股腐臭气息，耳边传来令人不安的滴答声。"

            -- 开灯会吸引怪物，但提供潜行优势
            ---@diagnostic disable-next-line: inject-field
            room.lights_on = true
            player:reply("【提示】灯发出的声音吸引了怪物的注意，你可以趁机潜行通过！")
        end,
        ---@param player Investigator
        ---@param cmds string[]
        flee = function(player, cmds)
            perform_flee(player)
        end,
    },
    listeners = {
        after_go = function(event_name, room, player)
            player:reply("你进入了一片黑暗...")
            player:modify_san(-math.random(1, 3))
            player:reply("【系统】你需要潜行通过这节车厢！")
        end,
        look = function(event_name, room, player)
            if not room.exits["east"] and not room:has_obj("id", "clicker") then
                player:reply("黑暗中，你隐约看到前方有什么东西在移动...")
            end
        end,
        ---监听玩家在5号车厢的 perform 命令
        ---@param player Investigator
        perform = function(event_name, target, player, skill_name, skill_level)
            if skill_name == "侦查" then
                perform_search(target, player, skill_level)
                return true
            end
            if skill_name == "潜行" then
                perform_sneak(target, player, skill_level)
                return true
            end
            player:reply("你使用了" .. skill_name .. "，但眼前依然一片黑暗。")
            return true
        end,
        -- 监听返回4号车厢的尝试
        before_go = function(event_name, room, player, direction, target_id)
            if direction == "west" then
                player:reply("身后的黑暗中传来了怪物的声音...")
                player:reply("你不敢回头，只能继续前进！")
                return false -- 阻止移动
            end
            return true
        end
    }

})





return compartment3.title .. " 加载完成"