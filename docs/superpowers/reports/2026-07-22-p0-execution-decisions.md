# P0 Execution Decision Log

Date: 2026-07-22
Branch: `release-readiness`
Plan: `docs/superpowers/plans/2026-07-21-p0-release-blockers.md`

This is the single durable log for implementation decisions made while
executing the approved P0 release-blocker plan. Each entry records the evidence,
chosen action, affected scope, and verification contract. It does not replace
the approved plan or task-specific test reports.

## Decision 001: Resume Task 4 from the reviewed baseline

- Status: adopted
- Evidence: `.superpowers/sdd/progress.md` marks Tasks 1 through 3M complete;
  commits `29998af`, `47c5902`, `1de5594`, `d7073d4`, `f804ef9`, and `b169539`
  are the reviewed Task 4 baseline; HEAD was `86952cd`; the index was empty.
- Decision: use `86952cd` as the Task 4 implementation base. Preserve all
  existing dirty changes and do not replay, amend, reset, or revert the reviewed
  commits.
- Impact: Task 4 resumes at the unfinished Grid/coordinator/Search slices.
- Verification: compare the progress ledger, commit chain, task brief, working
  tree, and final Task 4 base-to-head review package.

## Decision 002: Reorder Task 4 to remove the self-delegate before Grid GREEN

- Status: adopted; explicitly confirmed by the user
- Evidence: the approved coordinator design records three independently
  reproducible non-converging AppKit paths while `AppGridCollectionView` is its
  own delegate: initial diffable reload, metrics-triggered `reloadItems`, and
  `deselectAll`. The pending Grid GREEN exercises those paths before the
  original Step 11-13 ordering removes the self-delegate.
- Decision: first complete the Step 11-13 ownership boundary atomically:
  introduce the external coordinator and host, migrate interaction tests, make
  `LaunchPadViewController` the strong owner, remove the grid's delegate and
  business-interaction API, and change programmatic clearing to
  `deselectItems(at:)`. Only then run Grid GREEN. Continue with Search,
  wall-clock regression, watchdog, and the original Task 4 release gates.
- Impact: changes only Task 4's internal execution and commit order. Final
  product behavior, interfaces, test inventory, strict timing thresholds, and
  downstream task ownership remain those of the approved plan.
- Verification: the focused coordinator/Grid suites must run under a bounded
  watchdog; static gates must find no grid self-delegate or obsolete interaction
  API; the real AppKit cycle must always assert `< 1s`.

## Decision 003: Preserve compatible dirty Grid work and rewrite conflicting selection work

- Status: adopted
- Evidence: the recovery audit found the dirty metrics, reload/reconfigure,
  section-aware accessibility, stable-ID lookup, test helpers, and eight Grid
  behavior tests consistent with the approved design. It also found a
  grid-owned optional selection callback, `deselectAll`, programmatic business
  output, and direct self-delegate callback tests inconsistent with that design.
- Decision: retain the compatible implementation and tests. Move callback-order
  behavior into the coordinator suite, delete grid-owned interaction callbacks,
  and ensure valid, nil, and unknown programmatic selection paths emit no
  business output.
- Impact: no intended change to user-facing selection behavior; ownership and
  notification semantics become explicit and cycle-free.
- Verification: stable-ID tests inspect real `selectionIndexPaths`; coordinator
  tests assert exact `changed:<id>` then `activated:<id>` ordering for mouse
  selection and zero output for every programmatic path.

## Decision 004: Continue autonomously and record future decisions here

- Status: adopted; explicitly authorized by the user
- Evidence: the user directed that subsequent tasks require no further
  confirmation, that recommended solutions be executed until all tasks finish,
  and that every decision be recorded in one Markdown document.
- Decision: within the approved P0 scope, resolve implementation ordering,
  engineering tradeoffs, and verification details using code and test evidence,
  then append the decision to this file. Pause only when external authority is
  required or the product requirement cannot be determined from the approved
  artifacts and repository evidence.
- Impact: execution proceeds continuously through all remaining plan tasks.
- Verification: every non-trivial deviation or choice has a numbered entry in
  this file and is covered by the applicable task report, review, and release
  gate.

## Decision 005: Keep Task 5 compileable and bound every AppKit test process

- Status: adopted under the user's autonomous-execution authorization
- Evidence: Task 5 Step 4 specifies `reloadProjectedLayout(preserving:)` and
  calls `selectItem(id:)`, while Step 5 is the first place that declares that
  method. The committed controller has no equivalent helper. Task 5's original
  focused commands are also unbounded even though Task 4 exists partly to close
  reproducible AppKit hot-loop failures.
- Decision: use the final reviewed Task 4 GREEN commit as Task 5's implementation
  and review base. Introduce stable-ID selection, page synchronization, and
  projected reload in one compileable production slice. Wrap every focused and
  aggregate Task 5 `swift test` command with the shared process-group watchdog.
- Additional constraints: remove both controller calls to the deprecated
  `updateLayout(screenWidth:)` path; retain `selectedIndex` only as a deprecated
  read-only stable-ID projection and in its single compatibility test; keep the
  existing always-enabled coordinator `< 1s` wall-clock assertion unchanged.
- Impact: Task 5's commit grouping and test invocation become deterministic;
  product behavior and the approved viewport/search/selection contracts do not
  change.
- Verification: Task 4 prerequisite static/focused gates pass first; Task 5 has
  no compile-broken commit; static scans reject legacy selected-index mutation
  and old viewport calls; watchdog-bounded controller, layout, paging,
  coordinator, grid, and integration suites pass.

## Decision 006: Execute Tasks 6-10 on isolated, bounded, linearly reviewed slices

