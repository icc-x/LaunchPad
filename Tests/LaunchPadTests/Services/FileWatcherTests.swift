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

    // MARK: - Additional coverage tests

    func testStart_withMultiplePaths_doesNotCrash() {
        let watcher = FileWatcher()
        watcher.start(paths: [NSTemporaryDirectory(), NSTemporaryDirectory()]) { }
        watcher.stop()
    }

    func testStart_stop_thenStartAgain_doesNotCrash() {
        // start -> stop -> start，引用计数已平衡，应可安全重启
        let watcher = FileWatcher()
        watcher.start(paths: [NSTemporaryDirectory()]) { }
        watcher.stop()
        watcher.start(paths: [NSTemporaryDirectory()]) { }
        watcher.stop()
    }

    func testInit_zeroDebounceInterval_doesNotCrash() {
        let watcher = FileWatcher(debounceInterval: 0)
        XCTAssertNotNil(watcher)
        watcher.start(paths: [NSTemporaryDirectory()]) { }
        watcher.stop()
    }

    func testDeinit_withoutStart_isSafe() {
        autoreleasepool {
            _ = FileWatcher()
        }
    }

    func testStart_realFileChange_triggersOnChange() throws {
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let expectation = expectation(description: "onChange triggered")
        let watcher = FileWatcher(debounceInterval: 0.1)
        watcher.start(paths: [dir]) {
            expectation.fulfill()
        }
        defer { watcher.stop() }

        // 写入文件触发 FSEvents
        let file = (dir as NSString).appendingPathComponent("test.txt")
        try "hello".write(toFile: file, atomically: true, encoding: .utf8)

        wait(for: [expectation], timeout: 10.0)
    }

    // MARK: - stream 创建失败防御分支

    func testStart_streamCreationFails_doesNotCrash() {
        // 注入总是返回 nil 的 stream 工厂，模拟 FSEventStreamCreate 失败
        let watcher = FileWatcher(debounceInterval: 1.0, streamCreationOverride: { nil })
        watcher.start(paths: [NSTemporaryDirectory()]) { }
        // stream 为 nil 时应安全返回，不崩溃
        watcher.stop()
    }

    func testStart_streamCreationFails_thenStop_isSafe() {
        let watcher = FileWatcher(streamCreationOverride: { nil })
        watcher.start(paths: [NSTemporaryDirectory()]) { }
        watcher.stop()
        watcher.stop() // double stop after failed creation
    }
}
#endif
