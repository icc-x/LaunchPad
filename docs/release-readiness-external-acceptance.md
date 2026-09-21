# 发布就绪外部验收清单

> 创建：2026-08-11
> 配套：`docs/release-readiness-todo.md`（外部验收事项状态来源）
> 原则：以下验收不得用 dry-run、mock 或静态检查替代；每一项必须在对应真实环境执行并产生新鲜证据后，才可回写 todo.md 结论。

## 环境要求

| 验收项 | 所需环境 | 前置条件 |
|---|---|---|
| 1. 发布门禁 ×2 | 完整 macOS（可执行 `/bin/ps`） | 无 |
| 2. 签名/公证链 | 装有 Developer ID 证书与 Keychain profile 的 macOS | 三项环境变量 |
| 3. 干净 Gatekeeper | 独立/干净的 macOS 虚拟机或新用户 | 已签名公证的 `.build/LaunchPad.app` |
| 4. GitHub Actions | GitHub 仓库（可推送） | 已推送 `release-readiness` 分支 |
| 5. VoiceOver | 装有 VoiceOver 的 macOS + 辅助功能授权 | 应用可正常启动 |

---

## 验收 1：发布门禁连续两次运行

**目标**：证明 `scripts/test-release.sh` 可重复、确定地通过，发现集与执行集一致，无残留进程。

**命令**（在仓库根目录，确保工作树干净 `git status --short` 无输出）：

```bash
./scripts/test-release.sh   # 第一次
./scripts/test-release.sh   # 第二次
```

**记录**：
- 两次退出码均为 0
- 每轮摘要中的测试数与套件数（当前本地基线：1126 tests / 65 suites；以实际输出为准）
- 三轮发现集与执行集完全一致，无跳过/超时/残留进程/失败标记
- 记录 artifact 目录路径（`.superpowers/sdd/release-gate.*`）与 `result.status=passed`

**通过标准**：两次运行均 `result.status=passed`；`command.provenance-start.status=0` 且首尾受控文件摘要一致。

**失败处理**：记录失败命令、退出码与 manifest 中 status=1 的条目，先修复再重跑；不得以单次通过替代连续两次。

---

## 验收 2：Developer ID 签名、公证与 stapling

**目标**：证明 `scripts/release-app.sh` 在真实凭据下完成签名与公证链。

**前置条件**：
- 钥匙串中存在 Developer ID Application 证书与 notarytool Keychain Profile（`xcrun notarytool history --keychain-profile <名称>` 可查询）
- 仓库工作树干净

**步骤**：

```bash
# 1) 预热：确认将要执行的命令（不签名、不联网）
LAUNCHPAD_CODESIGN_IDENTITY='Developer ID Application: <你的身份>' \
LAUNCHPAD_TEAM_ID='<TEAMID(10位字母数字)>' \
LAUNCHPAD_NOTARY_PROFILE='<profile 名称>' \
  ./scripts/release-app.sh --dry-run

# 2) 真实执行（耗时取决于公证队列；--wait 会阻塞到结果返回）
LAUNCHPAD_CODESIGN_IDENTITY='Developer ID Application: <你的身份>' \
LAUNCHPAD_TEAM_ID='<TEAMID>' \
LAUNCHPAD_NOTARY_PROFILE='<profile 名称>' \
  ./scripts/release-app.sh
```

**产物**：`.build/LaunchPad.app`、`.build/LaunchPad.zip`、`.build/release-manifest.txt`（含 team_id 与时间戳）。

**验证命令与预期**：

```bash
codesign --verify --deep --strict --verbose=2 .build/LaunchPad.app
# 预期：".build/LaunchPad.app: valid on disk" / "satisfies its Designated Requirement"

codesign -d --entitlements - .build/LaunchPad.app 2>&1 | plutil -p -
# 预期：包含 Resources/LaunchPad.entitlements 中的键（如 hardened runtime 相关）

xcrun notarytool history --keychain-profile '<profile 名称>' --last 1
# 预期：最近一条记录状态为 Accepted（可在提交日志中确认 id）

xcrun stapler validate .build/LaunchPad.app
# 预期："The validate action worked!"

spctl --assess --type execute --verbose=4 .build/LaunchPad.app
# 预期：accepted, source=Notarized Developer ID
```

