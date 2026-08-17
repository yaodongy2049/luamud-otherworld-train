---@module "mud_os/serialize"
---@desc 序列化系统

---基本序列化函数
---@param o any 要序列化的值
---@return string
local function basic_serialize(o)
  if type(o) == "number" then
    return tostring(o)
  elseif type(o) == "boolean" then
    return tostring(o)
  else -- assume it is a string
    return string.format("%q", o)
  end
end

---保存值到文件
---@param name string 变量名
---@param value any 要保存的值
---@param saved any 已保存值的表
local function save(name, value, saved)
  local value_type = type(value)
  if value_type == "function" then
    return
  end

  local is_root = false
  if not saved then
    is_root = true
  end
  saved = saved or {} -- initial value
  if is_root then
    io.write("local ")
  end
  io.write(name .. " = ")
  if value_type == "number" or value_type == "string" or value_type == "boolean" then
    io.write(basic_serialize(value), "\n")
  elseif value_type == "table" then
    if saved[value] then -- value already saved?
      -- use its previous name
      io.write(saved[value], "\n")
    else
      saved[value] = name         -- save name for next time
      io.write("{}\n")            -- create a new table
      for k, v in pairs(value) do -- save its fields
        --如果 k 是字符串而且不以 _ 开头，才保存
        if (type(k) == "string" and not k:match("^_")) or type(k) == "number" then
          local fieldname = string.format("%s[%s]", name, basic_serialize(k))
          save(fieldname, v, saved)
        end
      end
    end
  else
    error("cannot save a " .. type(value) .. ": " .. name)
  end
  if is_root then
    io.write("\nreturn " .. name)
  end
end


---判断表是否为纯数组（连续整数索引从1开始）
---@param t table
---@return boolean
local function is_array(t)
  local n = #t
  if n == 0 then return false end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
  end
  return true
end

---递归序列化函数
---@param value any
---@param saved table
---@return string
local function serialize_value(value, saved)
  local value_type = type(value)
  
  if value_type == "number" or value_type == "string" or value_type == "boolean" then
    return basic_serialize(value)
  elseif value_type == "table" then
    if saved[value] then
      return saved[value]
    end
    
    -- 先标记为已保存，防止循环引用导致无限递归
    saved[value] = "{}"
    
    local filtered = {}
    for k, v in pairs(value) do
      -- 跳过以 _ 开头的字符串键和非数字键
      if not ((type(k) == "string" and k:match("^_")) or type(k) ~= "string" and type(k) ~= "number") then
        -- 跳过 function 和 userdata 类型的值
        local v_type = type(v)
        if v_type ~= "function" and v_type ~= "userdata" then
          filtered[k] = v
        end
      end
    end
    
    if next(filtered) == nil then
      return "{}"
    end
    
    if is_array(filtered) then
      local parts = {}
      for i = 1, #filtered do
        table.insert(parts, serialize_value(filtered[i], saved))
      end
      return "{" .. table.concat(parts, ", ") .. "}"
    end
    
    local parts = {}
    for k, v in pairs(filtered) do
      local key_str
      if type(k) == "string" then
        -- 检查是否为合法的 Lua 标识符（包括中文等 Unicode 字母）
        -- 合法标识符：以字母或下划线开头，后面跟着字母、数字或下划线
        local is_valid_identifier = k:match("^[%a_][%w_]*$") ~= nil
        -- 额外检查是否包含非 ASCII 字符（如中文）
        local has_non_ascii = k:match("[\x80-\xff]") ~= nil
        
        if is_valid_identifier and not has_non_ascii then
          -- 纯 ASCII 合法标识符，直接使用
          key_str = k
        else
          -- 中文字符或特殊字符，使用方括号语法
          key_str = "[" .. basic_serialize(k) .. "]"
        end
      else
        key_str = "[" .. basic_serialize(k) .. "]"
      end
      table.insert(parts, key_str .. " = " .. serialize_value(v, saved))
    end
    return "{" .. table.concat(parts, ", ") .. "}"
  else
    return "nil"
  end
end

---保存值到文件（简洁格式）
---@param name string 变量名
---@param value any 要保存的值
---@param saved any 已保存值的表
local function save2(name, value, saved)
  local value_type = type(value)
  if value_type == "function" then
    return
  end
  
  saved = saved or {}
  local result = serialize_value(value, saved)
  io.write("local " .. name .. " = " .. result .. "\n\nreturn " .. name)
end

return {
  save = save2
}