# LaunchPad

> 一个以 TDD 为硬性工程约束、通过逆向工程系统 Dock 二进制来忠实复刻 macOS 启动台的 Swift 开源项目。

---

## 背景与动机

### 纪念：启动台的终结

从 macOS 26（Tahoe）起，Apple 移除了陪伴用户多年的启动台（LaunchPad），以全新的"应用程序"视图取而代之。本项目旨在用代码留住这个被删除的老朋友——忠实复刻它的交互、动画与视觉行为，让它在新系统上延续。

### 逆向工程：从 Dock 二进制还原真实行为

系统启动台的实现并不开源。本项目通过对 `/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock` 二进制执行 `strings` 提取、偏好设置读取和资源文件分析，系统性还原了以下核心技术维度的真实行为（完整 12 维度见参考文档）：

- 网格布局（`springboard-columns` / `springboard-rows` 偏好驱动，按屏幕宽度自适应）
- 背景模糊（`CABackdropLayer` + 高斯/可变模糊，非 `NSVisualEffectView`）
- 动画行为（`WASpringTimingFunction` 弹性时序、magic zoom 入场、DIGDURATION 长按检测）
- 搜索（`ECTextInputLayer` 即时过滤，非独立覆盖层）
- 文件夹（`ECSBGroupPager` 分页，内联展开覆盖层）
- 分页（离散翻页，非连续滚动）
- 拖拽（6 种拖拽状态机：重排/跨页/建文件夹/拖出/删除/边缘自动翻页）
- 辅助功能（`AXReduceMotionObserver` / `AXReduceTransparencyObserver` 自适应回退）

完整的逆向分析记录见 [`docs/原始app技术实现参考.md`](docs/原始app技术实现参考.md)。

### 工程实践：TDD + Swift 6 严格并发

LaunchPad 足够复杂——44 个源文件、1086 测试、SQLite 持久化、AppKit 视图层、全局快捷键、FSEvents 监控——是验证现代 Swift 工程方法论的理想载体。本项目将 **TDD（测试驱动开发）** 和 **Swift 6 严格并发模式** 设为硬性约束，而非可选项。

---

## 项目状态

| 维度 | 状态 |
|------|------|
| 编译（debug） | ✅ 0 errors, 0 warnings |
| 编译（release） | ✅ 0 errors, 0 warnings |
| 测试 | ✅ 1086 tests，0 失败 |
| 行覆盖率 | 97.91%（2026-07-24 重新测量，42 个源文件，8144 行 / 170 行未覆盖） |
| 区域覆盖率 | 94.11%（2026-07-24 重新测量，2664 区域 / 157 区域未覆盖） |
| 函数覆盖率 | 93.62%（2026-07-24 重新测量，1098 函数 / 70 函数未覆盖） |
| 100% 行覆盖文件 | 23 / 42 个源文件 |
| 代码签名 | ⏳ adhoc 签名，未公证 |
| 手动功能验证 | ⏳ 0/13 执行 |

> 覆盖率于 2026-07-24 通过 `llvm-cov report` 重新测量。此前于 2026-07-10 在 34 个源文件时曾达成全部文件真实 100%（`llvm-cov show` 逐文件验证）。当前因新增 8 个源文件（交互协调器、布局域状态、SQLite 事务、拖放会话等），覆盖率有待重新收敛。

---

## 技术栈

| 维度 | 选型 | 说明 |
|------|------|------|
| 编程语言 | Swift 6.0 | `swift-tools-version: 6.0`，启用严格并发模式 |
| 目标平台 | macOS 14+（Sonoma） | `platforms: [.macOS(.v14)]` |
| 构建工具 | Swift Package Manager | 零外部依赖，纯 SPM 管理 |
| UI 框架 | AppKit | `NSCollectionView` / `NSPanel` / `NSVisualEffectView` |
| 持久化 | SQLite3 | 直接使用 C API（`import SQLite3`） |
| 测试框架 | Swift Testing | `@Suite` / `@Test` / `#expect`，已完全迁移，零 XCTest 残留 |
| 并发模型 | Swift 6 严格并发 | `@MainActor` / `@Sendable` / `Sendable` 协议约束 |
| 系统集成 | CGEventTap / FSEvents / NSWorkspace / SMAppService | 全局快捷键 / 文件监控 / 应用扫描 / 登录项 |

