# Task 19 FolderOverlay 测试迁移映射

## 迁移约束

- `FolderOverlayViewTests` 使用 `@MainActor @Suite("FolderOverlayView")`，每个测试创建独立 overlay。
- 迁移只移除旧方法名的 `test` 前缀并小写下一字符；不合并、拆分或删除测试。
- 原断言逐项迁移为 `#expect`/`#require`；completion 与 `.main` notification 均同步断言，不保留固定等待或 RunLoop polling。
- migration commit 必须保持 production diff 为空。brief Step 2 示例引用的 `folderViewportSizeProvider` 直到 Step 7 才存在，因此该注入将在 behavior commit 随生产 API 一起补入。

## Qualified ID 映射

| 旧 qualified ID | 新 qualified ID | Assertion | Actor | Fixture | Cleanup |
| --- | --- | --- | --- | --- | --- |
| `LaunchPadTests.FolderOverlayViewTests/testInit_doesNotCrash` | `LaunchPadTests.FolderOverlayViewTests/init_doesNotCrash()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 `makeOverlay()` | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testInit_isHiddenByDefault` | `LaunchPadTests.FolderOverlayViewTests/init_isHiddenByDefault()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 `makeOverlay()` | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testInit_alphaIsZero` | `LaunchPadTests.FolderOverlayViewTests/init_alphaIsZero()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 `makeOverlay()` | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testPaginateItems_empty_returnsEmpty` | `LaunchPadTests.FolderOverlayViewTests/paginateItems_empty_returnsEmpty()` | 1 个原断言逐项迁移 | `@MainActor` suite | 调用 `makeOverlay()` 后测纯函数 | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testPaginateItems_lessThanPageSize_returnsSinglePage` | `LaunchPadTests.FolderOverlayViewTests/paginateItems_lessThanPageSize_returnsSinglePage()` | 2 个原断言逐项迁移 | `@MainActor` suite | 调用 `makeOverlay()` 后测纯函数 | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testPaginateItems_exactPageSize_returnsSinglePage` | `LaunchPadTests.FolderOverlayViewTests/paginateItems_exactPageSize_returnsSinglePage()` | 2 个原断言逐项迁移 | `@MainActor` suite | 调用 `makeOverlay()` 后测纯函数 | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testPaginateItems_moreThanPageSize_returnsMultiplePages` | `LaunchPadTests.FolderOverlayViewTests/paginateItems_moreThanPageSize_returnsMultiplePages()` | 4 个原断言逐项迁移 | `@MainActor` suite | 调用 `makeOverlay()` 后测纯函数 | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testPaginateItems_zeroPageSize_returnsEmpty` | `LaunchPadTests.FolderOverlayViewTests/paginateItems_zeroPageSize_returnsEmpty()` | 1 个原断言逐项迁移 | `@MainActor` suite | 调用 `makeOverlay()` 后测纯函数 | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testPaginateItems_negativePageSize_returnsEmpty` | `LaunchPadTests.FolderOverlayViewTests/paginateItems_negativePageSize_returnsEmpty()` | 1 个原断言逐项迁移 | `@MainActor` suite | 调用 `makeOverlay()` 后测纯函数 | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testOpenFolder_showsOverlay` | `LaunchPadTests.FolderOverlayViewTests/openFolder_showsOverlay()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 `makeOverlay()` | 同步 completion runner |
| `LaunchPadTests.FolderOverlayViewTests/testOpenFolder_setsTitle` | `LaunchPadTests.FolderOverlayViewTests/openFolder_setsTitle()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 `makeOverlay()` | 同步 completion runner |
| `LaunchPadTests.FolderOverlayViewTests/testOpenFolder_responsiveSize` | `LaunchPadTests.FolderOverlayViewTests/openFolder_responsiveSize()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 `makeOverlay()` | 同步 completion runner |
| `LaunchPadTests.FolderOverlayViewTests/testOpenFolder_reduceMotion_usesReducedBranch` | `LaunchPadTests.FolderOverlayViewTests/openFolder_reduceMotion_usesReducedBranch()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 settings provider | 无固定等待 |
| `LaunchPadTests.FolderOverlayViewTests/testCollectionView_dataSource_withAppAndIconCache_loadsIcon` | `LaunchPadTests.FolderOverlayViewTests/collectionView_dataSource_withAppAndIconCache_loadsIcon()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 window、cache、overlay | 无固定等待 |
| `LaunchPadTests.FolderOverlayViewTests/testCloseFolder_hidesOverlay` | `LaunchPadTests.FolderOverlayViewTests/closeFolder_hidesOverlay()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 `makeOverlay()` | 同步 completion runner |
| `LaunchPadTests.FolderOverlayViewTests/testCloseFolder_callsOnClosedCallback` | `LaunchPadTests.FolderOverlayViewTests/closeFolder_callsOnClosedCallback()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 callback | 同步 completion runner |
| `LaunchPadTests.FolderOverlayViewTests/testOnAppSelected_callbackIsSettable` | `LaunchPadTests.FolderOverlayViewTests/onAppSelected_callbackIsSettable()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 callback | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testOnClosed_callbackIsSettable` | `LaunchPadTests.FolderOverlayViewTests/onClosed_callbackIsSettable()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 callback | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testMouseDown_outsidePanel_closesFolder` | `LaunchPadTests.FolderOverlayViewTests/mouseDown_outsidePanel_closesFolder()` | 5 个 Step 1 断言/require 逐项迁移 | `@MainActor` suite | layout 后 panel 外点 | 同步 completion；无 wait |
| `LaunchPadTests.FolderOverlayViewTests/testOpenFolder_withManyItems_paginates` | `LaunchPadTests.FolderOverlayViewTests/openFolder_withManyItems_paginates()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 80-item fixture | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testOpenFolder_withExactly35Items_singlePage` | `LaunchPadTests.FolderOverlayViewTests/openFolder_withExactly35Items_singlePage()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 35-item fixture | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testOpenFolder_withNoTitle_usesDefaultTitle` | `LaunchPadTests.FolderOverlayViewTests/openFolder_withNoTitle_usesDefaultTitle()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 nil-title fixture | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testCloseThenReopen_doesNotCrash` | `LaunchPadTests.FolderOverlayViewTests/closeThenReopen_doesNotCrash()` | 原 no-crash 路径原样保留 | `@MainActor` suite | 独立 `makeOverlay()` | 同步 completion runner |
| `LaunchPadTests.FolderOverlayViewTests/testObserveScrollPosition_doesNotCrash` | `LaunchPadTests.FolderOverlayViewTests/observeScrollPosition_doesNotCrash()` | 原 no-crash 路径原样保留 | `@MainActor` suite | 独立 `makeOverlay()` | 无 RunLoop polling |
| `LaunchPadTests.FolderOverlayViewTests/testInitCoder_producesValidInstance` | `LaunchPadTests.FolderOverlayViewTests/initCoder_producesValidInstance()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 archiver/unarchiver | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testNumberOfSections_returnsCorrectCount` | `LaunchPadTests.FolderOverlayViewTests/numberOfSections_returnsCorrectCount()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 40-item fixture | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testNumberOfItemsInSection_returnsCorrectCount` | `LaunchPadTests.FolderOverlayViewTests/numberOfItemsInSection_returnsCorrectCount()` | 2 个原断言逐项迁移 | `@MainActor` suite | 独立 40-item fixture | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testNumberOfItemsInSection_outOfBounds_returnsZero` | `LaunchPadTests.FolderOverlayViewTests/numberOfItemsInSection_outOfBounds_returnsZero()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 stale section | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testItemForRepresentedObjectAt_outOfBounds_returnsEmptyItem` | `LaunchPadTests.FolderOverlayViewTests/itemForRepresentedObjectAt_outOfBounds_returnsEmptyItem()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 stale index path | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testDidSelectItemsAt_callsOnAppSelected` | `LaunchPadTests.FolderOverlayViewTests/didSelectItemsAt_callsOnAppSelected()` | 2 个原断言逐项迁移 | `@MainActor` suite | 独立 callback | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testDidSelectItemsAt_emptySet_doesNotCallCallback` | `LaunchPadTests.FolderOverlayViewTests/didSelectItemsAt_emptySet_doesNotCallCallback()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 empty selection | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testDidSelectItemsAt_outOfBounds_doesNotCallCallback` | `LaunchPadTests.FolderOverlayViewTests/didSelectItemsAt_outOfBounds_doesNotCallCallback()` | 1 个原断言逐项迁移 | `@MainActor` suite | 独立 stale selection | 无共享状态 |
| `LaunchPadTests.FolderOverlayViewTests/testNavigateToPage_updatesScrollPosition` | `LaunchPadTests.FolderOverlayViewTests/navigateToPage_updatesScrollPosition()` | 5 个原断言/unwrap 逐项迁移 | `@MainActor` suite | `#require` page/scroll views | 无固定等待 |
| `LaunchPadTests.FolderOverlayViewTests/testNavigateToPage_outOfBounds_isNoOp` | `LaunchPadTests.FolderOverlayViewTests/navigateToPage_outOfBounds_isNoOp()` | 1 个原断言保留并显式 require fixture | `@MainActor` suite | `#require` page/scroll views | 无固定等待 |
| `LaunchPadTests.FolderOverlayViewTests/testUpdatePageFromScrollPosition_updatesCurrentPage` | `LaunchPadTests.FolderOverlayViewTests/updatePageFromScrollPosition_updatesCurrentPage()` | 3 个原断言/unwrap 逐项迁移 | `@MainActor` suite | 本地 `.main` notification | 删除 RunLoop polling |
| `LaunchPadTests.FolderOverlayViewTests/testMouseDown_insidePanel_doesNotClose` | `LaunchPadTests.FolderOverlayViewTests/mouseDown_insidePanel_doesNotClose()` | 原可见断言保留并证明实际 inside 点 | `@MainActor` suite | layout 后 panel 中点 | 同步 completion；无 wait |
| `LaunchPadTests.FolderOverlayViewTests/testNavigateToPage_zeroPageWidth_returnsEarly` | `LaunchPadTests.FolderOverlayViewTests/navigateToPage_zeroPageWidth_returnsEarly()` | 1 个原断言保留并显式 require fixture | `@MainActor` suite | 零宽 scroll fixture | 无固定等待 |
| `LaunchPadTests.FolderOverlayViewTests/testUpdatePageFromScrollPosition_zeroPageWidth_returnsEarly` | `LaunchPadTests.FolderOverlayViewTests/updatePageFromScrollPosition_zeroPageWidth_returnsEarly()` | 2 个原断言/unwrap 逐项迁移 | `@MainActor` suite | 零宽 `.main` notification | 删除 RunLoop polling |
| `LaunchPadTests.FolderOverlayViewTests/testOpenFolder_responsiveSize_withWidthZeroFallback` | `LaunchPadTests.FolderOverlayViewTests/openFolder_responsiveSize_withWidthZeroFallback()` | 1 个原断言逐项迁移 | `@MainActor` suite | 无 superview fixture | 无共享状态 |
