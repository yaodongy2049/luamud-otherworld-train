---@module "mud_lib/cmd/ask"

local class                   = require("mud_os/class")
local log                     = require("mud_os/log")
local EventSystem             = require("mud_os/event_system")
local cmd_sys                 = require("mud_lib/cmds")
local misc                    = require("mud_os/misc")
local invoke_llm              = require("mud_lib/invoke_llm")
local semantic_match          = require("mud_os/semantic_match")

cmd_sys.command_desc_list.say = [[say：对A说B/问A关于B的事，args=[内容(b),目标(a)]，如：对张三说登记→{"results":[{"func":"say","args":["登记","张三"]}]}。]]


---使用LLM进行话题模糊匹配
---@param target_char table NPC对象，包含topics属性
---@param msg string 玩家输入的消息
---@param user_id string? 用户ID
---@return string, string? #匹配到的话题名称，如果未匹配到则返回原消息，以及话题内容
local function select_topic(target_char, msg, user_id)
    if not target_char.topics then
        return msg
    end

    local topics = target_char.topics
    local topic_list = {}
    for topic_name, _ in pairs(topics) do
        table.insert(topic_list, topic_name)
    end

    if #topic_list == 0 then
        return msg
    end

    local best_topic = semantic_match.best_match(msg, topic_list)
    if best_topic then
        return best_topic, topics[best_topic]
    end

--     local topics_str = table.concat(topic_list, "、")

--     local prompt = string.format([[
-- 你是一个话题匹配助手。
-- 首先判断玩家输入是否有退出/结束/离开对话的意图（如"退出"、"结束"、"离开"、"告辞"、"走了"、"quit"等）。
-- 如果有退出意图，输出：{"results":["EXIT"]}
-- 如果没有退出意图，判断玩家输入语义是否和列表中任意话题有关联：
-- 1. 如果有关联返回：{"results":["话题名称"]}；
-- 2. 如果完全没有关联返回：输出{"results":[]}；

-- ]], topics_str)

--     local input = string.format("以下是NPC可回答的话题列表：[%s]\n 用户的输入为：%s", topics_str, msg)
--     local llm_result = invoke_llm(prompt, input, user_id) --[[@as LLMInputResult]]

--     if llm_result and #llm_result.results > 0 then
--         local matched_topic = llm_result.results[1] --[[@as string]]
--         if matched_topic == "EXIT"  then
--             return matched_topic, nil
--         end
--         if matched_topic and matched_topic ~= "" and topics[matched_topic] then
--             return matched_topic, topics[matched_topic]
--         end
--     end

    return msg
end

---使用LLM生成NPC的自然回复
---@param target table NPC对象，包含id、name、desc、topics属性
---@param player_msg string 玩家的问题/消息
---@param default_reply? string 默认回复内容
---@param user_id string? 用户ID
---@param is_in_dialog_mode boolean 是否处于对话模式
---@return string? #生成的回复内容，返回 nil 表示玩家有退出对话意图
local function generate_npc_reply(target, player_msg, default_reply, user_id, is_in_dialog_mode)
    if not target.name or not target.topics then
        return default_reply
    end

    if not IS_LLM_ENABLED then
        return default_reply
    end
    local npc = target --[[@as Npc]]

    -- 构建NPC人设信息
    local npc_info = {
        id = npc.id or "",
        name = npc.name or "",
        desc = npc.desc or ""
    }

    -- 构建话题列表字符串
    local topics_str = ""
    for topic, content in pairs(npc.topics) do
        topics_str = topics_str .. "\"" .. topic .. "\": \"" .. content .. "\","
    end
    topics_str = string.sub(topics_str, 1, -2) -- 移除末尾逗号

    -- 使用LLM同时判断退出意图和生成回复
    local llm_reply = nil
    local prompt = string.format([[
你是一个角色扮演游戏中的NPC，名字叫「%s」。
你的描述：%s
你的话题：{%s}

%s
1. 身份问题：当玩家问"你是谁"、"介绍自己"等问题时，请用符合角色设定的方式介绍自己，并从你能回答的话题中选择一个话题来引导玩家继续聊天。
2. 话题问题：当玩家询问与你的话题相关时，你要根据话题内容进行回复。当玩家询问的内容与你的话题无关时，你应该表示不知道或转移话题。

请用中文回复，保持简洁自然。
输出格式：{"results":["回复内容"]}
]], npc_info.name, npc_info.desc, topics_str, 
    is_in_dialog_mode 
        and "首先判断玩家输入是否有退出/结束/离开对话的意图（如\"退出\"、\"结束\"、\"离开\"、\"告辞\"、\"走了\"、\"quit\"等）。\n如果有退出意图，输出：{\"results\":[\"EXIT\"]}\n如果没有退出意图，按照以下规则回复："
        or "")

    llm_reply = invoke_llm(prompt, player_msg, user_id) --[[@as LLMInputResult]]

    -- 如果LLM返回了有效回复
    if llm_reply and #llm_reply.results > 0 then
        local result = llm_reply.results[1] --[[@as string]]
        if is_in_dialog_mode and result == "EXIT" then
            return nil
        end
        return result ~= "" and result or default_reply
    end

    return default_reply
end

