---@module "mud_os/timer"
---@desc 定时器系统（心跳）

---@class HeartBeatObject
---@interface
---@field heart_beat fun(self:HeartBeatObject, now:number):boolean|nil 心跳函数，返回 false 可删除自己
---@field interval number 可选，回调间隔秒数，默认为心跳频率
---@field last_call_time number 上次调用时间（内部使用）

local log = require("mud_os/log")
local socket = require("socket")

---Timer System
---@class HeartOfWorld
---@field rate number 心跳频率（秒）
---@field members table<number, HeartBeatObject> 心跳对象列表（弱引用）
---@field last_beat_time number 上次心跳时间
local HeartOfWorld = {
  rate = 0.1,
  last_beat_time = 0,
  members = {}
}

---添加心跳对象
---@param heart HeartBeatObject|function 心跳对象或回调函数
---@param interval number|nil 可选，回调间隔秒数，默认1秒
---@return number #对象索引
function HeartOfWorld:add(heart, interval)
  local next_idx = #(self.members) + 1
  
  -- 如果传入的是函数，包装成心跳对象
  if type(heart) == "function" then
    heart = {
      heart_beat = heart,
      interval = interval or 1,
      last_call_time = 0
    }
  else
    -- 支持通过参数设置间隔
    if interval then
      heart.interval = interval
    elseif not heart.interval then
      heart.interval = 1
    end
  end
  
  -- 初始化上次调用时间
  if heart.last_call_time == 0 then
    heart.last_call_time = os.time()
  end
  
  self.members[next_idx] = heart
  return next_idx
end

---删除心跳对象
---@param heart_or_idx number|HeartBeatObject 心跳对象或索引
function HeartOfWorld:del(heart_or_idx)
  local idx = heart_or_idx
  if type(heart_or_idx) ~= 'number' then
    for i, obj in pairs(self.members) do
      if obj == heart_or_idx then
        idx = i
        break
      end
    end
  end
  if type(idx) == "number" then
    self.members[idx] = nil
  end
end

---特殊返回值，用于删除定时器
local REMOVE_SELF = false

---执行心跳
function HeartOfWorld:tick()
  local now = socket.gettime()
  local interval = now - self.last_beat_time
  if interval >= self.rate then
    self.last_beat_time = now

    -- 初始化随机数种子（转换为整数）
    math.randomseed(math.floor(now*1000))

    -- Make hearts beating
    -- 需要收集要删除的索引，避免在迭代中修改表
    local to_remove = {}
    for idx, obj in pairs(self.members) do
      -- 弱引用可能已经被 GC，需要检查
      if obj == nil then
        table.insert(to_remove, idx)
      elseif obj.heart_beat and type(obj.heart_beat) == 'function' then
        -- 检查是否到达调用间隔
        local call_interval = obj.interval or self.rate
        if now - (obj.last_call_time or 0) >= call_interval then
          obj.last_call_time = now
          -- 调用回调，支持返回 false 删除自己
          local ret = obj:heart_beat(now)
          if ret == REMOVE_SELF then
            table.insert(to_remove, idx)
          end
        end
      else
        -- 对象不合法，删除
        table.insert(to_remove, idx)
      end
    end
    
    -- 删除标记的对象
    for _, idx in ipairs(to_remove) do
      self.members[idx] = nil
    end
  end
end

---创建一次性定时器
---@param delay number 延迟秒数
---@param callback function 回调函数
---@return number #定时器索引
function HeartOfWorld:after(delay, callback)
  local timer_obj = {
    heart_beat = function(self, now)
      callback(now)
      return REMOVE_SELF -- 执行一次后删除
    end,
    interval = delay,
    last_call_time = os.time()
  }
  return self:add(timer_obj)
end

return HeartOfWorld