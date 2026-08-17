---@module "mud_os/telnet"
---@desc Telnet 协议处理模块

local log = require("mud_os/log")
local network = require("mud_os/network")

---Telnet protocol handler
---@class TelnetHandler : Protocol
---@field clients table<string, table> 客户端状态表
---@field client_info table<string, table> 客户端信息表
---@field initClient fun(self: TelnetHandler, client_id: string) 初始化客户端状态
---@field cleanupClient fun(self: TelnetHandler, client_id: string) 清理客户端状态
---@field handle_terminal_type fun(self: TelnetHandler, client_id: string, buffer: string) 处理终端类型子协商
---@field handle_naws fun(self: TelnetHandler, client_id: string, buffer: string) 处理窗口大小子协商
---@field handle_suppress_go_ahead fun(self: TelnetHandler, client_id: string, buffer: string) 处理抑制前向子协商
---@field handle_gmcp fun(self: TelnetHandler, client_id: string, buffer: string) 处理GMCP子协商
local TelnetHandler = {
  -- Telnet command definitions
  IAC = string.char(255), -- Interpret As Command
  DONT = string.char(254),
  DO = string.char(253),
  WONT = string.char(252),
  WILL = string.char(251),
  SB = string.char(250), -- Subnegotiation Begin
  SE = string.char(240), -- Subnegotiation End

  -- Telnet options
  ECHO = string.char(1),
  SUPPRESS_GO_AHEAD = string.char(3),
  LINEMODE = string.char(34),      -- Line mode option
  TERMINAL_TYPE = string.char(24), -- Terminal type option (0x18)
  NAWS = string.char(31),          -- Negotiate About Window Size (0x1F)
  GMCP = string.char(201),         -- Generic Mud Communication Protocol (0xC9)

  -- Client states
  clients = {},
  client_info = {},

  ---初始化客户端状态
  ---@param client_id string 客户端ID
  initClient = function(self, client_id)
    self.clients[client_id] = {
      in_negotiation = false,
      negotiation_buffer = "",
      data_buffer = "",
      -- Track negotiated options to avoid loops
      negotiated = {
        terminal_type = false,
        naws = false,
        suppress_go_ahead = false,
        gmcp = false
      }
    }
    self.client_info[client_id] = {
      terminal_type = nil,
      window_width = nil,
      window_height = nil,
      gmcp_supported = false,
      gmcp_modules = {}
    }

    -- Send telnet negotiations
    local TcpServer = network.TcpServer
    TcpServer:send_to(client_id, self.IAC .. self.DO .. self.NAWS, true)
    TcpServer:send_to(client_id, self.IAC .. self.DO .. self.ECHO, true)
    TcpServer:send_to(client_id, self.IAC .. self.DO .. self.GMCP, true)
    --TcpServer:SendTo(client_id, self.IAC .. self.DO .. self.SUPPRESS_GO_AHEAD, true)
    --TcpServer:SendTo(client_id, self.IAC .. self.DO .. self.LINEMODE, true)
    --TcpServer:SendTo(client_id, self.IAC .. self.DO .. self.TERMINAL_TYPE, true)
  end,

  ---清理客户端状态
  ---@param client_id number 客户端ID
  cleanupClient = function(self, client_id)
    self.clients[client_id] = nil
    self.client_info[client_id] = nil
  end,

  ---处理终端类型子协商
  ---@param client_id number 客户端ID
  ---@param buffer string 协商缓冲区
  handle_terminal_type = function(self, client_id, buffer)
    local suboption = string.byte(buffer, 3)
    if suboption == 0 then -- IS
      local terminal_type = string.sub(buffer, 4, #buffer - 1)
      self.client_info[client_id].terminal_type = terminal_type
      log.DEBUG(string.format("Telnet terminal type: Client #%s is using %s", client_id, terminal_type))
    end
  end,

  ---处理NAWS窗口大小子协商
  ---@param client_id number 客户端ID
  ---@param buffer string 协商缓冲区
  handle_naws = function(self, client_id, buffer)
    -- NAWS format: IAC SB NAWS width_high width_low height_high height_low IAC SE
    if #buffer >= 5 then
      local width_high = string.byte(buffer, 3)
      local width_low = string.byte(buffer, 4)
      local height_high = string.byte(buffer, 5)
      local height_low = string.byte(buffer, 6)
      local width = width_high * 256 + width_low
      local height = height_high * 256 + height_low
      self.client_info[client_id].window_width = width
      self.client_info[client_id].window_height = height
      log.DEBUG(string.format("Telnet window size: Client #%s has window %dx%d", client_id, width, height))
    end
  end,

  ---处理GMCP子协商
  ---@param client_id number 客户端ID
  ---@param buffer string 协商缓冲区
  handle_gmcp = function(self, client_id, buffer)
    -- GMCP format: IAC SB GMCP <module> <data> IAC SE
    local gmcp_data = string.sub(buffer, 3)
    if gmcp_data and #gmcp_data > 0 then
      local module, content = string.match(gmcp_data, "^([^ ]+) (.*)$")
      if module then
        self.client_info[client_id].gmcp_supported = true
        self.client_info[client_id].gmcp_modules[module] = content
        log.DEBUG(string.format("GMCP data received from client #%s: %s", client_id, gmcp_data))
      end
    end
  end,

  ---处理子协商数据
  ---@param client_id number 客户端ID
  ---@param buffer string 协商缓冲区
  handle_subnegotiation = function(self, client_id, buffer)
    if #buffer == 0 then
      return
    end
    local sub_type = string.byte(buffer, 2)
    if sub_type == string.byte(self.TERMINAL_TYPE) then
      self:handle_terminal_type(client_id, buffer)
    elseif sub_type == string.byte(self.NAWS) then
      self:handle_naws(client_id, buffer)
    elseif sub_type == string.byte(self.GMCP) then
      self:handle_gmcp(client_id, buffer)
    end
  end,

  ---处理协商命令，返回是否需要继续协商
  ---@param client_id string 客户端ID
  ---@param state table 客户端状态表
  ---@param cmd string 命令字节
  ---@param option string 选项字节
  ---@return boolean
  handle_negotiation_command = function(self, client_id, state, cmd, option)
    -- Handle DO SUPPRESS_GO_AHEAD (FF FD 03)
    if cmd == self.DO and option == self.SUPPRESS_GO_AHEAD then
      log.DEBUG(string.format("Telnet negotiation: Client #%s sent DO SUPPRESS_GO_AHEAD", client_id))
      state.negotiated.suppress_go_ahead = true
      return false
    end

    -- Handle WILL TERMINAL_TYPE (FF FB 18)
    if cmd == self.WILL and option == self.TERMINAL_TYPE and not state.negotiated.terminal_type then
      log.DEBUG(string.format("Telnet negotiation: Client #%s sent WILL TERMINAL_TYPE", client_id))
      network.TcpServer:send_to(client_id, self.IAC .. self.DO .. self.TERMINAL_TYPE, true)
      network.TcpServer:send_to(client_id,
        self.IAC .. self.SB .. self.TERMINAL_TYPE .. string.char(1) .. self.IAC .. self.SE,
        true)
      state.negotiated.terminal_type = true
      return false
    end

    -- Handle DONT ECHO (FF FE 01)
    if cmd == self.DONT and option == self.ECHO then
      log.DEBUG(string.format("Telnet negotiation: Client #%s sent DONT ECHO", client_id))
      network.TcpServer:send_to(client_id, self.IAC .. self.WONT .. self.ECHO, true)
      return false
    end

    -- Handle WILL GMCP (FF FB C9)
    if cmd == self.WILL and option == self.GMCP and not state.negotiated.gmcp then
      log.DEBUG(string.format("Telnet negotiation: Client #%s sent WILL GMCP", client_id))
      network.TcpServer:send_to(client_id, self.IAC .. self.DO .. self.GMCP, true)
      state.negotiated.gmcp = true
      self.client_info[client_id].gmcp_supported = true
      log.DEBUG(string.format("GMCP is now enabled for client #%s", client_id))
      return false
    end

    -- Default: continue negotiation if SB
    return cmd == self.SB
  end,

  ---处理原始数据通过telnet协议，返回处理后的命令列表
  ---@param client_id number 客户端ID
  ---@param raw_data string 原始数据
  ---@return table
  processData = function(self, client_id, raw_data)
    local state = self.clients[client_id]
    if not state then
      self:initClient(client_id)
      state = self.clients[client_id]
    end

    -- Print raw binary data
    --   local hex_data = ""
    --   for i = 1, #raw_data do
    --     local byte = string.byte(string.sub(raw_data, i, i))
    --     hex_data = hex_data .. string.format("%02X ", byte)
    --   end
    --   log.DEBUG(string.format("Telnet raw data: Client #%s received: %s", client_id, hex_data))

    local processed_commands = {}

    for i = 1, #raw_data do
      local char = string.sub(raw_data, i, i)

      if state.in_negotiation then
        if char == self.SE then
          -- End of subnegotiation
          self:handle_subnegotiation(client_id, state.negotiation_buffer)
          state.in_negotiation = false
          state.negotiation_buffer = ""
        else
          -- Add to negotiation buffer
          state.negotiation_buffer = state.negotiation_buffer .. char

          -- Check if we have a complete command
          if #state.negotiation_buffer == 2 then
            local cmd = string.sub(state.negotiation_buffer, 1, 1)
            local option = string.sub(state.negotiation_buffer, 2, 2)

            local continue = self:handle_negotiation_command(client_id, state, cmd, option)
            if not continue then
              state.negotiation_buffer = ""
              state.in_negotiation = false
            end
          end
        end
      else
        if char == self.IAC then -- Start of command
          state.in_negotiation = true
          state.negotiation_buffer = ""
        else
          if (char == "\r" or char == "\n") then -- End of line, add to commands
            table.insert(processed_commands, state.data_buffer)
            state.data_buffer = ""
          else
            state.data_buffer = state.data_buffer .. char -- Add to data buffer
          end
        end
      end
    end

    return processed_commands
  end,

  ---发送GMCP命令, 返回是否成功
  ---@param client_id string 客户端ID
  ---@param module string GMCP模块名
  ---@param data string GMCP数据
  ---@return boolean
  send_gmcp = function(self, client_id, module, data)
    local client_info = self.client_info[client_id]
    if not client_info or not client_info.gmcp_supported then
      return false
    end

    -- 构建GMCP数据包
    local gmcp_data = module .. " " .. data
    local gmcp_packet = self.IAC .. self.SB .. self.GMCP .. gmcp_data .. self.IAC .. self.SE

    -- 发送数据包
    local success, err = network.TcpServer:send_to(client_id, gmcp_packet, true)
    if success then
      log.DEBUG(string.format("GMCP command sent to client #%s: %s", client_id, gmcp_data))
    else
      log.WARNING(string.format("Failed to send GMCP command to client #%s: %s", client_id, err))
    end

    return success
  end
}

return TelnetHandler
