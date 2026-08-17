---@module "mud_lib/cmd/use"
---@desc use命令模块，提供使用道具功能

local class = require("mud_os/class")
local cmd_sys = require("mud_lib/cmds")

cmd_sys.command_desc_list.use = "use：对YY用XX/把XX用到YY身上，args=[物品(XX),目标(YY)]"
cmd_sys.command_desc_list.wear = "wear：穿上XX/装备XX，args=[物品]"
cmd_sys.command_desc_list.unwear = "unwear：脱下XX/收起XX，args=[物品]"

---use 命令：使用道具
cmd_sys.command_list.use = function(this_player, cmds)
    local target_id = cmds[2]
    local target_name = cmds[3]

    -- 检查参数是否完整
    if not target_id then
        this_player:reply("你要使用什么？")
        return
    end

    -- 在玩家身上查找物品（按id或name）
    local targets = this_player:resolve_content(target_id)

    if #targets == 0 then
        this_player:reply(string.format("你身上没有⌈%s⌋", target_id))
        return
    end

    local target_item = targets[1] --[[@as table]]

    -- 检查物品是否有 use 方法
    if not target_item.use or type(target_item.use) ~= "function" then
        this_player:reply(string.format("⌈%s⌋不能使用", target_item.name))
        return
    end

    -- 查找目标（如果指定了）
    local target_obj = nil
    if target_name then
        local this_place = this_player.environment --[[@as Room]]
        if class.is_empty(this_place) then
            this_player:reply("你周围什么都没有")
            return
        end

        local targets_list = this_place:resolve_content(target_name, this_player.user_id)

        if #targets_list == 0 then
            this_player:reply(string.format("没有找到目标⌈%s⌋", target_name))
            return
        end

        target_obj = targets_list[1]
    end

    -- 调用物品的 use 方法
    target_item:use(this_player, target_obj)
end

---wear 命令：穿戴装备
cmd_sys.command_list.wear = function(this_player, cmds)
    local target_id = cmds[2]

    -- 检查参数是否完整
    if not target_id then
        this_player:reply("你要穿戴什么？")
        return
    end

    -- 在玩家身上查找物品（按id或name）
    local targets = this_player:resolve_content(target_id)

    if #targets == 0 then
        this_player:reply(string.format("你身上没有⌈%s⌋", target_id))
        return
    end

    local target_item = targets[1] --[[@as Item]]

    -- 检查物品是否可穿戴
    if not target_item.wear_pos or target_item.wear_pos == "" then
        this_player:reply(string.format("⌈%s⌋无法穿戴", target_item.name))
        return
    end

    -- 初始化玩家装备表
    if not this_player.equipment then
        this_player.equipment = {}
    end

    local wear_pos = target_item.wear_pos
    local old_equip = this_player.equipment[wear_pos]

    -- 如果该位置已有装备，先卸下
    if old_equip then
        this_player:reply(string.format("你先脱下了⌈%s⌋", old_equip.name))
    end

    -- 穿戴新装备（只是添加引用，不移动物品）
    this_player.equipment[wear_pos] = target_item

    this_player:reply(string.format("你穿戴好了⌈%s⌋[%s] 位置：%s", target_item.name, target_item.id, wear_pos))
end

---unwear 命令：脱下装备
cmd_sys.command_list.unwear = function(this_player, cmds)
    local target = cmds[2]

    -- 检查参数是否完整
    if not target then
        this_player:reply("你要脱下什么？")
        return
    end

    -- 检查玩家装备表
    if not this_player.equipment or next(this_player.equipment) == nil then
        this_player:reply("你身上没有穿戴任何装备")
        return
    end

    local target_item = nil
    local wear_pos = nil

    -- 先尝试按装备位置查找
    if this_player.equipment[target] then
        wear_pos = target
        target_item = this_player.equipment[target]
    else
        -- 再尝试按道具id或名称查找
        for pos, item in pairs(this_player.equipment) do
            if item.id == target or item.name == target then
                wear_pos = pos
                target_item = item
                break
            end
        end
    end

    if not target_item or not wear_pos then
        this_player:reply(string.format("你没有穿戴⌈%s⌋", target))
        return
    end

    -- 脱下装备（只是移除引用，不移动物品）
    this_player.equipment[wear_pos] = nil

    this_player:reply(string.format("你脱下了⌈%s⌋[%s] 位置：%s", target_item.name, target_item.id, wear_pos))
end