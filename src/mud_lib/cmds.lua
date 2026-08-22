---@module "mud_lib/cmds"
---@description 玩法命令模块

local log            = require("mud_os/log")
local misc           = require("mud_os/misc")
local network        = require("mud_os/network")
local login          = require("mud_lib/login")
local semantic_match = require("mud_os/semantic_match")



---用户执行的命令所调用的函数接口形式
---@alias CmdFunc fun(this_player:Player, cmds:string[]):boolean?

---命令列表，存储所有已注册的命令函数
---@type table<string, CmdFunc>
local command_list         = {}

---命令描述列表，存储命令的说明信息
---@type table<string, string>
local command_desc_list    = {}

---GM命令列表，存储调试命令函数
---@type table<string, CmdFunc>
local gm_command_list      = {}

---GM命令描述列表，存储调试命令的说明信息
---@type table<string, string>
local gm_command_desc_list = {}

---命令行提示符
local prompt               = "❯ "

---退出对话命令列表
---@type string[]
local exit_cmds            = {
  "结束对话", "再见",
  "退出对话",
  "离开对话",
  "end dialog",
  "finish dialog",
  "退出", "结束", "离开", "告辞", "走了", "先走", "失陪", "不聊了", "到此为止", "终止对话",
  "取消", "放弃", "取消对话", "放弃交谈", "放弃本次交谈", "关掉对话",
  "先不说了", "下次再说", "回头再说", "待会儿再来", "不说了",
  "quit", "exit", "leave",
}

for _, cmd in ipairs(exit_cmds) do
  semantic_match.add_match_src(cmd)
end

---检查是否为退出命令（语义匹配 + 精确匹配）
---@param input_str string 输入字符串
---@param user_id string? 用户ID
---@return boolean #是否为退出命令
local function is_exit_command(input_str, user_id)
  log.DEBUG("检查是否为退出命令: " .. input_str)
  for _, cmd in ipairs(exit_cmds) do
    if cmd == input_str then
      log.DEBUG("退出对话精确命中: " .. cmd)
      return true
    end
  end
  if IS_LLM_ENABLED then
    local matched = semantic_match.best_match(input_str, exit_cmds)
    if matched then
      log.DEBUG("退出命令语义匹配命中: " .. input_str .. " -> " .. matched)
      return true
    end
  end
  return false
end

---通用命令处理器函数
---@param this_player Player 用户ID
---@param cmds table 命令参数列表
---@return boolean? #nil 表示没有此命令，true/false表示命令执行结果
local function common_cmd_handler(this_player, cmds)
  if #cmds == 0 or not cmds[1] then
    return nil
  end

  local cmd = string.lower(cmds[1])
  local cmd_fun = command_list[cmd]

  if cmd_fun and type(cmd_fun) == "function" then
    local ret = cmd_fun(this_player, cmds)
    return not ret or ret == true
  end

  -- TODO: 日后增加 GM 身份校验于此
  local gm_cmd_fun = gm_command_list[cmd]
  if gm_cmd_fun and type(gm_cmd_fun) == "function" then
    local ret = gm_cmd_fun(this_player, cmds)
    return not ret or ret == true
  end

  return nil
end

---运行房间的 avg_cmds 命令
--- @param this_player Player 用户ID
--- @param cmds string[] 命令参数表
--- @return boolean #是否执行成功
local function run_avg_cmd(this_player, cmds)
  if #cmds == 0 or not cmds[1] then
    return false
  end

  if not this_player then
    return false
  end

  if not this_player.dynamic_cmds or type(this_player.dynamic_cmds) ~= "table" then
    return false
  end

  -- 检查命令是否存在
  local cmd_name = cmds[1]
  local cmd_func = this_player.dynamic_cmds[cmd_name]
  if not cmd_func or type(cmd_func) ~= "function" then
    return false
  end

  -- 执行命令
  cmd_func(this_player, cmds)
  return true
end

---将命令字符串拆分为普通命令数组；动作提示只能登记已注册的普通命令。
local function split_normal_command(cmd)
  if type(cmd) ~= "string" or cmd == "" then
    return nil
  end
  local parts = {}
  for part in string.gmatch(cmd, "%S+") do
    table.insert(parts, part)
  end
  if #parts == 0 or not command_list[string.lower(parts[1])] then
    return nil
  end
  return parts
end

---取得与当前房间绑定的作者动作提示别名表。
local function get_action_hint_aliases(player, create)
  if not player or not player.environment or not player.environment.id then
    return nil
  end
  player.temp_status = player.temp_status or {}
  local aliases = player.temp_status.action_hint_aliases
  if aliases and aliases.room_id == player.environment.id then
    return aliases
  end
  if not create then
    return nil
  end
  aliases = { room_id = player.environment.id, values = {} }
  player.temp_status.action_hint_aliases = aliases
  return aliases
end

---登记当前房间展示给玩家的中文动作提示。它不是自由文本执行器：只映射到已注册普通命令。
local function register_action_hint(player, label, cmd)
  local aliases = get_action_hint_aliases(player, true)
  local parts = split_normal_command(cmd)
  if aliases and parts and type(label) == "string" and label ~= "" then
    aliases.values[label] = parts
  end
end

---把玩家输入的精确中文提示还原为作者提供的普通命令；房间切换后自动失效。
local function resolve_action_hint(player, cmds)
  local aliases = get_action_hint_aliases(player, false)
  if not aliases or type(cmds) ~= "table" then
    return nil
  end
  local label = table.concat(cmds, " ")
  local mapped = aliases.values[label]
  if not mapped then
    return nil
  end
  local copied = {}
  for index, value in ipairs(mapped) do
    copied[index] = value
  end
  return copied
end

