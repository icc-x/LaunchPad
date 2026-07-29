# LaunchPad 文档清理设计

> 日期：2026-07-29
> 目标：将发布复审结论收敛为唯一待处理事项文档，并删除不再服务于当前开发与发布的历史过程文档。

## 最终文档集合

清理完成后，`docs/` 只保留以下三个长期文档：

1. `docs/architecture.md`：由现有 `docs/superpowers/specs/2026-06-06-launchpad-design.md` 重命名而来，作为产品与架构设计基线。
2. `docs/release-readiness-todo.md`：记录当前尚未完全修复的 14 项发布待办、证据、验收标准和状态维护规则。
3. `docs/原始app技术实现参考.md`：保留系统 LaunchPad 行为与逆向分析依据。

`README.md` 继续作为项目入口，但必须同步当前测试数量、Release warning 状态、签名公证状态和文档索引。

## 删除范围

删除以下已过期或可被新待办文档替代的跟踪材料：

- `docs/2026-07-15-release-readiness-review.md`
- `docs/coverage-progress.md`
- `docs/superpowers/findings/P1-P2-findings.md`
- `docs/superpowers/plans/2026-07-21-p0-release-blockers.md`
- `docs/superpowers/plans/2026-07-27-release-readiness-remediation.md`
- `docs/superpowers/reports/` 下全部迁移与决策报告
- `docs/superpowers/specs/` 下除架构基线源文件外的全部过程设计，包括本清理设计

不删除源码、测试、脚本、资源、Git 历史以及被忽略的运行产物。

## 待处理事项文档

`docs/release-readiness-todo.md` 使用当前代码和 2026-07-29 新鲜验证结果，而不是复制历史计划。内容包括：

- 总体状态：27 项已修复，7 项部分修复，7 项未修复；当前仍不可正式发布。
- 仅列出 14 项部分修复或未修复问题。
- 每项包含优先级、现状、代码证据、剩余工作和可执行验收标准。
- 发布阻断项排在最前：P0-6、P1-11～P1-13、P2-13、P2-16。
- 不记录实施过程、历史提交列表或尚未确认的技术方案。
- 状态只有在对应验收命令产生新鲜成功证据后才能更新。

## README 同步

README 做最小事实修订：

- 测试数量从 1086 更新为 1109，并注明 2026-07-29 的 `swift test` 新鲜结果。
- Release 状态改为存在 warning，不能声明 0 warning。
- 保留现有 2026-07-24 覆盖率数字，但明确当前覆盖率脚本不具备发布证据可信性。
- 文档列表只链接最终三个文档。
- 删除对历史计划、发现记录和覆盖率过程报告的引用。

## 验证标准

清理完成后必须满足：

1. `find docs -type f` 只返回三个预期文档。
2. 全仓搜索不再引用任何已删除路径。
3. Markdown 相对链接目标全部存在。
4. `git diff --check` 通过。
5. `swift test` 新鲜执行通过。
6. 工作区中不存在本任务之外的意外修改。

