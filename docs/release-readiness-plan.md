# Release Readiness Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按风险优先顺序完成发布待办的本地可执行整改，并把外部环境验收保留为有证据的明确状态。

**Architecture:** 保留现有发布门禁、布局事务和拖拽状态机，只修正不可信边界并收紧公共模型。发布、覆盖率和 CI 统一调用仓库内稳定脚本；每个 Task 独立测试、提交并实时更新本文状态。

**Tech Stack:** Swift 6、Swift Testing、AppKit、SQLite、zsh、LLVM coverage、codesign/notarytool、GitHub Actions。

## Global Constraints

- 不改变现有启动、搜索、分页、文件夹、拖拽和快捷键行为。
- 任何时刻最多一个 Task 为 `进行中`。
- 开始修改代码前先更新本文状态；完成 Task 时将代码、测试、证据和状态放入同一提交。
- 自动验收失败时立即将 Task 标为 `阻塞`，不得开始下一 Task。
- 不用 mock、dry-run 或静态检查替代真实 Apple 公证、GitHub runner 或 VoiceOver 验收。
- 每个 Task 都运行目标测试、完整 `swift test`、严格 Debug/Release 构建和 `git diff --check`。
- 手工编辑使用 `apply_patch`；不覆盖无关工作树变更。

---

## 实时状态

| Task | 范围 | 状态 | 提交 | 验收证据 |
|---|---|---|---|---|
| 1 | 严格编译与发布门禁 | 已完成 | 本提交 | 三轮均发现并执行 1109 项/62 suites；严格 Debug、Release 与完整门禁通过 |
| 2 | 可信覆盖率工具 | 待处理 | - | - |
| 3 | 发布打包、签名与公证流程 | 待处理 | - | - |
| 4 | 布局事务与 PageItem 不变量 | 待处理 | - | - |
| 5 | 分页无障碍 | 待处理 | - | - |
| 6 | 拖拽状态所有权与输入常量 | 待处理 | - | - |
| 7 | 生命周期安全、CI 与最终验收 | 待处理 | - | - |

状态只允许：`待处理`、`进行中`、`已完成`、`阻塞`。

---

### Task 1: Strict Builds And Deterministic Release Gate

**状态：已完成**

**Covers:** P0-6、P2-13

**Files:**
- Modify: `Sources/LaunchPad/App/AppDelegate.swift`
- Modify: `Sources/LaunchPad/App/LaunchPadWindowController.swift`
- Modify: `Sources/LaunchPad/Controllers/LaunchPadViewController.swift`
- Modify: `Sources/LaunchPad/Views/AppGridCollectionView.swift`
- Modify: `Sources/LaunchPad/Views/EmptyStateView.swift`
- Modify: `Sources/LaunchPad/Views/FolderOverlayView.swift`
- Modify: `Sources/LaunchPad/Views/PageScrollView.swift`
- Modify: `Sources/LaunchPad/Views/SearchBar.swift`
- Modify: `Tests/LaunchPadTests/Controllers/LaunchPadViewControllerTests.swift`
- Modify: `Tests/LaunchPadTests/Utilities/AnimationConstantsTests.swift`
- Modify: `Tests/LaunchPadTests/Views/AppGridCollectionViewTests.swift`
- Modify: `Tests/LaunchPadTests/Views/FolderOverlayViewTests.swift`
- Modify: `Tests/LaunchPadTests/Views/PageScrollViewTests.swift`
- Modify: `Tests/LaunchPadTests/Views/TransientMessageViewTests.swift`
- Modify: `Tests/LaunchPadTests/Views/ViewLayerTests.swift`
- Modify: `scripts/test-release.sh`
- Create: `scripts/tests/test-release-discovery.sh`

**Interfaces:**
- Consumes: Swift Testing discovery output and event-stream identity.
- Produces: strict Sendable scheduling boundaries and a release gate whose discovered set is authoritative.

- [x] **Step 1: Mark Task 1 in progress**

Change the table and this section to `进行中`; do not change Task 2.

- [x] **Step 2: Write a failing discovery-contract test**

Create a shell test with a five-entry `LaunchPadTests.PerformanceTests/...` fixture and an empty fixture. Invoke:

