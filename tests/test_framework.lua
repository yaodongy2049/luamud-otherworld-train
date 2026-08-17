---@module "tests/test_framework"
---@description 自动化测试框架 - 不依赖TCP网络连接，直接模拟用户交互
--- 架构原理：
---   1. Mock network.TcpServer:send_to() 捕获所有输出消息
---   2. 直接调用 command:process_command(user_id, cmd) 模拟命令输入
---   3. 通过状态机管理登录流程（login_progress表）
---   4. 手动驱动定时器系统，跳过真实网络等待

-- ========================================
--- 必须在require任何模块前设置全局变量
-- ========================================
IS_LLM_ENABLED = false
OLLAMA_HOST = "http://127.0.0.1:11434"
MUD_LIB_PATH = "./src/mud_lib/"
PLAYER_CLASS = "mud_lib/chars/investigator"
BORN_POINT = "StationHall"

package.path = package.path .. ";./src/?.lua;./src/?/init.lua;./tests/?.lua"

-- ========================================
--- 加载模块
-- ========================================
local log = require("mud_os/log")
local socket = require("socket")
local network = require("mud_os/network")
local telnet = require("mud_os/telnet")
local command = require("mud_os/command")
local cmds = require("mud_lib/cmds")
local Room = require("mud_lib/room")
local login = require("mud_lib/login")
local storage = require("mud_os/storage")
local semantic = require("mud_os/semantic_match")
local heart_of_world = require("mud_os/timer")
local misc = require("mud_os/misc")

-- ========================================
--- Mock语义匹配（LLM禁用时返回nil）
-- ========================================
semantic.best_match = function() return nil end

-- ========================================
--- 测试数据目录（独立临时目录）
-- ========================================
local TEST_DATA_PATH = "/tmp/luamud_test_" .. tostring(os.time()) .. "/"
os.execute("mkdir -p " .. TEST_DATA_PATH)
storage.USER_DATA_SAVE_PATH = TEST_DATA_PATH

-- ========================================
--- 测试客户端类
-- ========================================
---@class TestClient
---@field user_id string 模拟客户端ID
---@field output_buffer string[] 输出消息缓冲区
local TestClient = {}
TestClient.__index = TestClient

function TestClient.New(client_id)
    local self = setmetatable({}, TestClient)
    self.user_id = tostring(client_id)
    self.output_buffer = {}
    return self
end

function TestClient:clear_output()
    self.output_buffer = {}
end

function TestClient:get_output()
    return table.concat(self.output_buffer, "\n")
end

function TestClient:output_contains(pattern)
    return string.find(self:get_output(), pattern, 1, true) ~= nil
end

-- ========================================
--- 测试框架主类
-- ========================================
---@class TestFramework
---@field clients table<string, TestClient> 模拟客户端列表
local TestFramework = {
    clients = {},
    _original_send_to = nil,
    _original_close_client = nil,
    test_count = 0,
    pass_count = 0,
    fail_count = 0,
    failed_tests = {},
}

---初始化测试环境
function TestFramework.setup()
    log.set_log_level(100)
    
    TestFramework._original_send_to = network.TcpServer.send_to
    TestFramework._original_close_client = network.TcpServer.close_client
    
    -- Mock send_to: 捕获输出
    network.TcpServer.send_to = function(self, client_id, message, no_ret)
        local client = TestFramework.clients[client_id]
        if client and message then
            local clean_msg = message
            clean_msg = clean_msg:gsub("\255.", "")
            clean_msg = clean_msg:gsub("\r\n", "\n")
            clean_msg = clean_msg:gsub("\r", "")
            clean_msg = clean_msg:gsub("\27%[[%d;]*m", "")
            
            for line in clean_msg:gmatch("[^\n]+") do
                line = misc.trim(line)
                if line ~= "" then
                    table.insert(client.output_buffer, line)
                end
            end
        end
        return true
    end
    
    -- Mock close_client: 不关闭socket
    network.TcpServer.close_client = function(self, client_id)
        local client = TestFramework.clients[client_id]
        if not client then return end
        self.num2client[client_id] = nil
        if self.protocol and self.protocol.cleanupClient then
            self.protocol:cleanupClient(client_id)
        end
        if self.disconnect_handler then
            self.disconnect_handler(client_id)
        end
    end
    
    -- 初始化命令系统
    cmds.reload_cmds()
    command:set_command_handler(cmds.normal_handler, login.greeting_fun, login.login_fun)
    network.TcpServer.disconnect_handler = login.disconnect
    network.TcpServer.protocol = telnet
    
    -- 加载地图
    Room:load_all_maps()
    
    -- 初始化网络状态表
    network.TcpServer.num2client = {}
    network.TcpServer.client2num = {}
    network.TcpServer.clients = {}
    network.TcpServer.conn_count = 0
