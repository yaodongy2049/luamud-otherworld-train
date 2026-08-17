---@module "mud_lib/npcs/arthur_cohen"
---@description 海关登记员亚瑟·科恩

local log = require("mud_os/log")
local Npc = require("mud_lib/npc")
local COC = require("mud_lib/coc/attrs")
local invoke_llm = require("mud_lib/invoke_llm")
local cmds = require("mud_lib/cmds")

local PlayerState = COC.PlayerState

local function generate_attrs_with_llm(player_info, user_id)
    if not IS_LLM_ENABLED then
        return nil
    end

    local prompt = [[
你是COC7版属性生成专家。首要规则：9属性总和严格=460，验算不对自动修正。
第一步：先给出贴合人设的基础属性，单项15-90；第二步：计算9数总和差值，均匀增减各数值补齐至总和460。
角色：]] .. player_info.name ..
        [[ ]] .. player_info.age .. [[岁]] ..
        player_info.gender .. [[，]] .. [[
仅输出压缩无空格JSON
{"results":[{"STR":?,"CON":?,"SIZ":?,"DEX":?,"APP":?,"INT":?,"POW":?,"EDU":?,"LUK":?}]}
]]
    local result = invoke_llm(prompt, "自我介绍是：" .. player_info.self_intro, user_id) --[[@as LLMInputResult]]
    if result and #result.results > 0 then
        return result.results[1]
    end
    log.WARNING("generate_attrs_with_llm: 生成属性失败", result)
    return nil
end

local arthur_cohen = Npc.New("arthur_cohen", "亚瑟·科恩",
    "身着标准藏蓝色厚重海关制服，袖口沾有墨渍与灰尘，肩章略有磨损。体型微胖，面容平庸，常年戴着一副老旧圆框玻璃眼镜。神态麻木慵懒，日复一日重复枯燥登记工作。")
