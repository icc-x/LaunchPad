# LaunchPad Swift Testing 统一与确定性发布门禁设计

> 状态：已确认设计。本文补充
> `docs/superpowers/specs/2026-07-21-p0-release-blockers-design.md`，并在测试框架、
> 测试生命周期、测试失败处理和发布测试门禁发生冲突时，以本文为准。P0 业务行为、
> 数据库事务、拖放语义和网格产品规则仍以原 P0 设计为准。

## 1. 目标

本设计将 `LaunchPadTests` 统一为 Swift Testing，并在不丢失测试语义的前提下消除
现有非确定性失败、进程级副作用和门禁假阳性。

完成状态同时满足：

1. `Tests/LaunchPadTests` 不再包含 XCTest 导入、类型、断言、等待或跳过 API。
2. 当前 9 个 XCTest 文件中的 261 个测试方法全部有可审查的一对一迁移记录。
3. 迁移不删除期望、不降低精度、不把失败改为跳过；弱测试在所属业务 Task 中强化。
4. AppKit、FSEvents、pasteboard、global hotkey 和动画测试不依赖宿主偶然状态。
5. 墙钟性能断言始终执行，使用单调时钟和固定输入，不按环境跳过、重试或放宽。
6. 唯一发布门禁连续三次完成完整串行测试，每次都产生完整 Swift Testing summary，
   随后完成 release build 和进程资源检查。

本文不把 P0 readiness gate 等同于正式分发授权。Developer ID、hardened runtime、
notarization、stapling、Gatekeeper 和剩余 P1/P2 仍需在正式发布流程中独立关闭。

## 2. 已验证基线

### 2.1 工具链与平台

- `Package.swift` 使用 `swift-tools-version: 6.0` 和 `macOS 14.0+`。
- 当前工具链为 Apple Swift 6.3.1。
- 实际探针以 `arm64-apple-macosx14.0` 编译并运行 Swift Testing。
- `Testing.framework` 的 `LC_BUILD_VERSION minos` 为 14.0。
- `Package.swift` 无需为迁移增加依赖或调整 deployment target。

### 2.2 测试框架分布

当前测试目标包含：

| 类型 | 文件数 | Suite/Case | 测试声明 |
| --- | ---: | ---: | ---: |
| Swift Testing | 27 | 42 个 `@Suite` | 634 个 `@Test` |
| XCTest | 9 | 15 个 `XCTestCase` | 261 个 `test...` 方法 |
| 测试辅助文件 | 2 | - | - |

XCTest 剩余文件共约 3,364 行：

| 文件 | XCTest 方法数 | 迁移执行点 |
| --- | ---: | --- |
| `Tests/LaunchPadTests/Views/ViewLayerTests.swift` | 56 | Task 3M |
| `Tests/LaunchPadTests/Views/AppIconCellTests.swift` | 26 | Task 4 |
| `Tests/LaunchPadTests/Views/FolderCellTests.swift` | 20 | Task 4 |
| `Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift` | 71 | Task 4 |
| `Tests/LaunchPadTests/Views/DiffableDataSourceBuilderTests.swift` | 11 | Task 4 |
| `Tests/LaunchPadTests/Views/FolderOverlayViewTests.swift` | 39 | Task 19 |
| `Tests/LaunchPadTests/Views/FolderOverlayViewPagingTests.swift` | 8 | Task 19 |
| `Tests/LaunchPadTests/Services/FileWatcherTests.swift` | 14 | Task 21 |
| `Tests/LaunchPadTests/Utilities/AccessibilitySettingsTests.swift` | 16 | Task 21 |

合计为 261，所有文件均有唯一迁移归属。

### 2.3 当前失败不是可接受基线

统一命令已验证以下状态：

```bash
CLANG_MODULE_CACHE_PATH=/tmp/launchpad-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/launchpad-swiftpm-module-cache \
swift test --disable-sandbox --no-parallel
```

- XCTest：261 个测试，2 个跳过，6 个失败。
- Swift Testing：历史全量运行在后台 scheduler 上触发 SIGTRAP，未产生最终 summary。
- 完整 `AppDelegateTests` 还稳定暴露 1 个 hotkey override 断言失败。

这些问题只用于建立修复归属台账，不构成白名单。Task 21 完成后不再接受任何既有失败、
跳过、signal 或缺失 summary。

## 3. 核心决策

### 3.1 渐进迁移，最终零残留

迁移按测试文件首次被后续业务 Task 触达的时间分批执行。一个 Task 一旦修改 XCTest
文件，Task 结束时该文件必须完全使用 Swift Testing。禁止在同一文件、同一 suite 或
同一提交结果中保留 `XCTest + Testing` 混用。

