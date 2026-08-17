# luamud
A MudOS and MudLib sample written by LUA

详细说明请参考 [项目 Wiki](https://gitee.com/wadehan/luamud/wikis/)

## 项目简介
luamud 是一个用 Lua 语言编写的 MUD（多用户地牢）游戏服务器框架，提供完整的游戏服务端实现，包括网络通信、命令系统、事件系统、角色系统等核心功能。

## 安装运行
### 基础依赖
- 推荐试用 Debian Linux，本项目开发环境是 Windows 11 + WSL2 + Debian，以下安装命令都是 Debian 系统下的安装命令
- 使用 Lua 5.4 版本开发：`sudo apt install lua5.4 lua-cjson lua-socket`

### 启动服务
- 运行 `sh/start.sh` 启动服务器

### 运行自动化测试
- 运行 `sh/test.sh` 执行自动化测试（无需启动TCP服务器，直接模拟客户端连接）

### 大模型服务（可选）
- 本地大模型服务 Ollama：`curl -fsSL https://ollama.com/install.sh | sh` （不翻墙会比较慢）
- 安装模型：`ollama pull qwen2.5:3b` （可以考虑试用国内镜像拉取）
- 修改 `src/main.lua` 中的全局变量配置：
  - 修改 `IS_LLM_ENABLED` 为 `true` 启用大模型功能
  - 修改 `LLM_MODEL` 为模型的名字，如上面的 `qwen2.5:3b`

### 试用 Web 客户端
- 安装 [github mud-web-proxy](https://github.com/maldorne/mud-web-proxy) 启动：`WS_PORT=8888 DEFAULT_HOST=localhost DEFAULT_PORT=7777 DEFAULT_ENCODING=utf8 DEBUG=true LOG_LEVEL=debug npm start`
- 安装 [github mud-web-client](https://github.com/maldorne/mud-web-client) 启动：`npm run dev -- --host`。打开浏览器，输入 `http://localhost:5173/?proxy=ws://localhost:8888&host=localhost&port=7777&debug=1` 即可连接服务器

## 功能特性

### 一、MudOS 框架层

MudOS 是游戏服务器的核心框架，提供底层基础设施支持：

#### 1. 网络通信
- **TCP 服务器**：基于 LuaSocket 实现的非阻塞 TCP 服务器
- **Telnet 协议**：支持 Telnet 协议标准（ECHO、SUPPRESS_GO_AHEAD、NAWS 等）
- **GMCP 协议**：支持 GMCP（Generic Mud Communication Protocol）扩展协议
- **协程管理**：内置协程池，支持异步任务调度
- **频道管理**：提供频道的创建、加入、退出、广播消息等功能

#### 2. 事件系统
- **事件触发**：支持自定义事件的触发和监听
- **目标过滤**：支持按目标对象过滤事件回调
- **事件链**：支持事件的链式处理和优先级控制

#### 3. 日志系统
- **多级别日志**：DEBUG、INFO、WARNING、ERROR 四个级别
- **彩色输出**：支持 ANSI 颜色代码，终端彩色显示
- **调用追踪**：自动记录日志调用的文件名和行号
- **时间戳**：每条日志包含精确时间戳

#### 4. 定时器系统
- **定时任务**：支持定时执行任务，如保存数据、更新状态等
- **时间戳**：提供精确的时间戳，用于事件触发和日志记录

#### 5. 数据持久化
- **Lua 格式保存**：支持将对象序列化为 Lua 脚本
- **临时环境加载**：加载时使用临时环境，避免全局污染
- **自动保存**：支持定时自动保存玩家数据

#### 6. 类系统
- **DefineClass**：现代化的类定义方式
- **继承支持**：支持单继承，自动处理原型链
- **类冻结**：定义后禁止修改类字段（除 New 方法）
- **深拷贝克隆**：支持对象的深拷贝克隆

#### 7. 大模型集成（LLM）
- **大模型解析**：支持通过大模型解析自然语言，支持以 JSON 格式返回结果，降低错乱字符串解析风险
- **非阻塞处理**：通过异步请求 ollama 模型，避免阻塞主线程

---

### 二、MudLib 逻辑层

MudLib 是游戏逻辑层，提供游戏世界的核心概念和玩法：

#### 1. 空间系统
- **SpaceObject**：空间对象基类，支持位置管理
- **容器机制**：支持对象的添加、移除、搜索
- **层级结构**：支持嵌套空间（背包、房间、世界）

#### 2. 房间系统
- **Room 类**：房间定义，包含标题、描述、出口
- **自动加载**：启动时自动加载 Map 目录下的房间脚本
- **临时命令**：房间级别的临时动作命令
- **事件监听**：支持注册房间事件回调

#### 3. 角色系统
- **Charactor**：角色基类，包含生命值、魔法值
- **Player**：玩家类，继承自角色，包含用户数据
- **Npc**：NPC 类，继承自角色，支持对话话题
- **对话系统**：支持话题查询、事件触发

#### 4. 物品系统
- **Item 类**：物品定义，支持堆叠、描述
- **可堆叠**：支持相同物品的数量叠加
- **放入容器**：支持放入背包、房间等空间

#### 5. 战斗系统
- **Combat 函数**：战斗逻辑处理
- **技能系统**：支持技能攻击
- **伤害计算**：基于属性的伤害公式

#### 6. 命令系统
- **命令解析**：支持命令行解析、参数提取、命令分发
- **命令注册**：动态命令注册机制，支持运行时加载
- **临时命令**：支持房间级别的临时命令注册
- **大模型支持**：支持通过大模型解析自然语言命令
- **登录注册**：支持玩家登录注册，包含用户名、密码

---

### 三、技术亮点

| 特性           | 说明                                  |
| -------------- | ------------------------------------- |
| **非阻塞 IO**  | 基于 socket.select 实现的事件驱动模型 |
| **协程异步**   | 支持异步任务而不阻塞主线程            |
| **模块化设计** | 清晰的框架层和逻辑层分离              |
| **热更新支持** | 命令可运行时重新加载                  |
| **类型安全**   | 完整的 EmmyLua 类型注解               |

## 项目结构
```
luamud/
├── docs/                             # 文档目录
│   ├── coc_charactor.md              # COC 角色系统说明
│   ├── dark_compartment.md           # 黑暗车厢场景文档
│   └── job_office.md                 # 职业办公室场景文档
├── sh/                               # 运行脚本
│   ├── start.sh                      # 启动服务器
│   ├── test.sh                       # 运行自动化测试
│   ├── dev.sh                        # 开发调试脚本
│   ├── cr_agent.sh                   # 角色代理脚本
│   └── latency.py                    # 延迟测试工具
├── src/                              # 源代码目录
│   ├── main.lua                      # 应用入口，启动服务器（含全局配置）
│   ├── client.lua                    # 简易客户端
│   ├── mud_os/                        # 【框架层】游戏引擎核心
│   │   ├── network.lua               # TCP 服务器，管理网络连接
│   │   ├── telnet.lua                # Telnet 协议处理（ECHO、GMCP 等）
│   │   ├── command.lua               # 命令系统核心，解析和分发
│   │   ├── channel.lua               # 频道管理，支持消息广播
│   │   ├── event_system.lua          # 事件系统，支持发布订阅
│   │   ├── timer.lua                 # 定时器系统，定时任务调度
│   │   ├── log.lua                   # 彩色日志输出
│   │   ├── md5.lua                   # MD5 加密函数
│   │   ├── storage.lua               # 数据持久化，保存/加载玩家数据
│   │   ├── serialize.lua             # 对象序列化，支持 Lua 格式输出
│   │   ├── class.lua                 # 类系统，DefineClass/Clone 等
│   │   ├── misc.lua                  # 工具函数集合
│   │   ├── llm_input.lua             # 大模型交互，调用 Ollama 服务
│   │   ├── semantic_match.lua        # 语义匹配模块，支持命令模糊匹配
│   │   └── waiting_animation.lua     # 等待动画效果
│   └── mud_lib/                       # 【逻辑层】游戏世界内容
│       ├── cmds.lua                  # 命令系统入口，加载所有命令
│       ├── room.lua                  # 房间类，管理房间属性和行为
│       ├── space.lua                 # 空间对象基类，支持容器管理
│       ├── char.lua                  # 角色基类，包含生命/魔法属性
│       ├── player.lua                # 玩家类，继承自 Charactor
│       ├── npc.lua                   # NPC 类，支持对话话题系统
│       ├── monster.lua               # 怪物类
│       ├── item.lua                  # 物品类，支持可堆叠
│       ├── weapon.lua                # 武器类
│       ├── combat.lua                # 战斗系统，处理攻击和技能
│       ├── login.lua                 # 登录注册逻辑
│       ├── llm_cmd.lua               # 大模型命令解析
│       ├── invoke_llm.lua            # LLM 调用封装
│       ├── cmd.modelfile             # 命令解析模型配置
│       ├── coc/                      # COC（克苏鲁的呼唤）规则系统
│       │   ├── attrs.lua             # 属性定义（力量/体质/敏捷等）
│       │   ├── jobs.lua              # 职业定义（调查员/医生/学者等）
│       │   └── skills.lua            # 技能定义（侦查/聆听/神秘学等）
│       ├── cmd/                      # 命令实现目录
│       │   ├── common.lua            # 通用命令（help/bye/look/go/who）
│       │   ├── say.lua               # 说话命令（含对话系统）
│       │   ├── hp.lua                # 状态查看命令
│       │   ├── get.lua               # 获取/丢弃/背包命令（get/drop/inv）
│       │   ├── use.lua               # 使用/穿戴命令（use/wear/unwear）
│       │   ├── kill.lua              # 攻击命令
│       │   ├── perform.lua           # 技能执行命令
│       │   └── gm.lua                # GM 管理命令（fly/dofile/loadcmd/clone）
│       ├── chars/                    # 角色模板目录
│       │   └── investigator.lua      # 调查员角色（默认玩家类）
│       ├── npcs/                     # NPC 模板目录
│       │   ├── arthur_cohen.lua      # 亚瑟·科恩 NPC
│       │   ├── ella_hayes.lua        # 艾拉·海斯 NPC
│       │   └── jimmy_barlow.lua      # 吉米·巴洛 NPC
│       ├── map/                      # 地图脚本目录
│       │   ├── customs_hall.lua      # 海关大厅
│       │   ├── state_street.lua      # 州街与无名旧书店
│       │   └── compartment/           # 车厢场景目录
│       │       ├── station_hall.lua  # 车站大厅（出生点）
│       │       ├── station_end.lua   # 车站终点
│       │       ├── compartment1.lua  # 1号车厢
│       │       ├── compartment2.lua  # 2号车厢
│       │       ├── compartment3.lua  # 3号车厢
│       │       ├── compartment4.lua  # 4号车厢
│       │       ├── compartment5.lua  # 5号车厢
│       │       ├── compartment6.lua  # 6号车厢
│       │       └── compartment7.lua  # 7号车厢
│       ├── item/                     # 物品模板目录
│       │   ├── book_of_green_god.lua # 《绿神》禁忌典籍
│       │   └── conductor_key.lua     # 列车长钥匙
│       └── legacy/                   # 遗留代码目录
│           ├── base.lua              # 旧版基础代码
│           ├── combat.lua            # 旧版战斗系统
│           └── skill.lua             # 旧版技能系统
├── tests/                            # 自动化测试目录
│   ├── test_framework.lua            # 测试框架（网络Mock、输出捕获、断言）
│   ├── run.lua                       # 测试用例入口
│   ├── run.sh                        # 测试运行脚本
│   └── test_basic.lua                # 结构化测试示例
└── LICENSE                           # 许可证文件
```



## 游戏命令

### 基础命令

| 命令     | 格式                  | 说明                              |
| -------- | --------------------- | --------------------------------- |
| help     | help [命令]           | 显示帮助信息，可查询特定命令用法  |
| bye      | bye                   | 退出游戏                          |
| look     | look [目标]           | 观察当前环境或指定目标            |
| hp       | hp                    | 查看当前状态（HP/MP/SAN/属性/技能）|
| go       | go <方向>             | 向指定方向移动（东/南/西/北等）    |
| who      | who                   | 查看当前在线玩家列表，显示名字、ID、状态、登录时长 |

### 社交命令

| 命令     | 格式                  | 说明                              |
| -------- | --------------------- | --------------------------------- |
| say      | say <内容> [目标]     | 在当前房间说话，可指定对话目标    |
|          | say <内容> <目标>     | 对特定目标说某事，进入对话模式    |

### 物品命令

| 命令     | 格式                  | 说明                              |
| -------- | --------------------- | --------------------------------- |
| get      | get <物品> [容器]     | 获取物品到背包，可从容器中获取    |
| drop     | drop <物品>           | 丢弃物品到当前房间                |
| inv      | inv                   | 查看背包中的物品                  |
| use      | use <物品> [目标]     | 使用物品，可指定使用目标          |
| wear     | wear <物品>           | 穿戴装备到对应位置                |
| unwear   | unwear <物品>         | 脱下已穿戴的装备                  |

### 战斗命令

| 命令     | 格式                  | 说明                              |
| -------- | --------------------- | --------------------------------- |
| kill     | kill <目标>           | 攻击指定目标                      |
| perform  | perform <技能> [目标] | 执行技能，可指定目标              |

### GM 命令

| 命令     | 格式                  | 说明                              |
| -------- | --------------------- | --------------------------------- |
| fly      | fly <房间ID>          | 瞬间传送到指定房间                |
| dofile   | dofile <文件路径>     | 加载并执行指定 Lua 文件           |
| loadcmd  | loadcmd <命令名>      | 热重载指定命令文件                |
| clone    | clone <物品名>        | 克隆物品到背包                    |
| dev      | dev                  | 进入 Lua 命令执行模式             |

### 命令示例
```bash
# 观察当前房间
> look
【车站大厅】
这是一座老式车站的候车大厅，弥漫着陈旧的木质气息。
出口：
east 通往 海关大厅
north 通往 1号车厢

# 查看自身状态
> hp
调查员 - 张三
核心属性：
力量: 12    体质: 14    体型: 15
敏捷: 13    外貌: 11    智力: 16
意志: 14    教育: 18    幸运: 50
信用: 0     移动: 8

技能：
【核心生存/侦查技能】
侦查: 70    聆听: 60    潜行: 50

状态：
HP:【12/12】        MP:【0/0】        SAN:【100】

# 与 NPC 对话
> say 你好 亚瑟
你对亚瑟·科恩说道："你好"
亚瑟·科恩对你说道：欢迎来到这辆神秘的列车，我是这里的列车长。

# 继续对话（对话模式下直接输入内容）
亚瑟·科恩：❯ 这趟车要去哪里？
亚瑟·科恩对你说道：这趟车开往未知的彼岸，只有命运才能决定终点。

# 结束对话
亚瑟·科恩：❯ 告辞
你结束了对话。

# 获取物品
> get 车票
你捡起了车票

# 查看背包
> inv
你背包里的物品：
 * ⌈车票⌋[ticket]

# 使用物品
> use 车票
你出示了车票，检票员点了点头。

# 移动
> go east
你来到了海关大厅。

# 战斗
> kill 怪物
你对着怪物大喝一声："納命来！"
怪物对你一瞪眼，一跺脚，狠狠道："竟敢在太岁头上动土？"

# GM 命令（管理员使用）
> fly station_hall
一阵烟雾腾起，你往station_hall方向飞去。

> loadcmd say
重载: say，结果：true
```

## 开发指南

### 项目架构概述

luamud 采用分层架构设计，分为 **MudOS（框架层）** 和 **MudLib（逻辑层）**：

- **MudOS**：提供底层基础设施，包括网络通信、命令解析、事件系统、定时器、日志、类系统等核心功能。
- **MudLib**：实现游戏逻辑，包括房间系统、角色系统、物品系统、战斗系统、命令实现等。

### 添加新命令

命令文件位于 `src/mud_lib/cmd/` 目录下，每个文件实现一组相关命令。

#### 命令注册方式
```lua
local cmd_sys = require("mud_lib/cmds")

-- 注册命令描述（用于 help 命令显示）
cmd_sys.command_desc_list.your_cmd = "your_cmd：命令描述，args=[参数说明]"

-- 注册命令处理函数
cmd_sys.command_list.your_cmd = function(this_player, cmds)
    -- cmds[1] 是命令名，cmds[2] 开始是参数
    local arg1 = cmds[2]
    if not arg1 then
        this_player:reply("缺少参数")
        return
    end
    -- 执行命令逻辑
    this_player:reply(string.format("执行命令：%s，参数：%s", cmds[1], arg1))
end
```

#### GM 命令注册
```lua
cmd_sys.gm_command_desc_list.gm_cmd = "gm_cmd：GM命令描述"
cmd_sys.gm_command_list.gm_cmd = function(this_player, cmds)
    -- GM 命令逻辑
end
```

#### 命令热重载
使用 `loadcmd <命令名>` 可以在运行时重新加载命令文件，无需重启服务器。

### 创建房间

房间文件位于 `src/mud_lib/map/` 目录下，使用 `Room:New()` 创建房间实例。

#### 房间定义示例
```lua
local Room = require("mud_lib/room")

Room:New({
    id = "my_room",           -- 房间唯一标识
    title = "我的房间",        -- 房间标题
    desc = "这是一个自定义房间。", -- 房间描述
    exits = {                 -- 出口配置
        east = "station_hall",  -- 东 -> 车站大厅
        south = "compartment1", -- 南 -> 1号车厢
    },
    spown_list = {},          -- 房间内生成的物体列表
    listeners = {},           -- 事件监听器
    avg_cmds = {},            -- 临时命令
})
```

#### 房间属性说明
| 属性 | 类型 | 说明 |
|------|------|------|
| `id` | string | 房间唯一标识，用于出口引用和 `fly` 命令 |
| `title` | string | 房间标题，显示在 `look` 命令结果中 |
| `desc` | string | 房间详细描述 |
| `exits` | table | 出口配置，键为方向（east/west/south/north/up/down），值为目标房间ID |
| `spown_list` | table | 房间初始化时自动生成的物体列表 |
| `listeners` | table | 事件监听器，注册房间级事件回调 |
| `avg_cmds` | table | 临时命令，仅在当前房间可用 |
| `avg_cmds_desc` | table | 临时命令描述，用于 LLM 解析 |

### 创建物品

物品通过 `Item:New()` 创建，支持可堆叠和不可堆叠两种类型。

#### 物品创建示例
```lua
local Item = require("mud_lib/item")

-- 创建不可堆叠物品
local key = Item:New("gold_key", "金钥匙", "一把闪闪发光的金钥匙", false)
key.use = function(this_player, target)
    this_player:reply("你用金钥匙打开了锁。")
end

-- 创建可堆叠物品
local coin = Item:New("gold_coin", "金币", "一枚金色的硬币", true)

-- 创建可穿戴物品
local sword = Item:New("iron_sword", "铁剑", "一把普通的铁剑", false)
sword.wear_pos = "weapon"  -- 穿戴位置：weapon/armor/helmet等
```

#### 物品属性说明
| 属性 | 类型 | 说明 |
|------|------|------|
| `id` | string | 物品唯一标识 |
| `name` | string | 物品名称 |
| `desc` | string | 物品描述 |
| `is_stackable` | boolean | 是否可堆叠 |
| `count` | number | 堆叠数量（仅可堆叠物品） |
| `wear_pos` | string | 穿戴位置，空字符串表示不可穿戴 |
| `is_unmov` | boolean | 是否不可移动 |
| `custom` | table | 自定义属性（仅不可堆叠物品） |

### 创建 NPC

NPC 通过 `Npc:New()` 创建，支持对话话题系统。

#### NPC 创建示例
```lua
local Npc = require("mud_lib/npc")

local guide = Npc:New("guide_npc", "向导", "一位穿着制服的向导，看起来很友善。")
guide.topics = {
    ["任务"] = "你可以去东边的海关大厅接取任务。",
    ["列车"] = "这趟列车开往未知的彼岸，只有命运才能决定终点。",
    ["帮助"] = "你可以使用 look 查看周围，go 移动，say 说话。",
}

-- 将 NPC 添加到房间的 spown_list
Room:New({
    id = "station_hall",
    spown_list = { guide },
})
```

#### NPC 属性说明
| 属性 | 类型 | 说明 |
|------|------|------|
| `id` | string | NPC 唯一标识 |
| `name` | string | NPC 名称 |
| `desc` | string | NPC 描述 |
| `topics` | table | 对话话题表，键为话题名称，值为回复内容 |
| `is_invulnerable` | boolean | 是否无敌（默认 true，无法被攻击） |

### 事件系统

事件系统基于发布/订阅模式，支持全局事件和房间级事件。

#### 支持的事件列表
| 事件名 | 触发时机 | 参数 |
|--------|----------|------|
| `say` | 玩家说话时 | `(room, player, msg)` |
| `ask_about` | 玩家与 NPC 对话时 | `(npc, player, topic, content)` |
| `look` | 玩家使用 look 命令时 | `(target, player, target_id)` |
| `before_go` | 玩家移动前 | `(room, player, direction, room_id)` |
| `after_go` | 玩家移动后 | `(new_room, player, direction, room_id)` |
| `perform` | 玩家使用技能时 | `(target, player, skill_name, skill_level)` |

#### 注册事件监听器
```lua
Room:New({
    id = "mystery_room",
    listeners = {
        -- 监听 say 事件
        say = function(room, player, msg)
            if msg == "hello" then
                player:reply("房间中传来一阵回声：Hello...")
                return "房间回应了你的问候" -- 返回字符串会替换玩家说的话
            end
        end,
        -- 监听 before_go 事件，可阻止移动
        before_go = function(room, player, direction)
            if direction == "east" then
                player:reply("东边的门被锁住了。")
                return false -- 返回 false 阻止移动
            end
        end,
    },
})
```

### 添加临时命令

临时命令（avg_cmds）是房间级别的命令，仅在当前房间内可用。

#### 临时命令示例
```lua
Room:New({
    id = "puzzle_room",
    avg_cmds = {
        search = function(this_player, cmds)
            this_player:reply("你仔细搜索了房间，发现了一个隐藏的开关。")
            -- 触发事件或修改游戏状态
        end,
        push = function(this_player, cmds)
            local target = cmds[2]
            if target == "开关" then
                this_player:reply("你按下了开关，墙上出现了一道暗门。")
            else
                this_player:reply("你推了推空气，什么也没发生。")
            end
        end,
    },
    avg_cmds_desc = {
        search = "search：搜索房间，寻找隐藏物品",
        push = "push：推动物体，如 push 开关",
    },
})
```

### COC 角色系统

项目内置了 COC（克苏鲁的呼唤）TRPG 角色系统，支持属性、技能、职业等机制。

#### COC 核心属性
| 属性 | 说明 |
|------|------|
| STR（力量） | 影响近战伤害和负重 |
| CON（体质） | 影响生命值上限 |
| SIZ（体型） | 影响生命值和伤害 |
| DEX（敏捷） | 影响闪避和行动速度 |
| APP（外貌） | 影响社交技能 |
| INT（智力） | 影响知识技能 |
| POW（意志） | 影响魔法和抵抗 |
| EDU（教育） | 影响学术技能 |
| LUK（幸运） | 影响运气判定 |

#### 技能分类
- 核心生存/侦查技能：侦查、聆听、潜行、追踪、闪避
- 社交/交涉技能：话术、说服、恐吓、取悦、心理学
- 知识/学术技能：图书馆使用、历史、神秘学、博物学等
- 医疗/精神技能：急救、医学、精神分析等
- 战斗/武器技能：斗殴、手枪、步枪、近战武器等
- 技术/手工技能：锁匠、机械维修、电气维修等
- 艺术/表演技能：艺术(文学)、艺术(摄影)等
- 特殊技能：克苏鲁神话

### LLM 集成

项目支持通过 Ollama 集成大语言模型，实现自然语言命令解析和 NPC 对话生成。

#### 启用 LLM
修改 `src/main.lua` 中的全局配置：
```lua
IS_LLM_ENABLED = true    -- 启用 LLM 功能
LLM_MODEL = "qwen2.5:3b" -- 指定模型名称
```

#### LLM 功能
- **自然语言命令解析**：玩家可以用自然语言输入命令，LLM 将其转换为系统命令
- **NPC 智能对话**：支持 NPC 根据人设和话题生成自然回复
- **语义匹配**：支持话题、出口的模糊匹配

### 调试工具

#### 自动化测试框架
项目内置了无需 TCP 网络连接的自动化测试框架，可以直接模拟客户端连接、输入命令、验证输出。

**运行测试：**
```bash
# 方式1：在项目根目录
bash tests/run.sh

# 方式2：在sh目录
bash sh/test.sh
```

**测试框架特性：**
- 无需启动 TCP 服务器，直接 Mock 网络层
- 模拟真实客户端连接（顺序递增ID，和真实TCP行为一致）
- 捕获服务器输出，自动清洗ANSI颜色码和Telnet协议字节
- 定时器驱动：可触发延迟事件（如登录欢迎消息）
- 测试隔离：每个测试间自动清理玩家状态、房间内容、频道消息
- 断言函数：支持输出包含、正则匹配等验证方式
- 独立测试数据目录，不影响正式玩家存档

**编写测试用例示例：**
```lua
local TF = require("tests/test_framework")

TF.setup()

-- 测试who命令
TF.run_test("who命令-单个用户", function()
    local c = TF.register_user("testuser")  -- 注册并自动登录
    TF.send(c, "who")
    TF.assert_output_contains(c, "在线玩家", "应显示在线玩家列表标题")
    TF.assert_output_contains(c, "testuser", "应看到自己的名字")
    TF.assert_output_contains(c, "1 位玩家在线", "应显示在线人数1")
end)

TF.print_summary()
TF.teardown()
os.exit(TF.fail_count == 0 and 0 or 1)
```

**核心API：**
| API | 说明 |
|-----|------|
| `TF.connect()` | 创建新连接，返回TestClient对象 |
| `TF.register_user(name)` | 快捷注册新用户并自动登录，返回客户端 |
| `TF.send(client, cmd)` | 向客户端发送命令 |
| `TF.assert_output_contains(client, str, desc)` | 断言客户端输出包含指定字符串 |
| `TF.drain_pending_timers()` | 推进定时器，触发所有延迟事件 |

#### 开发调试脚本
运行 `sh/dev.sh` 可以调试具体的 Lua 代码文件。

#### GM 命令
- `fly <房间ID>`：瞬间传送到指定房间
- `dofile <文件路径>`：加载并执行 Lua 文件
- `loadcmd <命令名>`：热重载命令文件
- `clone <物品名>`：克隆物品到背包

#### 日志系统
日志分为四个级别：DEBUG、INFO、WARNING、ERROR，支持彩色输出和调用追踪。

### 文件加载机制

项目使用 `misc.save_do_file()` 安全加载 Lua 文件，避免全局变量污染。命令文件在启动时自动加载 `src/mud_lib/cmd/` 目录下的所有 `.lua` 文件。

## 许可证
MIT License

## 作者
1740168@qq.com