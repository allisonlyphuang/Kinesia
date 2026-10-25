import Combine
import CoreData
import Foundation

// Loads opening and home screen display

final class HomeSummaryModel: ObservableObject {
    @Published private(set) var summary: HomeSummary = .empty
    @Published private(set) var loadFailed = false

    func reload(in context: NSManagedObjectContext, now: Date = Date()) {
        do {
            let sessions = try ReportQuery.allSessions(in: context)
            let slots = try MedicationStore.activeSchedule(in: context).map { MedicationStore.slot(for: $0) }
            summary = HomeSummaryBuilder.make(sessions: sessions, slots: slots, now: now)
            loadFailed = false
        } catch {
            summary = .empty
            loadFailed = true
        }
    }
}