全仓 XCTest 残量只能单调下降。新测试从现在起一律使用 Swift Testing；计划中 Task 16、
Task 17 和 Task 19 的 XCTest 示例全部重写，Task 17 不再创建新的 `XCTestCase`。

### 3.2 不重写已审查历史

Task 1–3 的实现提交、报告和 review package 保持不可变：

- Task 1：`2083b03`
- Task 2：`11a8253`
- Task 3：`1e17738`

Task 1 和 Task 2 已使用 Swift Testing，不制造空迁移提交。Task 3 的
`ViewLayerTests.swift` 通过后续 Task 3M 补迁移；`task-3-report.md` 保留当时仍有
XCTest 的事实，新建迁移报告记录后续提交和审查区间。

### 3.3 先恢复 executor 与系统边界，再迁移

Task 3M 前新增 Task 3R。3R 是独立、可拒绝的稳定性修复单元，不修改 XCTest 文件：

1. `SearchDebouncer` 的 scheduler action 显式 hop 到 `MainActor`，不在后台队列调用
   `MainActor.assumeIsolated`。
2. `LaunchPadViewControllerTests` 为 debounce 注入可控 scheduler，推进时间并断言调用，
   不留下逃逸后台任务。
3. 增加真实 `DispatchQueueScheduler` 的异步 actor 回归测试和 cancel 回归测试。
4. `HotkeyManager.tapProvider` 明确区分“没有 override”和“override 返回 nil”；后者不得
   回退真实 `CGEvent.tapCreate`。
5. AppDelegate/Hotkey 测试不得注册真实 tap、local monitor、status item 或打开系统设置。

3R 完成后，全量测试可以完整退出并输出 summary；仍待后续 Task 修复的 6 个 XCTest
失败必须与迁移台账完全一致，不能出现新增失败。

## 4. 任务结构

保留现有 Task 1–23 编号，避免破坏进度和已完成审查。新增两个带后缀的执行单元：

### Task 3R：恢复确定性测试运行时

职责：修复 scheduler executor SIGTRAP、逃逸 debounce task 和 hotkey override 的系统
回退。完成门禁是相关 focused suite 全绿、全量测试能完整结束且产生 Swift Testing
summary，不再出现 signal 5。

### Task 3M：补齐已完成 Task 3 的测试迁移

职责：先用现有 `hideCompletionRunner` 修复 SearchBar 的 headless 动画夹具，再将
`ViewLayerTests.swift` 的 6 个 XCTestCase、56 个方法全部迁移。迁移后的 AppKit suite
在 suite 级使用 `@MainActor`，固定等待被同步 completion 驱动替代。

### Task 4：迁移 Cell/Grid 测试并完成统一 metrics

在新行为 RED 前完成 4 个文件、128 个方法迁移。三个当前拖放失败先修复夹具：

- 真实 `NSPasteboard(name:)` 在隔离测试进程中写入返回 `false`，不能作为内存 fake。
- `AppGridCollectionView` 提供窄的 internal UUID reader 注入，生产默认读取
  `draggingPasteboard.string(forType:)`，测试注入固定 UUID 或 nil。
- 保留 `NSPasteboardItem` writer 测试验证序列化。
- group、same-page reorder、missing target 和 out-of-range 测试必须断言实际分支结果，
  修复当前“pasteboard 先失败导致 target 分支未执行”的假阳性。

上述测试全绿并迁移后，再按 P0 计划为 metrics、cell constraint、accessibility、稳定选择和
paged search 执行 RED-GREEN。

### Task 19：迁移 Folder Overlay 测试并完成文件夹拖放

先迁移 2 个文件、47 个方法。外部点击测试使用已有
`closeFolderCompletionRunner = { $0() }`，强制解包事件、完成布局，并用可证明位于
panel 外的坐标断言 `isHidden` 和 `onClosed`；删除固定延时。随后执行文件夹内重排、拖出、
自动解散和安全删除的业务 RED-GREEN。

### Task 21：迁移系统边界测试并关闭资源

先修复 `FileWatcher` 的启动与生命周期契约，再迁移 `FileWatcherTests` 和原计划遗漏的
`AccessibilitySettingsTests`，共 30 个方法：

- 检查 `FSEventStreamStart` 的 Bool 结果并向调用方暴露启动失败。
- 启动失败立即释放 stream 与 retained context。
- 重复 start 先停止旧 backend，不覆盖并泄漏旧资源。
- callback context 不自持有 watcher；deinit/stop 只释放一次。
- 单元测试通过可注入 backend 确定性驱动 event、debounce、stop 和失败分支。
- 真实 FSEvents 保留为宿主集成门禁，必须真实执行并通过，不按环境跳过。
- Accessibility observer/settings 测试使用测试局部清理，不访问或修改用户系统设置。

