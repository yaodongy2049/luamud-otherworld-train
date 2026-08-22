---@module "mud_lib/llm_safety"
---@description LLM 输出的最小权限验证。模型只能建议有限的普通玩家命令。

local M = {}

-- LLM 绝不能触及 GM 命令、开发者控制台、Lua 执行或服务器管理命令。
-- 动态剧情命令也不在第一版 LLM 白名单内；玩家仍可使用原生命令完成剧情。
local SAFE_COMMANDS = {
  ["unknown"] = true,
  ["help"] = true,
  ["look"] = true,
  ["go"] = true,
  ["say"] = true,
  ["get"] = true,
  ["inv"] = true,
  ["hp"] = true,
  ["perform"] = true,
  ["kill"] = true,
  ["flee"] = true,
  ["save"] = true,
  ["journal"] = true,
  ["bye"] = true,
}

local MAX_ARG_CHARS = 96
local ARG_LIMITS = {
  ["unknown"] = 0,
  ["help"] = 1,
  ["look"] = 1,
  ["go"] = 1,
  ["say"] = 2,
  ["get"] = 1,
  ["inv"] = 0,
  ["hp"] = 0,
  ["perform"] = 2,
  ["kill"] = 1,
  ["flee"] = 0,
  ["save"] = 0,
  ["journal"] = 1,
  ["bye"] = 0,
}

local function is_safe_text(value)
  if type(value) ~= "string" or value == "" or #value > MAX_ARG_CHARS then
    return false
  end
  -- 控制字符可能破坏日志、终端或命令切分；一律拒绝。
  if string.find(value, "[%z\1-\31\127]") then
    return false
  end
  return true
end

---验证单个模型命令候选。返回标准化 {func=..., args={...}} 或 nil。
---@param call table
---@return table?
function M.validate_command(call)
  if type(call) ~= "table" or type(call.func) ~= "string" then
    return nil
  end

  local func = string.lower(call.func)
  if not SAFE_COMMANDS[func] then
    return nil
  end

  local args = call.args or {}
  if type(args) ~= "table" or #args > ARG_LIMITS[func] then
    return nil
  end

  local normalized = {}
  for index, arg in ipairs(args) do
    if not is_safe_text(arg) then
      return nil
    end
    normalized[index] = arg
  end

  return { func = func, args = normalized }
end

---验证桥接层或模型返回的结构化结果；第一版只接受一个命令候选。
---@param result table
---@return table?
function M.validate_command_result(result)
  if type(result) ~= "table" or type(result.results) ~= "table" or #result.results ~= 1 then
    return nil
  end

  local command = M.validate_command(result.results[1])
  if not command then
    return nil
  end
  return { results = { command } }
end

function M.unknown_result()
  return { results = { { func = "unknown", args = {} } } }
end

function M.is_safe_command_name(command)
  return type(command) == "string" and SAFE_COMMANDS[string.lower(command)] == true
end

function M.safe_command_names()
  local names = {}
  for name, _ in pairs(SAFE_COMMANDS) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

return M