end

---清理测试环境
function TestFramework.teardown()
    network.TcpServer.send_to = TestFramework._original_send_to
    network.TcpServer.close_client = TestFramework._original_close_client
    for k in pairs(login.session_pool) do
        login.session_pool[k] = nil
    end
    os.execute("rm -rf " .. TEST_DATA_PATH)
end

---触发所有待处理定时器
--- 关键：greeting等定时器在heart_beat中自己检查时间差（current_time - start_time >= 1）
--- 所以我们不能只依赖tick()，需要传入一个"未来时间"来让定时器认为时间已到
function TestFramework.drain_pending_timers()
    local fake_future = os.time() + 999
    for _ = 1, 10 do
        local to_process = {}
        for idx, obj in pairs(heart_of_world.members) do
            if obj and obj.heart_beat then
                table.insert(to_process, {idx = idx, obj = obj})
            end
        end
        
        for _, item in ipairs(to_process) do
            local ret = item.obj:heart_beat(fake_future)
            if ret == false then
                heart_of_world.members[item.idx] = nil
            end
        end
        
        heart_of_world.last_beat_time = 0
        heart_of_world:tick()
    end
end

---创建新连接（模拟客户端连接服务器）
---@return TestClient
function TestFramework.connect()
    -- 模拟真实TCP连接：cid就是递增的连接序号（字符串类型，和真实代码一致）
    network.TcpServer.conn_count = network.TcpServer.conn_count + 1
    local client = TestClient.New(network.TcpServer.conn_count)
    TestFramework.clients[client.user_id] = client
    -- 存一个mock socket对象（空table即可，因为我们已经mock了send_to）
    network.TcpServer.num2client[client.user_id] = {}
    
    telnet:initClient(client.user_id)
    command:process_command(client.user_id, nil)
    
    TestFramework.drain_pending_timers()
    
    return client
end

---向客户端发送命令
---@param client TestClient
---@param cmd string
function TestFramework.send(client, cmd)
    client:clear_output()
    command:process_command(client.user_id, cmd)
    TestFramework.drain_pending_timers()
end

---真正彻底清理玩家（退出世界，从session_pool移除）
---@param client TestClient
local function force_cleanup_player(client)
    local player = login.session_pool[client.user_id]
    if player then
        pcall(function() player:leave() end)
        pcall(function() heart_of_world:del(player.heart_id) end)
        login.session_pool[client.user_id] = nil
    end
end

---断开客户端连接
---@param client TestClient
function TestFramework.disconnect(client)
    force_cleanup_player(client)
    pcall(function() telnet:cleanupClient(client.user_id) end)
    network.TcpServer.num2client[client.user_id] = nil
    TestFramework.clients[client.user_id] = nil
end

-- ========================================
--- 断言函数
-- ========================================
function TestFramework.assert(condition, message)
    TestFramework.test_count = TestFramework.test_count + 1
    if condition then
        TestFramework.pass_count = TestFramework.pass_count + 1
    else
        TestFramework.fail_count = TestFramework.fail_count + 1
        table.insert(TestFramework.failed_tests, message)
        print("  [FAIL] " .. message)
    end
end

function TestFramework.assert_output_contains(client, expected, desc)
    desc = desc or ("输出应包含: " .. expected)
    local found = client:output_contains(expected)
    if not found then
        print("  [DEBUG] 实际输出:\n" .. client:get_output())
    end
    TestFramework.assert(found, desc)
