---@module "mud_lib/npcs/ella_hayes"
---@description 前台接待员艾拉·海耶斯

local Npc = require("mud_lib/npc")
local COC = require("mud_lib/coc/attrs")
local log = require("mud_os/log")
local cmds = require("mud_lib/cmds")

local PlayerState = COC.PlayerState

-- 创建前台接待员 NPC
local ella_hayes = Npc.New("ella_hayes", "艾拉·海耶斯",
    "她常年身着合身的定制藏蓝色女款公务制服，领口别着一枚磨损的黄铜海关徽章，乌黑的长发一丝不苟盘在脑后。肤色偏苍白，眼底带着长期熬夜堆积的淡青乌色，神情淡漠，眉眼间带着习惯性的戒备与倦怠。")
ella_hayes.topics = {
    ["登记"] = "到那边的海关登记员处办理入境登记，需要提供身份证件和如实填写登记表。",
    ["禁酒令"] = "现在全美施行禁酒令，禁止私自携带、藏匿、交易任何酒类，一旦查出后果严重。",
    ["职业介绍所"] = "西侧是职业介绍所，大多是码头搬运、杂工这类苦力活，报酬高的外勤零工背后基本都牵扯灰色勾当。",
    ["大厅"] = "这座大厅已经有几十年历史了，见过无数移民怀揣希望而来，也见过不少人一无所有而去。",
    ["传闻"] = "最近夜间近海船只往来异常频繁，扣押的不明包裹比以往多了一倍..."
}
ella_hayes.listeners = {
    ask_about = function(event_name, target, player, topic, content)
        -- 如果还没完成登记，引导去登记
        if not player.game_tags.customs_state or
            player.game_tags.customs_state < PlayerState.REGISTER_COMPLETED then
            player:reply("艾拉抬眼瞥了你一下：'先去完成入境登记再来问其他事情。海关登记员就在那边柜台。'")
            cmds.show_action_hint(player, "退出和艾拉的对话", "exit", "不说了")
            return false
        end
        return true
    end
}

return ella_hayes