- Status: adopted under the user's autonomous-execution authorization
- Evidence: the Task 6-10 preflight found that their original focused commands
  do not use the shared watchdog. It also found two concrete isolation and
  coverage defects: Task 8's new optional-result matrix covers only `.keyDown`
  even though the production monitor also receives `.flagsChanged`; Task 9's
  proposed keyboard helper constructs a default `HotkeyManager`, which can
  query real accessibility state and create a real event tap.
- Decision: execute Tasks 6 through 10 linearly, with each reviewed GREEN commit
  becoming the next task's base. Wrap every test process with
  `scripts/run-with-timeout.sh`. Extend Task 8's suppression matrix with
  `.flagsChanged -> nil`. Make Task 9 reuse the existing fully isolated hotkey
  fixture and replace weak direct-callback tests with real injected
  handler-chain identity and action assertions.
- Additional task boundaries: Task 6 applies search-state mutation and its
  tests atomically; Task 7 replaces the historical "every character enters
  search" test and uses the mock scheduler rather than wall-clock waiting;
  Task 10 lands the intent model, protocol, mock, and success/failure tests as
  one compileable slice, does not add `LayoutMutating` to `DataStoring`, and
  leaves exhaustive six-case behavior to Task 11.
- Impact: test execution and system-boundary behavior become deterministic;
  no approved product behavior changes beyond each task's existing contract.
- Verification: all touched tests remain Swift Testing; Task 8 proves both
  event types preserve callback nil; Task 9 performs no real AX, event-tap, or
  workspace side effect; Task 10 keeps the protocol composition unchanged and
  has no compile-broken intermediate commit.

## Decision 007: Make Task 4 AppKit boundaries directly observable and synchronous

- Status: adopted during Task 4 GREEN and review
- Evidence: `NSClipView` normalized a test's zero-width bounds back to its real
  viewport, so the intended independent invalid-axis branch was not reached.
  Diffable `reloadItems` also did not synchronously guarantee that the visible
  cell instance observed by the test had received the new metrics. The initial
  validation matrix asserted `.move` but did not directly prove the resolved
  hover value for every target type. VC and coordinator weak probes released
  before the AppKit view hierarchy only after its surrounding autorelease pool
  drained.
- Decision: add an internal, default-to-production clip-size reader so invalid
  width and height fallbacks can be injected independently. After applying a
  reloaded metrics snapshot, synchronously reconfigure current visible cells
  through the same app/folder configuration helpers. Require the coordinator
  validation matrix to assert exact hover values for group, app, page, stale
  path, and no-path cases in addition to drop-operation results. Drain a local
  autorelease pool before asserting complete VC/grid ownership-graph release.
- Impact: production defaults and drag/drop semantics remain unchanged; metrics
  application now has deterministic visible-content timing, and tests execute
  the intended branches rather than AppKit-normalized substitutes.
- Verification: Grid tests prove each axis fallback, reload the current visible
  cell instance, and assert both app and folder icon sizes; coordinator tests
  prove group `.overIcon` and all non-group/missing cases `.empty`. The latest
  bounded coordinator/Grid gate passes 95 tests with the suite still at exactly
  39 tests, and the controller/coordinator/grid weak probes all become nil.

## Decision 008: Make every commit gate fail closed

- Status: adopted after the first decision-log commit
- Evidence: `git diff --cached --check` correctly reported two Markdown trailing
  spaces, but the multi-command shell did not use `set -e`; it therefore
  continued to the commit instead of stopping at the failed quality gate.
- Decision: preserve the existing commit, remove the whitespace in a follow-up
  commit, and begin every future multi-command stage/commit gate with
  `set -euo pipefail` so any static or staging failure aborts before commit.
- Impact: no product behavior changes; repository hygiene failures become
  fail-closed and auditable.
- Verification: the follow-up diff passes `git diff --check`, its staged file
  list contains only this decision log, and subsequent task commit reports must
  include the fail-closed gate result.

## Decision 009: Enforce reviewed linear prerequisites through Task 16

- Status: adopted under the user's autonomous-execution authorization
- Evidence: Tasks 14, 15, and 16 consume types and behavior introduced by their
  immediate predecessors; the current committed tree does not yet contain the
  Task 10-13 domain/transaction types or the Task 15 drag-session type.
- Decision: execute and review Tasks 10 through 16 linearly. A later task may
  start only from the clean, reviewed GREEN commit of its immediate predecessor;
  uncommitted shared-worktree content never constitutes an interface contract.
- Impact: no behavior change; compile and review ranges remain attributable to
  one task and cannot accidentally consume partial upstream work.
- Verification: prerequisite types exist in `HEAD`, the previous task's focused
  gate and review are clean, and the next RED fails only on its own missing
  behavior.

## Decision 010: Remove Task 16 coordinate and optimistic-snapshot shortcuts atomically

- Status: adopted under the user's autonomous-execution authorization
- Evidence: the current coordinator compares AppKit window coordinates directly
  with collection bounds and forwards them directly to the local resolver. Its
  acceptance path also trusts a proposed index path and invokes
  `moveSnapshotItem`, mutating the visual snapshot before persistence commits.
- Decision: Task 16 lands exact window-to-local conversion, stable-ID destination
  resolution, callback-only acceptance, preview lifecycle, and contraction of
  the old host/snapshot API in one compileable reviewed slice. Strengthen the
  approved tests so every validate, accept, and drag-ended branch compares
  before/after snapshot identifiers, not only representative cases.
- Impact: hover remains preview-only and release remains the unique commit seam;
  no validation or preview path writes visual or persistent state.
- Verification: non-zero-origin tests prove exactly one coordinate conversion;
  stable-ID negative branches reject; all delegate branches preserve snapshot
  identifiers; static scans find no optimistic move API or old host shortcut.

