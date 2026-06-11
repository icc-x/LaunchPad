# LaunchPad — 全面验证报告

> **日期:** 2026-06-07
> **验证范围:** 设计文档 `specs/2026-06-06-launchpad-design.md` + 实施计划 `plans/2026-06-06-launchpad-implementation.md` vs 全部源码
> **验证方法:** 逐文件读取 33 个源码文件 + 21 个测试文件，逐章节对比设计文档 17 个规格段落
> **构建状态:** ✅ Build complete! (0 errors, 0 warnings)
> **测试状态:** ✅ 279 tests in 31 suites 全部通过
> **代码规模:** 源码 3,991 行 / 测试 3,977 行 / 测试比 1:1

---

## 一、总体评估

### 1.1 实现完成度

| 层级 | 文件数 | 代码行 | 完成度 | 评价 |
|------|--------|--------|--------|------|
| **Data Layer** (Protocols + Models + Storage) | 7 | 337 | **95%** | Schema、协议、CRUD 完整，质量优秀 |
| **Service Layer** (AppScanner + IconCache + SearchEngine) | 4 | 529 | **75%** | 核心算法正确，缺 FSEvents 和防抖 |
| **Controllers Layer** (状态机 + 协调器) | 5 | 974 | **80%** | 状态机优秀，与 UI 集成不足 |
| **App Layer** (AppDelegate + Window + Hotkey) | 3 | 603 | **70%** | 框架完成，缺多实例防护/多显示器 |
| **View Layer** (12 个视图文件) | 12 | 1,402 | **55%** | 基础布局完成，核心交互功能缺失 |
| **Utilities** | 4 | 356 | **90%** | 纯函数/常量定义完整 |
| **合计** | **35** | **3,991** | **~70%** | — |

### 1.2 测试完成度

| 模块 | 设计要求用例数 | 已覆盖 | 覆盖率 |
|------|---------------|--------|--------|
| GridLayoutCalculator | 5 | 5 | 100% |
| SearchEngine | 8 | 8 | 100% |
| StorageManager | 7 | 5 | 71% |
| AppScanner | 8 | 8 | 100% |
| WindowLifecycle | 7 | 7 | 100% |
| DragController | 9 | 9 | 100% |
| IconCache | 6 | 6 | 100% |
| FolderController | 4 | 4 | 100% |
| KeyboardNavigator | — | 17 | — |
| 错误恢复 | 6 | 6 | 100% |
| View 层纯逻辑 | 8 | 8 | 100% |
| 无障碍 | 3 | 3 | 100% |
| 搜索防抖 | 4 | 0 | **0%** |
| 首次启动集成 | 4 | 1 | 25% |
| **合计** | **~79** | **~73** | **~92%** |

---

## 二、各层逐文件评估

### 2.1 Data Layer（完成度 95%）

#### `LaunchPadProtocols/Protocols.swift` — ✅ 优秀

| 设计文档协议 | 实现状态 | 备注 |
|-------------|---------|------|
| `ItemReading` | ✅ 签名完全匹配 | Sendable 合规 |
| `ItemWriting` | ✅ insertItem/updateItem/deleteItem/reorderItems | Sendable 合规 |
| `ImageStoring` | ✅ saveImage/fetchImage | Sendable 合规 |
| `DataStoring` | ✅ 组合继承三协议 | — |
| `AppScanning` | ✅ scanDirectories/isExcluded | — |
| `IconProviding` | ✅ icon/modificationDate | — |
| `HotkeyManaging` | ✅ onToggle/register/unregister | 使用 @Sendable 闭包（改进） |
| `FileSystemService` | ✅ 三个方法 | 返回 `[String: any Sendable]`（改进） |
| `Scheduler` | ✅ schedule/cancelPending | — |

**额外引入:** `ScannedApp` 结构体（AppScanning 返回值），设计文档未显式定义但属必要。

#### `Models/` (ItemType + AppInfo + GroupInfo + PageItem) — ✅ 完全匹配

所有字段、类型、rawValue 与设计文档 §6 100% 一致。额外增加 `Codable` + `Sendable` 一致性（正向改进）。

