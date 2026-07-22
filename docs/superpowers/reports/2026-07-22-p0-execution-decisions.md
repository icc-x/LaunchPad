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
