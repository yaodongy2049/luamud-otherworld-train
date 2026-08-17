---@module "mud_lib/cmd/perform"

local log = require("mud_os/log")
local class = require("mud_os/class")
local EventSystem = require("mud_os/event_system")
local cmd_sys = require("mud_lib/cmds")

-- cmd_sys.command_desc_list.perform = [[ perform: 对YY进行/使用技能XX;尝试YYXX，args=[技能名XX, 可选目标YY] ]]

---perform 命令：使用技能
cmd_sys.command_list.perform = function(this_player, cmds)
    -- 解析参数
    local skill_name = cmds[2]
    local target_name = cmds[3]
    
    -- 检查技能参数是否完整
    if not skill_name or skill_name == "null" or skill_name == "" then
        this_player:reply("你要使用什么技能？")
        return
    end
    
    -- 检查玩家是否有此技能
    local this_investigator = this_player --[[@as Investigator]]
    if not this_investigator.skill or type(this_investigator.skill) ~= "table" then
        this_player:reply("你没有任何技能。")
        return
    end
    
    -- 检查技能是否存在
    local skill_level = this_investigator.skill[skill_name]
    if not skill_level then
        this_player:reply(string.format("你不会「%s」这项技能。", skill_name))
        return
    end
    
    -- 确定目标
    local target
    local this_place = this_player.environment --[[@as Room]]
    
    if not target_name or target_name == "null" or target_name == "" then
        -- 没有指定目标，目标为当前房间
        target = this_place
    else
        -- 在当前环境中查找目标
        if class.is_empty(this_place) then
            this_player:reply('你周围什么都没有')
            return
        end
        local targets = this_place:resolve_content(target_name) --[[@as Npc[] ]]
        
        if #targets == 0 then
            this_player:reply(string.format("这里没有%s。", target_name))
            return
        end
        
        target = targets[1]
    end
    
    ---@alias PerformCallback fun(event_name:string, target:SpaceObject, this_investigator:Investigator, skill_name:string, skill_level:number)
    -- 触发 perform 事件
    local has_handled = EventSystem:trigger("perform", target, this_investigator, skill_name, skill_level)
    if not has_handled then
        this_player:reply("你尝试了" .. skill_name .. "技能，但是没有反应。")
    end
end