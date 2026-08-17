---@module "mud_lib/map/compartment6"
---@description COC跑团6号车厢场景（起始车厢）

local log = require("mud_os/log")
local EventSystem = require("mud_os/event_system")
local Room = require("mud_lib/room")
local Item = require("mud_lib/item")
local cmds = require("mud_lib/cmds")
local Casebook = require("mud_lib/casebook")
local MaraVane = require("mud_lib/npcs/mara_vane")

local TRAIN_CASE_ID = "otherworld_train"
local function start_train_case(player)
    local case = Casebook.start_case(player, TRAIN_CASE_ID, "通往异世界的列车", "你在一列不该存在的末班列车上醒来。理解规则、收集线索并抵达终点。")
    if not case.objective or case.objective == "" then
        Casebook.set_objective(player, TRAIN_CASE_ID, "调查6号车厢的便签、示意图与旅客玛拉，再向东前进。")
    end
end

-- 创建便签物品
local note = Item.New(
    "mysterious_note",
    "神秘便签",
    "一张皱巴巴的便签纸，上面写着：「只管前进吧！已经没有退路了。」",
    false
)
note.listeners = {
    look = function(event_name, item, player)
        start_train_case(player)
        player:reply("你仔细查看便签：")
        player:reply("正面写着：「只管前进吧！已经没有退路了。」")

        -- 根据玩家职业触发不同效果
        if player.exclusive == "记者身份" then
            player:reply("你凭借敏锐的观察力，发现便签背面有微小的扭曲眼睛图案...")
            player:modify_san(-1)
            player:reply("同时你解读出隐藏的信息：「千万别往车后面走，巨口在等着你」")
        else
            local roll = math.random(1, 100)
            if roll <= player.skill["侦查"] then
                player:reply("你发现便签背面有模糊的字迹：「...别去后..厢...巨口...」")
            else
                player:reply("便签背面似乎什么都没有。")
            end
        end
        Casebook.add_clue(player, TRAIN_CASE_ID, "mysterious_note", "神秘便签", "便签警告：不要前往车后；前方存在被刻意隐瞒的危险。")
        Casebook.set_objective(player, TRAIN_CASE_ID, "查看车门旁的电车示意图，并向玛拉询问列车规则。")
    end
}

-- 创建电车示意图物品
local map = Item.New(
    "train_map",
    "电车示意图",
    "一张被部分涂抹的电车示意图，能模糊看到车厢编号。",
    false
)
map.is_unmov = true
map.listeners = {
    look = function(event_name, item, player)
        start_train_case(player)
        player:reply("你查看这张示意图，上面标注着7节车厢的位置，但部分区域被涂黑了。")
        if player.exclusive == "乘务员身份" then
            player:reply("凭借你的电车知识，你认出3号车厢的电路开关位置在左侧扶手下方。")
        end
        Casebook.add_clue(player, TRAIN_CASE_ID, "train_map", "电车示意图", "列车共有7节车厢；后方被涂黑，前方路线仍可继续调查。")
        local casebook_state = player.game_tags and player.game_tags.casebook
        local train_case = casebook_state and casebook_state.cases and casebook_state.cases[TRAIN_CASE_ID]
        if train_case and train_case.clues and train_case.clues.mara_rules then
            Casebook.set_objective(player, TRAIN_CASE_ID, "已理解基本规则。确认风险后向东前进：go east。遇到阻碍时用 journal 回看线索。")
        else
            Casebook.set_objective(player, TRAIN_CASE_ID, "向玛拉询问“理智”或“帮助”，理解列车内的生存规则。")
        end
    end
}

local corpse = Item.New(
    "corpse",
    "尸体",
    "一具尸体，冷冰冰的躺在地上。",
    false
)
corpse.is_unmov = true

local function die_cb(event_name, dead_char)
    local player = dead_char --[[@as Investigator]]
    corpse.name = player.name .. "的尸体"
    player.environment:add_obj(corpse)
    local t = player:fly_to("Compartment6")

    -- 重置玩家状态
    player:set_hp(player.max_hp)
    player.equipment = {}
    for _, item in pairs(player.equipment) do
        item:leave()
        item:dispose()
    end

    player:save()
    player:reply("...你浑身酸软，头痛欲裂的醒来。")
end

