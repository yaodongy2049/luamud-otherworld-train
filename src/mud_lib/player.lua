---@module 'mud_lib/player'
local log            = require("mud_os/log")
local heart_of_world = require("mud_os/timer")
local telnet         = require("mud_os/telnet")
local network        = require("mud_os/network")
local class          = require("mud_os/class")
local cjson          = require("cjson")
local Charactor      = require("mud_lib/char")
local login          = require("mud_lib/login")
local cmds           = require("mud_lib/cmds")

---发呆状态判定时间（秒）
local IDLE_TIMEOUT = 300

---断线超时时间（秒），超过此时间则清理玩家
local DISCONNECT_TIMEOUT = 300

---玩家类
---@class Player : Charactor, HeartBeatObject
---@field New fun(user_id:string, user_data:UserData):Player 构造函数
---@field user_data UserData 存储的玩家数据
---@field user_id string 通信用的ID
---@field desc string 玩家的描述
---@field dynamic_cmds table<string, CmdFunc> 动态命令列表
---@field dynamic_cmds_desc table<string, string> 动态命令描述列表
---@field temp_status TempStatus 临时状态，存储短时间内有效的状态信息
---@field network_status NetworkStatus 网络状态：正常、离线、断线、发呆
---@field last_input_time number 最后输入时间戳
Player = {
  __name = "Player",
  user_id = "",
  desc = "一个普通的玩家",
  dynamic_cmds = {},
  dynamic_cmds_desc = {},
  temp_status = {},
  network_status = login.NetworkStatus.NORMAL,
  last_input_time = 0,
  offline_time = 0
}

---设置游戏逻辑数据到存档中
---@param key string 键名
---@param value any 键值
function Player:set_user_data(key, value)
  local user_table = self.user_data --[[@as table]]
  user_table[key] = value
end

---获取游戏逻辑数据，优先从存档中获取，若不存在则从默认属性中获取
---@param key string 键名
---@return any #键值
function Player:get_user_data(key)
  local user_table = self.user_data --[[@as table]]
  if not user_table[key] then
    return self[key]
  end
  return user_table[key]
end

---创建玩家实例
---@param user_id string 通信用的ID
---@param user_data UserData 存储的玩家数据
function Player:init(user_id, user_data)
  if user_id and user_data then
    self.user_data = user_data
    self.user_id = user_id

    self.id = user_data.user_name -- 玩家的英文ID
    self.name = self:get_user_data("nick_name") or user_data.user_name
    self.desc = self:get_user_data("desc") or self.desc

    -- 加载保存的HP数据
    self.hp = self:get_user_data("hp")
    self.max_hp = self:get_user_data("max_hp")

    -- 加载背包物品
    local inventory_data = self:get_user_data("inventory")
    if inventory_data and type(inventory_data) == "table" then
      local Item = require("mud_lib/item")
      for _, item_data in ipairs(inventory_data) do
        local prefab = GLOBAL_ITEM_LIST[item_data.id]
        local item = class.clone(prefab)
        item.count = item_data.count
        -- 只有不可堆叠的物品才加载 custom 字段
        if not item.is_stackable and item_data.custom then
          item.custom = item_data.custom
        end
        item:put(self)
      end
    end

    -- 加载装备（根据content数组索引查找）
    local equipment_data = self:get_user_data("equipment")
    if equipment_data and type(equipment_data) == "table" then
      for pos, content_index in pairs(equipment_data) do
        -- 根据数组索引从背包中获取物品
        if self.content[content_index] then
          local equip = self.content[content_index] --[[@as Item]]
          self.equipment[pos] = equip
        end
      end
    end

    self.last_input_time = os.time()
    self.login_time = os.time()
    self.heart_id = heart_of_world:add(self)
  end
  return self
end

function Player:heart_beat(now)
  Charactor.heart_beat(self, now)

  local current_time = os.time()

  if self.network_status == login.NetworkStatus.NORMAL then
    if current_time - self.last_input_time >= IDLE_TIMEOUT then
      self.network_status = login.NetworkStatus.IDLE
      log.INFO("玩家 " .. self.name .. " 进入发呆状态")
    end
  elseif self.network_status == login.NetworkStatus.DISCONNECTED then
    if current_time - self.offline_time >= DISCONNECT_TIMEOUT then
      log.INFO("玩家 " .. self.name .. " 断线超时，强制下线")
      self:cleanup()
    end
  end
end

function Player:reset_input_timer()
  self.last_input_time = os.time()
  if self.network_status == login.NetworkStatus.IDLE then
    self.network_status = login.NetworkStatus.NORMAL
    log.INFO("玩家 " .. self.name .. " 从发呆状态恢复")
  end
end

function Player:set_disconnected()
  if self.network_status ~= login.NetworkStatus.LEAVING then
    self.network_status = login.NetworkStatus.DISCONNECTED
    self.offline_time = os.time()
    log.INFO("玩家 " .. self.name .. " 连接断开")
  end
end

function Player:set_leaving()
  self.network_status = login.NetworkStatus.LEAVING
  self.is_leaving = true
end

---清理玩家（下线）
---统一处理正常退出、断线超时等场景的下线逻辑
function Player:cleanup()
  if self.network_status == login.NetworkStatus.LEAVING then
    return
  end

  self:set_leaving()
  login.cleanup_player(self)
  network.TcpServer:close_client(self.user_id)
  self:dispose()
end

