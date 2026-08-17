# LuaMUD 上游公开发布核验

核验日期：2026-08-16

## 结论

截至核验时，未发现 `wadehan/luamud` 的 GitHub 官方仓库或官方镜像。

核验方法如下：

1. 使用 GitHub CLI 搜索 `luamud` 相关公开仓库。结果中没有 `wadehan/luamud`，仅出现无关的同名 Lua MUD 项目以及 `vcalibrator/python_mud` 的 Python 迁移项目。
2. 调用 GitHub API 查询 `wadehan`，未获得包含 LuaMUD 的公开仓库列表。
3. 检索 `wadehan luamud GitHub`、`gitee wadehan luamud github` 与 `Eye of the Blizzard LuaMUD GitHub`，没有发现官方 GitHub 镜像。
4. 阅读上游 Gitee 仓库主页及开发日志，仓库只提供 Gitee 克隆地址 `https://gitee.com/wadehan/luamud.git`，未列出 GitHub 地址。

## 许可证

上游仓库采用 MIT License，版权行是：

> Copyright (c) 2026 wadehan

MIT 许可允许使用、复制、修改、合并、发布和分发，但要求在所有副本或实质部分保留上述版权声明和许可文本。

## 公开改造版的合规措施

公开改造版应：

- 原样保留 `LICENSE`；
- 在 README 顶部说明上游为 `wadehan/luamud`；
- 链接到 `https://gitee.com/wadehan/luamud` 及开发日志；
- 使用“基于上游的修改版”描述，避免暗示上游作者认可、维护或共同发布本改造版；
- 用 CHANGELOG/UPSTREAM_ATTRIBUTION 明确列出本项目新增的网页客户端、HTTPS部署资料、Agent API、玩家私有案件状态、线索册、引导和剧本改名等改动；
- 排除服务器私钥、访问令牌、玩家存档、证书、日志与其他运行环境敏感数据。

## 来源

- 上游仓库：https://gitee.com/wadehan/luamud
- 上游开发日志：https://gitee.com/wadehan/luamud/wikis/%E5%BC%80%E5%8F%91%E6%97%A5%E5%BF%97
- 上游许可证：仓库 `LICENSE`