arthur_cohen.topics = {
    ["登记"] = "请先回答我的问题，所有人都必须走这套流程。",
    ["费用"] = "正规入境登记免费，收费都是私下索要小费的违规官员，我这边只做本职工作。",
    ["修改"] = "短时间内可以更正基础信息，但身份、职业这类核心信息修改需要提交审批。"
}
arthur_cohen.listeners = {
    ask_about = function(event_name, target, player, msg, topic_resp)
        if not player.game_tags.customs_state then
            player.game_tags.customs_state = PlayerState.IDLE
        end

        if player.game_tags.customs_state >= PlayerState.REGISTER_COMPLETED then
            if msg == "登记" then
                player:reply("亚瑟抬头看了你一眼：'你的信息已经录入档案了，无需重复登记。'")
                return false
            end
            return true
        end

        if player.game_tags.customs_state == PlayerState.IDLE then
            if msg == "登记" then
                player.game_tags.customs_state = PlayerState.REGISTER_NAME
                player.game_tags.register_info = {}
                player:reply("亚瑟抬了抬眼皮，推了推鼻梁上的旧眼镜，将空白登记表推到你面前：'要办理入境登记？那就配合我回答问题。首先，告诉我你的全名。'")
            else
                player:reply("亚瑟头也不抬：'先完成登记再说其他事情。'")
            end
            return false
        end

        if player.game_tags.customs_state == PlayerState.REGISTER_NAME then
            local invalid_names = { ["登记"] = true, ["费用"] = true, ["修改"] = true }
            if invalid_names[msg] then
                player:reply("亚瑟皱了皱眉：'请输入你的真实姓名，不要使用这些关键词。'")
                return false
            end
            player.name = msg
            player.game_tags.register_info.name = msg
            player.game_tags.customs_state = PlayerState.REGISTER_AGE
            player:reply("亚瑟记下你的名字，继续问道：'你的实际年龄与性别？'")
            return false
        end

        if player.game_tags.customs_state == PlayerState.REGISTER_AGE then
            local age = string.match(msg, "(%d+)")
            local gender = nil

            if string.find(msg, "[男mMaleMALE]") then
                gender = "男"
            elseif string.find(msg, "[女fFemaleFEMALE]") then
                gender = "女"
            end

            player.game_tags.register_info.age = age or "未知"
            player.game_tags.register_info.gender = gender or "男"
            player.game_tags.customs_state = PlayerState.REGISTER_SELF_INTRO
            player:reply("亚瑟点点头，继续问道：'请简单做个自我介绍，说明你的籍贯、职业，以及入境这座城市的目的。'")
            return false
        end

        if player.game_tags.customs_state == PlayerState.REGISTER_SELF_INTRO then
            player.game_tags.register_info.self_intro = msg
            player.game_tags.customs_state = PlayerState.REGISTER_STAY_TIME
            player:reply("亚瑟快速记录着，然后问道：'计划在境内停留多长时间？'")
            return false
        end

        if player.game_tags.customs_state == PlayerState.REGISTER_STAY_TIME then
            player.game_tags.register_info.stay_time = msg

            player:reply("亚瑟低头用蘸水钢笔快速誊写所有信息，笔尖划过纸张发出沙沙声响。")

            local attrs
            if IS_LLM_ENABLED then
                attrs = generate_attrs_with_llm(player.game_tags.register_info, player.user_id)
                -- 验算是否符合规则
                if attrs then
                    local total = 0
                    for k, attr in pairs(attrs) do
                        log.DEBUG("Checking attrs "..k..":", attr)
                        if attr < 15 then --小于下限
                            local less = 15 - attr
                            attrs[k] = 15
                        end
                        if attr > 90 then --大于上限
                            local large = attr - 90
                            attrs[k] = 90
                        end
                        total = total + attrs[k]
                    end
                    -- 总和不对，挨个扣减
                    local adj_p = 460 - total
                    local avg_add = math.floor(adj_p/9)
                    if avg_add ~= 0 then
                        log.DEBUG("Adjusting point:", adj_p, avg_add)
                        for k, attr in pairs(attrs) do
                            attrs[k] = attr + avg_add
                        end

                    end
                end
            end

            if not attrs then
                local seed = string.len(msg) + (string.byte(msg, 1) or 0)
                attrs = COC.generate_attrs(seed)
            end

            player.game_tags.attrs = attrs

            -- 从 game_tags.attrs 生成 core_attrs（不再单独保存）
            player.core_attrs = {
                str = attrs.STR,
                con = attrs.CON,
                dex = attrs.DEX,
                int = attrs.INT,
                pow = attrs.POW,
                app = attrs.APP,
                edu = attrs.EDU
            }

            player:set_san(attrs.POW)

            player.max_hp = COC.calculate_hp(attrs)
            player:set_hp(player.max_hp)

            player.game_tags.customs_state = PlayerState.REGISTER_COMPLETED

            player.desc = player.game_tags.register_info.self_intro

            player:reply("亚瑟抬头看向你：'信息已录入海关档案。再次提醒你，遵守美利坚联邦法律，严格恪守禁酒令。'")
            player:reply("【系统】你的基础属性已生成！")
            player:reply("力量: " .. attrs.STR .. " | 体质: " .. attrs.CON .. " | 体型: " .. attrs.SIZ)
            player:reply("敏捷: " .. attrs.DEX .. " | 外貌: " .. attrs.APP .. " | 智力: " .. attrs.INT)
            player:reply("意志: " .. attrs.POW .. " | 教育: " .. attrs.EDU .. " | 幸运: " .. attrs.LUK)
            player:reply("HP: " .. player.max_hp .. " | SAN: " .. player.san)
            player:reply("【提示】你现在可以前往西侧职业介绍区，向吉米·巴洛发起 '介绍工作' 话题选择职业。")

            player:save()
            cmds.exit_dialog_mode(player)
            return false
        end

        return false
    end
}

return arthur_cohen