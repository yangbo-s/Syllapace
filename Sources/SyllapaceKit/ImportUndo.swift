import Foundation

/// Undo only records still equal to this operation's result; later edits and syncs win.
public struct ImportUndo: Sendable {
    private var oldEvents: [String: AcademicEvent]
    private var changedEvents: [String: AcademicEvent]
    private var oldSources: [String: SourceDocument]
    private var changedSources: [String: SourceDocument]
    public init(before: AppArchive, after: AppArchive) {
        let previousEvents = Dictionary(before.events.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let previousSources = Dictionary(before.sources.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        oldEvents = previousEvents; oldSources = previousSources
        changedEvents = Dictionary(after.events.filter { previousEvents[$0.id] != $0 }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        changedSources = Dictionary(after.sources.filter { previousSources[$0.id] != $0 }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    public func restoreEvents(in current: [AcademicEvent]) -> [AcademicEvent] {
        current.compactMap { changedEvents[$0.id] == $0 ? oldEvents[$0.id] : $0 }
    }
    public func restoreSources(in current: [SourceDocument], referencedSourceIDs: Set<String> = []) -> [SourceDocument] {
        current.compactMap { source in
            guard changedSources[source.id] == source, !referencedSourceIDs.contains(source.id) || oldSources[source.id] != nil else { return source }
            return oldSources[source.id]
        }
    }
}
