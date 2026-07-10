# LaunchPad — 正式发布工程化评审报告

> **评审日期:** 2026-07-08
> **评审标准:** 正式发布标准（含 100% 测试覆盖率硬性指标）
> **基准数据:** `swift build` ✅ | `swift test` 395 tests ✅ | 行覆盖 82.64% | release 64 warnings
> **评审结论:** ❌ **未达发布标准**，存在 5 类阻塞项

---

## 一、阻塞项总览

| # | 阻塞项 | 硬性指标 | 当前状态 | 缺口 |
|---|--------|---------|---------|------|
| **R1** | 测试覆盖率 100% | 100% 行覆盖 | 82.64%（506 行未覆盖） | **17.36%** |
| **R2** | Release build 0 warnings | 0 warning | 64 warnings | **64** |
| **R3** | 代码签名与公证 | 签名+公证 | adhoc 签名，未公证 | **完全缺失** |
| **R4** | 13 项手动功能验证 | 全部通过 | 0/13 执行 | **13/13** |
| **R5** | `.nonactivatingPanel` 键盘焦点 | 可收键盘事件 | 未验证 | **未验证** |

---

## 二、R1 — 测试覆盖率 100%（硬性指标）

### 2.1 整体覆盖率

| 指标 | 当前值 | 目标 | 缺口 |
|------|--------|------|------|
| 行覆盖率 | 82.64% | 100% | -17.36%（506 行未覆盖） |
| 函数覆盖率 | 88.71% | 100% | -11.29%（201 函数未覆盖） |
| 区域覆盖率 | 82.64% | 100% | -17.36%（506 区域未覆盖） |

### 2.2 逐文件覆盖率缺口（按未覆盖行数降序）

| 文件 | 总行 | 未覆盖行 | 行覆盖% | 难度 | 说明 |
|------|------|---------|--------|------|------|
| AppDelegate.swift | 363 | 363 | 0.00% | 🔴 高 | 需 .app bundle 环境，事件监视器/菜单/多实例防护/FSEvents 集成 |
| LaunchPadViewController.swift | 615 | 165 | 73.17% | 🟡 中 | animateAppLaunch/动画完成回调/private 方法分支 |
| AppGridCollectionView.swift | 337 | 98 | 70.92% | 🟡 中 | 拖拽 acceptDrop 完整流程/动画辅助方法 |
| FolderOverlayView.swift | 290 | 82 | 71.72% | 🟡 中 | 分页滚动/CollectionView delegate/动画 |
| HotkeyManager.swift | 190 | 121 | 36.32% | 🔴 高 | CGEventTap 回调路径需真实辅助功能权限 |
| StorageManager.swift | 578 | 29 | 94.98% | 🟢 低 | 错误处理分支/边界条件 |
| PageScrollView.swift | 142 | 57 | 59.86% | 🟡 中 | scrollWheel 完整手势/mayBegin 边缘 |
| LaunchPadWindowController.swift | 290 | 33 | 88.62% | 🟡 中 | 动画完成回调/焦点丢失/多显示器 |
| AppIconCell.swift | 257 | 17 | 93.39% | 🟢 低 | 抖动动画/delete 按钮/通知回调细节 |
| AppScanner.swift | 177 | 13 | 92.66% | 🟢 低 | 增量同步 DELETE/排除列表 |
| SearchEngine.swift | 132 | 9 | 93.18% | 🟢 低 | 缓存失效/空查询边界 |
| IconCache.swift | 114 | 8 | 92.98% | 🟢 低 | 磁盘失效/storeToDisk 路径 |
| FolderCell.swift | 145 | 18 | 87.59% | 🟢 低 | 编辑模式/thumbnail 配置细节 |
| SearchBar.swift | 81 | 7 | 91.36% | 🟢 低 | delegate 回调/动画 |
| Schema.swift | 41 | 7 | 82.93% | 🟢 低 | migration/版本检查 |
| EmptyStateView.swift | 61 | 4 | 93.44% | 🟢 低 | 动画分支 |
| PageControl.swift | 68 | 4 | 94.12% | 🟢 低 | draw/鼠标事件细节 |
| ErrorRecovery.swift | 53 | 5 | 90.57% | 🟢 低 | corruption 检测分支 |
| AppGridFlowLayout.swift | 54 | 5 | 90.74% | 🟢 低 | targetContentOffset 边界 |
| AnimationRunner.swift | 29 | 9 | 68.97% | 🟡 中 | reduceMotion 分支 |
| FileWatcher.swift | 104 | 2 | 98.08% | 🟢 低 | stop 边界 |
| DragController.swift | 185 | 2 | 98.92% | 🟢 低 | 边界条件 |
| FolderController.swift | 79 | 1 | 98.73% | 🟢 低 | 单一分支 |
| **合计** | **5423** | **~1095** | **~80%** | — | — |