## Decision 011: Expand Task 14 transaction-fault coverage to every destructive write family

- Status: adopted under the user's autonomous-execution authorization
- Evidence: the approved Task 14 matrix heavily exercises folder insert and
  item-update failures, while folder deletion and page delete/insert statements
  are equally capable of violating all-or-nothing layout persistence.
- Decision: retain the approved folder mutation matrix and add deterministic
  fault injection for folder delete plus page delete/insert paths. Every injected
  failure must roll back the complete layout, and a rollback failure must
  invalidate the connection before reopen verification.
- Impact: production transaction semantics are unchanged; release confidence in
  destructive and repagination branches increases.
- Verification: each new fault case checks the full pre-transaction snapshot,
  transaction status, connection invalidation when applicable, and state after a
  fresh database reopen.

## Decision 012: Strengthen Tasks 11-13 domain and storage boundary evidence

- Status: adopted under the user's autonomous-execution authorization
- Evidence: the minimum Task 11 matrix does not directly cover every invalid
  state/type/generated-ID/anchor branch; Task 12 needs evidence that one queue
  serializes concurrent reads and writes and that an already-autocommit primary
  failure is not hidden by a synthetic rollback; Task 13's minimum cases do not
  directly cover corrupted persisted topology or all five future-owned intents.
- Decision: add parameterized negative cases for every Task 11 validation and
  stable-anchor branch. Add a bounded Task 12 concurrent read/write test and
  direct autocommit-after-error evidence using existing driver/transaction
  injection; do not add a production-only seam solely for that test. Add Task 13
  corrupted-snapshot cases, a parameterized five-unsupported-intent zero-write
  matrix, and page-order bind/changes fault cases. Keep the Task 12 one-queue
  rewrite atomic and Task 13 behavior limited to top-level moves.
- Impact: task scope grows only in deterministic tests and required atomic
  implementation boundaries; future folder semantics remain owned by Task 14.
- Verification: every pure-state rejection preserves full value equality; every
  storage fault compares the complete persisted snapshot; concurrent operations
  finish under the watchdog without nested-queue deadlock; unsupported intents
  perform zero SQL writes.

## Decision 013: Scope Task 5 metrics no-op behavior to the current grid instance

- Status: adopted after Task 5 review
- Evidence: `LaunchPadViewController` caches `gridMetrics` across `loadView()`
  rebuilds. A replacement `AppGridCollectionView` begins with nil metrics, but a
  controller-only equality guard treats an unchanged viewport as a no-op and can
  permanently skip metrics application and layout projection for the new grid.
  Existing page-navigation tests also used empty persisted pages, which collapse
  to one visual page, and contained no behavioral assertions.
- Decision: the same-metrics early return requires both the controller and the
  current grid instance to already hold the calculated metrics. Add a rebuild
  regression that establishes metrics and data before replacing the view. Build
  navigation tests from enough real items to create multiple visual pages and
  assert exact right, left, drag, and dot destinations plus boundary no-ops.
  Add a loaded-but-nil-metrics keyboard matrix proving Up, Down, and Tab preserve
  stable selection state.
- Impact: rebuilding the view at the same viewport rehydrates the new grid while
  ordinary repeated layout remains a no-op; page and keyboard contracts gain
  real branch evidence without changing their approved behavior.
- Verification: the rebuild test proves the new grid receives metrics, snapshot
  sections, restored stable selection, and no storage writes; navigation tests
  prove actual multi-page transitions; keyboard nil-metrics tests inspect both
  stable ID and grid selection before and after every action.

## Decision 014: Keep one commit-time layout writer for every drop and folder mutation

- Status: adopted under the user's autonomous-execution authorization
- Evidence: the pre-Task-16 code can optimistically mutate a diffable snapshot,
  the legacy drag controller can persist reorder state, and `FolderController`
  performs multi-call folder CRUD. Retaining any of those after the intent-based
  transaction path would create duplicate or partially committed writers.
- Decision: grid and folder drag, reorder, drag-out, folder creation, and safe
  folder deletion only map a stable-ID intent and call
  `LaunchPadViewController.applyDropIntent` once on release. Success reloads
  after COMMIT; failure reloads the unchanged persisted state, reports the fixed
  accessible error, and returns false for AppKit snapback. Rename and ordinary
  app deletion retain only their explicitly approved dedicated paths.
- Impact: hover is preview-only, release is the unique mutation boundary, and no
  legacy CRUD or optimistic UI route can race the transaction writer.
- Verification: each branch records exactly one apply attempt, failures record
  zero success, snapshots stay unchanged before reload, and static scans find no
  old snapshot/reorder/folder-layout writer APIs.

## Decision 015: Treat overlay closure as a drag-session lifecycle exit

- Status: adopted under the user's autonomous-execution authorization
- Evidence: closing a folder removes the visual and coordinate context needed to
  resolve a folder-child drag, while Task 15's cancel operation is idempotent and
  performs no write. Leaving the session alive after an outside click would
  retain a timer or preview with no legal destination.
- Decision: every folder close path, including outside click, ESC, search,
  editing exit, window close, and hidden transition, cancels the active drag
  before removing overlay observers or content.
- Impact: closing a folder cannot leave a stale session, timer, preview, or
  observer. Native drag-ended cleanup remains idempotent and does not commit.
- Verification: each close trigger directly asserts nil session, cancelled
  scheduled work, cleared preview, removed observer token, and zero writer calls.

## Decision 016: Canonicalize scan corruption atomically and refresh active search

- Status: adopted under the user's autonomous-execution authorization
- Evidence: Task 20 requires malformed and duplicate persisted apps to be
  successful cases, while its example loops skip malformed rows and preserve
  duplicates whose bundle still exists. The current loaded-view refresh also
  retains stale `currentSearchResults` when a query is active.
