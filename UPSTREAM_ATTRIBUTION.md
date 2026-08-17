# 上游归属、许可证与本修改版说明

## 上游归属

本仓库是对 **LuaMUD** 的修改版。最初软件与核心框架来自：

| 项目 | 信息 |
|---|---|
| 上游作者 | `wadehan` |
| 上游仓库 | <https://gitee.com/wadehan/luamud> |
| 上游开发日志 | <https://gitee.com/wadehan/luamud/wikis/%E5%BC%80%E5%8F%91%E6%97%A5%E5%BF%97> |
| 上游许可证 | MIT License |
| 上游版权声明 | `Copyright (c) 2026 wadehan` |

本仓库**不是**上游作者的官方 GitHub 镜像、fork 或协作发布渠道。上游作者并未参与、批准、维护或保证本修改版。

## 许可证

上游采用 MIT License。MIT 允许使用、复制、修改、合并、发布、分发、再许可和销售软件副本，但要求在软件的全部或实质部分中保留版权声明与许可文本。

因此，本仓库原样保留根目录 `LICENSE`，其中包含：

> Copyright (c) 2026 wadehan

任何使用、分发或再发布本仓库实质部分的行为，也必须继续保留该许可证与版权声明。

## 本修改版的维护范围

本修改版由当前仓库维护者整理，用于探索可玩性、网页体验、COC 调查流程、玩家私有案件状态和 Agent 交互。主要新增内容包括：

- 将教学剧本组织为《通往异世界的列车》；
- 将书店章节入口改名为《暴风之眼》；
- 新增教学/铺垫 NPC、玩家线索册、显式存档、失败前进与私有案件状态；
- 增加浏览器网页客户端改进、HTTPS 部署示例和端口隔离；
- 增加可选的、令牌保护的 AI Agent API 与回归测试工具；
- 新增玩家教程、部署资料、体验验证和改动记录。

完整变更见 [CHANGELOG.md](CHANGELOG.md)。

## GitHub 核验

在本仓库创建前，维护者通过 GitHub 公开仓库检索、GitHub API 的 `wadehan` 账号查询、网页检索以及上游 Gitee 仓库/开发日志交叉核验，未发现 `wadehan/luamud` 的官方 GitHub 仓库或镜像。核验记录见 [docs/UPSTREAM_VERIFICATION.md](docs/UPSTREAM_VERIFICATION.md)。

## 安全与数据边界

本仓库不应包含任何真实玩家账号、密码、游戏存档、服务器 SSH 私钥、TLS 私钥、Agent API 令牌、运行日志或商业服务凭据。部署示例中的域名、路径、用户名和服务参数均必须在使用者自己的环境中重新配置。