#### `Storage/Schema.swift` — ✅ 完全匹配

5 张表（items, apps, groups, image_cache, schema_version）与设计文档 §6 SQL 定义 100% 一致。幂等创建、外键级联删除、版本号管理均正确。

#### `Storage/StorageManager.swift` — ✅ 良好

**已实现:**
- WAL 模式 + 外键约束
- 串行写入队列保证线程安全
- 事务包裹的 insert/update/delete
- LEFT JOIN 查询 + parentId 过滤
- BLOB 图标读写

**问题:**
- `fetchAllItems` 在写队列中同步执行读操作，阻塞写队列（应使用独立读队列）
- `insertItem` 和 `updateItem` 的事务/rollback 机制风格不一致
- `reorderItems` 同时更新 parent_id，跨父节点移动时可能数据错误

---

### 2.2 Service Layer（完成度 75%）

#### `Services/AppScanner.swift` — ⚠️ 核心完整，扩展缺失

**已实现:**
- ✅ .app bundle 扫描
- ✅ 过滤：无 CFBundleName、LSUIElement=YES、排除列表
- ✅ `firstLaunchPaginate`：字母排序 + 分页
- ✅ `incrementalSync`：INSERT/UPDATE/DELETE

**缺失:**
- ❌ `/System/Applications` 扫描目录（AppDelegate 只传入 2 个目录）
- ❌ 读取系统 LaunchPadLayout.plist 排除列表
- ❌ FSEvents 文件系统监控（设计文档 §7 首选方案）
- ❌ 定时轮询备选方案

#### `Services/IconCache.swift` — ⚠️ 良好，细节偏差

**已实现:**
- ✅ 双层缓存（NSCache + SQLite）
- ✅ memory → disk → live extraction 查找链
- ✅ modificationDate 缓存失效检测
- ✅ @2x 256x256px 生成

**偏差:**
- ❌ @1x 未按 128×128pt 缩放，直接存原始 PNG
- ❌ 未按 cell 尺寸缩放避免内存浪费
- ⚠️ 磁盘缓存失效时比较 TIFF 数据，效率低

#### `Services/SearchEngine.swift` — ✅ 算法优秀

**已实现:**
- ✅ 评分完全匹配：prefix=100, word-prefix=75, substring=50, bundleId=25
- ✅ 大小写不敏感
- ✅ LRU 结果缓存（50 条）
- ✅ 自实现 LRUCache（双向链表 + 字典）

**缺失（体现在调用方 ViewController/SearchBar）:**
- ❌ 100ms 防抖
- ❌ 后台线程搜索
- ❌ Backspace 立即响应不防抖

#### `Services/LayoutPersistence.swift` — ✅ 基本完整

实现 saveLayout + loadLayout。代码自注释 N+1 查询和事务支持缺失。

---

### 2.3 Controllers Layer（完成度 80%）

#### `WindowLifecycle.swift` — ✅ 优秀（项目最佳组件之一）

- ✅ 完整 5 状态：hidden/opening/visible/closing/launching
- ✅ 所有设计文档要求的状态转换路径
- ✅ 防抖：中间状态下 toggle 被忽略
- ✅ WindowLifecycleDelegate 协议完整

#### `KeyboardNavigator.swift` — ✅ 完全匹配

- ✅ idle/search/edit 三态
- ✅ 8 种按键映射完全匹配设计文档 §13 键位表
- ✅ ESC 二级行为（search → clearSearch → idle → closeWindow）

#### `DragController.swift` — ⚠️ 数据层完整，UI 集成缺失

**已实现（状态机数据层）:**
- ✅ idle/jiggling/dragging 三态 + substate
- ✅ 长按 0.5s 触发，10px 移动阈值
- ✅ 边缘悬停 1.5s 翻页，图标悬停 0.8s 创建文件夹
- ✅ commitReorder / rollbackReorder

