---@module "mud_lib/map/state_street"
---@description 1920纽约州街与无名旧书店场景

local Room = require("mud_lib/room")
local Item = require("mud_lib/item")
local cmd_sys = require("mud_lib/cmds")
local EliasThorne = require("mud_lib/npcs/elias_thorne")
local NoahGrant = require("mud_lib/npcs/noah_grant")
local BookOfGreenGod = require("mud_lib/item/book_of_green_god")

local state_street = Room.New({
    id = "StateStreet",
    title = "州街",
    desc =
    "1920年纽约曼哈顿下城的州街（State Street），紧邻鲍灵格林海关与纽约港码头，永远笼罩在一层浑浊的灰雾之中。海风裹挟着海水的咸腥、煤炭燃烧的焦糊味与劣质机油的刺鼻气息，终年不散。街道两侧是老旧的欧式砖石建筑，墙面斑驳起皮。层层叠叠的广告牌、老旧灯牌歪斜悬挂，在微风中发出细碎刺耳的金属吱呀声。几辆老旧的福特T型轿车停靠在路边，远处码头传来模糊的轮船鸣笛声，沉闷、悠远，隔着浓雾传来。有间书店夹在两家破败的杂货铺之间，门面极窄，比周边商铺低矮半尺，像是硬生生挤进街道的异物。店铺门楣上只有一块发黑的老旧木质牌匾，木纹沟壑里沉积着常年的暗色污垢，凑近细看，能隐约看到细碎扭曲的纹路，都是无人认识的古老符号。门板把手是黄铜材质，早已氧化发黑，摸上去没有金属凉意，反而带着一种干涩、黏滞的触感。",
    exits = {
        north = "CustomsHall",
        west = "NamelessBookstore"
    },
    spown_list = { NoahGrant },
    avg_cmds = {
        search = function(this_player, cmds)
            local this_place = this_player.environment --[[@as Room]]
            if not this_place then
                return
            end
            this_player:reply("你仔细搜索了街道周围，发现除了几家破败的杂货铺和那间诡异的书店外，没有其他值得注意的东西。")
        end
    },
    avg_cmds_desc = {
        search = "search：搜索周围环境。"
    },
    listeners = {
        after_go = function(event_name, target_room, player, direction, target_id)
            if target_room.id == "StateStreet" then
                player:reply("你来到了州街，浑浊的灰雾笼罩着整条街道。")
                if not (player.game_tags and (player.game_tags.storm_eye_triggered or player.game_tags.green_god_triggered)) then
                    player:reply("一名气象记录员正盯着一张不断收缩的气压图，像在等待风暴抵达。")
                    cmd_sys.show_action_hint(player, "询问下一章的异象", "say 暴风 noah_grant", "问问诺亚")
                end
            end
            return true
        end,
        before_go = function(event_name, room, player, direction, target_id)
            if direction == "south" or direction == "深入街道" then
                player:reply("前方雾霭浓稠异常，冥冥之中有未知力量禁止你继续深入。")
                return false
            end
            if direction == "west" then
                player:reply("你推开了那扇黄铜把手的木门...")
                return true
            end
            return true
        end
    }
})

local mysterious_bookshelf = Item.New(
    "mysterious_bookshelf",
    "书架",
    "层层叠叠的老旧书架紧贴墙壁、堆叠向黑暗深处，上面摆满了封存的旧书。"
)
mysterious_bookshelf.is_unmov = true

local nameless_bookstore_spown_list = { EliasThorne, mysterious_bookshelf }

local function show_bookstore_guidance(player)
    player:reply("伊莱亚斯·索恩守在书架阴影中；他似乎在等你先问一个问题。")
    cmd_sys.show_action_hint(player, "询问守书人如何开始", "say 帮助 elias_thorne", "问伊莱亚斯")
    cmd_sys.show_action_hint(player, "直接调查可疑书架", "search 书架", "搜索书架")
end