- Decision: the scan transaction reads the complete persisted snapshot, orders
  existing apps stably, retains the first canonical row per bundle, deletes
  duplicate rows and app rows lacking `AppInfo`, then applies scanned first-wins
  insert/update/delete behavior and normalizes pages. After a successful batch,
  a loaded controller keeps its active query and re-executes it against the new
  item snapshot through the existing injectable search path; stale-query guards,
  selection restoration, and page clamp remain in force.
- Impact: old scan corruption is repaired rather than silently retained or
  causing a partial batch; loaded normal and search UIs both reflect committed
  scan state.
- Verification: malformed/duplicate fixtures reopen with one canonical row per
  installed bundle and no malformed apps; every fault rolls the full repair back;
  active-search tests cover added, removed, and renamed matches without changing
  the query or displaying stale results.

## Decision 017: Serialize system-resource ownership and keep one real FSEvents host test

- Status: adopted under the user's autonomous-execution authorization
- Evidence: Task 21's proposed `SystemFileEventStream` stores mutable raw stream,
  callback-context, and started state behind `@unchecked Sendable` without an
  explicit serialization mechanism. Removing the old stream override also
  affects production and test factories atomically, while Tasks 20 and 21 would
  otherwise create duplicate real FSEvents coverage.
- Decision: implement one locked cleanup state machine for backend start, stop,
  start-failure, callback, and deinit ownership. Add the shared mock/backend
  initializer and remove the legacy override plus every call site in the same
  compileable commit. Keep routine Task 20 watcher evidence injected; retain one
  UUID-scoped real FSEvents host test only in Task 21's final host gate.
- Impact: raw resources are released exactly once under concurrent lifecycle
  calls, no compatibility side door survives, and host integration remains
  covered without making focused suites environment-dependent.
- Verification: function-table tests count stop/invalidate/release/context
  cleanup for success and every failure; concurrent stop/deinit is idempotent;
  static scans reject the override and real system calls outside the backend and
  single host test.

## Decision 018: Resolve review findings from complete branch evidence

- Status: adopted during Task 6 review
- Evidence: the initial reviewer classified the lack of a mode assertion in
  `search_esc_clearSearch` as Important, but the same test file already contains
  `search_escTwice_closeWindow`, which asserts the first ESC returns
  `.clearSearch`, immediately changes the mode to `.idle`, and makes the second
  ESC return `.closeWindow`.
- Decision: do not add a duplicate ESC state assertion merely to satisfy an
  incomplete diff-context reading. Present the existing exact branch evidence
  to the same reviewer and require a corrected full verdict. Treat a review
  finding as a hypothesis until it is reconciled with all relevant branches.
- Impact: Task 6 remains limited to its approved character, Delete, and empty
  input behavior while retaining explicit regression coverage for the unchanged
  ESC transition.
- Verification: the reviewer re-read the focused range, withdrew the Important
  finding, and approved Task 6 with Critical/Important/Minor counts of `0/0/0`;
  the controller independently ran the focused suite with `21/21` tests passing.

## Decision 019: Verify search focus through AppKit's field editor

- Status: adopted during Task 7 systematic debugging
- Evidence: after the approved production call
  `makeFirstResponder(searchBar)`, the exact RED test and an independent
  controller run consistently reported `window.firstResponder` as the shared
  `NSTextView` field editor. Every action, query, and debounce assertion passed;
  only the brief's direct `NSSearchField` identity assertion failed.
- Decision: retain the single production request that makes the search field the
  responder, but test actual editing focus by requiring
  `searchBar.currentEditor()` to be non-nil and identical to
  `window.firstResponder`. Do not issue duplicate responder requests or weaken
  the assertion to a generic non-nil check.
- Impact: the test now expresses AppKit's real responder-chain contract while
  preserving the product requirement that the first character, input focus, and
  one debounced request are applied atomically.
- Verification: the corrected exact test passed `1/1`; the controller ran the
  complete VC and debounce filter with `118/118` passing; the independent task
  reviewer confirmed the field-editor assertion is the more accurate contract
  and approved with Critical/Important/Minor counts of `0/0/0`.

## Decision 020: Reuse the stronger monitor lifecycle test and cover both event types

- Status: adopted before Task 8 implementation
- Evidence: the existing injected-boundary lifecycle test already performs
  duplicate registration and duplicate unregistration and asserts exactly one
  install, exactly one remove, and removed-token identity. The brief's proposed
  idempotence test would duplicate a weaker subset. The production installer
  listens to both `.keyDown` and `.flagsChanged`, while the brief's nil matrix
  originally exercised only `.keyDown`.
- Decision: rename and retain the stronger lifecycle test under the Task 8
  focused-filter name instead of adding duplicate logic. Add an explicit
  `.flagsChanged` callback-nil case alongside special and ordinary keyDown cases,
  and run every case through the injected `localMonitorHandler` boundary.
- Impact: the suite has one authoritative lifecycle contract and a complete
  event-type suppression matrix without touching real accessibility, event-tap,
  or local-monitor system resources.
- Verification: the cumulative Task 8 diff preserves all lifecycle assertions;
  the controller ran `HotkeyManagerTests` with `50/50` passing, and the final
  reviewer approved the reuse and event matrix with no findings.

## Decision 021: Separate manager deallocation from callback suppression

- Status: adopted from Task 8 RED root-cause evidence
- Evidence: the original initializer used
  `self?.handleLocalMonitorEvent(event) ?? event`. Both a released manager and a
  live callback intentionally returning `nil` produce nil at that expression,
  so nil-coalescing incorrectly converts a valid suppression result into the
  original event. Changing only `handleLocalMonitorEvent` cannot satisfy the
  Task 8 contract.
