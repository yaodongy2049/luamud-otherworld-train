---@module "mud_lib/cmd/login"
---@description 登录命令模块

local log            = require("mud_os/log")
local misc           = require("mud_os/misc")
local network        = require("mud_os/network")
local telnet         = require("mud_os/telnet")
local command        = require("mud_os/command")
local storage        = require("mud_os/storage")
local heart_of_world = require("mud_os/timer")
local Room           = require("mud_lib/room")

---玩家网络状态枚举
---@enum NetworkStatus
local NetworkStatus = {
  NORMAL = "normal",
  LEAVING = "leaving",
  DISCONNECTED = "disconnected",
  IDLE = "idle"
}

---处于登录过程的用户记录在此
---@type table<string, AnyCmdFun>
local login_progress = {}

---会话池，存储所有连接的客户端会话
---@type table<string, Player>
local session_pool   = {}

---处理用户登录过程的命令函数
---@type AnyCmdFun
local login_fun      = function(user_id, cmds)
  local user_name = "" --[[@type string]]
  local password = "" --[[@type string]]


  local function unknow_cmd(user_id, cmds)
    if cmds[1] and cmds[1] == "unknown" then
      log.WARNING("递归调用！", cmds[1])
      return
    end
    command:process_command(user_id, "unknown")
  end

  local function find_online_user(user_name)
    for k, v in pairs(session_pool) do
      if v.id == user_name then
        return v
      end
    end
  end

  local function login(login_user)
    -- 查找之前在线的用户
    local now_player = find_online_user(login_user.user_name) --[[@as Player]]
    if now_player then
      network.TcpServer:send_to(now_player.user_id, "你的帐号在另外一个地方登录了。")
      if now_player.network_status == NetworkStatus.DISCONNECTED then
        -- 断线重连
        local old_id = now_player.user_id
        session_pool[old_id] = nil
        Room.get_world().channel:leave(old_id)
        
        now_player:reconnect(user_id)
        session_pool[user_id] = now_player
        login_progress[user_id] = unknow_cmd
        Room.get_world().channel:join(user_id, now_player)
        now_player:reply("重新连接成功！")
        command:process_command(now_player.user_id, "look")
        now_player:send_vitals_gmcp()
        return true
      else
        -- 踢掉之前在线的用户
        command:process_command(now_player.user_id, "bye")
      end
    end

    local player_class_file = PLAYER_CLASS or "mud_lib/player"
    local Player            = require(player_class_file)
    now_player              = Player.New(user_id, login_user) --[[@as Player]]
    if not now_player then
      log.ERROR(user_name, "创建玩家实例失败！")
      network.TcpServer:send_to(user_id, "创建玩家实例失败！")
      command:process_command(user_id, "bye")
      return 
    end
    session_pool[user_id] = now_player
    login_progress[user_id] = unknow_cmd -- 登录流程结束，兜底命令处理交给命令系统
    Room.get_world().channel:say(now_player.name .. "进入了这个世界！")
    Room.get_world().channel:join(user_id, now_player)
    if IS_LLM_ENABLED then
      now_player:reply([[
登录成功！你可以直接输入]] .. log.COLORS.LIGHT_BLUE .. [[你想做的动作]] .. log.COLORS.RESET .. [[，大模型将尝试执行。
--------------------------------------------------------------
    ]])
    else
      now_player:reply([[
登录成功！你可以输入]] .. log.COLORS.LIGHT_BLUE .. [[ help ]] .. log.COLORS.RESET .. [[，查看所有游戏命令。
--------------------------------------------------------------
    ]])
    end

    -- 进入上次下线的场景
    local last_room = login_user.cur_room
    if last_room and Room.get_world().rooms[last_room] then
      now_player:fly_to(last_room)
    else
      now_player:fly_to(BORN_POINT or "BornPoint")
    end
    command:process_command(now_player.user_id, "look")

    -- 检查客户端是否支持GMCP，如果支持则发送HP数据
    now_player:send_vitals_gmcp()
  end

  local new_password = nil;
  local function CreateNewUser(user_id, cmds)
    if not new_password then
      new_password = cmds[1]
      login_progress[user_id] = CreateNewUser
      network.TcpServer:send_to(user_id, "请再次输入密码：", true)
      return true
    elseif new_password == cmds[1] then
      local new_user = storage.UserData.create(user_name, new_password)
      network.TcpServer:send_to(user_id, string.format("用户%s创建成功！", user_name))
      login(new_user)
      return true
    else
      new_password = nil
      network.TcpServer:send_to(user_id, "两次密码不一致，请重新输入密码：", true)
    end
  end

  -- 先声明函数变量
  local enter_user_name, enter_password

  enter_password = function(user_id, cmds)
    password = cmds[1]
    if password then
      -- 读取存档文件
      local login_user, err = storage.UserData.load(user_name, password)
      if not login_user then
        --验证失败
        log.WARNING(user_name, err);
        network.TcpServer:send_to(user_id, "错误的用户名或密码，请重新输入用户名：", true)
        login_progress[user_id] = enter_user_name
        return true
      end

      login(login_user)
      return true
    else
      network.TcpServer:send_to(user_id, "空密码，请重新输入：", true)
    end
    return true
  end

  enter_user_name = function(user_id, cmds)
    if cmds and #cmds > 0 then
      user_name = cmds[1]
      if storage.UserData.is_exists(user_name) then
        login_progress[user_id] = enter_password
        network.TcpServer:send_to(user_id, string.format("请输入密码：", user_name), true)
      else
        login_progress[user_id] = CreateNewUser
        network.TcpServer:send_to(user_id, string.format("请创建用户%s，设置密码：", user_name), true)
      end
    else
      login_progress[user_id] = enter_user_name
    end
    return true
  end

  -- 从状态函数表login_progeress{}里面获得行为做操作
  local progress_fun = login_progress[user_id];
  if progress_fun then
    local ret = progress_fun(user_id, cmds)
    return ret
  else
    return enter_user_name(user_id, cmds);
  end
