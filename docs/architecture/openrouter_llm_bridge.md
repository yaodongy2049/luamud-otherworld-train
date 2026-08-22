# LuaMUD 的 OpenRouter LLM 侧车

## 目标与边界

本功能为《通往异世界的列车》增加**受限的自然语言命令解释**和既有的短叙事生成能力。LuaMUD 不再运行本地 Ollama，也不保存任何模型 API 凭据；它仍只向本机的 Ollama 兼容路径发送 HTTP 请求。新增的 Python 侧车把这两个本机请求转换成 OpenRouter 的 HTTPS Chat Completions 请求。

> 模型只产生一个结构化候选。LuaMUD 的普通玩家命令系统负责最终执行；模型不具有 Lua 执行、GM 命令、开发者控制台、文件、数据库、网络管理或服务器控制权限。

OpenRouter 的 Chat Completions API 使用 Bearer token 鉴权并提供 JSON 输出模式；凭据必须仅存放于服务器的权限受限环境文件中。[1] [2]

## 架构

```text
网页玩家 → HTTPS / WebSocket → LuaMUD（127.0.0.1:7777）
                                     │
                                     │ 仅在普通命令不能识别时
                                     ▼
                         侧车（127.0.0.1:11435）
                         - 固定模型和超时
                         - 单并发、每日调用上限
                         - 请求大小/输出 token 上限
                         - JSON 与动作白名单验证
                         - 不记录 prompt、回答或密钥
                                     │ HTTPS + Bearer（服务器私有）
                                     ▼
                               OpenRouter 模型 API
```

侧车只监听 `127.0.0.1`，只实现 `POST /api/chat` 与 `POST /api/generate`，并返回 LuaMUD 既有客户端可解析的 Ollama 风格 JSON 响应。它不会转发客户端传入的模型名；服务器私有环境文件固定唯一可用模型。

LuaMUD 上游还包含独立的 Ollama embedding 语义匹配模块（`/api/embeddings`）。该模块**不属于本侧车的接口范围**，因此 `LUAMUD_SEMANTIC_MATCH_ENABLED` 默认且应保持为 `false`；只有另行部署一个兼容 embedding 后端后才能单独评审启用。此保护避免命令解释功能在游戏启动时误访问不存在的 embedding 路径。

| 层 | 强制边界 |
|---|---|
| 网络 | 侧车固定回环绑定，不配置公网端口或 Nginx 路由。 |
| 认证 | OpenRouter key 只存在 `/etc/luamud-openrouter-bridge/openrouter.env`，不进入 Git、LuaMUD 进程环境、日志或 API 响应。 |
| 资源 | 默认单并发、25 秒超时、最大 12 KiB 请求、最大 6,000 输入字符、最大 180 输出 token、每日最多 24 次调用。 |
| 命令 | 每次仅允许一个普通玩家命令；`help`、`look`、`go`、`say`、`get`、`inv`、`hp`、`perform`、`kill`、`flee`、`save`、`journal`、`bye` 或 `unknown`。 |
| 禁止项 | GM 命令、动态剧情函数、开发者控制台、任意 Lua、服务管理和多命令链均被拒绝。 |
| 可观测性 | 只记录请求 ID、端点、结果类别和耗时；不记录玩家输入、模型输出、令牌或 API key。 |

## 部署

部署需要 root 权限，并且应在维护窗口中进行。仓库提供的是**不含密钥的模板**，真实环境文件必须在服务器上创建。

```bash
# 1. 安装代码到独立目录，创建低权限服务账户与状态目录。
sudo install -d -o luamudbridge -g luamudbridge -m 0750 /opt/luamud-openrouter-bridge
sudo install -d -o luamudbridge -g luamudbridge -m 0750 /var/lib/luamud-openrouter-bridge

# 2. 在服务器上创建私有环境文件；不要复制任何 key 到仓库。
sudo install -d -m 0700 /etc/luamud-openrouter-bridge /etc/luamud
sudo cp deploy/env/openrouter-bridge.env.example /etc/luamud-openrouter-bridge/openrouter.env
sudo cp deploy/env/luamud-llm.env.example /etc/luamud/llm.env
sudo chmod 0600 /etc/luamud-openrouter-bridge/openrouter.env
sudo chmod 0640 /etc/luamud/llm.env
```

在 `openrouter.env` 中填写服务器私有的 `OPENROUTER_API_KEY`，并在确认预算后保留或调整固定模型和每日上限。首次部署时，`/etc/luamud/llm.env` 应保持 `LUAMUD_LLM_ENABLED=false`。复制 `deploy/systemd/luamud-openrouter-bridge.service` 至 `/etc/systemd/system/`，并复制 `deploy/systemd/luamud.service.d/20-openrouter-bridge.conf` 至 `/etc/systemd/system/luamud.service.d/`。

完成 `systemctl daemon-reload` 后，先启动侧车并检查其回环健康端点；它不应在任何公网地址监听。随后才将 `LUAMUD_LLM_ENABLED=true` 写入 `/etc/luamud/llm.env`，同时保留 `LUAMUD_SEMANTIC_MATCH_ENABLED=false`，并重启 LuaMUD 服务。

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now luamud-openrouter-bridge.service
curl -fsS http://127.0.0.1:11435/healthz
sudo systemctl restart luamud.service
```

## 回滚

如需立即停止模型调用而不改代码，只需将 `/etc/luamud/llm.env` 中的 `LUAMUD_LLM_ENABLED` 改为 `false`，然后重启 `luamud.service`。游戏的确定性命令、网页客户端、WebSocket 桥接、存档和剧情均应继续可用。若需要完全停用侧车，再执行 `sudo systemctl disable --now luamud-openrouter-bridge.service`。

## 验证方法

仓库提供独立的 `sh/test_llm_bridge.sh`，其中包含四项无需外部凭据的针对性验证：`tests/openrouter_bridge/test_bridge.py` 覆盖协议转换和 JSON/动作契约；`tests/test_llm_safety.lua` 覆盖 Lua 侧最终白名单；`tests/test_semantic_match_disabled.lua` 确保不会误调用未实现的 embedding 路径；`tests/test_llm_startup_guard.lua` 确保旧 Ollama 示例自测不会在模块加载时修改全局开关。`tests/openrouter_bridge/integration_probe.py` 与 `game_agent_probe.py` 则只应在服务器私有环境中运行，分别验证真实回环侧车到 OpenRouter 的 `向东走 → go east` 映射，以及真实游戏会话中的自然语言观察。

网页测试时，先照常登录列车游戏。输入一条标准命令（如 `look` 或 `go east`）应继续由原有命令系统立即处理。随后可输入自然语言等价表达，例如“向东走”；若模型与侧车均可用，LuaMUD 会将它转成一个已验证的 `go east` 候选。测试不应使用开发者控制台、GM 命令或要求模型执行多步命令。

## References

[1]: https://openrouter.ai/docs/quickstart "OpenRouter Quickstart"
[2]: https://openrouter.ai/docs/api_reference/authentication "OpenRouter API Authentication"
