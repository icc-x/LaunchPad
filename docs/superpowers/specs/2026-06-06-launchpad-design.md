# LaunchPad macOS 全功能复刻 — 设计文档

> 日期: 2026-06-06
> 状态: 设计完成，待实现
> 目标平台: macOS 26+
> 框架: 纯 AppKit + Swift

---

## 1. 概述

复刻 macOS LaunchPad 应用启动器，作为独立 macOS 应用运行。全屏毛玻璃覆盖层，展示已安装应用图标网格，支持多页滑动、搜索、文件夹、拖拽排序等完整功能。

### 应用身份

- **类型**: LSUIElement = YES（Agent 应用，不在 Dock 显示图标）
- **常驻方式**: 菜单栏图标（NSStatusItem），右键菜单提供"打开 LaunchPad"和"退出"
- **启动方式**: 登录自启动（SMAppService.mainApp.register()，可选）
- **多实例防护**: 通过 NSRunningApplication 检测已有实例，激活而非重复启动

### 核心决策

| 决策项 | 选择 | 理由 |
|--------|------|------|
| UI 框架 | 纯 AppKit | 控制力强，NSCollectionView 天然支持网格+拖拽 |
| 窗口模式 | 全屏覆盖层 | 与原版一致，screenSaver 级别 |
| 数据存储 | 独立 SQLite | 不干扰系统 Dock，首次从系统 DB 导入 |
| 全局热键 | CGEventTap + 应用内 NSEvent | Option+Space 全局唤起 + 应用内快捷键 |
| 网格分页 | 单 CollectionView + 自定义横向 FlowLayout | 跨页拖拽自然，数据源简单 |
| 数据模型 | struct 值类型 | 轻量、不可变、适配 DiffableDataSource |
| 拖拽实现 | NSCollectionView 内置拖拽 | 系统级支持，自动生成预览 |
| 动画引擎 | NSAnimationContext + Core Animation | 原生 API，CASpringAnimation 弹性动画 |

---

## 2. 系统架构

### 四层架构

```
┌─────────────────────────────────────────────────────────────┐
│                        App Layer                            │
│  AppDelegate · HotkeyManager · LaunchPadWindowController    │
├─────────────────────────────────────────────────────────────┤
│                        View Layer                           │
│  PageScrollView · SearchBar · PageControl · AppIconCell     │
│  FolderCell · FolderOverlayView                             │
├─────────────────────────────────────────────────────────────┤
│                       Service Layer                         │
│  AppScanner · IconCache · DragController · SearchEngine     │
├─────────────────────────────────────────────────────────────┤
│                        Data Layer                           │
│  StorageManager (SQLite) · Models (struct)                  │
└─────────────────────────────────────────────────────────────┘
```

### 项目结构

```
LaunchPad/
├── App/
│   ├── AppDelegate.swift
│   ├── LaunchPadWindowController.swift
│   └── HotkeyManager.swift
├── Views/
│   ├── PageScrollView.swift          # NSScrollView 分页容器
│   ├── AppGridCollectionView.swift   # NSCollectionView 网格
│   ├── AppGridFlowLayout.swift       # 自定义横向 FlowLayout
│   ├── AppIconCell.swift             # 应用图标 cell
│   ├── FolderCell.swift              # 文件夹 cell
│   ├── FolderOverlayView.swift       # 文件夹展开弹窗
│   ├── SearchBar.swift               # 搜索输入框
│   ├── PageControl.swift             # 页码指示点
│   └── EmptyStateView.swift          # 搜索无结果
├── Controllers/
│   ├── LaunchPadViewController.swift # 主控制器
│   └── DragController.swift          # 拖拽状态机
├── Services/
│   ├── AppScanner.swift              # 应用扫描
│   ├── IconCache.swift               # 图标缓存
│   ├── SearchEngine.swift            # 搜索逻辑
│   └── LayoutPersistence.swift       # 布局存取
├── Models/
│   ├── AppInfo.swift                 # 应用信息
│   ├── GroupInfo.swift               # 文件夹信息
│   ├── PageItem.swift                # 页面项 (app/group)
│   └── ItemType.swift                # 类型枚举
├── Storage/
│   ├── StorageManager.swift          # SQLite 管理器
│   └── Schema.swift                  # 数据库 Schema
├── Utilities/
│   ├── GridLayoutCalculator.swift    # 网格尺寸计算
│   ├── AnimationConstants.swift      # 动画参数
│   └── AccessibilityObservers.swift  # 无障碍设置监听
└── Resources/
    └── Assets.xcassets
```

---

## 3. 窗口与背景层

### 窗口配置

