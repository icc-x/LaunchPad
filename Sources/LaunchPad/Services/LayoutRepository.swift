import Foundation
import LaunchPadProtocols

protocol LayoutRepositoryProtocol: Sendable {
    func load() async throws -> PersistedLayoutSnapshot
    func apply(_ intent: LayoutDropIntent, pageCapacity: Int) async throws
    func renameFolder(_ item: PageItem, newTitle: String) async throws
}

/// Serializes layout reads and mutations on its actor executor.
actor LayoutRepository: LayoutRepositoryProtocol {
    private let reader: any LayoutReading
    private let mutator: any LayoutMutating
    private let writer: any ItemWriting

    init(
        reader: any LayoutReading,
        mutator: any LayoutMutating,
        writer: any ItemWriting
    ) {
        self.reader = reader
        self.mutator = mutator
        self.writer = writer
    }

    func load() async throws -> PersistedLayoutSnapshot {
        try reader.persistedLayoutSnapshot()
    }

    func apply(_ intent: LayoutDropIntent, pageCapacity: Int) async throws {
        try mutator.apply(intent, pageCapacity: pageCapacity)
    }

    func renameFolder(_ item: PageItem, newTitle: String) async throws {
        var group = item.group ?? GroupInfo(id: item.id, title: newTitle)
        group.title = newTitle
        try writer.updateItem(PageItem(
            id: item.id,
            uuid: item.uuid,
            type: item.type,
            ordering: item.ordering,
            parentId: item.parentId,
            app: item.app,
            group: group
        ))
    }
}
