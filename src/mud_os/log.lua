---@module "mud_os/log"
---@desc 日志系统模块，提供日志记录功能

-- ANSI 颜色代码
---@type table<string, string>
local COLORS = {
    RESET = "\27[0m",
    BLACK = "\27[30m",
    RED = "\27[31m",
    GREEN = "\27[32m",
    YELLOW = "\27[33m",
    BLUE = "\27[34m",
    MAGENTA = "\27[35m",
    CYAN = "\27[36m",
    LIGHT_BLUE = "\27[94m",  -- 浅蓝色
    LIGHT_CYAN = "\27[96m",  -- 浅青色
    GRAY = "\27[90m",        -- 灰色
}

---日志等级枚举
---@class LogLevel
---@field DEBUG number
---@field INFO number
---@field WARNING number
---@field ERROR number
local LogLevel = {
    DEBUG   = 1,
    INFO    = 2,
    WARNING = 3,
    ERROR   = 4,
}

---当前日志等级（默认为 INFO，低于此等级的日志不会输出）
---@type number
local current_level = LogLevel.INFO

---设置日志等级
---@param level number 日志等级（log.LogLevel.DEBUG/INFO/WARNING/ERROR）
local function set_log_level(level)
    current_level = level
end

---获取调用位置信息，返回文件路径、行号
---@param skip_frames number 跳过的调用栈帧数
---@return string, number 
local function get_caller_info(skip_frames)
    skip_frames = skip_frames or 3  -- 默认跳过3层（日志函数本身）
    local info = debug.getinfo(skip_frames, "Sl")
    
    if info then
        -- 提取文件名（只保留最后一部分）
        local filename = info.source:match("[^/\\]+$") or info.source
        -- 去除开头的@符号
        filename = filename:gsub("^@", "")
        return filename, info.currentline
    end
    
    return "unknown", 0
end

---获取当前时间戳，返回格式化的时间字符串（YYYY-MM-DD HH:MM:SS）
---@return string 
local function get_timestamp()
    local now = os.date("*t")
    return string.format("%04d-%02d-%02d %02d:%02d:%02d",
        now.year, now.month, now.day,
        now.hour, now.min, now.sec)
end

---格式化输出内容
---@param level string 日志等级标签
---@param ... any 要输出的内容
---@return string 
local function format_output(level, ...)
    local args = {...}
    local output = ""
    
    -- 获取调用位置
    local filename, line = get_caller_info(4)  -- 额外跳过format_output本身
    
    -- 构建日志头部
    local header = string.format("[%s] %s [%s:%d] ", 
        get_timestamp(), level, filename, line)
    
    -- 拼接输出内容
    for i, v in ipairs(args) do
        output = output .. tostring(v)
        if i < #args then
            output = output .. "\t"
        end
    end
    
    return header .. output
end

---输出 DEBUG 信息（灰色）
---@param ... any 要输出的内容
local function DEBUG(...)
    if current_level > LogLevel.DEBUG then
        return
    end
    print(COLORS.GRAY .. format_output("DEBUG", ...) .. COLORS.RESET)
end

---输出普通信息（浅蓝色）
---@param ... any 要输出的内容
local function INFO(...)
    if current_level > LogLevel.INFO then
        return
    end
    print(COLORS.LIGHT_BLUE .. format_output("INFO", ...) .. COLORS.RESET)
end

---输出警告信息（黄色）
---@param ... any 要输出的内容
local function WARNING(...)
    if current_level > LogLevel.WARNING then
        return
    end
    print(COLORS.YELLOW .. format_output("WARN", ...) .. COLORS.RESET)
end

---输出错误信息（红色）
---@param ... any 要输出的内容
local function ERROR(...)
    if current_level > LogLevel.ERROR then
        return
    end
    print(COLORS.RED .. format_output("ERROR", ...) .. COLORS.RESET)
end

return {
    COLORS = COLORS,
    LogLevel = LogLevel,
    DEBUG = DEBUG,
    INFO = INFO,
    WARNING = WARNING,
    ERROR = ERROR,
    set_log_level = set_log_level,
}