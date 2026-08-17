---@module "mud_lib/cmd/common"

local log                      = require("mud_os/log")
local class                    = require("mud_os/class")
local network                  = require("mud_os/network")
local EventSystem              = require("mud_os/event_system")
local Room                     = require("mud_lib/room")
local login                    = require("mud_lib/login")
local cmd_sys                  = require("mud_lib/cmds")
local Casebook                 = require("mud_lib/casebook")

cmd_sys.command_desc_list.help = "help：查询指令用法，args=[命令(可选)]"
cmd_sys.command_desc_list.bye  = "bye：退出/下线，args=[]"
cmd_sys.command_desc_list.look = "look：看XX，args=[目标(可选)]"
cmd_sys.command_desc_list.go   = "go：去往XX，args=[地点/方位]"
cmd_sys.command_desc_list.who  = "who：查看当前在线玩家列表，args=[]"
cmd_sys.command_desc_list.perform = "perform：使用技能，args=[技能名, 目标(可选)]；示例：perform 侦查、perform 急救 dying_conductor"
cmd_sys.command_desc_list.flee = "flee：战斗中尝试逃跑；成功率主要受敏捷影响。失败后可再次尝试。"
cmd_sys.command_desc_list.combat = "战斗帮助：遇敌后会自动交战。可用 flee 尝试逃跑；输入 hp 查看当前状态。"
cmd_sys.command_desc_list.skills = "技能帮助：输入 perform <技能名> [目标]。场景会提示可用技能与目标。"
cmd_sys.command_desc_list.save = "save：立即保存当前角色的地点、属性、SAN、技能、背包与剧情进度。"
cmd_sys.command_desc_list.journal = "journal：查看只属于当前角色的案件、线索、代价与下一步目标；可选 args=[案件编号]。"

local function append_sorted_desc(lines, desc_list)
    local keys = {}
    for key in pairs(desc_list or {}) do
        table.insert(keys, key)
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        table.insert(lines, desc_list[key])
    end
end

cmd_sys.command_list.help      = function(this_player, cmds)
    local target = cmds[2] and string.lower(cmds[2]) or nil
    if target then
        local dynamic_desc = this_player.dynamic_cmds_desc or {}
        local output = cmd_sys.command_desc_list[target] or dynamic_desc[target] or "缺失描述；可输入 help 查看基础命令，或观察当前场景提示。"
        this_player:reply(output)
        return
    end

    local lines = { "=== 基础命令 ===" }
    append_sorted_desc(lines, cmd_sys.command_desc_list)

    local dynamic_desc = this_player.dynamic_cmds_desc or {}
    if next(dynamic_desc) then
        table.insert(lines, "=== 当前场景命令 ===")
        append_sorted_desc(lines, dynamic_desc)
    end

    if this_player.get_local_enemies and #this_player:get_local_enemies() > 0 then
        table.insert(lines, "=== 当前战斗 ===")
        table.insert(lines, cmd_sys.command_desc_list.flee)
    end

    table.insert(lines, "提示：输入 help combat 查看战斗说明；输入 help skills 查看技能说明。")
    this_player:reply(table.concat(lines, "\n"))
end

cmd_sys.command_list.bye       = function(this_player, cmds)
    local user_id = this_player.user_id
    log.INFO("Closing client #" .. user_id)
    this_player:reply("再见")
    this_player:cleanup()
end

cmd_sys.command_list.journal = function(this_player, cmds)
    cmd_sys.exit_dialog_mode(this_player)
    Casebook.show(this_player, cmds[2])
end

cmd_sys.command_list.save = function(this_player, cmds)
    cmd_sys.exit_dialog_mode(this_player)
    local ok, err = pcall(function()
        this_player:save()
    end)
    if ok then
        local room_title = this_player.environment and this_player.environment.title or "未知地点"
        this_player:reply("【存档】已保存。地点：" .. room_title .. "；可随时继续冒险。")
    else
        log.ERROR("Manual save failed: " .. tostring(err))
        this_player:reply("【存档失败】当前进度未确认写入，请稍后重试或正常退出游戏。")
    end
end

