---@module "mud_lib/map/customs_hall"
---@description COC跑团海关大厅场景（角色创建）

local log = require("mud_os/log")
local Room = require("mud_lib/room")

-- 导入COC系统模块
local COC = require("mud_lib/coc/attrs")

-- 导入NPC
local ella_hayes = require("mud_lib/npcs/ella_hayes")
local arthur_cohen = require("mud_lib/npcs/arthur_cohen")
local jimmy_barlow = require("mud_lib/npcs/jimmy_barlow")

local PlayerState = COC.PlayerState

-- 创建海关大厅房间
local customs_hall = Room.New({
    id = "CustomsHall",
    title = "联合海关大厅",
    desc =
    "大厅层高开阔，老旧石膏天花板泛黄开裂，雕花角落结满蛛网。两侧拱形落地窗积满灰尘与海雾，惨白日光被污垢阻隔，只能洒下零散、昏暗的光斑。窗边悬挂的星条旗褪色发皱，被穿堂而过的海风无精打采地吹动。空气中混杂着咸涩刺骨的远洋海风、廉价烟草与汗臭、劣质皮鞋皮革的腥气，还夹杂着海关办公油墨、消毒药水以及一丝若有若无的酒精气息。空间被老旧的橡木围栏天然分割为两大区域——东侧的入境登记区和西侧的职业介绍区。",
    exits = {
        west = "JobOffice",
        south = "StateStreet"
    },
    spown_list = { ella_hayes, arthur_cohen },
    listeners = {
        after_go = function(event_name, target_room, player, direction, target_id)
            if not player.game_tags.customs_state or player.game_tags.customs_state == PlayerState.IDLE then
                player:reply("艾拉·海耶斯抬眼看向你，语气平淡：'站住，到这边的柜台排队登记。所有人入境都必须填报身份信息、写明停留目的，这是港口海关的硬性规定。'")
                player:reply("【提示】你可以向亚瑟·科恩（海关登记员）发起 '登记' 话题开始办理入境手续。")
            end
            return true
        end
    }
})

-- 创建职业介绍区房间
local job_office = Room.New({
    id = "JobOffice",
    title = "职业介绍区",
    desc = "这是大厅西侧的职业介绍区，空间相对拥挤杂乱。几张破旧的木桌摆放在角落里，墙上贴着各种招工告示，空气中弥漫着廉价烟草和汗水的味道。吉米·巴洛坐在最里面的桌子后面，面前堆满了招工名册。",
    exits = {
        east = "CustomsHall"
    },
    spown_list = { jimmy_barlow },
    listeners = {
        after_go = function(event_name, target_room, player, direction, target_id)
            if target_room.id == "JobOffice" then
                -- 检查是否完成登记
                if not player.game_tags.customs_state or
                    player.game_tags.customs_state < PlayerState.REGISTER_COMPLETED then
                    player:reply("吉米看到你进来，撇了撇嘴：'还没登记就想来找工作？先去东边柜台登记完再说。'")
                    player:fly_to("CustomsHall", "你被人群拥挤着推回了联合海关大厅。")
                    return false
                end

                if player.game_tags.customs_state == PlayerState.REGISTER_COMPLETED then
                    player:reply("吉米抬头看了你一眼：'登记完了？过来聊聊，看看有什么适合你的工作。'")
                    player:reply("【提示】你可以向吉米·巴洛发起 '介绍工作' 话题。")
                elseif player.game_tags.customs_state >= PlayerState.JOB_SELECT then
                    player:reply("你回到了职业介绍区。")
                end
            end
            return true
        end
    }
})

return customs_hall.title .. "/" .. job_office.title .. " 加载完成"