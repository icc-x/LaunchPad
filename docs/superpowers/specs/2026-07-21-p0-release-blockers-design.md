# LaunchPad P0 发布阻断项修复设计

> 日期：2026-07-21
>
> 状态：设计分段已确认，自审完成，等待用户书面复核
>
> 分支：`release-readiness`

## 1. 目标

修复发布审查确认的 6 个 P0 阻断项，并把扩大后的拖放、动态网格和真实性能门禁按上线标准闭环：

1. 主网格多行不得重叠，并能适配实际 viewport 高度；
2. 键盘搜索不得丢失首字符或后续字符；
3. ESC、方向键、Enter 和字符输入必须经过真实 local monitor 入口；
4. 同页、跨页、空白追加、已有文件夹、拖拽建文件夹、文件夹内重排与拖出必须原子持久化；
5. 首次扫描完成后已加载的 UI 必须刷新；
6. 测试门禁必须可重复退出、无用户系统副作用，且墙钟性能断言始终执行。

本设计不以“测试变绿”为唯一目标。所有成功状态必须对应已提交的数据，所有失败状态必须可回滚、可观察并有自动化证据。

## 2. 已确认产品规则

### 2.1 键盘

- 窗口可见且事件被业务实际处理时返回 `nil`，阻止 AppKit 重复输入；
- `flagsChanged`、未知空字符键、窗口隐藏或 ViewController 不存在时放行原事件；
- idle 状态收到首字符时，在一个入口内完成模式切换、首字符写入、焦点设置和搜索调度；
- ESC 在搜索、编辑和普通模式下分别执行清空搜索、退出编辑和关闭窗口。

### 2.2 拖放

- 禁止文件夹嵌套；文件夹可以同页重排、跨页移动和追加到页面空白处；
- 应用拖到应用上时，悬停 0.8 秒只显示建文件夹预览，松手才提交；
- 应用拖到已有文件夹时追加到文件夹末尾；
- 跨页目标已满时级联后移，末页溢出时自动创建新页；
- 页面变空时自动删除并连续重排，但数据库始终至少保留一页；
- 搜索状态禁用全部拖放；
- 页面是当前 viewport 对稳定全局顺序的展示切片，不是用户可感知的固定容器；
- 文件夹内应用可以重排和拖出；剩余一个子应用时自动解散文件夹；
- 删除文件夹前确认，子应用回到文件夹原全局位置，再删除文件夹；
- 事务失败时项目回弹，显示非阻塞提示“无法更新布局，请重试”，并记录不暴露数据库细节的系统日志；
- 不自动重试拖放写入，避免重复执行含歧义的用户操作。

### 2.3 网格

- 保持图标最小 64pt、最大 96pt；
- 从 5 行开始适配高度，64pt 仍无法容纳时依次降为 4、3、2、1 行；
- 列数继续按宽度选择 7、9、10 列；
- 页面容量为当前 `columns * rows`，切换显示器时只重新投影展示，不写数据库；
- 最后一页从固定网格的左上位置开始填充，切页时项目不发生垂直跳动；
- 不引入纵向滚动，不裁切最后一行。

### 2.4 性能

- 墙钟断言始终启用，不使用环境变量、测试 trait 或发布脚本跳过；
- 保留现有 50ms、1ms、10ms、1ms 和 300ms 上限；
- 通过单调时钟、预热、确定性输入、多轮统计和非并行发布环境消除测量污染；
- 若仍超限，先复现和采样，再优化真实路径或夹具额外开销，不放宽阈值掩盖问题。

## 3. 当前代码证据

### 3.1 网格

