import XCTest
@testable import LaunchPad

#if canImport(AppKit)
import AppKit

@MainActor
final class FileWatcherTests: XCTestCase {

    func testInit_doesNotCrash() {
        XCTAssertNotNil(makeWatcher())
    }

    func testInit_customDebounceInterval() {
        XCTAssertNotNil(makeWatcher(debounceInterval: 5.0))
    }

    func testStop_withoutStart_doesNotCrash() {
        let watcher = makeWatcher()
        watcher.stop()
    }

    func testStart_emptyPaths_doesNotCrash() {
        let backend = MockFileEventStream()
        let watcher = makeWatcher(backend: backend)

        XCTAssertFalse(watcher.start(paths: []) {})
        XCTAssertEqual(backend.startedPaths, [])
    }

    func testStart_thenStop_releasesProperly() {
        let backend = MockFileEventStream()
        let watcher = makeWatcher(backend: backend)

        XCTAssertTrue(watcher.start(paths: ["/Applications"]) {})
        watcher.stop()
        watcher.stop()

        XCTAssertEqual(backend.stopCallCount, 1)
    }

    func testDeinit_afterStart_doesNotCrash() {
        let backend = MockFileEventStream()
        var watcher: FileWatcher? = makeWatcher(backend: backend)
        XCTAssertTrue(watcher?.start(paths: ["/Applications"]) {} == true)

        watcher = nil

        XCTAssertEqual(backend.stopCallCount, 1)
    }

    func testStart_withMultiplePaths_doesNotCrash() {
        let backend = MockFileEventStream()
        let watcher = makeWatcher(backend: backend)
        let paths = ["/Applications", "/System/Applications"]

        XCTAssertTrue(watcher.start(paths: paths) {})
        XCTAssertEqual(backend.startedPaths, [paths])
    }

    func testStart_stop_thenStartAgain_doesNotCrash() {
        let backend = MockFileEventStream()
        let watcher = makeWatcher(backend: backend)

        XCTAssertTrue(watcher.start(paths: ["/Applications"]) {})
        watcher.stop()
        XCTAssertTrue(watcher.start(paths: ["/System/Applications"]) {})

        XCTAssertEqual(backend.stopCallCount, 1)
        XCTAssertEqual(backend.startedPaths, [["/Applications"], ["/System/Applications"]])
    }

    func testInit_zeroDebounceInterval_doesNotCrash() async {
        let backend = MockFileEventStream()
        let scheduler = MockScheduler()
        let watcher = FileWatcher(
            debounceInterval: 0,
            backend: backend,
            scheduler: scheduler
        )
        var changes = 0

        XCTAssertTrue(watcher.start(paths: ["/Applications"]) { changes += 1 })
        backend.emit()
        await Task.yield()
        scheduler.advance(by: 0)

        XCTAssertEqual(changes, 1)
    }

    func testDeinit_withoutStart_isSafe() {
        let backend = MockFileEventStream()
        var watcher: FileWatcher? = makeWatcher(backend: backend)

        XCTAssertNotNil(watcher)
        watcher = nil

        XCTAssertEqual(backend.stopCallCount, 0)
    }

    func testStart_realFileChange_triggersOnChange() async {
        let backend = MockFileEventStream()
        let scheduler = MockScheduler()
        let watcher = FileWatcher(
            debounceInterval: 0.1,
            backend: backend,
            scheduler: scheduler
        )
        var changes = 0

        XCTAssertTrue(watcher.start(paths: ["/Applications"]) { changes += 1 })
        backend.emit()
        await Task.yield()
        scheduler.advance(by: 0.1)

        XCTAssertEqual(changes, 1)
    }

    func testStart_streamCreationFails_doesNotCrash() {
        let backend = MockFileEventStream()
        backend.startResult = false
        let watcher = makeWatcher(backend: backend)

        XCTAssertFalse(watcher.start(paths: ["/Applications"]) {})
        watcher.stop()

        XCTAssertEqual(backend.startedPaths, [["/Applications"]])
        XCTAssertEqual(backend.stopCallCount, 0)
    }

    func testStart_streamCreationFails_thenStop_isSafe() {
        let backend = MockFileEventStream()
        backend.startResult = false
        let watcher = makeWatcher(backend: backend)

        XCTAssertFalse(watcher.start(paths: ["/Applications"]) {})
        watcher.stop()
        watcher.stop()

        XCTAssertEqual(backend.stopCallCount, 0)
    }

    func testHandleEvents_clientCallBackInfoNil_returnsEarly() async {
        let backend = MockFileEventStream()
        let scheduler = MockScheduler()
        let watcher = FileWatcher(
            debounceInterval: 0,
            backend: backend,
            scheduler: scheduler
        )
        var changes = 0

        XCTAssertTrue(watcher.start(paths: ["/Applications"]) { changes += 1 })
        watcher.stop()
        backend.emit()
        await Task.yield()
        scheduler.advance(by: 0)

        XCTAssertEqual(changes, 0)
    }

    private func makeWatcher(
        debounceInterval: TimeInterval = 2.0,
        backend: MockFileEventStream = MockFileEventStream()
    ) -> FileWatcher {
        FileWatcher(
            debounceInterval: debounceInterval,
            backend: backend,
            scheduler: MockScheduler()
        )
    }
}
#endif
