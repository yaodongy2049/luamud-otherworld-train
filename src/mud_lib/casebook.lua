---@module "mud_lib/casebook"
---@description 玩家私有案件状态、线索册与失败前进提示。

local Casebook = {}

local function ensure_state(player)
    player.game_tags = player.game_tags or {}
    player.game_tags.casebook = player.game_tags.casebook or {
        cases = {},
        order = {}
    }
    return player.game_tags.casebook
end

local function ensure_case(player, case_id, title, summary)
    local state = ensure_state(player)
    local case = state.cases[case_id]
    if not case then
        case = {
            id = case_id,
            title = title or case_id,
            summary = summary or "",
            objective = "",
            status = "active",
            clues = {},
            clue_order = {},
            setbacks = {}
        }
        state.cases[case_id] = case
        table.insert(state.order, case_id)
    end
    return case
end

---开始或获取玩家私有案件。
---@param player Investigator
---@param case_id string
---@param title string
---@param summary string
---@return table
function Casebook.start_case(player, case_id, title, summary)
    return ensure_case(player, case_id, title, summary)
end

---更新案件当前目标。
---@param player Investigator
---@param case_id string
---@param objective string
function Casebook.set_objective(player, case_id, objective)
    local case = ensure_case(player, case_id)
    case.objective = objective or ""
end

---记录只属于当前玩家的线索；重复记录不会生成副本。
---@param player Investigator
---@param case_id string
---@param clue_id string
---@param title string
---@param detail string
---@return boolean #本次是否首次发现
function Casebook.add_clue(player, case_id, clue_id, title, detail)
    local case = ensure_case(player, case_id)
    if case.clues[clue_id] then
        return false
    end
    case.clues[clue_id] = {
        id = clue_id,
        title = title,
        detail = detail
    }
    table.insert(case.clue_order, clue_id)
    player:reply("【线索册】记录线索：" .. title .. "。输入 journal 可回看。")
    return true
end

---记录失败代价与下一步，不把失败当作无提示的死路。
---@param player Investigator
---@param case_id string
---@param title string
---@param detail string
---@param next_step string
function Casebook.record_setback(player, case_id, title, detail, next_step)
    local case = ensure_case(player, case_id)
    table.insert(case.setbacks, {
        title = title,
        detail = detail,
        next_step = next_step
    })
    case.objective = next_step or case.objective
    player:reply("【案件进展】" .. title .. "。" .. detail)
    if next_step and next_step ~= "" then
        player:reply("【下一步】" .. next_step)
    end
end

---将案件标记为完成或保留活动状态。
---@param player Investigator
---@param case_id string
---@param status string
function Casebook.set_status(player, case_id, status)
    local case = ensure_case(player, case_id)
    case.status = status or "active"
end

local function case_status_label(status)
    if status == "completed" then
        return "已完成"
    elseif status == "locked" then
        return "已封存"
    end
    return "进行中"
end

---渲染当前玩家的私有案件册。
---@param player Investigator
---@param case_id string? #可选的案件ID
function Casebook.show(player, case_id)
    local state = ensure_state(player)
    local ids = {}
    if case_id and case_id ~= "" then
        if state.cases[case_id] then
            table.insert(ids, case_id)
        else
            player:reply("【线索册】没有编号为 " .. case_id .. " 的案件。")
            return
        end
    else
        ids = state.order
    end

    if #ids == 0 then
        player:reply("【线索册】尚未开始案件。先观察环境、与NPC交谈或调查可疑物品。")
        return
    end

    local lines = { "========== 线索册 ==========" }
    for _, id in ipairs(ids) do
        local case = state.cases[id]
        table.insert(lines, string.format("【%s】%s（%s）", id, case.title, case_status_label(case.status)))
        if case.summary and case.summary ~= "" then
            table.insert(lines, "摘要：" .. case.summary)
        end
        if case.objective and case.objective ~= "" then
            table.insert(lines, "当前目标：" .. case.objective)
        end
        if #case.clue_order > 0 then
            table.insert(lines, "线索：")
            for _, clue_id in ipairs(case.clue_order) do
                local clue = case.clues[clue_id]
                table.insert(lines, "- " .. clue.title .. "：" .. clue.detail)
            end
        end
        if #case.setbacks > 0 then
            local setback = case.setbacks[#case.setbacks]
            table.insert(lines, "最近代价：" .. setback.title .. "——" .. setback.detail)
        end
        table.insert(lines, "")
    end
    table.insert(lines, "提示：案件、线索与目标会随 save 和正常下线自动保存。")
    player:reply(table.concat(lines, "\n"))
end

return Casebook