```bash
LAUNCHPAD_RELEASE_ARTIFACT_DIR="$tmp/artifacts" \
  scripts/test-release.sh --probe-discovery-contract "$tmp/raw" "$tmp/list"
```

The five-entry fixture must pass and compare byte-for-byte after sorting; the empty fixture must fail. First run must fail because the probe is absent and the production function requires six performance tests.

- [x] **Step 3: Make discovery data-driven**

Replace the fixed count and fixed-name loop with:

```zsh
extract_discovery() {
  local raw=$1 list=$2
  LC_ALL=C rg '^LaunchPadTests\.' "$raw" | LC_ALL=C sort > "$list" || return 1
  [[ -s "$list" ]]
}
```

Expose `--probe-discovery-contract` before normal execution. Keep `extract_execution_set` as the exhaustive discovery-versus-execution comparison.

- [x] **Step 4: Fix all 11 strict compiler diagnostics**

Use `@MainActor @Sendable` for UI scheduling operations and `@Sendable` for completion closures in the eight listed Swift files. Preserve existing weak captures and closure bodies. Explicitly discard the two intentional return values:

```swift
_ = self.alertRunner(alert)
_ = processScrollPhase(event.phase, deltaX: event.scrollingDeltaX, event: event)
```

- [x] **Step 5: Make the authoritative commands strict**

Add `-Xswiftc -warnings-as-errors` to discovery, test and Release commands. Add one explicit Debug build using the same scratch/cache paths, then update `assert_swiftpm_resource_contract` for the extra authoritative invocation.

- [x] **Step 6: Verify Task 1**

已解除阻塞（2026-07-29）：首次 `./scripts/test-release.sh` 在进入 SwiftPM 前退出 1，
`mktemp` 报告默认父目录 `.superpowers/sdd` 不存在。新增默认目录回归测试先复现失败，
脚本改为自行建立忽略的运行时父目录后，回归测试退出 0。

提交闭环证据（2026-07-29）：修复后在未提交工作树重跑门禁时，manifest 记录
`command.provenance-start.status=1`，证明门禁只接受干净 HEAD。形成可 amend 的 Task 提交后，
门禁首尾 HEAD 与受控文件摘要完全一致。

```bash
zsh scripts/tests/test-release-discovery.sh
swift test --filter 'AppDelegate|LaunchPadWindowController|LaunchPadViewController|AppGridCollectionView|EmptyStateView|FolderOverlayView|PageScrollView|SearchBar'
swift build --product LaunchPadApp -Xswiftc -warnings-as-errors
swift build -c release --product LaunchPadApp -Xswiftc -warnings-as-errors
swift test
git diff --check
```

- [x] **Step 7: Complete and commit Task 1**

验收证据（2026-07-29）：`zsh scripts/tests/test-release-discovery.sh`、完整 `swift test`、
`swift build --product LaunchPadApp -Xswiftc -warnings-as-errors`、严格 Release 构建和
`git diff --check` 均退出 0。`./scripts/test-release.sh` 三轮发现集和执行集均为 1109 项，
三轮摘要均为 1109 tests / 62 suites passed；8 次权威 SwiftPM 调用、静态策略、watchdog
自测、残留进程检查、严格 Debug/Release 和首尾 provenance 状态全部为 0，最终
`result.status=passed`。

Write exact counts/results into the table, mark Task 1 `已完成`, and commit code, tests and plan together:

```bash
git add Sources Tests scripts docs/release-readiness-plan.md
git commit -m "fix: enforce deterministic release builds"
```

---

### Task 2: Trustworthy Portable Coverage Tooling

**状态：待处理**

**Covers:** P1-12、P1-13、P2-16（覆盖率部分）

**Files:**
- Create: `scripts/coverage.sh`
- Create: `scripts/tests/test-coverage.sh`
- Delete: `scripts/coverage_measure.sh`
- Delete: `scripts/final_measure.sh`
- Delete: `scripts/measure_coverage.py`
- Modify: `README.md`

**Interfaces:**
- Consumes: `swift test --enable-code-coverage`, `swift build --show-bin-path`, and `xcrun --find`.
- Produces: `.build/coverage/coverage.profdata`, `coverage-summary.txt`, and `coverage-show.txt` with trustworthy exit status.

- [ ] **Step 1: Mark Task 2 in progress**

Update only Task 2 to `进行中`.