- Decision: use an explicit weak-self guard that returns the original event only
  when the manager is gone, then return the live handler's `NSEvent?` without
  coalescing. Keep register/unregister unchanged. Tests must distinguish the two
  states: the same closure returns nil while the manager lives and the original
  event after a weak reference proves deallocation; ordinary keyDown must also
  prove callback invocation and nil propagation.
- Impact: callback suppression and object-lifecycle fallback no longer share an
  ambiguous optional path; special keys, ordinary keys, and flags changes obey
  one routing rule.
- Verification: the initial review caught two non-discriminating tests; fix
  `c3ae65d` made both old behavior and a live-manager false positive impossible.
  The controller reran `50/50`, and re-review reported
  Critical/Important/Minor counts of `0/0/0`.

## Decision 022: Prove suppression from every mapped action outcome

- Status: adopted before Task 9 implementation
- Evidence: `KeyboardNavigator` maps eight key codes, but the resulting action
  depends on mode. In idle, seven mappings are handled while Delete is
  `.ignored`; in search, directions and Tab are ignored; in edit, only Escape is
  handled. The old AppDelegate tests called the callback directly, asserted only
  non-nil or nothing, and used a partially isolated manager in the proposed new
  helper.
- Decision: exercise the real `localMonitorHandler` chain with the existing fully
  isolated hotkey fixture. Test all seven handled idle mappings as suppressed,
  and use idle Delete plus search-left as explicit mapped-but-ignored identity
  cases. Replace the two old weak tests instead of retaining duplicates, and
  upgrade the released-delegate case to the same monitor chain.
- Impact: event suppression is verified from semantic action results rather than
  switch membership, with no accessibility query, event tap, real monitor,
  workspace open, or System Settings side effect.
- Verification: the exact entry matrix passed `10/10`; the controller ran the
  four related suites with `228/228` passing; independent review reconciled the
  complete key/mode outcome table and reported no findings.

## Decision 023: Reject non-key events before reading key-only AppKit properties

- Status: adopted from Task 9 RED crash evidence
- Evidence: the approved pseudocode captured `event.characters` before checking
  `event.type`. A real `.flagsChanged` fixture raised
  `NSInternalInconsistencyException` with `Invalid message sent to FlagsChanged`
  in `-[NSEvent characters]` and terminated the test process with signal 6.
- Decision: after the weak-self guard, inspect only `event.type` and immediately
  return the original event unless it is `.keyDown`. Read `keyCode` and
  `characters` only on the keyDown branch, then enter the MainActor lifecycle,
  controller, and action routing logic. Do not catch the Objective-C exception or
  emulate flags events with a test seam.
- Impact: flags changes and any future non-keyDown local events are safe identity
  pass-throughs; keyDown suppression remains exactly `Action != .ignored`.
- Verification: the same flagsChanged test passed without a signal after the
  change; the combined `228/228` gate and independent review confirmed the guard
  ordering and the monitor's subscribed event types.

## Decision 024: Avoid an unstable nil-characters event fixture

- Status: adopted during Task 9 branch review
- Evidence: public `NSEvent.keyEvent` construction reliably produces empty and
  nonempty character strings but does not provide a stable keyDown fixture whose
  `characters` property is nil. Production handles nil and empty in the same
  `guard let characters, !characters.isEmpty` branch.
- Decision: use a loaded-controller, unknown-key event with an empty string as
  the dynamic guard-branch proof and inspect the nil arm statically. Do not add a
  production-only injection seam or rely on an undocumented event-construction
  trick solely to manufacture nil.
- Impact: the test remains deterministic and exercises the actual AppKit event
  path without expanding production API surface; both nil and empty still have
  one implementation branch.
- Verification: the empty event preserves exact object identity in the focused
  and aggregate gates; the reviewer confirmed the shared guard makes this an
  acceptable boundary rather than a coverage downgrade.

## Decision 025: Commit pure layout mutations through a validated candidate

- Status: adopted during Task 11 implementation and independent review
- Evidence: every public layout intent must leave the in-memory state unchanged
  on failure. Mutating `self` before a later helper or postcondition throws would
  expose a partially applied order even though persistence is expected to roll
  back. The Task 11 reviewer also found that the initial tests missed the
  two-item-folder owning-anchor branch and exact/zero-existing page boundaries.
- Decision: `apply` validates the original state, applies the intent to a local
  candidate, validates the resulting candidate, and assigns back to `self` only
  after both stages succeed. Keep `applyValidated` as the narrow internal path
  for already validated persistence work. Add exact regression coverage for
  owning-folder before/after dissolution and all page-count relations. Prove the
  new assertions with temporary production mutations, then restore production
  before committing the test-only review fix. Do not add a production test seam
  solely to force an otherwise unreachable post-validation throw.
- Impact: public mutations provide strong exception safety without widening the
  domain API; folder dissolution and page reconstruction now have branch-complete
  behavioral evidence. The remaining testability limitation stays visible as a
  review Minor instead of becoming permanent production complexity.
- Verification: the initial `19/19` suite passed; three temporary mutations
  produced `2`, `1`, and `2` issues respectively; the restored cumulative suite
  passed `21/21`, and the review fix commit changed only
  `LayoutDomainStateTests.swift`.

## Decision 026: Make SQLite success explicit and test the transaction machine

- Status: adopted before Task 12 implementation
- Evidence: the current storage layer shares one SQLite connection across two
  queues, ignores BEGIN/COMMIT/ROLLBACK and bind return codes, treats terminal
  query errors as normal end-of-data, and accepts writes that affect zero rows.
  The Task 12 preflight also showed that the plan's four proposed tests do not
  exercise driver prepare/bind/step/changes injection, immediate mode, or the
  autocommit branch after SQLite has already rolled back a transaction.
