---@module "mud_lib/npcs/mara_vane"
---@description 《通往异世界的列车》列车教学NPC：失忆旅客玛拉·维恩

local Npc = require("mud_lib/npc")
local Casebook = require("mud_lib/casebook")

local TRAIN_CASE_ID = "otherworld_train"

local MaraVane = Npc.New(
    "mara_vane",
    "玛拉·维恩",
    "一名裹着褪色旅行斗篷的年轻旅客，怀中抱着一只没有指针的怀表。她总在看向窗外，却像在聆听车厢深处某种并不存在的潮声。"
)

MaraVane.topics = {
    ["理智"] = "玛拉压低声音：‘他们把它写作 SAN。那不是勇气，而是你还能把眼前所见称作现实的余量。SAN 越低，列车越容易替你解释世界。’她用怀表轻点地上的便签：‘先把它收起来：get mysterious_note；再看清它：look mysterious_note。车门旁的示意图也值得看一眼：look train_map。’",
    ["伤势"] = "玛拉看了一眼你发白的指节：‘HP 是身体剩下的余温。它耗尽时，你会被扔回醒来的地方；别把每一次醒来都当成恩赐。’",
    ["检定"] = "她用指甲在窗雾上写下几笔：‘要动用本事，就输入 perform <技能> [目标]。不确定时先 look；看清楚，往往比逞强活得久。’",
    ["逃跑"] = "‘这里的怪物不在乎你是否勇敢。若战斗失控，输入 flee；能离开，就是另一种胜利。’",
    ["存档"] = "玛拉合上那只坏掉的怀表：‘记忆会被列车改写。想停下时输入 save，让你此刻所在的位置和选择留下来。’",
    ["列车"] = "‘这不是开往某座城市的列车。它只负责把人送到原本不该抵达的世界边缘。前方的每节车厢，都是一堂代价不同的课。先调查眼前的便签和示意图；准备好后，向东走：go east。’",
    ["帮助"] = "玛拉把坏怀表递近了一寸：‘你可以问我“理智、伤势、检定、逃跑、存档、列车”。若不知道怎么开始，就先输入 say 理智 mara_vane。列车不会奖励鲁莽。’"
}

MaraVane.listeners = {
    look = function(event_name, npc, player)
        player:reply("玛拉·维恩的怀表没有指针，表盖内侧却刻着一行细字：‘不要把醒来误认为安全。’")
    end,
    ask_about = function(event_name, npc, player, topic, topic_content)
        if topic == "理智" or topic == "帮助" or topic == "列车" then
            Casebook.start_case(player, TRAIN_CASE_ID, "通往异世界的列车", "你在一列不该存在的末班列车上醒来。理解规则、收集线索并抵达终点。")
            Casebook.add_clue(player, TRAIN_CASE_ID, "mara_rules", "玛拉的列车规则", "SAN 表示对现实的锚定；HP 耗尽会被送回醒来的地方；战斗失控时可以 flee。")
            Casebook.set_objective(player, TRAIN_CASE_ID, "确认便签与示意图后，向东进入下一节车厢；遇到危险时优先观察并保留 flee 作为退路。")
        end
    end
}

return MaraVane
