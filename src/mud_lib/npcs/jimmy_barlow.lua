---@module "mud_lib/npcs/jimmy_barlow"
---@description 职业介绍员吉米·巴洛

local log = require("mud_os/log")
local misc = require("mud_os/misc")
local Npc = require("mud_lib/npc")
local COC = require("mud_lib/coc/attrs")
local Jobs = require("mud_lib/coc/jobs")
local Skills = require("mud_lib/coc/skills")
local invoke_llm = require("mud_lib/invoke_llm")
local cmds = require("mud_lib/cmds")

local PlayerState = COC.PlayerState
local job_data = Jobs.job_data

local function generate_skills_with_llm(player_info, job_name, selected_skills, occupation_points, interest_points, attrs,
                                        user_id)
    if not IS_LLM_ENABLED then
        return nil
    end

    local job_info = job_data[job_name]
    local prompt = [[
你是一个COC（克苏鲁的呼唤）技能分配专家。根据以下信息，分配技能点数。
玩家信息：
]] .. player_info.name .. [[,
]] .. job_name .. [[,
]] .. player_info.age .. [[岁,
]] .. player_info.gender .. [[,
自我介绍：]] .. player_info.self_intro .. [[,
属性值：
力量 ]] .. attrs.STR .. [[,
体质 ]] .. attrs.CON .. [[,
敏捷 ]] .. attrs.DEX .. [[,
智力 ]] .. attrs.INT .. [[,
意志 ]] .. attrs.POW .. [[,
外貌 ]] .. attrs.APP .. [[,
教育 ]] .. attrs.EDU .. [[.
第一部分，职业技能点共]] .. occupation_points .. [[，分配到本职技能：【]] .. table.concat(job_info.occupation_skills, ",") .. [[】，每项最高75;
第二部分，兴趣技能点共]] .. interest_points .. [[，分配到兴趣技能：【]] .. table.concat(selected_skills, ",") .. [[】，每项最高50;
两部分都必须全部写出，缺一不可，分配完成自行求和核对总点数。
只输出{"results":[{"技能名1":技能值1,...}]}，无多余文字
]]
    local result = invoke_llm(prompt, "", user_id) --[[@as LLMInputResult]]
    if result and #result.results > 0 then
        local merged = {}
        for _, item in ipairs(result.results) do
            for skill_name, value in pairs(item) do
                merged[skill_name] = value
            end
        end
        return merged
    end
    log.WARNING("generate_skills_with_llm: 生成技能失败", result)
    return nil
end

local function generate_backstory_with_llm(player_info, job_name, attrs, user_id)
    if not IS_LLM_ENABLED then
        return nil
    end

    local prompt = [[
你是一个COC（克苏鲁的呼唤）模组背景写手。
根据以下玩家信息，创作一段生动的背景故事小传，包含一些神秘或诡异的元素（约100-200字）。
背景设定：1920年代美国，玩家是刚抵达的海外移民。
输出格式，纯JSON：
{"results":["……"]}
举例：
{"results":["XX是一个来自乌拉圭的农民，他来到美国后，开始在城市中工作，接触到一些奇怪的教会……"]}
]]
    local player_str = [[
角色信息：
]] .. player_info.name .. [[,
]] .. player_info.age .. [[岁,
]] .. player_info.gender .. [[,
]] .. job_name .. [[,
自评：]] .. player_info.self_intro .. [[。
力量 ]] .. attrs.STR .. [[,
体质 ]] .. attrs.CON .. [[,
敏捷 ]] .. attrs.DEX .. [[,
智力 ]] .. attrs.INT .. [[,
意志 ]] .. attrs.POW .. [[,
外貌 ]] .. attrs.APP .. [[,
教育 ]] .. attrs.EDU .. [[,
理智 ]] .. attrs.POW .. [[,
幸运 ]] .. attrs.LUK .. [[
]]

    local result = invoke_llm(prompt, player_str, user_id) --[[@as LLMInputResult]]
    if result and #result.results > 0 then
        return table.concat(result.results, "")
    end
    log.WARNING("generate_backstory_with_llm: 生成故事失败", result)
    return nil
end

--- 列出所有可选职业
---@param player Investigator 玩家对象
local function list_jobs(player)
    local job_list = "可选职业：\n"
    local count = 1
    for job_name, _ in pairs(job_data) do
        job_list = job_list .. count .. ". " .. job_name .. "\n"
        count = count + 1
    end
    job_list = job_list .. "你想选哪个？"
    player:reply(job_list)