- **级别**: `NSWindow.Level.screenSaver` — 覆盖所有窗口
- **尺寸**: 全屏（当前鼠标所在屏幕）
- **样式**: `styleMask = [.borderless]`, `isOpaque = false`, `backgroundColor = .clear`
- **行为**: `canBecomeKey = true`, `canBecomeMain = true`, `hidesOnDeactivate = false`

### 毛玻璃背景

```
NSWindow
└── ContentView
    └── NSVisualEffectView
        ├── blendingMode: .behindWindow
        ├── material: .hudWindow
        ├── state: .followsWindowActiveState
        └── maskToBounds: true
            └── LaunchPadContentView (所有 UI 内容)
```

- 无障碍回退：监听 `AccessibilityReduceTransparencyObserver`，开启时替换为纯色背景 `NSColor.windowBackgroundColor`

### 多显示器

- 在鼠标所在屏幕 (`NSEvent.mouseLocation` → `NSScreen.screen(at:)`) 上显示
- 监听 `NSApplication.didChangeScreenParametersNotification` 处理显示器热插拔

### 焦点丢失

- LaunchPad 可见时，如果应用失去焦点（用户 Cmd+Tab 或点击其他窗口），自动执行 hide 流程
- 监听 `NSApplication.didResignActiveNotification`
- 菜单栏图标点击可重新唤起

---

## 4. 全局热键

### HotkeyManager

**全局热键（CGEventTap）:**
- 监听 `.flagsChanged` 事件
- 检测 Option + Space 组合键
- 需要辅助功能权限（首次使用引导用户授权）
- 权限检查：`AXIsProcessTrusted()`
- Fallback：菜单栏图标右键菜单 + 设置中的自定义快捷键
- 快捷键冲突：如果 Option+Space 已被占用，在首次启动时提示用户选择其他快捷键或关闭冲突应用

**应用内热键（NSEvent local monitor）:**
- `keyDown` 事件拦截，处理以下按键：
  - ESC — 关闭窗口（搜索非空时先清空搜索）
  - ←/→ — 翻页
  - ↑/↓ — 网格内垂直导航
  - Enter — 启动选中应用
  - 任意字符 — 进入搜索模式

### 窗口生命周期状态机

```
hidden → (toggle) → opening → visible
visible → (toggle/ESC/click empty) → closing → hidden
visible → (click app) → launching → closing → hidden
```

---

## 5. 网格与分页

### 布局计算 — GridLayoutCalculator

根据屏幕宽度自动计算网格参数：

| 屏幕宽度 | 列数 | 行数 | 每页图标数 |
|----------|------|------|-----------|
| ≤ 1440px | 7 | 5 | 35 |
| ≤ 1728px | 9 | 5 | 45 |
| > 1728px | 10 | 5 | 50 |

- 固定 5 行
- 图标尺寸自适应：`(可用宽度 - 总间距) / 列数`
- 最小图标 64pt，最大 96pt
- 图标间距 20pt
- 上下边距：顶部 100pt（留搜索栏空间），底部 60pt（留页码空间）

### AppGridFlowLayout

自定义 `NSCollectionViewFlowLayout` 子类：
- items 从左到右、从上到下排列
- 每页是一个 section，section 间距等于屏幕宽度
- `scrollDirection = .horizontal`
- 配合 `NSScrollView.isPagingEnabled = true` 实现分页

### 分页滚动 — PageScrollView

- `NSScrollView` 子类，自定义分页逻辑（`NSScrollView` 没有原生 `isPagingEnabled` 属性）
- **分页实现**: 重写 `scrollWheel`，在 `.ended` phase 根据滚动速度和位移判断目标页，用 `NSAnimationContext` 平滑 snap 到目标页
- 双指横滑翻页：监听 `scrollWheel` 的 `.changed` 和 `.ended` phase
- 弹性回弹：第一页右滑 / 末页左滑允许轻微滚动后弹回（`horizontalScrollElasticity = .allowed`）
- 键盘翻页：←/→ 方向键，焦点在边缘时触发
- 翻页动画：`NSAnimationContext.runAnimationGroup`，duration 0.35s，easeInOut

### PageControl

- 居中底部，每个页面一个小圆点
- 当前页：白色实心圆，其他：白色空心圆
- 点击圆点可跳转到对应页面
- 搜索时隐藏

---

## 6. 数据模型与持久化

### 数据模型

```swift
enum ItemType: Int {
    case page = 1
    case app = 4
    case group = 7
}

struct PageItem: Hashable, Identifiable {
    let id: Int64
    let uuid: String
    let type: ItemType
    let ordering: Int
    let parentId: Int64?
    var app: AppInfo?
    var group: GroupInfo?
}

struct AppInfo: Hashable {
    let id: Int64
    let title: String
    let bundleId: String
    let path: String
    let storeId: String?
    let category: String?
}

struct GroupInfo: Hashable {
    let id: Int64
    var title: String
}
```

