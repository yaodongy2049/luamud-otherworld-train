---@module "mud_os/network"
---@desc 网络模块，提供网络连接管理功能

local log = require("mud_os/log")
local socket = require("socket")
local heart_of_world = require("mud_os/timer")

---@class Protocol : table 协议接口
---@interface
---@field initClient fun(self: Protocol, conn_num: string) 初始化客户端状态
---@field cleanupClient fun(self: Protocol, client_id: string) 清理客户端状态
---@field processData fun(self: Protocol, client_id: string, data: string) 处理客户端数据

---TCP 服务器类，管理网络连接和协程
---@class TcpServer
---@field num2client table<string, table> ID 到连接的映射
---@field client2num table<table, string> 连接到 ID 的映射（弱引用）
---@field clients table[] 客户端连接列表
---@field conn_count number 当前连接数
---@field coroutines thread[] 协程池，用于管理需要驱动的协程
---@field protocol Protocol 协议处理模块，如 TelnetHandler
---@field disconnect_handler fun(conn_num: string) 断开连接处理函数
local TcpServer = {
  num2client = {},
  client2num = {},
  clients = {},
  conn_count = 0,
  coroutines = {},
}

---处理客户端发来数据的函数
---@alias CommandHandler fun(client_id: string, command: string?)

---启动 TCP 服务器
---@param self TcpServer TcpServer实例
---@param bind_addr table 绑定地址配置（包含 host 和 port）
---@param protocol Protocol 协议处理模块，如 TelnetHandler
---@param handler CommandHandler 连接以及命令处理函数
function TcpServer.start(self, bind_addr, protocol, handler)
  self:_initialize_server(bind_addr, protocol)
  local server = self.clients[1]

  while true do
    self:_process_network_events(server, handler)
    self:process_coroutines()
    heart_of_world:tick()
  end
end

---初始化服务器配置
---@param bind_addr table 绑定地址配置
---@param protocol Protocol 协议处理模块
function TcpServer:_initialize_server(bind_addr, protocol)
  self.protocol = protocol
  setmetatable(self.client2num, { __mode = "k" })
  bind_addr.host = bind_addr.host or "0.0.0.0"
  bind_addr.port = bind_addr.port or "7777"
  local server = assert(socket.bind(bind_addr.host, bind_addr.port, 1024))
  server:settimeout(0)
  table.insert(self.clients, server)
  log.INFO("Bind the TCP server at " .. bind_addr.host .. ":" .. bind_addr.port)
end

---计算事件循环的等待时间
---@return number #等待时间（秒）
function TcpServer:_calculate_sleep_time()
  local sleep_time = 0.01
  if #self.coroutines > 0 then
    sleep_time = sleep_time / #self.coroutines
  end
  return sleep_time
end

---处理网络事件
---@param server table 服务器socket
---@param handler CommandHandler 连接以及命令处理函数
function TcpServer:_process_network_events(server, handler)
  local sleep_time = self:_calculate_sleep_time()
  local recvt = socket.select(self.clients, nil, sleep_time)

  for _, client in ipairs(recvt) do
    if client == server then
      self:_accept_new_connection(handler)
    else
      self:_handle_client_data(client, handler)
    end
  end
end

---接受新连接
---@param handler CommandHandler 连接处理函数
function TcpServer:_accept_new_connection(handler)
  local conn = self.clients[1]:accept()
  if not conn then return end

  conn:settimeout(0)
  self.conn_count = self.conn_count + 1
  local conn_id = tostring(self.conn_count)

  self.num2client[conn_id] = conn
  self.client2num[conn] = conn_id
  table.insert(self.clients, conn)

  self.protocol:initClient(conn_id)
  log.INFO(string.format("A client(#%s) successfully connect! online: %d", conn_id, #self.client2num))
  handler(conn_id)
end

---处理客户端数据
---@param client table 客户端socket
---@param handler CommandHandler 命令处理函数
function TcpServer:_handle_client_data(client, handler)
  local data, receive_status, partial = client:receive(1024)
  local receive = data or partial
  local conn_num = self.client2num[client]

  if receive_status == 'closed' then
    log.INFO(string.format("Client #%d disconnect!", conn_num))
    self:close_client(conn_num)
    return
  end

  if not receive then return end

  local processed_commands = self.protocol:processData(conn_num, receive)
  if not processed_commands or #processed_commands == 0 then return end

  for _, command in ipairs(processed_commands) do
    handler(conn_num, command)
  end
end

---发送消息到客户端
---@param client_id string 客户端ID
---@param message string 消息内容
---@param no_ret boolean? 是否不添加换行符
---@return boolean, string? #是否成功，错误信息
function TcpServer:send_to(client_id, message, no_ret)
  if not message then
    return false, "Message is nil"
  end
  local client = self.num2client[client_id];
  if not client then
    return false, "Can not find the client connection: " .. client_id
  end
  local output = message:gsub("\n", "\r\n")
  if not no_ret then
    output = output .. '\r\n'
  end
  return client:send(output);
end

---添加协程到协程池
---@param co thread 协程对象
function TcpServer:add_coroutine(co)
  table.insert(self.coroutines, co)
end

---处理协程池中的协程
function TcpServer:process_coroutines()
  local completed_coroutines = {}
  for i, co in ipairs(self.coroutines) do
    if coroutine.status(co) ~= "dead" then
      -- log.DEBUG("resume coroutine " .. i)
      local status, err = coroutine.resume(co)
      if not status then
        log.ERROR("协程错误：" .. err)
        table.insert(completed_coroutines, i)
      end
    else
      table.insert(completed_coroutines, i)
    end
  end

  -- 清理已完成的协程
  for i = #completed_coroutines, 1, -1 do
    table.remove(self.coroutines, completed_coroutines[i])
  end
end

---关闭客户端连接
---@param client_id string 客户端ID
function TcpServer:close_client(client_id)
  local client = self.num2client[client_id];
  if not client then
    return
  end
  self.num2client[client_id] = nil
  self.client2num[client] = nil

  -- Cleanup telnet handler
  self.protocol:cleanupClient(client_id)

  -- 调用断开连接回调
  if self.disconnect_handler then
    self.disconnect_handler(client_id)
  end

  for i, c in pairs(self.clients) do
    if c == client then
      table.remove(self.clients, i)
      client:close();
      collectgarbage();
      return
    end
  end
end

return {
  TcpServer = TcpServer,
}