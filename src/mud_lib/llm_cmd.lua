---@module 'mud_lib/llm_cmd'

local log        = require("mud_os/log")
local network    = require("mud_os/network")
local invoke_llm = require("mud_lib/invoke_llm")
local cmd_sys    = require("mud_lib/cmds")
local login      = require("mud_lib/login")
local llm_safety = require("mud_lib/llm_safety")

---获取房间的 avg_cmds 描述
---@param user_id string 用户ID
---@return table<string, string>? #房间的 avg_cmds 描述
local function get_avg_desc(user_id)
    local player = login.session_pool[user_id]
    if not player then
        return nil
    end
    return player.dynamic_cmds_desc
end

---获取玩家已有的技能列表
---@param user_id string 用户ID
---@return table<string, number>? #技能名到等级的映射表
local function get_player_skills(user_id)
    local player = login.session_pool[user_id] --[[@as Investigator]]
    if not player then
        return nil
    end
    -- 检查玩家是否有技能属性
    if not player.skill or type(player.skill) ~= "table" then
        return nil
    end
    return player.skill
end

---用技能名在命令字符串中进行正则模糊匹配，过滤不命中的技能
---@param cmd_str string 命令字符串
---@param skills table<string, number>? 技能名到等级的映射表
---@return table<string, number>? #过滤后的技能表
local function find_skill_from_cmds(cmd_str, skills)
    if not skills or not cmd_str then
        return skills
    end
    local matched_skills = {}
    for name, level in pairs(skills) do
        if string.find(cmd_str, name) then
            matched_skills[name] = level
        end
    end
    if next(matched_skills) then
        return matched_skills
    end
    return skills
end

---构造临时动作提示词
local function generate_dy_prompt(command_desc_tab)
    local ret = ""
    if not command_desc_tab then
        return ret
    end
    for _, desc in pairs(command_desc_tab) do
        ret = ret .. " - " .. desc .. "\n"
    end
    return ret
end

-- 生成命令列表的函数
local function generate_command_list(command_desc_tab)
    local command_list = ""
    for _, desc in pairs(cmd_sys.command_desc_list) do
        command_list = command_list .. " - " .. desc .. "\n"
    end

    command_list = command_list .. generate_dy_prompt(command_desc_tab)
    return command_list
end


---构造技能提示词
local function generate_skill_prompt(skills)
    -- 构建技能提示词
    local skill_prompt = ""
    if skills then
        for name, _ in pairs(skills) do
            skill_prompt = skill_prompt .. name .. ","
        end

        -- 添加技能使用提示
        if skill_prompt ~= "" then
            skill_prompt = "\n可用技能：" .. skill_prompt
        end
    end
    return skill_prompt
end


---生成完整的大模型提示词
---@param command_desc_tab? table<string, string> 命令描述表
---@param skills? table<string, number> 玩家技能表
---@return string #大模型提示词
local function generate_cmds_prompt(command_desc_tab, skills)
    local command_list = generate_command_list(command_desc_tab)

    -- 构建技能提示词
    local skill_prompt = generate_skill_prompt(skills)
    return [[
你是自然语言转游戏指令Agent，仅输出严格标准JSON，无多余文字，格式固定：
{"results":[{"func":"动词","args":[参数1,...]}]}
1.动作规则（参数顺序不可颠倒）:
]] .. command_list .. [[
2.技能调用统一用perform，凡含'尝试XX技能、对YY进行XX技能、对YY使用XX技能'均解析为perform，args=[技能名(XX),可选目标(YY)]，
]] .. skill_prompt .. [[

兜底：无法匹配输出{"results":[{"func":"unknown","args":[]}]}
]]
end

local function generate_cmds_system_prompt()
    return [[
你是自然语言转游戏指令Agent，仅输出严格标准JSON，无多余文字，格式固定：
{"results":[{"func":"动词","args":[参数1,...]}]}
可用动作（参数顺序不可颠倒）:
]] .. generate_command_list() .. [[
- perform：凡含'尝试XX技能、对YY进行XX技能、对YY使用XX技能'均解析为perform，args=[技能名(XX),可选目标(YY)]。
兜底：无法匹配输出{"results":[{"func":"unknown","args":[]}]}
]]
end

