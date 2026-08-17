---@module "mud_os/EventSystem"
---@description 事件系统模块

local log = require("mud_os/log")

---事件回调函数
---@alias EventCallback fun(string, table?, ...):any

---事件监听器项
---@class EventItem
---@field callback EventCallback 回调函数
---@field priority number 优先级（数字越小优先级越高）

---事件系统
---@class EventSystem
---@field listeners table<string, table<table, EventItem[]>> 存储事件监听器，结构为 event_name -> target -> EventItem[]
local EventSystem = {
    listeners = {}
}

---注册事件监听器
---@param event_name string 事件名称
---@param callback EventCallback 回调函数，参数为(event_name, target, ...)
---@param target table 目标对象
---@param priority number? 优先级（可选，默认10，数字越小优先级越高）
function EventSystem:register_listener(event_name, callback, target, priority)
    if not target then
        log.WARNING("事件" .. event_name .. "监听器注册错误：目标对象不能为空")
        return
    end
    
    local event_targets = self.listeners[event_name]
    if not event_targets then
        event_targets = setmetatable({}, { __mode = "k" }) -- target层使用弱引用key
        self.listeners[event_name] = event_targets
    end

    local target_listeners = event_targets[target]
    if not target_listeners then
        target_listeners = {}
        event_targets[target] = target_listeners
    end

    local event = setmetatable({}, { __mode = "v" }) -- 事件监听器项为弱引用
    event.callback = callback
    event.priority = priority or 10

    for _, existing_event in ipairs(target_listeners) do -- 检查是否存在相同的回调函数
        if existing_event.callback == callback then
            return
        end
    end
    
    table.insert(target_listeners, event)

    -- 按优先级排序
    table.sort(target_listeners, function(a, b)
        return a.priority < b.priority
    end)
end

---触发事件
---@param event_name string 事件名称
---@param target table 目标对象
---@param ... any 事件参数
---@return boolean, any[] #是否有监听器处理了事件，事件函数返回值，放入一个 table 中
function EventSystem:trigger(event_name, target, ...)
    local event_targets = self.listeners[event_name]
    if not event_targets then
        return false, {}
    end

    local target_listeners = event_targets[target]
    if not target_listeners or #target_listeners == 0 then
        return false, {}
    end

    -- 复制事件监听器列表，避免在遍历过程中修改列表
    local event_listeners_copy = {} ---@type EventItem[]
    local remove_idx = {}
    for i, event_item in ipairs(target_listeners) do
        if not event_item.callback then -- 登记需要删除的弱引用回调函数索引
            table.insert(remove_idx, i)
        else
            table.insert(event_listeners_copy, event_item) -- 复制有效回调函数，供后面进行调用
        end
    end

    -- 移除弱引用回调函数
    for _, idx in ipairs(remove_idx) do
        table.remove(target_listeners, idx)
    end

    -- 触发事件监听器
    local handled = false
    local result_list = {}
    for _, listener in ipairs(event_listeners_copy) do
        local success, result = pcall(listener.callback, event_name, target, ...)
        if success then
            handled = true
            table.insert(result_list, result)
        else
            log.WARNING("事件监听器触发失败: " .. event_name .. " " .. tostring(target) .. " " .. tostring(result))
        end
    end

    return handled, result_list
end

---移除事件监听器
---@param event_name string 事件名称
---@param callback fun(string, table?, ...):boolean,any 要移除的回调函数
---@param target table? 目标对象（可选）
function EventSystem:remove_listener(event_name, callback, target)
    local event_targets = self.listeners[event_name]
    if not event_targets then
        return
    end

    if target then
        local target_listeners = event_targets[target]
        if not target_listeners then
            return
        end

        for i = #target_listeners, 1, -1 do
            local listener = target_listeners[i]
            if listener.callback == callback then
                table.remove(target_listeners, i)
            end
        end
    else
        -- 没有指定target，遍历所有target移除匹配的callback
        for t, target_listeners in pairs(event_targets) do
            for i = #target_listeners, 1, -1 do
                local listener = target_listeners[i]
                if listener.callback == callback then
                    table.remove(target_listeners, i)
                end
            end
        end
    end
end

---清除所有监听器
---@param event_name string? 事件名称（可选，不传则清除所有事件）
function EventSystem:clear_listeners(event_name)
    if event_name then
        self.listeners[event_name] = {}
    else
        self.listeners = {}
    end
end

---获取事件监听器数量
---@param event_name string 事件名称
---@param target table? 目标对象（可选，不传则统计所有target的监听器数量）
---@return number #监听器数量
function EventSystem:get_listener_count(event_name, target)
    local event_targets = self.listeners[event_name]
    if not event_targets then
        return 0
    end

    if target then
        local target_listeners = event_targets[target]
        return target_listeners and #target_listeners or 0
    end

    local count = 0
    for _, target_listeners in pairs(event_targets) do
        count = count + #target_listeners
    end
    return count
end

return EventSystem