### SQLite Schema

```sql
CREATE TABLE items (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid        TEXT UNIQUE NOT NULL,
    type        INTEGER NOT NULL,  -- 1=page, 4=app, 7=group
    parent_id   INTEGER REFERENCES items(id) ON DELETE CASCADE,
    ordering    INTEGER NOT NULL,
    created_at  REAL DEFAULT (strftime('%s','now'))
);

CREATE TABLE apps (
    item_id     INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    title       TEXT NOT NULL,
    bundle_id   TEXT UNIQUE NOT NULL,
    store_id    TEXT,
    category    TEXT,
    path        TEXT NOT NULL
    -- bookmark 列省略：本地开发无需沙盒 security-scoped bookmark
);

CREATE TABLE groups (
    item_id     INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    title       TEXT NOT NULL DEFAULT 'New Folder'
);

CREATE TABLE image_cache (
    item_id     INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
    icon_1x     BLOB,
    icon_2x     BLOB,
    updated_at  REAL DEFAULT (strftime('%s','now'))
);

CREATE TABLE schema_version (
    version     INTEGER NOT NULL
);
```

### DiffableDataSource

使用 `NSDiffableDataSourceSnapshot<Section, PageItem>` 驱动 CollectionView 更新：
- Section = 一个页面
- PageItem 实现 `Hashable`，变更时自动 diff + 动画

---

## 7. 应用扫描

### AppScanner

**扫描目录：**
- `/Applications`
- `~/Applications`
- `/System/Applications`

**过滤规则（排除项）：**
- 无 `CFBundleName` 的 .app
- `LSUIElement = YES` 的后台应用
- 排除列表中的 bundle ID（读取系统 `LaunchPadLayout.plist` 的排除列表）

**同步策略：**
1. 启动时全量扫描
2. 文件系统监控方案：
   - **首选**: FSEvents API（`FSEventStreamCreate`）监控 `/Applications` 和 `~/Applications` 目录树变化
   - **备选**: 定时轮询（每 30s 比较目录内容与数据库），实现更简单但延迟更高
3. 新应用 → INSERT 到末尾页面
4. 已有应用 → UPDATE title/path
5. 已删应用 → DELETE（从 items 表级联删除）
6. 首次运行 → 按 ordering 自动分页，每页 maxPerPage 个

### 首次启动流程

1. 检测数据库是否为空（SELECT COUNT(*) FROM items）
2. 空数据库 → 全量扫描 + 创建默认页面 + 按字母顺序填充
3. 填充完成后展示 LaunchPad

---

## 8. 图标缓存

### 双层缓存

**内存层 — NSCache：**
- `NSCache<NSString, NSImage>`，countLimit = 500
- 按 bundle_id 作为 key
- 自动 LRU 淘汰

**磁盘层 — SQLite image_cache：**
- 存储 PNG 数据（@1x 和 @2x）
- 提取后首次写入，后续直接读取
- 比较 `path.modificationDate` 检测失效

**图标尺寸：**
- @1x: 128×128 pt
- @2x: 256×256 px（Retina）
- CollectionView cell 显示尺寸: 根据 GridLayoutCalculator 计算（64~96pt）
- 加载时按 cell 尺寸缩放，避免内存浪费

**图标提取：**
```swift
// 从 .app bundle 提取高分辨率图标
NSWorkspace.shared.icon(forFile: appPath)
// 兜底: NSImage(named: "NSApplicationIcon")
// 图标提取在后台线程执行，避免阻塞主线程
```

---

## 9. 搜索系统

### 搜索行为

- LaunchPad 可见时，任何键盘输入自动进入搜索（无需聚焦）
- 原位过滤：搜索结果替换当前页内容，非覆盖层
- 页码隐藏，可选显示结果计数

### 匹配算法

```swift
func match(item: PageItem, query: String) -> Int {
    let title = item.app?.title.lowercased() ?? item.group?.title.lowercased() ?? ""
    let q = query.lowercased()

    if title.hasPrefix(q) { return 100 }       // 词首匹配最高
    if title.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 75 }
    if title.contains(q) { return 50 }          // 子串匹配
    if item.app?.bundleId.lowercased().contains(q) == true { return 25 }
    return 0
}
```

### 防抖策略

- 100ms debounce
- Backspace 立即响应不防抖
- 后台线程（`DispatchQueue.global(qos: .userInitiated)`）执行搜索
- LRU 结果缓存（50 条）

### 清空搜索

- ✕ 按钮 / ESC（搜索非空时）/ 全选+Delete
- 清空后恢复原始页面布局和页码

---

## 10. 拖拽与编辑模式

### 拖拽状态机