---say 命令：对目标说话
--- 在当前房间说话，此命令会触发事件：
--- - "say"：在说话前触发，事件函数如果返回字符串，会替换用户说的话；如果返回 false，会阻止说话
--- - "ask_about"：在说话后，如果有对话的目标，会触发 ask_about 事件
---@param this_player Investigator 玩家对象
---@param cmds string[] 命令参数列表
---@return boolean #是否成功处理此命令
cmd_sys.command_list.say = function(this_player, cmds)
    if #cmds == 1 then
        this_player:reply("你在喃喃自语，没人能听见。")
        cmd_sys.exit_dialog_mode(this_player)
        return true
    end

    -- 解析参数
    local msg = cmds[2]
    if not msg or misc.trim(msg) == "" then
        this_player:reply("你在喃喃自语，没人能听见。")
        cmd_sys.exit_dialog_mode(this_player)
        return true
    end

    -- 检查是否有当前房间
    local this_place = this_player.environment --[[@as Room]]
    if class.is_empty(this_place) then
        this_player:reply('你处于一片虚空之中')
        return true
    end

    -- 获取当前时间（秒）
    local now = os.time()

    -- 回显动作
    local target = cmds[3]
    local target_char = nil

    -- 确保临时状态结构体存在
    if not this_player.temp_status then
        this_player.temp_status = {}
    end

    if target then
        -- 用户指定了目标，解析并验证
        local targets = this_place:resolve_content(target)
        if #targets == 0 then
            this_player:reply(string.format("这里没有%s。", target))
            return true
        end
        target_char = targets[1] --[[@as table]]

        -- 检查是否对自己说话
        if target_char == this_player then
            this_player:reply("你自言自语，不知道在说什么")
            return true
        end

        -- 保存目标ID和时间到临时状态
        this_player.temp_status.last_say_target = target_char.id
        this_player.temp_status.last_say_time = now
    else
        -- 用户没有指定目标，检查是否有延续目标
        if this_player.temp_status.last_say_target and this_player.temp_status.last_say_time then
            -- 检查是否超过5分钟（300秒）
            if now - this_player.temp_status.last_say_time <= 300 then
                -- 使用ID检查目标是否在当前房间（效率更高）
                local targets = this_place:resolve_content(this_player.temp_status.last_say_target)
                if #targets > 0 then
                    target_char = targets[1] --[[@as table]]
                else
                    -- 目标不在当前房间，清除延续目标
                    cmd_sys.exit_dialog_mode(this_player)
                end
            else
                -- 超过5分钟，清除延续目标
                cmd_sys.exit_dialog_mode(this_player)
            end
        end
    end
    if target_char and target_char.name then
        this_player:reply(string.format("你对%s说道：\"%s\"", target_char.name, msg))
        -- 检查目标是否为玩家（通过 user_id 判断）
        if target_char.user_id then
            -- 目标是玩家，发送私聊消息
            local player = target_char --[[@as Player]]
            player:reply(string.format("%s对你说道：\"%s\"", this_player.name, msg))
            return true
        end
    else
        this_player:reply(string.format("你说道：\"%s\"", msg))
    end


    -- 触发 say 事件，目标为当前房间
    -- log.DEBUG("触发 say 事件，目标为当前房间")
    local handled, result_list = EventSystem:trigger("say", this_place, this_player, msg)
    local is_aloud = true
    if handled then
        for _, v in ipairs(result_list) do
            if type(v) == "string" then
                if v ~= "" then
                    msg = v
                end
            end
            if type(v) == "boolean" and not v then
                this_player:reply("你的声音被吞没了。")
                is_aloud = false
            end
        end
    end
    if is_aloud then
        this_player:say(msg)
    end

    -- log.DEBUG("触发 ask_about 事件", target_char)
    -- 触发 ask_about 事件
    if not target_char then
        return true
    end

    -- 查找话题内容
    local topic_content = nil
    if target_char.topics then
        topic_content = target_char.topics[msg]
    end
    -- log.DEBUG("select_topic: " .. msg )

    if not topic_content and IS_LLM_ENABLED then
        msg, topic_content = select_topic(target_char, msg, this_player.user_id)
        log.DEBUG("select_topic: " .. msg .. " " .. tostring(topic_content))
        if msg == "EXIT" and topic_content == nil then
            cmd_sys.exit_dialog_mode(this_player)
            return true
        end
    end

    -- log.DEBUG("ask_about 事件参数: " .. msg .. " " , topic_content)

    local reply_msg = ""
    local handled, result_list = EventSystem:trigger("ask_about", target_char, this_player, msg, topic_content)
    -- log.DEBUG("ask_about 事件触发结果: " .. tostring(handled))
    if handled then
        for _, v in ipairs(result_list) do
            -- 事件函数返回字符串时，合并到 reply_msg 中，返回给玩家显示
            if type(v) == "string" then
                if v ~= "" then
                    reply_msg = reply_msg .. "\n" .. v
                end
            end
            -- 事件函数返回 false 时，阻止 ask_about 事件继续执行
            if type(v) == "boolean" and not v then
                return true
            end
        end
        -- 事件函数有内容返回，就不去执行后面的固定内容了
        if reply_msg ~= "" then
            this_player:reply(reply_msg)
            return true
        end
    end

    -- 检查目标是否有 topics 属性（NPC）
    if not target_char.topics then
        this_player:reply(string.format("%s 没有什么可聊的。", target_char.name))
        return true
    end

    -- 判断是否处于对话模式（有延续目标）
    local is_in_dialog_mode = this_player.temp_status and this_player.temp_status.last_say_target ~= nil

    -- 使用LLM生成NPC回复（同时检测退出意图）
    local reply_content = generate_npc_reply(target_char, msg, topic_content, this_player.user_id, is_in_dialog_mode)

    if is_in_dialog_mode and reply_content == nil then
        cmd_sys.exit_dialog_mode(this_player)
        return true
    end

    if reply_content == "" then
        this_player:reply(string.format("%s 不知道关于「%s」的事情。", target_char.name, msg))
        return true
    end


    -- 用 this_player:reply() 返回话题内容给玩家
    this_player:reply(string.format("%s对你说道：%s", target_char.name, reply_content))
    return true
end