---Save/Load user data
local serialize = require("mud_os/serialize")
local md5 = require("mud_os/md5")
local log = require("mud_os/log")

-- 生产环境由启动脚本设置为持久目录；未设置时保留/tmp回退以兼容开发测试。
USER_DATA_SAVE_PATH = os.getenv("LUA_MUD_SAVE_PATH") or "/tmp/"
if string.sub(USER_DATA_SAVE_PATH, -1) ~= "/" then
  USER_DATA_SAVE_PATH = USER_DATA_SAVE_PATH .. "/"
end

---登录用户列表，用于缓存已经登录了的用户数据
---@type table<string, UserData>
local login_users = {}

---用户存档数据类，可以添加任意成员
---@class UserData:table
---@field user_name string 用户名
---@field pass_token string 密码
local UserData = {
  __name = "UserData",
  user_name = "",
  pass_token = "",
}
---创建UserData实例
---@param value? table 初始化值
---@return UserData #新的UserData实例
UserData.New = function(value)
  value = value or {}
  UserData.__index = UserData
  setmetatable(value, UserData)
  if value.user_name ~= "" then
    login_users[value.user_name] = value
  end
  return value
end

---创建新用户
---@param user_name string 用户名
---@param password string 密码
---@return UserData?, string? # 1.用户数据实例, 2.err 错误信息
UserData.create = function(user_name, password)
  --Check if the file exist
  local save_path = USER_DATA_SAVE_PATH .. user_name .. ".lua";
  local file, err = io.open(save_path, "r")
  if not err then
    io.close(file)
    return nil, "The save file " .. save_path .. "had existed!"
  end

  local user_data = nil
  user_data = UserData.New()
  user_data.user_name = user_name
  user_data.pass_token = md5.sumhexa(password)

  file, err = io.open(save_path, "w")
  if err then
    return nil, err
  end
  if not file then
    return nil, "file " .. save_path .. "open() return nil"
  end
  io.output(file)
  log.INFO("Creating file: " .. save_path)
  serialize.save('player_' .. user_name, user_data)
  io.close(file)

  return user_data
end

---检查用户是否存在
---@param user_name string 用户名
---@return boolean #是否存在
UserData.is_exists = function(user_name)
  local save_path = USER_DATA_SAVE_PATH .. user_name .. ".lua";
  local file, err = io.open(save_path, "r")
  if file then
    io.close(file)
  end
  if err then
    return false
  end
  return true
end

---加载用户数据
---@param user_name string 用户名
---@param password string 密码
---@return UserData?, string? # 1.用户数据实例, 2.err 错误信息
UserData.load = function(user_name, password)
  -- check file exits
  local save_path = USER_DATA_SAVE_PATH .. user_name .. ".lua";
  local file, err = io.open(save_path, "r")
  if err then
    return nil, err
  end
  io.close(file)

  -- load file
  local user_data = login_users[user_name]
  if not user_data then
    local load_obj = dofile(save_path)
    user_data = UserData.New(load_obj)
  end

  -- check password
  local check_token = md5.sumhexa(password)
  if check_token ~= user_data.pass_token then
    log.ERROR("Invalid password!", check_token, user_data.pass_token)
    return nil, "Invalid password!"
  end
  return user_data
end

---保存用户数据
---@param self UserData
---@return boolean, string? #是否成功, 错误信息
UserData.save = function(self)
  local save_path = USER_DATA_SAVE_PATH .. self.user_name .. ".lua";
  local file, err = io.open(save_path, "w");
  if err then
    return false, err
  end
  local save_obj_name = 'player_' .. self.user_name
  if not file then
    return false, "file " .. save_path .. "open() return nil"
  end
  log.INFO("Saving file: " .. save_path)
  io.output(file)
  serialize.save(save_obj_name, self)
  io.close(file)
  return true
end

---清理用户数据
---@param self UserData
UserData.dispose = function(self)
end


return {
  UserData = UserData,
}
