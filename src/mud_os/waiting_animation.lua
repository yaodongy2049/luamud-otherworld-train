---@module "mud_os/waiting_animation"
---@description 等待动画模块

local timer = require("mud_os/timer")
local network = require("mud_os/network")

local WaitingAnimation = {}

---创建等待动画
---@param user_id string 用户ID
---@param chars table? 动画字符数组
---@param interval number? 动画间隔（秒），默认为 0.2
---@return fun() #停止动画的函数
function WaitingAnimation.start(user_id, chars, interval)
    local spin_idx = 1
    local spin_chars = chars or {"⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"}
    local timer_interval = interval or 0.2
    local timer_idx = nil

    timer_idx = timer:add(function()
        spin_idx = spin_idx % #spin_chars + 1
        network.TcpServer:send_to(user_id, "\x1b[K\r\0 💭 "..spin_chars[spin_idx].." ", true)
        return nil
    end, timer_interval)

    return function()
        if timer_idx then
            timer:del(timer_idx)
            timer_idx = nil
        end
        network.TcpServer:send_to(user_id, "\x1b[K\r\0", true)
    end
end

return WaitingAnimation