---@module "mud_lib/cmd/get"
---@desc get命令模块，提供获取道具功能，支持从地面或容器中获取

local class = require("mud_os/class")
local cmd_sys = require("mud_lib/cmds")
local Item = require("mud_lib/item")
local EventSystem = require("mud_os/event_system")

cmd_sys.command_desc_list.get = "get：捡起XX/在YY里拿XX，args=[物品(XX),容器(YY 可选)]"
cmd_sys.command_desc_list.drop = "drop：丢掉XX，args=[物品]"
cmd_sys.command_desc_list.inv = "inv：查看背包，args=[]"

---inv 命令：查看玩家背包中的物品
cmd_sys.command_list.inv = function(this_player, cmds)
    -- 检查玩家是否有物品
    if not this_player.content or #this_player.content == 0 then
        this_player:reply("你的背包里没有任何物品。")
        return
    end

    -- 构建物品列表
    local output = "你背包里的物品：\n"
    for _, obj in ipairs(this_player.content) do
        local item = obj --[[@as Item]]
        local count_str = item.is_stackable and item.count > 1 and string.format("(x%d)", item.count) or ""
        
        -- 检查物品是否被装备
        local equip_mark = ""
        if this_player.equipment then
            for pos, equip_item in pairs(this_player.equipment) do
                if equip_item == item then
                    equip_mark = string.format(" → %s", equip_item:pos_str())
                    break
                end
            end
        end
        
        output = output .. string.format(" * ⌈%s⌋[%s]%s%s\n", item.name, item.id, count_str, equip_mark)
    end

    this_player:reply(output)
end

---drop 命令：丢弃道具到地上
cmd_sys.command_list.drop = function(this_player, cmds)
    local target_id = cmds[2]

    -- 检查参数是否完整
    if not target_id then
        this_player:reply("你要丢弃什么？")
        return
    end

    local this_place = this_player.environment --[[@as Room]]
    if class.is_empty(this_place) then
        this_player:reply("你周围什么都没有")
        return
    end

    -- 在玩家身上查找物品（按id或name）
    local targets = this_player:resolve_content(target_id, this_player.user_id)

    if #targets == 0 then
        this_player:reply(string.format("你身上没有 %s", target_id))
        return
    end

    local target_item = targets[1] --[[@as Item]]

    -- 检查是否是物品
    if not class.is_instance(target_item, Item) then
        this_player:reply("这不是可以丢弃的物品")
        return
    end

    -- 如果物品正在被装备，先脱下
    if this_player.equipment then
        for pos, equip_item in pairs(this_player.equipment) do
            if equip_item == target_item then
                this_player.equipment[pos] = nil
                this_player:reply(string.format("你先脱下了 %s", target_item.name))
                break
            end
        end
    end

    -- 创建物品副本（用于可堆叠物品）
    local item_to_drop = target_item

    -- 如果是可堆叠物品且数量大于1，创建一个新物品实例
    if target_item.is_stackable and target_item.count > 1 then
        item_to_drop = Item.New(target_item.id, target_item.name, target_item.desc, true)
        item_to_drop.count = 1
    end

    -- 从玩家身上移除物品（使用 Item:leave() 处理堆叠逻辑）
    target_item:leave()

    -- 将物品放入当前房间（使用 SpaceObject:put() 方法）
    item_to_drop:put(this_place)

    -- 发送反馈
    this_player:reply(string.format("你丢弃了%s", item_to_drop.name))
    this_place.channel:say(string.format("%s丢弃了%s", this_player.name, item_to_drop.name), this_player)
end

---get 命令：获取道具
cmd_sys.command_list.get = function(this_player, cmds)
    local target_id = cmds[2]
    local container_id = cmds[3]

    -- 检查参数是否完整
    if not target_id then
        this_player:reply("你要获取什么？")
        return
    end

    local this_place = this_player.environment --[[@as Room]]
    if class.is_empty(this_place) then
        this_player:reply("你周围什么都没有")
        return
    end

    local target_item = nil
    local search_source = this_place --[[@as SpaceObject]]
    local source_name = "地上"

    -- 如果指定了容器，先查找容器
    if container_id then
        local containers = this_place:resolve_content(container_id, this_player.user_id)

        if #containers == 0 then
            this_player:reply(string.format("没有找到：%s", container_id))
            return
        end

        local container = containers[1]
        -- 检查容器是否有 content（作为容器的标志）
        if not container.content or type(container.content) ~= "table" then
            this_player:reply(string.format("%s 不能打开", container))
            return
        end

        -- 在容器中查找物品
        local with_name = container --[[@as table]]
        if with_name.name then
            source_name = with_name.name
        end
    end

    -- 在搜索源中查找物品（按id或name）
    local targets = search_source:resolve_content(target_id, this_player.user_id)

    if #targets == 0 then
        this_player:reply(string.format("%s 里没有找到 %s", source_name, target_id))
        return
    end

    target_item = targets[1] --[[@as Item]]

    -- 检查是否是物品
    if not class.is_instance(target_item, Item) then
        this_player:reply("这不是可以获取的物品")
        return
    end

    if target_item.is_unmov then
        this_player:reply("你不能移动这个物品")
        return
    end

    ---@alias BeforeGetCallback fun(event_name:string, target:Item, player:Investigator):boolean
    local has_handled, result_list = EventSystem:trigger("before_get", target_item, this_player)
    if has_handled then
        for _, result in ipairs(result_list) do
            if result == false then
                return
            end
        end
    end

    -- 创建物品副本（用于可堆叠物品）
    local item_to_get = target_item

    -- 如果是可堆叠物品且数量大于1，创建一个新物品实例
    if target_item.is_stackable and target_item.count > 1 then
        item_to_get = Item.New(target_item.id, target_item.name, target_item.desc, true)
        item_to_get.count = 1
    end

    -- 从源中移除物品（使用 Item:leave() 处理堆叠逻辑）
    target_item:leave()

    -- 将物品放入玩家身上（使用 SpaceObject:put() 方法）
    item_to_get:put(this_player)

    ---@alias AfterGetCallback fun(event_name:string, target:Item, player:Investigator)
    EventSystem:trigger("after_get", item_to_get, this_player)

    -- 发送反馈
    if container_id then
        this_player:reply(string.format("你从%s中取出了%s", source_name, item_to_get.name))
        this_place.channel:say(string.format("%s从%s中取出了%s", this_player.name, source_name, item_to_get.name), this_player)
    else
        this_player:reply(string.format("你捡起了%s", item_to_get.name))
        this_place.channel:say(string.format("%s捡起了%s", this_player.name, item_to_get.name), this_player)
    end
end