- Decision: serialize every public read, write, close, and transaction on one
  non-reentrant `databaseQueue`; transaction bodies may call only private helpers
  that receive the local nonoptional connection. Require exactly one affected
  row for update/delete/reorder and successful insert/upsert statements, so a
  stale ID is an explicit error. Test every driver fault family, both transaction
  modes, terminal query errors, rollback failure invalidation, and the
  already-autocommit path. Run every RED and GREEN command through the shared
  watchdog rather than the plan's unwrapped command examples.
- Impact: missing records cannot masquerade as successful persistence, concurrent
  access cannot race one connection, and rollback ambiguity has one documented
  invalidation boundary. The stricter stale-ID behavior is intentional and will
  be consumed by the atomic layout writer instead of being hidden by legacy CRUD.
- Verification: Task 12 must include exact stale-ID assertions, fault-injection
  assertions for each SQLite operation family, immediate/deferred transaction
  evidence, all existing null-field suites, and a static scan proving no old
  read/write queue or public-method transaction reentry remains.

## Decision 027: Assert persisted values, not incidental SQLite row order

- Status: adopted during Task 12 formal review
- Evidence: the initial stale-reorder test compared only fetched item IDs. If the
  transaction wrapper were removed, the first update could set the second row's
  ordering to zero before a later stale ID failed. Both rows would then share an
  ordering value, and SQLite could still return them in rowid order, making the
  ID-only assertion pass despite a missing rollback. The bind fault test likewise
  checked the returned error but not whether its autoclosure was evaluated.
- Decision: after a failed reorder, locate both rows by stable ID and assert each
  exact persisted ordering. Test driver bind directly with a side-effect counter
  and require that a fault-injected result leaves the counter at zero. Prove both
  assertions with temporary production mutations, restore production, and commit
  only the test changes.
- Impact: rollback and lazy fault injection are tested as observable state
  contracts rather than inferred from nondeterministic row order or error type.
- Verification: removing the reorder transaction produced the exact failure
  `second.ordering 0 != 1`; making bind eager produced `evaluationCount 1 != 0`.
  Restored production passed the controller's `55/55` StorageManager gate, and
  formal re-review reported Critical/Important/Minor counts of `0/0/0`.

## Decision 028: Expand Task 13 around the real eighth storage entry point

- Status: adopted from Task 13 preflight under autonomous execution authority
- Evidence: Task 13 adds public `apply`, invalidating Task 12's test claim that all
  seven public storage APIs enter `databaseQueue`. The generated brief also omits
  Decision 012's corrupt-topology, five unsupported-intent zero-write, and
  `updatePageOrdering` bind/changes cases, and its example commands bypass the
  mandatory shared watchdog.
- Decision: add `StorageManagerTests.swift` to the Task 13 commit whitelist and
  upgrade the queue observer to cover exactly eight public APIs, including one
  successful move apply. Treat the corrupt persisted topology matrix, all five
  non-move intents with zero layout SQL writes and unchanged full snapshots, and
  page-ordering bind/changes faults as binding Task 13 requirements. Assert exact
  domain errors for stale source, stale anchor, self drop, and invalid capacity.
  Wrap every focused command with `scripts/run-with-timeout.sh 120 --`.
- Impact: Task 13 cannot add an unobserved queue entry, reject unsupported work
  after touching SQLite, or leave a page-ordering statement fault untested. The
  scope expands by one existing test file but does not move Task 14 folder writes
  or UI integration forward.
- Verification: the Task 13 cumulative review must show only
  `StorageManager.swift`, `StorageManagerLayoutMutationTests.swift`, and
  `StorageManagerTests.swift`; the focused run must dynamically cover the eighth
  queue entry, exact zero-write counters for all unsupported intents, complete
  before/after snapshots, and each added fault branch.

## Decision 029: Verify the complete persisted layout before every layout COMMIT

- Status: adopted and verified in Task 13
- Evidence: checked statement return codes prove that SQLite accepted each call,
  but they do not prove that the final parent/order graph matches the domain
  result. A fault can return `SQLITE_DONE` without performing the intended write,
  and a locally valid page plan can still be persisted in the wrong order.
- Decision: the top-level layout entry reads one complete snapshot, validates its
  topology, applies the stable-ID intent in pure domain state, persists the dense
  page plan, then re-reads and compares page IDs/order, page children/order,
  flattened top-level order, folder children, created titles, and the full ID set
  before COMMIT. Keep all of this inside one immediate transaction and the one
  `databaseQueue`; unsupported intents are rejected before snapshot or layout SQL.
- Impact: successful SQLite status codes cannot hide a partial or misordered
  layout, and the future folder implementation inherits one verified transaction
  boundary instead of adding a second writer.
- Verification: a silent `SQLITE_DONE` no-op produced
  `persistedStateMismatch` and a full rollback; corrupt topology and five
  unsupported intents preserved complete snapshots; the controller ran `86/86`
  related tests and formal review reported `0/0/0` findings.

## Decision 030: Correct and broaden Task 14's destructive folder matrix

- Status: adopted from Task 14 preflight under autonomous execution authority
- Evidence: the generated brief duplicates the final child in its safe-delete
  expected order, contradicting the pure domain result and unique-ID invariants.
  It also omits Decision 011's folder-delete and repagination fault families, and
  its rollback-failure case fails before any real layout write occurs.
