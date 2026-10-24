import CoreData
import Foundation

nonisolated enum MedicationStoreError: Error, Equatable {
    case invalidWallClockTimestamp
    case scheduleInactive
    case unresolvableScheduledTime
    case doseAlreadyLogged(dayStart: Double)
}

struct MedicationStore {

    // MARK: Schedule

    @discardableResult
    static func replaceSchedule(
        with slots: [MedicationScheduleSlot],
        in context: NSManagedObjectContext
    ) throws -> [MedicationSchedule] {
        try MedicationSchedulePlan.validate(slots)

        let existing = try allSchedules(in: context)
        let ordered = MedicationSchedulePlan.ordered(slots)

        for schedule in existing where schedule.isActive {
            schedule.isActive = false
        }

        var created: [MedicationSchedule] = []
        created.reserveCapacity(ordered.count)
        for (index, slot) in ordered.enumerated() {
            let schedule = MedicationSchedule(context: context)
            // A fresh id, not slot.id. The slots come from the screen, which loaded them
            // from the rows being replaced, and those rows are deactivated rather than
            // deleted. Reusing the id puts two live rows under the uniqueness constraint
            // on MedicationSchedule.id and the save throws, so only the first save worked.
            schedule.id = UUID()
            schedule.dosageMg = slot.dosageMg
            schedule.hour = Int16(slot.hour)
            schedule.minute = Int16(slot.minute)
            schedule.sortIndex = Int16(index)
            schedule.isActive = true
            created.append(schedule)
        }

        try commit(context)
        return created
    }

