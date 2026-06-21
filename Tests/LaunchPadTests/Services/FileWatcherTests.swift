import XCTest
@testable import LaunchPad

#if canImport(AppKit)
import AppKit

/// Tests for FileWatcher (0% → basic safety)
final class FileWatcherTests: XCTestCase {

    func testInit_doesNotCrash() {
        let watcher = FileWatcher()
        XCTAssertNotNil(watcher)
    }

    func testInit_customDebounceInterval() {
        let watcher = FileWatcher(debounceInterval: 5.0)
        XCTAssertNotNil(watcher)
    }

    func testStop_withoutStart_doesNotCrash() {
        let watcher = FileWatcher()
        watcher.stop() // Should not crash
    }

    func testStart_emptyPaths_doesNotCrash() {
        let watcher = FileWatcher()
        watcher.start(paths: []) { }
        // Should return early without creating stream
        watcher.stop()
    }

    func testStart_thenStop_releasesProperly() {
        let watcher = FileWatcher()
        // Use a real but harmless path
        watcher.start(paths: [NSTemporaryDirectory()]) { }
        watcher.stop()
        // Stop called twice should be safe
        watcher.stop()
    }

    func testDeinit_afterStart_doesNotCrash() {
        // Ensure deinit calls stop() properly
        autoreleasepool {
            let watcher = FileWatcher()
            watcher.start(paths: [NSTemporaryDirectory()]) { }
            // watcher goes out of scope here
        }
    }
}
#endif