**通过标准**：上述 5 条验证命令全部给出预期输出。

**失败处理**：notarytool 返回 invalid/Rejected 时，读取 `notarytool log <submission-id> --keychain-profile <profile>` 定位原因（多为签名身份/Team ID 不匹配或 entitlements 问题），修复后重新执行。

---

## 验收 3：干净 macOS 环境的 Gatekeeper 启动

**目标**：证明最终用户下载分发时不会被 Gatekeeper 拦截（无 quarantine 属性时由 stapling 通过）。

**环境**：无本机签名开发者信息、无 LaunchPad 历史数据的干净 macOS（虚拟机或新用户）。

**步骤**：
1. 将验收 2 的 `.build/LaunchPad.app` 拷贝到干净环境
2. 直接双击打开（不手动右键"打开"绕过）
3. 确认：应用正常启动，无"已损坏，无法打开"或"无法验证开发者"弹窗
4. 附带确认 Option+Space 快捷键需在 **系统设置 → 隐私与安全性 → 辅助功能** 授权后生效

**通过标准**：首次双击即可正常启动，系统不提示无法验证开发者。

**补充（可选）**：如需模拟最严格场景，在干净环境执行 `xattr -dr com.apple.quarantine .build/LaunchPad.app` 后通过 `spctl --assess --type execute --verbose=4` 复验。

---

## 验收 4：GitHub 托管 runner 结果（标准与 xlarge 双 runner）

**目标**：证明 CI 在 `macos-26` 与 `macos-26-xlarge` 两个矩阵 runner 上全绿，且性能工作流在固定 runner 无偶发失败。

> 2026-09-21 修订：GitHub 已弃用 macos-14 镜像（其最新工具链仅 Xcode 16.2 / Swift 6.0，与本仓库要求的 Swift 6.3 / macOS 26 SDK 不兼容）。CI 镜像改为 macOS 26（与本地门禁工具链同代），性能工作流固定 runner 同步改为 `macos-26-xlarge`。

**步骤**：
1. 推送 `release-readiness` 分支到 GitHub 远端
2. 打开 Actions 页面的 **quality** 工作流，等待两个矩阵 job（macos-26 / macos-26-xlarge）完成
3. 打开 **performance** 工作流，手动触发一次（`workflow_dispatch`），等待完成并下载 performance-log artifact

**记录**：
- quality 两个 job 的 6 个脚本自测、质量扫描、完整测试、严格 Debug/Release 构建是否全绿
- 每轮测试数与套件数（应与本地 1126/65 一致或按 runner 实际输出）
- performance artifact 中的 log 是否包含完整基准输出、无偶发失败

**通过标准**：quality 全绿；performance 在固定 runner 连续两次触发无偶发失败且趋势 log 可下载。

**失败处理**：runner 不可用时**保留真实失败**，不得降级为单架构成功（仓库约束）。

---

## 验收 5：VoiceOver 实际播报与键盘调整

**目标**：证明分页控件的无障碍改造在真实 VoiceOver 下可读可操作。

**步骤**：
1. 启动应用，打开任意多页布局（≥2 页）
2. 开启 VoiceOver（Command+F5）
3. 将焦点移到页码指示器，确认播报：
   - 角色为"滑块/调整器"类
   - 内容为"Page N of M"格式的当前页/总页数
4. 使用 VoiceOver 的调整操作（Control+Option+Command+↑/↓）切换页面
5. 依次验证：首页 decrement 无动作、末页 increment 无动作、中间页可增可减、页面切换生效

**记录**：实际播报文本、切换是否生效、边界行为。

**通过标准**：VoiceOver 可播报当前页/总页数并可切换页面，边界不越界。

**补充**：同时人工确认搜索态下页码点隐藏、文件夹分页的页码控件同样可操作。

---

## 完成后回写

全部（或部分）验收完成后，更新 `docs/release-readiness-todo.md`：

1. 将已通过的验收项从待处理移出（或标注"外部验收已通过 + 证据")
2. 重新统计"已修复/待处理"并更新发布结论：
   - 六项发布阻断清零 + 门禁连续两次通过 → 发布结论可更新为"具备正式发布条件"
   - 任一外部验收失败 → 保持"不可正式发布"，记录失败证据与解除条件
3. 提交更新（单独提交，便于回溯）