-- 创建CompartmentSleep房间（玩家上车后睡着的房间）
local compartment_sleep = Room.New({
    id = "CompartmentSleep",
    title = "末班列车",
    desc = "你感到一阵莫名的困倦，眼皮越来越沉重...意识逐渐模糊，似乎陷入了沉睡...",
    exits = {},
    logic_funcs = {
        die_cb = die_cb
    },
    listeners = {
        -- 监听玩家进入事件，1秒后传送到Compartment6
        after_go = function(event_name, room, player)
            player:reply("一股温暖的睡意席卷了你，你不由自主地闭上了眼睛...")
            EventSystem:register_listener("die", die_cb, player)
            -- 记录死亡事件（game_tags表会存盘），key 是房间id，value 是房间对象的 logic_funcs 表中 value 对应的函数对象
            player.game_tags.die = {
                CompartmentSleep = "die_cb"
            }

            -- 使用timer延迟1秒后传送
            local timer = require("mud_os/timer")
            local auto_go = {
                interval = 2,
                heart_beat = function(now)
                    player:fly_to("Compartment6", "...你在一阵颠簸中醒来。")
                    timer:del(player.auto_go_id)
                    cmds.show_action_hint(player, "查看周围环境", "look", "看看")
                end
            }
            player.auto_go_id = timer:add(auto_go)
        end
    }
})

-- 创建Compartment6房间（起始车厢）
local compartment6 = Room.New({
    id = "Compartment6",
    title = "6号车厢",
    desc = "这是一节老旧的电车车厢，座椅上覆盖着一层灰尘。车厢内光线昏暗，只有窗外透进的微弱光线。一张皱巴巴的便签纸掉在地上，车门旁边似乎贴着什么东西。",
    exits = {
        east = "Compartment5",
        west = "Compartment7"
    },
    spown_list = { MaraVane },
    listeners = {
        ---监听玩家观察事件
        ---@param room Room 目标房间
        look = function(event_name, room, player, target_id)
            start_train_case(player)
            player:reply("你仔细观察车厢：")
            player:reply("- 车厢向西延伸，但似乎被黑暗笼罩...")
            if not room:has_obj("id", note.id) and not player:has_obj("id", note.id) then
                room:add_obj(note)
            end
            if room:has_obj("id", note.id) then
                player:reply("- 地上有一张便签纸；玛拉的目光在它上面停留了一瞬。")
                cmds.show_action_hint(player, "捡起神秘便签", "get mysterious_note", "捡起便签")
            end
            if not room:has_obj("id", map.id) then
                room:add_obj(map)
            end
            if room:has_obj("id", map.id) then
                player:reply("- 车门旁贴着一张示意图，灰尘下能辨认出前方车厢的编号。")
                cmds.show_action_hint(player, "查看电车示意图", "look train_map", "看示意图")
            end
            if room:has_obj("id", "mara_vane") then
                player:reply("- 靠窗坐着一名抱着坏怀表的旅客。她先看向便签，又指了指示意图，像是在等你先弄懂规则。")
                cmds.show_action_hint(player, "向玛拉询问列车规则", "say 理智 mara_vane", "问问玛拉")
                cmds.show_action_hint(player, "查看全部可问话题", "say 帮助 mara_vane", "请玛拉说明")
            end
            if player:has_obj("id", note.id) then
                player:reply("- 便签已经在你手中；别急着前进，先用 look mysterious_note 读完它。")
                cmds.show_action_hint(player, "阅读神秘便签", "look mysterious_note", "读便签")
            end
            if player:has_obj("id", note.id) and room:has_obj("id", map.id) then
                player:reply("- 示意图仍贴在车门旁；它能告诉你该往哪里走。")
                cmds.show_action_hint(player, "查看电车示意图", "look train_map", "看示意图")
            end
        end,
        -- 监听前往7号车厢的尝试（回头）
        before_go = function(event_name, room, player, direction, target_id)
            if direction == "west" then
                player:reply("一股寒意从背后袭来，你感到莫名的恐惧...")
                local roll = math.random(1, 100)
                log.DEBUG("roll: " .. roll .. "，灵感: " .. player.skill["灵感"])
                if roll <= player.skill["灵感"] then
                    player:reply("你察觉到后方空间正在扭曲，无法前进！")
                    player:modify_san(-1)
                else
                    player:reply("黑暗似乎伸出了无形的手，抓住了你的衣角！")
                    local ls = math.random(1, 3)
                    player:modify_san(-ls)
                end
                player:reply("你被强制留在了原地。")
                return false -- 阻止移动
            end
            return true
        end
    }
})

return compartment_sleep.title .. "/" .. compartment6.title .. " 加载完成"