```
idle ──(长按 0.5s)──→ jiggling ──(拖拽开始)──→ dragging
  ↑                                              │
  │ ESC/点空白                                   ├─ overEdge (1.5s) → pageChange
  │                                              ├─ overIcon (0.8s) → createGroup
  │                                              ├─ drop → reorder
  └──────────────────────────────────────────────┘
```

### 编辑模式（Jiggle Mode）

- 长按 0.5s 触发（距离阈值 < 10px，否则进入拖拽）
- 所有图标同时开始抖动：CABasicAnimation on `transform.rotation.z`，角度 ±2°~3°，duration 0.12~0.15s，autoreverses，每个 cell 随机延迟 0~0.1s
- 左上角显示 ✕ 删除按钮（淡入动画）
- 退出：ESC 或点击空白区域，图标渐停旋转，✕ 淡出

### NSCollectionView 内置拖拽

通过 NSCollectionViewDelegate 方法链实现：

- `collectionView(_:pasteboardWriterForItemAt:)` → 返回 NSPasteboardWriting（PageItem.uuid），非 nil 即表示该 item 可拖拽
- `collectionView(_:validateDrop:proposedIndexPath:dropOperation:)` → 判断 drop 目标，返回 NSDragOperation（.move / .generic）
- `collectionView(_:acceptDrop:indexPath:dropOperation:)` → 执行数据变更 + 保存布局
- 拖拽预览：`collectionView(_:draggingImageForItemsAt:with:offset:)` → 自定义拖拽时的半透明图标

### 跨页拖拽

由于单个 CollectionView 中每页是一个 section，跨页拖拽在数据源层面是 section 间的 item 移动：
- NSCollectionView 内置拖拽天然支持 section 间移动
- 拖拽到屏幕边缘时的自动翻页：在 `draggingUpdated` delegate 中检测 drop 位置是否在可视区域边缘，触发动画翻页

### 无障碍回退

- Reduce Motion 开启时：抖动改为缩放脉冲（scale 1.0→1.05→1.0），✕ 按钮直接显示无动画

---

## 11. 文件夹系统

### 文件夹外观

- 网格中显示为圆角矩形毛玻璃背景 + 3×3 缩略预览图（前9个子应用图标）
- 下方可编辑文件夹名称

### FolderOverlayView

- 居中浮动面板（60% 屏幕宽度，最大 70% 屏幕高度）
- 毛玻璃材质（`.hudWindow`）
- 内部网格最多 35 个/页，超出显示页码点
- 弹出动画：scale 0.8→1.0 + fade in，0.25s，spring(damping: 0.8)
- ESC 或点击暗化背景关闭

### 文件夹操作

| 操作 | 触发方式 | 行为 |
|------|---------|------|
| 创建 | 拖拽 A 到 B 上 hover 0.8s | 自动创建文件夹，A 和 B 入内 |
| 添加 | 拖拽到文件夹上 hover 0.8s | 追加到末尾，更新预览图 |
| 移出 | 文件夹内拖拽到弹窗外 | 移回主网格，剩余1个时自动解散 |
| 重命名 | 双击文件夹名称 | NSTextField 可编辑 |
| 删除 | 编辑模式点击 ✕ | 确认后子应用移回主网格 |
| 打开 | 点击文件夹 | 弹出 FolderOverlayView |

### 预览图生成

取前 9 个子应用图标，缩小到 40%，按 3×3 排列，用 `NSImage(size:drawIn:)` 合成。缓存到 image_cache 表。

**生成时机：**
- 文件夹创建时
- 文件夹内应用增减时
- 子应用图标更新时（检测到 path.modificationDate 变化）

### 搜索中的文件夹

- 文件夹名匹配 → 整个文件夹作为结果项
- 文件夹内 app 匹配 → 单独列出，标记所属文件夹

---

## 12. 动画系统

### 动画参数表

| 动画 | Duration | Timing | Reduce Motion 替代 |
|------|----------|--------|-------------------|
| 窗口展开 | 0.35s | Spring(damping: 0.75) | Fade 0.2s |
| 窗口收起 | 0.25s | EaseOut | Fade 0.2s |
| 应用启动 | 0.3s | EaseOut | 即时切换 |
| 翻页 | 0.35s | EaseInOut | 即时切换 |
| 图标入场 | 0.3s/个 | Spring(damping: 0.8) | 直接显示 |
| 抖动模式 | 0.13s 循环 | Autoreverse | 缩放脉冲 |
| 文件夹展开 | 0.25s | Spring(damping: 0.8) | Fade 0.15s |
| 文件夹收起 | 0.2s | EaseOut | Fade 0.15s |
| 删除（缩放淡出） | 0.3s | EaseIn | 即时删除 |
| 拖拽让位 | 0.25s | Spring(damping: 0.85) | 即时移动 |

### 实现方式

