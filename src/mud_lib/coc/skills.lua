---@module "mud_lib/coc/skills"
---@description COC 7版技能系统

---所有技能的基础值（COC 7版标准）
---@type table<string, number>
local skill_base_values = {
    -- 核心生存/侦查技能
    ["侦查"] = 25,
    ["聆听"] = 20,
    ["潜行"] = 20,
    ["追踪"] = 10,
    ["闪避"] = 0, -- 特殊：DEX÷2

    -- 社交/交涉技能
    ["话术"] = 5,
    ["说服"] = 15,
    ["恐吓"] = 15,
    ["取悦"] = 15,
    ["心理学"] = 10,

    -- 知识/学术技能
    ["图书馆使用"] = 20,
    ["历史"] = 20,
    ["神秘学"] = 5,
    ["博物学"] = 10,

    -- 医疗/精神技能
    ["急救"] = 30,
    ["医学"] = 5,
    ["精神分析"] = 5,

    -- 战斗/武器技能
    ["斗殴"] = 25,
    ["手枪"] = 20,
    ["步枪/霰弹枪"] = 15,
    ["近战武器"] = 15,
    ["投掷"] = 20,

    -- 技术/手工技能
    ["锁匠"] = 10,
    ["机械维修"] = 10,
    ["电气维修"] = 5,

    -- 艺术/表演技能
    ["艺术(文学)"] = 5,
    ["艺术(摄影)"] = 5,
    ["艺术(表演)"] = 5,
    ["伪装"] = 5,

    -- 特殊技能
    ["克苏鲁神话"] = 0,

    -- 其他技能
    ["考古学"] = 10,
    ["地质学"] = 10,
    ["其他语言"] = 10,
    ["母语"] = 30,
    ["法律"] = 10,
    ["科学(生物)"] = 10,
    ["科学(药学)"] = 10,
    ["攀爬"] = 20,
    ["游泳"] = 20,
    ["导航"] = 10,
    ["驾驶"] = 10,
    ["会计"] = 10,
    ["拉丁语"] = 5,
    ["技艺(木工/焊接)"] = 10,
    ["射击"] = 20,
    ["航海"] = 10,
    ["指挥"] = 10,
    ["工程"] = 10,
    ["机械"] = 10,
    ["诊断"] = 5,
    ["解剖"] = 5,
    ["谈判"] = 10
}

---初始化所有技能基础值
---@return table<string, number> # 所有技能的基础值
local function init_skills(attrs)
    local skills = {}
    for skill_name, base_value in pairs(skill_base_values) do
        -- 闪避特殊处理：DEX÷2
        if skill_name == "闪避" then
            skills[skill_name] = math.floor((attrs.DEX or 50) / 2)
        else
            skills[skill_name] = base_value
        end
    end
    return skills
end

---分配职业技能点数（随机分配到本职技能，上限75%）
---@param skills table<string, number> # 所有技能的基础值
---@param occupation_skills table<string> # 本职技能列表
---@param points number # 分配的点数
---@return table<string, number> # 所有技能的基础值
local function allocate_occupation_points(skills, occupation_skills, points)
    local remaining_points = points
    local allocated = {}

    -- 初始化已分配点数
    for _, skill in ipairs(occupation_skills) do
        allocated[skill] = 0
    end

    -- 随机分配，每次分配1d10点
    while remaining_points > 0 do
        -- 随机选择一个本职技能
        local idx = math.random(1, #occupation_skills)
        local skill = occupation_skills[idx]

        -- 计算该技能还能加多少（上限75%）
        local current_value = skills[skill] or 0
        local max_add = 75 - current_value - allocated[skill]

        if max_add > 0 then
            -- 分配1d10点，但不超过剩余点数和上限
            local add_points = math.min(math.random(1, 10), remaining_points, max_add)
            allocated[skill] = allocated[skill] + add_points
            remaining_points = remaining_points - add_points
        end
    end

    -- 应用分配结果
    for skill, add_points in pairs(allocated) do
        if skills[skill] then
            skills[skill] = skills[skill] + add_points
        end
    end

    return skills
end

---分配兴趣技能点数（完全分配到用户选择的技能，非本职上限50%，本职上限75%）
---@param skills table<string, number> # 所有技能的基础值
---@param occupation_skills table<string> # 本职技能列表
---@param points number # 分配的点数
---@param selected_skills table<string>? # 用户选择的兴趣技能列表（可选）
---@return table<string, number> # 所有技能的基础值
local function allocate_interest_points(skills, occupation_skills, points, selected_skills)
    local remaining_points = points
    selected_skills = selected_skills or {}

    -- 如果没有选择技能，直接返回
    if #selected_skills == 0 then
        return skills
    end

    -- 分配用户选择的技能
    while remaining_points > 0 do
        local allocated = false
        -- 遍历用户选择的技能
        for _, skill in ipairs(selected_skills) do
            if remaining_points <= 0 then break end
            
            -- 判断是否为本职技能
            local is_occupation = false
            for _, occ_skill in ipairs(occupation_skills) do
                if occ_skill == skill then
                    is_occupation = true
                    break
                end
            end

            -- 计算该技能还能加多少
            local current_value = skills[skill] or 0
            local max_add = is_occupation and (75 - current_value) or (50 - current_value)

            if max_add > 0 then
                -- 分配1d10点
                local add_points = math.min(math.random(1, 10), remaining_points, max_add)
                skills[skill] = current_value + add_points
                remaining_points = remaining_points - add_points
                allocated = true
            end
        end
        if not allocated then break end
    end

    -- 未分配完的点数直接丢弃

    return skills
end

return {
    skill_base_values = skill_base_values,
    init_skills = init_skills,
    allocate_occupation_points = allocate_occupation_points,
    allocate_interest_points = allocate_interest_points
}