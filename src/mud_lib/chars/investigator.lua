---@module 'mud_lib/chars/investigator'
local class = require("mud_os/class")
local EventSystem = require("mud_os/event_system")
local Charactor = require("mud_lib/char")
local Player = require("mud_lib/player")

---@class CoreAttrs
---@field str number 力量
---@field con number 体质
---@field dex number 敏捷
---@field int number 智力
---@field pow number 意志
---@field app number 外貌
---@field edu number 教育

---短时间状态结构体，存储临时状态信息
---@class TempStatus
---@field last_say_target string? 上次说话的目标ID
---@field last_say_time number? 上次说话的时间戳（秒）
---@field dev_mode boolean? 是否为开发模式

---调查员类，继承自Player，增加理智值和魔法值属性
---@class Investigator : Player
---@field san number 当前理智值
---@field mp number 当前魔法值
---@field max_mp number 最大魔法值
---@field core_attrs CoreAttrs 核心属性，如智力、敏捷、力量等
---@field skill table<string,number> 技能，如侦查、聆听、急救、潜行、话术、灵感等
---@field exclusive string 专属属性，如是否只能与指定角色交互
---@field game_tags table<string, any> 游戏标签，记录游戏逻辑相关的信息
---@field environment Room 所处房间，记录当前所在的位置
local Investigator = {
    __name = "Investigator",
    san = 100,
    mp = 0,
    max_mp = 0,
    core_attrs = {
        str = 50, --力量
        con = 50, --体质
        dex = 50, --敏捷
        int = 50, --智力
        pow = 50, --力量
        app = 50, --敏捷
        edu = 50, --智力
    },
    skill = {
        ["侦查"] = 20,
        ["聆听"] = 20,
        ["急救"] = 20,
        ["潜行"] = 20,
        ["灵感"] = 20,
        ["格斗"] = 20,
    },
    exclusive = "nobody",
    desc = "一个专业的调查员，负责调查和分析事件。",
    game_tags = {},
}

---创建调查员实例
---@param user_id string 通信用的ID
---@param user_data UserData 存储的玩家数据
function Investigator:init(user_id, user_data)
    -- 调用父类初始化
    Player.init(self, user_id, user_data)

    -- 加载保存的理智值数据
    self.san = self:get_user_data("san")

    -- 加载保存的魔法值数据
    self.mp = self:get_user_data("mp")
    self.max_mp = self:get_user_data("max_mp")

    -- 从 game_tags.attrs 生成 core_attrs（避免重复存储）
    if self.game_tags and self.game_tags.attrs then
        local attrs = self.game_tags.attrs
        self.core_attrs = {
            str = attrs.STR or 50,
            con = attrs.CON or 50,
            dex = attrs.DEX or 50,
            int = attrs.INT or 50,
            pow = attrs.POW or 50,
            app = attrs.APP or 50,
            edu = attrs.EDU or 50
        }
    end

    -- 加载保存的技能数据
    self.skill = self:get_user_data("skill")

    -- 加载保存的专属属性数据
    self.exclusive = self:get_user_data("exclusive")

    -- 加载保存的游戏标签数据
    self.game_tags = self:get_user_data("game_tags")

    -- 加载保存的死亡回调函数
    if self.game_tags and self.game_tags.die then
        for k, v in pairs(self.game_tags.die) do
            local room = Room.get_world().rooms[k] --[[@class table]]
            local die_cb = room.logic_funcs[v]
            EventSystem:register_listener("die", die_cb, self)
        end
    end

    return self
end

---保存调查员数据（包含理智值）
function Investigator:save()
    -- 保存理智值数据
    self:set_user_data("san", self.san)

    -- 保存魔法值数据
    self:set_user_data("mp", self.mp)
    self:set_user_data("max_mp", self.max_mp)

    -- 核心属性不再单独保存，从 game_tags.attrs 自动生成

    -- 保存技能数据
    self:set_user_data("skill", self.skill)

    -- 保存专属属性数据
    self:set_user_data("exclusive", self.exclusive)

    -- 保存游戏标签数据
    self:set_user_data("game_tags", self.game_tags)

    -- 调用父类保存
    Player.save(self)
end

