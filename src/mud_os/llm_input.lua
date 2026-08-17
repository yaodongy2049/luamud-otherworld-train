---@module "mud_os/llm_input"
---@description 大模型输入模块

local socket = require("socket")
local cjson = require("cjson")
local log = require("mud_os/log")
local misc = require("mud_os/misc")
local network = require("mud_os/network")


---@class LLMInputResult
---@field results any[] #返回的结果列表

---递归过滤表中的 null 值和空字符串
---@param t table 输入表
---@return table #过滤后的表
local function filter(t)
    if type(t) == "table" then
        for k, v in pairs(t) do
            if v == cjson.null then
                t[k] = nil
            elseif type(v) == "string" and v then
                local r = misc.trim(v)
                if r == "" then
                    t[k] = nil
                else
                    t[k] = r
                end
            elseif type(v) == "table" then
                filter(v)
            end
        end
    end
    return t
end

---HTTP 客户端函数，用于与 LLM 服务通信
---@async
---@param url string LLM 服务的 URL
---@param req_body table 请求体
---@return table?, string? #经过json解码后的响应体以及错误信息
local function http_llm(url, req_body)
    -- 解析 URL
    local host, port, path = string.match(url, "http://([^:]+):(%d+)(.*)")
    if not host then
        return nil, "URL 解析失败"
    end

    -- 创建 TCP 连接
    local sock = socket.tcp()
    sock:settimeout(0) -- 设置为非阻塞

    -- 连接服务器
    log.DEBUG("Connecting " .. host .. ":" .. port)
    local success, err = sock:connect(host, tonumber(port))

    -- 非阻塞模式下，成功或超时都是正常的
    if not success and err ~= "timeout" then
        sock:close()
        return nil, "连接失败：" .. err
    end

    -- 等待连接完成
    local connected = false
    while not connected do
        -- 等待套接字可写（表示连接完成）
        local readable, writable, err = socket.select(nil, { sock }, 0)
        if err then
            sock:close()
            return nil, "选择失败：" .. err
        end

        if #writable > 0 then
            -- 再次调用 connect 检查连接状态
            local success, err = sock:connect(host, tonumber(port))
            if success or err == "already connected" then
                -- 连接成功
                connected = true
                log.DEBUG("Connected, err: " .. tostring(err))
                break
            else
                sock:close()
                return nil, "连接失败：" .. (err or "未知错误")
            end
        end

        coroutine.yield(true)
    end

    -- 发送 HTTP 请求
    local request = string.format(
        "POST %s HTTP/1.1\r\n"
        .. "Host: %s:%s\r\n"
        .. "Content-Type: application/json\r\n"
        .. "Content-Length: %d\r\n"
        .. "Connection: close\r\n"
        .. "\r\n"
        .. "%s",
        path, host, port, #req_body, req_body
    )

    local sent = 0
    while sent < #request do
        local readable, writable, err = socket.select(nil, { sock }, 0)
        if #writable > 0 then
            local bytes, err = sock:send(string.sub(request, sent + 1))
            if not bytes then
                sock:close()
                return nil, "发送失败：" .. err
            end
            sent = sent + bytes
            log.DEBUG("Send byets：" .. bytes .. "/" .. tostring(#request))
        elseif err then
            sock:close()
            return nil, "选择失败：" .. err
        end
        coroutine.yield(true)
    end

    -- 接收响应
    local response = ""
    local headers_received = false
    local content_length = 0
    local received = 0
    local http_headers = "" -- 保存HTTP头部信息

    while true do
        local readable, writable, err = socket.select({ sock }, nil, 0)
        if #readable > 0 then
            local data, err, partial = sock:receive(4096)

            -- 处理接收到的数据
            if data then
                response = response .. data
            elseif partial then
                response = response .. partial
            end

            -- 解析头部（如果还没有解析）
            if not headers_received then
                local headers, body = string.match(response, "(.-\r\n\r\n)(.*)")
                if headers then
                    headers_received = true
                    http_headers = headers -- 保存头部信息
                    response = body
                    -- 获取 Content-Length
                    local length_str = string.match(headers, "Content%-Length: (%d+)")
                    content_length = tonumber(length_str) or 0
                    log.DEBUG("Received headers: " .. headers)
                end
            end

            -- 检查是否接收完成
            if headers_received then
                received = #response
                if content_length and content_length > 0 and received >= content_length then
                    log.DEBUG("Received done, length: " .. tostring(content_length))
                    break
                end
            end

            -- 检查连接是否关闭
            if err == "closed" then
                -- 即使连接关闭，也要确保处理完所有数据
                if response ~= "" then
                    -- 如果还有数据，继续处理
                    if not headers_received then
                        local headers, body = string.match(response, "(.-\r\n\r\n)(.*)")
                        if headers then
                            headers_received = true
                            http_headers = headers -- 保存头部信息
                            response = body
                        end
                    end
                end
                log.DEBUG("Connection got closed")
                break
            end
        elseif err and err ~= "timeout" then
            sock:close()
            return nil, "选择失败：" .. err
        end
        coroutine.yield(true)
    end
    sock:close()

    -- 解析响应
    local status_code = 0
    if http_headers ~= "" then
        local sc = tonumber(string.match(http_headers, "HTTP/%d+%.%d+ (%d+)") or 0)
        if sc then
            status_code = sc
        end
    end
    if status_code ~= 200 then
        return nil, "请求失败，状态码：" .. tostring(status_code)
    end

    log.DEBUG("原始响应：$$" .. response .. "$$")

    -- 提取 JSON 部分
    local json_start = string.find(response, "{")
    if not json_start then
        return nil, "响应格式错误：未找到JSON开始标记{"
    end

    -- 找到最后一个}
    local json_end = string.find(response, "}", json_start, true)
    if not json_end then
        return nil, "响应格式错误：未找到JSON结束标记}"
    end

    -- 确保找到的是最后一个}
    local last_json_end = json_end
    while true do
        local next_end = string.find(response, "}", last_json_end + 1, true)
        if not next_end then
            break
        end
        last_json_end = next_end
    end

    local json_str = string.sub(response, json_start, last_json_end)
    local resp
    local success, err = pcall(function()
        resp = cjson.decode(json_str)
    end)
    if not success then
        return nil, "JSON 解析失败：" .. err
    end

    return resp, nil
