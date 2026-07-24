# P1 / P2 发现记录

> 最后更新：2026-07-24
> 来源：P0 Readiness Gate review (`docs/superpowers/plans/2026-07-21-p0-release-blockers.md`)

## 当前状态

截至本文件创建时，P0 readiness gate review **未产生任何 P1 或 P2 级别发现**。

## 背景

- 24 个 P0 task 已全部实现并提交，1086 tests 全绿，零 XCTest 残留
- `scripts/test-release.sh` 正式门禁因 WorkBuddy sandbox 限制 (`/bin/ps` 权限) 未能在本环境中执行，需在真实 macOS 终端中运行
- 覆盖率数据 (99.81%/98.29%) 来自 2026-07-10 最后测量，待重新收集

## 待跟踪项（非发现）

| 项目 | 级别 | 说明 | 状态 |
|------|------|------|------|
| 覆盖率重新测量 | P1 | 后续随代码变更重新收集 profraw 数据 | ⏳ |
| `test-release.sh` 正式执行 | P0 | 需在无 sandbox 的真实终端中运行，保留 artifact | ⏳ |
| 代码签名 / 公证 / Developer ID | P1 | 正式分发前必须完成 | ⏳ |
| CI 集成 | P2 | 正式分发前配置 | ⏳ |

## 约定

如果后续 review 产生新的 P1/P2 发现，请在此文件中新增条目，保持此节"当前状态"更新。