### 选型理由

**AppKit 而非 SwiftUI**：主要原因是性能。启动台需要同时渲染数十个图标、实时拖拽预览、多层动画叠加，AppKit 提供更精细的控制（`NSCollectionView` 的 diffable data source、`NSPanel` 的 `.nonactivatingPanel` 行为、`CALayer` 级动画），且能直接与系统底层交互，避免 SwiftUI 的抽象层开销。

**裸 SQLite 而非 ORM**：本项目的 SQL 交互简单（5 张表、基础 CRUD + 级联删除 + 重排序），裸 SQLite 足以胜任且零依赖。未来若数据层复杂度增长，有考虑引入 ORM 框架（如 GRDB）。

---

## 架构设计

### 五层分层

```
LaunchPadProtocols          ← 协议层：纯协议 + 数据模型，零实现依赖
└── LaunchPad               ← 核心库
    ├── App/                ← 应用层：AppDelegate / WindowController / 生命周期
    ├── Controllers/        ← 控制层：ViewController / DragController / KeyboardNavigator
    ├── Models/             ← 模型层：DragSession
    ├── Services/           ← 服务层：AppScanner / SearchEngine / IconCache / FileWatcher / LayoutProjection / ScanBatch
    ├── Views/              ← 视图层：CollectionView / Cells / FolderOverlay / SearchBar / Coordinator
    ├── Storage/            ← 存储层：Schema / StorageManager / SQLiteTransaction / LayoutDomainState
    └── Utilities/          ← 工具层：AnimationRunner / GridLayoutCalculator / ErrorRecovery
└── LaunchPadApp            ← 可执行入口（main.swift）
```

### 协议驱动依赖注入

项目定义了 11 个核心协议（`Protocols.swift`），将所有外部依赖抽象为接口：

| 协议 | 职责 | 对应实现 |
|------|------|---------|
| `ItemReading` | 只读数据查询 | `StorageManager` |
| `ItemWriting` | 数据写入/重排 | `StorageManager` |
| `LayoutMutating` | 原子布局变更 | `StorageManager` |
| `ImageStoring` | 图标磁盘读写 | `StorageManager` |
| `DataStoring` | 以上三者组合 | `StorageManager` |
| `AppScanning` | 应用目录扫描 | `AppScanner` |
| `IconProviding` | 系统图标获取 | `AppScanner` 内部 |
| `FileSystemService` | 文件系统操作 | `AppScanner` 内部 |
| `IconCaching` | 图标缓存 | `IconCache` |
| `HotkeyManaging` | 全局快捷键 | `HotkeyManager` |
| `Scheduler` | 延时调度 | `SearchDebouncer` |

**DI 与 TDD 的关系**：协议驱动 DI 是 100% 覆盖率可达的前置条件。每个协议都有对应的 Mock 类（`MockProtocols.swift`），测试通过注入 Mock 精确控制行为——模拟抛错、返回空值、记录调用次数——从而覆盖所有分支路径。没有这层抽象，系统单例（`NSWorkspace` / `NSApp` / `CGEventTap`）在测试环境中不可控，100% 覆盖不可能达成。

---

## TDD 工程约束

TDD 是本项目的硬性约束，而非开发风格偏好。以下从原则、架构、方法论三个层面说明其在项目中的具体实践。

### 核心原则

#### RED → GREEN → REFACTOR

每个功能单元严格遵循三步循环：

