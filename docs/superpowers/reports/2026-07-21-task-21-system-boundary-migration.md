# Task 21 System Boundary Migration

Task baseline: `fa07620`. Pure migration production baseline: `5461d8db7cc4d0f6b0f14594bac2d186cbe5d43c`.

The first two code fields in every row are the exact qualified old and new discovery IDs.

| Old discovery ID | New discovery ID | Coverage preserved |
| --- | --- | --- |
| `LaunchPadTests.FileWatcherTests/testDeinit_afterStart_doesNotCrash` | `LaunchPadTests.FileWatcherTests/deinit_afterStart_doesNotCrash()` | active deinit stops backend |
| `LaunchPadTests.FileWatcherTests/testDeinit_withoutStart_isSafe` | `LaunchPadTests.FileWatcherTests/deinit_withoutStart_isSafe()` | inactive deinit leaves backend untouched |
| `LaunchPadTests.FileWatcherTests/testHandleEvents_clientCallBackInfoNil_returnsEarly` | `LaunchPadTests.FileWatcherTests/handleEvents_clientCallBackInfoNil_returnsEarly()` | late callback after stop is discarded |
| `LaunchPadTests.FileWatcherTests/testInit_customDebounceInterval` | `LaunchPadTests.FileWatcherTests/init_customDebounceInterval()` | custom interval boundary |
| `LaunchPadTests.FileWatcherTests/testInit_doesNotCrash` | `LaunchPadTests.FileWatcherTests/init_doesNotCrash()` | inert initialization |
| `LaunchPadTests.FileWatcherTests/testInit_zeroDebounceInterval_doesNotCrash` | `LaunchPadTests.FileWatcherTests/init_zeroDebounceInterval_doesNotCrash()` | zero interval callback |
| `LaunchPadTests.FileWatcherTests/testStart_emptyPaths_doesNotCrash` | `LaunchPadTests.FileWatcherTests/start_emptyPaths_doesNotCrash()` | empty paths reject startup |
| `LaunchPadTests.FileWatcherTests/testStart_realFileChange_triggersOnChange` | `LaunchPadTests.FileWatcherTests/start_realFileChange_triggersOnChange()` | one UUID host FSEvents integration |
| `LaunchPadTests.FileWatcherTests/testStart_stop_thenStartAgain_doesNotCrash` | `LaunchPadTests.FileWatcherTests/start_stopThenStartAgain_doesNotCrash()` | stop and restart ownership |
| `LaunchPadTests.FileWatcherTests/testStart_streamCreationFails_doesNotCrash` | `LaunchPadTests.FileWatcherTests/start_streamCreationFails_doesNotCrash()` | backend start failure |
| `LaunchPadTests.FileWatcherTests/testStart_streamCreationFails_thenStop_isSafe` | `LaunchPadTests.FileWatcherTests/start_streamCreationFails_thenStop_isSafe()` | stop after start failure |
| `LaunchPadTests.FileWatcherTests/testStart_thenStop_releasesProperly` | `LaunchPadTests.FileWatcherTests/start_thenStop_releasesProperly()` | double stop idempotence |
| `LaunchPadTests.FileWatcherTests/testStart_withMultiplePaths_doesNotCrash` | `LaunchPadTests.FileWatcherTests/start_withMultiplePaths_doesNotCrash()` | multiple path forwarding |
| `LaunchPadTests.FileWatcherTests/testStop_withoutStart_doesNotCrash` | `LaunchPadTests.FileWatcherTests/stop_withoutStart_doesNotCrash()` | stop before start |
| `LaunchPadTests.AccessibilityObserverTests/testDeinit_doesNotCrash` | `LaunchPadTests.AccessibilityObserverTests/deinit_doesNotCrash()` | observer deinit cleanup |
| `LaunchPadTests.AccessibilityObserverTests/testInit_doesNotCrash` | `LaunchPadTests.AccessibilityObserverTests/init_doesNotCrash()` | observer initialization |
| `LaunchPadTests.AccessibilityObserverTests/testStop_multipleCalls_doesNotCrash` | `LaunchPadTests.AccessibilityObserverTests/stop_multipleCalls_doesNotCrash()` | observer double stop |
| `LaunchPadTests.AccessibilitySettingsTests/testAnimationFallback_normalMotion_returnsSpring` | `LaunchPadTests.AccessibilitySettingsTests/animationFallback_normalMotion_returnsSpring()` | normal motion strategy |
| `LaunchPadTests.AccessibilitySettingsTests/testAnimationFallback_reduceMotion_returnsFadeOrInstant` | `LaunchPadTests.AccessibilitySettingsTests/animationFallback_reduceMotion_returnsFadeOrInstant()` | reduced motion strategy |
| `LaunchPadTests.AccessibilitySettingsTests/testBackgroundMaterial_normalTransparency_returnsHudWindow` | `LaunchPadTests.AccessibilitySettingsTests/backgroundMaterial_normalTransparency_returnsHudWindow()` | normal transparency material |
| `LaunchPadTests.AccessibilitySettingsTests/testBackgroundMaterial_reduceTransparency_returnsSolidColor` | `LaunchPadTests.AccessibilitySettingsTests/backgroundMaterial_reduceTransparency_returnsSolidColor()` | reduced transparency material |
| `LaunchPadTests.AccessibilitySettingsTests/testContrastFallback_increaseContrast_returnsHighContrast` | `LaunchPadTests.AccessibilitySettingsTests/contrastFallback_increaseContrast_returnsHighContrast()` | increased contrast strategy |
| `LaunchPadTests.AccessibilitySettingsTests/testContrastFallback_normalContrast_returnsSystemColors` | `LaunchPadTests.AccessibilitySettingsTests/contrastFallback_normalContrast_returnsSystemColors()` | normal contrast strategy |
| `LaunchPadTests.AccessibilitySettingsTests/testCurrent_increaseContrast_isBool` | `LaunchPadTests.AccessibilitySettingsTests/current_increaseContrast_isBool()` | injected increase-contrast read |
| `LaunchPadTests.AccessibilitySettingsTests/testCurrent_reduceMotion_isBool` | `LaunchPadTests.AccessibilitySettingsTests/current_reduceMotion_isBool()` | injected reduce-motion read |
| `LaunchPadTests.AccessibilitySettingsTests/testCurrent_reduceTransparency_isBool` | `LaunchPadTests.AccessibilitySettingsTests/current_reduceTransparency_isBool()` | injected reduce-transparency read |
| `LaunchPadTests.AccessibilitySettingsTests/testCurrent_returnsValidSettings` | `LaunchPadTests.AccessibilitySettingsTests/current_returnsValidSettings()` | complete injected snapshot |
| `LaunchPadTests.AccessibilitySettingsTests/testInit_allFalse` | `LaunchPadTests.AccessibilitySettingsTests/init_allFalse()` | all-false value initialization |
| `LaunchPadTests.AccessibilitySettingsTests/testInit_allTrue` | `LaunchPadTests.AccessibilitySettingsTests/init_allTrue()` | all-true value initialization |
| `LaunchPadTests.AccessibilitySettingsTests/testInit_withExplicitValues` | `LaunchPadTests.AccessibilitySettingsTests/init_withExplicitValues()` | mixed explicit initialization |

