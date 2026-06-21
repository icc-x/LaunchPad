# LaunchPad — 未完成项实施计划

> **日期:** 2026-06-07（初版） / 2026-06-20（上线就绪复核修订）
> **依据:** `docs/verification-report.md` 全面验证结果
> **目标:** ~~将实现完成度从 ~70% 提升至 ~95%~~（代码实现度已达 ~90%，当前目标是达到上线就绪标准）
> **前提:** 每个 Phase 内部遵循 TDD（先写测试 → RED → 实现 → GREEN → REFACTOR）
>
> **2026-06-20 复核说明:** 本计划原版声称各 Phase 已完成，经实际运行测试与覆盖率分析复核，代码实现度确实高（P0 功能均已编码），但发现三类问题：(1) 部分 Task 验收标准未实测确认；(2) Phase 2 的拖拽交互因 LaunchPadViewController.executeAction 空实现而断裂；(3) Phase 7/8 的测试覆盖与手动验证目标未真正达成。以下进度标注已据此修订。

---

## 目录

- [Phase 1: 关键修复与基础补全（P0 + 快速修复）](#phase-1)
- [Phase 2: 拖拽系统集成（P0 核心）](#phase-2)
- [Phase 3: 分页滚动与动画系统（P0 + P1）](#phase-3)
- [Phase 4: 文件夹系统完善（P1）](#phase-4)
- [Phase 5: 扫描与系统集成（P1）](#phase-5)
- [Phase 6: 无障碍与视觉打磨（P2）](#phase-6)
- [Phase 7: 测试补充与技术债务](#phase-7)
- [Phase 8: 性能优化与收尾](#phase-8)
- [技术债务清单](#技术债务)
- [验收标准](#验收标准)

---

<a id="phase-1"></a>
## Phase 1: 关键修复与基础补全

> **目标:** 修复验证报告中的严重偏差，补全低成本高价值的功能
> **预计工期:** 1-2 天（✅ 代码全部实现）
> **进度:** ✅ 代码全部实现（Task 1.1-1.6），验收标准见各 Task（代码已实现但未手动验证）

### Task 1.1: 搜索防抖 100ms ✅

**设计文档:** §9 搜索系统 — 防抖策略

**完成情况:** 已在 commit `2e84581` 中实现。新建 `SearchDebouncer` 类，注入 `Scheduler` 可测试。
- 空查询 → 立即触发
- Backspace（查询变短）→ 立即触发
- 正常输入 → 100ms debounce
- 集成到 `LaunchPadViewController.setupCallbacks`
- 6 个新测试全部通过

---

### Task 1.2: 窗口级别修正 ✅

**设计文档:** §3 — 窗口级别: `NSWindow.Level.screenSaver`

**完成情况:** 已在 commit `5cebeff` 中修复，`panel.level = .screenSaver`

**验收标准:**
- [x] `panel.level == .screenSaver`
- [~] LaunchPad 可覆盖所有级别窗口 — 代码已设 .screenSaver，未手动验证（无 .app 可运行）

---

### Task 1.3: 视觉效果 state 修正 ✅

**设计文档:** §3 — `state: .followsWindowActiveState`

**完成情况:** 已在 commit `5cebeff` 中修复，init 和 `applyAccessibilitySettings` 均改为 `.followsWindowActiveState`

**验收标准:**
- [x] 毛玻璃效果随窗口活跃状态自动切换

---

### Task 1.4: `/System/Applications` 扫描目录补全 ✅

**设计文档:** §7 — 扫描目录包含 `/System/Applications`

**完成情况:** 已在 commit `b00e949` 中修复，`performInitialScan()` 的 directories 数组添加了 `/System/Applications`

---

### Task 1.5: 应用启动动画三阶段 ✅

**设计文档:** §12 — 点击图标 → 高亮反馈(scale 0.95→1.0) → 放大淡出(scale→2.0, opacity→0) → 关闭窗口

**完成情况:** 已在 commit `a018465` 中实现
- 窗口打开: CASpringAnimation scale 0.8→1.0 (damping 0.75) + fade
- 图标点击: scale 0.95→1.0 高亮 (0.1s) → scale→2.0 + alpha→0 放大淡出 (0.3s)
- Reduce Motion 回退: 简单 fade / 直接启动

---

### Task 1.6: 后台线程搜索 ✅

**设计文档:** §9 — 后台线程（`DispatchQueue.global(qos: .userInitiated)`）执行搜索

**完成情况:** 已在 commit `bac5c7d` 中实现
- 非空查询派发到 `DispatchQueue.global(qos: .userInitiated)`
- Stale query 检查：查询变化时丢弃结果
- 空查询在主线程快速处理
- UI 更新始终在主线程

---

<a id="phase-2"></a>
## Phase 2: 拖拽系统集成

> **目标:** 将 DragController 状态机连接到 NSCollectionView，实现完整的拖拽交互
> **预计工期:** 3-4 天（✅ 代码全部实现，交互链已修复）
> **进度:** ✅ Task 2.1-2.4 代码已实现。原 executeAction 空 break 问题已在 commit d92e1af 修复，ESC 退出编辑模式正常工作。

### Task 2.1: NSCollectionView 拖拽 Delegate

**设计文档:** §10 — 通过 NSCollectionViewDelegate 方法链实现内置拖拽

**实现步骤:**

1. **RED — 编写拖拽 delegate 测试**

   在 `Tests/LaunchPadTests/Views/` 创建 `CollectionViewDragTests.swift`：
   ```swift
   // 测试用例:
   // - pasteboardWriterForItemAt 返回 PageItem.uuid
   // - validateDrop 在有效 drop 位置返回 .move
   // - acceptDrop 执行 reorderItems
   // - validateDrop 在边缘位置返回 .generic（触发翻页）
   // - 拖拽取消后恢复原始顺序
   ```

2. **GREEN — 实现拖拽 delegate**

   **修改 `Sources/LaunchPad/Views/AppGridCollectionView.swift`:**

   扩展为 `NSCollectionViewDelegate`（当前只有 `didSelectItemsAt`）：

   ```swift
   extension AppGridCollectionView: NSCollectionViewDelegate {
       // 已有: didSelectItemsAt

       // 新增: 拖拽支持
       public func collectionView(_ collectionView: NSCollectionView,
                                  pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
           guard let item = diffableDataSource.itemIdentifier(for: indexPath) else { return nil }
           let pasteboardItem = NSPasteboardItem()
           pasteboardItem.setString(String(item.id), forType: .string)
           return pasteboardItem
       }

       public func collectionView(_ collectionView: NSCollectionView,
                                  validateDrop draggingInfo: NSDraggingInfo,
                                  proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                                  dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
           // 检测是否在边缘（触发翻页）
           let location = draggingInfo.draggingLocation
           let edgeWidth: CGFloat = 40
           if location.x < edgeWidth || location.x > collectionView.bounds.width - edgeWidth {
               return .generic  // 边缘 = 翻页
           }
           return .move
       }

       public func collectionView(_ collectionView: NSCollectionView,
                                  acceptDrop draggingInfo: NSDraggingInfo,
                                  indexPath: IndexPath,
                                  dropOperation: NSCollectionView.DropOperation) -> Bool {
           // 执行重排
           guard let draggedId = extractDraggedId(from: draggingInfo),
                 let sourceIndexPath = findIndexPath(for: draggedId) else { return false }
           dragController.handleDrop()
           return true
       }
   }
   ```

3. **连接 DragController 到 CollectionView:**
   - `AppGridCollectionView` 添加 `dragController: DragController` 属性
   - 启用 `collectionView.draggingSourceOperationMask = [.move]`

**验收标准:**
- [~] 可以拖拽图标在同页内重排 — 代码已实现（pasteboardWriter/validateDrop/acceptDrop），0% 覆盖率未验证
- [~] 拖拽到边缘触发翻页 — 代码已实现（validateDrop 边缘检测 + DragController.updateDragHover），未验证
- [~] 拖拽取消恢复原始顺序 — 代码已实现（rollbackReorder），未验证

---

### Task 2.2: 编辑模式 UI — 长按手势 + 抖动

**设计文档:** §10 — 长按 0.5s 触发 jiggle mode

**实现步骤:**

1. **RED — 编写 UI 连接测试**

   ```swift
   // 测试用例:
   // - 长按 0.5s 后 AppIconCell.startJiggling 被调用
   // - 移动 > 10px 不触发 jiggle（进入 drag）
   // - ESC 退出 jiggle（所有 cell stopJiggling）
   // - jiggle 时 ✕ 按钮可见
   ```

2. **GREEN — 实现**

   **修改 `Sources/LaunchPad/Controllers/LaunchPadViewController.swift`:**
   - 添加 `NSPressGestureRecognizer` 到 collectionView
   - `handleLongPress` 回调中：
     - `state == .began` → `dragController.handlePressBegan(at:)`
     - `state == .changed` → `dragController.handleDragMoved(to:)`
     - `state == .ended` → `dragController.handlePressEnded()`
   - 监听 `dragController.state` 变化：
     - `.jiggling` → 遍历所有可见 cell 调用 `startJiggling()`
     - `.idle` → 遍历所有可见 cell 调用 `stopJiggling()`

3. **修改 `Sources/LaunchPad/Views/AppIconCell.swift`:**
   - 添加 `deleteButton: NSButton`（✕ 按钮，左上角）
   - `startJiggling()` 时 fade in ✕ 按钮
   - `stopJiggling()` 时 fade out ✕ 按钮
   - ✕ 按钮点击回调：`onDelete: (() -> Void)?`

4. **Reduce Motion 回退:**
   - `startJiggling()` 中检查 `AccessibilitySettings.current().reduceMotion`
   - Reduce Motion 时改为缩放脉冲（scale 1.0→1.05→1.0）

**验收标准:**
- [x] 长按 0.5s 触发所有图标抖动 + ✕ 按钮显示 — ✅ 已实现（NSPressGestureRecognizer + startJiggling + deleteButton）
- [x] ESC 或点击空白退出编辑模式 — ✅ 已修复（executeAction 调用 dragController.handleCancel + updateJiggleState，keyboardNavigator.mode 同步）
- [x] Reduce Motion 时缩放脉冲替代抖动 — ✅ 已实现（AppIconCell.startJiggling 检查 reduceMotion）
- [x] ✕ 按钮点击触发删除流程 — ✅ 已实现（onDelete 回调 + handleItemDelete）

---

### Task 2.3: 跨页拖拽

**设计文档:** §10 — section 间移动 + 边缘自动翻页

**实现步骤:**

1. **RED — 测试:**
   ```swift
   // - 拖拽 item 从 section 0 到 section 1 → ordering 更新
   // - 边缘悬停 1.5s → 自动翻页
   // - 跨页拖拽后 DiffableDataSource 快照正确
   ```

2. **GREEN — 实现:**
   - `AppGridCollectionView` 拖拽 delegate 中检测 drop 目标 section
   - 调用 `dragController.updateDragHover(location:)` 通知边缘悬停
   - `dragController.onPageChange` 回调中执行 `navigateToPage`
   - Drop 时更新 `parentId` + `ordering` + 刷新 DiffableDataSource

**验收标准:**
- [~] 可以将图标从一页拖到另一页 — 代码已实现（acceptDrop section 间移动），未验证
- [~] 边缘悬停自动翻页 — 代码已实现（updateDragHover .screenEdge + onPageChange），未验证
- [~] 拖拽后数据正确持久化 — 代码已实现（commitReorder → reorderItems），未验证

---

### Task 2.4: 拖拽创建文件夹

**设计文档:** §10/§11 — 拖拽 A 到 B 上 hover 0.8s → 自动创建文件夹

**实现步骤:**

1. **GREEN — 连接 DragController.onCreateGroup:**
   - `dragController.onCreateGroup` 回调已在 `LaunchPadViewController.setupCallbacks` 中注册
   - 确保 `handleCreateGroup(targetId:)` 调用 `folderController.createFolder`
   - 创建后刷新 `loadData()`

2. **视觉反馈:**
   - 拖拽悬停在图标上时，目标图标显示"高亮圈"效果（scale 1.1 + 边框）
   - 悬停 0.8s 后显示"创建文件夹"预览动画

**验收标准:**
- [ ] 拖拽 A 到 B 上 0.8s 后创建文件夹
- [ ] 文件夹包含 A 和 B
- [ ] DiffableDataSource 更新显示文件夹 cell

---

<a id="phase-3"></a>
## Phase 3: 分页滚动与动画系统

> **目标:** 实现自定义分页滚动行为，完善动画系统
> **预计工期:** 2-3 天（✅ 代码全部实现）
> **进度:** ✅ 代码全部实现（Task 3.1-3.3），验收标准见各 Task（代码已实现但未手动验证）

### Task 3.1: PageScrollView 自定义分页滚动

**设计文档:** §5 — 重写 `scrollWheel`，双指横滑翻页，弹性回弹

**实现步骤:**

1. **RED — 扩展 PageScrollView 测试:**
   ```swift
   // - scrollWheel .changed phase 正确跟踪滚动位移
   // - scrollWheel .ended phase 根据速度/位移决定目标页
   // - 弹性回弹：首页右滑/末页左滑 → 弹回当前页
   // - 翻页动画 0.35s easeInOut
   ```

2. **GREEN — 实现:**

   **修改 `Sources/LaunchPad/Views/PageScrollView.swift`:**

   ```swift
   public class PageScrollView: NSScrollView {
       private var scrollAccumulator: CGFloat = 0
       private var isScrolling = false

       override public func scrollWheel(with event: NSEvent) {
           if event.phase.contains(.changed) {
               scrollAccumulator += event.scrollingDeltaX
               isScrolling = true
           }

           if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
               guard isScrolling else { return }
               isScrolling = false

               let pageWidth = bounds.width
               guard pageWidth > 0 else { return }

               let currentPage = Int(contentView.bounds.origin.x / pageWidth)
               let totalPages = max(1, Int(documentView!.bounds.width / pageWidth))

               let target = Self.targetPage(
                   for: contentView.bounds.origin.x,
                   velocity: event.scrollingDeltaX,
                   currentPage: currentPage,
                   totalPages: totalPages,
                   pageWidth: pageWidth
               )

               scrollToPage(target, pageWidth: pageWidth)
               scrollAccumulator = 0
           }

           // 弹性回弹：边缘时仍然接受事件但不翻页
           if event.phase.contains(.mayBegin) {
               let atFirstPage = contentView.bounds.origin.x <= 0
               let atLastPage = contentView.bounds.origin.x >= documentView!.bounds.width - bounds.width
               if (atFirstPage && event.scrollingDeltaX > 0) ||
                  (atLastPage && event.scrollingDeltaX < 0) {
                   super.scrollWheel(with: event)
                   return
               }
           }
       }

       private func scrollToPage(_ page: Int, pageWidth: CGFloat) {
           let targetX = CGFloat(page) * pageWidth
           NSAnimationContext.runAnimationGroup { ctx in
               ctx.duration = AnimationConstants.pageScroll.duration
               ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
               contentView.animator().bounds.origin.x = targetX
           }
       }
   }
   ```

3. **配置弹性:**
   - `horizontalScrollElasticity = .allowed`

**验收标准:**
- [~] 双指横滑可以翻页 — ⚠️ 代码已实现（scrollWheel 重写），但 PageScrollView 覆盖率 40%，未手动验证
- [~] 快速短滑也能触发翻页（速度阈值） — ⚠️ targetPage 纯函数已测，scrollWheel 集成未测
- [~] 首页右滑/末页左滑有弹性回弹 — ⚠️ 代码已实现，未验证
- [~] 翻页动画 0.35s easeInOut — ⚠️ scrollToPage 已实现，但 navigateToPage 绕过此方法

---

### Task 3.2: 图标入场动画

**设计文档:** §12 — 图标入场: 每个 cell 延迟 `colIndex * 0.02s`，从左到右"铺开"

**实现步骤:**

1. **修改 `Sources/LaunchPad/Views/AppGridCollectionView.swift`:**
   - 在 `reload()` 方法中，apply snapshot 后遍历可见 cell
   - 对每个 cell：初始 `alphaValue = 0` + `transform = scale(0.8)`
   - 按 `colIndex * AnimationConstants.iconEntranceDelayPerColumn` 延迟
   - 动画：`NSAnimationContext` 0.3s spring → `alphaValue = 1` + identity transform

2. **Reduce Motion:** 直接显示无动画

**验收标准:**
- [~] LaunchPad 打开时图标从左到右依次"铺开" — ⚠️ animateEntrance 已实现，覆盖率 0%
- [~] Reduce Motion 时直接显示 — ⚠️ 代码已实现，覆盖率 0%

---

### Task 3.3: 已运行应用小圆点指示器

**设计文档:** §12 — 已运行应用显示小圆点指示器

**实现步骤:**

1. **修改 `Sources/LaunchPad/Views/AppIconCell.swift`:**
   - 添加 `runningIndicator: NSView`（小圆点，3x3pt，位于图标底部居中）
   - `configure(item:icon:)` 中检查 `NSWorkspace.shared.runningApplications` 是否包含该 bundleId
   - 显示/隐藏 `runningIndicator`

2. **可选:** 监听 `NSWorkspace.didActivateApplicationNotification` 更新状态

**验收标准:**
- [~] 正在运行的应用底部显示小圆点 — ⚠️ runningIndicator 已实现，覆盖率 0%
- [~] 关闭应用后小圆点消失 — ⚠️ updateRunningState 已实现，但未监听 NSWorkspace 通知实时更新

---

<a id="phase-4"></a>
## Phase 4: 文件夹系统完善

> **目标:** 完善文件夹的所有交互行为
> **预计工期:** 2-3 天（✅ 已完成 5/5）
> **进度:** ✅ Task 4.1, 4.2, 4.3, 4.4, 4.5 代码已实现

### Task 4.1: 文件夹弹窗响应式尺寸

**设计文档:** §11 — 60% 屏幕宽度，最大 70% 屏幕高度

**实现步骤:**

1. **修改 `Sources/LaunchPad/Views/FolderOverlayView.swift`:**
   - 移除 `backgroundView` 的固定宽高约束
   - 改为相对于父视图：
     ```swift
     backgroundView.widthAnchor.constraint(equalTo: superview!.widthAnchor, multiplier: 0.6)
     backgroundView.heightAnchor.constraint(lessThanOrEqualTo: superview!.heightAnchor, multiplier: 0.7)
     ```
   - 添加最大宽度/高度限制（防止超大屏幕）

2. **修改 `Sources/LaunchPad/Controllers/LaunchPadViewController.swift`:**
   - 移除 FolderOverlayView 的固定 320×360 约束（已在修复 #8 中改为覆盖全屏）
   - 确保 backgroundView 约束生效

**验收标准:**
- [~] 文件夹弹窗大小随屏幕尺寸变化 — ⚠️ openFolder 响应式尺寸已实现，覆盖率 0%
- [~] 不超过屏幕 70% 高度 — ⚠️ 代码已实现，覆盖率 0%

---

### Task 4.2: FolderOverlayView Scale 弹出动画

**设计文档:** §11 — scale 0.8→1.0 + fade in，0.25s，spring(damping: 0.8)

**实现步骤:**

1. **修改 `FolderOverlayView.openFolder()`:**
   ```swift
   isHidden = false
   backgroundView.layer?.transform = CATransform3DMakeScale(0.8, 0.8, 1)

   let settings = AccessibilitySettings.current()
   if settings.reduceMotion {
       // Reduce Motion: fade 0.15s
       NSAnimationContext.runAnimationGroup({ ctx in
           ctx.duration = 0.15
           animator().alphaValue = 1
       })
   } else {
       // 正常: scale + fade
       NSAnimationContext.runAnimationGroup({ ctx in
           ctx.duration = AnimationConstants.folderExpand.duration
           animator().alphaValue = 1
       })
       let spring = CASpringAnimation(keyPath: "transform.scale")
       spring.fromValue = 0.8
       spring.toValue = 1.0
       spring.damping = 0.8
       backgroundView.layer?.add(spring, forKey: "scaleIn")
   }
   ```

**验收标准:**
- [~] 文件夹弹出有 Spring 缩放动画 — ⚠️ CASpringAnimation 已实现，覆盖率 0%
- [ ] Reduce Motion 时 fade

---

### Task 4.3: 文件夹内部网格分页 ✅

**设计文档:** §11 — 最多 35 个/页，超出显示页码点

**完成情况:** 已在 commit `28e7dd6` 中实现
- `FolderOverlayView.paginateItems` 纯函数将 items 按 35 个/页拆分
- 水平分页滚动（`NSCollectionViewFlowLayout` + `scrollDirection = .horizontal`）
- 每个 section 代表一页，`PageControlView` 底部显示页码点
- 滚动位置变化自动同步页码指示器
- 8 个新测试覆盖分页逻辑

**验收标准:**
- [x] 超过 35 个应用的文件夹支持分页 — ✅ 已实现（每页 section 最多 35 个 item）
- [x] 底部显示页码点 — ✅ 已实现（PageControlView + observeScrollPosition）

---

### Task 4.4: 文件夹自动解散

**设计文档:** §11 — 移出至只剩 1 个 → 自动解散

**实现步骤:**

1. **修改 `Sources/LaunchPad/Controllers/FolderController.swift`:**
   ```swift
   public func removeFromFolder(item: PageItem, targetPageId: Int64, targetOrdering: Int, writer: ItemWriting) throws {
       var updated = item
       updated.parentId = targetPageId
       updated.ordering = targetOrdering
       try writer.updateItem(updated)

       // 新增: 检查剩余子项数
       // 如果只剩 1 个，自动解散
       // 注意: 需要 ItemReading 来查询子项数
   }
   ```

2. **调整 `removeFromFolder` 签名:** 添加 `reader: ItemReading` 参数

3. **RED — 测试:**
   ```swift
   // - 文件夹有 2 个子项，移出 1 个 → 自动解散
   // - 文件夹有 3 个子项，移出 1 个 → 不解散
   // - 解散后子项回到主网格
   ```

**验收标准:**
- [x] 文件夹剩余 1 个子项时自动解散 — ✅ 已实现且有测试（FolderControllerTests）
- [x] 解散后子项回到原来页面 — ✅ 已实现且有测试

---

### Task 4.5: FolderCell 毛玻璃背景

**设计文档:** §11 — 圆角矩形毛玻璃背景

**实现步骤:**

1. **修改 `Sources/LaunchPad/Views/FolderCell.swift`:**
   - 在 `loadView()` 中添加 `NSVisualEffectView` 作为 `containerView` 的背景
   - `blendingMode = .withinWindow`，`material = .hudWindow`
   - `cornerRadius = 8`

2. **Reduce Transparency 回退:**
   - 检查 `AccessibilitySettings.current().reduceTransparency`
   - 开启时使用纯色背景 `NSColor.windowBackgroundColor`

**验收标准:**
- [~] 文件夹 Cell 有圆角毛玻璃背景 — ⚠️ frostedBackground 已实现，覆盖率 0%
- [~] Reduce Transparency 时使用纯色 — ⚠️ 代码已实现，覆盖率 0%

---

<a id="phase-5"></a>
## Phase 5: 扫描与系统集成

> **目标:** 实现 FSEvents 监控和多显示器支持
> **预计工期:** 2-3 天（✅ 代码全部实现）
> **进度:** ✅ 代码全部实现（Task 5.1-5.4），验收标准见各 Task（代码已实现，但无 .app bundle 无法实测）

### Task 5.1: FSEvents 文件系统监控

**设计文档:** §7 — FSEvents API 监控 `/Applications` 和 `~/Applications`

**实现步骤:**

1. **创建 `Sources/LaunchPad/Services/FileWatcher.swift`:**
   ```swift
   public final class FileWatcher {
       private var stream: FSEventStreamRef?

       public func start(paths: [String], onChange: @escaping @Sendable () -> Void) {
           let callback: FSEventStreamCallback = { _, _, _, _, _, _ in
               onChange()
           }
           // FSEventStreamCreate + FSEventStreamScheduleWithRunLoop + FSEventStreamStart
       }

       public func stop() {
           // FSEventStreamStop + FSEventStreamInvalidate + FSEventStreamRelease
       }
   }
   ```

2. **集成到 AppDelegate:**
   - `setupServices()` 中创建 `FileWatcher`
   - 监控路径：`/Applications`、`~/Applications`、`/System/Applications`
   - 变化回调：调用 `performInitialScan()` 中的增量同步逻辑
   - 添加防抖（避免批量安装时频繁触发）

3. **RED — 测试:**
   ```swift
   // - 文件系统变化触发回调
   // - 回调防抖（100ms 内多次变化只触发一次）
   // - stop() 后不再触发回调
   ```

**验收标准:**
- [~] 安装新应用后自动出现在 LaunchPad — ⚠️ FileWatcher + incrementalSync 已实现，FileWatcher 覆盖率 0%
- [~] 卸载应用后自动从 LaunchPad 移除 — ⚠️ 同上，未验证
- [~] 不会因批量操作频繁触发扫描 — ⚠️ debounceInterval=2.0 已实现，未验证

---

### Task 5.2: 多显示器支持 ✅

**设计文档:** §3 — 在鼠标所在屏幕显示

**完成情况:** 已在 commit `5cebeff` 中实现，`showWindowAnimated()` 使用 `NSEvent.mouseLocation` + `NSScreen.screens.first(where:)`

**验收标准:**
- [x] LaunchPad 在鼠标所在的显示器上显示 — ✅ NSEvent.mouseLocation 已实现

---

### Task 5.3: 多实例防护

**设计文档:** §1 — NSRunningApplication 检测已有实例

**实现步骤:**

1. **修改 `Sources/LaunchPad/App/AppDelegate.swift` `applicationDidFinishLaunching`:**
   ```swift
   let bundleId = Bundle.main.bundleIdentifier ?? ""
   let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
   if running.count > 1 {
       // 激活已有实例，退出当前
       running.first?.activate()
       NSApp.terminate(nil)
       return
   }
   ```

**验收标准:**
- [~] 双击启动第二个实例时，激活已有实例并退出 — ⚠️ 代码已实现（AppDelegate:36），但无 .app bundle 无法实测

---

### Task 5.4: 登录自启动

**设计文档:** §1 — SMAppService.mainApp.register()

**实现步骤:**

1. **修改 `Sources/LaunchPad/App/AppDelegate.swift`:**
   - 在菜单栏添加"开机自启"选项
   - 点击切换 `SMAppService.mainApp.register()` / `unregister()`
   - 菜单项显示当前状态（✓ 或无）

**验收标准:**
- [~] 菜单栏可切换开机自启 — ⚠️ SMAppService 已实现，但无 .app bundle 无法实测
- [~] 状态正确持久化 — ⚠️ 代码已实现，无 .app bundle 无法实测

---

<a id="phase-6"></a>
## Phase 6: 无障碍与视觉打磨

> **目标:** 完善无障碍支持和视觉细节
> **预计工期:** 2-3 天（✅ 代码全部实现 11/11）
> **进度:** ✅ 代码全部实现（Task 6.1-6.11），验收标准见各 Task（代码已实现但 0% 覆盖率，未手动验证）

### Task 6.1: AppIconCell 图标尺寸自适应

**设计文档:** §5 — 图标尺寸从 GridLayoutCalculator 获取（64~96pt）

**实现步骤:**

1. **修改 `AppIconCell.configure(item:icon:)`:**
   - 添加 `iconSize: CGFloat` 参数
   - 约束使用传入的 `iconSize` 而非硬编码 64

2. **修改 `AppGridCollectionView.configureCell`:**
   - 从 `gridParams` 获取当前 `iconSize` 传递给 cell

**验收标准:**
- [~] 不同屏幕宽度下图标尺寸自适应（64~96pt） — 代码已实现（AppIconCell.configure 接收 iconSize），未验证

---

### Task 6.2: VoiceOver Grid 结构

**设计文档:** §14 — `accessibilityRows` / `accessibilityColumns`

**实现步骤:**

1. **修改 `AppGridCollectionView`:**
   ```swift
   override public func accessibilityRows() -> [Any]? {
       // 按 section（页面）返回行
       return sections.map { section in
           // 返回每行的 accessibility element
       }
   }
   ```

2. **修改 `AppIconCell`:**
   - 添加 `accessibilityDescription`（应用描述）

**验收标准:**
- [~] VoiceOver 能正确读出网格结构（行×列） — 代码已实现（accessibilityRows），0% 覆盖
- [~] 每个 Cell 有 label + description — 代码已实现（setAccessibilityLabel），0% 覆盖

---

### Task 6.3: Increase Contrast 应用

**设计文档:** §14 — 增强图标边框和文字对比度

**实现步骤:**

1. **修改 `AppIconCell`:**
   - `configure` 中检查 `AccessibilitySettings.current().increaseContrast`
   - 开启时添加边框（`layer?.borderWidth = 1, borderColor`）+ 文字加粗

2. **修改 `FolderCell`:** 类似处理

**验收标准:**
- [~] Increase Contrast 开启时图标有明显边框 — 代码已实现（AppIconCell.configure），0% 覆盖
- [~] 文字对比度增强 — 代码已实现（semibold font），0% 覆盖

---

### Task 6.4: CGEventTap 权限检查与引导 ✅

**设计文档:** §4 — AXIsProcessTrusted() 检查 + 引导用户授权

**完成情况:** 已在 commit `5cebeff` 中实现。`HotkeyManager.registerGlobalHotkey` 入口处检查 `AXIsProcessTrusted()`，无权限时返回 false（由调用方决定如何引导用户）

**验收标准:**
- [x] 无权限时 `registerGlobalHotkey` 返回 false
- [x] 首次启动无权限时弹出引导 — ✅ 已实现（commit 86f8344，弹出 alert + "打开系统设置"按钮直达 Input Monitoring 设置页）

---

### Task 6.5: CGEventTap 快捷键冲突处理

**设计文档:** §4 — Option+Space 被占用时提示用户

**实现步骤:**

1. **修改 `HotkeyManager.registerGlobalHotkey`:**
   - 如果 `CGEvent.tapCreate` 返回 nil（被拒绝），检测是否已有应用占用
   - 弹窗提示用户选择其他快捷键或关闭冲突应用

**验收标准:**
- [~] 快捷键冲突时有友好提示 — 代码已实现（hasConflict + NSAlert），0% 覆盖

---

### Task 6.6: FolderCell 可编辑名称

**设计文档:** §11 — 双击文件夹名称进入编辑模式

**实现步骤:**

1. **修改 `FolderCell`:**
   - `titleLabel` 改为 `NSTextField`（可编辑）
   - 默认 `isEditable = false`
   - 双击设置 `isEditable = true` + `becomeFirstResponder()`
   - 编辑完成（Enter/失焦）→ `isEditable = false` → 回调 `onRenamed`

2. **连接 `FolderController.renameFolder`**

**验收标准:**
- [~] 双击文件夹名称可以重命名 — 代码已实现（FolderCell handleDoubleClick + controlTextDidEndEditing），0% 覆盖
- [~] Enter 或点击外部完成编辑 — 代码已实现（controlTextDidEndEditing），0% 覆盖

---

### Task 6.7: 搜索结果计数显示

**设计文档:** §9 — 可选显示结果计数

**实现步骤:**

1. **修改 `LaunchPadViewController.handleSearch`:**
   - 在 `pageControl` 位置显示 "N results" 文本（搜索模式下替换页码点）

**验收标准:**
- [~] 搜索时显示匹配结果数量 — 代码已实现（resultCountLabel），0% 覆盖

---

### Task 6.8: 图标 @1x 128×128 缩放

**设计文档:** §8 — @1x: 128×128pt

**实现步骤:**

1. **修改 `IconCache.storeToDisk`:**
   - 将原始图标缩放到 128×128pt 后再存储为 icon_1x

**验收标准:**
- [x] 磁盘缓存中 icon_1x 为 128×128pt 尺寸 — ✅ 已实现（IconCache storeToDisk）

---

### Task 6.9: 文件夹预览图合成缓存

**设计文档:** §11 — 取前 9 个子应用图标，缩小 40%，3×3 合成

**实现步骤:**

1. **创建 `Sources/LaunchPad/Services/FolderThumbnailGenerator.swift`:**
   - `static func generate(childIcons: [NSImage]) -> NSImage`
   - 取前 9 个图标，每个缩小 40%
   - 按 3×3 排列，`NSImage(size:drawIn:)` 合成
   - 缓存到 `image_cache` 表

2. **在 `FolderController.createFolder` 和 `addToFolder` 中调用**

**验收标准:**
- [~] 文件夹 Cell 显示 3×3 缩略预览 — 代码已实现（FolderCell + FolderThumbnailGenerator），0% 覆盖
- [~] 添加/移除子应用后预览更新 — 代码已实现，0% 覆盖

---

### Task 6.10: 拖拽预览生成

**设计文档:** §10 — 自定义拖拽时的半透明图标

**实现步骤:**

1. **修改 `AppGridCollectionView`:**
   ```swift
   func collectionView(_ collectionView: NSCollectionView,
                       draggingImageForItemsAt indexPaths: Set<IndexPath>,
                       with event: NSEvent,
                       offset dragImageOffset: NSPoint) -> NSImage? {
       guard let indexPath = indexPaths.first,
             let cell = collectionView.item(at: indexPath) else { return nil }
       // 截取 cell 内容，设置半透明
       let image = NSImage(size: cell.view.bounds.size)
       image.lockFocus()
       cell.view.draw(cell.view.bounds)
       image.unlockFocus()
       image.size = NSSize(width: 64, height: 64)
       return image
   }
   ```

**验收标准:**
- [~] 拖拽时显示半透明图标预览 — 代码已实现（draggingImageForItemsAt），0% 覆盖

---

### Task 6.11: LoginItems 排除列表读取

**设计文档:** §7 — 读取系统 LaunchPadLayout.plist 排除列表

**实现步骤:**

1. **修改 `AppScanner`:**
   - 在 init 或首次扫描时读取 `~/Library/Application Support/Dock/LaunchPadLayout.plist`
   - 解析排除的 bundleId 列表
   - `isExcluded(bundleId:)` 中检查该列表

**验收标准:**
- [~] 系统 LaunchPad 中排除的应用不会出现在自定义 LaunchPad 中 — 代码已实现（AppScanner 读取 LaunchPadLayout.plist），0% 覆盖

---

<a id="phase-7"></a>
## Phase 7: 测试补充与技术债务

> **目标:** 补充缺失测试，修复技术债务
> **预计工期:** 2-3 天（部分完成）
> **进度:** ⚠️ Task 7.1 测试数达标（302），但覆盖率仅 63%；Task 7.2 技术债务 TD-1/4/5/6 已修复，TD-2 未修复，TD-3 部分改善

### Task 7.1: 补充缺失测试

| 缺失测试 | 优先级 | 对应 Phase |
|----------|--------|-----------|
| 搜索防抖 4 个用例 | P0 | Phase 1 Task 1.1 |
| 首次启动集成 3 个用例 | P0 | Phase 7 |
| StorageManager 三层嵌套 | P1 | Phase 7 |
| 跨页拖拽 ordering 验证 | P1 | Phase 2 Task 2.3 |
| 文件夹预览图生成 | P1 | Phase 6 Task 6.9 |

**首次启动集成测试补充:**
```swift
// - 100 个应用 + 35 每页 → 创建 3 页，最后一页 30 项
// - 应用按字母顺序排列，跨页连续
// - 被过滤应用不出现在网格中
```

**StorageManager 三层嵌套:**
```swift
// - page → group → items 正确解析
// - 删除 group → items 级联删除
```

**验收标准:**
- [ ] 所有设计文档 §16 要求的测试用例已覆盖 — ❌ 2026-06-20 实测行覆盖率仅 63.13%，LaunchPadViewController 等核心控制器 0% 覆盖
- [x] 测试总数 ≥ 300 — ✅ 实测 302 tests / 35 suites 全部通过

---

### Task 7.2: 修复技术债务

| 编号 | 问题 | 修复方案 |
|------|------|---------|
| TD-1 | HotkeyManager unregister 内存管理不对称 | 统一使用类级 retained 引用 |
| TD-2 | StorageManager fetchAllItems 阻塞写队列 | 引入独立读队列 |
| TD-3 | insertItem/updateItem 事务风格不一致 | 统一使用 committed 标志 |
| TD-4 | ErrorRecovery 总返回 deleteAndRescan | 添加 PRAGMA integrity_check |
| TD-5 | IconCache 磁盘失效比较 TIFF | 改为比较 modificationDate 哈希 |
| TD-6 | AppGridCollectionView 引用 IconCache 具体类 | 抽象为 IconCaching 协议 |

**验收标准:**
- [ ] 6 项技术债务全部修复 — ❌ TD-1/4/5/6 已修复，TD-2 未修复（无独立读队列），TD-3 部分改善（均用事务但风格仍不一致）
- [x] 编译 0 warning — ✅ swift build 0 errors, 0 warnings
- [x] 所有测试通过 — ✅ 302 tests 全部通过

---

<a id="phase-8"></a>
## Phase 8: 性能优化与收尾

> **目标:** 性能基准测试和最终打磨
> **预计工期:** 1-2 天（部分完成）
> **进度:** ⚠️ Task 8.1/8.2 已完成；Task 8.3 最终集成验证未执行——无 .app 可运行，13 项手动功能验证全部未做

### Task 8.1: 性能基准测试

**设计文档:** §17 Phase 7 REFACTOR — 1000+ 图标加载、搜索响应 < 50ms

**实现步骤:**

1. **创建 `Tests/LaunchPadTests/Performance/PerformanceTests.swift`:**
   ```swift
   // - 1000 个 PageItem 生成 + DiffableDataSource apply < 1s
   // - 搜索 1000 个 item 响应时间 < 50ms
   // - IconCache 1000 次随机访问无内存泄漏
   ```

**验收标准:**
- [x] 1000+ 图标加载性能达标 — ✅ PerformanceTests 实测通过（1000 项 snapshot 构建 < 10ms）
- [x] 搜索响应 < 50ms — ✅ 实测搜索 1000 项 < 50ms

---

### Task 8.2: Reduce Motion 统一拦截层

**当前状态:** 各动画点分散检查 Reduce Motion，缺乏统一拦截

**实现步骤:**

1. **创建动画执行 Helper:**
   ```swift
   enum AnimationRunner {
       static func animate(
           settings: AccessibilitySettings = .current(),
           normal: () -> Void,
           reduced: () -> Void
       ) {
           if settings.reduceMotion { reduced() } else { normal() }
       }
   }
   ```

2. **统一所有动画调用点使用此 Helper**

**验收标准:**
- [x] 主要动画点使用 AnimationRunner — ✅ AppGridCollectionView、FolderOverlayView、WindowController 已统一使用（commit 7d15237）
- [x] Reduce Motion 全局生效 — ✅ 关键动画路径已走 AnimationRunner，AppIconCell 的 jiggle 因 CAKeyframeAnimation 特殊性保留直接检查

---

### Task 8.3: 最终集成验证 — ⚠️ 部分完成

1. **运行全部测试:** `swift test` — ✅ 实测 302 tests / 35 suites 全部通过（2026-06-20）
2. **编译检查:** `swift build` — ✅ 0 errors, 0 warnings（2026-06-20 实测）
3. **手动功能验证清单:** — ❌ 全部未执行（无 .app 可运行，无法进行手动验证）
   - [ ] Option+Space 唤起/关闭 LaunchPad
   - [ ] 图标网格正确显示（3 种屏幕宽度）
   - [ ] 双指横滑翻页 + 页码点同步
   - [ ] 搜索输入 + 防抖 + 清空恢复
   - [ ] 点击图标启动应用 + 三阶段动画
   - [ ] 长按进入编辑模式 + 抖动 + ✕ 按钮
   - [ ] 拖拽重排 + 跨页拖拽
   - [ ] 拖拽创建文件夹
   - [ ] 文件夹打开/关闭/重命名
   - [ ] VoiceOver 可读
   - [ ] Reduce Motion / Reduce Transparency 生效
   - [ ] 多显示器正确显示
   - [ ] 新安装应用自动出现

---

<a id="技术债务"></a>
## 技术债务清单

| 编号 | 问题 | 所在文件 | 风险 | 修复 Phase |
|------|------|---------|------|-----------|
| TD-1 | ~~unregisterGlobalHotkey 内存管理不对称~~ | HotkeyManager:117 | 中 | ✅ 已修复 |
| TD-2 | ~~fetchAllItems 在写队列同步执行~~ | StorageManager | 低 | ✅ 已修复（独立 readQueue） |
| TD-3 | ~~insert/updateItem 事务风格不一致~~ | StorageManager | 低 | ✅ 已修复（统一使用 committed 标志 + ROLLBACK） |
| TD-4 | ~~handleSQLiteCorruption 无真正检测~~ | ErrorRecovery | 低 | ✅ 已修复（已加 PRAGMA integrity_check） |
| TD-5 | ~~IconCache 磁盘失效比较 TIFF~~ | IconCache | 低 | ✅ 已修复（改用 modificationDate） |
| TD-6 | ~~AppGridCollectionView 引用 IconCache 具体类~~ | AppGridCollectionView | 低 | ✅ 已修复（抽象为 IconCaching 协议） |

---

<a id="验收标准"></a>
## 验收标准总览

> **2026-06-20 上线就绪复核结果：** 以下勾选状态为实测值，非原始计划值。

### 编译
- [x] `swift build` — 0 errors, 0 warnings（实测通过）

### 测试
- [x] `swift test` — ≥ 300 tests pass（实测 302 tests / 35 suites 全部通过）
- [ ] 设计文档 §16 所有测试用例 100% 覆盖 — ❌ 实测行覆盖率仅 63.13%（4957/7852），函数覆盖率 65.39%
  - LaunchPadViewController 0%（529 行）、AppDelegate 0%、LaunchPadWindowController 0%
  - AppGridCollectionView / AppIconCell / FolderOverlayView / FolderCell / SearchBar / PageControl / EmptyStateView / AppGridFlowLayout / FileWatcher / LayoutPersistence / AnimationRunner 均为 0%
  - HotkeyManager 37.30%、PageScrollView 40.14%、StorageManager 71.80%

### 功能完整度
- [x] P0 (5 项) 代码已实现（拖拽 delegate、分页滚动 scrollWheel、搜索防抖、启动动画、编辑模式 UI）
- [x] P0 行为缺陷已修复：.closeWindow → onClose 回调、.exitEditMode → handleCancel + updateJiggleState、moveUp/moveDown/selectNext → moveSelection（方向键导航）
- [~] P1 — 多数已实现，FolderOverlayView 内部分页（Task 4.3）仍未实现
- [~] P2 — 多数已实现
- [~] 技术债务 (6 项) — TD-1/4/5/6 已修复，TD-2 未修复（无独立读队列），TD-3 部分改善（均用事务，但 insertItem 用 defer COMMIT、updateItem 用 committed 标志，风格仍不完全一致）

### 手动验证
- [ ] 全部 13 项手动功能验证通过 — ❌ 未执行（无 .app 可运行）

### 发布阻塞项（上线前必须解决）
1. **无 .app 打包配置** — Package.swift 仅声明 .library，无 Xcode 项目 / Info.plist / entitlements / 签名公证流水线。无法配置 LSUIElement、权限声明，无法分发。
2. **测试覆盖率 63.13%，未达 100% 目标** — 核心协调器 LaunchPadViewController 及全部视图层 0% 覆盖。
3. ~~**核心键盘交互为空实现**~~ ✅ 已修复（commit d92e1af）— executeAction 的 .closeWindow/.exitEditMode/.moveUp/.moveDown/.selectNext 均已正确实现。
4. ~~**navigateToPage 绕过分页动画**~~ ✅ 已修复 — 改用 `scrollView.scrollToPage(index)` 获得 0.35s easeInOut 动画。
5. ~~**FolderOverlayView 未实现内部分页（Task 4.3）**~~ ✅ 已实现 — 水平分页滚动 + PageControl 页码点（commit 28e7dd6）。
6. **.nonactivatingPanel 键盘焦点待验证** — 可能导致窗口无法成为 key window 收不到键盘事件。

### 最终完成度目标
- **实测（2026-06-21 更新）:** 代码实现度高（P0 功能均已编码），行为缺陷已修复（B3/B4），上线就绪度受覆盖率 63% 和无打包配置阻塞
- **达到上线预估:** 6-10 个工作日（打包配置 + ViewController 集成测试 + 覆盖率补齐）

---

## 工期估算总览（2026-06-21 更新）

> **状态变化:** Phase 1-6 的代码实现已全部完成。原计划的 32 个 Task 中，仅 Task 4.3（文件夹内分页）
> 未实现。executeAction 空实现和 navigateToPage 动画问题已在 commit d92e1af 修复。
> 剩余工作量集中在上线就绪（测试覆盖率、打包配置），而非功能开发或行为缺陷修复。

| 工作项 | 内容 | 预计工期 | 累计 |
|--------|------|---------|------|
| ViewController 集成测试 | LaunchPadViewController（529 行）0% 覆盖，补集成测试 | 2-3 天 | 3 天 |
| App/View 层测试 | AppDelegate / WindowController / 12 个视图文件 0% 覆盖，补测试拉至 90%+ | 3-5 天 | 8 天 |
| .app 打包配置 | 创建 Xcode 工程 + Info.plist + entitlements + 签名/公证流水线 | 1-2 天 | 10 天 |
| FolderOverlayView 分页 | Task 4.3 实现文件夹内部分页 + 页码点 | 1-2 天 | 12 天 |
| **合计** | | — | **6-10 天** |

> **前提:** 以上工期遵循 TDD 约束——每项修复先写失败测试，再实现。覆盖率目标 100%（项目硬性要求）。
