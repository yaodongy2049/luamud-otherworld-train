---@module "mud_lib/room"
---@description 房间模块

local log = require("mud_os/log")
local semantic_match = require("mud_os/semantic_match")
local class = require("mud_os/class")
local misc = require("mud_os/misc")
local Channel = require("mud_os/channel")

local SpaceObject = require("mud_lib/space")
local invoke_llm = require("mud_lib/invoke_llm")

local Item = require("mud_lib/item")
local Charactor = require("mud_lib/char")

---世界对象，管理游戏中的所有房间和全局状态
---@class world
---@field __name string 世界名称
---@field channel Channel 全局频道
---@field rooms table<string, Room> 房间对象索引
local world = {
  __name = "世界",
  channel = Channel.New(),
  rooms = {},
}

---房间类
---@class Room : SpaceObject
---@field id string 房间ID
---@field title string 房间标题
---@field desc string 房间描述
---@field exits table<string, string> 房间出口（方向->房间ID）
---@field channel Channel 房间频道
---@field avg_cmds table<string, CmdFunc> 临时命令表
---@field avg_cmds_desc table<string, string> 临时命令描述
---@field spown_list SpaceObject[] 房间内所有物体的实例
---@field New fun(property_table: table): Room
---@field world world 世界对象，管理游戏中的所有房间和全局状态
Room = {
  __name = "Room",
  id = "",
  title = "虚空",
  desc = "这里一片白茫茫",
  exits = {},         -- east="xxx", west="yyy", ...
  channel = world.channel,
  avg_cmds = {},      -- cmd_name=func(cmds)
  avg_cmds_desc = {}, -- 临时命令描述
  spown_list = {},    -- 存储房间内所有物体的实例
}

function Room:init(property_table)
  -- log.DEBUG("正在加载地图：" .. tostring(property_table.title))
  class.copy_property(property_table, self)
  SpaceObject.start(self) -- 把数据初始化完之后再执行事件监听器注册
  semantic_match.add_match_src(self.title)
  local ch = Channel.New()
  if ch then
    self.channel = ch
  else
    log.ERROR("创建房间通信频道失败")
    return false
  end

  self:spown()
  world.rooms[self.id] = self -- 存放房间到世界对象中
  return true
end

---返回世界对象
---@return world
function Room.get_world()
  return world
end

---生成房间内的所有物体实例
function Room:spown()
  if self.spown_list then
    for _, spown_target in ipairs(self.spown_list) do
      self:add_obj(spown_target)
    end
  end
end

---使用大模型搜索房间出口
---@param destination string 目标（方向或房间标题）
---@param user_id string 用户ID
---@return string? #目标出口的房间ID（如果找到，否则为 nil）
function Room:search_exit_llm(destination, user_id)
  if not IS_LLM_ENABLED then
    log.WARNING("LLM 功能未启用，无法进行模糊搜索")
    return nil
  end

  local exit_list = ""     -- 用于 LLM 的提示词
  local match_options = {} -- 用于 BGE 匹配房间 title

  -- 开始匹配出口方向的房间 title
  for direction, room_id in pairs(self.exits) do
    local the_room = world.rooms[room_id]
    if not the_room then
      goto continue
    end
    local room_title = the_room.title
    table.insert(match_options, room_title)
    exit_list = exit_list .. "[" .. direction .. "]->'" .. room_title .. "'\n"
    ::continue::
  end

  local semantic_result = semantic_match.best_match(destination, match_options)
  if semantic_result then
    log.DEBUG("语义匹配命中: " .. destination .. " -> " .. semantic_result)

    -- 由于只缓存了目标方向房间的 title，所以“方向”就不判断了，方向有时候需要中英文翻译
    for _, chk_room_id in pairs(self.exits) do
      local room = world.rooms[chk_room_id]
      if room and room.title == semantic_result then
        return chk_room_id
      end
    end
  end

  local prompt = [[
方位转换器，规则：
1.读取用户传入映射表：方位->地点，标识绑定同义方位词；
2.输入含方位及其中文翻译/地点及其近似名词、近似发音，匹配对应英文标识；
3.只输出{"results":["方位"]}，无匹配输出{"results":[]}
映射表：
]] .. exit_list
  local input = [[
输入：
]] .. destination .. "\n"
  local llm_ret = invoke_llm(prompt, input, user_id) --[[@as LLMInputResult]]
  if not llm_ret or #llm_ret.results == 0 then
    log.DEBUG("LLM 搜索未找到匹配结果")
    return nil
  end

  local result = {} ---@type string[]
  for _, dir in ipairs(llm_ret.results) do
    local room_id = self.exits[dir]
    if room_id then
      table.insert(result, room_id)
    end
  end

  if #result == 0 then
    return nil
  end
  return result[1]