function Investigator:description()
    local san_msg = "他的表情扭曲而疯狂，看起来理智完全崩溃了。"
    if self.san >= 50 then
        san_msg = "他表情自然放松，看起来精神充沛，思绪清晰。"
    elseif self.san > 40 then
        san_msg = "他的表情正常，但似乎有一点疲惫。"
    elseif self.san > 30 then
        san_msg = "他看起来感觉有些不安，但还能保持镇定。"
    elseif self.san > 20 then
        san_msg = "他看起来有些神经兮兮，似乎觉得自己被什么东西注视着，不时的四处张望。"
    elseif self.san > 10 then
        san_msg = "他时不时自言自语，似乎听到了一些奇怪的声音，看起来理智正在逐渐瓦解。"
    elseif self.san > 0 then
        san_msg = "他眼神空洞，嘴角抽搐，看起来已经无法分辨现实和虚幻，接近崩溃的边缘。"
    end

    return Charactor.description(self) .. "\n" .. san_msg
end

function Investigator:status_gmcp()
    local data = Player.status_gmcp(self)
    data.san = self.san
    data.mp = self.mp
    data.max_mp = self.max_mp
    return data
end

---设置角色的理智值，上限 99
---@param value number 理智值
function Investigator:set_san(value)
    local was_sane = self.san > 0
    local old_san = self.san
    self.san = math.max(0, math.min(value, 99))
    local delta = self.san - old_san

    if delta ~= 0 then
        local color = "\27[35m"
        local reset = "\27[0m"
        self:reply(string.format("%s【系统】SAN %+d%s", color, delta, reset))
    end

    if was_sane and self.san == 0 then
        self:_trigger_permanent_insanity()
    end
end

---触发永久疯狂（SAN降到0）
function Investigator:_trigger_permanent_insanity()
    self.game_tags.permanent_insanity = true
    self:_trigger_insanity_event("永久疯狂", "理智值归零")
    self:reply("你的理智彻底崩溃了...你不再是你自己了...")
end

---修改角色的技能值（增减）
---@param skill_name string 技能名称
---@param delta number 技能变化量（正数增加，负数减少）
function Investigator:modify_skill(skill_name, delta)
    if delta == 0 then return end

    local old_value = self.skill[skill_name] or 0
    self.skill[skill_name] = math.max(0, old_value + delta)
    local actual_delta = self.skill[skill_name] - old_value

    if actual_delta ~= 0 then
        local color = "\27[94m"
        local reset = "\27[0m"
        self:reply(string.format("%s【系统】%s %+d%s", color, skill_name, actual_delta, reset))
    end
end

---修改角色的理智值（增减）
---@param delta number 理智值变化量（正数增加，负数减少）
function Investigator:modify_san(delta)
    -- SAN值增加：直接设置新值，触发恢复事件（如解除临时疯狂）
    if delta >= 0 then
        self:set_san(self.san + delta)
        if delta > 0 then
            self:_on_san_recovery(delta)
        end
        return
    end

    -- SAN值减少：先记录原值，再计算实际损失量（防止负值溢出）
    local original_san = self.san
    self:set_san(self.san + delta)
    local actual_loss = original_san - self.san

    -- 无实际损失时直接返回（如SAN已为0）
    if actual_loss <= 0 then
        return
    end

    -- COC规则：理智丧失伴随着对宇宙真相的认知加深，每损失1点SAN，克苏鲁神话技能+1
    self:modify_skill("克苏鲁神话", actual_loss)

    -- 检查临时疯狂：单次损失≥5点时触发理智检定，失败则获得临时疯狂状态
    self:_check_temporary_insanity(actual_loss)
    -- 检查不定疯狂：单日累计损失≥当前SAN值1/5时触发，可能获得永久疯狂症状
    self:_check_indefinite_insanity(actual_loss)
end

---检查临时疯狂（单次掉SAN≥5点）
---@param loss number 单次SAN损失量
function Investigator:_check_temporary_insanity(loss)
    if loss < 5 then
        return
    end

    local int_roll = math.random(1, 100)
    local int_value = self.core_attrs.int or 50

    if int_roll > int_value then
        self:reply("你感到一阵眩晕，但大脑自动压抑了这段记忆...")
        return
    end

    local duration = math.random(1, 10)
    self.game_tags.temporary_insanity = {
        duration = duration,
        end_time = os.time() + duration * 3600
    }

    local insanity_type = math.random(1, 2) == 1 and "恐惧症" or "躁狂症"
    self.game_tags.insanity_disorder = insanity_type

    self:_trigger_insanity_event("临时疯狂", string.format("持续%d小时，获得%s", duration, insanity_type))
end