    // active schedule in time of day order
    static func activeSchedule(in context: NSManagedObjectContext) throws -> [MedicationSchedule] {
        let request = MedicationSchedule.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == YES")
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(MedicationSchedule.sortIndex), ascending: true)
        ]
        return try context.fetch(request)
    }

    static func allSchedules(in context: NSManagedObjectContext) throws -> [MedicationSchedule] {
        let request = MedicationSchedule.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(MedicationSchedule.sortIndex), ascending: true)
        ]
        return try context.fetch(request)
    }

    // MARK: Logging

    @discardableResult
    static func logDose(
        schedule: MedicationSchedule,
        takenAt: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws -> MedicationLog {
        guard schedule.isActive else {
            throw MedicationStoreError.scheduleInactive
        }
        guard let scheduledDate = nearestScheduledDate(for: schedule, to: takenAt, calendar: calendar) else {
            throw MedicationStoreError.unresolvableScheduledTime
        }
        return try insert(
            schedule: schedule,
            timestamp: takenAt,
            scheduledDate: scheduledDate,
            wasSkipped: false,
            in: context,
            calendar: calendar
        )
    }

    @discardableResult
    static func logSkipped(
        schedule: MedicationSchedule,
        onDayContaining day: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws -> MedicationLog {
        guard schedule.isActive else {
            throw MedicationStoreError.scheduleInactive
        }
        guard let scheduledDate = scheduledDate(for: schedule, onDayContaining: day, calendar: calendar) else {
            throw MedicationStoreError.unresolvableScheduledTime
        }
        return try insert(
            schedule: schedule,
            timestamp: scheduledDate,
            scheduledDate: scheduledDate,
            wasSkipped: true,
            in: context,
            calendar: calendar
        )
    }

    // records unscheduled dose, e.g. rescue dose
    @discardableResult
    static func logUnscheduledDose(
        takenAt: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws -> MedicationLog {
        try insert(
            schedule: nil,
            timestamp: takenAt,
            scheduledDate: nil,
            wasSkipped: false,
            in: context,
            calendar: calendar
        )
    }

    // undo for a dose
    static func delete(_ log: MedicationLog, in context: NSManagedObjectContext) throws {
        context.delete(log)
        try commit(context)
    }

    /// Undo for a slot: removes every log it has on that day, not just the first.
    ///
    /// A build whose fetch predicate never matched could record the same dose more than
    /// once, and deleting one of those leaves the dose still recorded, at a later time.
    static func clearLogs(
        for schedule: MedicationSchedule,
        onDayContaining day: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws {
        let request = MedicationLog.fetchRequest()
        request.predicate = NSPredicate(
            format: "schedule == %@ AND dayStart == %@",
            schedule,
            NSNumber(value: calendar.startOfDay(for: day).timeIntervalSince1970)
        )
        for log in try context.fetch(request) {
            context.delete(log)
        }
        try commit(context)
    }

    // MARK: Reading back

    static func logs(
        onDayContaining day: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws -> [MedicationLog] {
        let request = MedicationLog.fetchRequest()
        // NSNumber, not %f. A %f placeholder is parsed as a 32-bit float, and an epoch
        // second around 1.79e9 needs 31 bits, so the value the predicate compares against
        // can land up to 128 seconds off. On an equality test that means no rows at all.
        request.predicate = NSPredicate(
            format: "dayStart == %@",
            NSNumber(value: calendar.startOfDay(for: day).timeIntervalSince1970)
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(MedicationLog.timestamp), ascending: true)
        ]
        return try context.fetch(request)
    }

    // the log for this schedule slot on this day if the patient has already recorded it
    static func existingLog(
        for schedule: MedicationSchedule,
        onDayStarting dayStart: Double,
        in context: NSManagedObjectContext
    ) throws -> MedicationLog? {
        let request = MedicationLog.fetchRequest()
        request.predicate = NSPredicate(
            format: "schedule == %@ AND dayStart == %@",
            schedule,
            NSNumber(value: dayStart)
        )
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    // MARK: Scheduled-time resolution

    static func scheduledDate(
        for schedule: MedicationSchedule,
        onDayContaining day: Date,
        calendar: Calendar = .current
    ) -> Date? {
        MedicationSchedulePlan.occurrence(of: slot(for: schedule), onDayContaining: day, calendar: calendar)
    }

    static func nearestScheduledDate(
        for schedule: MedicationSchedule,
        to instant: Date,
        calendar: Calendar = .current
    ) -> Date? {
        MedicationSchedulePlan.nearestOccurrence(of: slot(for: schedule), to: instant, calendar: calendar)
    }

    static func slot(for schedule: MedicationSchedule) -> MedicationScheduleSlot {
        MedicationScheduleSlot(
            id: schedule.id ?? UUID(),
            dosageMg: schedule.dosageMg,
            hour: Int(schedule.hour),
            minute: Int(schedule.minute)
        )
    }

    // MARK: Private

    private static func insert(
        schedule: MedicationSchedule?,
        timestamp: Date,
        scheduledDate: Date?,
        wasSkipped: Bool,
        in context: NSManagedObjectContext,
        calendar: Calendar
    ) throws -> MedicationLog {
        let timestampEpoch = timestamp.timeIntervalSince1970
        let scheduledEpoch = scheduledDate?.timeIntervalSince1970 ?? 0

        let dayStart = calendar.startOfDay(for: scheduledDate ?? timestamp).timeIntervalSince1970

        guard timestampEpoch.isFinite, scheduledEpoch.isFinite, dayStart.isFinite else {
            throw MedicationStoreError.invalidWallClockTimestamp
        }

        if let schedule, try existingLog(for: schedule, onDayStarting: dayStart, in: context) != nil {
            throw MedicationStoreError.doseAlreadyLogged(dayStart: dayStart)
        }

        let log = MedicationLog(context: context)
        log.id = UUID()
        log.timestamp = timestampEpoch
        log.scheduledTime = scheduledEpoch
        log.dayStart = dayStart
        log.wasSkipped = wasSkipped
        log.schedule = schedule

        try commit(context)
        return log
    }

    private static func commit(_ context: NSManagedObjectContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

// Read by the nonisolated snapshot initialisers, so these stay off the main actor.
nonisolated extension MedicationLog {

    var scheduledDate: Date? {
        scheduledTime == 0 ? nil : Date(timeIntervalSince1970: scheduledTime)
    }

    var takenDate: Date {
        Date(timeIntervalSince1970: timestamp)
    }

    var delayMinutes: Double? {
        guard let scheduledDate else { return nil }
        return takenDate.timeIntervalSince(scheduledDate) / 60
    }
}
