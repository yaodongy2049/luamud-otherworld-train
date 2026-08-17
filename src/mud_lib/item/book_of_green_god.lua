---@module "mud_lib/item/book_of_green_god"
---@description 禁忌典籍《暴风之眼》物品模块（保留旧模块名以兼容既有存档）

local Item = require("mud_lib/item")
local Casebook = require("mud_lib/casebook")

local STORM_CASE_ID = "storm_eye"

local BookOfGreenGod = Item.New(
    "book_of_green_god",
    "《暴风之眼》",
    "书籍封面被一圈褪色的银灰云纹包围，中央像有一只闭合的眼睛。书页封存紧实，靠近时能听见遥远风暴在纸间翻涌。"
)

BookOfGreenGod.listeners = {
    before_get = function(event_name, item, player)
        player:reply("店内所有细碎低语声瞬间骤停，像有一阵风从书页背后掠过。它不允许被带走，但会等待你再次阅览。")
        return false
    end
}

---为当前玩家记录书店发现；不依赖房间是否已有共享书籍对象。
---@param player Investigator
function BookOfGreenGod.discover_for_player(player)
    player.game_tags = player.game_tags or {}
    player.game_tags.storm_eye_found = true
    Casebook.start_case(player, STORM_CASE_ID, "暴风之眼", "州街的无名旧书店藏着一本不允许带走的禁忌典籍。")
    Casebook.add_clue(player, STORM_CASE_ID, "storm_eye_book", "《暴风之眼》", "银灰云纹包围的古籍拒绝离开书店；伊莱亚斯要求你先保存，再决定是否翻阅。")
    Casebook.set_objective(player, STORM_CASE_ID, "输入 save 保存进度，然后输入 read 暴风之眼 阅读禁书。")
end

---让当前玩家阅读章节入口；可由房间命令直接调用。
---@param player Investigator
function BookOfGreenGod.read_for_player(player)
    BookOfGreenGod.discover_for_player(player)
    player:reply("你翻开《暴风之眼》。纸页上的云线骤然旋转，遥远的雷声穿过书脊：风暴尚未抵达，但它已经记住了你的名字。")
    player:reply("【章节预告】《暴风之眼》正在观测中；你已留下进入下一章的印记。")
    player.game_tags.storm_eye_triggered = true
    -- 保留旧标记，避免已创建角色的历史进度失效。
    player.game_tags.green_god_triggered = true
    Casebook.set_status(player, STORM_CASE_ID, "completed")
    Casebook.set_objective(player, STORM_CASE_ID, "章节入口已记录。下一部《暴风之眼》副本开放后，可从线索册继续追踪。")
end

function BookOfGreenGod:start()
    Item.start(self)
    self["read"] = function(_, this_player)
        BookOfGreenGod.read_for_player(this_player)
    end
end

return BookOfGreenGod
