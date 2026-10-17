import CoreData
import Foundation

nonisolated enum MedicationStoreError: Error, Equatable {
    case invalidWallClockTimestamp
    case scheduleInactive
    case unresolvableScheduledTime
    case doseAlreadyLogged(dayStart: Double)
}

struct MedicationStore {

    static let manualSource = "manual"

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
            schedule.id = slot.id
            schedule.label = slot.label
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
        source: String = manualSource,
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
            source: source,
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
            source: manualSource,
            in: context,
            calendar: calendar
        )
    }

    // records unscheduled dose, e.g. rescue dose
    @discardableResult
    static func logUnscheduledDose(
        takenAt: Date,
        source: String = manualSource,
        in context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws -> MedicationLog {
        try insert(
            schedule: nil,
            timestamp: takenAt,
            scheduledDate: nil,
            wasSkipped: false,
            source: source,
            in: context,
            calendar: calendar
        )
    }

    // undo for a dose
    static func delete(_ log: MedicationLog, in context: NSManagedObjectContext) throws {
        context.delete(log)
        try commit(context)
    }

    // MARK: Reading back

    static func logs(
        from start: Date,
        to end: Date,
        in context: NSManagedObjectContext
    ) throws -> [MedicationLog] {
        let request = MedicationLog.fetchRequest()
        request.predicate = NSPredicate(
            format: "timestamp >= %f AND timestamp < %f",
            start.timeIntervalSince1970,
            end.timeIntervalSince1970
        )
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(MedicationLog.timestamp), ascending: true)
        ]
        return try context.fetch(request)
    }

  
    static func logs(
        onDayContaining day: Date,
        in context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) throws -> [MedicationLog] {
        let request = MedicationLog.fetchRequest()
        request.predicate = NSPredicate(
            format: "dayStart == %f",
            calendar.startOfDay(for: day).timeIntervalSince1970
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
            format: "schedule == %@ AND dayStart == %f",
            schedule,
            dayStart
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
            label: schedule.label,
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
        source: String,
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
        log.source = source
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

extension MedicationLog {

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