---显示操作提示
---@param player Player 玩家对象
---@param hint string 提示文本（不含"【操作提示】"前缀）
---@param cmd string 普通模式下的命令
---@param llm_cmd string LLM模式下的命令
local function show_action_hint(player, hint, cmd, llm_cmd)
  -- 无论当前是否启用 LLM，均登记与房间绑定的确定性别名；这使可见中文提示无需猜测对象内部 ID。
  register_action_hint(player, llm_cmd, cmd)
  player:reply("【操作提示】" .. hint .. "，输入：")
  local msg = log.COLORS.GREEN .. cmd .. log.COLORS.RESET
  if IS_LLM_ENABLED then
    msg = log.COLORS.GREEN .. llm_cmd .. log.COLORS.RESET
  end
  player:reply(msg)
end

---退出对话模式
---@param this_player Player 玩家对象
local function exit_dialog_mode(this_player)
  if this_player.temp_status
      and this_player.temp_status.last_say_target then
    this_player:reply("你结束了对话。")
    this_player.temp_status.last_say_target = nil
    this_player.temp_status.last_say_time = nil
  end
end

---处理开发者控制台模式下的输入
---@param this_player Player 玩家对象
---@param cmds string[] 命令参数表
---@return boolean #是否已处理（在dev模式下始终返回true）
local function handle_dev_mode(this_player, cmds)
  if not this_player.temp_status or not this_player.temp_status.dev_mode then
    return false
  end

  local input_str = table.concat(cmds, " ")
  if input_str == "exit" then
    this_player.temp_status.dev_mode = nil
    this_player:reply("已退出开发者控制台模式。")
    this_player:send_prompt()
    return true
  end
  local chunk_env = setmetatable({
    this_player = this_player,
    this_place = this_player.environment,
    print = function(...)
      this_player:reply(misc.return_print(...))
    end,
  }, { __index = _G })
  local chunk, load_err = load(input_str, "dev_mode", "t", chunk_env)
  if not chunk then
    this_player:reply(log.COLORS.RED .. "代码解析错误: " .. tostring(load_err)..log.COLORS.RESET)
    this_player:send_prompt()
    return true
  end
  local ok, result = pcall(chunk)
  if ok then
    if result ~= nil then
      this_player:reply(misc.format_value(result))
    end
  else
    this_player:reply(log.COLORS.RED .. "代码执行错误: " .. tostring(result)..log.COLORS.RESET)
  end
  this_player:send_prompt()
  return true
end

---调用基础命令
---@param user_id string 用户ID
---@param cmds string[] 命令参数表
---@return boolean #是否成功处理此命令
local function normal_handler(user_id, cmds)
  --- Shotcut: 当前玩家
  local this_player = login.session_pool[user_id]
  if not this_player then
    return false -- If client have not logined, use any_cmd() process all the input
  end

  -- 更新输入计时器，重置发呆状态
  this_player:reset_input_timer()

  -- 开发者控制台模式
  if handle_dev_mode(this_player, cmds) then
    return true
  end

  -- 空输入，发送提示符
  if #cmds == 0 or not cmds[1] then
    this_player:send_prompt()
    return true
  end

  -- 玩家可见的房间动作提示优先确定性还原为作者指定的普通命令，避免模型猜测对象内部 ID。
  local hinted_cmds = resolve_action_hint(this_player, cmds)
  if hinted_cmds then
    cmds = hinted_cmds
  end

  -- 特殊命令 unknown 处理
  local input_str = table.concat(cmds, " ")
  if input_str == "unknown" then
    this_player:reply("不知道您想做什么？")
    this_player:send_prompt()
    return true
  end

  local rs = common_cmd_handler(this_player, cmds)
  if not rs then
    -- 尝试调用房间解谜命令
    rs = run_avg_cmd(this_player, cmds)
  end

  if not rs
      and this_player.temp_status
      and this_player.temp_status.last_say_target then
    if is_exit_command(input_str, user_id) then
      exit_dialog_mode(this_player)
      this_player:send_prompt()
      return true
    end
    local msg = table.concat(cmds, " ")
    local say_cmds = { "say", msg }
    log.DEBUG("say_cmds: " .. table.concat(say_cmds, " "))
    rs = common_cmd_handler(this_player, say_cmds)
  end

  if rs and (cmds[1] and this_player.network_status == login.NetworkStatus.NORMAL) then
    this_player:send_prompt()
  end
  return rs or false
end

---重载全部通用命令
local function reload_cmds()
  local ret_msg = {}
  local handle = io.popen("ls " .. MUD_LIB_PATH .. "cmd/*.lua") --Search cmd path
  if not handle then
    log.ERROR("打开命令文件失败", MUD_LIB_PATH .. "cmd/*.lua")
    return nil, nil, nil
  end
  local result = handle:read("*a")
  handle:close()
  local cmd_files = {}
  string.gsub(result, '[^\n \t]+', function(w) table.insert(cmd_files, w) end)
  for i, v in pairs(cmd_files) do
    log.INFO(i .. "." .. misc.get_last_dir_and_file(v))
    table.insert(ret_msg, "- " .. v .. ":\t" .. tostring(misc.save_do_file(v)))
  end
  -- log.DEBUG("Cmds reload result:\n" .. table.concat(ret_msg, "\n"))
end

return {
  reload_cmds = reload_cmds,
  command_list = command_list,
  command_desc_list = command_desc_list,
  gm_command_list = gm_command_list,
  gm_command_desc_list = gm_command_desc_list,
  normal_handler = normal_handler,
  exit_dialog_mode = exit_dialog_mode,
  show_action_hint = show_action_hint,
  resolve_action_hint = resolve_action_hint,
  prompt = prompt,
}