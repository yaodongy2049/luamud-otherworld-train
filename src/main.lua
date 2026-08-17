--[[
LuaMudOS v0.1 by 1740168@qq.com
It's a simple MUD server for study LUA
]]

-- 设置全局配置
IS_LLM_ENABLED = false                            ---是否开启大模型服务
OLLAMA_HOST    = "http://127.0.0.1:11434"        ---ollama主机地址
LLM_MODEL      = "qwen2.5:7b-instruct-q3_K_M"    ---当前使用的大模型名称
EMB_MODEL      = "quentinz/bge-base-zh-v1.5"     ---当前使用的向量模型名称
MUD_LIB_PATH   = MUD_LIB_PATH or "./src/mud_lib/" ---MudLib的路径
PLAYER_CLASS   = "mud_lib/chars/investigator"     ---默认玩家类（调查员）
BORN_POINT     = "StationHall"                   ---出生点房间名称

-- 导入必要模块
local log      = require("mud_os/log")
local network  = require("mud_os/network")
local telnet   = require("mud_os/telnet")
local command  = require("mud_os/command")
local semantic = require("mud_os/semantic_match")
local cmds     = require("mud_lib/cmds")
local Room     = require("mud_lib/room")
local login    = require("mud_lib/login")

LUAMUD_VER_STR = log.COLORS.YELLOW .."LuaMud v0.4.0".. log.COLORS.RESET
GREETING_MSG   = {
  "",
  "'########:'########::::'########::'########:::'######:::",
  "##.....::... ##..::::: ##.... ##: ##.... ##:'##... ##::",
  "##:::::::::: ##::::::: ##:::: ##: ##:::: ##: ##:::..:::",
  "######:::::: ##::::::: ########:: ########:: ##::'####:",
  "##...::::::: ##::::::: ##.. ##::: ##.....::: ##::: ##::",
  "##:::::::::: ##::::::: ##::. ##:: ##:::::::: ##::: ##::",
  "########:::: ##::::::: ##:::. ##: ##::::::::. ######:::",
  "........:::::..::::::::..:::::..::..::::::::::......::::",
  "",
  "╔══════════════════════════════════╗",
  "║    最新剧本：《通往异世界的列车》    ║",
  "║      Powered by " .. LUAMUD_VER_STR .. "      ║",
  "╚══════════════════════════════════╝",
  "",
  "★ ★ ★",
  "╔════════════════╗",
  "║  汝已踏入...   ║",
  "║  不可名状之境  ║",
  "╚════════════════╝",
  "★ ★ ★",
  "",
  "[ LLM: " .. (IS_LLM_ENABLED and LLM_MODEL or "disabled") .. " ]",
  "",
  "※ 输入 help 查看指令列表 ※",
  "",
}

-- 设定日志等级
log.set_log_level(log.LogLevel.DEBUG)
log.INFO("MudLib is loading...")

-- 设置命令处理器
cmds.reload_cmds()
local handler = cmds.normal_handler
if IS_LLM_ENABLED then
  local llm_cmd = require("mud_lib/llm_cmd")
  handler = llm_cmd.llm_handler
end
command:set_command_handler(handler, login.greeting_fun, login.login_fun) -- 设置命令处理函数

-- 设置断开连接处理器
network.TcpServer.disconnect_handler = login.disconnect

-- 加载所有地图文件
Room:load_all_maps()

-- 预加载语义匹配模型
semantic.preload_base_emb()

-- 启动网络服务
log.INFO("Starting TCP server ...")
network.TcpServer:start({ host = "127.0.0.1", port = 7777 }, telnet, command:get_processor())
