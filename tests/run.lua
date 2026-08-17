#!/usr/bin/env lua
--- 测试入口文件：自动发现并运行 tests/cases/ 目录下所有测试模块

package.path = package.path .. ";./src/?.lua;./src/?/init.lua;./tests/?.lua;./tests/?/init.lua"

-- 先加载测试框架（它会设置所有全局变量）
local TF = require("test_framework")

local lfs = nil
-- 尝试加载 luafilesystem 做目录扫描，如果没有则使用内置方法
local ok, lfs_mod = pcall(require, "lfs")
if ok then
    lfs = lfs_mod
end

print("=== LuaMUD 自动化测试 ===")
print()

TF.setup()
print("测试环境初始化完成")
print()

-- ========================================
-- 加载所有测试模块
-- ========================================
---测试模块列表，按顺序执行
local test_modules = {
    "cases.basic",           -- 基础功能测试
    "cases.state_street",    -- 州街/无名旧书店场景测试
    "cases.dark_compartment",-- 《常暗之厢》剧本测试
    -- 后续新场景在这里添加：
    -- "cases.customs_hall",
}

-- 使用ls命令作为备选目录扫描方案（当lfs不可用时）
local function scan_dir_with_ls(dir)
    local modules = {}
    local p = io.popen('ls -1 "' .. dir .. '" 2>/dev/null')
    if p then
        for file in p:lines() do
            if file:match("%.lua$") then
                local mod_name = "cases." .. file:gsub("%.lua$", "")
                table.insert(modules, mod_name)
            end
        end
        p:close()
    end
    return modules
end

-- 如果有 lfs，可以自动扫描目录，否则尝试ls命令，最后使用硬编码列表
local function auto_discover_tests()
    local cases_dir = "./tests/cases/"
    
    if lfs then
        local modules = {}
        for file in lfs.dir(cases_dir) do
            if file:match("%.lua$") then
                local mod_name = "cases." .. file:gsub("%.lua$", "")
                table.insert(modules, mod_name)
            end
        end
        if #modules > 0 then
            table.sort(modules)
            return modules
        end
    end
    
    -- 尝试使用ls命令扫描
    local ls_modules = scan_dir_with_ls(cases_dir)
    if #ls_modules > 0 then
        table.sort(ls_modules)
        return ls_modules
    end
    
    --  fallback到硬编码列表
    return test_modules
end

local modules_to_run = auto_discover_tests()
print(string.format("将运行 %d 个测试模块：", #modules_to_run))
for i, mod_name in ipairs(modules_to_run) do
    print(string.format("  %d. %s", i, mod_name))
end
print()

-- 执行所有测试模块
for _, mod_name in ipairs(modules_to_run) do
    print(string.format("---------- 加载测试模块: %s ----------", mod_name))
    local test_func = require(mod_name)
    if type(test_func) == "function" then
        test_func(TF)
    else
        print(string.format("[警告] 模块 %s 没有返回测试函数", mod_name))
    end
    print()
end

TF.print_summary()
TF.teardown()

os.exit(TF.fail_count == 0 and 0 or 1)