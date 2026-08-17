---@module "tests/cases/state_street"
---@description 州街/无名旧书店场景测试

---州街场景测试集合
---@param TF TestFramework 测试框架实例
return function(TF)
    local login = require("mud_lib/login")
    local Room = require("mud_lib/room")

    -- 辅助函数：将玩家传送到指定房间
    local function fly_player_to(client, room_id)
        local player = login.session_pool[client.user_id]
        TF.assert(player ~= nil, "玩家应已登录")
        player:fly_to(room_id)
        TF.drain_pending_timers()
    end

    -- 辅助函数：清理房间中可能残留的绿神书（测试之间状态隔离）
    local function clear_book_of_green_god()
        local world = Room.get_world()
        local function remove_book_from(room)
            if room and room.content then
                for i = #room.content, 1, -1 do
                    local obj = room.content[i]
                    if obj and obj.id == "book_of_green_god" then
                        obj:leave()
                    end
                end
            end
        end
        if world and world.rooms then
            remove_book_from(world.rooms["NamelessBookstore"])
            remove_book_from(world.rooms["StateStreet"])
        end
        for _, player in pairs(login.session_pool) do
            if player.content then
                for i = #player.content, 1, -1 do
                    local obj = player.content[i]
                    if obj and obj.id == "book_of_green_god" then
                        obj:leave()
                    end
                end
            end
        end
    end

    -- 州街场景 - 初始状态与search命令
    TF.run_test("州街-初始状态与search", function()
        clear_book_of_green_god()
        local c = TF.register_user("statestreet_" .. os.time())
        fly_player_to(c, "StateStreet")
        
        TF.send(c, "look")
        TF.assert_output_contains(c, "州街", "应看到州街标题")
        TF.assert_output_contains(c, "灰雾", "应看到州街描述-灰雾")
        TF.assert_output_contains(c, "书店", "应看到书店入口")
        TF.assert_output_contains(c, "north", "应有north出口")
        TF.assert_output_contains(c, "west", "应有west出口到书店")
        
        TF.send(c, "search")
        TF.assert_output_contains(c, "搜索了街道周围", "search命令应执行")
        TF.assert_output_contains(c, "没有其他值得注意的东西", "州街搜索无特别发现")
    end)

    -- 州街 - 无效方向（south无出口，系统提示走不通）
    TF.run_test("州街-无效方向提示", function()
        clear_book_of_green_god()
        local c = TF.register_user("ssdir_" .. os.time())
        fly_player_to(c, "StateStreet")
        
        TF.send(c, "go south")
        TF.assert_output_contains(c, "south方向的路走不通", "south无出口应提示走不通")
    end)

    -- 进入无名旧书店
    TF.run_test("书店-进入与初始状态", function()
        clear_book_of_green_god()
        local c = TF.register_user("bookstore_" .. os.time())
        fly_player_to(c, "StateStreet")
        
        TF.send(c, "go west")
        TF.assert_output_contains(c, "推开了那扇黄铜把手的木门", "应提示推开门")
        TF.assert_output_contains(c, "无名旧书店", "应到达书店")
        TF.assert_output_contains(c, "外界的声音瞬间消失", "应提示进入书店的特殊氛围")
        TF.assert_output_contains(c, "伊莱亚斯·索恩", "应看到NPC伊莱亚斯")
        TF.assert_output_contains(c, "书架", "应看到书架")
        
        TF.send(c, "look")
        TF.assert_not_contains(c, "旧木桌", "初始房间不应有旧木桌")
        TF.assert_not_contains(c, "木椅", "初始房间不应有木椅")
        TF.assert_not_contains(c, "《绿神》", "初始房间不应有绿神这本书")
        TF.assert_output_contains(c, "east", "应有east出口回州街")
    end)

    -- 书店 - listen命令
    TF.run_test("书店-listen命令", function()
        clear_book_of_green_god()
        local c = TF.register_user("sslisten_" .. os.time())
        fly_player_to(c, "NamelessBookstore")
        
        TF.send(c, "listen")
        TF.assert_output_contains(c, "死寂", "应提示店内死寂")
        TF.assert_output_contains(c, "细碎的低语声", "应听到低语声")
    end)

    -- 书店 - touch命令
    TF.run_test("书店-touch命令", function()
        clear_book_of_green_god()
        local c = TF.register_user("sstouch_" .. os.time())
        fly_player_to(c, "NamelessBookstore")
        
        TF.send(c, "touch")
        TF.assert_output_contains(c, "你要触碰什么", "无参数应提示")
        
        TF.send(c, "touch 门把手")
        TF.assert_output_contains(c, "黄铜门把手", "应描述门把手触感")
        TF.assert_output_contains(c, "干涩、黏滞", "应描述特殊触感")
        
        TF.send(c, "touch 门")
        TF.assert_output_contains(c, "黄铜门把手", "touch门也应触发门把手描述")
        
        TF.send(c, "touch 书架")
        TF.assert_output_contains(c, "潮湿冰凉", "应描述书架触感")
        
        TF.send(c, "touch 空气")
        TF.assert_output_contains(c, "没有什么特别的感觉", "触摸不存在的东西应无特殊感觉")
    end)

    -- 书店 - search命令无参数提示
    TF.run_test("书店-search无参数", function()
        clear_book_of_green_god()
        local c = TF.register_user("sssearch0_" .. os.time())
        fly_player_to(c, "NamelessBookstore")
        
        TF.send(c, "search")
        TF.assert_output_contains(c, "你要搜索什么", "无参数应提示搜索目标")
    end)

    -- 书店 - search书架找到《绿神》
    TF.run_test("书店-search书架发现绿神", function()
        clear_book_of_green_god()
        local c = TF.register_user("sssearch1_" .. os.time())
        fly_player_to(c, "NamelessBookstore")
        
        TF.send(c, "read 绿神")
        TF.assert_output_contains(c, "没有找到《绿神》", "未搜索前不应能读到绿神")
        TF.assert_output_contains(c, "搜索一下书架", "应提示搜索书架")
        
        TF.send(c, "search 书架")
        TF.assert_output_contains(c, "找到了一册覆着暗绿霉纹的古籍", "搜索书架应发现绿神")
        TF.assert_output_contains(c, "《绿神》", "应提到书名")
        
        TF.send(c, "look")
        TF.assert_output_contains(c, "《绿神》", "look房间现在应能看到绿神")
    end)

    -- 书店 - 重复搜索书架提示已找到（同一玩家连续搜索）
    TF.run_test("书店-重复搜索书架", function()
        clear_book_of_green_god()
        local c = TF.register_user("sssearch2_" .. os.time())
        fly_player_to(c, "NamelessBookstore")
        
        TF.send(c, "search 书籍")
        TF.assert_output_contains(c, "找到了一册", "第一次搜索应发现")
        
        TF.send(c, "search 书架")
        TF.assert_output_contains(c, "你已经找到了", "重复搜索应提示已找到")
    end)

    -- 书店 - search其他东西无特殊发现
    TF.run_test("书店-search其他物品", function()
        clear_book_of_green_god()
        local c = TF.register_user("sssearch3_" .. os.time())
        fly_player_to(c, "NamelessBookstore")
        
        TF.send(c, "search 地板")
        TF.assert_output_contains(c, "没有发现什么特别的东西", "搜索其他物品无发现")
    end)

    -- 书店 - read绿神（在房间内）
    TF.run_test("书店-read绿神-房间内", function()
        clear_book_of_green_god()
        local c = TF.register_user("ssread1_" .. os.time())
        fly_player_to(c, "NamelessBookstore")
        
        TF.send(c, "search 书架")
        c:clear_output()
        
        TF.send(c, "read 绿神")
        TF.assert_output_contains(c, "翻开了这本沾染旧日绿意的禁忌古籍", "应成功阅读绿神")
        TF.assert_output_contains(c, "绿神的迷雾已然笼罩", "应触发剧情")
        
        local player = login.session_pool[c.user_id]
        TF.assert(player.game_tags.green_god_triggered == true, "阅读后应设置green_god_triggered标记")
    end)

    -- 书店 - read《绿神》带书名号也能识别
    TF.run_test("书店-read绿神-书名号格式", function()
        clear_book_of_green_god()
        local c = TF.register_user("ssread2_" .. os.time())
        fly_player_to(c, "NamelessBookstore")
        
        TF.send(c, "search 书架")
        c:clear_output()
        
        TF.send(c, "read 《绿神》")
        TF.assert_output_contains(c, "翻开了这本", "带书名号也应能阅读")
    end)

    -- 书店 - read无参数提示
    TF.run_test("书店-read无参数", function()
        clear_book_of_green_god()
        local c = TF.register_user("ssread0_" .. os.time())
        fly_player_to(c, "NamelessBookstore")
        
        TF.send(c, "read")
        TF.assert_output_contains(c, "你要阅读什么", "无参数应提示")
    end)

    -- 书店 - 离开书店回到州街
    TF.run_test("书店-离开回州街", function()
        clear_book_of_green_god()
        local c = TF.register_user("ssleave_" .. os.time())
        fly_player_to(c, "NamelessBookstore")
        
        TF.send(c, "go east")
        TF.assert_output_contains(c, "推开木门", "应提示离开")
        TF.assert_output_contains(c, "州街的灰雾", "应回到州街")
    end)

    -- 书店 - read搜索背包逻辑验证（直接构造物品在背包中测试）
    TF.run_test("书店-read搜索背包逻辑", function()
        clear_book_of_green_god()
        local c = TF.register_user("ssreadbag_" .. os.time())
        fly_player_to(c, "NamelessBookstore")
        
        local player = login.session_pool[c.user_id]
        local BookOfGreenGod = require("mud_lib/item/book_of_green_god")
        
        player:add_obj(BookOfGreenGod)
        TF.drain_pending_timers()
        c:clear_output()
        
        TF.send(c, "read 绿神")
        TF.assert_output_contains(c, "翻开了这本", "背包中的绿神也应能被读到")
    end)
end