1. **RED（测试先行）**：先写一个失败的测试，明确"要做什么"和"完成标准是什么"。测试必须编译通过但断言失败。
2. **GREEN（最小实现）**：写恰好能让测试通过的代码，不多做。不预设未来需求，不添加未被测试覆盖的分支。
3. **REFACTOR（持续重构）**：在测试全绿的保护下重构代码——消除重复、改善命名、提取方法、调整结构。每步重构后立即验证测试仍全绿。

#### 100% 行覆盖硬性指标

项目将"每个源文件行覆盖率 100%"设为发布阻塞项。当前状态：42 个源文件中 23 个已达 100%，整体行覆盖率 97.91%，历史曾于 2026-07-10 达成全部 34 个源文件 100%。这意味着：

- 每条 `guard else` 的 early-return 分支必须有测试触发
- 每个 `if let` 的 nil 路径和 non-nil 路径都要覆盖
- 每个 `switch` 的 `default` 分支都要有对应测试
- 每个错误处理分支（`catch` / `try?` / `throw`）都要被实际触发

#### 无死代码容忍

未被测试覆盖的代码被视为缺陷而非冗余。对于 LLVM 覆盖率工具的误报（如 ternary 表达式的 entry region count=0 但两条分支都已执行），通过重构消除歧义而非忽略：

- `itemsByPage[id] ?? []` → 改为 `allPages.compactMap { itemsByPage[$0.id] }`（消除 if-let/else region）
- `item.app?.x ?? item.group?.x ?? ""` → 改为显式 `if let / else if / else`（避免 LLVM 误报）

### 测试架构

#### Swift Testing 框架

主力测试框架为 Swift Testing，使用其原生宏：

```swift
@Suite("SQLite Schema")
struct SchemaTests {
    @Test("setupSchema 在空数据库上成功创建所有表")
    func setupSchema_createsAllTables() {
        let db = openMemoryDB()
        defer { sqlite3_close(db) }
        Schema.setupSchema(db: db!)
        // ...
        #expect(tables.contains("items"))
    }
}
```

所有测试统一使用 Swift Testing，已完成从 XCTest 的完整迁移，零残留。

#### 依赖注入模式

所有协议都有对应的 Mock 类，具备以下能力：

- **可编程返回值**：`fetchResult` / `insertError` / `shouldThrow` 等属性控制 Mock 行为
- **调用记录**：`fetchCallCount` / `saveCallCount` / `reorderedParentIds` 等属性验证副作用
- **错误注入**：每个方法都可注入特定 `Error`，触发调用方的错误处理分支

测试辅助工厂 `TestDataFactory` 枚举提供标准数据构造器（`makePageItem` / `makeAppInfo` / `makeGroupInfo` / `makeAppItems`），确保测试数据一致性。

#### 注入钩子模式

对于无法通过协议抽象的系统依赖（动画完成回调、系统无障碍设置、主线程调度），采用统一的**"可注入属性 + 默认走真实实现"**模式：

```swift
// 生产代码：默认走真实 NSAnimationContext
var runAnimated: (@MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void) = { duration, action in
    NSAnimationContext.runAnimationGroup(after: duration) { action() }
}

// 测试代码：注入同步立即执行
sut.runAnimated = { _, action in action() }  // 测试中动画完成回调被确定性地触发
```

项目中的注入钩子包括：

| 注入点 | 默认实现 | 测试用途 |
|--------|---------|---------|
| `runAnimated` | `NSAnimationContext.runAnimationGroup` | 同步触发动画完成闭包 |
| `mainAsyncRunner` | `DispatchQueue.main.async` | 同步执行主线程任务 |
| `hideCompletionRunner` | 真实动画完成回调 | 触发隐藏完成分支 |
| `accessibilitySettingsProvider` | `AccessibilitySettings.current()` | 注入 Reduce Motion / Reduce Transparency 状态 |
| `schemaSetup` | `Schema.setupSchema(db:)` | 注入错误 SQL 触发 prepare 失败分支 |
| `storageFactory` | 真实 `StorageManager` 初始化 | 注入抛错工厂测试损坏恢复 |
| `runningInstanceChecker` | `NSRunningApplication` 查询 | 测试多实例防护逻辑 |