- View 级动画：`NSAnimationContext.runAnimationGroup`，macOS 14+ 支持 spring timing via `NSAnimationContext.timingFunction = CAMediaTimingFunction(...)` 
- Layer 级动画（抖动）：`CABasicAnimation` / `CASpringAnimation`
- Spring timing：`CASpringAnimation(damping: 0.75~0.85)` 用于 layer；view 级用 `NSAnimationContext` 配合 `CAMediaTimingFunction(name: .easeInEaseOut)` 模拟
- 图标入场：每个 cell 依次延迟 `colIndex * 0.02s`，从左到右"铺开"
- Reduce Motion：监听 `AccessibilityReduceMotionObserver`，所有动画回退为淡入淡出或即时切换

### 应用启动流程

1. 点击图标 → 高亮反馈（scale 0.95 → 1.0，0.1s）
2. 图标放大 + 淡出（scale → 2.0, opacity → 0，0.3s）
3. 同时 LaunchPad 整体淡出
4. `NSWorkspace.shared.open(appURL)` 启动应用
5. 关闭 LaunchPad 窗口
6. 已运行应用：显示小圆点指示器，再次点击 activate 已有窗口

---

## 13. 键盘导航

| 按键 | 空闲状态 | 搜索状态 | 编辑模式 |
|------|---------|---------|---------|
| ESC | 关闭窗口 | 清空搜索（再按关闭） | 退出编辑模式 |
| ←/→ | 翻页/移动焦点 | 忽略 | 忽略 |
| ↑/↓ | 垂直移动焦点 | 忽略 | 忽略 |
| Enter | 启动选中应用 | 启动第一个匹配 | 忽略 |
| Tab | 移到下一个图标 | 忽略 | 忽略 |
| 任意字符 | 进入搜索 | 追加到查询 | 忽略 |
| Delete | — | 删除最后一个字符 | — |
| Space | — | 追加空格 | — |

---

## 14. 无障碍支持

- **VoiceOver**: 每个 AppIconCell 实现 `NSAccessibilityElement` 协议，提供 `accessibilityLabel`（应用名）、`accessibilityRole`（.button）、`accessibilityDescription`（应用描述）
- **Reduce Motion**: 监听设置变化，切换动画为淡入淡出或即时切换
- **Reduce Transparency**: 替换毛玻璃为纯色背景
- **Increase Contrast**: 增强图标边框和文字对比度
- **键盘导航**: 完整的 Tab/方向键导航，焦点环可见
- **网格结构**: 提供 `accessibilityRows` / `accessibilityColumns` 让 VoiceOver 理解网格布局

---

## 15. 错误处理

| 场景 | 处理策略 |
|------|---------|
| SQLite 数据库损坏 | 删除数据库文件，重新全量扫描创建 |
| 扫描目录无权限 | 跳过该目录，日志警告，提示用户授权 |
| CGEventTap 权限被拒 | 引导用户到系统设置开启辅助功能权限，降级为菜单栏图标唤起 |
| 图标提取失败 | 使用 `NSImage(named: "NSApplicationIcon")` 兜底 |
| 应用路径失效 | 扫描时检测 .app 是否仍存在，失效则标记并在下次扫描清理 |
| 数据库写入冲突 | 使用 WAL 模式 + 串行写入队列（`DispatchQueue` 标记为 serial） |

---

## 16. 测试策略与可测试接口

### TDD 原则

所有代码遵循 Red-Green-Refactor：先写失败测试，再写最小实现代码通过测试，最后重构。每个协议方法、每个状态转换、每个错误路径都有对应的测试用例。

**TDD 先行工作流：**

| Phase | 先写测试（RED） | 再写实现（GREEN） |
|-------|----------------|-------------------|
| 1 | GridLayoutCalculator 断言（7/9/10列） | Calculator 实现 |
| 2 | StorageManager CRUD 测试 + Schema 验证 | SQLite 实现 + Schema |
| 2 | AppScanner 过滤规则测试（注入 mock） | AppScanner 实现 |
| 3 | SearchEngine 评分测试（100/75/50/25） | SearchEngine 实现 |
| 3 | 分页逻辑测试（目标页计算、边界回弹） | PageScrollView 实现 |
| 4 | DragController 状态机测试（6 种转换） | DragController 实现 |
| 5 | 文件夹操作测试（创建/解散/预览） | FolderOverlayView 实现 |
| 6 | 动画回退测试 + 键盘导航测试 | 动画系统 + 焦点管理实现 |
| 7 | 无障碍属性测试 + 错误恢复测试 | 无障碍支持 + 错误处理实现 |

> **铁律：测试必须先于生产代码。** 如果没有看到测试失败，就不知道测试是否真的在测正确的东西。

### 依赖注入协议

