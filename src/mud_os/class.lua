---@module "mud_os/class"
---@desc 类系统模块，提供类对象功能

local log = require("mud_os/log")

---已定义的类对象表
---@generic T : table
---@type table<T, T>
local defined_classes = {}

---只复制成员为 Table 类型的属性
---@param src any 源对象
---@param dest any 目标对象
---@return any 复制后的对象
---@note 此函数会复制所有 Table 类型的属性，不复制其他属性，也不复制元表
local function copy_sub_table(src, dest)
    dest = dest or {}
    for k, v in pairs(src) do
        if type(v) == "table"
        then
            local new_v = {}
            for k_i, v_i in pairs(v) do
                new_v[k_i] = v_i
            end
            dest[k] = new_v
        end
    end
    return dest
end

---复制类对象的 Table 属性到实例对象
---@param instance table 实例对象
---@param class_obj table 类对象
local function copy_table_from_class(instance, class_obj)
    copy_sub_table(class_obj, instance)
    local mt = getmetatable(class_obj)
    if mt then
        local super = mt.__index
        if not super then
            return
        end
        copy_table_from_class(instance, super)
    end
end

---深拷贝表，返回复制后的表
---@param tbl table 源表
---@param is_skip_inner? boolean 是否跳过内部表（如 __index, __tostring 等）（可选）
---@param seen? table 已访问表（可选）
---@return table
local function deep_copy(tbl, is_skip_inner, seen)
    if type(tbl) ~= "table" then
        return tbl
    end

    -- 防止循环引用导致栈溢出
    seen = seen or {}
    if seen[tbl] then
        return seen[tbl]
    end

    local copy = {}
    seen[tbl] = copy

    for k, v in pairs(tbl) do
        -- 跳过特殊字段（以_开头的内部字段）
        if is_skip_inner and type(k) == "string" and string.sub(k, 1, 1) == "_" then
            goto continue
        end
        if type(v) == "table" then
            copy[k] = deep_copy(v, is_skip_inner, seen)
        else
            -- function / userdata / number / string 等
            copy[k] = v
        end
        ::continue::
    end

    return copy
end

---定义类对象，此对象会被增加构造器方法 New()，用于创建实例对象。创建实例时会调用 `Init(self)/init(self)` 方法初始化实例对象。<br>
---1. 一旦调用此函数，类对象就会被“**冻结**”，之后修改类对象的属性、方法都不能影响到后续创建的实例对象。
---2. 父类对象必须在子类对象调用此函数之前调用本函数进行“**定义**”，否则会报错：`Base class XXX not defined`
---
---继承实现：实例 → 【__index: 类对象】 → 【__index: 父类对象】 → 【__index: ...】<br>
---成员实现：
---    - 方法（function）：直接在类对象中定义的方法，会自动绑定到实例对象上。
---    - 属性（string/number/user_data）：直接在类对象中定义的属性，初始化在类对象上，后续修改会直接赋值到实例对象上。
---    - 集合（table）：会递归复制到实例对象中，不会直接引用类对象的属性，以便实例对象可以独立修改其内容。
---@generic T : table
---@param cls T 类对象
---@param base? table 父类对象
local function define_class(cls, base)
    -- 检查类对象是否已定义
    local frozen = defined_classes[cls]
    if frozen then
        ---@diagnostic disable-next-line: undefined-field
        local cls_name = cls.__name or tostring(cls)
        log.WARNING(string.format("Class [%s] already defined", cls_name))
        return
    end

    -- 复制类对象，避免直接修改原始类对象
    frozen = deep_copy(cls)
    frozen.__index = frozen

    local cls_meta = { __name = "Class" }

    -- 实现继承
    local base_frozen = nil
    if base then
        base_frozen = defined_classes[base]
        assert(base_frozen, string.format("Base class [%s] not defined", tostring(base)))
        cls_meta.__index = base_frozen
        cls.super = base_frozen
    end

    -- 冻结类对象
    cls_meta.__newindex =
        function(tbl, key, value)
            error(string.format("Cannot modify class [%s] field [%s]: [%s]",
                tostring(tbl), tostring(key), tostring(value)))
        end

    setmetatable(frozen, cls_meta)
    defined_classes[cls] = frozen

    -- 添加构造器
    cls.New = function(...)
        local obj = setmetatable({}, frozen)
        copy_table_from_class(obj, frozen) --基类如果有table，会递归复制

        -- 调用初始化函数
        if obj.Init and type(obj.Init) == "function" then
            obj:Init(...)
        elseif obj.init and type(obj.init) == "function" then
            obj:init(...)
        end
        return obj
    end
end

---克隆对象（深拷贝）。适用于由 define_class() 创建的类实例
---@generic T : table
---@param obj T 实例对象
---@return T #被克隆的对象
local function clone(obj)
    -- 检查输入
    if not obj or type(obj) ~= "table" then
        log.ERROR("Clone: 必须传入一个有效的对象")
        return {}
    end

    -- 创建新实例，使用相同的类作为元表
    local new_obj = deep_copy(obj, true)
    local mt = getmetatable(obj)
    if mt then
        setmetatable(new_obj, mt)
    end
    return new_obj
end

---判断表是否为空
---@param t table 表
---@return boolean
local function is_empty(t)
    return t == nil or next(t) == nil
end

---复制属性表，返回复制后的表
---@param src table 源表
---@param dest? table 目标表（可选）
---@return table
---@note 此函数会复制所有属性，不复制函数属性，也不复制元表
local function copy_property(src, dest)
    if type(src) ~= "table" then
        return src
    end
    dest = dest or {}
    for k, v in pairs(src) do
        dest[k] = v
    end
    return dest
end

---判断实例对象是否为类对象的实例
---@param instance table 实例对象
---@param class_obj table 类对象
---@param is_recall boolean? 是否递归调用
---@return boolean
local function is_instance(instance, class_obj, is_recall)
    local frozen = class_obj
    if not is_recall then
        frozen = defined_classes[class_obj]
    end
    if not frozen then
        log.WARNING("[IsInstance] class_obj has not been defined, class_obj:", class_obj)
        return false
    end

    local mt = getmetatable(instance)
    if not mt then
        return false
    end
    if mt.__index == frozen then
        return true
    end

    return is_instance(mt.__index, frozen, true)
end

return {
    define_class = define_class,
    clone = clone,
    is_empty = is_empty,
    copy_property = copy_property,
    is_instance = is_instance,
}
