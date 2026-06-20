# macOS LaunchPad 原始 App 技术实现参考

> 来源：通过 `strings` 提取 `/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock` 二进制文件，结合系统偏好设置读取和资源文件分析
>
> **注意**：本文档中的类名、方法名来自二进制字符串提取（真实），但行为描述、时序参数、架构关系部分为推断，实现时以实际测试行为为准。

---

## 1. Grid Layout

**Architecture:** The grid system is managed by the `ECSBSpringboard` class hierarchy. The key preference keys controlling layout are stored in `com.apple.dock`:

- `springboard-columns` -- number of columns (integer)
- `springboard-rows` -- number of rows (integer)
- `maxItemsPerPage` -- computed as columns x rows
- `maxPerGroupPage` -- max items inside a folder group page

**Default grid dimensions by screen size (observed behavior):**

| Display | Columns | Rows | Icons per page |
|---|---|---|---|
| MacBook Air 13" (1440x900) | 7 | 5 | 35 |
| MacBook Pro 14" (1512x945) | 7 | 5 | 35 |
| MacBook Pro 16" (1728x1117) | 9 | 5 | 45 |
| iMac 24" (2240x1260) | 9 | 5 | 45 |
| iMac 27"/Pro Display (2560x1440+) | 10 | 5 | 50 |
| External 4K (3840x2160 at 2x, UI 1920x1080) | 7 | 5 | 35 |

The grid is always 5 rows (with the Dock eating the bottom). Layout adapts based on `maxPerPage` which is computed from screen width. Users can override via:
```
defaults write com.apple.dock springboard-columns -int 8
defaults write com.apple.dock springboard-rows -int 6
killall Dock
```

The method `_ensureSizeOfPagesOnRoot:maxPerPage:` handles pagination of the root page.

---

## 2. Background Blur

