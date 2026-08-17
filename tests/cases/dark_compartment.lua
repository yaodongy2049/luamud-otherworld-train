---@module "tests/cases/dark_compartment"
---@description 《常暗之厢》剧本自动化测试

---《常暗之厢》剧本测试集合
---@param TF TestFramework 测试框架实例
return function(TF)
    local login = require("mud_lib/login")
    local Room = require("mud_lib/room")
    local class = require("mud_os/class")
    local Npc = require("mud_lib/npc")
    local Item = require("mud_lib/item")
    local timer = require("mud_os/timer")

    -- 辅助函数：直接获取玩家对象
    local function get_player(client)
        return login.session_pool[client.user_id]
    end

    -- 辅助函数：将玩家传送到指定房间
    local function fly_player_to(client, room_id)
        local player = get_player(client)
        TF.assert(player ~= nil, "玩家应已登录")
        player:fly_to(room_id)
        TF.drain_pending_timers()
        return player
    end

    -- 直接设置玩家为某个职业角色（跳过售票员对话，用于快速测试）
    local function set_player_job(player, job_name)
        local job_data = {
            ["消防员"] = {
                job = "退役消防员",
                str = 75, con = 70, dex = 65, int = 45, pow = 60, app = 45, edu = 40,
                san = 60, max_hp = 65,
                skill = {
                    ["侦查"] = 50, ["聆听"] = 55, ["急救"] = 60, ["潜行"] = 65,
                    ["话术"] = 35, ["灵感"] = 35, ["格斗"] = 70
                },
                exclusive = "消防员身份"
            },
            ["乘务员"] = {
                job = "末班电车乘务员",
                str = 40, con = 65, dex = 55, int = 50, pow = 45, app = 60, edu = 55,
                san = 55, max_hp = 55,
                skill = {
                    ["侦查"] = 40, ["聆听"] = 60, ["急救"] = 70, ["潜行"] = 35,
                    ["话术"] = 45, ["灵感"] = 40, ["电车知识"] = 80
                },
                exclusive = "乘务员身份"
            },
            ["记者"] = {
                job = "自由记者",
                str = 50, con = 45, dex = 60, int = 70, pow = 55, app = 50, edu = 65,
                san = 50, max_hp = 50,
                skill = {
                    ["侦查"] = 75, ["聆听"] = 50, ["急救"] = 30, ["潜行"] = 55,
                    ["话术"] = 60, ["灵感"] = 70, ["摄影"] = 65
                },
                exclusive = "记者身份"
            }
        }

        local jd = job_data[job_name]
        TF.assert(jd ~= nil, "职业数据应存在: " .. job_name)

        player.core_attrs = {
            str = jd.str, con = jd.con, dex = jd.dex,
            int = jd.int, pow = jd.pow, app = jd.app, edu = jd.edu
        }
        player.game_tags.attrs = {
            STR = jd.str, CON = jd.con, DEX = jd.dex, INT = jd.int,
            POW = jd.pow, APP = jd.app, EDU = jd.edu, SIZ = 50, LUK = 50
        }
        player.skill = jd.skill
        player.exclusive = jd.exclusive
        player.desc = jd.desc
        player.max_hp = jd.max_hp
        player:set_hp(player.max_hp)
        player:set_san(jd.san)
        player.game_tags.ticket_clerk_state = "completed"
        return player
    end

    -- 确保房间有必要的NPC/物品（重新生成）
    local function ensure_room_has(room, obj)
        if not room:has_obj("id", obj.id) then
            room:add_obj(obj)
        end
    end

    -- 辅助函数：清理测试环境 - 通过重新加载房间模块完全重置
    local function cleanup_compartment_state()
        -- 清除所有相关房间模块缓存，重新加载以重置状态
        local room_modules = {
            "mud_lib/map/compartment/station_hall",
            "mud_lib/map/compartment/compartment1",
            "mud_lib/map/compartment/compartment2",
            "mud_lib/map/compartment/compartment3",
            "mud_lib/map/compartment/compartment4",
            "mud_lib/map/compartment/compartment5",
            "mud_lib/map/compartment/compartment6",
            "mud_lib/map/compartment/compartment7",
            "mud_lib/map/compartment/station_end",
            "mud_lib/map/compartment/platform",
        }
        
        for _, mod in ipairs(room_modules) do
            package.loaded[mod] = nil
        end
        
        -- 重新加载所有车厢房间以重置NPC/物品状态
        for _, mod in ipairs(room_modules) do
            pcall(require, mod)
        end
        
        -- 清理玩家的对话状态
        for _, player in pairs(login.session_pool) do
            if player.temp_status then
                player.temp_status.last_say_target = nil
                player.temp_status.last_say_time = nil
                player.temp_status.dev_mode = nil
            end
            -- 清除战斗状态
            player.is_in_combat = false
            player.fright_list = nil
        end
    end

    -- ========================================
    -- 第一部分：车站大厅与角色创建测试
    -- ========================================

    -- 测试1: 车站大厅初始状态
    TF.run_test("常暗之厢-车站大厅初始状态", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_station_" .. os.time())
        fly_player_to(c, "StationHall")
        c:clear_output()
        
        TF.send(c, "look")
        TF.assert_output_contains(c, "车站入口大厅", "应在车站入口大厅")
        TF.assert_output_contains(c, "售票员", "应看到售票员NPC")
    end)

    -- 测试2: 月台未确认身份时无法进入
    TF.run_test("常暗之厢-未确认身份无法进月台", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_platform_" .. os.time())
        fly_player_to(c, "StationHall")
        c:clear_output()
        
        TF.send(c, "go east")
        TF.assert_output_contains(c, "请先到售票窗口确认身份", "应提示先确认身份")
    end)

    -- 测试3: 售票员对话流程 - 询问姓名（正确参数顺序：内容在前）
    TF.run_test("常暗之厢-售票员询问姓名", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_talk1_" .. os.time())
        fly_player_to(c, "StationHall")
        c:clear_output()
        
        TF.send(c, "say 你好 ticket_clerk")
        local output = c:get_output()
        -- 应该触发对话，可能是初始回复或询问姓名
        local has_response = string.find(output, "你叫什么名字") or string.find(output, "你好") or string.find(output, "售票员")
        TF.assert(has_response, "售票员应回应")
    end)

    -- 测试4: 无效职业（直接设置职业来测试，避免对话流程依赖骰子）
    TF.run_test("常暗之厢-直接设置职业测试", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_jobs_" .. os.time())
        local player = get_player(c)
        player = set_player_job(player, "消防员")
        
        TF.assert(player.exclusive == "消防员身份", "应设置消防员专属身份")
        TF.assert(player.core_attrs.str == 75, "力量应为75")
        TF.assert(player.skill["格斗"] == 70, "格斗技能应为70")
        
        player = set_player_job(player, "乘务员")
        TF.assert(player.exclusive == "乘务员身份", "应设置乘务员专属身份")
        TF.assert(player.skill["电车知识"] == 80, "电车知识应为80")
        TF.assert(player.skill["急救"] == 70, "急救应为70")
        
        player = set_player_job(player, "记者")
        TF.assert(player.exclusive == "记者身份", "应设置记者专属身份")
        TF.assert(player.skill["侦查"] == 75, "侦查应为75")
        TF.assert(player.skill["灵感"] == 70, "灵感应为70")
    end)

    -- 测试5: 确认身份后可进入月台
    TF.run_test("常暗之厢-确认身份后可进月台", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_goplat_" .. os.time())
        local player = get_player(c)
        set_player_job(player, "记者")
        fly_player_to(c, "StationHall")
        c:clear_output()
        
        TF.send(c, "go east")
        TF.assert_output_contains(c, "月台", "应到达月台")
    end)

    -- 测试6: 进入电车入睡场景
    TF.run_test("常暗之厢-进入电车入睡", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_sleep_" .. os.time())
        local player = get_player(c)
        set_player_job(player, "乘务员")
        fly_player_to(c, "Platform")
        c:clear_output()
        
        TF.send(c, "go east")
        TF.assert_output_contains(c, "睡意席卷", "应触发睡意描述")
        TF.drain_pending_timers()
        player = get_player(c)
        local this_place = player.environment --[[@as Room]]
        TF.assert(this_place.id == "Compartment6", "应传送到6号车厢")
    end)

    -- ========================================
    -- 第三部分：6号车厢（起始车厢）测试
    -- ========================================

    -- 测试7: 6号车厢初始状态
    TF.run_test("常暗之厢-6号车厢初始状态", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_c6_" .. os.time())
        local player = get_player(c)
        set_player_job(player, "记者")
        fly_player_to(c, "Compartment6")
        c:clear_output()
        
        TF.send(c, "look")
        TF.assert_output_contains(c, "6号车厢", "应在6号车厢")
        TF.assert_output_contains(c, "便签纸", "应看到便签")
    end)

    -- 测试8: 6号车厢回头（west）被阻挡
    TF.run_test("常暗之厢-6号车厢回头惩罚", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_c6w_" .. os.time())
        local player = get_player(c) --[[@as Investigator]]
        set_player_job(player, "记者")
        local old_san = player.san
        fly_player_to(c, "Compartment6")
        c:clear_output()
        
        TF.send(c, "go west")
        TF.assert_output_contains(c, "寒意从背后袭来", "应触发恐惧描述")
        TF.assert_output_contains(c, "强制留在了原地", "应被强制留在原地")
        player = get_player(c) --[[@as Investigator]]
        TF.assert(player.san < old_san, "应损失SAN值")
        TF.assert(player.environment.id == "Compartment6", "应仍在6号车厢")
    end)

    -- 测试9: 拾取并查看便签 - 记者专属
    TF.run_test("常暗之厢-拾取查看便签记者专属", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_c6note_" .. os.time())
        local player = get_player(c)
        set_player_job(player, "记者")
        fly_player_to(c, "Compartment6")
        TF.drain_pending_timers()
        c:clear_output()
        
        TF.send(c, "look")
        -- 尝试拾取便签（可能需要先look生成它）
        TF.send(c, "get mysterious_note")
        local got_note = false
        if c:output_contains("神秘便签") or c:output_contains("mysterious_note") then
            got_note = true
        end
        
        -- 如果get没找到，先look再get
        if not got_note then
            TF.send(c, "look")
            TF.send(c, "get mysterious_note")
        end
        
        c:clear_output()
        TF.send(c, "look mysterious_note")
        TF.assert_output_contains(c, "只管前进吧", "应看到便签正面内容")
        TF.assert_output_contains(c, "扭曲眼睛图案", "记者应看到眼睛图案")
    end)

    -- 测试10: 乘务员查看示意图有专属提示
    TF.run_test("常暗之厢-乘务员看示意图", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_c6map_" .. os.time())
        local player = get_player(c)
        set_player_job(player, "乘务员")
        fly_player_to(c, "Compartment6")
        TF.drain_pending_timers()
        c:clear_output()
        
        TF.send(c, "look")
        TF.send(c, "look train_map")
        TF.assert_output_contains(c, "3号车厢的电路开关", "乘务员应看到电路开关位置提示")
    end)

    -- ========================================
    -- 第四部分：5号车厢（过渡车厢）测试
    -- ========================================

    -- 测试11: 进入5号车厢
    TF.run_test("常暗之厢-进入5号车厢", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_c5_" .. os.time())
        local player = get_player(c)
        set_player_job(player, "消防员")
        fly_player_to(c, "Compartment6")
        TF.drain_pending_timers()
        c:clear_output()
        
        TF.send(c, "go east")
        TF.assert_output_contains(c, "5号车厢", "应到达5号车厢")
        TF.assert_output_contains(c, "水渍", "应看到水渍")
    end)

    -- 测试12: 消防员查看水渍有专属描述（需要侦查判定通过）
    TF.run_test("常暗之厢-消防员看水渍", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_c5water_" .. os.time())
        local player = get_player(c) --[[@as Investigator]]
        set_player_job(player, "消防员")
        player.skill["侦查"] = 99  -- 确保侦查判定成功
        fly_player_to(c, "Compartment5")
        TF.drain_pending_timers()
        c:clear_output()
        
        TF.send(c, "look")
        TF.send(c, "look water_stain")
        TF.assert_output_contains(c, "消防水", "消防员应有专属描述")
    end)

    -- 测试13: 5号车厢回头惩罚
    TF.run_test("常暗之厢-5号车厢回头惩罚", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_c5w_" .. os.time())
        local player = get_player(c)
        set_player_job(player, "消防员")
        fly_player_to(c, "Compartment5")
        TF.drain_pending_timers()
        c:clear_output()
        
        TF.send(c, "go west")
        TF.assert_output_contains(c, "车厢似乎在收缩", "应触发车厢收缩描述")
        player = get_player(c)
        local this_place = player.environment --[[@class Room]]
        local in_5_or_4 = this_place.id == "Compartment5" or this_place.id == "Compartment4"
        TF.assert(in_5_or_4, "应留在5号或被推到4号")
    end)

    -- ========================================
    -- 第五部分：4号车厢（关键车厢）测试
    -- ========================================

    -- 测试14: 进入4号车厢
    TF.run_test("常暗之厢-进入4号车厢", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_c4_" .. os.time())
        local player = get_player(c)
        set_player_job(player, "乘务员")
        fly_player_to(c, "Compartment4")
        TF.drain_pending_timers()
        c:clear_output()
        
        TF.send(c, "look")
        TF.assert_output_contains(c, "4号车厢", "应到达4号车厢")
        TF.assert_output_contains(c, "乘务员", "应看到乘务员")
    end)

    -- 测试15: 乘务员急救自动成功
    TF.run_test("常暗之厢-乘务员急救自动成功", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_c4heal_" .. os.time())
        local player = get_player(c)
        set_player_job(player, "乘务员")
        fly_player_to(c, "Compartment4")
        TF.drain_pending_timers()
        c:clear_output()
        
        -- 先look确保dying_conductor NPC被spawn出来
        TF.send(c, "look")
        c:clear_output()
        
        TF.send(c, "perform 急救 dying_conductor")
        TF.drain_pending_timers()
        player = get_player(c)
        local has_key = player:has_obj("id", "conductor_key")
        TF.assert(has_key, "应获得乘务员钥匙")
    end)

    -- 测试16: 4号车厢回头惩罚
    TF.run_test("常暗之厢-4号车厢回头惩罚", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_c4w_" .. os.time())
        local player = get_player(c)
        set_player_job(player, "乘务员")
        local old_hp = player.hp
        fly_player_to(c, "Compartment4")
        TF.drain_pending_timers()
        c:clear_output()
        
        TF.send(c, "go west")
        TF.assert_output_contains(c, "车厢开始收缩", "应触发车厢收缩")
        player = get_player(c)
        TF.assert(player.hp < old_hp, "应损失HP")
        local this_place = player.environment --[[@class Room]]
        TF.assert(this_place.id == "Compartment4", "应被强制留在4号车厢")
    end)

    -- ========================================
    -- 第六部分：3号车厢（怪物车厢）测试
    -- ========================================

    -- 测试17: 进入3号车厢（黑暗）
    TF.run_test("常暗之厢-进入3号车厢", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_c3_" .. os.time())
        local player = get_player(c) --[[@as Investigator]]
        set_player_job(player, "乘务员")
        local old_san = player.san
        fly_player_to(c, "Compartment4")
        TF.drain_pending_timers()
        c:clear_output()
        
        TF.send(c, "go east")
        TF.assert_output_contains(c, "3号车厢", "应到达3号车厢")
        player = get_player(c) --[[@as Investigator]]
        TF.assert(player.san <= old_san, "进入黑暗应损失SAN或保持")
    end)

    -- 测试18: 3号车厢不能回头（west）
    TF.run_test("常暗之厢-3号车厢不能回头", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_c3w_" .. os.time())
        local player = get_player(c)
        set_player_job(player, "消防员")
        fly_player_to(c, "Compartment3")
        TF.drain_pending_timers()
        c:clear_output()
        
        TF.send(c, "go west")
        TF.assert_output_contains(c, "怪物的声音", "应听到怪物声音或提示不能回头")
        player = get_player(c) --[[@as Investigator]]
        local this_place = player.environment --[[@class Room]]
        TF.assert(this_place.id == "Compartment3", "应留在3号车厢")
    end)

    -- ========================================
    -- 第七部分：2号车厢（线索车厢）测试
    -- ========================================

    -- 测试19: 乘务员高潜行成功进入2号车厢
    TF.run_test("常暗之厢-潜行成功进2号车厢", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_c2_" .. os.time())
        local player = get_player(c) --[[@as Investigator]]
        set_player_job(player, "乘务员")
        -- 设置潜行150确保threshold = 150 - 0 = 150 >= 100，100%成功
        player.skill["潜行"] = 150
        fly_player_to(c, "Compartment3")
        TF.drain_pending_timers()
        
        -- 先开灯降低难度
        local room3 = player.environment --[[@class Room]]
        room3.lights_on = true
        c:clear_output()
        
        TF.send(c, "perform 潜行")
        TF.drain_pending_timers()
        player = get_player(c) --[[@as Investigator]]
        local this_place = player.environment --[[@class Room]]
        TF.assert(this_place.id == "Compartment2", "潜行成功应到2号车厢")
        
        -- fly_to只发送移动消息，需要手动look查看房间
        c:clear_output()
        TF.send(c, "look")
        TF.assert_output_contains(c, "2号车厢", "应显示2号车厢描述")
    end)

    -- 测试20: 2号车厢不能回头
    TF.run_test("常暗之厢-2号车厢回头有怪物", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_c2w_" .. os.time())
        local player = get_player(c)
        set_player_job(player, "记者")
        fly_player_to(c, "Compartment2")
        TF.drain_pending_timers()
        c:clear_output()
        
        TF.send(c, "go west")
        TF.assert_output_contains(c, "怪物", "应感到怪物气息或提示不能回头")
        player = get_player(c) --[[@as Investigator]]
        local this_place = player.environment --[[@class Room]]
        TF.assert(this_place.id == "Compartment2", "应留在2号车厢")
    end)

    -- ========================================
    -- 第八部分：1号车厢（结局车厢）测试
    -- ========================================

    -- 测试21: 进入1号车厢
    TF.run_test("常暗之厢-进入1号车厢", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_c1_" .. os.time())
        local player = get_player(c)
        set_player_job(player, "乘务员")
        fly_player_to(c, "Compartment2")
        TF.drain_pending_timers()
        c:clear_output()
        
        TF.send(c, "go east")
        TF.assert_output_contains(c, "1号车厢", "应到达1号车厢")
        TF.assert_output_contains(c, "控制台", "应看到控制台")
    end)

    -- 测试22: 1号车厢不能回头
    TF.run_test("常暗之厢-1号车厢不能回头", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_c1w_" .. os.time())
        local player = get_player(c)
        set_player_job(player, "消防员")
        local old_hp = player.hp
        fly_player_to(c, "Compartment1")
        TF.drain_pending_timers()
        c:clear_output()
        
        TF.send(c, "go west")
        TF.assert_output_contains(c, "空间开始扭曲", "应触发空间扭曲")
        player = get_player(c)
        TF.assert(player.hp < old_hp, "应损失HP")
        local this_place = player.environment --[[@class Room]]
        TF.assert(this_place.id == "Compartment1", "应留在1号车厢")
    end)

    -- ========================================
    -- 第九部分：完整流程快速验证
    -- ========================================

    -- 测试23: 完整流程 - 乘务员从6号到1号
    TF.run_test("常暗之厢-乘务员完整流程", function()
        cleanup_compartment_state()
        local c = TF.register_user("dc_full1_" .. os.time())
        local player = get_player(c)
        set_player_job(player, "乘务员")
        
        -- 直接从6号开始
        fly_player_to(c, "Compartment6")
        TF.drain_pending_timers()
        
        -- 前进到5号
        TF.send(c, "go east")
        player = get_player(c) --[[@as Investigator]]
        local this_place = player.environment --[[@class Room]]
        TF.assert(this_place.id == "Compartment5", "应到5号车厢")
        
        -- 前进到4号
        TF.send(c, "go east")
        player = get_player(c) --[[@as Investigator]]
        this_place = player.environment --[[@class Room]]
        TF.assert(this_place.id == "Compartment4", "应到4号车厢")
        
        -- 先look确保NPC已生成
        TF.send(c, "look")
        c:clear_output()
        
        -- 急救乘务员（乘务员身份自动成功）
        TF.send(c, "perform 急救 dying_conductor")
        TF.drain_pending_timers()
        player = get_player(c)
        TF.assert(player:has_obj("id", "conductor_key"), "应拿到钥匙")
        
        -- 前进到3号
        TF.send(c, "go east")
        TF.drain_pending_timers()
        player = get_player(c) --[[@as Investigator]]
        this_place = player.environment --[[@class Room]]
        TF.assert(this_place.id == "Compartment3", "应到3号车厢")
        
        -- 高潜行通过（设置150确保100%成功）
        player.skill["潜行"] = 150
        local room3 = player.environment
        room3.lights_on = true
        c:clear_output()
        TF.send(c, "perform 潜行")
        TF.drain_pending_timers()
        player = get_player(c) --[[@as Investigator]]
        this_place = player.environment --[[@class Room]]
        TF.assert(this_place.id == "Compartment2", "潜行应到2号车厢")
        
        -- 前进到1号
        TF.send(c, "go east")
        TF.drain_pending_timers()
        player = get_player(c) --[[@as Investigator]]
        this_place = player.environment --[[@class Room]]
        TF.assert(this_place.id == "Compartment1", "应到1号车厢")
    end)

    print("---------- 《常暗之厢》测试模块执行完成 ----------")
end