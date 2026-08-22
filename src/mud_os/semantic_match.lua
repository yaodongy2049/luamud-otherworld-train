---@module "mud_os/senmantic_match"
---@description 语义匹配模块

local log = require("mud_os/log")
local http = require("socket.http")
local url = require("socket.url")
local cjson = require("cjson")
local ltn12 = require("ltn12")
local table_sort = table.sort

-- 基本常量
local SIM_THRESHOLD = 0.50
local base_emb_cache = {}
local base_emb_cache_keys = {}
local base_data = {}

-- Keep-Alive 连接池
local http_connection = nil
local url_parts = url.parse(OLLAMA_HOST)
local http_host, http_port = url_parts.host or "127.0.0.1", url_parts.port or 11434

-- OpenRouter 命令解释侧车只兼容聊天/生成接口，不兼容 Ollama embedding。
-- 只有单独配置了兼容 embedding 后端时才允许语义匹配访问该路径。
local function semantic_is_enabled()
    return IS_LLM_ENABLED and IS_SEMANTIC_MATCH_ENABLED
end
-- ================================================

-- 创建或复用 HTTP 连接
local function get_http_connection()
    if http_connection then
        local status, err = http_connection:getstats()
        if status then
            return http_connection
        end
        http_connection:close()
        http_connection = nil
    end

    local socket = require("socket")
    local conn = socket.tcp()
    conn:settimeout(10)
    local ok, err = conn:connect(http_host, http_port)
    if not ok then
        error("Failed to connect to Ollama: " .. err)
    end
    http_connection = conn
    return conn
end

-- 通用请求（支持 Keep-Alive）
local function post_embedding(prompt_text)
    local payload = cjson.encode({
        model = EMB_MODEL,
        prompt = prompt_text
    })
    local resp_buf = {}
    local conn = get_http_connection()

    local _, code = http.request {
        url = OLLAMA_HOST .. "/api/embeddings",
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#payload),
            ["Connection"] = "keep-alive",
            ["Keep-Alive"] = "timeout=30, max=1000"
        },
        source = ltn12.source.string(payload),
        sink = ltn12.sink.table(resp_buf),
        create = function() return conn end
    }

    -- 如果连接出错，下次请求时重新创建
    if not code or code == 0 then
        http_connection = nil
        error("Ollama HTTP connection error")
    end

    if code ~= 200 then
        error("Ollama HTTP error code: " .. tostring(code))
    end
    return cjson.decode(table.concat(resp_buf)).embedding
end

-- 文档编码（不加前缀）
local function get_doc_embedding(text)
    return post_embedding(text)
end

-- 查询编码（加 BGE 指令前缀）
local function get_query_embedding(text)
    return post_embedding("为这个句子生成表示以用于检索相关文章：" .. text)
end

-- 余弦相似度
local function cosine_similarity(a, b)
    local dot, mag_a, mag_b = 0, 0, 0
    for i = 1, #a do
        dot = dot + a[i] * b[i]
        mag_a = mag_a + a[i] * a[i]
        mag_b = mag_b + b[i] * b[i]
    end
    mag_a, mag_b = math.sqrt(mag_a), math.sqrt(mag_b)
    if mag_a < 1e-8 or mag_b < 1e-8 then
        return 0.0
    end
    return dot / (mag_a * mag_b)
end

---预加载知识库向量
local function preload_base_emb()
    if not semantic_is_enabled() then
        return
    end
    local total = #base_data
    for id = 1, total do
        local content = base_data[id]
        if not base_emb_cache_keys[content] then
            base_emb_cache[id] = get_doc_embedding(content)
            base_emb_cache_keys[content] = id
        end
    end
end

---匹配结果
---@class MatchResult
---@field id number 在匹配目的表中的序号
---@field text string 匹配命中的字符串
---@field sim number 匹配相关度分数，1 为最高

---返回所有候选分数，按相似度降序排列
---@param query string 需要匹配的字符串
---@param options string[] 可选的匹配目标，用于筛选结果
---@return MatchResult[] #匹配结果列表，按密切度排序
local function semantic_match_all(query, options)
    local q_vec = get_query_embedding(query)
    local results = {}
    local filters = {}
    for _, opt in ipairs(options) do
        filters[opt] = true
    end

    for bid, vec in pairs(base_emb_cache) do
        local doc_text = base_data[tonumber(bid) or bid] or ""
        if not filters[doc_text] then
            goto continue
        end
        local sim = cosine_similarity(q_vec, vec)

        -- ★ 文本包含加分
        if #doc_text > 0 and doc_text:find(query, 1, true) then
            sim = sim + 0.2
        end

        results[#results + 1] = {
            id = bid,
            text = doc_text,
            sim = sim
        }
        ::continue::
    end

    table_sort(results, function(a, b)
        return a.sim > b.sim
    end)

    return results
end

---按相似度匹配最接近的，且相似度超过 SIM_THRESHOLD 阈值的字符串
---@param query string 查询的字符串
---@param options string[] 可选的匹配目标，用于筛选结果，注意这里的字符串必须都被提前add_match_src()缓存过
---@return string? #匹配命中的字符串，若无匹配则返回 nil
local function best_match(query, options)
    if not semantic_is_enabled() then
        return nil
    end
    local results = semantic_match_all(query, options)
    if #results > 0 and results[1].sim >= SIM_THRESHOLD then
        log.DEBUG(string.format("best_match: %s -> %s, sim=%.4f", query, results[1].text, results[1].sim))
        local matched_text = results[1].text
        return matched_text
    end
    return nil
end

---增加需要匹配的内容
---@param content string
local function add_match_src(content)
    -- log.DEBUG(string.format("add_match_src: %s", content))
    table.insert(base_data, content)
end

-- ===================== 测试 =====================
local function test()
    if not semantic_is_enabled() then
        log.INFO("语义匹配未启用，跳过 embedding 测试")
        return
    end
    log.INFO("开始测试语义匹配...")
    base_data = {
        "月台",
        "联合海关大厅",
        "车站入口售票处",
        "末班列车"
    }

    preload_base_emb()

    local test_queries = {
        "月台",
        "大厅",
        "售票处",
        "列车",
        "末班车",
        "海关",
        "入口售票"
    }

    local has_fail = false
    for _, q in ipairs(test_queries) do
        local results = semantic_match_all(q, base_data)
        local best = results[1]

        -- print(string.format("查询:「%s」", q))
        -- print(string.format("  ✅ 最佳匹配 → ID=%d 原文=%-12s 相似度=%.4f",
            -- best.id, best.text, best.sim))

        if best.sim < SIM_THRESHOLD then
            -- print("  ❌ 相似度低于阈值 0.50，视为无匹配")
            has_fail = true
        end

        -- print("  📊 全部候选：")
        -- for _, r in ipairs(results) do
        --     local marker = (r.id == best.id) and " ★" or ""
        --     if r.sim >= SIM_THRESHOLD then
        --         marker = marker .. " ✅"
        --     end
        --     print(string.format("     ID=%-2d %-14s 相似度=%.4f%s",
        --         r.id, r.text, r.sim, marker))
        -- end
        -- print()
    end
    base_data = {}
    base_emb_cache_keys = {}
    if has_fail then
        log.ERROR("❌ 语义匹配测试失败")
    else
        log.INFO("✅ 语义匹配测试通过")
    end
end

test()

return {
    add_match_src = add_match_src,
    preload_base_emb = preload_base_emb,
    semantic_match_all = semantic_match_all,
    SIM_THRESHOLD = SIM_THRESHOLD,
    best_match = best_match,
}