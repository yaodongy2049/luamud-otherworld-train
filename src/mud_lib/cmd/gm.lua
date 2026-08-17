---@module "mud_lib/cmd/gm"

local misc  = require("mud_os/misc")
local class = require("mud_os/class")
local cmd_sys = require("mud_lib/cmds")

cmd_sys.gm_command_desc_list.fly    = "fly：飞到指定地点，args=[房间ID]"
cmd_sys.gm_command_desc_list.dofile = "dofile：加载并执行Lua文件，args=[文件路径]"
cmd_sys.gm_command_desc_list.loadcmd = "loadcmd：重载命令文件，args=[命令名]"
cmd_sys.gm_command_desc_list.clone  = "clone：克隆物品，args=[物品名]"
cmd_sys.gm_command_desc_list.dev    = "dev：进入开发者控制台模式，输入exit退出"

cmd_sys.gm_command_list.fly       = function(this_player, cmds)
    local room_id = cmds[2]
    if not room_id then
        this_player:reply("你要飞到哪里？")
        return
    end
    this_player:reply("一阵烟雾腾起，你往" .. room_id .. "方向飞去。")
    if not this_player:fly_to(room_id) then
        this_player:reply("地点不存在。")
    end
end

cmd_sys.gm_command_list.dofile    = function(this_player, cmds)
    table.remove(cmds, 1)
    if #cmds == 0 then
        this_player:reply("你凌空一指，啥都没发生。")
        return
    end

    local msg     = table.concat(cmds, " ")
    local load_rs = misc.save_do_file(MUD_LIB_PATH .. msg)
    this_player:reply("你凌空一指，天空中显示出几个大字：\n" .. load_rs)
end

cmd_sys.gm_command_list.loadcmd   = function(this_player, cmds)
    if not cmds[2] then
        this_player:reply("你要重载什么命令？")
        return
    end

    local msg = misc.save_do_file(MUD_LIB_PATH .. "cmd/" .. cmds[2] .. ".lua")
    this_player:reply("重载: " .. cmds[2] .. "，结果：" .. msg)
end

cmd_sys.gm_command_list.clone     = function(this_player, cmds)
    if not cmds[2] then
        this_player:reply("你要克隆什么？")
        return
    end

    local Item = require("mud_lib/item")
    local target = GLOBAL_ITEM_LIST[cmds[2]]
    if target then
        local clone = class.clone(target) --[[@as Item]]
        if not class.is_instance(clone, Item) then
            this_player:reply("你不能克隆非物品")
            return
        end
        clone:start()
        clone:put(this_player)
        this_player:reply(string.format("你凌空一指，一个⌈%s⌋凭空出现了。", clone.name))
    else
        this_player:reply(string.format("身上没有 %s 这个东西", cmds[2]))
    end
end

cmd_sys.gm_command_list.dev       = function(this_player, cmds)
    this_player.temp_status.dev_mode = true
    this_player:reply("进入开发者控制台模式，输入 exit 退出。")
end