为了使各层可独立测试（不依赖真实文件系统、NSWorkspace、CGEventTap），定义以下协议。遵循接口隔离原则，按职责拆分为细粒度协议：

```swift
// 应用扫描抽象 — 测试时可注入 mock 数据
protocol AppScanning {
    func scanDirectories(_ directories: [URL]) -> [ScannedApp]
    func isExcluded(bundleId: String) -> Bool
}

// 图标提供抽象 — 测试时可返回预设图标
protocol IconProviding {
    func icon(forPath path: String) -> NSImage
    func modificationDate(forPath path: String) -> Date?
}

// 数据读取 — 只读操作，SearchEngine/AppScanner 查询使用
protocol ItemReading {
    func fetchAllItems(parentId: Int64?) throws -> [PageItem]
}

// 数据写入 — 写操作，AppScanner 同步、DragController 重排使用
protocol ItemWriting {
    func insertItem(_ item: PageItem) throws -> Int64
    func updateItem(_ item: PageItem) throws
    func deleteItem(id: Int64) throws
    func reorderItems(parentId: Int64, orderedIds: [Int64]) throws
}

// 图标存储 — IconCache 专用
protocol ImageStoring {
    func saveImage(itemId: Int64, icon1x: Data, icon2x: Data) throws
    func fetchImage(itemId: Int64) throws -> (Data, Data)?
}

// 组合协议 — StorageManager 同时实现三个子协议
protocol DataStoring: ItemReading, ItemWriting, ImageStoring {}

// 热键管理抽象 — 测试时可模拟按键事件
protocol HotkeyManaging {
    var onToggle: (() -> Void)? { get set }
    func registerGlobalHotkey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> Bool
    func unregisterGlobalHotkey()
}

// 文件系统抽象 — 测试时可使用内存文件系统
protocol FileSystemService {
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func fileExists(at url: URL) -> Bool
    func bundleInfo(at bundleURL: URL) -> [String: Any]?
}

// 调度器抽象 — 测试时可精确控制时间，避免 flaky test
protocol Scheduler {
    func schedule(after interval: TimeInterval, action: @escaping () -> Void)
    func cancelPending()
}
```

### StorageManager 测试方案

- 生产环境: `StorageManager(dbPath: "~/Library/Application Support/LaunchPad/launchpad.db")`
- 测试环境: `StorageManager(dbPath: ":memory:")` — 内存数据库，每个测试用例独立创建/销毁
- 每个测试前调用 `setupSchema()`，测试后自动回滚

### 具体测试用例

**GridLayoutCalculator（纯函数，无需 mock）:**
- 1440px 宽度 → 7 列 5 行 35 每页
- 1728px 宽度 → 9 列 5 行 45 每页
- 2560px 宽度 → 10 列 5 行 50 每页
- 图标尺寸在 64~96pt 范围内
- 间距计算正确（总宽度 = 列数 × 图标 + (列数-1) × 间距 + 2 × 边距）

**SearchEngine（纯函数，注入数据即可测试）:**
- "saf" 匹配 "Safari"（词首匹配 score=100）
- "sa" 匹配 "Safari" 优先于 "Tessa"（词中匹配 score=50）
- "com.apple" 匹配 bundleId（score=25）
- 空查询返回所有项
- 大小写不敏感
- 无匹配返回空数组
- 多词应用 "Final Cut Pro" 中 "cut" 命中词首匹配（score=75）
- 同分项按字母排序

**StorageManager（注入内存数据库）:**
- 插入 app → 查询返回相同 app
- 删除 group → 子 app 级联删除
- 更新 ordering → 查询顺序正确
- 重复 bundleId → 抛出错误
- 图标保存/读取往返
- 空表 fetchAllItems 返回空数组
- 多层嵌套（page → group → items）正确解析

**AppScanner（注入 AppScanning + FileSystemService 协议）:**
- 扫描返回 .app bundle 列表
- LSUIElement=YES 的应用被过滤
- 无 CFBundleName 的应用被过滤
- 排除列表中的 bundleId 被过滤
- 首次扫描自动创建页面并分页
- 新安装应用 → INSERT 到末尾页面
- 已有应用 title/path 变更 → UPDATE
- 已删应用 → 从 items 表级联删除

**WindowLifecycle（状态机，注入 HotkeyManaging）:**
- hidden 状态下 toggle → 依次经过 opening → visible
- visible 状态下 toggle → 依次经过 closing → hidden
- visible 状态下 ESC → 依次经过 closing → hidden
- visible 状态下点击应用 → 依次经过 launching → closing → hidden
- opening 状态下再次 toggle → 被忽略（防抖）
- visible 状态下焦点丢失 → 自动执行 closing → hidden
- hidden 状态下 ESC → 无操作