## Verification

### FileWatcher migration boundary

Task 20 temporarily placed the UUID host proof in `FileWatcherLifecycleTests` while landing the Step 5 production lifecycle. Step 9 requires the old 14/14 `testStart_realFileChange_triggersOnChange` method to become that host proof. The proof was therefore moved into the mapped `FileWatcherTests/start_realFileChange_triggersOnChange()` case and removed from the lifecycle suite in the same production-empty migration commit. Keeping both would violate the explicit one-host-test contract.

- Sandboxed focused run: 13 injected tests passed; the host case failed because `FSEventStreamStart` returned false, then the structured 10-second timeout elapsed. No skip, retry, fixed wait or weakened assertion was introduced.
- Controlled host focused run: 14/14 passed; the real UUID-directory case passed after 1.074 seconds.
- Production baseline: `git diff --exit-code 5461d8d..HEAD -- Sources` must remain empty after both migration commits.

### Accessibility migration boundary

- Focused run: 16/16 passed across `AccessibilitySettingsTests` and `AccessibilityObserverTests`.
- All four `current_*` mappings use `AccessibilitySettingsSource`; no migrated test reads `NSWorkspace.shared`.
- All three observer mappings use their own `NotificationCenter` and constant injected settings provider.

### Qualified mapping gate

- Report old column: 30 lines.
- Report new column: 30 lines.
- Current qualified discovery: 30 lines.
- Baseline discovery versus report old column: empty diff.
- Report new column versus current discovery: empty diff.
- Legacy framework/static scan of both migrated files: empty output.
- `5461d8d..working tree` production diff: empty.

The final focused/full-suite and residue gates are recorded in the Task 21 execution report.
