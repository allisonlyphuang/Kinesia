//
//  PDQ8Store.swift
//  Kinesia
//

import CoreData
import Foundation

nonisolated enum PDQ8StoreError: Error, Equatable {
    case invalidWallClockTimestamp
    case missingItemScores
}

struct PDQ8Store {

    @discardableResult
    static func save(
        score: PDQ8Score,
        completedAt: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws -> PDQ8Log {
        let timestamp = completedAt.timeIntervalSince1970
        let dayStart = calendar.startOfDay(for: completedAt).timeIntervalSince1970
        guard timestamp.isFinite, dayStart.isFinite else {
            throw PDQ8StoreError.invalidWallClockTimestamp
        }

        let payload = try JSONEncoder().encode(score.itemScores)

        let log = PDQ8Log(context: context)
        log.id = UUID()
        log.timestamp = timestamp
        log.dayStart = dayStart
        log.itemScores = payload
        log.rawSum = Int16(score.rawSum)
        log.scoreIndex = score.scoreIndex

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return log
    }

    @discardableResult
    static func save(
        responses: [PDQ8Item: PDQ8Response],
        completedAt: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws -> PDQ8Log {
        try save(
            score: try PDQ8Score.compute(from: responses),
            completedAt: completedAt,
            in: context,
            calendar: calendar
        )
    }

    // MARK: Reading back

    static func fetchLogs(in context: NSManagedObjectContext) throws -> [PDQ8Log] {
        let request = PDQ8Log.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(PDQ8Log.timestamp), ascending: false)]
        return try context.fetch(request)
    }

    static func fetchLogs(
        from start: Date,
        to end: Date,
        in context: NSManagedObjectContext
    ) throws -> [PDQ8Log] {
        let request = PDQ8Log.fetchRequest()
        request.predicate = NSPredicate(
            format: "timestamp >= %f AND timestamp < %f",
            start.timeIntervalSince1970,
            end.timeIntervalSince1970
        )
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(PDQ8Log.timestamp), ascending: true)]
        return try context.fetch(request)
    }

    static func fetchLatest(in context: NSManagedObjectContext) throws -> PDQ8Log? {
        let request = PDQ8Log.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(PDQ8Log.timestamp), ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func hasCompletedQuestionnaire(in context: NSManagedObjectContext) throws -> Bool {
        try context.count(for: PDQ8Log.fetchRequest()) > 0
    }
}

extension PDQ8Log {

    func decodedScore() throws -> PDQ8Score {
        guard let itemScores else {
            throw PDQ8StoreError.missingItemScores
        }
        return try PDQ8Score.compute(itemScores: try JSONDecoder().decode([Int16].self, from: itemScores))
    }

    var completedDate: Date {
        Date(timeIntervalSince1970: timestamp)
    }
}