**缺失（UI 集成）:**
- ❌ NSCollectionView 拖拽 delegate 方法（pasteboardWriter/validateDrop/acceptDrop）
- ❌ 长按手势（NSPressGestureRecognizer）连接到 UI
- ❌ 抖动动画启动（startJiggling 调用）
- ❌ ✕ 删除按钮显示
- ❌ 拖拽预览生成
- ❌ 跨页拖拽 section 间移动

#### `FolderController.swift` — ⚠️ 基本完整

**已实现:** createFolder / addToFolder / dissolveFolder / removeFromFolder / renameFolder

**缺失:**
- ❌ 移出时自动检测剩余 1 个并解散
- ❌ 预览图合成（取前 9 个子图标 → 3×3 缩略图 → 缓存到 image_cache）

#### `LaunchPadViewController.swift` — ⚠️ 框架完成，交互不完整

**已实现:**
- ✅ 6 个子视图组装 + Auto Layout
- ✅ 搜索/清空/结果展示
- ✅ 页面导航（navigateToPage）
- ✅ 项目选择（应用启动 + 文件夹打开）
- ✅ 键盘事件委托
- ✅ DiffableDataSource 数据加载

**缺失:**
- ❌ 搜索防抖 100ms（直接调用 searchEngine，无 debounce）
- ❌ 后台线程搜索（主线程同步执行）
- ❌ `executeAction(.closeWindow)` 是空 break（应调用 lifecycle）
- ❌ `executeAction(.exitEditMode)` 是空 break（应退出 jiggle 模式）
- ❌ `moveUp/moveDown/selectNext` 行为未实现（空 break）

---

### 2.4 App Layer（完成度 70%）

#### `AppDelegate.swift` — ⚠️ 框架完整

**已实现:**
- ✅ LSUIElement 模式
- ✅ 菜单栏图标 + 右键菜单
- ✅ 完整服务初始化链
- ✅ 首次扫描 + 增量同步
- ✅ SQLite 损坏恢复

**缺失:**
- ❌ 登录自启动（SMAppService.mainApp.register()）
- ❌ 多实例防护（NSRunningApplication 检测）
- ❌ `/System/Applications` 扫描
- ❌ FSEvents 监控

#### `HotkeyManager.swift` — ⚠️ 核心完整

**已实现:**
- ✅ CGEventTap 两步状态机
- ✅ NSEvent local monitor
- ✅ 正确的 Unmanaged 内存管理
- ✅ 测试模拟方法

**缺失:**
- ❌ AXIsProcessTrusted() 权限检查
- ❌ 快捷键冲突处理
- ❌ 权限拒绝 UI 引导

#### `LaunchPadWindowController.swift` — ⚠️ 核心完整，关键偏差

**已实现:**
- ✅ NSPanel 无边框 + 毛玻璃
- ✅ 焦点丢失检测
- ✅ AccessibilityObserver 集成
- ✅ WindowLifecycleDelegate 5 状态处理

**关键偏差:**

| 项目 | 设计文档 | 实际代码 | 影响 |
|------|---------|---------|------|
| 窗口级别 | `.screenSaver` (1000) | `.statusBar` (25) | 无法覆盖屏幕保护程序等高级别窗口 |
| 多显示器 | 鼠标所在屏幕 | `NSScreen.main` 硬编码 | 多屏用户无法在当前屏幕显示 |
| 视觉效果 state | `.followsWindowActiveState` | `.active` | 窗口非活跃时效果不跟随 |
| 打开动画 | Spring(0.75) 缩放 | 简单 alpha 渐变 | 视觉体验差距大 |

---

### 2.5 View Layer（完成度 55%）

#### 已完成的视图组件

| 文件 | 完成度 | 说明 |
|------|--------|------|
| `AppGridCollectionView.swift` | 70% | DiffableDataSource 完整，缺拖拽 delegate |
| `AppGridFlowLayout.swift` | 90% | 垂直居中 + snap-to-page 完整 |
| `AppIconCell.swift` | 50% | 基础布局+抖动，缺删除按钮/自适应尺寸/Reduce Motion |
| `FolderCell.swift` | 40% | 3×3 网格基础，缺毛玻璃背景/可编辑名称 |
| `FolderOverlayView.swift` | 50% | 毛玻璃面板+点击外部关闭，缺响应式尺寸/分页/scale动画 |
| `SearchBar.swift` | 60% | NSSearchField+显示隐藏，缺 100ms 防抖 |
| `PageControl.swift` | 85% | 圆点指示器+点击跳转，颜色细节偏差 |
| `PageScrollView.swift` | 30% | 只有 targetPage 纯函数，scrollWheel 未重写 |
| `EmptyStateView.swift` | 100% | 完整实现 |
| `DiffableDataSourceBuilder.swift` | 100% | 完整实现 |