end

---搜索房间出口
---@param destination string 目标（方向或房间标题）
---@return string? #目标出口的房间ID（如果找到，否则为 nil）
function Room:search_exit(destination)
  local room_id = self.exits[destination]
  if room_id then
    return room_id
  end

  -- 检查 destination 是否为通往某个房间的名字
  for _, chk_room_id in pairs(self.exits) do
    local room = Room.get_world().rooms[chk_room_id]
    if room and room.title == destination then
      room_id = room.id
      break
    end
  end
  if room_id then
    return room_id
  end

  return nil
end

---返回房间的文字信息，包含出口和物品、角色
---@return string
function Room:to_str()
  local output = [[
--%s--
%s
这里的出口：
%s
这里有：
%s]]

  local str_builder = {}
  for dir, exit in pairs(self.exits) do
    if world.rooms[exit] and world.rooms[exit].title then
      table.insert(str_builder, "  ➡️  " .. dir)
      table.insert(str_builder, " 通往 ")
      table.insert(str_builder, world.rooms[exit].title)
      table.insert(str_builder, "\n")
    end
  end
  local exits_str = table.concat(str_builder, "")

  str_builder = {}
  for _, content_obj in pairs(self.content) do
    local is_item = class.is_instance(content_obj, Item)
    local is_charactor = class.is_instance(content_obj, Charactor)
    local c = content_obj --[[@as table]]
    if is_item then
      table.insert(str_builder, "  📦 ")
    end
    if is_charactor then
      local icon = nil
      if c.hp <= 0 then
        icon = "  😵‍ "
      elseif c.user_id then
        icon = icon or "  😀 "
      else
        icon = icon or "  😎 "
      end
      table.insert(str_builder, icon)
    end
    table.insert(str_builder, c.display_name and c:display_name() or c.name)
    table.insert(str_builder, " [")
    table.insert(str_builder, c.id)
    table.insert(str_builder, "]")
    table.insert(str_builder, "\n")
  end
  local content_str = table.concat(str_builder, "")

  return string.format(output, self.title, self.desc, exits_str, content_str)
end

---加载地图文件
---@param map_file_name string 地图文件名（不含.lua扩展名）
function Room.load_map(map_file_name)
  local map_path = MUD_LIB_PATH .. "map/" .. map_file_name .. ".lua"
  local result = misc.save_do_file(map_path)
  return result
end

---加载所有地图文件
function Room.load_all_maps()
  local map_dir = MUD_LIB_PATH .. "map/"
  local handle = io.popen("find " .. map_dir .. " -name '*.lua'")
  if not handle then
    log.ERROR("打开地图目录失败")
    return
  end
  local result = handle:read("*a")
  handle:close()
  local map_files = {}
  string.gsub(result, '[^\n \t]+', function(w) table.insert(map_files, w) end)
  log.INFO("正在加载地图文件: ")
  for i, v in pairs(map_files) do
    local map_path = string.gsub(v, map_dir, "")
    map_path = string.gsub(map_path, "%.lua$", "")
    if map_path then
      io.write(i .. "." .. misc.get_last_dir_and_file(v).."...")
      local map_result = Room.load_map(map_path)
      io.write(map_result.."\n")
    end
  end
end

class.define_class(Room, SpaceObject)

return Room