---检查不定疯狂（单日累计掉SAN≥当前1/5）
---@param loss number 本次SAN损失量
function Investigator:_check_indefinite_insanity(loss)
    local now = os.time()
    local day_seconds = 24 * 3600

    -- 首次扣减SAN，初始化不定疯狂追踪数据
    -- start_san: 记录第一次开始累计时的SAN值（当前san + 本次损失，还原到扣减前）
    -- accumulated: 累计扣减值
    -- last_time: 最后一次扣减时间戳
    if not self.game_tags.indefinite_insanity then
        self.game_tags.indefinite_insanity = {
            start_san = self.san + loss, -- 记录累计周期开始时的SAN值
            accumulated = loss,          -- 累计扣减初始化为本次损失
            last_time = now              -- 记录扣减时间
        }
        return
    end

    local insanity_data = self.game_tags.indefinite_insanity

    -- 检查是否超过一个游戏日（24小时），如果超过则重置累计周期
    if now - insanity_data.last_time > day_seconds then
        insanity_data.start_san = self.san + loss -- 重置开始SAN值
        insanity_data.accumulated = loss          -- 重置累计扣减
        insanity_data.last_time = now             -- 更新时间戳
        self:reply("你的可怕回忆虽然渐渐淡去，但你仍然受到了不小的打击。")
        return
    end

    -- 如果已经处于潜伏状态（indefinite_insanity_active为true），再掉任何SAN都立即触发发作
    if self.game_tags.indefinite_insanity_active then
        self:_trigger_insanity_event("不定疯狂发作", "潜伏期间再次损失SAN")
    end

    -- 累加本次损失并更新时间戳
    insanity_data.accumulated = insanity_data.accumulated + loss
    insanity_data.last_time = now

    -- 检查累计损失是否达到当前SAN的1/5，达到则进入潜伏状态
    -- 此后只要再掉1点SAN就会触发不定疯狂发作
    if insanity_data.accumulated >= insanity_data.start_san * 0.2
        and not self.game_tags.indefinite_insanity_active then
        self.game_tags.indefinite_insanity_active = true -- 标记进入潜伏状态
        self:reply("你的精神开始变得不稳定...随时可能崩溃！")
    end
end

---理智值恢复时的处理
---@param recovery number 恢复量
function Investigator:_on_san_recovery(recovery)
    if self.game_tags.indefinite_insanity then
        local needed = self.game_tags.indefinite_insanity.start_san * 0.2
        if self.game_tags.indefinite_insanity.accumulated < needed then
            self.game_tags.indefinite_insanity = nil
            self.game_tags.indefinite_insanity_active = nil
            self:reply("经过休养，你的精神状态有所恢复。")
        end
    end
end

---触发发疯事件
---@param type string 疯狂类型："临时疯狂" | "不定疯狂发作" | "永久疯狂"
---@param reason string 触发原因："持续%d小时，获得恐惧症|躁狂症" | "潜伏期间再次损失SAN" | "理智值归零"
function Investigator:_trigger_insanity_event(type, reason)
    local handled = EventSystem:trigger("insanity", self, type, reason)

    if not handled then
        local insanity_messages = {
            "突然尖叫起来：'不！别过来！'",
            "跪倒在地，双手抱头瑟瑟发抖...",
            "眼神空洞地喃喃自语：'它们来了...它们一直在看着我们...'",
            "突然大笑起来，笑声令人毛骨悚然...",
            "拼命地抓挠自己的脸，似乎想把什么东西撕下来...",
            "蜷缩在角落，浑身发抖，不敢抬头...",
            "突然跳起来，对着空气疯狂攻击...",
            "泪流满面，语无伦次地说着什么..."
        }
        local msg = insanity_messages[math.random(1, #insanity_messages)]

        local this_place = self.environment --[[ @as Room ]]
        if this_place and this_place.channel then
            this_place.channel:say(self.name .. msg, self)
        end
    end
end

---设置角色的魔法值
---@param value number 魔法值
function Investigator:set_mp(value)
    self.mp = math.max(0, math.min(value, self.max_mp))
end

---修改角色的魔法值（增减）
---@param delta number 魔法值变化量（正数增加，负数减少）
function Investigator:modify_mp(delta)
    self:set_mp(self.mp + delta)
end

---执行 COC 检定骰子
---@param x number 骰子数量（如 3 表示 3d4）
---@param y number 骰子面数（如 4 表示 d4）
---@param z number? 投掷次数，默认为 1
---@return number[] #返回每次投掷的总点数
function Investigator:roll(x, y, z)
    -- 默认投掷次数为 1
    z = z or 1

    local results = {}

    -- 执行 z 次投掷
    for i = 1, z do
        local total = 0
        -- 每次投掷 x 个 y 面骰子
        for j = 1, x do
            total = total + math.random(y)
        end
        table.insert(results, total)
    end

    return results
end

class.define_class(Investigator, Player)
return Investigator