import Foundation
import LaunchPadProtocols
#if canImport(AppKit)
import AppKit

protocol FileEventStreaming: AnyObject, Sendable {
    @discardableResult
    func start(paths: [String], onEvents: @escaping @Sendable () -> Void) -> Bool
    func stop()
}

struct FSEventStreamFunctions: @unchecked Sendable {
    let create: (FSEventStreamCallback, UnsafeMutablePointer<FSEventStreamContext>, CFArray, FSEventStreamEventId, CFTimeInterval, FSEventStreamCreateFlags) -> FSEventStreamRef?
    let setDispatchQueue: (FSEventStreamRef, DispatchQueue) -> Void
    let start: (FSEventStreamRef) -> Bool
    let stop: (FSEventStreamRef) -> Void
    let invalidate: (FSEventStreamRef) -> Void
    let release: (FSEventStreamRef) -> Void

    static let system = FSEventStreamFunctions(
        create: { callback, context, paths, since, latency, flags in
            FSEventStreamCreate(nil, callback, context, paths, since, latency, flags)
        },
        setDispatchQueue: { FSEventStreamSetDispatchQueue($0, $1) },
        start: { FSEventStreamStart($0) },
        stop: { FSEventStreamStop($0) },
        invalidate: { FSEventStreamInvalidate($0) },
        release: { FSEventStreamRelease($0) }
    )
}

final class SystemFileEventStream: FileEventStreaming, @unchecked Sendable {
    private final class CallbackBox {
        let onEvents: @Sendable () -> Void
        init(onEvents: @escaping @Sendable () -> Void) { self.onEvents = onEvents }
    }

    private static let callback: FSEventStreamCallback = { _, context, _, _, _, _ in
        handleEvents(context: context)
    }

    static func handleEvents(context: UnsafeMutableRawPointer?) {
        guard let context else { return }
        Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue().onEvents()
    }

    private var stream: FSEventStreamRef?
    private var callbackContext: UnsafeMutableRawPointer?
    private var isStarted = false
    private let functions: FSEventStreamFunctions

    init(functions: FSEventStreamFunctions = .system) { self.functions = functions }

    @discardableResult
    func start(paths: [String], onEvents: @escaping @Sendable () -> Void) -> Bool {
        stop()
        guard !paths.isEmpty else { return false }
        let contextPointer = Unmanaged.passRetained(CallbackBox(onEvents: onEvents)).toOpaque()
        var context = FSEventStreamContext(version: 0, info: contextPointer, retain: nil, release: nil, copyDescription: nil)
        guard let created = functions.create(
            Self.callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else {
            Unmanaged<CallbackBox>.fromOpaque(contextPointer).release()
            return false
        }
        stream = created
        callbackContext = contextPointer
        functions.setDispatchQueue(created, DispatchQueue.main)
        guard functions.start(created) else {
            stop()
            return false
        }
        isStarted = true
        return true
    }

    func stop() {
        if let stream {
            if isStarted { functions.stop(stream) }
            functions.invalidate(stream)
            functions.release(stream)
            self.stream = nil
        }
        isStarted = false
        if let callbackContext {
            Unmanaged<CallbackBox>.fromOpaque(callbackContext).release()
            self.callbackContext = nil
        }
    }

    deinit { stop() }
}

@MainActor
public final class FileWatcher {
    private let backend: FileEventStreaming
    private let scheduler: Scheduler
    private let debounceInterval: TimeInterval
    private var onChange: (@MainActor @Sendable () -> Void)?
    private var isStarted = false
    private var generation = 0

    public convenience init(debounceInterval: TimeInterval = 2.0) {
        self.init(debounceInterval: debounceInterval, backend: SystemFileEventStream(), scheduler: DispatchQueueScheduler())
    }

    init(debounceInterval: TimeInterval = 2.0, backend: FileEventStreaming, scheduler: Scheduler) {
        self.debounceInterval = debounceInterval
        self.backend = backend
        self.scheduler = scheduler
    }

    @discardableResult
    public func start(paths: [String], onChange: @escaping @MainActor @Sendable () -> Void) -> Bool {
        stop()
        guard !paths.isEmpty else { return false }
        generation &+= 1
        let activeGeneration = generation
        self.onChange = onChange
        guard backend.start(paths: paths, onEvents: { [weak self] in
            Task { @MainActor in
                self?.receiveEvents(generation: activeGeneration)
            }
        }) else {
            self.onChange = nil
            generation &+= 1
            return false
        }
        isStarted = true
        return true
    }

    private func receiveEvents(generation: Int) {
        guard generation == self.generation, isStarted else { return }
        scheduler.cancelPending()
        scheduler.schedule(after: debounceInterval) { [weak self] in
            guard let self,
                  self.generation == generation,
                  self.isStarted else { return }
            self.onChange?()
        }
    }

    public func stop() {
        generation &+= 1
        scheduler.cancelPending()
        let shouldStopBackend = isStarted
        isStarted = false
        onChange = nil
        if shouldStopBackend { backend.stop() }
    }

    deinit {
        if isStarted { backend.stop() }
    }
}
#endif
