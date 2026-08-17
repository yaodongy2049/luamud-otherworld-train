---@module "mud_lib/npcs/elias_thorne"
---@description 书店店主伊莱亚斯·索恩（守书人NPC）

local Npc = require("mud_lib/npc")

local EliasThorne = Npc.New("elias_thorne", "伊莱亚斯·索恩",
    "身形清瘦挺拔，长久维持垂首静坐的姿势，一动不动，自你进店伊始，从未抬头、从未动作、从未呼吸起伏。他的面容不可辨识，无人知晓他在此驻守了多少岁月，他不属于州街的时空，只属于这间藏着旧日秘密的书店。")

EliasThorne.topics = {
    ["帮助"] = "伊莱亚斯缓慢抬起一根手指，指向最深处的书架：‘先找，再读。若想知道该找什么，就问“暴风”或“书架”。’",
    ["暴风"] = "他终于开口，声音像从潮湿纸页间挤出：‘眼睛不会出现在封面上；它藏在书架缝隙最安静的地方。用 search 书架。找到它以后，用 read 暴风之眼。’",
    ["书架"] = "伊莱亚斯的指节轻叩木头两下：‘别让书名替你做选择。搜索书架，找到那本被银灰云纹包围的书。’",
    ["准备"] = "‘读它之前，先保存你仍愿意承认的记忆。输入 save。然后，自己决定是否翻开。’"
}

EliasThorne.listeners = {
    look = function(event_name, npc, player)
        player:reply("伊莱亚斯·索恩依旧垂首静坐，一动不动，仿佛一尊凝固的石像。你试图看清他的面容，却发现无论如何都无法辨识他的五官，仿佛有一层无形的迷雾笼罩着他。")
    end,
    ask_about = function(event_name, target, player, topic, content)
        if content == nil then
            player:reply("伊莱亚斯·索恩没有任何回应，店内低语声微微波动了一下，随即恢复平静。你可以试试问他“帮助”、 “暴风”、 “书架”或“准备”。")
            return false
        end
        return true
    end
}

return EliasThorne