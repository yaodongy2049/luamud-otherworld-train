---@module "mud_lib/map/base"
---@description 基础地图模块

local log = require("mud_os/log")
local EventSystem = require("mud_os/event_system")
local Item = require("mud_lib/item")
local Npc = require("mud_lib/npc")
local Room = require("mud_lib/room")
local Monster = require("mud_lib/monster")
local Weapon = require("mud_lib/weapon")


-- 给 BornPoint 房间进行初始化
local admin = Npc.New("admin", "管理员", "一个中年秃头胖子")
admin.topics = {
    ["任务"] = "你可以去东边的新手村接取任务。",
    ["天气"] = "今天天气真好，适合冒险！",
    ["装备"] = "我这里有一些新手装备，需要的话可以拿。"
}

local badge = Item.New("badge", "调查员徽章", "这是一个摸得发旧的调查员徽章", false)
badge.wear_pos = "brooch" -- 可穿戴位置为胸针
badge.use = function(self, this_player, target)
    if not target then
        this_player:reply("你使用了调查员徽章，但是没有反应")
        return
    end
    if target.id == admin.id then
        this_player:reply("你对管理员展示了调查员徽章，他吓了一跳。")
        target:say(this_player.name .. "，你吓死我了")
        return
    else
        this_player:reply(string.format("你对%s使用了%s，但是没有反应。", target.name, self.name))
    end
end

local axe = Weapon.New("axe", "消防斧", "这是一个消防用的斧头", 6, "right_hand")

-- 消防斧的攻击命中消息
axe.attack_msg = {
    "%s挥舞着消防斧，狠狠砍向%s！",
    "%s举起消防斧，用力劈向%s！",
    "%s抡起消防斧，重重地砸向%s！",
    "%s手持消防斧，对着%s猛砍下去！"
}

-- 消防斧的未命中消息
axe.miss_msg = {
    "%s挥出消防斧，却被%s灵巧地躲开了。",
    "%s的斧头砍空，砸在了%s旁的地上，溅起一片尘土。",
    "%s用力过猛，斧头擦着%s的耳边飞过。",
    "%s对%s的攻击落空，消防斧重重地砸在地面上！"
}

-- 消防斧的受击消息
axe.hurt_msg = {
    "%s被消防斧轻轻擦过，只是轻微划伤。",
    "%s被斧头砍中手臂，鲜血直流！",
    "%s被消防斧重重击中，发出一声惨叫！",
    "%s被斧头劈中，伤口深可见骨！",
    "%s被消防斧狠狠砍中要害，当场倒地！"
}

local born_point = Room.New({
    id = "BornPoint",
    title = "出生点",
    desc = "这里是一片空地，周围站着很多刚注册的新手玩家。",
    exits = {
        east = "NewbiePlaza",
        west = "SmallRoad"
    },
    spown_list = { admin, badge, axe }
})

-- 给新手广场房间添加一个疯狗
local mad_dog = Monster.New("mad_dog", "疯狗", "一个非常生气的狗")
mad_dog.max_hp = 20
mad_dog:set_hp(mad_dog.max_hp)

-- 疯狗的攻击命中消息
mad_dog.attack_msg = {
    "%s猛地扑向%s，狠狠咬住了对方的腿！",
    "%s狂吠着冲向%s，锋利的牙齿深深刺入手臂！",
    "%s凶猛地一跃，爪子狠狠抓向%s的脸！",
    "%s低吠着逼近%s，突然一口咬在脚踝上！"
}

-- 疯狗的未命中消息
mad_dog.miss_msg = {
    "%s扑向%s，却被灵巧地躲开了。",
    "%s狂吠着冲过来，却扑了个空，差点摔倒。",
    "%s张口就咬，但是%s及时后退避开。",
    "%s猛地跃起，却只差一点点就能碰到%s。"
}

-- 疯狗的受击消息
mad_dog.hurt_msg = {
    "%s发出一声呜咽，但看起来毫发无损。",
    "%s被击中，愤怒地咆哮着。",
    "%s惨叫一声，后退了几步。",
    "%s鲜血淋漓，却更加疯狂地扑来。",
    "%s发出一声凄厉的哀嚎，倒在了地上。"
}

mad_dog.listeners = {
    -- 监听死亡事件
    die = function(event_name, dead_char)
        -- 找到杀死怪物的攻击者（在fright_list中找活着的角色）
        local attacker = nil
        for _, enemy in ipairs(dead_char.fright_list) do
            if enemy:is_alive() then
                attacker = enemy
                break
            end
        end
        if attacker then
            log.DEBUG(string.format("%s 被 %s 击倒了", dead_char.name, attacker.name))
        else
            log.DEBUG(string.format("%s 死亡了", dead_char.name))
        end
    end
}

local newbie_plaza = Room.New({
    id = "NewbiePlaza",
    title = "新手广场",
    desc = "光秃秃的黄土地上，有几棵小树。",
    exits = {
        west = "BornPoint"
    },
    spown_list = { mad_dog }
})

-- 初始化小路房间
local small_road = Room.New({
    id = "SmallRoad",
    title = "小路",
    desc = "这条小路荒草蔓延。似乎是通往外界的唯一道路。",
    exits = {
        east = "BornPoint"
    },
    avg_cmds = {
        ---push
        ---@param this_player Player
        ---@param cmds string[]
        push = function(this_player, cmds)
            local obj = cmds[2]
            if not obj or obj == "" then
                return this_player:reply("你要推什么？")
            end
            if obj == "石头" then
                return this_player:reply("你推开了草丛中的石头。")
            end

            this_player:reply("你尝试推了下" .. obj .. "，但是没有反应。")
        end
    },
    avg_cmds_desc = {
        push = [[
  - 描述：推动目标物体
  - 命令格式：{"results":[{"func":"push","args":["目标"]}]}
  - 示例：输入“推石头” 输出“{"results":[{"func":"push","args":["石头"]}]}”
]]
    },
    -- 注册事件监听器（目标为当前房间 SmallRoad）
    listeners = {
        -- 监听 look 事件
        look = function(event_name, target_room, player, target_id)
            -- 当玩家在这个房间观察时触发
            if not target_id then -- 观察房间
                player:reply("你注意到路边有一块奇怪的石头。")
            end
            return true
        end,

        -- 监听 say 事件
        say = function(event_name, target_room, player, message)
            -- 当玩家在这个房间说话时触发
            if message == "阿里巴巴" then
                player:reply("墙上的石门缓缓打开了！")
                -- 可以在这里添加解谜逻辑
                target_room.exits["door"] = "NewbiePlaza"
                return false -- 阻止说话避免泄露密码
            end
            return true
        end,

        -- 监听 after_go 事件
        after_go = function(event_name, target_room, player, direction, target_id)
            -- 当玩家进入这个房间后触发
            player:reply("你踏入了这片神秘的土地...")
            return true
        end,

        perform = function(event_name, target, player, skill_name, skill_level)
            local roll = player:roll(1, 100)[1]
            if roll < player.skill[skill_name] then
                if skill_name == "侦查" then
                    player:reply("你发现了一个隐藏的门在石头后面。")
                    return true
                else
                    player:reply("你尝试了" .. skill_name .. "技能，但似乎完全不起作用。["..roll.."]")
                    return true
                end
            end

            -- 当玩家在这个房间使用 perform 命令时触发
            player:reply("你尝试了" .. skill_name .. "技能，但是失败了，什么都没有发生。["..roll.."]")
            return true
        end,

    }
})

return born_point.title .. "/"..small_road.title.."/"..newbie_plaza.title.." 加载完成"