import Foundation
import LaunchPadProtocols
@testable import LaunchPad
#if canImport(AppKit)
import AppKit
#endif

enum TestError: Error { case generic }

// MARK: - MockItemReading

final class MockItemReader: ItemReading, @unchecked Sendable {
    var items: [PageItem] = []
    var fetchAllItemsHandler: ((Int64?) throws -> [PageItem])?
    private(set) var fetchAllItemsCallCount = 0

    func fetchAllItems(parentId: Int64?) throws -> [PageItem] {
        fetchAllItemsCallCount += 1
        return try fetchAllItemsHandler?(parentId) ?? items
    }
}

// MARK: - MockItemWriting

final class MockItemWriter: ItemWriting, @unchecked Sendable {
    var insertedItems: [PageItem] = []
    var updatedItems: [PageItem] = []
    var deletedIds: [Int64] = []
    var reorderedParentIds: [(parentId: Int64, orderedIds: [Int64])] = []
    var nextInsertId: Int64 = 1
    var insertError: Error?
    var reorderError: Error?
    var shouldThrow: Bool = false {
        didSet { if shouldThrow { reorderError = TestError.generic } }
    }

    func insertItem(_ item: PageItem) throws -> Int64 {
        if let error = insertError { throw error }
        insertedItems.append(item)
        let id = nextInsertId
        nextInsertId += 1
        return id
    }

    var updateError: Error?
    func updateItem(_ item: PageItem) throws {
        if let error = updateError { throw error }
        updatedItems.append(item)
    }

    var deleteError: Error?
    func deleteItem(id: Int64) throws {
        if let error = deleteError { throw error }
        deletedIds.append(id)
    }

    func reorderItems(parentId: Int64, orderedIds: [Int64]) throws {
        if let error = reorderError { throw error }
        reorderedParentIds.append((parentId, orderedIds))
    }
}

// MARK: - MockLayoutMutator

final class MockLayoutMutator: LayoutMutating, @unchecked Sendable {
    private(set) var applyAttemptCount = 0
    private(set) var attemptedIntents: [LayoutDropIntent] = []
    private(set) var attemptedPageCapacities: [Int] = []
    private(set) var appliedIntents: [LayoutDropIntent] = []
    private(set) var appliedPageCapacities: [Int] = []
    var applyError: Error?
    var eventRecorder: ((String) -> Void)?

    func apply(_ intent: LayoutDropIntent, pageCapacity: Int) throws {
        applyAttemptCount += 1
        attemptedIntents.append(intent)
        attemptedPageCapacities.append(pageCapacity)
        eventRecorder?("apply-start")
        if let applyError {
            eventRecorder?("apply-throw")
            throw applyError
        }
        appliedIntents.append(intent)
        appliedPageCapacities.append(pageCapacity)
        eventRecorder?("apply-return")
    }
}

// MARK: - MockImageStoring

final class MockImageStore: ImageStoring, @unchecked Sendable {
    var storedImages: [Int64: (icon1x: Data, icon2x: Data)] = [:]
    var stored: [Int64: (icon1x: Data, icon2x: Data)] {
        get { storedImages }
        set { storedImages = newValue }
    }
    var fetchResult: (Data, Data)?
    var fetchError: Error?
    private(set) var fetchCallCount = 0
    private(set) var saveCallCount = 0

    func saveImage(itemId: Int64, icon1x: Data, icon2x: Data) throws {
        saveCallCount += 1
        storedImages[itemId] = (icon1x, icon2x)
    }

    func fetchImage(itemId: Int64) throws -> (Data, Data)? {
        fetchCallCount += 1
        if let error = fetchError { throw error }
        return fetchResult ?? storedImages[itemId]
    }
}

// MARK: - MockFileSystemService

final class MockFileSystemService: FileSystemService, @unchecked Sendable {
    var directoryContentsMap: [URL: [URL]] = [:]
    var directoryContents: [URL] = []
    var bundleInfos: [URL: [String: any Sendable]] = [:]
    var existingFiles: Set<URL> = []
    var shouldThrowOnContentsOfDirectory = false

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        if shouldThrowOnContentsOfDirectory { throw TestError.generic }
        return directoryContentsMap[url] ?? directoryContents
    }

    func fileExists(at url: URL) -> Bool {
        return existingFiles.contains(url)
    }

    func bundleInfo(at bundleURL: URL) -> [String: any Sendable]? {
        return bundleInfos[bundleURL]
    }
}

final class MockFileEventStream: FileEventStreaming, @unchecked Sendable {
    var startResult = true
    private(set) var startedPaths: [[String]] = []
    private(set) var stopCallCount = 0
    private var onEvents: (@Sendable () -> Void)?

    func start(paths: [String], onEvents: @escaping @Sendable () -> Void) -> Bool {
        startedPaths.append(paths)
        guard startResult else { return false }
        self.onEvents = onEvents
        return true
    }

    func stop() {
        stopCallCount += 1
        onEvents = nil
    }

    func emit() { onEvents?() }
}

// MARK: - MockIconProviding

#if canImport(AppKit)
final class MockIconProvider: IconProviding, @unchecked Sendable {
    var iconResult = NSImage(size: NSSize(width: 128, height: 128))
    var modificationDateResult: Date?
    var icons: [String: NSImage] = [:]
    var modificationDates: [String: Date] = [:]
    private(set) var fetchCallCount = 0

    func icon(forPath path: String) -> NSImage {
        fetchCallCount += 1
        return icons[path] ?? iconResult
    }

    func modificationDate(forPath path: String) -> Date? {
        return modificationDates[path] ?? modificationDateResult
    }
}
#endif

// MARK: - MockHotkeyManager

@MainActor
final class MockHotkeyManager: HotkeyManaging {
    var onToggle: (@Sendable () -> Void)?
    var registerResult = true
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    func registerGlobalHotkey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> Bool {
        registerCallCount += 1
        return registerResult
    }

    func unregisterGlobalHotkey() {
        unregisterCallCount += 1
    }
}

// MARK: - MockScheduler

@MainActor
final class MockScheduler: Scheduler {
    var scheduledActions: [(interval: TimeInterval, action: @MainActor @Sendable () -> Void)] = []
    private(set) var cancelCallCount = 0
    private var currentTime: TimeInterval = 0

    func schedule(
        after interval: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        scheduledActions.append((currentTime + interval, action))
    }

    func cancelPending() {
        cancelCallCount += 1
        scheduledActions.removeAll()
    }

    func advance(by duration: TimeInterval) {
        currentTime += duration
        let toFire = scheduledActions.filter { $0.interval <= currentTime }
        scheduledActions.removeAll { $0.interval <= currentTime }
        toFire.forEach { $0.action() }
    }

    func fireLatest() {
        let action = scheduledActions.last?.action
        scheduledActions.removeAll()
        action?()
    }
}