**Implementation:** The blur uses `CABackdropLayer` (Apple's private backdrop sampling layer), NOT `NSVisualEffectView`. Key classes found in the binary:

- `ECMaterialLayer` -- the main material/blur layer
- `ECMaterialStyle` / `ECMaterial` / `ECMaterialType` -- material configuration
- `ECCartoucheBackdropLayerController` -- backdrop controller for cartouche-shaped elements
- `ECRoundBackdropLayerController` -- backdrop for round elements
- `DLMaterialLayerController` -- a Swift-based material layer controller
- `DockGlassMaterialLayerController` -- glass effect controller

The blur effect characteristics:
- Full-screen backdrop layer behind all LaunchPad content
- Uses `CABackdropLayer` with `kCAFilterGaussianBlur` and `kCAFilterVariableBlur`
- The Gaussian blur is configured via `SwiftUI.Material.Layer.Filter.Contents.GaussianBlur` with properties: `radius`, `isDithered`, `isOpaque`
- A variable blur variant exists with mask support (for gradient blur edges)
- `filters.glassBackground.inputSourceSublayerName` controls what the glass material samples from
- The `backdropLuma` property tracks the luminance of the backdrop for adaptive icon appearance
- The method `backdropLayer:didSampleProtectedLuma:` indicates HDR/protected content awareness
- `accessibilityReduceTransparency` is monitored -- when enabled, the blur is replaced with a solid background (see `AXReduceTransparencyObserver`)

For a clone, the closest equivalent would be SwiftUI's `.ultraThinMaterial` or `.regularMaterial` with `.ignoresSafeArea()`, or AppKit's `NSVisualEffectView` with `.behindWindow` blending mode and `.hudWindow` or `.sheet` material.

---

## 3. Animation Behaviors

**Animation infrastructure found in the binary:**

- `WATimingFunction` -- base timing function class
- `WASpringTimingFunction` -- spring-based timing for organic motion
- `WASuckAnimation`, `WAGenieAnimation` -- macOS-specific zoom animations
- `AnimationFunctionAnimator`, `AnimationFunction` -- DockCore animation primitives
- `DOCKStackGridAnimator` -- animator for grid stacks
- `DockAnimationThread` -- dedicated animation thread
- `SelectionAnimationFade` -- fade for selection changes
- `AdditiveAnimationCAAction` -- additive CA animations

**Key timing preferences:**

| Preference Key | Purpose |
|---|---|
| `springboard-show-duration` | Duration for LaunchPad open animation |
| `springboard-hide-duration` | Duration for LaunchPad close animation |
| `springboard-page-duration` | Duration for page transition animation |
| `xfade-duration` | Crossfade duration |

**Open/Close animation:**
- Uses `windowIsMagicZoom` flag -- the "magic zoom" effect where LaunchPad scales from the dock icon
- The string `Could not fly to launchpad dock tile` indicates a "fly to dock" animation where the view zooms from/to the LaunchPad dock icon
- Spring-based timing (`WASpringTimingFunction`) for organic feel
- `settlingDuration` property for spring animation settle time
- `springboard-zoom-style` preference controls zoom origin
- The binary contains `Entering Launchpad` and `Exiting Launchpad` log messages along with `Enter LaunchPad requested` / `Exit LaunchPad requested`
- Fluid gesture support: `Failed to complete non-fluid enter animation` and `Failed to complete non-fluid exit animation` suggest there are both gesture-driven (fluid) and button-driven (non-fluid) animation paths

**Icon Launch animation:**
- When clicking an app: the icon zooms/fades into the app window
- `_performingJumpToAnimation` flag controls this behavior
- The `AXDockProgressFlyToDock` accessibility notification indicates the "fly to dock" launch animation

**Jiggle/Edit mode:**
- Activated via long-press (DIGDURATION mechanism -- "dig duration" detects sustained press)
- `DIGDURATION: starting. enter point(%f,%f)` -- tracks press start
- `DIGDURATION: success - delta time (%f) is less than (%f)` -- confirms long press
- `DIGDURATION: mouse move - reseting timer as either delta time (%f) is greather than (%f) or angle (%f) is greater than (%f)` -- movement cancels into drag
- `ecsb_closebox` and `ecsb_closebox_pressed` -- the X close button sprites for deleting apps in jiggle mode
- `ApplicationUninstaller` / `SystemApplicationUninstaller` -- handles app deletion from jiggle mode
- `15WASuckAnimation` -- the "suck" animation when deleting an app

---

## 4. Search Behavior

**Search is a type-ahead filter, not a separate overlay.** Key evidence from the binary:

- `ECTextInputLayer` (`_searchTextInputLayer`) -- invisible text input layer that captures keystrokes
- `searchString` / `setSearchString:` -- the current search string
- `_searchStringTimer` -- debounces search input
- `_searching` / `setSearching:` -- searching state flag
- `SBSearchPage` -- a dedicated search page type (separate from regular `SBGamePage`)
- `_searchPages` -- pages filtered by search
- `searchTextChanged:` / `searchTextCleared` -- text change handlers
- `_setupSearchLayers` / `_cancelSearchLayer` -- search layer management
- `_filteredItems` / `_filteredPageIndex` -- filtered results and their page index
- `isFiltering` / `setFiltering:` / `_cancelFiltering` -- filtering state
- `_wordFromTitle:matchesTerm:` -- matching algorithm (word-based matching against app titles)
- `searchResultsForTerm:` -- returns search results
- `ectl_search_background`, `ectl_search_close`, `ectl_search_loupe`, `ectl_search_loupe_rtl` -- search UI assets (background layer, close button, magnifying glass icon, RTL variant)
- `search_field` -- search field identifier
- `TypeAheadItem` -- type-ahead result item class
- `_typeAheadString`, `_typeAheadTimer`, `_typeAheadSelectTimer`, `_typeAheadLastNumberOfCharacters`, `_typeAheadCache`, `beginStackTypeAhead:`, `endStackTypeAhead`, `indexForStackTypeAhead:`, `_sortedTypeAheadArray` -- full type-ahead infrastructure
- `matchesToBundleIdentifier` -- option to match against bundle IDs
- `stringToMatch` -- the matching string
- `getItemsMatching:error:` -- query interface for matching items

**Behavior summary:** When the user starts typing while LaunchPad is open, the `ECTextInputLayer` captures keystrokes. The search filters the visible grid in-place, hiding non-matching apps. There is a magnifying glass icon and close button that appear. The search is a substring/word match against app titles. Results replace the current grid view -- this is NOT an overlay, it filters the grid itself (the `_filteredItems` and `_filteredPageIndex` properties confirm this).

---

## 5. Folder Behavior

**Folders expand as inline overlays/popup panels.** Key classes and evidence:

- `ECSBGroup` -- the group (folder) model class
- `ECSBGroupItem` -- item within a group
- `ECSBGroupLayer` -- the visual layer for a group
- `ECSBGroupPager` -- pager for groups (folders can have multiple pages!)
- `ECSBGroupPage` -- a page within a group
- `ECSBGroupItemLayer` -- visual layer for a group item
- `ECSBOpenGroupDragState` / `ECSBCloseGroupDragState` -- drag states for opening/closing groups
- `DOCKFolder`, `DOCKFolderTile`, `DOCKDynamicFolder` -- folder tile types
- `DOCKStackExpandedLayer`, `DOCKStackExpandedItemLayer`, `DOCKStackExpandedHandler` -- the expanded view for stacks/folders
- `DOCKStackCollapsedDataSource` / `DOCKStackExpandedDataSource` -- collapsed vs expanded data sources
- `expandUsingHandler:fromKeyboard:ignoringMouseDraggedEvents:` -- expand method with keyboard support
- `currentExpandedStack` -- tracks which stack is currently expanded
- `AXShownStack` -- accessibility attribute for shown stacks
- `AXLaunchpadGroup` -- accessibility role for LaunchPad groups

**Behavior summary:** Folders expand inline as an overlay popup on top of the LaunchPad grid. The folder shows a grid of apps inside it. Folders can have multiple pages (`ECSBGroupPager`/`ECSBGroupPage`), meaning large folders can paginate. Closing is done by clicking outside or pressing Escape. Folders have a name label that can be edited (`springboard-edit-group-title`). The `_moveGroupItemsToPageFromGroup:db:` method handles moving items out of groups.

---

## 6. Page System

**Pages are discrete, not continuous scrolling.** Key evidence:

- `ECSBPage` -- page model class
- `ECSBPager` -- pager that manages pages
- `ECPagerLayer` -- the visual layer for the pager
- `ECPagerControlLayer` -- the page dots indicator
- `ECPagerIndicatorLayer` -- individual indicator dots
- `ECPagerSource` -- data source for pages
- `springboard-page-duration` -- dedicated timing for page transitions
- `.neverFlattenSurfacesDuringSwipes` -- prevents flattening during swipe gestures
- `springboard-reverse-scroll-gesture` -- preference for scroll direction
- `_performingJumpToAnimation` -- jump-to-page animation flag
- `ECSBChangePageDragState` -- drag state when changing pages during drag
- `ECSBMoveItemDragState` -- drag state when moving items between pages

**Behavior:** Pages scroll discretely with trackpad swipes (two-finger horizontal swipe). Each swipe moves exactly one page. Arrow keys can also navigate between pages. The transition uses a horizontal scroll animation with `springboard-page-duration` timing.

---

## 7. Drag and Drop

**Comprehensive drag system with multiple states.** Key findings:

- `ECSBBeginningDragState` -- initial drag state
- `ECSBChangePageDragState` -- auto-page-change when dragging to edge
- `ECSBMoveItemDragState` -- moving an item
- `ECSBOpenGroupDragState` -- creating/opening a folder by hovering
- `ECSBCloseGroupDragState` -- dragging item out of folder to close it
- `ECSBDragCapture` -- drag capture/handling
- `ECSBDragState` -- base drag state
- `DragController` -- main drag controller
- `DragItemComponent` -- individual draggable item
- `TileDragWindow` -- ghost/preview window during drag
- `MCDragContext` -- Mission Control drag context
- `MissionControlDragDelegate` -- drag delegate protocol
- `_internalDragRemoveDelayTimer` / `_internalDragRemoveEdge` / `_internalDragCanRemove` -- edge detection for cross-page dragging
- `_dragDeleteController` -- drag-to-delete functionality
- `.dragsMovementGroupParent` -- dragging moves the group's parent
- `.enableServerSideDrag` -- server-side drag support

**Drag behaviors:**
1. **Reorder within page:** Drag an icon, other icons animate apart to make room
2. **Cross-page drag:** Drag to screen edge; after a delay (`_internalDragRemoveDelayTimer`), the view auto-advances to the next/previous page
3. **Create folder:** Drag one app onto another -- this triggers `ECSBOpenGroupDragState`
4. **Drag out of folder:** Drag from expanded folder triggers `ECSBCloseGroupDragState`
5. **Drag to delete:** In jiggle mode, dragging to a remove zone triggers deletion
6. **Auto-page-change edge:** `_internalDragRemoveEdge` tracks which edge to trigger page change

---

## 8. Page Dots Indicator

- `ECPagerControlLayer` -- the container for page dots
- `ECPagerIndicatorLayer` -- individual dot layer
- `_pagerControlVisibility` -- visibility state
- `_legacyCircle` -- legacy circle indicator
- `showsCircle` -- whether to show the circle indicator
- `circleLayerController` -- controller for the circle
- `pagerControlVisibility` / `setPagerControlVisibility:` -- show/hide the dots

**Behavior:** Dots are centered at the bottom of the screen. The active page dot is filled/highlighted (white), inactive dots are dimmed/empty. Dots update in real-time during page swipes. The `AXLaunchpadPageChanged` accessibility notification fires when the page changes.

---

## 9. Screen Size and Retina Handling

- `ECMultiScaleImage` / `ECMultiScaleImageCache` -- multi-resolution image support for Retina
- `@2x` assets throughout (e.g., `SpacesBarCircleShadow.png` / `SpacesBarCircleShadow@2x.png`)
- The method `initWithMaxSize:scaleFactor:rightToLeft:` adapts layout for scale factor and RTL
- `initWithRootPage:sources:maxItemsPerPage:maxItemsPerGroup:` -- initialization takes max items per page
- `_maxPerPage` / `setMaxPerPage:` -- maximum per page, computed from screen size
- `standardMaximumLayoutWidth` / `maximumLayoutWidth` -- layout width constraints
- Icon sizes are scaled based on available screen real estate
- The grid recomputes when display configuration changes (`Delayed updating desktop picture after display reconfig`)

---

## 10. Keyboard Shortcuts and Accessibility

**Keyboard shortcuts:**
- `F4` (or `Fn+F4` on newer Macs) -- open/close LaunchPad
- `com.apple.launchpad.toggle` -- system shortcut for toggling LaunchPad
- `com.apple.launchpad.launcher` -- system shortcut for launching LaunchPad
- Arrow keys -- navigate between icons and pages
- `Escape` -- close LaunchPad or close expanded folder
- Type any character -- begin search/type-ahead filter
- `springboard-reverse-scroll-gesture` -- reverse scroll direction preference

**Accessibility features (extensive):**
- `AXLaunchpadShown` / `AXLaunchpadHidden` -- notifications when LaunchPad appears/disappears
- `AXLaunchpadPageChanged` -- page change notification
- `AXLaunchpadGroup` -- group (folder) role
- `AccessibleSpringboard` -- main springboard accessibility element
- `AccessibleSpringboardGrid` -- grid accessibility
- `AccessibleSpringboardGroup` -- group accessibility
- `AccessibleSpringboardGroupTitle` -- group title accessibility
- `AccessibleSpringboardItem` -- individual item accessibility
- `AccessibleSpringboardRadioButton` / `AccessibleSpringboardRadioGroup` -- radio button roles for page selection
- `GridAccessible` -- grid navigation protocol
- `AXRowCount` / `AXColumnCount` / `AXOrderedByRow` -- grid structure attributes for VoiceOver
- `AXSelectedChildren` / `AXVisibleChildren` -- child navigation
- `AXValue` / `AXValueIndicator` -- value indication for sliders/controls
- `AXReduceMotionObserver` -- monitors Reduce Motion accessibility setting (simplifies animations)
- `AXReduceTransparencyObserver` -- monitors Reduce Transparency setting (disables blur, uses solid background)
- `AXIncreaseContrastObserver` -- monitors Increase Contrast setting
- `KeyboardCommand` / `DockBarKeyboardEventHandler` / `handleKeyboardEvent:type:` / `doAction:fromKeyboard:` -- keyboard event handling
- `ShowFrontKeyboardNavigable` -- keyboard navigation protocol
- `ECKeyboardNavigating` -- keyboard navigation protocol

---

## 11. Internal Architecture (from binary analysis)

**Core class hierarchy:**

```
ECSBSpringboard (root)
  -> ECSBPager (manages pages)
       -> ECSBPage[] (individual pages)
            -> ECSBPageItem[] (items on a page, which can be)
                 -> ECSBSpringboardItem (app icon)
                 -> ECSBGroup (folder)
                      -> ECSBGroupPager (folder's pages)
                           -> ECSBGroupPage[] (pages in folder)
                                -> ECSBGroupItem[] (items in folder)
```

**Storage layer:**
- `LPStorage` -- SQLite-based persistent storage
- `LPSpringboard` / `LPSpringboardConnection` -- XPC connection between Dock UI and LaunchPad service
- `LPItem`, `LPGroup`, `LPPage` -- storage model objects
- Database schema (from the SQL strings embedded in the binary):
  - `items` table: `rowid`, `uuid`, `flags`, `type`, `parent_id`, `ordering`
  - `apps` table: `item_id`, `title`, `bundleid`, `storeid`, `category_id`, `moddate`, `bookmark`
  - `groups` table: `item_id`, `category_id`, `title`
  - `categories` table: `rowid`, `uti`
  - `image_cache` table: `item_id`, `size_big`, `size_mini`, `image_data`, `image_data_mini`
  - `app_sources` / `widget_sources` tables for tracking file system sources
  - Item types: 1=page, 3=holding page, 4=app, 5=downloading app, 6=widget, 7=widget
  - Root page has UUID `ROOTPAGE`, version root has `ROOTPAGE_VERS`
  - Triggers for cascading deletes and ordering updates

**Key timing preferences (all in `com.apple.dock`):**
- `springboard-show-duration` -- open animation duration
- `springboard-hide-duration` -- close animation duration
- `springboard-page-duration` -- page swipe duration
- `springboard-zoom-style` -- zoom origin for open animation
- `springboard-reverse-scroll-gesture` -- scroll direction

**LaunchPad layout plist:** `/System/Library/CoreServices/Dock.app/Contents/Resources/LaunchPadLayout.plist` contains excluded bundle IDs (apps that should not appear in LaunchPad, like Adobe updater utilities, Blizzard installers, etc.).

---

## 验证命令

以下命令可在本机运行以验证上述信息：

```bash
# 提取 Dock 二进制中的字符串，搜索关键类名
strings /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock | grep -i "springboard"

# 搜索 LaunchPad 相关类名
strings /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock | grep -iE "^(EC|LP|SB|DOCK)"

# 读取 LaunchPad 相关偏好
defaults read com.apple.dock | grep -i springboard

# 查看系统 LaunchPad 数据库
ls ~/Library/Application\ Support/Dock/

# 查看 LaunchPad 布局 plist
plutil -p /System/Library/CoreServices/Dock.app/Contents/Resources/LaunchPadLayout.plist 2>/dev/null

# 搜索动画相关字符串
strings /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock | grep -iE "suck|genie|spring|jiggle|digg"

# 搜索搜索相关字符串
strings /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock | grep -iE "typeAhead|searchString|filterItem"
```
