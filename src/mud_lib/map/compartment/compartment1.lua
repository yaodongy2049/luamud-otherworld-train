---@module "mud_lib/map/compartment1"
---@description COC跑团1号车厢场景（结局车厢）

local log = require("mud_os/log")
local Room = require("mud_lib/room")
local Item = require("mud_lib/item")

---@param this_player Investigator
local function trigger_true_ending(this_player, message)
    this_player:reply(message)
    this_player:reply([[奈亚的思绪一股脑的涌入你的脑海：
吾乃外神的心魂与使者，人虫的智识堪比吾之奇迹，奇行之物亦使真神苏醒。吾乘同吾之异形所似之物，但被此处之旧神追剿，借此人类科技之物进行躲避。
]])
    this_player.game_tags.is_touch_naiya = true
end

-- 创建控制台
local control_panel = Item.New(
    "control_panel",
    "控制台",
    "一个布满按钮和开关的控制台，看起来可以控制电车。",
    false
)
control_panel.is_unmov = true

-- 创建1号车厢房间
local compartment1 = Room.New({
    id = "Compartment1",
    title = "1号车厢",
    desc = "这是电车的最后一节车厢，前方是驾驶舱的门。车厢内一片死寂，空气中弥漫着一股非人的气息。角落里有一个应急控制台，上面布满了灰尘。",
    exits = {
        west = "Compartment2"
    },
    spown_list = { control_panel },
    avg_cmds = {
        ---@param this_player Investigator
        ---@param cmds string[]
        ---@description 操作控制台，尝试控制电车加速。
        ---如果成功，电车将加速，否则会短路并受伤。
        operate = function(this_player, cmds)
            local roll = math.random(1, 100)
            local difficulty = 60
            local sk = 0

            -- 乘务员专属：降低难度
            if this_player.exclusive == "乘务员身份" then
                difficulty = 30
            end

            local car_skill = this_player.skill["电车知识"] or 0
            local coc_skill = this_player.skill["克苏鲁神话"] or 0
            if (roll <= car_skill) 
            or (roll <= this_player.core_attrs.int + coc_skill +this_player.max_hp // 2 - this_player.hp // 2 - difficulty) then
                this_player:reply("你成功操作了控制台！")
                this_player:reply("电车开始加速，朝着终点驶去，然后停了下来，对外的车门自动打开了。")
                this_player.environment.exits.east = "TerminalStation"
            else
                this_player:reply("控制台短路了！火花四溅...")
                local dmg = math.random(1, 3)
                this_player:reply("你受伤到了" .. dmg .. "点伤害。但你还是想继续尝试控制电车。")
                this_player:modify_hp(-dmg)
            end
        end,
        touch = function(this_player, cmds)
            local target = cmds[2]
            if not target or target == "" then
                return this_player:reply("你要触碰谁？")
            end
            local this_place = this_player.environment --[[@as Room]]
            if not this_place or not this_place:has_obj("id", "mysterious_entity") then
                return this_player:reply("你无法触碰" .. target .. "。")
            end
            local mysterious_entity = this_place:search("id", "mysterious_entity")[1] --[[@as Npc]]

            -- 调整难度
            if this_player.game_tags.is_touch_naiya then
                this_player:reply("你已了解了真相，无需再触碰。")
                return 
            end
            local roll = math.random(1, 100)
            if this_player.exclusive == "记者身份" then
                -- 记者无需判定，直接触发真结局
                this_player:reply("你举起相机，对准了那团黑暗...")
                this_player:reply("闪光灯亮起的瞬间，你看到了它的真实形态...")
                trigger_true_ending(this_player, "【真结局】你记录下了真相，成为了新的见证者...奈亚也在你身上不起眼的地方留下了印记。")
                this_player:modify_san(-math.random(1, 3))
                return
            end

            if roll <= this_player.skill["话术"] then
                this_player:reply("你与那团黑暗交流...")
                mysterious_entity:say("「一切终将回归黑暗...但你...可以选择...」")
                trigger_true_ending(this_player, "【真结局】你理解了真相，获得了新生...奈亚也在你身上不起眼的地方留下了印记。")
            else
                this_player:reply("你伸出手，触碰那团黑暗...")
                this_player:reply("一股寒意席卷全身...这次接触并没让你理解真相。你要再来一次吗？")
                this_player:modify_san(-math.random(1, 6))
            end
        end,
    },
    avg_cmds_desc = {
        operate = "operate：操作控制台。",
        touch = "touch：触碰，args=[目标(可选)]",
    },
    listeners = {
        after_go = function(event_name, room, player)
            if room:has_obj("id", "mysterious_entity") then
                return
            end
            player:reply("你来到了电车的最后一节车厢...")
            player:reply("驾驶舱的门就在前方，但它是锁着的。")
            player:reply("应急控制台看起来可以尝试操作(operate)一下。")
        end,
        -- 监听返回2号车厢的尝试（回头）
        before_go = function(event_name, room, player, direction, target_id)
            if direction == "west" then
                player:reply("空间开始扭曲...你无法回头！")
                player:modify_san(-math.random(1, 6))
                player:modify_hp(-5)
                player:reply("你被强制留在了1号车厢！")
                return false -- 阻止移动
            end
            if direction == "east" and room.exits["east"] then
                player:reply("你逃离了电车，但这段记忆永远留在了你的脑海中...")
                room.exits.east = nil
            end
            return true
        end
    }
})

return compartment1.title .. " 加载完成"