end

function TestFramework.assert_not_contains(client, text, desc)
    desc = desc or ("输出不应包含: " .. text)
    TestFramework.assert(not client:output_contains(text), desc)
end

-- ========================================
--- 测试运行器
-- ========================================
function TestFramework.run_test(test_name, test_func)
    print("=== 测试: " .. test_name .. " ===")
    
    -- 先清理所有当前客户端（无论是否登录完成）
    for cid, client in pairs(TestFramework.clients) do
        local player = login.session_pool[cid]
        if player then
            pcall(function() player:leave() end)
            pcall(function() heart_of_world:del(player.heart_id) end)
            login.session_pool[cid] = nil
        end
        pcall(function() telnet:cleanupClient(cid) end)
    end
    
    -- 再清理session_pool中可能残留的玩家
    for cid, player in pairs(login.session_pool) do
        pcall(function() player:leave() end)
        pcall(function() heart_of_world:del(player.heart_id) end)
    end
    for k in pairs(login.session_pool) do
        login.session_pool[k] = nil
    end
    
    -- 清理世界频道
    local world = Room.get_world()
    if world and world.channel then
        for k in pairs(world.channel) do
            world.channel[k] = nil
        end
    end
    
    -- 清理所有房间内容中的玩家残留
    if world and world.rooms then
        for _, room in pairs(world.rooms) do
            if room.content then
                for i = #room.content, 1, -1 do
                    local obj = room.content[i]
                    if obj and obj.__name == "Player" then
                        table.remove(room.content, i)
                    end
                end
            end
        end
    end
    
    TestFramework.clients = {}
    network.TcpServer.num2client = {}
    -- 关键：conn_count 全局递增永不重置，保证每个连接cid唯一
    -- network.TcpServer.conn_count = 0  -- 不要重置！
    
    local ok, err = pcall(test_func)
    if not ok then
        TestFramework.test_count = TestFramework.test_count + 1
        TestFramework.fail_count = TestFramework.fail_count + 1
        table.insert(TestFramework.failed_tests, test_name .. " (异常: " .. tostring(err) .. ")")
        print("  [ERROR] " .. tostring(err))
        print(debug.traceback())
    end
end

function TestFramework.print_summary()
    print(string.format("\n========================================"))
    print(string.format("测试结果: 总计 %d, 通过 %d, 失败 %d",
        TestFramework.test_count, TestFramework.pass_count, TestFramework.fail_count))
    
    if #TestFramework.failed_tests > 0 then
        print("\n失败的测试:")
        for i, name in ipairs(TestFramework.failed_tests) do
            print(string.format("  %d. %s", i, name))
        end
    end
    print("========================================")
    
    return TestFramework.fail_count == 0
end

-- ========================================
--- 辅助函数：简化测试流程
-- ========================================

---注册一个新用户并登录
---@param username string
---@param password string?
---@return TestClient
function TestFramework.register_user(username, password)
    password = password or "testpass"
    local client = TestFramework.connect()
    
    TestFramework.send(client, username)
    TestFramework.assert_output_contains(client, "设置密码", "新用户应提示设置密码")
    
    TestFramework.send(client, password)
    TestFramework.assert_output_contains(client, "请再次输入密码", "应要求确认密码")
    
    TestFramework.send(client, password)
    TestFramework.assert_output_contains(client, "创建成功", "应提示创建成功")
    TestFramework.assert_output_contains(client, "登录成功", "应自动登录")
    
    return client
end

---登录已存在的用户
---@param username string
---@param password string?
---@return TestClient
function TestFramework.login_user(username, password)
    password = password or "testpass"
    local client = TestFramework.connect()
    
    TestFramework.send(client, username)
    TestFramework.assert_output_contains(client, "请输入密码", "已存在用户应提示输入密码")
    
    TestFramework.send(client, password)
    TestFramework.assert_output_contains(client, "登录成功", "密码正确应登录成功")
    
    return client
end

return TestFramework