> 注：以上"未覆盖行"来自 `llvm-cov` 行覆盖率列（含 `#if canImport(AppKit)` 守卫行等）。

### 2.3 100% 覆盖率可行性分析

**可达 100% 的文件（约 70% 缺口，~770 行）：**
- 🟢 低难度（StorageManager/SearchEngine/IconCache 等 ~100 行）：补充边界测试即可
- 🟡 中难度（ViewController/CollectionView/FolderOverlayView/PageScrollView ~500 行）：需要触发视图回调、动画完成、手势模拟，可通过反射或 MainActor 测试达到
- 🟡 中难度（AnimationRunner/FolderCell/SearchBar ~40 行）：reduceMotion 分支、编辑模式

**难以达 100% 的文件（约 30% 缺口，~325 行）：**
- 🔴 AppDelegate（363 行）：`applicationDidFinishLaunching`/事件监视器/菜单构建/`SMAppService`/`NSRunningApplication` 多实例防护 — 需完整 .app 生命周期，单元测试无法覆盖
- 🔴 HotkeyManager（121 行）：`CGEventTapCreate`/`CGEventTapEnable` 回调 — 需真实辅助功能权限（AXIsProcessTrusted），CI 环境无法模拟
- 这些代码需要 **集成测试**（XCUITest 或 .app 启动测试）或 **`@testable` + 协议抽象重构** 才能覆盖

### 2.4 达成 100% 的建议路径

| 策略 | 适用范围 | 预计工期 |
|------|---------|---------|
| A. 补充单元测试 | 🟢🟡 所有中低难度文件 | 2-3 天 |
| B. AppDelegate 提取可测试逻辑 | AppDelegate 的业务逻辑提取为独立类 | 1-2 天 |
| C. HotkeyManager 协议抽象 | CGEventTap 路径抽象为协议，测试注入 mock | 1 天 |
| D. 集成测试 (XCUITest) | .app 启动/菜单/多实例防护 | 1-2 天 |
| **合计** | — | **5-8 天** |

---

## 三、R2 — Release Build Warnings（0 warning 目标）

### 3.1 Warning 分类统计

全量 release build（`rm -rf .build && swift build -c release`）共 64 个 warning，分为 4 类：

| 类别 | 数量 | 严重性 | 说明 |
|------|------|--------|------|
| **Swift 6 并发隔离** | ~48 | 🟡 中 | `@MainActor` 属性/方法从 `@Sendable` 闭包访问 |
| **未使用结果** | ~8 | 🟢 低 | `withUnsafeBytes`/`insertItem`/`try?` 返回值未使用 |
| **协议方法签名不匹配** | 2 | 🟡 中 | `draggingImageForItemsAt` 参数类型 `NSPoint` vs `NSPointPointer` |
| **已弃用 API** | 2 | 🟢 低 | `FSEventStreamScheduleWithRunLoop` → `FSEventStreamSetDispatchQueue` |
| **未使用变量** | 4 | 🟢 低 | `snapshot`/`section` 定义后未使用 |

### 3.2 修复方案