- Decision: use the exact safe-delete sequence `[before, child0, child1, child2,
  after]`. Add checked prepare/bind/step/changes cases for folder deletion,
  overflow page insertion, and obsolete-page deletion, with exact errors and full
  snapshot rollback. Make rollback failure occur after at least one successful
  layout write, then prove the first connection is unavailable and a fresh `/tmp`
  reopen equals the original snapshot. Also cover metadata creation exactly once,
  zero-child delete, reorder before/after, and retained/dissolved folder anchor
  combinations. Use the shared watchdog for every command.
- Impact: Task 14 exercises every destructive write family without violating the
  correct domain order or silently expanding into later UI-writer removal.
- Verification: the Task 14 task review must reconcile every branch against the
  domain state, show exact fault-to-error mappings, prove no partial state after
  rollback/reopen, and retain the original three-file whitelist.

## Decision 031: Enforce storage serialization as a Dispatch barrier invariant

- Status: adopted and verified in Task 12R
- Evidence: the first concurrency test could deadlock itself while waiting for
  all workers to reach a start gate. Its replacement used a 250ms absence check
  to infer that a second database call had not entered, but a caller can be
  descheduled after announcing it started and before submitting `sync`; this
  made the concurrent-queue mutation capable of a false GREEN. The local 5s and
  250ms deadlines also contradicted the repository watchdog's role as the only
  deadlock bound. A platform probe demonstrated that
  `dispatchPrecondition(.onQueueAsBarrier(queue))` returns on a serial queue and
  deterministically traps in a normal synchronous block on a concurrent queue.
- Decision: centralize every `databaseQueue.sync` entry, including deinit close,
  in `onDatabaseQueue` and assert `.onQueueAsBarrier(databaseQueue)` inside the
  critical section. Remove the timing probe and every test-local deadline or
  timeout; enqueue 24 public writes and 24 public reads on a concurrent worker
  queue, release all gate tokens, and use an unbounded `DispatchGroup.wait()` so
  `scripts/run-with-timeout.sh 120 --` remains the sole deadlock supervisor.
  Expand the Task 12R cumulative whitelist to `StorageManager.swift` plus
  `StorageManagerTests.swift`; do not retain the earlier test-only whitelist once
  the black-box limitation is proven.
- Impact: serialization is now a production structural invariant rather than a
  timing inference or queue-label observation. Accidentally changing the storage
  queue to `.concurrent` fails at the first database critical section before
  SQLite operations overlap, while normal read/write completion and persisted
  values remain dynamically verified.
- Verification: the temporary `.concurrent` mutation triggered
  `_dispatch_assert_queue_barrier_fail` with shell exit 133; restored production
  passed the controller's fresh `87/87` tests across 8 suites. The cumulative
  diff contained only the two authorized files, and formal review reported spec
  compliant, Task quality Approved, and Critical/Important/Minor `0/0/0`.

## Decision 032: Delete explicit folders before obsolete parent pages

- Status: adopted and verified in Task 14 formal review
- Evidence: the initial Task 14 sequence let `persistPagePlan` delete obsolete
  pages before processing `folderIDsToDelete`. In a valid two-page layout
  `[before, after] / [emptyFolder]` with capacity 2, deleting the empty folder
  makes the second page obsolete, but the folder remains parented to that page
  because it is absent from the post-mutation page plan. SQLite's
  `parent_id ... ON DELETE CASCADE` therefore deleted the folder with its page;
  the later explicit folder delete observed zero changes and raised
  `StorageError.deleteFailed`. A focused pre-fix test reproduced exactly this
  failure.
- Decision: split non-destructive page resolution/reparenting from obsolete-page
  deletion. Persist surviving folder children, create/order pages, and reparent
  every surviving top-level item first; then delete every explicit folder effect;
  only then delete obsolete pages, verify the complete snapshot, and COMMIT. Do
  not add temporary detach SQL and do not relax the checked `changes == 1`
  contract. This refines Decision 030's broad "page writes before folder delete"
  rule by separating constructive page writes from destructive page cleanup.
- Impact: a parent-page cascade can no longer consume a folder before its checked
  explicit delete, while surviving children are still reparented before any
  folder deletion. The implementation avoids a new SQL statement family and
  preserves deterministic fault injection for both folder and page deletion.
- Verification: the two-page empty-folder case now commits to one dense page and
  `[before, after]`. A four-case matrix fails the second `deleteLayoutItem` at
  prepare/bind/step/changes after the first folder delete has reported successful
  changes, and every case restores the complete pre-transaction snapshot. The
  controller passed `116/116` tests across 9 suites; final cumulative review
  reported spec compliant, Task quality Approved, and
  Critical/Important/Minor `0/0/0`.

## Decision 033: Commit drag state before callbacks and isolate the legacy bridge

- Status: adopted and verified in Task 15.
- Evidence: the initial implementation notified preview clearing before removing
  the preview from `session`; a synchronous callback could therefore reenter
  `finishDrag()` and recursively observe the same preview. Edge and preview
  timers also matched only a destination, so an old action could hit a new,
  value-similar drag. Separately, the still-unmigrated grid coordinator enters
  gesture-only dragging without a native session and requires a temporary
  `.overIcon` substate. The first formal review then proved that forwarding the
  legacy API into the native path could clear a live native preview and emit a
  callback, violating that temporary bridge's no-side-effect contract.
- Decision: every callback-visible transition first commits `state`, immutable
  `session`, timer cancellation, and a monotonically advancing session revision;
  callback return paths perform no trailing state write. Delayed actions capture
  the complete armed session and revision. The legacy hover API operates only
  while gesture-only dragging has no native session, projects `.overIcon`, maps
  directionless screen-edge/empty to `.none`, and never schedules, cancels,
  calls back, or writes. Native sessions treat the legacy API as a strict no-op.