这一模式彻底解决了 headless 测试环境中 `NSAnimationContext.completionHandler` 不触发、以及 `UserDefaults` 注入系统无障碍设置不可靠的两大根因。

### 覆盖率方法论

#### 测量工具链

覆盖率测量使用 LLVM 工具链：

```bash
# 全量编译运行 + 收集覆盖率（Task 21 后全量测试可完整退出）
swift test --enable-code-coverage --disable-sandbox --no-parallel

# 合并所有 profraw
xcrun llvm-profdata merge -sparse <profraw目录>/*.profraw -o default.profdata

# 逐文件验证 0 计数执行行（真实 100% 判据）
BIN=$(find .build -name LaunchPadPackageTests -type f -path "*MacOS*" | grep -v dSYM | head -1)
xcrun llvm-cov show "$BIN" -instr-profile=default.profdata --ignore-filename-regex=".*Tests.*"
```

**判据**：`llvm-cov report` 的行覆盖率数字存在噪声（swiftc/llvm-cov 的函数入口段计数器未递增误报），**以 `llvm-cov show` 输出中每个源文件段内"计数列为 0 的执行行数量 = 0"为准**。

#### 关键陷阱与规避

**陷阱一：dSYM 误匹配**

`find .build -name LaunchPadPackageTests -type f -path "*MacOS*"` 会命中 dSYM 包内的 DWARF 文件而非真实测试二进制，导致 `llvm-cov show` 对源文件输出空，被误读为"全 0 覆盖"或"grep 列索引问题"。

**规避**：必须用 `grep -v dSYM` 过滤，取出真实二进制。

**陷阱二：按套件过滤运行**

全量 `swift test --disable-sandbox --no-parallel` 可完整退出并产生 Swift Testing summary，零残留进程。P0 release gate 由 `scripts/test-release.sh` 统一编排。

**规避**：全量测试可完整退出，但覆盖率收集仍建议按套件过滤运行（`--filter "<Suite名子串>"`），确保每个 profraw 正确落盘后由 `llvm-profdata merge` 合并。

**陷阱三：测试自身导致覆盖率数据丢失**

`SchemaTests` 曾有一个测试向 `setupSchema(db:)` 传入**已 `sqlite3_close` 释放的悬空指针**，在 SwiftPM 测试进程中触发 `abort`（signal 5）。这导致**整个 SchemaTests 进程的覆盖率数据被丢弃**——包括本应被覆盖的错误分支，极具迷惑性（成功路径被其他套件覆盖，表面上只有错误行"恰好"为 0）。

**规避**：移除 freed-pointer 测试；为 `setupSchema` 增加可注入 `statements:` 参数，由 `ensureVersionRecord` 的 `checkSQL` / `insertSQL` 注入语法错误 SQL，使 `sqlite3_prepare_v2` 失败分支被安全、确定地触发。

#### 无法消除的死代码区域

部分分支在测试环境中客观不可达，需识别并接受：

- 弱引用 `guard let self else { return }` 的 else 分支（除非主动释放 self）
- `NSScreen.main` 为 nil 的 fallback（测试环境总有 main screen）
- `sqlite3_open` 失败但 db 仍为 nil（macOS 几乎不可能）
- 通知 callback 已被 stop 但仍触发的竞态场景
- `AppDelegate` / `LaunchPadWindowController` 中隔离到系统边界的真实 NSWorkspace/SMAppService/CGEventTap 调用路径（Task 21 显式隔离，仅在生产环境中可达）

这些区域在覆盖率报告中会显示为未覆盖，但不计入真实缺口。

---

## 快速开始

### 环境要求

- macOS 14.0+（Sonoma）
- Xcode 16+（含 Swift 6.0 工具链）
- 辅助功能权限（全局快捷键 CGEventTap 需要）

### 构建

