---@module 'mud_lib/item'

local log = require('mud_os/log')
local semantic = require('mud_os/semantic_match')
local class = require('mud_os/class')
local SpaceObject = require('mud_lib/space')

---@type table<string, Item>
GLOBAL_ITEM_LIST = {}

---代表一个物品
---@class Item : SpaceObject
---@field New fun(id:string|table, name:string?, desc:string?, is_st:boolean?):Item 创建物品实例，会调用 Init 方法
---@field id string 物品id
---@field name string 物品名称
---@field count number 物品数量
---@field is_stackable boolean 是否可叠放
---@field wear_pos string 物品穿戴位置，不可穿戴为空字符串""
---@field desc string 物品描述
---@field is_unmov boolean 是否不可移动
---@field custom table? 自定义属性，用于记录同一id道具的不同特性（仅不可堆叠物品拥有）
Item = {
    id = 'item',
    name = '物品',
    count = 1,
    desc = '这是一个物品',
    is_stackable = false,
    wear_pos = "",
    __name = "Item",
    is_unmov = false,
}

---初始化一个物品
---@param id string|table 物品id
---@param name? string 物品名称
---@param desc? string 物品描述
---@param is_st? boolean 是否可叠放
---@return boolean
function Item:init(id, name, desc, is_st)
    -- 如果 id 是表，直接赋值
    if type(id) == "table" then
        class.copy_property(id, self)
        return true
    end
    -- 否则，根据参数初始化
    self.count = self.count or 1
    self.id = id
    self.name = name or '物品'
    self.desc = desc or '这是一个物品'
    self.is_stackable = is_st or false
    semantic.add_match_src(self.name)
    semantic.add_match_src(self.id)

    -- 只有不可堆叠的物品才初始化 custom 字段
    if not self.is_stackable then
        self.custom = self.custom or {}
    end
    if not GLOBAL_ITEM_LIST[id] then
        GLOBAL_ITEM_LIST[id] = self
    else
        log.WARNING(string.format("物品 %s 已存在，无法重复初始化", id))
    end
    return true
end

function Item:start()
    SpaceObject.start(self) --把数据初始化完之后再执行事件监听器注册
end

---使用物品，可以动态指定此函数以实现不同的使用行为
---@param this_player Player 使用品的玩家
---@param target any? 目标对象（可选）
function Item:use(this_player, target)
    this_player:reply("你尝试使用⌈" .. self.name .. "⌋，但是没有反应")
end

---放入物品到容器
---@override
---@param env SpaceObject 物品要放入的环境
function Item:put(env)
    -- 如果物品不可叠放，直接调用父类方法
    if not self.is_stackable then
        SpaceObject.put(self, env)
        return
    end

    -- 检查容器中是否已有相同ID的物品
    for _, item_obj in ipairs(env.content) do
        local item = item_obj --[[@as Item]]
        if class.is_instance(item, Item) and item.id == self.id and item.is_stackable then
            -- 找到相同ID的可叠放物品，增加数量
            item.count = item.count + self.count
            log.DEBUG(string.format("物品 %s 已叠放，数量变为 %d", self.name, item.count))
            return
        end
    end

    -- 如果没有找到相同ID的物品，调用父类方法放入
    SpaceObject.put(self, env)
end

---离开当前环境，对于可堆叠物品进行数量减少操作
---@override
function Item:leave()
    -- 如果物品不可堆叠，直接调用父类方法
    if not self.is_stackable then
        SpaceObject.leave(self)
        return
    end

    local old_env = self.environment
    if class.is_empty(old_env) then
        return
    end

    -- 查找当前物品在环境中的位置
    local found_pos = nil
    for pos, item in ipairs(old_env.content) do
        if item == self then
            found_pos = pos
            break
        end
    end

    if found_pos then
        -- 如果数量大于1，减少数量
        if self.count > 1 then
            self.count = self.count - 1
            log.DEBUG(string.format("物品 %s 数量减少，当前数量：%d", self.name, self.count))
        else
            -- 如果数量为1，移除物品
            table.remove(old_env.content, found_pos)
            log.DEBUG(string.format("物品 %s 已移除", self.name))
        end
    end

    -- 重置环境引用
    self.environment = {}
end

local pos_str_tab = {
    ["head"] = "头部",
    ["body"] = "身体",
    ["leg"] = "腿部",
    ["right_hand"] = "主手",
    ["left_hand"] = "副手",
    ["foot"] = "脚",
    ["brooch"] = "胸针",

}

---根据物品穿戴位置返回物品穿戴位置的字符串表示
---@param pos string? 物品穿戴位置
---@return string #物品穿戴位置的字符串表示
function Item:pos_str(pos)
    if not pos then
       pos = self.wear_pos
    end
    local rt = pos_str_tab[pos] or ""
    return rt
end

---@override
---@return string #物品的字符串表示
function Item:to_str()
    local wear_info = ""
    if self.wear_pos and self.wear_pos ~= "" then
        wear_info = string.format("□ %s\n", self:pos_str())
    end
    if not self.is_stackable then
        return string.format("- %s -\n%s%s", self.name, wear_info, self.desc)
    end
    return string.format("- %s(x%d) -\n%s%s", self.name, self.count, wear_info, self.desc)
end

class.define_class(Item, SpaceObject)
return Item