end -- end of any_fun

---新建连接的处理函数。会等待 1 秒后给出欢迎信息，这 1 秒主要用于 telnet 协议协商
---@param user_id string 用户ID
local greeting_fun   = function(user_id)
  -- 创建一个一次性定时器任务
  local timer_task = {
    start_time = os.time(),
    user_id = user_id,

    heart_beat = function(self, current_time)
      log.DEBUG("crrent_time: ", current_time)
      -- 检查是否到达1秒
      if current_time - self.start_time >= 1 then
        -- 执行任务：显示游戏标题和登录提示
        local online_number = 0
        for k, v in pairs(session_pool) do
          online_number = online_number + 1
        end

        -- 获取客户端屏幕宽度
        local screen_width = 80 -- 默认宽度
        local client_info = telnet.client_info[self.user_id]
        if client_info and client_info.window_width then
          screen_width = client_info.window_width
        end

        -- 构建居中的欢迎信息
        local lines = {
          "",
          "欢迎光临《我的游戏》！",
          "由LuaMudOS v0.1开发。",
          "",
        }
        local login_prompt = "请输入用户名："

        local greeting_msg = ""
        local title_lines = GREETING_MSG or lines
        local show_lines = { table.unpack(title_lines) }
        table.insert(show_lines, "当前在线" .. online_number .. "人。")
        for _, line in ipairs(show_lines) do
          if line ~= "" then
            -- 计算居中位置
            local content_width = misc.utf8_display_width(line)
            -- log.DEBUG(string.format("line: `%s`, content_width: %d", line, content_width))
            local padding = math.max(0, math.floor((screen_width - content_width) / 2))
            greeting_msg = greeting_msg .. string.rep(" ", padding) .. line .. "\n"
            -- greeting_msg = greeting_msg .. line .. "\n"
          else
            greeting_msg = greeting_msg .. "\n"
          end
        end
        greeting_msg = greeting_msg .. login_prompt

        -- 回复用户
        network.TcpServer:send_to(self.user_id, greeting_msg, true)

        -- 从定时器中移除
        heart_of_world:del(self)
      end
    end
  }

  -- 添加到定时器系统
  heart_of_world:add(timer_task)

  -- 打印“正在连接服务器”的语句
  network.TcpServer:send_to(user_id, "正在连接服务器，请稍候...", true)
  return true;
end

local function disconnect(conn_num)
  local player = session_pool[conn_num]
  if player then
    player:set_disconnected()
  end
end

---清理玩家连接资源
---@param player Player 玩家对象
local function cleanup_player(player)
  Room.get_world().channel[player.user_id] = nil
end

return {
  greeting_fun = greeting_fun,
  login_fun = login_fun,
  session_pool = session_pool,
  disconnect = disconnect,
  cleanup_player = cleanup_player,
  NetworkStatus = NetworkStatus,
}