```bash
# Debug 构建
swift build

# Release 构建（0 warnings）
swift build -c release --product LaunchPadApp

# 打包为 .app Bundle
./scripts/build-app.sh
# 产物：.build/LaunchPad.app
# 运行：open .build/LaunchPad.app
```

### 测试

```bash
# 全量测试（串行，禁用 sandbox）
swift test --disable-sandbox --no-parallel

# P0 release gate（完整门禁：编排上述命令 + 性能基准 + release build）
./scripts/test-release.sh

# 带覆盖率（按套件过滤运行，规避 AppKit 监视器卡死）
swift test --enable-code-coverage --disable-sandbox --filter "<Suite名子串>"

# 覆盖率报告
xcrun llvm-profdata merge -sparse .build/*/codecov/*.profraw -o default.profdata
BIN=$(find .build -name LaunchPadPackageTests -type f -path "*MacOS*" | grep -v dSYM | head -1)
xcrun llvm-cov report "$BIN" -instr-profile=default.profdata Sources/
```

### 首次运行

应用启动后需在 **系统设置 → 隐私与安全性 → 辅助功能** 中授权 LaunchPad，全局快捷键（Option+Space）方可生效。

---

## 项目结构

```
LaunchPad/
├── Package.swift                  # SPM 包定义
├── Sources/
│   ├── LaunchPadProtocols/        # 协议层（纯协议 + 数据模型）
│   │   ├── Models/                # ItemType / AppInfo / GroupInfo / PageItem / LayoutDropIntent
│   │   └── Protocols.swift        # 11 个核心协议
│   ├── LaunchPad/                 # 核心库
│   │   ├── App/                   # AppDelegate / WindowController / HotkeyManager
│   │   ├── Controllers/           # ViewController / DragController / KeyboardNavigator
│   │   ├── Models/                # DragSession
│   │   ├── Services/              # AppScanner / SearchEngine / LayoutProjection / ScanBatch 等
│   │   ├── Views/                 # CollectionView / Cells / FolderOverlay / SearchBar / Coordinator
│   │   ├── Storage/               # Schema / StorageManager / SQLiteTransaction / LayoutDomainState
│   │   └── Utilities/             # AnimationRunner / GridLayoutCalculator / ErrorRecovery
│   └── LaunchPadApp/              # 可执行入口（main.swift）
├── Tests/
│   └── LaunchPadTests/            # 44 个测试文件，1086 tests
│       ├── TestHelpers/           # MockProtocols / TestDataFactory
│       ├── App/                   # AppDelegate / WindowController 测试
│       ├── Controllers/           # 各 Controller 测试
│       ├── Models/                # 协议与模型测试
│       ├── Services/              # 各 Service 测试
│       ├── Storage/               # Schema / StorageManager / LayoutDomain 测试
│       ├── Utilities/             # 各 Utility 测试
│       ├── Views/                 # 各 View / Coordinator 测试
│       ├── Integration/           # 集成测试
│       └── Performance/           # 性能基准测试
├── Resources/                     # Info.plist / Entitlements
├── scripts/                       # 构建脚本 / 覆盖率 / P0 release gate
└── docs/                          # 详细文档
```

---

## 文档索引

| 文档 | 内容 |
|------|------|
| [`docs/原始app技术实现参考.md`](docs/原始app技术实现参考.md) | 对系统 Dock 二进制的逆向分析，12 个技术维度的真实行为还原 |
| [`docs/coverage-progress.md`](docs/coverage-progress.md) | 测试覆盖率提升全程记录，含方法论与陷阱复盘 |
| [`docs/superpowers/findings/P1-P2-findings.md`](docs/superpowers/findings/P1-P2-findings.md) | P0 readiness gate review 遗留发现（P1/P2 级别） |
| [`docs/superpowers/plans/2026-07-21-p0-release-blockers.md`](docs/superpowers/plans/2026-07-21-p0-release-blockers.md) | P0 release blockers 完整执行计划（24 个 task，已完成） |

---

## 许可

本项目暂未设定开源许可证。如需使用代码，请联系作者。