Task 21 结束时，完整串行 suite 必须首次达到全绿、零 skip、零 signal、完整 summary，且
测试目录 XCTest 静态扫描为零。

### Task 22–23：冻结发布门禁与文档

Task 22 重写墙钟测量并创建唯一发布脚本。Task 23 增加重开持久化集成证据、运行最终
门禁，并同步 README、迁移台账和 P0 文档。README 不再声明 Swift Testing 与 XCTest
共存。

## 5. Swift Testing 编码规范

### 5.1 Suite 与 actor

- 纯函数和不可变领域测试优先使用值类型 `@Suite`。
- AppKit 测试在 suite 类型上标注 `@MainActor`，不零散标注单个方法。
- 有每测试独立 fixture 的 suite 可使用 `final class`；工具链探针已证明每个 `@Test`
  创建独立 suite 实例。
- 不共享可变 SUT。优先由每个测试或 `makeSUT()` 创建完整 fixture。
- `.serialized` 只用于确实访问同一进程级资源的 suite，并写明被串行保护的资源；它不能
  代替正确隔离。

### 5.2 断言迁移

| XCTest | Swift Testing |
| --- | --- |
| `XCTAssert*` | `#expect(...)` |
| `XCTUnwrap` | `try #require(...)` |
| `XCTAssertThrowsError` | `#expect(throws:)` |
| `XCTFail` | `Issue.record(...)` |
| `accuracy:` | 显式 `abs(actual - expected) <= tolerance` |

现有 13 个 `accuracy:` 断言逐项保留原 tolerance。禁止将精确身份、顺序、调用次数或
错误类型断言降级为非 nil、count 或“不崩溃”。

### 5.3 生命周期与清理

- 临时目录使用 `FileManager.default.temporaryDirectory` 加 UUID，创建成功后立即注册
  测试局部 `defer` 删除。
- UserDefaults、通知 observer、watcher、monitor 和数据库连接在测试局部显式恢复/关闭。
- `deinit` 只做同步、不可失败的 best-effort 兜底，不能承担唯一清理责任。
- 迁移 `setUp/tearDown` 时，必须逐项记录 fixture 创建、清理顺序和 actor 语义，不能只把
  属性改成 optional 后依赖析构。

### 5.4 异步与超时

- 异步测试使用原生 `async throws`。
- callback 使用 `confirmation` 时，其 body 必须真正 await callback；不能在 body 返回后
  期待 confirmation 继续等待。
- 秒级超时使用基于 `ContinuousClock` 的统一 timeout helper 和结构化并发 race。
- 禁止固定 `sleep`、主 RunLoop 轮询和只为延长测试进程寿命的等待。
- AppKit headless 动画使用既有 completion runner 注入；不得靠增大延时等待真实
  `NSAnimationContext` completion。

### 5.5 跳过政策

- 性能测试禁止 `.enabled(if:)`、环境变量、compile flag、重试、阈值倍数和 skip。
- 当前依赖 Finder 运行状态的 `XCTSkip` 在 Task 4 改为可注入 workspace 状态，所有分支
  确定性执行。
- 发布门禁不接受 runtime skip。系统集成能力必须在具备正式宿主能力的发布环境中真实
  执行；环境不满足时门禁失败，而不是静默跳过。

## 6. 迁移证据与提交边界

一个含存量 XCTest 文件的 Task 允许多个原子提交，推荐顺序：

1. 修复已验证的既有失败；仍使用旧框架时先使 focused suite 全绿。
2. 每个测试文件独立完成纯迁移；迁移提交不得包含生产代码。
3. 为本 Task 新行为添加最小 RED 测试，保存失败证据。
4. 实现最小生产修改并验证 GREEN。
5. 运行 Task focused gate、静态风格检查和 package/test target 编译。

每个迁移文件生成旧方法 ID 到新 suite/test 的一对一映射，并记录：

- 迁移前后声明数；
- 每条断言的等价或强化说明；
- actor、fixture、异步等待和清理方式；
- 迁移前已知失败及其独立修复提交；
- focused 命令实际匹配数和最终结果。

禁止 amend/rebase 已审查提交。每份 review package 固定 `base..head`；审查后任何新增提交
都会使该区间结论失效，必须重新审查。

## 7. 审查模型

每个迁移 Task 至少经过三层非实现者审查：

1. **迁移等价审查**：只看纯迁移提交，逐项核对方法映射、断言、actor、fixture、清理和
   异步语义，确认没有生产 diff。
2. **规格与质量审查**：审查既有失败修复和新行为 RED-GREEN，确认修复根因而非修改
   期望、增加等待或引入跳过。