- `Sources/LaunchPad/Views/AppGridFlowLayout.swift:55-65` 把全部 layout attribute 的 y 改为同一个值，直接导致多行重叠；
- `Tests/LaunchPadTests/Views/ViewLayerTests.swift:696-731` 反向断言所有 attribute 使用同一 y，固化错误行为；
- `Sources/LaunchPad/Utilities/GridLayoutCalculator.swift:29-54` 只接收宽度，无法使用真实 scroll viewport 高度；
- 同文件固定 5 行、100/60pt 上下边距；`LaunchPadViewController.swift:143-160` 已通过约束为搜索栏和页码扣除约 102pt，形成重复预留；
- `AppGridFlowLayout.swift:15-20` 把 spacing 同时加入 item 宽度和 inter-item spacing；
- `AppGridFlowLayout.swift:41-47` 使用 collection view 宽度除以自身推算页数，非零时趋近于 1。

### 3.2 键盘

- `KeyboardNavigator.swift:70` idle 收到字符时只返回 action，没有建立真实 search 状态；
- `LaunchPadViewController.swift:572-579` 进入搜索只显示搜索框，首字符没有写入；
- `HotkeyManager.swift:168-174` 对 ESC、方向键和 Enter 直接放行，生产 callback 不可达；
- 现有测试分别固化“连续字符一直 enterSearchMode”和“特殊键不进入 callback”的错误行为。

### 3.3 拖放与事务

- `AppGridCollectionView.swift:359-378` 只修改 diffable snapshot 或调用 `handleDrop()`，不写业务数据；
- `DragController.swift:65` 的 `beginEditing` 没有生产调用，`currentOrder` 无法反映真实 UI 拖放；
- `DragController.swift:193-203` 的跨页状态使用 `itemId: 0`、`toPage: 0` 占位，且左右边缘都只回调 forward；
- `LaunchPadViewController.swift:509-525` 从 `currentOrder` 猜测拖拽项目，不携带真实 source item；
- `FolderController.swift:16-91` 的创建、移出、解散由多个独立 CRUD 调用组成，中途失败会留下部分状态；
- `ItemWriting` 只有 insert/update/delete/reorder，无法表达多容器原子事务；
- `StorageManager.swift:82-83,153-154,257-258` 在检查 COMMIT 前设置成功状态，并忽略 COMMIT 结果；
- `FolderOverlayView` 没有 pasteboard、validateDrop 或 acceptDrop 入口；
- Schema 允许任意 item 自引用，当前 UI 和自动解散逻辑却不支持嵌套文件夹。

### 3.4 首次扫描

- AppDelegate 先创建窗口控制器并触发 `viewDidLoad/loadData`，再执行首次扫描；
- 空库首次加载后，扫描成功路径没有再次调用 ViewController 的数据刷新入口；
- 现有首次扫描测试使用无业务含义的恒真断言，不能证明 UI 数据流。

### 3.5 测试与性能

- 全量测试曾以 exit 1、signal 5 或超时结束；
- AppKit monitor、status item、FSEvent、登录项、Dock plist 和系统设置缺少完整注入或释放边界；
- `PerformanceTests.swift` 使用 `Date` 单次计时和随机访问，容易把调度与随机数开销混入目标路径；
- 2026-07-16 隔离执行 6 项性能测试退出 0，但此前并行运行出现 IconCache 300ms 阈值失败，证明门禁环境和测量方法需要同时修正。

## 4. 总体架构

保持现有 AppKit、Controller、Protocol、SQLite 分层，不引入第三方依赖。新增边界只用于消除已确认的业务耦合。

### 4.1 `LayoutDropIntent`

领域命令表达用户已确认的落点，不携带整份 UI snapshot：

```swift
public enum LayoutDropIntent: Sendable, Equatable {
    case insert(itemID: Int64, beforeItemID: Int64)
    case appendToPage(itemID: Int64, visualPageIndex: Int)
    case addToFolder(itemID: Int64, folderID: Int64)
    case createFolder(itemID: Int64, targetItemID: Int64, title: String)
    case reorderFolderItem(itemID: Int64, folderID: Int64, beforeItemID: Int64?)
    case removeFromFolder(itemID: Int64, folderID: Int64, destination: TopLevelDestination)
    case deleteFolder(folderID: Int64)
}

public enum TopLevelDestination: Sendable, Equatable {
    case beforeItem(itemID: Int64)
    case endOfVisualPage(pageIndex: Int)
}
```