- Impact: synchronous reentry cannot recurse on stale preview state or overwrite
  a replacement session; stale timers cannot produce ABA-style page/preview
  actions; Task 16 retains a narrow compile-time bridge without restoring order,
  CRUD, writer, or persistence behavior.
- Verification: five review-fix regressions first failed against the original
  implementation; the final native-session legacy test produced 12 issues before
  the fix and zero after it. Controller-fresh evidence is `239/239` for the
  non-Window aggregate. The original Window gate contains `223` tests and still
  has exactly the registered three tests/four issues. Final independent review
  reported spec compliant, Task quality Approved, and
  Critical/Important/Minor `0/0/0` for commits `40393dd..a136bd5`.

## Decision 034: Make Task 16 page-aware at the point edge policy is introduced

- Status: adopted before Task 16 implementation.
- Evidence: Task 16 makes `canHoverEdge` depend on the grid host's
  `currentVisualPageIndex`, while the written plan delays synchronization from
  the real page-scroll/controller source until Task 18. On visual page 1 this
  would leave the host at zero and reject a valid backward edge hover. The same
  preflight found that the planned shared `MockDraggingInfo` is currently named
  `CoordinatorDraggingInfo`, `sourceVisualIndex` is not pinned to section versus
  item, and a truly empty page has no stable item from which to construct the
  required `afterItem` placement.
- Decision: expand Task 16's explicit whitelist to
  `LaunchPadViewController.swift` and its test file, and synchronize the grid at
  the three primitive page-state boundaries: reload clamp, scroll callback, and
  programmatic page synchronization. Derived dot, edge, selection, and search
  paths inherit those primitives and must not add duplicate setters. Define
  `sourceVisualIndex` as the snapshot section/visual-page index and test it with
  different section and item values. Rename the module-internal dragging-info
  fake to the Task 19 contract name. Treat a genuinely empty page section as an
  invalid persisted/projection topology for drop anchoring and reject it; blank
  space on a nonempty page always maps to `afterItem(lastStableID)`.
- Impact: Task 16 becomes independently correct rather than relying on a later
  task to repair its edge policy. Task 18 retains page-synchronization regression
  tests but does not duplicate production wiring. Empty-page rejection avoids
  inventing a visual page number or unstable synthetic anchor.
- Verification: Task 16 must cover reload reduction, scroll, programmatic/dot,
  both edge directions on a middle page, section-2/item-5 source identity,
  search sections, nonempty blank append, and empty-section rejection. Its task
  review must reconcile the expanded whitelist and show no duplicate setter path.

## Decision 035: Guard transient auto-hide work with message identity

- Status: adopted before Task 17 implementation.
- Evidence: cancelling a `DispatchWorkItem` marks it cancelled but does not make
  an already delivered or explicitly performed closure incapable of running.
  The plan's closure unconditionally called `hide()`, so the old work item from
  `show("first")` could hide a later `show("second")`. The planned repeated-show
  test checked only `isCancelled` and never executed the stale item.
- Decision: each show owns an identity token/generation in addition to the
  cancellable work item. Auto-hide verifies it is still the current message
  before clearing state. Manual hide and deinit cancel the owned item and
  invalidate its identity. Add deterministic synchronous tests for stale/current
  item execution, manual idempotent hide, release cancellation, custom duration,
  accessibility role/priority, and no-window layout; keep the fixed layout-error
  text owned by Task 18's domain call site rather than the generic view.
- Impact: rapid consecutive failures cannot have an older timeout erase the most
  recent accessible message, and Task 17 remains a reusable presentation view
  without importing layout-domain wording.
- Verification: Task 17 RED must explicitly perform the cancelled old item after
  the second show and observe the second message still visible; the current item
  must then be the only action that hides it.

## Decision 036: Give native drag cleanup one owner and keep failure recovery sanitized

- Status: adopted before Task 18 implementation.
- Evidence: Task 16 assigns native terminal cleanup to
  `draggingSession(_:endedAt:dragOperation:)`, while the Task 18 example also
  places `finishDrag()` in `applyDropIntent`'s `defer`; `finishDrag()` advances
  revision and cancels scheduling on every call, so this is observable double
  cleanup. `KeyboardNavigator` can remain in `.search("")` after deleting the
  final character, but the plan would re-enable drag from `handleSearch("")`,
  splitting the source/validate/accept guards from the controller writer guard.
  Finally, the planned sanitized mutation logger calls the existing `loadData()`
  on failure, whose catch interpolates the underlying error into `NSLog`.
- Decision: native `ended` is the sole terminal cleanup for native drags; the VC
  writer owns only one mutation attempt, authoritative reload, fixed feedback,
  and structured logging. Explicit search/ESC/window cancellation uses an
  idempotent cancel entry. One `synchronizeDragAvailability()` derives all grid,
  folder, and writer availability from both keyboard mode and current query, so
  `.search("")` remains disabled until an actual idle transition. Mutation
  failure reloads the last committed state through an injectable sanitized read
  and log boundary; neither apply nor reload errors or folder titles enter logs.
  Record attempted capacities before throws and trace apply-return/throw before
  exact authoritative read counts.
- Impact: accept-to-ended sequences clean up once, search cannot expose a partial
  drag surface, and rollback/storage failures cannot bypass the structured log
  policy. Failure reload is explicitly a snapback to committed state, not a UI
  update based on an uncommitted mutation.
- Verification: Task 18 must test accept-before/after-ended cleanup counts,
  callback false/reject plus ended, all mixed mode/query search states, six intent
  event mappings, sensitive sentinel errors from both mutation and reload, exact
  attempted capacity, AppDelegate dual-reference identity/nil combinations, and
  COMMIT-or-throw ordering before reads.
