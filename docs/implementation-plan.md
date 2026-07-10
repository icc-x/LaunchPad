# LaunchPad — 发布就绪修复计划

> **日期:** 2026-07-08
> **基线状态:** `swift build` ✅ 0 errors 0 warnings (debug) | `swift test` 395 tests ✅ | 行覆盖 82.64% | release 64 warnings
> **分支:** release-readiness
> **目标:** 达到正式发布标准（含 100% 测试覆盖率硬性指标）
> **预计总工期:** 9-13 天

---

## 目录

- [Phase 1: Release Build 0 Warnings](#phase-1-release-build-0-warnings)
- [Phase 2: 测试覆盖率 100%（硬性指标）](#phase-2-测试覆盖率-100硬性指标)
- [Phase 3: 代码签名与公证](#phase-3-代码签名与公证)
- [Phase 4: 手动功能验证](#phase-4-手动功能验证)
- [验收标准](#验收标准)

---

## Phase 1: Release Build 0 Warnings

> **目标:** `rm -rf .build && swift build -c release --product LaunchPadApp` 输出 0 warning
> **当前:** 64 warnings（4 类）
> **预计工期:** 2-3 天
> **方法:** TDD — 修复每个 warning 后 `swift build -c release` 验证 0 新增 warning

### 1.1 Swift 6 并发隔离违规（~48 warnings）

| 来源文件 | 问题 | 修复方案 |
|---------|------|---------|
| `AppDelegate.swift:207-225` | `nonisolated(unsafe)` 从 Sendable 闭包访问 @MainActor 属性（lifecycle/viewController/handleKeyEvent/handleCharacterInput） | 移除 `nonisolated(unsafe)`，改用 `DispatchQueue.main.async` 包裹闭包体 |
| `LaunchPadViewController.swift:308` | `searchEngine` 非 Sendable 被 @Sendable 闭包捕获 | 将 `SearchEngine` 标记为 `Sendable`（struct，属性均为 Sendable） |
| `LaunchPadViewController.swift:416` | `cellView.animator().alphaValue` 从 nonisolated context 访问 @MainActor | 将 `animateAppLaunch` 的动画闭包用 `DispatchQueue.main.async` 包裹 |
| `LaunchPadViewController.swift:424` | `cellView.layer?.add()` 从 Sendable 闭包访问 | 同上 |
| `AccessibilityObservers.swift:49` | `self` 非 Sendable 被 @Sendable 闭包捕获 | 将 `AccessibilityObserver` 标记为 `@unchecked Sendable` 或重构回调 |
| `AppIconCell.swift` (4 warnings) | NSWorkspace 通知回调中访问 @MainActor 属性（isHidden/currentBundleId/layer） | 将回调体用 `DispatchQueue.main.async` 包裹 |
| `FolderOverlayView.swift` (6 warnings) | pages/childItems/onClosed 从 Sendable 闭包访问 | 用 `DispatchQueue.main.async` 包裹或标记为 `@MainActor` |
| `LaunchPadWindowController.swift` (2 warnings) | alphaValue 从 nonisolated context 访问 | 用 `DispatchQueue.main.async` 包裹 |
| `PageScrollView.swift` (2 warnings) | updatePageFromScrollPosition 从 nonisolated 调用 | 标注方法为 `nonisolated` 或用 `DispatchQueue.main.async` |

**验收标准:**
- [ ] `swift build -c release --product LaunchPadApp` 中 `#ActorIsolatedCall` 和 `#SendableClosureCaptures` warning 为 0
- [ ] `swift test` 395+ tests 全部通过
- [ ] debug build 仍 0 warning

---

### 1.2 未使用结果（~8 warnings）

| 文件 | 行 | 问题 | 修复 |
|------|---|------|------|
| `StorageManager.swift:269,272` | `withUnsafeBytes` 返回值未使用 | 改为 `icon1x.withUnsafeBytes { _ in ... }` 或提取副作用 |
| `AppScanner.swift:111` | `try? writer.insertItem()` 结果未使用 | 加 `_ = ` |
| `AppScanner.swift:145` | `writer.insertItem()` 结果未使用 | 加 `_ = ` |

**验收标准:**
- [ ] `#no-usage` warning 为 0

---

### 1.3 协议方法签名不匹配（2 warnings）

| 文件 | 行 | 问题 | 修复 |
|------|---|------|------|
| `AppGridCollectionView.swift:321` | `draggingImageForItemsAt` 参数 `offset: NSPoint` 与协议要求的 `NSPointPointer` 不匹配 | 改签名为 `offset dragImageOffset: NSPointPointer` |

**验收标准:**
- [ ] `nearly matches optional requirement` warning 为 0
- [ ] 拖拽预览功能正常（`swift test` 中拖拽相关测试通过）

---

### 1.4 已弃用 API + 未使用变量（~6 warnings）

| 文件 | 行 | 问题 | 修复 |
|------|---|------|------|
| `FileWatcher.swift:68` | `FSEventStreamScheduleWithRunLoop` 已弃用 | 改用 `FSEventStreamSetDispatchQueue` |
| `LaunchPadViewController.swift:259` | 变量 `snapshot` 未使用 | 删除或改用 `_` |
| `SearchDebouncer.swift:56` | 冗余 `nonisolated(unsafe)` | 删除（String 已是 Sendable） |
| `AppDelegate.swift:207` | 冗余 `nonisolated(unsafe)` | 删除（随 1.1 修复一并处理） |

**验收标准:**
- [ ] `#DeprecatedDeclaration` warning 为 0
- [ ] FileWatcher 测试全部通过
- [ ] `#no-usage` 未使用变量 warning 为 0

---

## Phase 2: 测试覆盖率 100%（硬性指标）

> **目标:** `swift test --enable-code-coverage` + `llvm-cov` 行覆盖 100%
> **当前:** 82.64%（506 行未覆盖）
> **预计工期:** 5-8 天
> **方法:** TDD — 每个未覆盖路径先写测试再验证

### 2.1 可直接补充单元测试的文件（~370 行未覆盖）

| 文件 | 当前% | 未覆盖行 | 未覆盖内容 | 优先级 |
|------|-------|---------|-----------|--------|
| `LaunchPadViewController.swift` | 73.17% | 165 | animateAppLaunch 动画完成回调、updateJiggleState 分支、handleSearch 边界 | P0 |
| `AppGridCollectionView.swift` | 70.92% | 98 | acceptDrop 完整流程、animateEntrance 细节、accessibilityRows | P0 |
| `FolderOverlayView.swift` | 71.72% | 82 | 分页滚动 delegate、openFolder/closeFolder 分支、scrollWheel | P0 |
| `PageScrollView.swift` | 59.86% | 57 | scrollWheel .changed/.ended 完整手势、mayBegin 边缘回弹 | P1 |
| `LaunchPadWindowController.swift` | 88.62% | 33 | 动画完成回调、windowDidResignKey 分支 | P1 |
| `StorageManager.swift` | 94.98% | 29 | 错误处理分支、saveImage/fetchImage 边界 | P1 |
| `AppIconCell.swift` | 93.39% | 17 | startJiggling/stopJiggling 分支、通知回调 | P1 |
| `FolderCell.swift` | 87.59% | 18 | handleDoubleClick、controlTextDidEndEditing 分支 | P2 |
| `SearchEngine.swift` | 93.18% | 9 | 缓存失效、空查询 | P2 |
| `IconCache.swift` | 92.98% | 8 | 磁盘失效路径、storeToDisk | P2 |
| `SearchBar.swift` | 91.36% | 7 | delegate 回调、动画 | P2 |
| `Schema.swift` | 82.93% | 7 | migration、版本检查 | P2 |
| `AnimationRunner.swift` | 68.97% | 9 | reduceMotion 分支 | P2 |
| 其他 ≥90% 文件 | — | ~16 | 边界条件 | P3 |

**验收标准:**
- [ ] 以上文件行覆盖率达 100%（除 AppDelegate 和 HotkeyManager 外）

---

### 2.2 需重构才能测试的文件（~484 行未覆盖）

#### 2.2.1 AppDelegate（363 行，0% 覆盖率）

**问题:** `applicationDidFinishLaunching`/事件监视器/菜单构建/`SMAppService`/`NSRunningApplication` 多实例防护 — 需完整 .app 生命周期。

**修复方案:**

1. **提取可测试逻辑**（1-2 天）：
   - 将 `applicationDidFinishLaunching` 中的服务初始化逻辑提取为 `AppServiceConfigurator` 类
   - 将多实例防护逻辑提取为 `InstanceGuard` 类
   - 将菜单构建逻辑提取为 `MenuBuilder` 类
   - 以上类均可通过 Mock 测试

2. **补充集成测试**（1 天）：
   - 创建 `AppDelegateTests.swift`
   - 测试 `applicationDidFinishLaunching` 调用后各服务正确初始化
   - 测试 `applicationWillTerminate` 清理逻辑

**验收标准:**
- [ ] AppDelegate 行覆盖率达 100%（或通过集成测试覆盖）
- [ ] 提取的类各自有独立测试

---

#### 2.2.2 HotkeyManager（121 行未覆盖，36.32%）

**问题:** `CGEventTapCreate`/`CGEventTapEnable` 回调路径需真实辅助功能权限（`AXIsProcessTrusted()`），CI 环境无法模拟。

**修复方案:**

1. **协议抽象**（0.5 天）：
   - 创建 `EventTapCreating` 协议，封装 `CGEventTapCreate` 调用
   - `HotkeyManager` 通过依赖注入接收 `EventTapCreating`
   - 测试中注入 Mock，模拟事件回调

2. **补充测试**（0.5 天）：
   - 测试 `registerGlobalHotkey` 在无权限时返回 false
   - 测试 `hasConflict` 在 `tapCreate` 返回 nil 时为 true
   - 测试事件回调正确触发 `onToggle`/`onKeyDown`

**验收标准:**
- [ ] HotkeyManager 行覆盖率达 100%
- [ ] CGEventTap 路径通过 Mock 测试覆盖

---

### 2.3 覆盖率验证流程

每次提交覆盖率改进后执行：
```bash
swift test --enable-code-coverage
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/llvm-cov report \
  .build/arm64-apple-macosx/debug/LaunchPadPackageTests.xctest/Contents/MacOS/LaunchPadPackageTests \
  -instr-profile=.build/arm64-apple-macosx/debug/codecov/default.profdata
```

**最终验收标准:**
- [ ] `TOTAL` 行覆盖率 = 100.00%
- [ ] 每个生产文件行覆盖率 = 100.00%
- [ ] `swift test --enable-code-coverage` 0 失败 0 跳过

---

## Phase 3: 代码签名与公证

> **目标:** `.app` 通过 Developer ID 签名 + Apple 公证
> **当前:** adhoc 签名，未公证
> **预计工期:** 1 天
> **前提:** 拥有 Apple Developer Program 账号

### 3.1 补全 Entitlements

| 权限 | 当前 | 需要 | 说明 |
|------|------|------|------|
| `com.apple.security.automation.apple-events` | ✅ | ✅ | AppleScript 支持 |
| `com.apple.security.temporary-exception.input-monitoring` | ❌ | ✅ | CGEventTap 全局快捷键 |
| Hardened Runtime | ❌ | ✅ | 公证必须 |

### 3.2 签名脚本更新

修改 `scripts/build-app.sh`：
```bash
codesign --deep --options runtime \
  --entitlements Resources/LaunchPad.entitlements \
  --sign "Developer ID Application: <TEAM_NAME>" \
  .build/LaunchPad.app
```

### 3.3 公证

```bash
xcrun notarytool submit .build/LaunchPad.app.zip \
  --keychain-profile "LaunchPad" \
  --wait
xcrun stapler staple .build/LaunchPad.app
```

**验收标准:**
- [ ] `codesign -dv .build/LaunchPad.app` 显示 `Signature=ADHOC` → `Signature=valid`，`TeamIdentifier` 非空
- [ ] `spctl --assess --type execute .build/LaunchPad.app` 通过
- [ ] `xcrun stapler validate .build/LaunchPad.app` 通过

---

## Phase 4: 手动功能验证

> **目标:** 13 项手动验证全部通过
> **当前:** 0/13
> **预计工期:** 1 天
> **前提:** Phase 3 完成（签名后的 .app）

### 4.1 验证清单

| # | 验证项 | 验证方法 | 通过标准 |
|---|--------|---------|---------|
| 1 | Option+Space 唤起/关闭 | 系统设置授权后按快捷键 | 窗口出现/消失 |
| 2 | 图标网格正确显示 | 在 1280/1920/2560 宽度下截图 | 图标 3 种尺寸自适应 |
| 3 | 双指横滑翻页 + 页码点 | 触控板双指横滑 | 页面切换 + 页码点同步 |
| 4 | 搜索 + 防抖 + 清空 | 输入 "Sa"，等待 100ms，清空 | 结果实时过滤 + 清空恢复 |
| 5 | 点击图标 + 三阶段动画 | 点击任意图标 | scale 0.95→1.0 → 放大淡出 → 应用启动 |
| 6 | 长按 + 抖动 + ✕ 按钮 | 长按任意图标 0.5s | 全部抖动 + ✕ 按钮显示 |
| 7 | 拖拽重排 + 跨页拖拽 | 拖拽图标到新位置 | 顺序更新 + 跨页翻页 |
| 8 | 拖拽创建文件夹 | 拖拽 A 到 B 上停留 0.8s | 创建文件夹含 A+B |
| 9 | 文件夹打开/关闭/重命名 | 点击文件夹 + 双击名称 | 弹窗/关闭/重命名持久化 |
| 10 | VoiceOver 可读 | 开启 VoiceOver 浏览网格 | 读出应用名称 + 网格结构 |
| 11 | Reduce Motion/Transparency | 系统设置开启后操作 | 动画/材质正确回退 |
| 12 | 多显示器 | 外接显示器后唤起 | 在鼠标所在显示器显示 |
| 13 | 新安装应用自动出现 | 安装新 .app 到 /Applications | 自动出现在网格中 |

### 4.2 `.nonactivatingPanel` 键盘焦点验证

- 在 Phase 4 验证第 1 项时确认键盘事件是否到达
- 如失败：将 `.nonactivatingPanel` 改为普通 `NSPanel` + `becomesKeyOnlyIfNeeded`
- 修复后重新验证

**验收标准:**
- [ ] 13 项全部通过
- [ ] 键盘焦点正常（窗口打开后按键有响应）

---

## 验收标准

### 编译
- [ ] `swift build`（debug）— 0 errors, 0 warnings
- [ ] `swift build -c release --product LaunchPadApp` — 0 errors, 0 warnings

### 测试
- [ ] `swift test` — 395+ tests 全部通过
- [ ] `swift test --enable-code-coverage` — 0 失败 0 跳过
- [ ] **行覆盖率 100.00%**（硬性指标）
- [ ] 每个生产文件行覆盖率 100.00%

### 签名发布
- [ ] `.app` 通过 Developer ID 签名
- [ ] `.app` 通过 Apple 公证
- [ ] `spctl --assess` 通过

### 手动验证
- [ ] 13 项手动功能验证全部通过
- [ ] `.nonactivatingPanel` 键盘焦点正常

### 发布阻塞项
1. ~~R1: Release 0 warning~~ → Phase 1
2. ~~R2: 覆盖率 100%~~ → Phase 2
3. ~~R3: 签名+公证~~ → Phase 3
4. ~~R4: 手动验证~~ → Phase 4
5. ~~R5: 键盘焦点~~ → Phase 4 一并验证

---

## 工期估算总览

| Phase | 内容 | 预计工期 | 累计 |
|-------|------|---------|------|
| Phase 1 | Release 0 warnings | 2-3 天 | 3 天 |
| Phase 2 | 覆盖率 100% | 5-8 天 | 8-11 天 |
| Phase 3 | 签名+公证 | 1 天 | 9-12 天 |
| Phase 4 | 手动验证 | 1 天 | 10-13 天 |
| **合计** | | — | **10-13 天** |

> Phase 1 和 Phase 2 有重叠：修复并发隔离 warning 时会重构代码提升可测试性，实际工期可能缩短至 9-10 天。
