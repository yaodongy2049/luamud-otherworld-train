---@module "mud_os/command"
---@description 文本命令行处理系统

local network = require("mud_os/network")
local misc = require("mud_os/misc")

---@alias AcceptFun fun(user_id: string): boolean
---@alias AnyCmdFun fun(user_id: string, cmds: table): boolean
---@alias ProcessorFun fun(user_id: number, cmds: table): boolean

---命令系统，负责委托命令处理给外部处理器
---@class CommandSystem
---@field accept AcceptFun #处理新连接
---@field any_cmd AnyCmdFun #处理无效命令
---@field private command_handler AnyCmdFun #命令处理函数
local CommandSystem = {
  ---处理新连接
  ---@param user_id string 用户ID
  ---@return boolean #是否成功处理新连接
  accept = function(user_id)
    network.TcpServer:send_to(user_id, "Welcome.")
    return true
  end,

  ---处理无效命令
  ---@param user_id string 用户ID
  ---@param cmds table 命令参数表
  ---@return boolean #是否成功处理无效命令
  any_cmd = function(user_id, cmds)
    network.TcpServer:send_to(user_id, "Invalid command.")
    return true
  end,
}

---设置命令处理器
---@param handler ProcessorFun 命令处理函数
---@param accept AcceptFun 处理新连接函数
---@param any_cmd AnyCmdFun 处理无效命令函数
function CommandSystem:set_command_handler(handler, accept, any_cmd)
  self.command_handler = handler
  self.accept = accept
  self.any_cmd = any_cmd
end

---处理命令
---@param self CommandSystem 实例
---@param user_id string 用户ID
---@param command_line string? 命令行字符串
---@return boolean, string? #是否成功执行命令
function CommandSystem:process_command(user_id, command_line)
  if not command_line then
    return self.accept(user_id)
  end

  -- 按照命令行方式解析命令，每个空格分隔一个参数，最后和命令一起放在一个数组里
  local cmds = {}
  command_line = misc.trim(command_line)
  string.gsub(command_line, "[^ ]+", function(w) table.insert(cmds, w) end)

  -- 调用外部命令处理器
  if self.command_handler then
    local ret = self.command_handler(user_id, cmds)
    if ret then
      return ret
    end
  end

  -- 命令未处理，调用any_cmd
  return self.any_cmd(user_id, cmds)
end

function CommandSystem:get_processor()
  return function(client_id, recv_data)
    local result, err_msg
    = self:process_command(client_id, recv_data)
    if (result == false) then
      if not err_msg then
        err_msg = "Unknown error."
      end
      network.TcpServer:send_to(client_id, err_msg)
    end
  end
end

return CommandSystem