cmd_sys.command_list.look      = function(this_player, cmds)
    local target = this_player.environment --[[@as SpaceObject]]
    local target_id = cmds[2] -- cmds[1]是指令本身，cmds[2]才是参数
    if target_id then
        local this_place = this_player.environment --[[@as Room]]
        local found = nil
        if class.is_empty(this_place) then
            this_player:reply('你周围什么都没有')
            return
        end
        local targets = this_place:resolve_content(target_id, this_player.user_id)
        if targets[1] then
            found = targets[1]
        else
            local belongs = this_player:resolve_content(target_id, this_player.user_id)
            if belongs[1] then
                found = belongs[1]
            end
        end
        if not found then
            this_player:reply(string.format("没有%s这个东西", target_id))
            return
        end
        target = found
    end

    this_player:reply(target:to_str())

    -- 触发 look 事件，目标为当前房间
    EventSystem:trigger("look", target, this_player, target_id)
end

---前往指定方向，此命令会触发事件：
--- - "before_go"：在前往前触发，任何一个事件回调函数返回 false，都会阻止前往
--- - "after_go"：在前往后触发
cmd_sys.command_list.go        = function(this_player, cmds)
    cmd_sys.exit_dialog_mode(this_player)  
    if this_player.hp <= 0 then
        this_player:reply("你奄奄一息，倒地不起，不能移动分毫。")
        return
    end
    local direction = cmds[2]
    if not direction then
        this_player:reply("你要去什么地方？")
        return
    end

    local this_place = this_player.environment --[[@as Room]]
    if class.is_empty(this_place) then
        this_player:reply('你周围什么都没有')
        return
    end

    -- 检查是否有敌人
    local enemies = this_player:get_local_enemies()
    if #enemies > 0 then
        this_player:reply("你正在战斗，不能前往。")
        return
    end

    -- 搜索出口
    local room_id = this_place:search_exit(direction)
    if IS_LLM_ENABLED and not room_id then
        room_id = this_place:search_exit_llm(direction, this_player.user_id)
    end
    if not room_id then
        this_player:reply("往" .. direction .. "方向的路走不通。")
        return
    end

    local new_place = Room.get_world().rooms[room_id]
    if not new_place then
        this_player:reply("空间已经被扭曲，地点 " .. room_id .. "不存在。")
        return
    end

    local exit_direction = nil
    for dir, exit_room_id in pairs(this_place.exits) do
        if exit_room_id == room_id then
            exit_direction = dir
            break
        end
    end

    -- 触发 before_go 事件，目标为当前房间
    
    local handled, result_list = EventSystem:trigger("before_go", this_place, this_player, exit_direction or direction, room_id)
    if handled then
        for _, v in ipairs(result_list) do
            if type(v) == "boolean" and not v then
                return
            end
        end
    end

    if this_player:enter(new_place) == true then
        cmd_sys.command_list.look(this_player, { "look" })

        -- 触发 after_go 事件，目标为当前房间
        EventSystem:trigger("after_go", this_player.environment, this_player, exit_direction or direction, room_id)
    end
end

---格式化登录时长
---@param seconds number 秒数
---@return string #格式化后的时长字符串
local function format_duration(seconds)
    seconds = math.floor(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if hours > 0 then
        return string.format("%d小时%d分%d秒", hours, minutes, secs)
    elseif minutes > 0 then
        return string.format("%d分%d秒", minutes, secs)
    else
        return string.format("%d秒", secs)
    end
end

---who命令：查看当前在线玩家列表
cmd_sys.command_list.who = function(this_player, cmds)
    cmd_sys.exit_dialog_mode(this_player)
    
    local online_count = 0
    local lines = {
        "==================== 在线玩家 ====================",
        string.format("%-15s %-12s %-8s %s", "名字", "ID", "状态", "登录时长"),
        "--------------------------------------------------"
    }
    
    local now = os.time()
    
    -- 遍历session_pool获取所有在线玩家
    for _, player in pairs(login.session_pool) do
        -- 只显示正常在线和发呆的玩家（不显示断线中和退出中的）
        if player.network_status == login.NetworkStatus.NORMAL or
           player.network_status == login.NetworkStatus.IDLE then
            online_count = online_count + 1
            
            local status_str = "在线"
            if player.network_status == login.NetworkStatus.IDLE then
                status_str = "发呆"
            end
            
            local duration = format_duration(now - player.login_time)
            
            table.insert(lines, string.format("%-15s %-12s %-8s %s",
                player.name,
                player.id,
                status_str,
                duration
            ))
        end
    end
    
    table.insert(lines, "--------------------------------------------------")
    table.insert(lines, string.format("当前共有 %d 位玩家在线。", online_count))
    table.insert(lines, "==================================================")
    
    this_player:reply(table.concat(lines, "\n"))
end