**DragController（状态机，注入 ItemWriting + 时间控制）:**
- idle 状态下长按 0.5s（移动 < 10px）→ 转入 jiggling
- idle 状态下长按 0.5s（移动 > 10px）→ 转入 dragging（优先于 jiggling）
- jiggling 状态下 ESC → 转回 idle
- jiggling 状态下开始拖拽 → 转入 dragging
- dragging 状态下悬停屏幕边缘 1.5s → 触发 pageChange
- dragging 状态下悬停图标 0.8s → 触发 createGroup
- dragging 状态下松手 → reorder 数据变更 + 转回 idle
- 长按在 0.49s 中断 → 保持 idle（时间边界）
- 拖拽中途取消 → 恢复原始顺序（数据回滚）

**IconCache（注入 IconProviding + ImageStoring）:**
- 内存缓存命中 → 不读磁盘
- 内存未命中 + 磁盘命中 → 填充内存缓存
- 两层均未命中 → 调用 icon provider + 写入两层缓存
- 超过 500 条 → LRU 淘汰最旧条目
- path.modificationDate 变化 → 磁盘缓存失效，重新提取
- 磁盘缓存 PNG 数据损坏 → 回退到默认 NSApplicationIcon

**搜索防抖（注入 Scheduler mock）:**
- 输入 "sa" 间隔 < 100ms → 仅触发 1 次搜索
- 输入 "s" 后 50ms 按 Backspace → 立即触发搜索（不防抖）
- 快速输入 5 个字符 → 防抖结束后仅触发 1 次搜索
- 搜索缓存：相同查询第二次命中缓存，不重复计算

**错误恢复路径（注入各层 mock + 模拟故障）:**
- SQLite 文件损坏 → 自动删除 + 重新全量扫描
- `/Applications` 无权限 → 跳过该目录，继续扫描其他目录
- CGEventTap 权限被拒 → 降级为菜单栏图标唤起
- 图标提取失败 → 返回默认 NSApplicationIcon
- 应用路径失效（.app 被删除）→ 扫描时检测并清理
- 并发写入冲突 → WAL 模式 + 串行队列保证一致性

**View 层测试策略:**

View 层分为三类，按可测试性采用不同策略：

| 类别 | 组件 | 测试方式 |
|------|------|---------|
| 纯逻辑 | GridLayoutCalculator, SearchEngine | 单元测试，无 mock |
| 可提取逻辑 | PageScrollView 翻页计算, PageControl 页码状态, DiffableDataSource Snapshot 构建 | 提取为纯函数 → 单元测试 |
| 纯 UI 渲染 | AppIconCell, FolderCell, SearchBar, FolderOverlayView | 集成测试 / 手动验证 |

具体可提取测试的逻辑：

```swift
// PageScrollView — 提取目标页计算为纯函数
func targetPage(for offset: CGFloat, velocity: CGFloat,
                currentPage: Int, totalPages: Int) -> Int

// DiffableDataSource — 提取 Snapshot 构建为纯函数
func buildSnapshot(pages: [[PageItem]], searchResults: [PageItem]?,
                   searchQuery: String?) -> NSDiffableDataSourceSnapshot<Section, PageItem>
```

- targetPage：正向滚动速度 > 阈值 → 下一页；负向 → 上一页；速度不足按位移判断
- targetPage：首页右滑/末页左滑 → 弹回当前页
- buildSnapshot：搜索时替换当前 section 内容；清空搜索时恢复原始分页
- buildSnapshot：不同屏幕宽度的 section 数量与每 section item 数量正确

**首次启动流程集成测试:**
- 空数据库 → 触发全量扫描，创建页面，所有已安装应用出现在网格中
- 100 个应用 + 35 每页 → 创建 3 页，最后一页 30 项
- 应用按字母顺序排列，跨页连续
- 被过滤应用（LSUIElement=YES 等）不出现在网格中

---

## 17. 实现阶段

> **每个 Phase 内部遵循 Red-Green-Refactor 循环：** 先写失败测试（RED），再写最小实现通过测试（GREEN），最后重构（REFACTOR）。Phase 之间可串行推进，但每个 Phase 内部不允许"先写代码后补测试"。

### Phase 1: 基础框架（窗口 + 热键 + 空网格）

**RED — 先写测试：**
- GridLayoutCalculator: 1440px → 7列 / 1728px → 9列 / 2560px → 10列
- GridLayoutCalculator: 图标尺寸在 64~96pt，间距计算总和 == 可用宽度
- WindowLifecycle 状态机: hidden → toggle → opening → visible
- WindowLifecycle: visible → ESC → closing → hidden

**GREEN — 再写实现：**
- AppDelegate + 菜单栏图标 + Agent 应用配置
- 全屏窗口 + 毛玻璃背景
- HotkeyManager 全局/应用内热键
- GridLayoutCalculator + AppGridFlowLayout
- 空的 AppGridCollectionView 显示占位图标