---大模型解析回调函数
---@param results LLMInputResult? 大模型返回的结果列表
---@param exec_cmd fun(user_id: string, cmds: string[]): boolean 命令执行函数
---@param user_id string 回调上下文，用户ID
---@return boolean #是否成功解析
local process_parse_result = function(results, user_id, exec_cmd)
    local safe_result = llm_safety.validate_command_result(results)
    if not safe_result then
        network.TcpServer:send_to(user_id, "你手足无措，茫然若失。")
        local this_player = login.session_pool[user_id]
        if this_player then
            this_player:send_prompt()
        end
        return false
    end

    local call = safe_result.results[1]
    local cmd_arr = { call.func }
    for i = 1, #call.args do
        cmd_arr[#cmd_arr + 1] = call.args[i]
    end

    log.DEBUG("执行已验证的大模型解析：" .. table.concat(cmd_arr, " "))
    local has_cmd = exec_cmd(user_id, cmd_arr)
    if not has_cmd then
        network.TcpServer:send_to(user_id, "你稍显迟疑，感觉无法作出这个动作。")
        local this_player = login.session_pool[user_id]
        if this_player then
            this_player:send_prompt()
        end
        return false
    end
    return true
end


---使用大模型解析用户输入的命令
---@param cmds string[] 命令参数表
---@param user_id string 用户ID
---@return boolean #是否成功处理此命令
local function try_llm_cmd(cmds, user_id)
    if not IS_LLM_ENABLED then
        return false
    end
    local active_player = login.session_pool[user_id]
    if active_player and active_player.temp_status and active_player.temp_status.dev_mode then
        -- 开发者控制台属于高权限路径，禁止让模型参与解释或生成命令。
        return false
    end
    local cmd_str = table.concat(cmds, " ")

    -- 获取玩家技能列表
    local skills = get_player_skills(user_id)
    skills = find_skill_from_cmds(cmd_str, skills)

    -- 生成大模型提示词
    local avg_desc = get_avg_desc(user_id)
    -- local cmd_prompt = generate_cmds_prompt(avg_desc, skills)
    local cmd_prompt = generate_cmds_system_prompt()
    cmd_str = "额外可用动作：\n" .. generate_dy_prompt(avg_desc)
        .. generate_skill_prompt(skills)
        .. "\n用户输入：" .. cmd_str

    -- local call_list = invoke_llm("cmd_agent", cmd_str, user_id)
    local call_list = invoke_llm(cmd_prompt, cmd_str, user_id)

    process_parse_result(call_list, user_id, cmd_sys.normal_handler)
    return true
end

-- 尝试调用大模型
local function llm_handler(user_id, cmds)
    local this_player = login.session_pool[user_id]
    if not this_player then -- 没有登录的命令全部不执行
        return false
    end

    -- 创建协程
    local co = coroutine.create(function()
        -- 先尝试正常的指令运行
        local rs = cmd_sys.normal_handler(user_id, cmds)
        if rs then
            return rs
        end

        -- 进入大模型解释
        return try_llm_cmd(cmds, user_id)
    end)

    -- 将协程添加到TcpServer的协程池
    network.TcpServer:add_coroutine(co)
    return coroutine.resume(co)
end

---根据技能判定结果生成动作描述
---@param roll number 骰子结果
---@param threshold number 判定阈值（成功值越小越成功）
---@param context string 技能动作的基本描述，包括动作、环境、对象
---@param user_id string? 用户ID，用于显示等待动画
---@return string? 生成的动作效果描述，不超过30字
local function describe_skill_result(roll, threshold, context, user_id)
    local diff = threshold - roll
    local level_desc

    if diff >= 20 then
        level_desc = "大成功"
    elseif diff >= 10 then
        level_desc = "普通成功"
    elseif diff >= 0 then
        level_desc = "勉强成功"
    elseif diff >= -10 then
        level_desc = "勉强失败"
    elseif diff >= -20 then
        level_desc = "一般失败"
    else
        level_desc = "大失败"
    end

    local prompt = string.format(
        [[TRPG叙事生成，规则：
1.根据玩家动作结果进行描述：'失败'表示行动完全失效，无法达成目标；'成功'表示行动成功，行动奏效
2.主语你，≤30字，贴合诡异氛围
3.只输出{"results":["短句"]}
输入含场景、行动结果、骰子结果，按胜负生成文案
禁令：大失败不许写行动成功，成功不许写行动落空
]])

    local result = invoke_llm(prompt,
        string.format("场景为: %s\n玩家当前动作结果为%s（骰子点数%d，阈值%d）",
            context, level_desc, roll, threshold),
        user_id)
    if result and #result.results > 0 then
        return result.results[1]
    end
    return nil
end

return {
    llm_handler = llm_handler,
    describe_skill_result = describe_skill_result,
}