item after 落点转换为“下一个项目之前”；不存在下一个项目时转换为当前视觉页末尾。所有 ID 都由不可变 `DragSession` 提供，不从当前数组位置猜测。

### 4.2 `LayoutMutating`

```swift
public protocol LayoutMutating: Sendable {
    func apply(_ intent: LayoutDropIntent, pageCapacity: Int) throws
}
```

该接口由 `StorageManager` 实现。Controller 不获得数据库句柄、事务闭包或通用 repository 写权限。

### 4.3 `LayoutProjection`

纯函数输入数据库读取出的页面顺序、页面子项和当前 `GridMetrics`，输出视觉 sections：

1. 按 page ordering 及 item ordering 展平顶层项目；
2. 按当前 `pageCapacity` 分块；
3. 空布局仍产生一个空视觉页；
4. 文件夹 children 单独按文件夹 viewport capacity 分块；
5. 不修改数据库或领域项目的稳定顺序。

### 4.4 UI 责任

- `DragController`：拖拽会话、hover 子状态、左右边缘 timer、建文件夹预览；
- `AppGridCollectionView`：AppKit pasteboard 和落点解析，不直接 apply 成功 snapshot；
- `FolderOverlayView`：文件夹内拖放入口和弹窗边界解析；
- `LaunchPadViewController`：搜索态拒绝、调用 `LayoutMutating`、成功 reload、失败回弹与提示；
- `TransientMessageView`：单一、可访问、非阻塞错误提示，不承载数据库细节。

## 5. 原子事务设计

每个 `LayoutDropIntent` 都执行相同事务骨架：

1. 在 storage write queue 内执行 `BEGIN IMMEDIATE` 并检查返回码；
2. 从数据库读取当前页面、顶层项目、目标文件夹 children；
3. 验证 source/target 存在、类型合法、source != target、搜索态未越过 Controller 边界；
4. 在内存领域模型中应用一次 mutation；
5. 校验不变量；
6. 复用、创建或删除 page rows，并批量写入连续 parent/order；
7. 检查每次 prepare、bind、step 及 affected-row 结果；
8. 执行 COMMIT，只有 COMMIT 返回 `SQLITE_OK` 后才报告成功；
9. 任意失败执行 ROLLBACK，并保留原始错误作为上层日志证据。

事务不变量：

- 每个顶层 app/group 在全局顺序中恰好出现一次；
- 页面 ordering 从 0 连续，除唯一空页面外不存在空页面；
- 每个持久化页面不超过本次 mutation 使用的 `pageCapacity`；
- 文件夹只能包含 app，不能包含 page/group，也不能形成环；
- 文件夹 children ordering 从 0 连续；
- 新文件夹占据 target app 原全局位置；
- 安全删除或自动解散后，children 占据原文件夹位置并保持内部顺序；
- 任何错误不得留下部分 parent/order/group 变更。

不向 Controller 暴露 `withTransaction`。当前 `writeQueue.sync` 结构下通用事务闭包容易产生重入死锁，也会把领域不变量分散到 UI 层。

## 6. 拖放状态与交互

### 6.1 会话

`DragSession` 至少包含：

- `itemID`；
- source kind：顶层或 folder child；
- `sourceParentID`；
- 会话开始时的 source visual index；
- 当前 hover destination；
- folder-creation preview 状态。

drag start 建立会话；drop、cancel、ESC、窗口隐藏和 drag session end 都必须清理 timer、预览和强引用。

### 6.2 顶层分支

- item before/after：映射为全局插入位置；
- empty：映射为当前视觉页末尾；
- left/right edge：1.5 秒后分别翻上一页/下一页，边界不触发；
- app on app：0.8 秒后 preview，drop 时 create folder；
- app on group：drop 时 append child；
- group on app/group：拒绝合并；
- group before/after/empty：允许普通顶层移动；
- invalid UUID、stale source、stale target、self drop：拒绝且零写入；
- search active：drag source 和 drop destination 都禁用。