#### View 层关键缺失功能

1. **自定义分页滚动（scrollWheel 重写）** — PageScrollView 是空壳，分页依赖 FlowLayout 的 targetContentOffset
2. **NSCollectionView 拖拽** — 无 pasteboardWriter/validateDrop/acceptDrop delegate
3. **编辑模式 UI** — 长按手势、抖动动画启动、✕ 删除按钮均未连接
4. **应用启动动画** — scale 0.95→1.0→2.0 + alpha→0 三阶段未实现
5. **已运行应用小圆点指示器** — 未实现
6. **FolderOverlayView 响应式尺寸** — 硬编码 320×360
7. **图标尺寸自适应** — AppIconCell 硬编码 64×64

---

### 2.6 Utilities Layer（完成度 90%）

| 文件 | 完成度 | 说明 |
|------|--------|------|
| `GridLayoutCalculator.swift` | 100% | 列数/行数/每页数完全匹配设计文档表格 |
| `AnimationConstants.swift` | 100% | 10 种动画参数全部匹配设计文档 §12 |
| `AccessibilityObservers.swift` | 85% | 设置监听完整，缺 Increase Contrast Cell 层应用 |
| `ErrorRecovery.swift` | 80% | 6 种策略枚举完整，handleSQLiteCorruption 总返回 deleteAndRescan |

---

## 三、架构质量评估

### 3.1 四层架构一致性 — ✅ 优秀

