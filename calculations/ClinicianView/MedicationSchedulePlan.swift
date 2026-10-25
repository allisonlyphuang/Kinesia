import Foundation

// one scheduled dose as a value type
// inputs into `MedicationStore` and turns into `MedicationSchedule` rows
nonisolated struct MedicationScheduleSlot: Equatable, Codable, Identifiable {
    var id: UUID
    var dosageMg: Double
    var hour: Int
    var minute: Int

    init(id: UUID = UUID(), dosageMg: Double = 0, hour: Int, minute: Int) {
        self.id = id
        self.dosageMg = dosageMg
        self.hour = hour
        self.minute = minute
    }

    var minutesIntoDay: Int {
        hour * 60 + minute
    }
}

nonisolated enum MedicationScheduleError: Error, Equatable {
    case noSlots
    case invalidTimeOfDay(hour: Int, minute: Int)
    case duplicateSlot(hour: Int, minute: Int)
    case invalidDosage(Double)
}

nonisolated enum MedicationSchedulePlan {

    static func validate(_ slots: [MedicationScheduleSlot]) throws {
        guard !slots.isEmpty else {
            throw MedicationScheduleError.noSlots // if slots are empty throw noSlots
        }

        for slot in slots {
            guard (0..<24).contains(slot.hour), (0..<60).contains(slot.minute) else {
                throw MedicationScheduleError.invalidTimeOfDay(hour: slot.hour, minute: slot.minute)
            } // if hours and minutes of day not within real range throw invalidTimeOfDay
            guard slot.dosageMg.isFinite, slot.dosageMg >= 0 else {
                throw MedicationScheduleError.invalidDosage(slot.dosageMg)
            } // if dosage not finite throw invalidDosage
        }

    
        var seen: Set<Int> = []
        for slot in slots.sorted(by: { $0.minutesIntoDay < $1.minutesIntoDay }) {
            guard seen.insert(slot.minutesIntoDay).inserted else {
                throw MedicationScheduleError.duplicateSlot(hour: slot.hour, minute: slot.minute)
            }
        }
    }

    static func ordered(_ slots: [MedicationScheduleSlot]) -> [MedicationScheduleSlot] {
        slots.sorted { $0.minutesIntoDay < $1.minutesIntoDay }
    }

    static func occurrence(
        of slot: MedicationScheduleSlot,
        onDayContaining instant: Date,
        calendar: Calendar = .current
    ) -> Date? {
        calendar.date(
            bySettingHour: slot.hour,
            minute: slot.minute,
            second: 0,
            of: calendar.startOfDay(for: instant),
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    static func nearestOccurrence(
        of slot: MedicationScheduleSlot,
        to instant: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let day = calendar.startOfDay(for: instant)
        let candidates = [-1, 0, 1].compactMap { offset -> Date? in
            guard let shifted = calendar.date(byAdding: .day, value: offset, to: day) else {
                return nil
            }
            return occurrence(of: slot, onDayContaining: shifted, calendar: calendar)
        }

        return candidates.min { first, second in
            abs(first.timeIntervalSince(instant)) < abs(second.timeIntervalSince(instant))
        }
    }
}
