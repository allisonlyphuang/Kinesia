import Combine
import CoreData
import Foundation

/// What the patient has recorded for one scheduled dose on one day.
nonisolated enum DoseState: Equatable {
    case pending
    case taken(at: Date)
    case skipped
}

@MainActor
final class MedicationDayModel: ObservableObject {

    struct Row: Identifiable {
        let id: UUID
        let schedule: MedicationSchedule
        let label: String?
        let scheduledDate: Date
        let state: DoseState
        let log: MedicationLog?

        var isRecorded: Bool { state != .pending }
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var unscheduledDoses: [MedicationLog] = []
    @Published private(set) var loadError: Error?
    @Published private(set) var actionError: Error?
    @Published private(set) var day: Date

    private let context: NSManagedObjectContext
    private let calendar: Calendar
    private let now: () -> Date

    init(
        context: NSManagedObjectContext,
        day: Date? = nil,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.calendar = calendar
        self.now = now
        self.day = day ?? now()
    }

    var hasSchedule: Bool { !rows.isEmpty }

    var nextDose: Row? {
        rows.first { $0.state == .pending }
    } // = nil when everything is recorded

    func show(day: Date) {
        self.day = day
        load()
    }

    func load() {
        do {
            let schedules = try MedicationStore.activeSchedule(in: context)
            let logs = try MedicationStore.logs(onDayContaining: day, in: context, calendar: calendar)
            let logsBySchedule = Dictionary(
                logs.compactMap { log in log.schedule.map { ($0.objectID, log) } },
                uniquingKeysWith: { first, _ in first }
            )

            rows = schedules.compactMap { schedule in
                guard let scheduledDate = MedicationStore.scheduledDate(
                    for: schedule,
                    onDayContaining: day,
                    calendar: calendar
                ) else {
           
                    // spring daylight savings = slot's clock time does not exist on this day
                    return nil
                }

                let log = logsBySchedule[schedule.objectID]
                return Row(
                    id: schedule.id ?? UUID(),
                    schedule: schedule,
                    label: schedule.label,
                    scheduledDate: scheduledDate,
                    state: state(for: log),
                    log: log
                )
            }

            unscheduledDoses = logs.filter { $0.schedule == nil }
            loadError = nil
        } catch {
            loadError = error
            rows = []
            unscheduledDoses = []
        }
    }

    func markTaken(_ row: Row) {
        perform {
            try MedicationStore.logDose(
                schedule: row.schedule,
                takenAt: self.now(),
                in: self.context,
                calendar: self.calendar
            )
        }
    }

    func markSkipped(_ row: Row) {
        perform {
            try MedicationStore.logSkipped(
                schedule: row.schedule,
                onDayContaining: self.day,
                in: self.context,
                calendar: self.calendar
            )
        }
    }

    func clear(_ row: Row) {
        guard let log = row.log else { return }
        perform {
            try MedicationStore.delete(log, in: self.context)
        }
    }

    func logUnscheduledDose() {
        perform {
            try MedicationStore.logUnscheduledDose(
                takenAt: self.now(),
                in: self.context,
                calendar: self.calendar
            )
        }
    }

    private func state(for log: MedicationLog?) -> DoseState {
        guard let log else { return .pending }
        return log.wasSkipped ? .skipped : .taken(at: log.takenDate)
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            actionError = nil
        } catch {
            actionError = error
        }
        load()
    }
}
