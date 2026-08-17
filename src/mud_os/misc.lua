---@@module "mud_os/misc"
---@description 通用工具函数
local log = require("mud_os/log")


---执行指定文件中的 Lua 代码
---@param file string 文件路径
---@return string? #执行结果或错误信息
local function save_do_file(file)
  local fun, err = loadfile(file)
  local ret = err
  if fun then
    local is_succ, result = pcall(fun)
    if not is_succ then
      log.WARNING("执行文件失败: " .. file .. " " .. result)
    end
    if result then
      ret = tostring(result)
    else
      ret = "OK"
    end
  end
  return ret
end

---提取文件路径中的最后一层目录和文件名
---@param file_path string 文件路径
---@return string #最后一层目录和文件名，如果提取失败则返回原路径
local function get_last_dir_and_file(file_path)
  local last_dir_and_file = string.match(file_path, ".*/([^/]+/[^/]+)$")
  return last_dir_and_file or file_path
end

---去除字符串头尾的空白字符（空格、回车、换行等）
---@param s string 输入字符串
---@return string, number #去除空白后的字符串，位置
local function trim(s)
  return s:gsub("^%s+", ""):gsub("%s+$", "")
end

---计算字符串的显示宽度（处理UTF-8中文，跳过ANSI控制字符）
local function utf8_display_width(str)
  local width = 0
  local i = 1
  while i <= #str do
    local byte = str:byte(i)
    
    -- 跳过 ANSI 转义序列：ESC[... 命令字符
    if byte == 0x1B then  -- ESC
      if str:byte(i + 1) == 0x5B then  -- [
        i = i + 2
        -- 跳过直到遇到命令字符（字母范围：0x40-0x7E）
        while i <= #str do
          local b = str:byte(i)
          if b >= 0x40 and b <= 0x7E then
            break
          end
          i = i + 1
        end
        i = i + 1
        goto continue
      end
    end
    
    if byte < 0x80 then
      width = width + 1
      i = i + 1
    elseif byte < 0xE0 then
      width = width + 1
      i = i + 2
    elseif byte < 0xF0 then
      local code_point = { str:byte(i, i + 2) }
      local unicode = (code_point[1] % 0x10) * 0x1000 + (code_point[2] % 0x40) * 0x40 + (code_point[3] % 0x40)

      if unicode >= 0x2500 and unicode <= 0x257F then
        width = width + 1
      else
        width = width + 2
      end
      i = i + 3
    else
      width = width + 2
      i = i + 4
    end
    ::continue::
  end
  return width
end

---构建边框线：+-----+-----+ 格式
local function build_border(col_widths)
  local border = "+"
  for _, width in ipairs(col_widths) do
    border = border .. string.rep("-", width + 2) .. "+"
  end
  return border
end

-- 构建数据行：| 内容 | 内容 | 格式
local function build_row(row, col_widths)
  local line = "|"
  for i, width in ipairs(col_widths) do
    local cell = row[i] or ""
    local need_space = width - utf8_display_width(cell)
    if need_space < 0 then
      need_space = 0
    end
    line = line .. " " .. cell .. string.rep(" ", need_space) .. " |"
  end
  return line
end

---计算每列的最大宽度
local function calculate_col_widths(rows)
  if not rows or #rows == 0 then
    return {}
  end

  -- 确定列数：取所有行中最大的列数
  local col_count = 0
  for _, row in ipairs(rows) do
    if #row > col_count then
      col_count = #row
    end
  end

  -- 初始化每列宽度为0
  local col_widths = {}
  for i = 1, col_count do
    col_widths[i] = 0
  end

  -- 遍历所有单元格，记录每列最大显示宽度
  for _, row in ipairs(rows) do
    for i = 1, col_count do
      local cell = row[i] or ""
      local display_width = utf8_display_width(cell)
      if display_width > col_widths[i] then
        col_widths[i] = display_width
      end
    end
  end

  return col_widths
end

---构建最终表格字符串
local function build_table(rows, col_widths)
  local border = build_border(col_widths)
  local output = border .. "\n"

  for _, row in ipairs(rows) do
    output = output .. build_row(row, col_widths) .. "\n" .. border .. "\n"
  end

  -- 移除最后多余的换行符
  return string.sub(output, 1, -2)
end

---创建一个格式化的表格字符串，每行数据中间有边界
---@param lines string[]|string[][] 字符串数组，每个元素为表格的一行内容
---@return string #格式化后的表格字符串
local function create_sheet(lines)
  -- 空输入检查
  if not lines or #lines == 0 then
    return ""
  end

  -- 判断是否为二维数组：通过检查第一个元素是否为table
  local is_2d = type(lines[1]) == "table"

  local rows = {}
  local col_widths
  if not is_2d then
    -- 一维数组：转换为单列二维数组
    for _, line in ipairs(lines) do
      if line and line ~= "" then
        table.insert(rows, { tostring(line) })
      end
    end

    if #rows == 0 then
      return ""
    end

    col_widths = calculate_col_widths(rows)
  else
    -- 二维数组：过滤并转换有效数据
    for _, row in ipairs(lines) do
      if row and type(row) == "table" and #row > 0 then
        local valid_cells = {}
        for _, cell in ipairs(row) do
          table.insert(valid_cells, cell ~= nil and tostring(cell) or "")
        end
        if #valid_cells > 0 then
          table.insert(rows, valid_cells)
        end
      end
    end

    if #rows == 0 then
      return ""
    end

    col_widths = calculate_col_widths(rows)
  end

  -- 构建并返回表格
  return build_table(rows, col_widths)
end

-- UTF8 取单个字符（返回字符、下一个位置）
local function utf8_char(s, pos)
    local b = s:byte(pos)
    if b < 0x80 then
        return s:sub(pos, pos), pos + 1
    elseif b < 0xE0 then
        return s:sub(pos, pos+1), pos + 2
    elseif b < 0xF0 then
        return s:sub(pos, pos+2), pos + 3
    else
        return s:sub(pos, pos+3), pos + 4
    end
end

---通用分割函数，支持全角/半角分隔符、UTF8 中文
---@param str string 待分割的字符串
---@param sep_set string[]? 分隔符集合，默认",", "，", "/", "、", "|", " "
---@return string[] #分割后的字符串数组
local function split_string(str, sep_set)
    local result = {}
    local current = ""
    local pos = 1
    sep_set = sep_set or {",", "，", "/", "、", "|", " "} -- 预设常用分隔符
    
    while pos <= #str do
        local char, next_pos = utf8_char(str, pos)
        local is_sep = false
        
        -- 判断当前字符是否为分隔符
        for _, s in ipairs(sep_set) do
            if char == s then
                is_sep = true
                break
            end
        end
        
        if is_sep then
            -- 裁剪空白并加入结果
            local trim = current:match("^%s*(.-)%s*$")
            if trim ~= "" then
                table.insert(result, trim)
            end
            current = ""
        else
            current = current .. char
        end
        pos = next_pos
    end
    
    -- 处理最后一段内容
    local trim = current:match("^%s*(.-)%s*$")
    if trim ~= "" then
        table.insert(result, trim)
    end
    return result
end

---将任意值格式化为字符串，table 递归展开，func/userdata/thread 显示类型标签
---@param value any 要格式化的值
---@param indent number? 当前缩进层级（递归使用）
---@param seen table? 已访问的表集合（防止循环引用）
---@return string
local function format_value(value, indent, seen)
  indent = indent or 0
  seen = seen or {}
  local t = type(value)
  if t == "nil" then
    return "nil"
  elseif t == "boolean" then
    return tostring(value)
  elseif t == "number" then
    return tostring(value)
  elseif t == "string" then
    return "\"" .. value .. "\""
  elseif t == "function" then
    return "<func>"
  elseif t == "userdata" then
    return "<userdata>"
  elseif t == "thread" then
    return "<thread>"
  elseif t == "table" then
    if seen[value] then
      return "<cyclic>"
    end
    seen[value] = true

    if next(value) == nil then
      seen[value] = nil
      return "{}"
    end

    local indent_str = string.rep("  ", indent)
    local inner_indent = string.rep("  ", indent + 1)
    local parts = {}
    parts[#parts + 1] = "{\n"

    local array_part = {}
    local hash_part = {}
    local max_array_idx = 0
    for i, v in ipairs(value) do
      array_part[i] = v
      max_array_idx = i
    end
    for k, v in pairs(value) do
      if type(k) ~= "number" or k > max_array_idx or k < 1 or math.floor(k) ~= k then
        hash_part[#hash_part + 1] = { k = k, v = v }
      end
    end

    for i, v in ipairs(array_part) do
      parts[#parts + 1] = inner_indent .. format_value(v, indent + 1, seen) .. ",\n"
    end
    for _, kv in ipairs(hash_part) do
      local k_str
      if type(kv.k) == "string" and string.match(kv.k, "^[%a_][%w_]*$") then
        k_str = kv.k
      else
        k_str = "[" .. format_value(kv.k, indent + 1, seen) .. "]"
      end
      parts[#parts + 1] = inner_indent .. k_str .. " = " .. format_value(kv.v, indent + 1, seen) .. ",\n"
    end

    parts[#parts + 1] = indent_str .. "}"
    seen[value] = nil
    return table.concat(parts)
  end
  return "<" .. t .. ">"
end

---格式化多个参数，返回拼接后的字符串（类似 print 但返回字符串而非输出）
---@param ... any 任意数量的参数
---@return string
local function return_print(...)
  local n = select("#", ...)
  if n == 0 then
    return ""
  end
  local parts = {}
  for i = 1, n do
    local v = select(i, ...)
    parts[i] = format_value(v)
  end
  return table.concat(parts, "\t")
end

return {
  save_do_file = save_do_file,
  get_last_dir_and_file = get_last_dir_and_file,
  trim = trim,
  create_sheet = create_sheet,
  utf8_display_width = utf8_display_width,
  split_string = split_string,
  return_print = return_print,
  format_value = format_value,
}