end

--- 检查玩家是否已完成海关登记
---@param player Investigator 玩家对象
---@return boolean 是否已登记
local function check_registration(player)
    if not player.game_tags.customs_state or
        player.game_tags.customs_state < PlayerState.REGISTER_COMPLETED then
        player:reply("吉米撇了撇嘴：'先去海关那边登记完身份再来找我，没登记的人我可不敢介绍工作。'")
        return false
    end
    return true
end

--- 处理职业选择阶段
---@param player Investigator 玩家对象
---@param msg string 玩家输入
---@return boolean #是否继续处理
local function handle_job_select(player, msg)
    local job_info = job_data[msg]
    if job_info then
        -- 记录选中的职业并进入确认阶段
        player.game_tags.selected_job = msg
        player.game_tags.customs_state = PlayerState.JOB_CONFIRMED

        player:reply("吉米·巴洛从老花镜上方打量了你一眼：")
        player:reply("【" .. job_info.name .. "】")
        player:reply(job_info.desc)
        player:reply("职业点数公式：" .. job_info.skill_points_formula)
        player:reply("本职技能：" .. table.concat(job_info.occupation_skills, "、"))
        player:reply("信用区间：" .. job_info.credit_range[1] .. "-" .. job_info.credit_range[2])
        player:reply("你确定想选这个吗？需要再考虑一下吗？")
        return false
    end

    -- 职业不存在，重新列出可选职业
    player:reply("吉米皱了皱眉：'抱歉，我没听过这个职业。'")
    list_jobs(player)
    return false
end

--- 确认职业并进入技能选择阶段
---@param player Investigator 玩家对象
---@return boolean #是否继续处理
local function confirm_job(player)
    local job_info = job_data[player.game_tags.selected_job]

    -- 生成可选技能列表（排除克苏鲁神话技能）
    local skill_list = "可选技能（选择最多5个兴趣技能）：\n"
    local count = 1
    for skill_name, _ in pairs(Skills.skill_base_values) do
        if skill_name ~= "克苏鲁神话" then
            skill_list = skill_list .. skill_name .. "  "
            count = count + 1
            if count % 6 == 0 then skill_list = skill_list .. "\n" end
        end
    end

    -- 计算技能点数
    local occupation_points = Jobs.calculate_occupation_points(job_info.skill_points_formula,
        player.game_tags.attrs)
    local interest_points = Jobs.calculate_interest_points(player.game_tags.attrs.INT)

    -- 回复玩家并进入技能选择阶段
    player:reply("吉米眯着眼笑了笑：'好眼光！" .. job_info.name .. "是个不错的选择。'")
    player:reply("根据你的属性（" .. job_info.skill_points_formula .. "），你有 " ..
        occupation_points .. " 点职业技能点，以及 " .. interest_points .. " 点兴趣技能点。")
    player:reply("现在告诉我你的兴趣爱好相关的技能（最多5个，用逗号隔开）：")
    player:reply(skill_list)
    player.game_tags.customs_state = PlayerState.SKILL_SELECT
    return false
end

--- 处理职业确认阶段
---@param player Investigator 玩家对象
---@param msg string 玩家输入
---@return boolean #是否继续处理
local function handle_job_confirm(player, msg)
    -- 定义确认和取消的关键词模式
    local confirm_patterns = { "是", "确定", "不需要考虑", "不用考虑", "好", "选这个" }
    local cancel_patterns = { "不", "再考虑", "考虑", "取消", "换一个", "换职业" }

    -- 检查是否为确认
    local is_confirm = false
    for _, pattern in ipairs(confirm_patterns) do
        if string.find(msg, pattern) then
            is_confirm = true
            break
        end
    end

    -- 检查是否为取消
    local is_cancel = false
    for _, pattern in ipairs(cancel_patterns) do
        if string.find(msg, pattern) then
            is_cancel = true
            break
        end
    end

    -- 处理取消操作
    if is_cancel then
        player.game_tags.customs_state = PlayerState.JOB_SELECT
        player:reply("吉米点点头：'行，再和你说一次可选的职业：'")
        list_jobs(player)
        return false
    end

    -- 处理确认操作
    if is_confirm then
        return confirm_job(player)
    end

    -- 无法识别的输入，提示重新确认
    player:reply("吉米歪了歪头：'我没听懂你的意思。你确定想选" .. player.game_tags.selected_job .. "吗？需要再考虑一下吗？'")
    return false
