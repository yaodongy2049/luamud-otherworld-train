# 《通往异世界的列车》 / LuaMUD Otherworld Train

> **这是一个基于 [wadehan/luamud](https://gitee.com/wadehan/luamud) 的修改版与体验扩展，不是上游作者的官方 GitHub 镜像，也不代表上游作者认可、维护或支持本仓库。**

这是一个中文、浏览器可玩的 COC 风格文字 MUD 实验项目。它保留 LuaMUD 的 Lua 服务端、Telnet/事件/角色/物品系统，并在此基础上把原有教学剧本扩展为 **《通往异世界的列车》**：玩家从车站登记开始，在列车、州街和无名旧书店中完成调查、对话、技能检定、战斗/逃跑、存档和案件追踪。

## 上游项目与许可证

本项目最初版本来自：

- **作者：** `wadehan`
- **上游仓库：** <https://gitee.com/wadehan/luamud>
- **开发日志：** <https://gitee.com/wadehan/luamud/wikis/%E5%BC%80%E5%8F%91%E6%97%A5%E5%BF%97>
- **许可证：** MIT License，`Copyright (c) 2026 wadehan`

上游使用 MIT License；本仓库完整保留原始 `LICENSE` 与版权声明。详细归属与 GitHub 核验见 [UPSTREAM_ATTRIBUTION.md](UPSTREAM_ATTRIBUTION.md) 和 [docs/UPSTREAM_VERIFICATION.md](docs/UPSTREAM_VERIFICATION.md)。

## 本修改版做了什么？

| 领域 | 当前改动 |
|---|---|
| 剧本与命名 | 将教学剧本呈现为《通往异世界的列车》；将书店入口命名为《暴风之眼》，同时兼容旧剧情标记。 |
| 新手体验 | 重写网页终端体验，修复密码输入状态机，加入固定终端、暂停自动滚动、场景动作卡和更完整的 `help`。 |
| COC 教学 | 在 6 号车厢加入玛拉·维恩；以短对话解释 SAN、HP、检定、逃跑、存档和列车规则。 |
| 章节铺垫 | 在州街加入诺亚·格兰特，为《暴风之眼》后续章节留下调查钩子。 |
| 玩家进度 | 增加 `save` 和 `journal`；案件、线索、目标和失败代价随玩家私有存档保存。 |
| 多玩家基础 | 将书店《暴风之眼》的发现/阅读状态改为每位玩家独立，避免共享书架阻塞其他玩家。 |
| 失败前进 | 3 号车厢的侦查、潜行和逃跑会给出替代行动；第二次侦查确保发现关键开关。 |
| Agent 接口 | 提供可选的、本机监听的 HTTPS Agent API 代码与服务定义，可让 AI Agent 用受控令牌进行完整游戏会话与回归测试。 |
| 受限 LLM 命令理解 | 提供可选的回环 OpenRouter—Ollama 协议侧车。模型仅可提出一个经过 Lua 白名单验证的普通玩家命令或短叙事，不可执行 Lua、GM 命令、文件/服务器操作或多命令链。 |

更详细的代码/体验改动见 [CHANGELOG.md](CHANGELOG.md) 与 [docs/changes/P0_案件基础设施改造报告.md](docs/changes/P0_案件基础设施改造报告.md)。

## 玩家如何开始？

网页玩家进入后，建议依次输入：

```text
look
say 你好 ticket_clerk
# 按提示输入姓名
# 选择：消防员、列车员或记者
go east
go east
look
```

进入列车 6 号车厢后：

```text
say 理智 mara_vane
get mysterious_note
look mysterious_note
look train_map
journal
save
go east
```

新手完整路线、COC 机制和命令速查见：[《通往异世界的列车》新手说明](docs/player/新手说明.md)。

## 核心玩家命令

| 目标 | 命令 |
|---|---|
| 观察场景或物品 | `look`、`look <对象ID>` |
| 移动 | `go east`、`go west`、`go north`、`go south` |
| 对 NPC 说话 | `say <话题> <NPC ID>`，例如 `say 理智 mara_vane` |
| 拾取与查看物品 | `get <物品ID>`、`inv` |
| 查看 HP、SAN 和技能 | `hp` |
| 技能检定 | `perform <技能> [目标]` |
| 战斗和撤退 | `kill <敌人ID>`、`flee` |
| 查看私有案件/线索/目标 | `journal [案件ID]` |
| 保存和下线 | `save`、`bye` |

`inv` 只显示实际背包；`journal` 显示不可携带的调查证据、目标、失败代价和下一步。

## 本地运行

上游运行方式仍适用。项目默认使用 Lua 5.4，并需要 `lua-cjson` 与 `lua-socket`。

```bash
git clone https://github.com/<YOUR_ACCOUNT>/luamud-otherworld-train.git
cd luamud-otherworld-train
sh/sh/start.sh
```

默认游戏服务监听 7777。生产环境**不要把原始 Telnet 端口直接暴露到公网**；应使用 WebSocket 桥接和 HTTPS 反向代理。此仓库的 `web/`、`deploy/` 目录提供当前部署所用网页客户端、Nginx 示例、systemd 服务定义和端口隔离脚本，部署前请替换域名、路径和权限设置。

## 可选：让 AI Agent 试玩或回归测试

`tools/agent_api/` 包含一个仅绑定本机回环地址的 Python API 服务。它将经过令牌鉴权的 HTTPS 请求转发到本机 LuaMUD 服务，支持常规账号登录/注册、完整游戏命令、状态读取和关闭会话。

它是**可选组件**，不属于上游 LuaMUD 的原始代码。部署时必须：

1. 将 API 仅绑定到 `127.0.0.1`；
2. 使用 HTTPS 反向代理；
3. 将令牌保存到服务器权限受限文件，绝不提交到 Git；
4. 对外限流、记录审计日志，并限制并发会话数；
5. 保持 7777 和 WebSocket 桥接端口不向公网开放。

具体文件见 `tools/agent_api/` 与 `deploy/`。不要把真实玩家密码、私钥、证书、玩家存档或令牌提交到仓库。

## 可选：受限 OpenRouter 自然语言命令理解

本仓库的 `tools/openrouter_bridge/` 提供一个**仅绑定到服务器回环地址**的 Ollama 协议适配器。它让 LuaMUD 保持原有的本机 `/api/chat` 与 `/api/generate` 调用方式，同时由侧车使用服务器私有的 OpenRouter key 访问固定模型。该 key 不进入 LuaMUD、仓库、日志或网页端。

LLM 默认关闭。启用后，普通玩家命令会优先按现有规则执行；只有无法识别的自然语言输入才会进入模型解释。模型每次只能提出一个白名单内的普通玩家命令，LuaMUD 会再次进行最终验证。完整的架构、限额、部署、回滚和网页测试说明见：[OpenRouter LLM 侧车](docs/architecture/openrouter_llm_bridge.md)。

## 仓库结构

```text
src/                 LuaMUD 引擎和剧本
web/                 浏览器终端客户端
docs/player/         玩家说明
docs/changes/        改动与体验文档
tools/agent_api/     可选 AI Agent API 与客户端
tools/openrouter_bridge/  可选、本机回环的 OpenRouter—Ollama 协议适配器
deploy/              Nginx、systemd、端口隔离和无密钥环境模板
docs/architecture/   LLM 侧车的架构、限额、部署和回滚说明
tests/               上游及本修改版可扩展的测试框架
```

## 开发与贡献原则

这个项目的重点是把文字 MUD 做成可理解、可恢复、可测试的调查体验。新剧情应避免把玩家锁死在单一命令或单一共享物品状态中。新的案件建议使用 `mud_lib/casebook.lua`：以玩家私有的 `game_tags.casebook` 记录案件、线索、目标和失败后的替代路线。

欢迎提交 issue、修复、独立剧情模组和测试，但请保留上游许可证与署名，并避免提交任何密钥、玩家数据或商业 API 凭据。
