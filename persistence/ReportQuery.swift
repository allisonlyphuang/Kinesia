import CoreData
import Foundation

// value types needed for one window
nonisolated struct ReportData: Sendable {
    let window: ReportWindow
    let sessions: [SessionSnapshot]
    let doses: [DoseSnapshot]
    let questionnaires: [PDQ8Snapshot]
    let history: [SessionSnapshot]
}

nonisolated struct PDQ8Snapshot: Sendable, Equatable, Identifiable {
    let id: UUID
    let completedAt: Date
    let rawSum: Int
    let scoreIndex: Double
}


struct ReportQuery {

    // data for one window + data for baseline
    static func load(
        window: ReportWindow,
        in context: NSManagedObjectContext
    ) throws -> ReportData {
        ReportData(
            window: window,
            sessions: try sessions(from: window.start, to: window.end, in: context),
            doses: try doses(in: window, in: context),
            questionnaires: try questionnaires(in: context),
            history: try allSessions(in: context)
        )
    }

    // MARK: Sessions

    static func sessions(
        from start: Date,
        to end: Date,
        in context: NSManagedObjectContext
    ) throws -> [SessionSnapshot] {
        let request = TestSession.fetchRequest()
        request.predicate = NSPredicate(
            format: "startedAt >= %@ AND startedAt < %@",
            NSNumber(value: start.timeIntervalSince1970),
            NSNumber(value: end.timeIntervalSince1970)
        )
        return try fetchSessions(request, in: context)
    }

    static func allSessions(in context: NSManagedObjectContext) throws -> [SessionSnapshot] {
        try fetchSessions(TestSession.fetchRequest(), in: context)
    }

  
    private static func fetchSessions(
        _ request: NSFetchRequest<TestSession>,
        in context: NSManagedObjectContext
    ) throws -> [SessionSnapshot] {
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(TestSession.startedAt), ascending: true)
        ]
        request.relationshipKeyPathsForPrefetching = [
            #keyPath(TestSession.bradykinesiaResults),
            #keyPath(TestSession.akinesia),
            #keyPath(TestSession.dexterity),
            #keyPath(TestSession.medicationContext)
        ]
        return try context.fetch(request).compactMap(SessionSnapshot.init)
    }

    // MARK: Doses

    // aligned on dayStart
    static func doses(
        in window: ReportWindow,
        in context: NSManagedObjectContext
    ) throws -> [DoseSnapshot] {
        let request = MedicationLog.fetchRequest()
        request.predicate = NSPredicate(
            format: "dayStart >= %@ AND dayStart < %@",
            NSNumber(value: window.startEpoch),
            NSNumber(value: window.endEpoch)
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(MedicationLog.timestamp), ascending: true)
        ]
        request.relationshipKeyPathsForPrefetching = [#keyPath(MedicationLog.schedule)]
        return try context.fetch(request).compactMap(DoseSnapshot.init)
    }

    // MARK: Questionnaires

    static func questionnaires(in context: NSManagedObjectContext) throws -> [PDQ8Snapshot] {
        try PDQ8Store.fetchLogs(in: context)
            .compactMap(PDQ8Snapshot.init)
            .sorted { $0.completedAt < $1.completedAt } // the trend chart plots oldest first
    }
}

nonisolated extension PDQ8Snapshot {
    init?(_ row: PDQ8Log) {
        guard let id = row.id, row.scoreIndex.isFinite else { return nil }
        self.init(
            id: id,
            completedAt: row.completedDate,
            rawSum: Int(row.rawSum),
            scoreIndex: row.scoreIndex
        )
    }
}