### 6.3 文件夹分支

- child before/after/empty：更新 folder child 全局顺序；
- child 拖出 overlay：转换为顶层目标位置；
- remaining count == 1：事务内自动解散；
- delete folder：确认后 children 回到原 folder 全局位置；
- folder 内不提供 group source 或 app-on-app 建子文件夹。

### 6.4 失败反馈

失败时 collection view 不提交乐观 diffable snapshot。Controller 重新加载数据库状态，拖拽预览回弹；`TransientMessageView` 显示“无法更新布局，请重试”，随后自动消失。系统日志记录 intent 类型、source/target ID 和稳定错误分类，不记录用户路径或数据库内容。

## 7. 动态网格与视觉分页

### 7.1 `GridMetrics`

`GridLayoutCalculator.calculate(viewportSize:)` 返回：

- `columns`、`rows`、`itemsPerPage`；
- `iconSize`、`itemSize`；
- `horizontalSpacing`、`verticalSpacing`；
- `sectionInsets`、`pageWidth`。

列数保留现有三分支。高度算法从 5 行向下寻找第一个可容纳最小 64pt 图标、40pt label/padding、固定纵向间距和最小上下 inset 的行数；选定行数后在 64...96pt 内使用宽高共同约束的最大图标尺寸。即使 viewport 极端缩小，也至少返回 1 行并保证所有数值有限且非负。

### 7.2 Flow layout

- item width 不再包含 inter-item spacing；
- 每个 section 的几何宽度严格等于 clip viewport 宽度；
- section 起点为 `pageIndex * pageWidth`；
- item 使用固定网格槽，保留系统计算出的相对 x/y；
- 最后一页从左上填充，不把局部内容块重新垂直居中；
- supplementary attributes 不参与 item 位移；
- snap 使用真实 section count 和 page width。

### 7.3 尺寸变化

`LaunchPadViewController.viewDidLayout` 在约束完成后读取 `scrollView.contentView.bounds.size`。metrics 变化时：

1. 重新应用 flow layout 参数；
2. 用 `LayoutProjection` 重新分段；
3. 应用新 snapshot；
4. 按 item ID 恢复选择；
5. current page 超界时夹紧；
6. 更新页码、键盘 columns/rows 和 accessibility rows。

显示器变化和窗口首次展示不得写数据库。

## 8. 键盘与首次扫描

### 8.1 键盘

`KeyboardNavigator` 的 mode 和 query 必须保持一致：idle 首字符直接转为 search 并返回携带首字符的 action；search 后续字符 append；Delete 更新 query；ESC 清空后回到 idle。

Hotkey local monitor 把所有候选 keyDown 交给 AppDelegate callback，由 callback 返回是否已处理。只有已处理事件被吞；flagsChanged 和无法映射的事件放行。

### 8.2 首次扫描

启动数据流固定为：

1. 加载已有布局并允许窗口展示；
2. 执行首次或增量扫描；
3. 扫描写入成功后在主线程通知已加载 ViewController reload；
4. ViewController 未加载时不强制创建 view，首次访问按数据库加载；
5. 首扫写入按当前目标显示器的 `GridMetrics.itemsPerPage` 规范化存储页，但后续显示器变化仍只重新投影视图；
6. 扫描读取或写入失败时保留已有布局并记录错误。

空库、已有库、读取失败、写入失败、VC 已加载和未加载均有有效断言。

## 9. 测试设计

### 9.1 TDD 顺序

每个独立行为严格执行：

1. 添加最小失败测试；
2. 实际运行并保存 RED 证据；
3. 编写最小生产实现；
4. 运行 focused suite 获得 GREEN；
5. 运行相邻回归；
6. 检查 diff 后提交单一主题。

### 9.2 事务测试

纯领域测试覆盖每种 intent 的：

