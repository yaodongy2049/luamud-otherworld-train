---@module "mud_lib/coc/attrs"
---@description COC 7版属性系统

-- 玩家状态枚举（使用数字值便于比较大小）
local PlayerState = {
    IDLE = 0,
    REGISTER_NAME = 1,
    REGISTER_AGE = 2,
    REGISTER_SELF_INTRO = 3,
    REGISTER_STAY_TIME = 4,
    REGISTER_COMPLETED = 10,
    JOB_SELECT = 11,
    JOB_CONFIRMED = 12,
    SKILL_SELECT = 13,
    CHARACTER_COMPLETED = 100
}

-- 随机生成属性值（COC规则：3d6*5）
local function roll_attr()
    return math.floor((math.random(6) + math.random(6) + math.random(6)) * 5)
end

-- 生成完整属性（9维）
-- @param seed number? 随机种子，可选
local function generate_attrs(seed)
    -- 如果提供了种子，设置随机数生成器
    if seed then
        math.randomseed(seed)
        -- 调用几次以确保随机性
        math.random(); math.random(); math.random()
    end

    return {
        STR = roll_attr(),
        CON = roll_attr(),
        SIZ = roll_attr(),
        DEX = roll_attr(),
        APP = roll_attr(),
        INT = roll_attr(),
        POW = roll_attr(),
        EDU = roll_attr(),
        LUK = roll_attr()
    }
end

-- 计算HP ((CON + SIZ) ÷ 10 向下取整)
local function calculate_hp(attrs)
    return math.floor((attrs.CON + attrs.SIZ) / 10)
end

-- 计算MOV
local function calculate_mov(attrs)
    if attrs.DEX > attrs.SIZ then
        return 8
    elseif attrs.DEX == attrs.SIZ then
        return 7
    else
        return 6
    end
end

-- 计算信用（根据职业信用区间随机生成）
local function calculate_credit(credit_range)
    if not credit_range then
        return 0
    end
    local credit_min, credit_max = table.unpack(credit_range)
    return credit_min + math.random(0, credit_max - credit_min)
end

return {
    PlayerState = PlayerState,
    roll_attr = roll_attr,
    generate_attrs = generate_attrs,
    calculate_hp = calculate_hp,
    calculate_mov = calculate_mov,
    calculate_credit = calculate_credit
}