end

---执行大模型调用的内部函数
---@param req_body table 已编码的请求体
---@param url string 请求URL
---@param get_response_content fun(resp: table): string 获取响应内容的函数
---@return LLMInputResult? #解析JSON结果
local function do_invoke_llm(req_body, url, get_response_content)
    local start_time = socket.gettime() * 1000
    log.DEBUG("正在发送请求：\n" .. req_body)

    local resp, err = http_llm(url, req_body)

    if not resp then
        local end_time = socket.gettime() * 1000
        local elapsed_ms = end_time - start_time
        log.ERROR("❌ 大模型请求失败：" .. url .. " err: " .. err .. "，耗时: " .. string.format("%.2f", elapsed_ms) .. " ms")
        return nil
    end

    local response_content = get_response_content(resp)
    log.DEBUG("大模型返回：" .. response_content)
    local llm_result = nil
    local success, err = pcall(function()
        local clean_json = string.match(response_content, "%b{}")
        llm_result = cjson.decode(clean_json)
        if llm_result and not llm_result.results then
            llm_result = nil
        end
    end)
    if not success or not llm_result then
        local end_time = socket.gettime() * 1000
        local elapsed_ms = end_time - start_time
        log.ERROR("❌ 响应解析失败：" .. tostring(err) .. "，耗时: " .. string.format("%.2f", elapsed_ms) .. " ms")
        log.DEBUG("错误字符串：➡️  " .. response_content .. "  ⬅️")
        return nil
    end

    llm_result = filter(llm_result)

    local end_time = socket.gettime() * 1000
    local elapsed_ms = end_time - start_time
    log.INFO("LLM 调用完成，耗时: " .. string.format("%.2f", elapsed_ms) .. " ms")

    return llm_result
end

---调用大模型解析文本（使用 /api/generate 接口）
---@param prompt string 提示词
---@param input string 用户输入
---@return LLMInputResult? #解析JSON结果
local function invoke_llm_generate(prompt, input)
    local req_body = cjson.encode({
        model = LLM_MODEL,
        stream = false,
        prompt = prompt .. "\n当前用户输入：" .. input,
        keep_alive = -1,
        -- num_ctx = 2048,
        -- num_predict = 2048,
        nohistory = true,
        temperature = 0,
        format = "json",
        -- stop = {
        --     "<|im_start|>",
        --     "<|im_end|>"
        -- }
    })

    local url = OLLAMA_HOST .. "/api/generate"
    local rsp_fun = function(resp) return resp.response or "" end
    return do_invoke_llm(req_body, url, rsp_fun)
end