- happy path；
- source/target 缺失；
- self drop；
- 类型非法和文件夹嵌套；
- 首/末页、满页级联和新页；
- 空源页删除和至少一页；
- folder 第 36 项及多视觉页；
- 自动解散和安全删除；
- ordering 连续、无重复、无丢失。

真实 `:memory:` SQLite 测试通过触发器或注入点在 BEGIN、prepare、bind、step、COMMIT 和 ROLLBACK 边界制造失败，并通过同一 storage 的新读取证明状态完全未变。需要证明关闭后重开仍持久化的集成测试使用 `/tmp` 独立数据库文件，避免错误假设不同 `:memory:` 连接共享数据。

### 9.3 UI 测试

- pasteboard source：app、group、page、未知 UUID；
- validateDrop：左右边缘、item、folder、empty、搜索态；
- acceptDrop：同页、跨页、空白、已有 folder、create folder、self、stale target；
- hover：同位置、切换位置、移开、超时、cancel；
- FolderOverlay：内部重排、拖出、自动解散、失败回弹；
- transient message：显示文本、重复错误替换、自动隐藏、无障碍 announcement；
- 不依赖真实窗口展示、真实系统事件或用户数据库。

### 9.4 网格测试

- 900/768/600pt 和每个换行临界值；
- 64/96pt clamp、有限数和非负数；
- item width 与 spacing 不重复；
- 2/3/5 行真实 attributes 不重叠；
- 2/3 sections 起点相差 page width；
- supplementary attribute 不被移动；
- 最后一页左上填充；
- resize 后 page/selection/keyboard/accessibility 一致。

### 9.5 性能测试

- 使用 `ContinuousClock`；
- setup、预热和结果正确性检查不计入目标算法区间；
- 随机索引预先生成并固定 seed；
- 采集多轮样本，断言中位数和高分位不超过现有阈值；
- 测试始终启用；
- 若失败，使用采样证据区分生产热点、AppKit 初始化和调度污染。

## 10. 发布门禁

唯一入口 `scripts/test-release.sh`：

1. 设置 workspace-local `/tmp` module cache；
2. 使用可信 timeout 包装每次命令；
3. 连续三次运行完整非并行测试，性能 suite 每次都执行；
4. 任意失败、signal、超时或非零退出立即终止；
5. 检查没有遗留测试进程；
6. 运行 release build 并保留完整 warning 输出。

测试不得修改真实 Dock plist、登录项、辅助功能设置、全局热键或用户应用数据库。系统边界通过协议或闭包注入，资源在 teardown/deinit 中显式释放。

## 11. 文档同步

实现完成后同步：

- README 的拖放能力、动态行数和真实测试命令；
- 原设计中“hover 立即创建文件夹”改为“hover 预览、drop 提交”；
- 页面从固定持久化容器调整为稳定顺序的视觉切片；
- 删除历史“0 warning/0 failure”声明，改为本次新鲜验证结果；
- 发布评审报告保留原始证据，不改写历史结论。

## 12. 范围边界

本设计覆盖 P0-1 至 P0-6，以及为完整拖放原子性所必需的事务提交检查、文件夹移出和安全删除。它不自动关闭发布评审中的其他 P1/P2 项，例如增量扫描全量读取、通用 SQLite bind 生命周期、Schema 原子初始化、签名、公证和 hardened runtime。

因此，本计划完成后只能证明 P0 门禁关闭；正式发布仍必须重新审查剩余 P1/P2 并取得独立发布结论。

## 13. 验收标准

- 所有确认的键盘、拖放、布局、扫描和测试分支均有 RED-GREEN 自动化证据；
- 任何拖放成功在重新加载数据库后仍成立；
- 任意注入失败不产生部分布局状态；
- 900/768/600pt 及临界高度无重叠、裁切或 incoherent overlap；
- 普通测试和发布脚本都不跳过墙钟性能断言；
- 完整发布门禁连续三次退出 0；
- 无 signal 5、超时、残留进程或用户系统状态修改；
- README、设计文档和实际生产行为一致；
- P0 完成状态不被错误表述为全项目已满足正式发布条件。