| 类别 | 修复方案 | 预计工期 |
|------|---------|---------|
| Swift 6 并发隔离 | 将 `@Sendable` 闭包改为 `@MainActor` 或 `DispatchQueue.main.async` 包裹 | 1-2 天 |
| 未使用结果 | 加 `_ =` 或 `@discardableResult` | 0.5 天 |
| 协议签名不匹配 | 将 `draggingImageForItemsAt` 参数改为 `NSPointPointer` 或移到独立 extension | 0.5 天 |
| 已弃用 API | `FileWatcher` 改用 `FSEventStreamSetDispatchQueue` | 0.5 天 |
| 未使用变量 | 删除或改用 `_` | 0.1 天 |
| **合计** | — | **2-3 天** |

---

## 四、R3 — 代码签名与公证

### 4.1 当前状态

| 项目 | 状态 | 说明 |
|------|------|------|
| 代码签名 | ❌ adhoc 签名 | `Signature=adhoc`，`TeamIdentifier=not set` |
| 公证 | ❌ 未公证 | 未通过 `notarytool` 提交 |
| Entitlements | ⚠️ 不完整 | 仅有 `com.apple.security.automation.apple-events`，缺 Input Monitoring 权限声明 |
| Info.plist | ✅ 基本完整 | `LSUIElement=true`, `CFBundleIdentifier=com.launchpad.app` |

### 4.2 发布要求

- **Developer ID 签名**：需 Apple Developer Program 账号，使用 `codesign --deep --options runtime --sign "Developer ID Application: ..."` 签名
- **公证**：`xcrun notarytool submit ... --keychain-profile "..."` 提交公证
- **Entitlements 补充**：需添加 `com.apple.security.temporary-exception.input-monitoring` 或使用 `NSEvent.addGlobalMonitorForEvents` 替代 `CGEventTap`
- **Hardened Runtime**：`--options runtime` 启用

### 4.3 修复方案

需要 Apple Developer Program 账号（$99/年），预计 0.5 天配置 + 0.5 天测试。

---

## 五、R4 — 手动功能验证（13 项）

### 5.1 验证清单

| # | 验证项 | 状态 | 备注 |
|---|--------|------|------|
| 1 | Option+Space 唤起/关闭 LaunchPad | ❌ 未执行 | 需真实全局快捷键 |
| 2 | 图标网格正确显示（3 种屏幕宽度） | ❌ 未执行 | 需多分辨率测试 |
| 3 | 双指横滑翻页 + 页码点同步 | ❌ 未执行 | 需真实触控板 |
| 4 | 搜索输入 + 防抖 + 清空恢复 | ❌ 未执行 | — |
| 5 | 点击图标启动应用 + 三阶段动画 | ❌ 未执行 | — |
| 6 | 长按进入编辑模式 + 抖动 + ✕ 按钮 | ❌ 未执行 | — |
| 7 | 拖拽重排 + 跨页拖拽 | ❌ 未执行 | 需真实拖拽 |
| 8 | 拖拽创建文件夹 | ❌ 未执行 | — |
| 9 | 文件夹打开/关闭/重命名 | ❌ 未执行 | — |
| 10 | VoiceOver 可读 | ❌ 未执行 | 需 VoiceOver 辅助功能 |
| 11 | Reduce Motion / Reduce Transparency 生效 | ❌ 未执行 | 需系统设置切换 |
| 12 | 多显示器正确显示 | ❌ 未执行 | 需外接显示器 |
| 13 | 新安装应用自动出现 | ❌ 未执行 | 需 FSEvents 触发 |

### 5.2 执行条件

- 需在真实 macOS 环境运行 `.build/LaunchPad.app`
- 部分项需外接显示器、触控板、VoiceOver
- 预计 1 天完成全部验证

---

## 六、R5 — `.nonactivatingPanel` 键盘焦点

`NSPanel(styleMask: [.nonactivatingPanel])` 可能导致窗口无法成为 key window，从而收不到键盘事件。`AppDelegate` 使用 `NSEvent.addLocalMonitorForEvents` 作为替代方案，但：

- `addLocalMonitorForEvents` 只在应用处于活跃状态时工作
- 如果 LaunchPad 不是前台应用（Agent 模式 `LSUIElement=true`），键盘事件可能无法到达
- 需要手动验证：窗口打开后按键是否有响应