- [ ] **Step 2: Write failure-injection tests**

Use temporary PATH shims for `swift`, `xcrun`, `llvm-profdata`, and `llvm-cov`. Assert nonzero exit and no `coverage_status=passed` for: Swift test failure, empty profraw, merge failure, report failure, and empty show output. Assert the script contains no `/Users/`, `arm64-apple-macosx`, or `/Applications/Xcode.app`.

- [ ] **Step 3: Implement the strict entrypoint**

The implementation must preserve this discovery/data flow:

```zsh
ROOT=${0:A:h:h}
SWIFT_BIN=${LAUNCHPAD_SWIFT_BIN:-$(command -v swift)}
XCRUN_BIN=${LAUNCHPAD_XCRUN_BIN:-$(command -v xcrun)}
OUTPUT_DIR=${LAUNCHPAD_COVERAGE_OUTPUT_DIR:-$ROOT/.build/coverage}

"$SWIFT_BIN" test --disable-sandbox --no-parallel --enable-code-coverage
BIN_PATH=$("$SWIFT_BIN" build --show-bin-path)
TEST_BINARY=$(find "$BIN_PATH" -type f \
  -path '*/LaunchPadPackageTests.xctest/Contents/MacOS/LaunchPadPackageTests' \
  -print -quit)
PROFRAW_FILES=("$BIN_PATH"/codecov/*.profraw(N))
LLVM_PROFDATA=$("$XCRUN_BIN" --find llvm-profdata)
LLVM_COV=$("$XCRUN_BIN" --find llvm-cov)
```

Require an executable test binary, at least one profraw, successful merge/report/show, and nonempty report/show files before printing `coverage_status=passed`.

- [ ] **Step 4: Remove old entrypoints and update README**

After failure tests pass, delete the three historical scripts. README must name only `./scripts/coverage.sh` and must not equate successful report generation with 100% coverage.

- [ ] **Step 5: Verify Task 2**

```bash
zsh -n scripts/coverage.sh scripts/tests/test-coverage.sh
zsh scripts/tests/test-coverage.sh
./scripts/coverage.sh
test -s .build/coverage/coverage.profdata
test -s .build/coverage/coverage-summary.txt
test -s .build/coverage/coverage-show.txt
swift test
swift build --product LaunchPadApp -Xswiftc -warnings-as-errors
swift build -c release --product LaunchPadApp -Xswiftc -warnings-as-errors
git diff --check
```

- [ ] **Step 6: Complete and commit Task 2**

Record normal and five injected results, mark Task 2 `已完成`, then commit:

```bash
git add README.md scripts docs/release-readiness-plan.md
git commit -m "fix: make coverage reporting trustworthy"
```

---

### Task 3: Portable Signing And Notarization Workflow

**状态：待处理**

**Covers:** P1-11、P2-16（发布部分）

**Files:**
- Create: `scripts/release-app.sh`
- Create: `scripts/tests/test-release-app.sh`
- Modify: `scripts/build-app.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: `LAUNCHPAD_CODESIGN_IDENTITY`, `LAUNCHPAD_TEAM_ID`, `LAUNCHPAD_NOTARY_PROFILE`, and `Resources/LaunchPad.entitlements`.
- Produces: `.build/LaunchPad.app` and `.build/LaunchPad.zip`; `--dry-run` prints commands only.

- [ ] **Step 1: Mark Task 3 in progress**

Update only Task 3 to `进行中`.

- [ ] **Step 2: Write release workflow tests**

Cover help, unknown option, missing variables, dry-run, build failure propagation, and fake-tool success. Success order must be: build, sign, verify, archive, submit, staple, Gatekeeper assess, stapler validate. Dry-run must create no artifacts and output no value matching `SECRET_`.

- [ ] **Step 3: Implement release-app.sh**

Require the three environment variables and run this real sequence:

```zsh
"$ROOT/scripts/build-app.sh"
codesign --force --deep --options runtime --timestamp \
  --entitlements "$ROOT/Resources/LaunchPad.entitlements" \
  --sign "$LAUNCHPAD_CODESIGN_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --keepParent "$APP" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" \
  --keychain-profile "$LAUNCHPAD_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=4 "$APP"
