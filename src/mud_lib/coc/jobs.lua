---@module "mud_lib/coc/jobs"
---@description COC 7版职业数据

local log = require("mud_os/log")

---@class JobData
---@field name string # 职业名称
---@field desc string # 职业描述
---@field skill_points_formula string # 技能点数公式，用于计算职业技能点数分配
---@field occupation_skills table<string> # 本职技能列表
---@field credit_range table<number, number> # 信用区间

---14个职业数据（COC 7版规则）
---@type table<string, JobData>
local job_data = {
    ["作家"] = {
        name = "作家",
        desc = "适合博览群书、擅长文字创作的聪明人。主要为本地杂志社、报社撰写小说、纪实文稿与灵异专栏，闲暇可自主出版书籍。",
        skill_points_formula = "EDU×4",
        occupation_skills = { "艺术(文学)", "历史", "图书馆使用", "博物学", "神秘学", "其他语言", "母语", "心理学" },
        credit_range = { 9, 40 }
    },
    ["考古学家"] = {
        name = "考古学家",
        desc = "专门研究古物遗迹的专业人才，时常承接私人收藏家、博物馆的委托，走访城郊古遗址、打捞近海沉船古物。",
        skill_points_formula = "EDU×2+INT×2",
        occupation_skills = { "考古学", "历史", "图书馆使用", "神秘学", "地质学", "其他语言", "母语", "侦查" },
        credit_range = { 10, 40 }
    },
    ["图书馆管理员"] = {
        name = "图书馆管理员",
        desc = "城内公立、私立图书馆在岗职员，日常负责书籍归档、文献检索、登记借阅信息，协助学者查阅各类绝版档案。",
        skill_points_formula = "EDU×4",
        occupation_skills = { "会计", "图书馆使用", "其他语言", "母语", "历史", "神秘学", "博物学", "心理学" },
        credit_range = { 9, 35 }
    },
    ["私家侦探"] = {
        name = "私家侦探",
        desc = "不受警局管束的民间调查者，承接寻人、取证、纠纷调查、隐私追踪等私人委托。游走在法律灰色地带，人脉复杂。",
        skill_points_formula = "EDU×2+DEX×2",
        occupation_skills = { "艺术(摄影)", "伪装", "法律", "图书馆使用", "侦查", "心理学", "说服", "潜行" },
        credit_range = { 9, 30 }
    },
    ["警探"] = {
        name = "警探",
        desc = "隶属于城市警察局刑侦部门，负责侦破刑事案件、审讯嫌疑人、排查城区治安隐患。",
        skill_points_formula = "EDU×2+DEX×2",
        occupation_skills = { "艺术(表演)", "伪装", "射击", "法律", "聆听", "心理学", "侦查", "说服" },
        credit_range = { 20, 50 }
    },
    ["外勤记者"] = {
        name = "外勤记者",
        desc = "为本地报刊、杂志社奔走取材的外勤人员。游走港区、市井街巷搜集奇闻轶事、社会案件、近海秘闻。",
        skill_points_formula = "EDU×2+INT×2",
        occupation_skills = { "艺术(摄影)", "历史", "图书馆使用", "母语", "心理学", "话术", "侦查", "潜行" },
        credit_range = { 9, 40 }
    },
    ["执业医生"] = {
        name = "执业医生",
        desc = "持证上岗的专业全科医师，可就职于公立医院或开设私人诊所，处理外伤急救、常见病诊疗、药物调配等工作。",
        skill_points_formula = "EDU×4",
        occupation_skills = { "急救", "拉丁语", "医学", "心理学", "科学(生物)", "科学(药学)", "诊断", "解剖" },
        credit_range = { 30, 70 }
    },
    ["精神科医师"] = {
        name = "精神科医师",
        desc = "专攻精神类疾病的专科医生，一战过后创伤病患激增，岗位缺口极大。专门诊治心理扭曲、精神失常的病人。",
        skill_points_formula = "EDU×2+POW×2",
        occupation_skills = { "精神分析", "医学", "心理学", "神秘学", "母语", "说服", "话术", "急救" },
        credit_range = { 30, 70 }
    },
    ["演员"] = {
        name = "演员",
        desc = "巡回剧团、剧场院线的专职舞台剧及影视演员。当下电影行业刚刚起步，各地剧团巡演火热。",
        skill_points_formula = "APP×2+EDU×2",
        occupation_skills = { "艺术(表演)", "伪装", "说服", "心理学", "取悦", "话术", "恐吓"},
        credit_range = { 50, 90 }
    },
    ["执业律师"] = {
        name = "执业律师",
        desc = "持证法务从业者，为个人、商户乃至黑帮、走私团伙提供法律咨询与出庭辩护服务。",
        skill_points_formula = "EDU×4",
        occupation_skills = { "法律", "图书馆使用", "话术", "说服", "心理学", "母语", "恐吓", "谈判" },
        credit_range = { 20, 60 }
    },
    ["远洋水手"] = {
        name = "远洋水手",
        desc = "签约远洋货轮的专职船员，常年往返近海与周边港口，负责船舶航行、货物转运、海上应急作业。",
        skill_points_formula = "STR×2+CON×2",
        occupation_skills = { "攀爬", "游泳", "导航", "机械维修", "斗殴", "射击", "聆听", "航海" },
        credit_range = { 9, 30 }
    },
    ["私人保镖"] = {
        name = "私人保镖",
        desc = "受雇于富商、政客、社会名流，专职负责雇主人身安全。擅长近身格斗、枪械使用、潜行警戒与环境侦查。",
        skill_points_formula = "STR×2+DEX×2",
        occupation_skills = { "斗殴", "闪避", "射击", "潜行", "恐吓", "侦查", "聆听", "驾驶" },
        credit_range = { 10, 40 }
    },
    ["现役军官"] = {
        name = "现役军官",
        desc = "隶属于地方驻防部队的基层军官，经历过一战洗礼者优先录用。统筹小队执勤、物资调度、应急维稳工作。",
        skill_points_formula = "EDU×2+STR×2",
        occupation_skills = { "会计", "射击", "导航", "急救", "说服", "恐吓", "心理学", "指挥" },
        credit_range = { 20, 70 }
    },
    ["全能技师"] = {
        name = "全能技师",
        desc = "港区稀缺技术工匠，专攻汽车、船舶、工业机械、电气设备的维修与改造。",
        skill_points_formula = "DEX×2+EDU×2",
        occupation_skills = { "技艺(木工/焊接)", "攀爬", "驾驶", "电气维修", "机械维修", "锁匠", "工程", "机械" },
        credit_range = { 9, 40 }
    }
}