---调用大模型解析文本（使用 /api/chat 接口）
---@param prompt string 提示词，放入 role: system
---@param input string 用户输入，放入 role: user
---@return LLMInputResult? #解析JSON结果
local function invoke_llm_chat(prompt, input)
    local req_body = cjson.encode({
        model = LLM_MODEL,
        stream = false,
        messages = {
            { role = "system", content = prompt },
            { role = "user",   content = input }
        },
        keep_alive = -1,
        temperature = 0,
        format = "json"
    })

    local url = OLLAMA_HOST .. "/api/chat"
    local rsp_fun = function(resp) return resp.message and resp.message.content or "" end
    return do_invoke_llm(req_body, url, rsp_fun)
end

---请求 agent 返回
---@param agent string Agent 名字
---@param input string 用户输入
---@return LLMInputResult?
local function invoke_llm_agent(agent, input)
    local req_body = cjson.encode({
        model = agent,
        stream = false,
        messages = {
            { role = "user",   content = input }
        },
        keep_alive = -1,
        temperature = 0,
        format = "json"
    })

    local url = OLLAMA_HOST .. "/api/chat"
    local rsp_fun = function(resp) return resp.message and resp.message.content or "" end
    return do_invoke_llm(req_body, url, rsp_fun)
end


---大模型解析文本（异步非阻塞）
---@async
---@param prompt string 提示词
---@param input string 用户输入
---@param callback fun(table?, string?) #解析回调函数，参数为解析结果或错误信息
local function parse_input_async(prompt, input, callback)
    -- 创建协程
    local co = coroutine.create(function()
        local result_table = invoke_llm_chat(prompt, input)
        return callback(result_table)
    end)

    -- 将协程添加到TcpServer的协程池
    network.TcpServer:add_coroutine(co)
end

-- **************
-- 测试业务函数
-- **************
local function open_light(args)
    IS_LLM_ENABLED = true
    log.DEBUG("执行函数: 打开灯(" .. args .. ")")
end

local function close_light(args)
    IS_LLM_ENABLED = true
    log.DEBUG("执行函数: 关闭灯(" .. args .. ")")
end

local function adjust_brightness(arg1, arg2)
    IS_LLM_ENABLED = true
    log.DEBUG("执行函数: 调节亮度(" .. arg1 .. ", " .. arg2 .. ")")
end

-- 函数注册表
local func_map = {
    open = open_light,
    close = close_light,
    adjust = adjust_brightness,
}

-- **************
-- 执行解析出来的函数
-- **************
local function call_functions(call_list)
    for _, call in ipairs(call_list) do
        local func = func_map[call.func]
        if func then
            func(table.unpack(call.args))
        else
            log.ERROR("❌ 未知函数：" .. call.func)
        end
    end
end

-- **************
-- 保持向后兼容的同步版本
-- **************
local function parse_input(input)
    local result
    local done = false
    local base_prompt = [[
你是一个指令解析器。
用户输入一句话，你必须把它转换成我定义的函数调用。
只允许调用以下函数：
1. open(参数：{设备名})
2. close(参数：{设备名})
3. adjust(参数：{设备名, 亮度值})

输出要求：
- 只返回纯 JSON，不要解释、不要多余文字
- 格式：{"results":[{"func":"函数名","args":["值1"]}]}

例子：
输入：把客厅灯亮度调到50
输出：{"results":[{"func":"adjust","args":["客厅灯","50"]}]}
]]
    parse_input_async(base_prompt, input, function(call_list)
        result = call_list
        done = true
    end)

    -- 等待异步操作完成
    local spinner = { '-', '\\', '|', '/' }
    local spin_idx = 1
    while not done do
        io.write(spinner[spin_idx] .. ' AI 计算中...'.."\r")
        io.flush()
        spin_idx = spin_idx % #spinner + 1

        -- 待TcpServer处理协程
        network.TcpServer:process_coroutines()
        socket.sleep(0.1)
    end
    return result
end

-- **************
-- 启动测试，成功后 llm_enabled 为 true
-- **************
local function test()
    if not IS_LLM_ENABLED then
        return
    end
    log.INFO("开始测试大模型...")
    IS_LLM_ENABLED = false
    local user_text = "把客厅灯打开，然后把卧室灯亮度调到70"
    log.DEBUG("测试大模型输入：" .. user_text)
    local calls = parse_input(user_text)
    if calls then
        log.DEBUG("📥 大模型返回调用：" .. cjson.encode(calls))
        call_functions(calls.results)
    end
    if IS_LLM_ENABLED then
        log.INFO("✅ 测试大模型成功")
    else
        log.WARNING("❌ 测试大模型失败")
    end
end

test()

return {
    invoke_llm_chat = invoke_llm_chat,
    invoke_llm_generate = invoke_llm_agent,
    invoke_llm_agent = invoke_llm_agent,
}