local nameless_bookstore = Room.New({
    id = "NamelessBookstore",
    title = "无名旧书店",
    desc =
    "推门的瞬间没有任何声响，木门无声开合，不会发出吱呀异响，隔绝了外界所有气息。店内空间视觉上极小，踏入后却会感觉内部空间无限延伸，层层叠叠的老旧书架紧贴墙壁、堆叠向黑暗深处。空气中弥漫着陈旧纸张、干墨、腐朽木质混合微量尘土的味道，让人意识恍惚，感官变得迟钝模糊。地面铺着老旧木地板，踩上去无声无息。店内几乎被书籍填满，唯有进门处留出一小块空地。书店主人伊莱亚斯·索恩静静伫立在书架阴影中，垂首静坐，一动不动。",
    exits = {
        east = "StateStreet"
    },
    spown_list = nameless_bookstore_spown_list,
    avg_cmds = {
        search = function(this_player, cmds)
            local target = cmds[2]
            if not target or target == "" then
                this_player:reply("你要搜索什么？书店里最可疑的是墙边那排不断向黑暗延伸的书架。")
                cmd_sys.show_action_hint(this_player, "搜索最深处的书架", "search 书架", "搜索书架")
                return
            end
            if target == "书架" or target == "书籍" then
                this_player.game_tags = this_player.game_tags or {}
                if this_player.game_tags.storm_eye_found then
                    this_player:reply("你已经找到了《暴风之眼》，无需再次搜索。伊莱亚斯在阴影里轻轻点头。")
                else
                    BookOfGreenGod.discover_for_player(this_player)
                    this_player:reply("你在幽深书架之间仔细搜寻，终于找到一本被银灰云纹包围的古籍。它的封面中央像有一只闭合的眼睛——这是《暴风之眼》。")
                    this_player:reply("伊莱亚斯的声音从书架阴影里传来：‘先保存，再决定是否翻开。’")
                end
                cmd_sys.show_action_hint(this_player, "保存当前进度", "save", "保存")
                cmd_sys.show_action_hint(this_player, "阅读《暴风之眼》", "read 暴风之眼", "阅读")
                return
            end
            this_player:reply("你搜索了" .. target .. "，没有发现什么特别的东西。")
        end,
        read = function(this_player, cmds)
            local target = cmds[2]
            if not target or target == "" then
                this_player:reply("你要阅读什么？")
                return
            end
            if target == "暴风之眼" or target == "《暴风之眼》" or target == "绿神" or target == "《绿神》" then
                this_player.game_tags = this_player.game_tags or {}
                if this_player.game_tags.storm_eye_found then
                    BookOfGreenGod.read_for_player(this_player)
                    return
                end
                this_player:reply("你没有找到《暴风之眼》。试着搜索一下书架？")
                return
            end
            this_player:reply("你要阅读什么？")
        end,
        listen = function(this_player, cmds)
            this_player:reply("店内绝对死寂，无任何环境音，但你凝神倾听时，隐约听到无数细碎的低语声，重叠、模糊、无法分辨语种，贴近耳边却找不到声源。")
        end,
        touch = function(this_player, cmds)
            local target = cmds[2]
            if not target or target == "" then
                this_player:reply("你要触碰什么？")
                return
            end
            if target == "门把手" or target == "门" then
                this_player:reply("黄铜门把手早已氧化发黑，摸上去没有金属凉意，反而带着一种干涩、黏滞的触感。")
                return
            end
            if target == "书架" then
                this_player:reply("书架的木质老旧腐朽，摸上去有一种潮湿冰凉的感觉。")
                return
            end
            this_player:reply("你触碰了" .. target .. "，没有什么特别的感觉。")
        end
    },
    avg_cmds_desc = {
        search = "search：搜索书架/翻阅书籍。",
        read = "read：阅读书籍，args=[书籍名称]；示例：read 暴风之眼",
        listen = "listen：聆听周围声音。",
        touch = "touch：触摸物品，args=[目标]"
    },
    listeners = {
        after_go = function(event_name, target_room, player, direction, target_id)
            if target_room.id == "NamelessBookstore" then
                player:reply("你踏入了无名旧书店，外界的声音瞬间消失殆尽。")
                player:reply("店内光线不会跟随你移动，你走动时，身后走过的区域会瞬间沉入彻底黑暗。")
                show_bookstore_guidance(player)
            end
            return true
        end,
        look = function(event_name, room, player, target_id)
            if not target_id or target_id == "" then
                show_bookstore_guidance(player)
            end
        end,
        before_go = function(event_name, room, player, direction, target_id)
            if direction == "east" then
                player:reply("你推开木门，重新回到了州街的灰雾之中。")
            end
            return true
        end,
        say = function(event_name, target_room, player, message)
            local this_place = player.environment --[[@as Room]]
            if not this_place or this_place.id ~= "NamelessBookstore" then
                return true
            end
            if player.temp_status and player.temp_status.last_say_target == "elias_thorne" then
                player:reply("店内低语声突然短暂加重，像是无数窃窃私语在回应你的话语，随后迅速消散，归于沉寂。伊莱亚斯·索恩全程纹丝不动，没有任何动作反馈。")
            end
            return true
        end
    }
})

return state_street.title .. "/" .. nameless_bookstore.title .. " 加载完成"