### Phase 2: 数据层（扫描 + 存储 + 图标）

**RED — 先写测试：**
- StorageManager: 插入 → 查询往返、重复 bundleId 抛错、级联删除、ordering 更新
- AppScanner: LSUIElement 过滤、无 CFBundleName 过滤、排除列表过滤
- AppScanner: 首次扫描自动分页 + 字母排序
- IconCache: 两层缓存命中/未命中路径、LRU 淘汰、modificationDate 失效
- 错误恢复: 数据库损坏 → 删除重建、目录无权限 → 跳过

**GREEN — 再写实现：**
- SQLite StorageManager + Schema（WAL 模式）
- AppScanner 扫描已安装应用（注入 AppScanning + FileSystemService 协议）
- 首次启动：全量扫描 → 自动分页 → 按字母排序填充
- IconCache 双层缓存（内存 NSCache + SQLite 磁盘）
- FSEvents 文件系统监控（或定时轮询）
- 真实应用图标填充网格

### Phase 3: 分页 + 搜索

**RED — 先写测试：**
- SearchEngine: 评分排序（prefix=100, word-prefix=75, substring=50, bundleId=25）、大小写不敏感、空查询
- PageScrollView: targetPage 纯函数测试（速度阈值、位移判断、边界回弹）
- 搜索防抖（注入 Scheduler mock）: 100ms 合并、Backspace 立即响应、快速输入仅 1 次触发
- DiffableDataSource Snapshot 构建: 搜索替换、清空恢复

**GREEN — 再写实现：**
- PageScrollView 自定义分页滚动（scrollWheel 重写）
- PageControl 页码指示器
- SearchBar + SearchEngine
- 原位过滤 + 100ms 防抖 + LRU 结果缓存
- Scheduler 协议 + DispatchQueueScheduler 实现

### Phase 4: 拖拽与编辑模式

**RED — 先写测试：**
- DragController 状态机全部 6 种转换路径（见 §16 DragController 测试用例）
- 边界条件: 0.49s 中断保持 idle、拖拽取消恢复原始顺序
- 跨页拖拽: section 间移动后 ordering 正确

**GREEN — 再写实现：**
- Jiggle mode 长按触发 + CABasicAnimation 抖动
- NSCollectionView 拖拽重排（delegate 方法链）
- 跨页拖拽（section 间移动 + 边缘自动翻页）
- ✕ 删除按钮 + 确认对话框

### Phase 5: 文件夹系统

**RED — 先写测试：**
- 文件夹创建: 拖拽 A 到 B hover 0.8s → 自动创建文件夹
- 文件夹解散: 移出至只剩 1 个 → 自动解散
- 文件夹预览图: 取前 9 个子应用图标生成 3×3 缩略图
- 文件夹内搜索: 文件夹名匹配 → 整个文件夹作为结果项

**GREEN — 再写实现：**
- 拖拽创建文件夹（hover 0.8s）
- FolderOverlayView 展开弹窗 + 内部分页
- 文件夹预览图生成（3×3 缩略图）
- 重命名 / 删除 / 解散

### Phase 6: 动画 + 键盘导航 + 打磨

**RED — 先写测试：**
- 所有动画在 Reduce Motion 开启时回退为淡入淡出或即时切换
- 键盘导航: idle/search/edit 三态下各按键行为符合 §13 键位表
- 应用启动动画序列: scale 0.95→1.0→2.0 + opacity→0

**GREEN — 再写实现：**
- 所有动画实现（开/关、启动、入场、翻页、文件夹展开/收起）
- 键盘导航完善（焦点环、方向键、Tab 顺序）
- 焦点丢失自动隐藏
- 性能优化（图标懒加载、预取、后台线程）

### Phase 7: 无障碍 + 集成测试 + 持久化

**RED — 先写测试：**
- 无障碍: 每个 AppIconCell 有 accessibilityLabel/role/description
- 无障碍: VoiceOver 网格结构（accessibilityRows/accessibilityColumns）
- 错误恢复端到端: 损坏 DB → 自动重建 → 应用可正常使用

**GREEN — 再写实现：**
- 无障碍支持（VoiceOver、Reduce Motion/Transparency、Increase Contrast）
- 布局持久化（用户自定义排列保存/恢复）

**REFACTOR — 全面重构：**
- 审查所有层的测试覆盖率，补充遗漏的边界条件
- 端到端集成测试（首次启动完整流程、多页操作、搜索→拖拽→文件夹组合场景）
- 性能基准测试（1000+ 图标加载、搜索响应时间 < 50ms）
- 代码清理：提取重复的测试 helper、统一命名规范
