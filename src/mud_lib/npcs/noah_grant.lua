---@module "mud_lib/npcs/noah_grant"
---@description 《暴风之眼》章节铺垫NPC：气象记录员诺亚·格兰特

local Npc = require("mud_lib/npc")

local NoahGrant = Npc.New(
    "noah_grant",
    "诺亚·格兰特",
    "一名穿旧雨衣的气象记录员，脚边放着被海雾浸湿的皮箱。他反复翻看一张气压图，图上的同心圆正缓慢向州街中心收拢。"
)

NoahGrant.topics = {
    ["暴风"] = "诺亚把气压图压在掌下：‘那不是天气。风暴的中心从不移动，移动的是靠近它的人。有人把它称作《暴风之眼》。’",
    ["书店"] = "‘西边那间旧书店没有招牌，却总能替迷路的人准备一本恰好读得懂的书。别急着翻页；有些章节会先阅读你。’",
    ["准备"] = "‘进入未知之前，先看清四样东西：你的 HP、SAN、技能与出口。save 不是护身符，但能让你不必从头回忆。’",
    ["调查"] = "‘这里的线索不会主动追你。look 能揭开表面，search 能翻出藏处，perform 侦查 则要付出一点运气。’",
    ["去处"] = "‘先在州街熟悉雾的方向。等书店里的风声真正吹出来，你自然会知道下一章的门在哪里。’"
}

NoahGrant.listeners = {
    look = function(event_name, npc, player)
        player:reply("诺亚·格兰特在气压图边缘圈出一个墨色旋涡，旁边写着：‘风暴之眼——观测中。’")
    end
}

return NoahGrant
