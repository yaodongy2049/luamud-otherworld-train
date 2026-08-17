---@module 'mud_lib/invoke_llm'

local llm = require("mud_os/llm_input")
local WaitingAnimation = require("mud_os/waiting_animation")
local AGENTS = {
    cmd_agent = "luamud-cmd-agent:latest",
}
---请求 LLM 的封装函数
---@param system string 可以是提示词或者 agent 名（cmd_agent）
---@param input string 用户输入
---@param user_id string? 用户 ID
---@return LLMInputResult? #大模型返回的结果列表
local function invoke_llm(system, input, user_id)
    if not IS_LLM_ENABLED then
        return nil
    end

    local stop_animation = nil
    if user_id then
        stop_animation = WaitingAnimation.start(user_id)
    end

    local result
    local agent = AGENTS[system]
    if agent then
        result = llm.invoke_llm_agent(agent, input)
    else
        result = llm.invoke_llm_chat(system, input)
    end

    if stop_animation then
        stop_animation()
    end

    return result
end

return invoke_llm