end

--- 解析并验证玩家选择的技能
---@param msg string 玩家输入
---@return string[] #有效技能列表
---@return string[] #无效技能列表
local function parse_selected_skills(msg)
    local selected_skills = {}
    local invalid_skills = {}

    local parts = misc.split_string(msg)
    for _, skill_name in ipairs(parts) do
        -- 验证技能是否存在
        local found = false
        for valid_skill, _ in pairs(Skills.skill_base_values) do
            if valid_skill == skill_name then
                table.insert(selected_skills, valid_skill)
                found = true
                break
            end
        end
        if not found then
            table.insert(invalid_skills, skill_name)
        end
    end

    return selected_skills, invalid_skills
end

--- 完成角色创建流程
---@param player Investigator 玩家对象
---@param selected_skills table 玩家选择的兴趣技能列表
---@return boolean #是否继续处理
local function complete_character_creation(player, selected_skills)
    local job_info = job_data[player.game_tags.selected_job]
    local attrs = player.game_tags.attrs

    -- 初始化技能
    local skills = Skills.init_skills(attrs)

    -- 计算技能点数
    local occupation_points = Jobs.calculate_occupation_points(job_info.skill_points_formula, attrs)
    local interest_points = Jobs.calculate_interest_points(attrs.INT)
    log.DEBUG("occupation_points:",occupation_points,"interest_points:",interest_points,"INT:",attrs.INT)

    -- 分配技能点数（支持LLM自动分配和手动分配两种模式）
    if not IS_LLM_ENABLED then
        -- 手动分配模式：先分配职业技能点，再分配兴趣技能点
        skills = Skills.allocate_occupation_points(skills, job_info.occupation_skills, occupation_points)
        skills = Skills.allocate_interest_points(skills, job_info.occupation_skills, interest_points,
            selected_skills)
    else
        -- LLM自动分配模式：调用AI生成技能分配方案
        local llm_skills = generate_skills_with_llm(
            player.game_tags.register_info,
            player.game_tags.selected_job,
            selected_skills,
            occupation_points,
            interest_points,
            attrs,
            player.user_id
        )
        if llm_skills then
            -- 先应用LLM返回的技能值（不低于基础值）
            for skill_name, value in pairs(llm_skills) do
                if Skills.skill_base_values[skill_name] then
                    skills[skill_name] = math.max(Skills.skill_base_values[skill_name], value)
                end
            end

            -- 验证并修正LLM技能分配
            local occupation_skills_set = {}
            for _, skill in ipairs(job_info.occupation_skills) do
                occupation_skills_set[skill] = true
            end

            -- 计算职业技能实际分配点数（从基础值开始计算）
            local occ_actual_points = 0
            for _, skill in ipairs(job_info.occupation_skills) do
                occ_actual_points = occ_actual_points + (skills[skill] - Skills.skill_base_values[skill])
            end

            -- 检查并修正职业技能
            if occ_actual_points ~= occupation_points then
                local diff = occupation_points - occ_actual_points
                log.DEBUG("LLM职业技能分配错误，总点数差:", diff, "，期望:", occupation_points, "实际:", occ_actual_points)
                
                -- 按平均值方法修正（支持正负差值，均匀分配）
                local num_skills = #job_info.occupation_skills
                local remaining_diff = diff
                
                for i, skill in ipairs(job_info.occupation_skills) do
                    local skills_left = num_skills - i + 1
                    local add = math.floor(remaining_diff / skills_left)
                    
                    -- 确保至少分配1点（如果还有剩余）
                    if add == 0 and remaining_diff > 0 then
                        add = 1
                    elseif add == 0 and remaining_diff < 0 then
                        add = -1
                    end
                    
                    -- 确保技能值不低于基础值
                    local base_value = Skills.skill_base_values[skill]
                    local max_sub = skills[skill] - base_value
                    if add < 0 then
                        add = math.max(add, -max_sub)
                    end
                    
                    skills[skill] = skills[skill] + add
                    remaining_diff = remaining_diff - add
                    occ_actual_points = occ_actual_points + add
                    log.DEBUG("职业技能[", skill, "]修正了:", add, "点，修正后值:", skills[skill])
                end
            end

            -- 计算兴趣技能实际分配点数（从基础值开始计算）
            local int_actual_points = 0
            for _, skill in ipairs(selected_skills) do
                local base = Skills.skill_base_values[skill] or 0
                local current = skills[skill] or base
                int_actual_points = int_actual_points + (current - base)
            end

            -- 检查并修正兴趣技能
            if int_actual_points ~= interest_points then
                local diff = interest_points - int_actual_points
                log.DEBUG("LLM兴趣技能分配错误，总点数差:", diff, "，期望:", interest_points, "实际:", int_actual_points)
                
                -- 按平均值方法修正（支持正负差值，均匀分配）
                local num_skills = #selected_skills
                if num_skills > 0 then
                    local remaining_diff = diff
                    
                    for i, skill in ipairs(selected_skills) do
                        local skills_left = num_skills - i + 1
                        local add = math.floor(remaining_diff / skills_left)
                        
                        -- 确保至少分配1点（如果还有剩余）
                        if add == 0 and remaining_diff > 0 then
                            add = 1
                        elseif add == 0 and remaining_diff < 0 then
                            add = -1
                        end
                        
                        -- 检查上限（职业技能上限75，兴趣技能上限50）
                        local max_value = occupation_skills_set[skill] and 75 or 50
                        local base_value = Skills.skill_base_values[skill] or 0
                        local current_value = skills[skill] or base_value
                        
                        -- 限制增减范围
                        if add > 0 then
                            local max_add = max_value - current_value
                            add = math.min(add, max_add)
                        else
                            local max_sub = current_value - base_value
                            add = math.max(add, -max_sub)
                        end
                        
                        skills[skill] = current_value + add
                        remaining_diff = remaining_diff - add
                        int_actual_points = int_actual_points + add
                        log.DEBUG("兴趣技能[", skill, "]修正了:", add, "点，修正后值:", skills[skill])
                    end
                end
            end

            -- 检查并修正上限
            for _, skill in ipairs(job_info.occupation_skills) do
                if skills[skill] > 75 then
                    local diff = skills[skill] - 75
                    skills[skill] = 75
                    log.DEBUG("职业技能[", skill, "]超出上限75，修正减少:", diff, "点")
                end
            end
            for _, skill in ipairs(selected_skills) do
                local max_value = occupation_skills_set[skill] and 75 or 50
                if skills[skill] > max_value then
                    local diff = skills[skill] - max_value
                    skills[skill] = max_value
                    log.DEBUG("兴趣技能[", skill, "]超出上限", max_value, "，修正减少:", diff, "点")
                end
            end
        else
            player:reply("吉米突然打了个喷嚏，示意你再说一次。")
            return false
        end
    end

    -- 保存技能到玩家对象
    player.skill = skills

    -- 计算并保存信用值
    local credit = COC.calculate_credit(job_info.credit_range)
    player.game_tags.credit = credit

    -- 计算并保存移动力（MOV）
    local mov = COC.calculate_mov(attrs)
    player.game_tags.mov = mov

    -- 计算并保存魔法值（MP），COC规则中MP等于POW÷5向下取整
    local max_mp = math.floor(attrs.POW / 5)
    player.max_mp = max_mp
    player.mp = max_mp

    -- 生成背景故事（优先使用LLM生成）
    local backstory
    if IS_LLM_ENABLED then
        backstory = generate_backstory_with_llm(
            player.game_tags.register_info,
            player.game_tags.selected_job,
            attrs,
            player.user_id
        )
    end
    -- 如果LLM未启用或生成失败，使用玩家自我介绍
    if not backstory then
        backstory = player.game_tags.register_info.self_intro
    else
        -- LLM生成成功时，将玩家自我介绍添加到最后
        local self_intro = player.game_tags.register_info.self_intro
        if self_intro and self_intro ~= "" then
            backstory = backstory .. "\n自我介绍：" .. self_intro
        end
    end

    -- 更新玩家描述和身份标识
    player.desc = backstory
    player.exclusive = player.game_tags.selected_job .. "身份"

    -- 更新角色创建状态为已完成
    player.game_tags.customs_state = PlayerState.CHARACTER_COMPLETED

    -- 发送完成消息
    player:reply("吉米满意地点点头：'好，技能和背景都已经记录好了。'")
    player:reply("【系统】你的角色创建完成！")
    player:reply("职业：" .. player.game_tags.selected_job)
    player:reply("信用：" .. credit)
    player:reply("移动力：" .. mov)
    player:reply("魔法值：" .. max_mp)
    player:reply("兴趣技能：" .. (#selected_skills > 0 and table.concat(selected_skills, "、") or "无"))
    player:reply("【系统】你可以使用 'hp' 命令查看自己的状态。")
    player:reply("【系统】现在你可以走出大厅开始冒险了！")

    -- 保存玩家数据
    player:save()
    cmds.exit_dialog_mode(player)
    return false
end

--- 处理技能选择阶段
---@param player Investigator 玩家对象
---@param msg string 玩家输入
---@return boolean 是否继续处理
local function handle_skill_select(player, msg)
    -- 解析并验证技能
    local selected_skills, invalid_skills = parse_selected_skills(msg)

    -- 处理无效技能
    if #invalid_skills > 0 then
        player:reply("吉米皱了皱眉：'我没听过这些技能：" .. table.concat(invalid_skills, "、") .. "，你确定没记错吗？'")
        player:reply("请重新选择你的兴趣技能（最多5个，用逗号隔开）：")
        return false
    end

    -- 处理未选择技能的情况
    if #selected_skills == 0 then
        player:reply("吉米疑惑地看着你：'你还没有选择任何技能呢。'")
        player:reply("请选择你的兴趣技能（最多5个，用逗号隔开）：")
        return false
    end

    -- 去重处理
    local unique_skills = {}
    local seen = {}
    for _, skill in ipairs(selected_skills) do
        if not seen[skill] then
            seen[skill] = true
            table.insert(unique_skills, skill)
        end
    end
    selected_skills = unique_skills

    -- 限制最多选择5个技能
    if #selected_skills > 5 then
        selected_skills = { table.unpack(selected_skills, 1, 5) }
    end

    player.game_tags.selected_skills = selected_skills

    -- 完成角色创建
    player:reply("吉米喃喃的说道：'让我来看看，你适合哪些岗位...'")
    return complete_character_creation(player, selected_skills)
end



local jimmy_barlow = Npc.New("jimmy_barlow", "吉米·巴洛",
    "一身熨烫过但略显陈旧的深色细条纹西装，领口系着油腻的领带，马甲口袋里塞着半截雪茄与厚厚的纸质招工名册。头顶发量稀疏，两侧头发花白，嘴里常年叼着熄灭的雪茄，浑身透着老油条商人的市侩与圆滑。")
jimmy_barlow.topics = {
    ["介绍工作"] = "你看起来已经有一份工作了，用不着我再介绍了。",
    ["薪资"] = "学者、技师这类技术岗温饱无忧；律师、医生属于上流圈子；水手、保镖赚得多但要拿命换。",
    ["换工作"] = "初次选定免费更换一次，二次换岗需要支付中介费。官方岗位一旦入职可不容易离职。",
    ["怪事"] = "记者、考古学家、私家侦探、精神科医师更容易接触到离奇怪事。"
}
jimmy_barlow.listeners = {
    ---@param event_name string
    ---@param target Npc
    ---@param player Investigator
    ---@param msg string
    ---@param topic_resp string
    ---@return boolean
    ask_about = function(event_name, target, player, msg, topic_resp)
        -- 获取当前角色创建状态
        local state = player.game_tags.customs_state or PlayerState.IDLE

        -- 前置检查：玩家必须完成海关登记
        if not check_registration(player) then
            return false
        end

        -- 根据不同状态分支处理
        if state == PlayerState.JOB_SELECT then
            return handle_job_select(player, msg)
        end

        if state == PlayerState.JOB_CONFIRMED then
            return handle_job_confirm(player, msg)
        end

        if state == PlayerState.SKILL_SELECT then
            return handle_skill_select(player, msg)
        end

        -- 处理"介绍工作"命令，开始职业选择流程
        if msg == "介绍工作" then
            if player.game_tags.customs_state == PlayerState.REGISTER_COMPLETED then
                player.game_tags.customs_state = PlayerState.JOB_SELECT
                player:reply("吉米抬手吐出一口烟圈，将泛黄的招工名册拍在桌面上：'新来的？我这里有港区最全的工作。我给你介绍一下目前的空缺岗位：'")
                list_jobs(player)
                return false
            end
            return true
        end

        -- 其他输入处理
        if msg and player.game_tags.customs_state == PlayerState.REGISTER_COMPLETED then
            player:reply("吉米：'先选好职业再说其他的。'")
            return false
        end

        return true
    end
}

return jimmy_barlow