---计算职业技能点数
---@param formula string # 技能点数公式，用于计算职业技能点数分配
---@param attrs table<string, number> # 所有属性的基础值
---@return number # 职业技能点数分配
local function calculate_occupation_points(formula, attrs)
    local points = 0
    local attr_map = {
        STR = attrs.STR,
        CON = attrs.CON,
        SIZ = attrs.SIZ,
        DEX = attrs.DEX,
        APP = attrs.APP,
        INT = attrs.INT,
        POW = attrs.POW,
        EDU = attrs.EDU,
        LUK = attrs.LUK
    }

    -- 解析公式如 "EDU×4" 或 "EDU×2+INT×2"
    local parts = {}
    for part in string.gmatch(formula, "[^+]+") do
        table.insert(parts, part)
    end

    for _, part in ipairs(parts) do
        local attr_name, multiplier = string.match(part, "^%s*([A-Z]+)%s*×%s*(%d+)%s*$")
        if attr_name and multiplier then
            local attr_value = attr_map[attr_name] or 50
            points = points + attr_value * tonumber(multiplier)
            log.DEBUG("attr_name", attr_name, ",multiplier", multiplier)
        end
    end

    log.DEBUG("formula:", formula, ",points:", points)
    return points
end

---计算兴趣技能点数（固定分配）
---@param int_attr number # 兴趣属性值
---@return number # 兴趣技能点数分配
local function calculate_interest_points(int_attr)
    return int_attr * 2
end

return {
    job_data = job_data,
    calculate_occupation_points = calculate_occupation_points,
    calculate_interest_points = calculate_interest_points
}