**修复方案**：如键盘焦点有问题，将 `.nonactivatingPanel` 改为普通 `NSPanel` 并配合 `becomesKeyOnlyIfNeeded`，或使用 `NSApp.activate(ignoringOtherApps:)`。

---

## 七、非阻塞发现

### 7.1 代码质量

| 发现 | 严重性 | 说明 |
|------|--------|------|
| `LaunchPadViewController.swift:259` 未使用变量 `snapshot` | 🟢 低 | release warning，应删除 |
| `AppScanner.swift:111,145` `insertItem` 返回值未使用 | 🟢 低 | release warning，加 `_ =` |
| `StorageManager.swift:269,272` `withUnsafeBytes` 返回值未使用 | 🟢 低 | release warning，加 `_ =` |
| `SearchDebouncer.swift:56` 冗余 `nonisolated(unsafe)` | 🟢 低 | release warning，删除 |
| `AppDelegate.swift:207` 冗余 `nonisolated(unsafe)` | 🟢 低 | release warning，删除 |
| 无 TODO/FIXME/HACK 标记 | ✅ 良好 | — |
| 无死代码残留 | ✅ 良好 | FolderThumbnailGenerator 已删除 |

### 7.2 架构一致性

| 维度 | 评估 |
|------|------|
| 四层架构 | ✅ 优秀 — App/Controllers/Services/Views/Storage 清晰 |
| 协议驱动 DI | ✅ 优秀 — 10 个协议，Mock 完整 |
| Swift 6 并发 | ⚠️ 良好但有 warning — `@MainActor` 标注完整，但 `@Sendable` 闭包访问存在违规 |
| `swift-tools-version: 6.0` | ✅ Swift 6 模式 |

### 7.3 测试工程质量

| 维度 | 评估 |
|------|------|
| 测试总数 | 395 tests（XCTest + Swift Testing） |
| Mock 类 | 7+ 完整实现 |
| 测试风格 | 混合使用 XCTest 和 Swift Testing，风格不完全统一 |
| Flaky 测试 | ⚠️ 存在 — IconCache 性能测试依赖 NSCache 行为，已修复为确定性但仍有风险 |
| 测试隔离 | ✅ 良好 — 每个测试使用独立 Mock |

---

## 八、发布就绪度评估

### 8.1 评分

| 维度 | 评分 | 说明 |
|------|------|------|
| 架构设计 | ⭐⭐⭐⭐⭐ | 五层清晰、协议驱动 DI |
| 代码实现度 | ⭐⭐⭐⭐⭐ | 32 Task 全部实现，0 偏差 |
| 测试覆盖 | ⭐⭐⭐ | 395 tests，82.64% 行覆盖，未达 100% 硬性指标 |
| 构建质量 | ⭐⭐⭐ | debug 0 warning，release 64 warning |
| 签名公证 | ⭐ | adhoc 签名，未公证 |
| 手动验证 | ❌ | 0/13 执行 |
| **发布就绪** | ❌ | **5 项阻塞未解决** |

### 8.2 达到发布标准的预估工期

| 工作项 | 预计工期 | 优先级 |
|--------|---------|--------|
| R1: 覆盖率达 100% | 5-8 天 | P0（硬性指标） |
| R2: release 0 warning | 2-3 天 | P0 |
| R3: 代码签名+公证 | 1 天（需 Developer 账号） | P0 |
| R4: 13 项手动验证 | 1 天 | P0 |
| R5: 键盘焦点验证 | 0.5 天 | P1 |
| **合计** | **9-13 天** | — |

> R1 和 R2 有部分重叠（修复 warning 时可能涉及可测试性重构），实际工期可能缩短。

### 8.3 建议执行顺序

1. **R2（release 0 warning）**→ 修复过程中改善并发隔离，部分代码可测试性提升
2. **R1（覆盖率 100%）**→ 利用 R2 的重构提升可测试性，补充单元测试 + 集成测试
3. **R3（签名公证）**→ 配置 Developer 账号
4. **R4 + R5（手动验证）**→ 签名后运行 .app 执行验证清单