```
┌─────────────────────────────────────────────────────────────────┐
│  App Layer    AppDelegate · HotkeyManager · WindowController    │  ✅ 一致
├─────────────────────────────────────────────────────────────────┤
│  View Layer   12 个视图文件 + DiffableDataSourceBuilder          │  ✅ 一致
├─────────────────────────────────────────────────────────────────┤
│  Controllers  LaunchPadVC · DragController · WindowLifecycle    │  ⚠️ 设计文档归为 Service
├─────────────────────────────────────────────────────────────────┤
│  Services     AppScanner · IconCache · SearchEngine             │  ✅ 一致
├─────────────────────────────────────────────────────────────────┤
│  Data Layer   StorageManager · Schema · Protocols · Models      │  ✅ 一致
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 依赖方向 — ✅ 基本正确

- ✅ Views 不依赖具体 Storage（通过协议访问）
- ✅ Controllers 只依赖协议（ItemWriting/Reading），不依赖 StorageManager
- ✅ AppDelegate 是组装根，负责依赖注入
- ⚠️ `AppGridCollectionView` 直接引用 `IconCache`（具体类而非协议）

### 3.3 协议驱动的依赖注入 — ✅ 优秀

| 协议 | 生产实现 | Mock 实现 | 可测试性 |
|------|---------|----------|---------|
| ItemReading | StorageManager | MockItemReader | ✅ |
| ItemWriting | StorageManager | MockItemWriter | ✅ |
| ImageStoring | StorageManager | MockImageStore | ✅ |
| AppScanning | AppScanner | Mock（通过 FileSystemService 注入） | ✅ |
| IconProviding | SystemIconProvider | MockIconProvider | ✅ |
| FileSystemService | SystemFileSystemService | MockFileSystemService | ✅ |
| HotkeyManaging | HotkeyManager | MockHotkeyManager | ✅ |
| Scheduler | DispatchQueueScheduler | MockScheduler | ✅ |

### 3.4 Sendable / Swift 6 并发合规 — ✅ 良好

- 所有协议标记 `Sendable`
- 所有模型结构体标记 `Sendable` + `Codable`
- `@unchecked Sendable` 仅用于确实线程安全的类型（NSCache、DispatchQueue）
- `nonisolated(unsafe)` 使用极少（仅 AppDelegate 的 key event 处理，因 NSEvent non-Sendable）

### 3.5 代码风格 — ✅ 良好

- MARK 注释分隔一致
- 中文注释说明业务逻辑
- 英文注释说明技术实现
- 命名遵循 Swift API Design Guidelines

---

## 四、缺失功能清单（按优先级排序）

### P0 — 核心功能缺失（影响基本使用）

| # | 缺失项 | 设计文档章节 | 当前状态 | 工作量估计 |
|---|--------|------------|---------|-----------|
| 1 | **NSCollectionView 拖拽 delegate** | §10 | 完全缺失 | 2-3 天 |
| 2 | **编辑模式 UI 集成**（长按→抖动→✕按钮） | §10 | DragController 数据层有，UI 未连接 | 2 天 |
| 3 | **搜索防抖 100ms** | §9 | 完全缺失 | 0.5 天 |
| 4 | **PageScrollView 自定义滚动** | §5 | scrollWheel 未重写 | 1-2 天 |
| 5 | **应用启动动画**（三阶段 scale+fade） | §12 | 仅 alpha 渐变 | 0.5 天 |

### P1 — 重要功能缺失（影响用户体验）

| # | 缺失项 | 设计文档章节 | 当前状态 | 工作量估计 |
|---|--------|------------|---------|-----------|
| 6 | **多显示器支持** | §3 | NSScreen.main 硬编码 | 0.5 天 |
| 7 | **窗口级别改为 .screenSaver** | §3 | 当前 .statusBar | 0.5 小时 |
| 8 | **`/System/Applications` 扫描** | §7 | 只扫描 2 个目录 | 0.5 小时 |
| 9 | **FSEvents 文件系统监控** | §7 | 完全缺失 | 1-2 天 |
| 10 | **文件夹弹窗响应式尺寸** | §11 | 硬编码 320×360 | 0.5 天 |
| 11 | **FolderOverlayView scale 弹出动画** | §11 | 仅 alpha | 0.5 天 |
| 12 | **文件夹内部网格分页** | §11 | 单个 ScrollView | 1 天 |
| 13 | **已运行应用小圆点指示器** | §12 | 未实现 | 0.5 天 |
| 14 | **后台线程搜索** | §9 | 主线程同步 | 0.5 天 |
| 15 | **文件夹自动解散**（剩余 1 个时） | §11 | 未检测 | 0.5 天 |

### P2 — 增强功能（不阻塞使用）

| # | 缺失项 | 设计文档章节 | 工作量估计 |
|---|--------|------------|-----------|
| 16 | 登录自启动 SMAppService | §1 | 0.5 天 |
| 17 | 多实例防护 | §1 | 0.5 天 |
| 18 | CGEventTap 权限检查+引导 | §4 | 1 天 |
| 19 | 快捷键冲突处理 | §4 | 1 天 |
| 20 | AppIconCell 图标尺寸自适应 | §5 | 0.5 天 |
| 21 | FolderCell 毛玻璃背景 | §11 | 0.5 天 |
| 22 | FolderCell 可编辑名称 | §11 | 1 天 |
| 23 | VoiceOver grid 结构 | §14 | 1 天 |
| 24 | Increase Contrast Cell 应用 | §14 | 0.5 天 |
| 25 | 拖拽预览生成 | §10 | 0.5 天 |
| 26 | 文件夹预览图合成缓存 | §11 | 1 天 |
| 27 | 图标 @1x 128×128 缩放 | §8 | 0.5 小时 |
| 28 | 搜索结果计数显示 | §9 | 0.5 小时 |
| 29 | LoginItems 排除列表读取 | §7 | 0.5 天 |
| 30 | 性能基准测试（1000+ 图标） | §17 | 1 天 |

---

## 五、代码质量亮点

### 5.1 优秀设计模式

| 模式 | 应用位置 | 评价 |
|------|---------|------|
| **协议驱动 DI** | 全部 Service 层 8 个协议 | 高度可测试，mock 注入干净 |
| **状态机** | WindowLifecycle (5态) / DragController (3态) | 转换路径完整，防抖正确 |
| **纯函数提取** | GridLayoutCalculator / targetPage / buildSnapshot | 无副作用，易测试 |
| **值类型模型** | 所有 struct + Sendable | 轻量、不可变、DiffableDataSource 友好 |
| **策略模式** | AnimationFallback / BackgroundMaterial / ContrastFallback | 无障碍回退优雅 |

### 5.2 测试工程质量

| 指标 | 数值 |
|------|------|
| 测试总数 | 279 |
| 测试套件数 | 31 |
| 源码行数 | 3,991 |
| 测试行数 | 3,977 |
| 测试/源码比 | 1.00:1 |
| Mock 类数 | 7 个完整实现 |
| 状态机覆盖 | 100% 转换路径 |

### 5.3 Swift 6 并发处理

- 正确使用 `@MainActor` 隔离 UI 代码
- `Sendable` 一致性覆盖所有跨边界类型
- `nonisolated(unsafe)` 使用极少且有注释说明原因
- `@unchecked Sendable` 仅用于确实线程安全的类型

---

## 六、已知技术债务

| 编号 | 问题 | 位置 | 风险 | 建议 |
|------|------|------|------|------|
| TD-1 | `unregisterGlobalHotkey` 中 passUnretained 与注册时 passRetained 不对称 | HotkeyManager:117 | 中（潜在 use-after-free） | 统一由类级 retained 引用管理 |
| TD-2 | `fetchAllItems` 在写队列中同步执行读操作 | StorageManager | 低（性能） | 引入独立读队列 |
| TD-3 | `insertItem` 和 `updateItem` 事务风格不一致 | StorageManager | 低（可维护性） | 统一事务管理方式 |
| TD-4 | `handleSQLiteCorruption` 总返回 deleteAndRescan | ErrorRecovery | 低（功能） | 添加 PRAGMA integrity_check |
| TD-5 | IconCache 磁盘失效时比较 TIFF 数据 | IconCache | 低（性能） | 比较 modificationDate 哈希 |
| TD-6 | `AppGridCollectionView` 直接引用 `IconCache` 具体类 | AppGridCollectionView | 低（架构） | 抽象为协议 |

---

## 七、总结

### 整体评分

| 维度 | 评分 | 说明 |
|------|------|------|
| **架构设计** | ⭐⭐⭐⭐⭐ | 四层清晰、协议驱动 DI、依赖方向正确 |
| **数据层完成度** | ⭐⭐⭐⭐⭐ | Schema/模型/协议/CRUD 完整且质量高 |
| **Service 层完成度** | ⭐⭐⭐⭐ | 核心算法正确，扩展功能缺失 |
| **Controller 层完成度** | ⭐⭐⭐⭐ | 状态机优秀，UI 集成不足 |
| **View 层完成度** | ⭐⭐⭐ | 基础框架搭建，核心交互功能缺失 |
| **测试质量** | ⭐⭐⭐⭐⭐ | 279 测试、状态机全覆盖、Mock 完整 |
| **代码风格** | ⭐⭐⭐⭐ | 命名规范、注释清晰、Swift 6 合规 |
| **总体完成度** | ⭐⭐⭐½ | **约 70%**，基础设施优秀，交互层待完善 |

### 结论

项目在**架构设计、数据层、测试工程**方面质量优秀，四层架构划分清晰，协议驱动的 DI 设计使得核心逻辑高度可测试。279 个测试用例覆盖了所有状态机转换路径和纯函数边界条件。

主要差距集中在 **View 层的交互功能实现**——NSCollectionView 拖拽、自定义分页滚动、编辑模式 UI 连接、应用启动动画等设计文档中定义的核心交互行为停留在框架搭建阶段。这些功能的底层数据模型和状态机已经就绪（DragController、WindowLifecycle 等），需要的是 UI 层的连接和实现。

**建议下一步优先实现：** P0 的 5 项（#1-#5），预计 6-8 个工作日可将完成度提升至 ~85%。