function Player:reconnect(user_id)
  if self.network_status == login.NetworkStatus.DISCONNECTED then
    self.user_id = user_id
    self.network_status = login.NetworkStatus.NORMAL
    self.last_input_time = os.time()
    self.login_time = os.time()
    log.INFO("玩家 " .. self.name .. " 重新连接")
    return true
  end
  return false
end

---发消息给用户
---@param message string 消息内容
function Player:reply(message)
  network.TcpServer:send_to(self.user_id, message)
end


---获取对话模式下的提示符
---@return string #提示符
function Player:get_dialog_prompt()
  if self.temp_status and self.temp_status.dev_mode then
    return log.COLORS.GRAY .. "dev_mode" .. log.COLORS.RESET .. cmds.prompt
  end

  if not self.temp_status or not self.temp_status.last_say_target then
    return cmds.prompt
  end

  local this_place = self.environment
  if not this_place then
    return cmds.prompt
  end

  local targets = this_place:resolve_content(self.temp_status.last_say_target, self.user_id)
  if #targets > 0 then
    local target_char = targets[1] --[[@as Charactor]]
    if target_char.name then
      return log.COLORS.BLUE .. target_char.name .. "：" .. log.COLORS.RESET .. cmds.prompt
    end
  end

  return cmds.prompt
end

---发送提示符给玩家
function Player:send_prompt()
    network.TcpServer:send_to(self.user_id, self:get_dialog_prompt(), true)
end

---获取玩家显示名称（包含网络状态）
---@return string #显示名称
function Player:display_name()
  local status_str = ""
  if self.network_status == login.NetworkStatus.DISCONNECTED then
    status_str = " <断线> "
  elseif self.network_status == login.NetworkStatus.IDLE then
    status_str = " <发呆> "
  elseif self.network_status == login.NetworkStatus.LEAVING then
    status_str = " <退出> "
  end
  return self.name .. status_str
end

---玩家传输到目标房间
---@param room_id string 目标房间ID
---@param after_msg string? 传送后显示的消息
---@return boolean #是否成功传输
function Player:fly_to(room_id, after_msg)
  local room = Room.get_world().rooms[room_id]
  if room then
    local ret = self:enter(room)
    if ret then
      if after_msg then
        self:reply(after_msg)
      else
        self:reply("你正身处于" .. room.title .. "。")
      end
    end
    return ret
  end
  log.WARNING("玩家" .. self.name .. "尝试传输到不存在的房间" .. room_id)
  self:reply("你脚下的空间一阵扭曲，但你依然呆在原地。")
  return false
end

---进入房间
---@param room Room 目标房间
---@return boolean #是否成功进入
function Player:enter(room)
  -- 删除本房间中在玩家身上的指令
  local this_place = self.environment --[[@as Room]]
  if this_place then
    if this_place.avg_cmds then
      for k in pairs(this_place.avg_cmds) do
        self.dynamic_cmds[k] = nil
        self.dynamic_cmds_desc[k] = nil
      end
    end
    -- 离开老房间，进入新房间
    if this_place.channel then
      this_place.channel:leave(self.user_id)
    end
  end

  -- 进入新房间
  Charactor.enter(self, room)
  room.channel:join(self.user_id, self)

  -- 更新玩家动态指令列表
  if room.avg_cmds then
    for key, value in pairs(room.avg_cmds) do
      self.dynamic_cmds[key] = value
      self.dynamic_cmds_desc[key] = room.avg_cmds_desc[key] or "缺失描述"
    end
  end
  return true
end

function Player:save()
  -- 保存展示数据
  self:set_user_data("nick_name", self.name)
  self:set_user_data("desc", self.desc)

  -- 保存当前HP
  self:set_user_data("hp", self.hp)
  self:set_user_data("max_hp", self.max_hp)

  -- 保存下线地点
  local this_place = self.environment --[[@as Room]]
  if not class.is_empty(this_place) then
    self:set_user_data("cur_room", this_place.id)
  end

  -- 保存背包物品
  local inventory_data = {}
  for _, obj in ipairs(self.content) do
    local item = obj --[[@as Item]]
    local item_save_data = {
      id = item.id,
      count = item.count,
    }
    -- 只有不可堆叠的物品才保存 custom 字段
    if not item.is_stackable and item.custom and next(item.custom) then
      item_save_data.custom = item.custom
    end
    table.insert(inventory_data, item_save_data)
  end
  self:set_user_data("inventory", inventory_data)

  -- 保存装备信息（记录物品在content数组中的索引位置）
  local equipment_data = {}
  for pos, item in pairs(self.equipment) do
    -- 查找物品在content数组中的索引
    for index, obj in ipairs(self.content) do
      if obj == item then
        equipment_data[pos] = index
        break
      end
    end
  end
  self:set_user_data("equipment", equipment_data)

  self.user_data:save()
end

function Player:dispose()
  self:save()
  self.user_data:dispose()

  local this_place = self.environment --[[@as Room]]
  if this_place then
    this_place.channel:say(self.name .. "下线了", self)
    this_place.channel:leave(self.user_id)
  end
  Charactor.dispose(self)
  login.session_pool[self.user_id] = nil
end

---发送状态相关的GMCP数据
function Player:send_vitals_gmcp()
  local client_id = self.user_id
  local client_info = telnet.client_info[client_id]
  if client_info and client_info.gmcp_supported then
    local data = self:status_gmcp()
    telnet:send_gmcp(client_id, "Char.Vitals", cjson.encode(data))
  end
end

---获取状态相关的GMCP数据，可被子类重写
---@return table
function Player:status_gmcp()
  return {
    hp = self.hp,
    max_hp = self.max_hp
  }
end

class.define_class(Player, Charactor)
return Player