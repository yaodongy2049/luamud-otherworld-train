---@module "mud_lib/space"

local log = require("mud_os/log")
local class = require("mud_os/class")
local EventSystem = require("mud_os/event_system")
local invoke_llm = require("mud_lib/invoke_llm")
local semantic_match = require("mud_os/semantic_match")

---代表一个物理空间物体
---@class SpaceObject
---@field environment SpaceObject 所处环境
---@field content SpaceObject[] 内容物体数组
---@field listeners table<string, EventCallback> 事件监听器表
---@field super table? #父类对象
SpaceObject = {
  __name = "SpaceObject",
  environment = {},
  content = {},
  listeners = {},
}

---启动空间物体，注册 self.listeners 中的事件监听器
function SpaceObject:start()
  for event_name, callback in pairs(self.listeners) do
    EventSystem:register_listener(event_name, callback, self)
  end
  -- 注册语义匹配
  -- local my_table = self --[[@as table]]
  -- if my_table.name then
  --   semantic_match.add_match_src(tostring(my_table.name))
  -- end
  -- if my_table.id then
  --   semantic_match.add_match_src(tostring(my_table.id))
  -- end
  -- if my_table.title then
  --   semantic_match.add_match_src(tostring(my_table.title))
  -- end
end

---查找本身包含的内容物，返回找到的对象数组
---@param key string? 内容物的属性名,如果是 nil 则对比 value 整个对象是否存在与内容中（引用相等）
---@param value any 要查找的属性值或者内容物本身
---@param fun fun(pos:number, con_obj:SpaceObject)? 找到后的处理函数 (可选)
---@return SpaceObject[] #找到的对象数组
function SpaceObject:search(key, value, fun)
  local result = {}
  for pos, con_obj in ipairs(self.content) do
    local compare_obj = con_obj
    if key then
      compare_obj = con_obj[key]
    end
    if compare_obj == value then
      if fun then
        fun(pos, con_obj)
      end
      table.insert(result, #result + 1, con_obj)
    end
  end
  return result
end

---使用语义匹配进行搜索
---@param name string 要搜索的物品名称
---@param options string[] 候选名称列表
---@param name_to_obj table<string, SpaceObject> 名称到对象的映射表
---@return SpaceObject[] #找到的对象数组
local function search_semantic(name, options, name_to_obj)
  -- log.DEBUG("开始语义匹配搜索: " .. name)
  local best = semantic_match.best_match(name, options)
  if not best then
    return {}
  end

  local matched_obj = name_to_obj[best] --[[@as table]]
  if matched_obj then
    log.DEBUG("语义匹配命中：", matched_obj.name, matched_obj.id)
    return {matched_obj}
  end
  return {}
end

---使用 LLM 进行模糊搜索
---@async
---@param name string 要搜索的物品名称（支持近似匹配）
---@param user_id string? 用户ID
---@return SpaceObject[] #找到的对象数组
function SpaceObject:search_llm(name, user_id)
  if not IS_LLM_ENABLED then
    return {}
  end

  if #self.content == 0 then
    return {}
  end

  local options = {}
  local name_to_obj = {}
  local obj_list = ""

  for i, item in ipairs(self.content) do
    local item_name = item.name --[[@as string?]]
    local item_id = item.id --[[@as string?]]

    if item_name and type(item_name) == "string" then
      table.insert(options, item_name)
      name_to_obj[item_name] = item
    end
    if item_id and type(item_id) == "string" then
      table.insert(options, item_id)
      name_to_obj[item_id] = item
    end

    obj_list = obj_list .. i .. " " .. (item_name or "未知物品") .. " " .. (item_id or "") .. "\n"
  end

  local result = search_semantic(name, options, name_to_obj)
  if #result > 0 then
    return result
  end

  local prompt = [[
# 物品匹配任务
硬性强制规则，严格按顺序执行，不可跳过前置规则：
1.【最高优先级】包含匹配：用户输入字符串 出现在 条目中文/英文标识任意一处，直接匹配该条目；
2. 完全匹配：输入与条目中文名/英文名完全相等；
3. 语义匹配：同义、别名；
4. 拼音匹配：拼音/简写对应。
物品列表: 
]] .. obj_list .. [[
仅输出{"results":[匹配序号]}，无匹配输出{"results":[]}
]]

local input= [[
用户输入：]] .. name .. [[
]]
  local llm_ret = invoke_llm(prompt, input, user_id) --[[@as LLMInputResult]]
  if llm_ret and #llm_ret.results > 0 then
    for _, idx in ipairs(llm_ret.results) do
      local pos = tonumber(idx)
      if pos and self.content[pos] then
        table.insert(result, self.content[pos])
      end
    end
  end

  return result
end

---使用 name 或者 id 进行内容物搜索。如果 LLM 可用则使用 LLM。
---@async
---@param name string 要搜索的物品名称或id(支持近似模糊匹配)
---@param user_id string? 用户ID
---@return SpaceObject[] #找到的对象数组
function SpaceObject:resolve_content(name, user_id)
  local result = self:search("id", name)
  if #result > 0 then
    return result
  end
  result = self:search("name", name)
  if #result > 0 then
    return result
  end

  result = self:search_llm(name, user_id)
  return result
end

---离开当前环境
function SpaceObject:leave()
  local old_env = self.environment
  local fun = function(my_idx, _)
    table.remove(old_env.content, my_idx)
  end
  if not class.is_empty(old_env) and class.is_instance(old_env, SpaceObject) then
    old_env:search(nil, self, fun)
  end
end

---放入指定环境
---@param env SpaceObject 目标环境
function SpaceObject:put(env)
  --不能放到自己身上
  if self == env then return end
  self:leave()
  self.environment = env
  table.insert(env.content, #(env.content) + 1, self)
end

---克隆并添加一个物品到本对象空间中
---@param obj SpaceObject 要克隆的物品对象
function SpaceObject:add_obj(obj)
  local cloned = class.clone(obj)
  cloned:put(self)
  cloned:start()
end

---判断是否存有此物品
---@param key string 物品的属性名
---@param value any 物品的属性值
---@return boolean #是否存在此物品对象
function SpaceObject:has_obj(key, value)
  local objs = self:search(key, value)
  return #objs > 0
end

---销毁当前物体
function SpaceObject:dispose()
  --取消注册所有事件监听器
  for event_name, callback in pairs(self.listeners) do
    EventSystem:remove_listener(event_name, callback, self)
  end
  self.listeners = {}

  --删除自己的内容物
  for _, con in ipairs(self.content) do
    con:dispose()
  end

  --把自己从空间系统中删除
  self:leave()
  self.content = {}
  self.environment = nil
end

---返回当前物体的描述
function SpaceObject:to_str()
  return "白茫茫一片"
end

class.define_class(SpaceObject)
return SpaceObject