xcrun stapler validate "$APP"
```

Route `--dry-run` through one shell-quoting printer and execute no command. Validate Team ID and write it to a non-secret release manifest. Set executable mode on build, coverage, and release entrypoints.

- [ ] **Step 4: Verify Task 3**

```bash
zsh -n scripts/release-app.sh scripts/tests/test-release-app.sh
zsh scripts/tests/test-release-app.sh
LAUNCHPAD_CODESIGN_IDENTITY='Developer ID Application: Example' \
LAUNCHPAD_TEAM_ID='EXAMPLETEAM' \
LAUNCHPAD_NOTARY_PROFILE='example-profile' \
  ./scripts/release-app.sh --dry-run
swift test
swift build --product LaunchPadApp -Xswiftc -warnings-as-errors
swift build -c release --product LaunchPadApp -Xswiftc -warnings-as-errors
git diff --check
```

- [ ] **Step 5: Complete and commit Task 3**

Mark local implementation `已完成`, record real signing/notarization as external pending, then commit:

```bash
git add README.md scripts docs/release-readiness-plan.md
git commit -m "feat: add release signing workflow"
```

---

### Task 4: Atomic Layout Boundary And Valid PageItem States

**状态：已完成（P1-9、P3-3；P3-1 不变量不在本次范围，计划保留）**

**验收证据（2026-08-02）：** 删除 `LayoutPersistence.swift` 与 ViewLayerTests 中 `LayoutPersistenceTests` 套件（5 个测试）；`rg 'LayoutPersistence\.|saveLayout\(' Sources Tests` 无命中；在 `scripts/test-release.sh` `assert_static_policy` 新增 `dead-layout-entrypoint` 静态策略（先加策略确认当前代码命中后删除，验证无残留）。全量 `swift test` 1104 tests / 61 suites 通过（1109 - 5）；严格 Debug/Release 构建退出 0；`git diff --check` 通过。`StorageManagerLayoutMutationTests` 的逐故障注入回滚测试与 `LayoutRepositoryTests` 的 rename 事务/错误传播测试维持全绿，满足 P1-9 与 P3-3 验收。

**Covers:** P1-9、P3-1、P3-3

**Files:**
- Modify: `Sources/LaunchPadProtocols/Models/PageItem.swift`
- Modify: `Sources/LaunchPad/Storage/StorageManager.swift`
- Modify: `Sources/LaunchPad/Services/LayoutRepository.swift`
- Delete: `Sources/LaunchPad/Services/LayoutPersistence.swift`
- Modify: all `PageItem(` call sites under `Sources/` and `Tests/`
- Modify: `Tests/LaunchPadTests/TestHelpers/TestDataFactory.swift`
- Modify: model, storage and ViewLayer tests

**Interfaces:**
- Consumes: Codable payloads and SQLite joined item/app/group rows.
- Produces: `PageItem.page`, `.app`, `.group`, internal throwing validation, and `StorageError.invalidItem`.

- [ ] **Step 1: Mark Task 4 in progress**

Update only Task 4 to `进行中`.

- [ ] **Step 2: Write failing invariant tests**

Cover three legal factories, Codable round-trip, unknown type, and every illegal type/app/group combination. Add direct SQLite fixtures for unknown type and missing/mismatched metadata, expecting `StorageError.invalidItem`.

- [ ] **Step 3: Implement the invariant API**

Use this public shape:

```swift
public enum ValidationError: Error, Equatable, Sendable {
    case invalidMetadata(ItemType)
}

public let app: AppInfo?
public let group: GroupInfo?

public static func page(id: Int64, uuid: String, ordering: Int) -> Self
public static func app(
    id: Int64, uuid: String, ordering: Int, parentId: Int64?, app: AppInfo
) -> Self
public static func group(
    id: Int64, uuid: String, ordering: Int, parentId: Int64?, group: GroupInfo
) -> Self
```

The arbitrary initializer becomes internal and throwing. Custom `init(from:)` decodes the existing seven field names and delegates to validation.

- [ ] **Step 4: Make SQLite decoding strict**

Change `decodePageItem` to `throws -> PageItem`; reject unknown raw types, missing required joined rows, and mismatched metadata. Both fetch loops use `try`; add `StorageError.invalidItem`.

- [ ] **Step 5: Migrate all 352 construction sites**

Map `.page` to `PageItem.page`, legal app records to `.app`, and legal group records to `.group`. `TestDataFactory` supplies default valid metadata for its selected type. Invalid tests use JSON or direct SQLite, never a public bypass.

- [ ] **Step 6: Remove the non-atomic dead entrypoint**

Delete `LayoutPersistence.swift` and its three tests. Verify its name and `saveLayout(` have no production/test matches.

- [ ] **Step 7: Verify Task 4**

```bash
swift test --filter 'PageItem|StorageManager|LayoutRepository|LayoutDomainState|Integration'
test "$(rg -l 'PageItem\(' Sources Tests --glob '*.swift' | rg -v 'PageItem.swift' | wc -l | tr -d ' ')" = 0
! rg -n 'LayoutPersistence|saveLayout\(' Sources Tests
swift test
swift build --product LaunchPadApp -Xswiftc -warnings-as-errors
swift build -c release --product LaunchPadApp -Xswiftc -warnings-as-errors
git diff --check
```

- [ ] **Step 8: Complete and commit Task 4**

Record migration/search results, mark Task 4 `已完成`, then commit:

```bash
git add Sources Tests docs/release-readiness-plan.md
git commit -m "refactor: enforce valid page item states"
```

---

### Task 5: Adjustable Accessible Page Control

**状态：已完成（VoiceOver 真实播报留待外部验收）**

**验收证据（2026-08-02）：** `PageControlView` 改为 `.slider` 角色，新增 `accessibilityValue`（1 基当前页）、min/max、`Page N of M`/`No pages` 描述、`accessibilityIncrement`/`accessibilityDecrement`（经 `stepPage` 走 `selectDot → onDotSelected → update`，越界拒绝）。新增 11 个测试覆盖零页/单页/中间/首页递减/末页递增/成功动作及 value/min/max/描述/回调序列；旧 `accessibilityRole_isGroup` 断言更新为 `.slider`。全量 `swift test` 1115 tests / 62 suites 通过；严格 Debug/Release 构建退出 0；`git diff --check` 通过。

**Covers:** P2-12

**Files:**
- Modify: `Sources/LaunchPad/Views/PageControl.swift`
- Modify: `Tests/LaunchPadTests/Views/ViewLayerTests.swift`
- Verify: PageScrollView and FolderOverlayView tests

**Interfaces:**
- Consumes: existing PageControlViewModel state and `onDotSelected`.
- Produces: slider role/value plus increment/decrement actions.

- [ ] **Step 1: Mark Task 5 in progress**

Update only Task 5 to `进行中`.

- [ ] **Step 2: Write six failing branch tests**

Cover zero pages, one page, middle page, first-page decrement, last-page increment, and successful actions. Assert `.slider`, integer value, `Page N of M`, view-model state and callback sequence.

- [ ] **Step 3: Implement accessibility through existing selection flow**

```swift
override public func accessibilityRole() -> NSAccessibility.Role? { .slider }
override public func accessibilityValue() -> Any? { viewModel.currentPage + 1 }
override public func accessibilityMinValue() -> Any? { viewModel.totalPages == 0 ? 0 : 1 }
override public func accessibilityMaxValue() -> Any? { viewModel.totalPages }
override public func accessibilityValueDescription() -> String? {
    guard viewModel.totalPages > 0 else { return "No pages" }
    return "Page \(viewModel.currentPage + 1) of \(viewModel.totalPages)"
}
```

Increment/decrement call one helper that rejects zero/unchanged values, then calls `selectDot`, `onDotSelected`, and `update()` in mouse-selection order.

- [ ] **Step 4: Verify Task 5**

```bash
swift test --filter 'PageControlView|PageControl state logic|FolderOverlayView paging'
swift test
swift build --product LaunchPadApp -Xswiftc -warnings-as-errors
swift build -c release --product LaunchPadApp -Xswiftc -warnings-as-errors
git diff --check
```

Keep VoiceOver manual verification external unless actually performed.

- [ ] **Step 5: Complete and commit Task 5**

Mark Task 5 `已完成`, record VoiceOver pending, then commit:

```bash
git add Sources/LaunchPad/Views/PageControl.swift Tests docs/release-readiness-plan.md
git commit -m "feat: make page control accessible"
```

---

### Task 6: Narrow Drag Ownership And Named Key Codes

**状态：已完成（P2-14；P3-4 键码常量不在本次范围，计划保留）**

**验收证据（2026-08-02）：** 新增三个窄协议 `LaunchPadDragControlling`（LaunchPadViewController.swift 旁）、`GridDragControlling`（AppGridInteractionCoordinator.swift 旁）、`FolderDragControlling`（FolderOverlayView.swift 旁），只声明各消费者实际使用的状态与命令；`DragController` 通过 extension 遵守（状态机分支未改动），仅 AppDelegate 构造具体控制器。`FolderOverlayView.dragController` 由 `public` 降为 internal 协议类型。新增 8 个协议 fake 测试（先写失败测试：协议不存在编译失败），覆盖 begin/hover/结束/取消/预览回调注入；既有 `state == .idle` 断言改为 `isIdle`。`scripts/test-release.sh` 新增 `drag-controller-leak` 静态策略：Views 目录不得出现 `DragController` 标识符。全量 `swift test` 1123 tests / 64 suites 通过；严格 Debug/Release 构建退出 0；`git diff --check` 通过。

**Covers:** P2-14、P3-4

**Files:**
- Create: `Sources/LaunchPad/Controllers/KeyboardKeyCode.swift`
- Modify: DragController, LaunchPadViewController, AppGridInteractionCoordinator, FolderOverlayView, AppDelegate, HotkeyManager
- Modify: corresponding controller and view tests

**Interfaces:**
- Consumes: the existing DragController state machine and Carbon virtual key values.
- Produces: consumer-owned protocols and named KeyboardKeyCode values without duplicate drag state.

- [ ] **Step 1: Mark Task 6 in progress**

Update only Task 6 to `进行中`.

- [ ] **Step 2: Write failing dependency and mapping tests**

Use protocol fakes to exercise coordinator and folder begin/hover/cancel/finish without concrete DragController. Test escape, return, arrows, tab, delete, space, and unknown key codes.

- [ ] **Step 3: Add narrow drag protocols**

Define `LaunchPadDragControlling` beside `LaunchPadViewController`, `GridDragControlling` beside `AppGridInteractionCoordinator`, and `FolderDragControlling` beside `FolderOverlayView`. Each protocol declares only the existing properties and commands used in that file. Make DragController conform through extensions without changing its 38 state branches; only AppDelegate constructs the concrete controller.

- [ ] **Step 4: Centralize key codes**

```swift
enum KeyboardKeyCode {
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let delete: UInt16 = 51
    static let escape: UInt16 = 53
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
    static func navigationKey(for keyCode: UInt16) -> KeyboardNavigator.Key?
}
```

Use `.space` in AppDelegate/HotkeyManager and the mapping method for navigation. Unknown raw values remain only in tests.

- [ ] **Step 5: Verify all drag terminal branches and literal scans**

```bash
swift test --filter 'DragController|AppGridInteractionCoordinator|FolderOverlayView|HotkeyManager|AppDelegate'
rg -n 'keyCode == (36|48|49|51|53|123|124|125|126)' Sources
swift test
swift build --product LaunchPadApp -Xswiftc -warnings-as-errors
swift build -c release --product LaunchPadApp -Xswiftc -warnings-as-errors
git diff --check
```

The literal scan must have no output outside KeyboardKeyCode.swift.

- [ ] **Step 6: Complete and commit Task 6**

Record branch tests and scans, mark Task 6 `已完成`, then commit:

```bash
git add Sources Tests docs/release-readiness-plan.md
git commit -m "refactor: isolate drag state ownership"
```

---

### Task 7: Lifecycle Safety CI And Final Gate

**状态：已完成（P2-15、P3-5；GitHub 托管 runner 与 VoiceOver 等外部验收按实际状态保留）**

**最终验证（2026-08-02）：** 全量 `swift test` 1126 tests / 64 suites 通过；`zsh scripts/tests/test-test-quality.sh` 与 `./scripts/check-test-quality.sh` 通过；`./scripts/test-release.sh` 完整门禁退出 0（manifest 全部 status=0，三轮均 1126 tests / 64 suites）；严格 Debug/Release 构建退出 0；`git diff --check` 通过。`docs/release-readiness-todo.md` 中 P1-9/P2-12/P2-14/P2-15/P3-3/P3-5 六项已更新为已修复并记录验收证据。

**Covers:** P2-15、P3-5，以及总体发布结论

**Files:**
- Modify: AppDelegate, LaunchPadWindowController, LaunchPadViewController, AppGridCollectionView, AppGridFlowLayout, FolderOverlayView
- Create: `scripts/check-test-quality.sh`
- Create: `scripts/tests/test-test-quality.sh`
- Create: `.github/workflows/quality.yml`
- Create: `.github/workflows/performance.yml`
- Modify: affected tests, README, release todo and this plan

**Interfaces:**
- Consumes: existing AppKit lifecycle callbacks and repository verification scripts.
- Produces: no unproven production unwraps, CI quality gate, separate performance workflow, and final evidence.

- [ ] **Step 1: Mark Task 7 in progress**

Update only Task 7 to `进行中`.

- [ ] **Step 2: Write failing lifecycle and quality tests**

Cover database path fallback, absent service state, view not loaded, failed cell downcast, and absent panel content view. Fixture tests must prove the quality script rejects `#expect(true)`, `Thread.sleep`, and `RunLoop.current.run`, but accepts behavior assertions.

- [ ] **Step 3: Remove production IUO/force unwrap by ownership**

- AppDelegate installed services become optionals guarded at every consumer.
- LaunchPadViewController and FolderOverlayView owned subviews become `let`/`lazy var`; searchDebouncer becomes lazy.
- AppGridCollectionView data source becomes lazy; cell casts use `as?` guards.
- AppGridFlowLayout uses `compactMap` for copied attributes.
- WindowController uses `panel.contentView?.bounds ?? panel.contentRect(forFrameRect: panel.frame)`.
- Database path uses the system URL with a deterministic home-directory fallback.

- [ ] **Step 4: Add static quality and CI workflows**

`check-test-quality.sh` accepts an optional scan root and rejects the three forbidden patterns with filename/line output. `quality.yml` runs shell self-tests, quality scan, full tests and strict builds on `macos-14` and `macos-14-xlarge`. `performance.yml` runs only manually/weekly on one fixed runner, pipes `swift test --filter PerformanceTests --no-parallel` into a timestamped log, and uploads that log with `actions/upload-artifact@v4` for trend retention.

- [ ] **Step 5: Verify unwrap scans**

```bash
! rg -n '^\s*(private\(set\)\s+|private\s+|internal\s+|public\s+|var\s+)*var\s+[A-Za-z_][A-Za-z0-9_]*\s*:[^=]+!' Sources --glob '*.swift'
! rg -n '[A-Za-z0-9_.)\]]!' Sources --glob '*.swift'
```

Review every match; do not confuse `!` logical negation or `!=` with unwraps.

- [ ] **Step 6: Run all local verification, including the gate twice**

```bash
zsh scripts/tests/test-event-parser.sh
zsh scripts/tests/test-provenance-contract.sh
zsh scripts/tests/test-release-discovery.sh
zsh scripts/tests/test-coverage.sh
zsh scripts/tests/test-release-app.sh
zsh scripts/tests/test-test-quality.sh
./scripts/check-test-quality.sh
swift test
swift build --product LaunchPadApp -Xswiftc -warnings-as-errors
swift build -c release --product LaunchPadApp -Xswiftc -warnings-as-errors
./scripts/test-release.sh
./scripts/test-release.sh
git diff --check
```

Do not finish while either gate process is running. Capture exact counts, manifest paths and exit codes.

- [ ] **Step 7: Update authoritative status from evidence**

Remove only fully accepted items from `release-readiness-todo.md`. Keep real notarization, Gatekeeper, GitHub runner and VoiceOver items pending until actual results exist. Recompute totals and release conclusion without inferring release readiness from local success alone.

- [ ] **Step 8: Complete and commit Task 7**

Mark Task 7 `已完成`, record external pending conditions, then commit:

```bash
git add .github README.md Sources Tests scripts docs/release-readiness-todo.md docs/release-readiness-plan.md
git commit -m "ci: enforce release readiness gates"
```

- [ ] **Step 9: Final process-document cleanup**

After user review of final evidence, delete `docs/release-readiness-remediation-design.md` and this plan. Commit cleanup separately so execution remains recoverable from Git history.