3. **Task 聚合审查**：审查整个 `base..head`，运行 focused gate，确认组合结果可编译、
   可发现、全绿且未影响相邻任务合同。

`progress.md` 分别记录迁移提交、行为提交、review range 和复测证据。Task 3 的历史报告
不追溯修改；新增 Task 3R/3M 报告记录后续事实。

## 8. 发布门禁

### 8.1 每 Task 门禁

- focused filter 必须先从测试清单证明至少匹配一个明确命名测试；零匹配退出 0 仍失败。
- 所属 focused suite 必须全绿、零 skip、无 signal。
- package 和 test target 必须完整编译。
- 被触达的迁移文件必须通过零 XCTest 静态检查。
- 全仓 XCTest 文件数和已登记失败数只能减少，不能增加。
- 性能测试若在任何完整运行中失败，立即采样并优化目标路径，不延后、不跳过。

### 8.2 静态零残留门禁

最终脚本以 `rg` 拒绝至少以下符号：

```text
import XCTest
XCTestCase
XCTAssert*
XCTFail
XCTSkip
XCTestExpectation
expectation(
wait(for:
```

扫描范围为 `Tests/**/*.swift`。任何命中都使门禁退出非零。

### 8.3 墙钟性能门禁

- `SearchEngine` 无缓存：固定 1000 项，median 和 p95 均小于 50ms。
- `SearchEngine` 缓存命中：median 和 p95 均小于 1ms。
- Diffable snapshot：固定 1002 项，median 和 p95 均小于 10ms。
- 三组动态 `GridMetrics`：median 和 p95 均小于 1ms。
- `IconCache` 1000 次内存命中：median 和 p95 均小于 300ms。

测量使用 `ContinuousClock`、预热、固定输入和排序后的样本。失败时使用
`/usr/bin/sample` 采集目标测试进程并优化真实生产路径；禁止条件启用、retry、扩大阈值或
从全量测试中过滤 PerformanceTests。

### 8.4 最终脚本合同

`scripts/test-release.sh` 是唯一 P0 发布测试入口，按顺序执行：

1. shell 语法、自测和零 XCTest/反 skip 静态检查；
2. 生成测试清单，验证清单非空且所有预期 PerformanceTests 均可发现；
3. 连续三轮完整 `swift test --no-parallel`，每轮使用独立日志；
4. 每轮验证命令退出 0、Swift Testing 最终 summary 存在、零失败、零 skip、零 signal，
   且每个性能测试名称均实际执行；
5. 三轮测试清单和执行集合一致；
6. `swift build -c release` 成功；
7. timeout、signal、nonzero 自测能立即传播失败并清理准确的进程组；
8. 不存在残留 `swift test`、xctest 或 LaunchPad 测试进程。

当前工具链的纯 Swift Testing focused probe 未生成 `--xunit-output` 文件，因此脚本不能
把 XUnit 当作结果权威。完整原始日志、测试清单、最终 summary 和退出状态共同构成证据；
任一缺失都失败。

## 9. 完成标准

- [ ] Task 3R 消除 scheduler SIGTRAP、逃逸 task 和 hotkey 真实系统回退。
- [ ] Task 3M、4、19、21 精确迁移 9 个文件、261 个 XCTest 方法。
- [ ] 所有迁移文件都有一对一映射和独立迁移审查。
- [ ] 所有测试文件只使用 Swift Testing，静态 XCTest 扫描零命中。
- [ ] 当前 6 个 XCTest 失败、2 个 skip 和 1 个 AppDelegate 失败均已根因修复。
- [ ] Task 21 后完整 suite 全绿、零 skip、零 signal、summary 完整。
- [ ] 五组墙钟阈值始终执行并通过 median/p95 断言。
- [ ] `scripts/test-release.sh` 连续三轮完整测试与 release build 真实退出 0。
- [ ] README、P0 计划、Task brief、progress 和发布证据与最终实现一致。

## 10. 停止条件

- focused filter 零匹配或无法证明匹配测试时立即停止。
- 迁移后测试数减少、断言变弱、fixture 清理不等价或出现新 skip 时立即停止。
- Task 3R 后仍出现 signal、缺失 summary 或未登记失败时，回到系统化根因调查并修订计划。
- 三次修复假设均失败时停止继续打补丁，重新评估对应架构边界。
- FileWatcher、hotkey、AppDelegate 或 AppKit 测试触碰真实用户状态时立即停止。
- 性能阈值失败时停止发布流程，采样并修复生产路径；禁止绕过。
- 最终脚本任何一轮非零、超时、signal、skip、缺 summary 或残留进程时，P0 不得标记完成。
