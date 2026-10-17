import Combine
import CoreData
import Foundation

@MainActor
final class MedicationScheduleModel: ObservableObject {

    @Published private(set) var slots: [MedicationScheduleSlot] = []
    @Published private(set) var validationMessage: String?
    @Published private(set) var saveError: Error?
    @Published private(set) var didSave = false

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    var canSave: Bool {
        !slots.isEmpty && validationMessage == nil
    }

    // loads active schedule for editing or offer starting point based on most common levodopa dosing and schedule
    func load() {
        do {
            let existing = try MedicationStore.activeSchedule(in: context)
            if existing.isEmpty {
                slots = Self.defaultSlots
            } else {
                slots = existing.map(MedicationStore.slot(for:))
            }
        } catch {
            saveError = error
            slots = Self.defaultSlots
        }
        revalidate()
    }

    static let defaultSlots: [MedicationScheduleSlot] = [
        MedicationScheduleSlot(hour: 8, minute: 0),
        MedicationScheduleSlot(hour: 13, minute: 0),
        MedicationScheduleSlot(hour: 18, minute: 0)
    ]

    func add(hour: Int = 12, minute: Int = 0) {
        slots.append(MedicationScheduleSlot(hour: hour, minute: minute))
        reorder()
    }

    func remove(_ slot: MedicationScheduleSlot) {
        slots.removeAll { $0.id == slot.id }
        revalidate()
    }

    func update(_ slot: MedicationScheduleSlot, hour: Int, minute: Int) {
        guard let index = slots.firstIndex(where: { $0.id == slot.id }) else { return }
        slots[index].hour = hour
        slots[index].minute = minute
        reorder()
    }

    func update(_ slot: MedicationScheduleSlot, dosageMg: Double) {
        guard let index = slots.firstIndex(where: { $0.id == slot.id }) else { return }
        slots[index].dosageMg = dosageMg
        revalidate()
    }

    func update(_ slot: MedicationScheduleSlot, label: String?) {
        guard let index = slots.firstIndex(where: { $0.id == slot.id }) else { return }
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        slots[index].label = (trimmed?.isEmpty ?? true) ? nil : trimmed
        revalidate()
    }

    @discardableResult
    func save() -> Bool {
        revalidate()
        guard validationMessage == nil else { return false }
        do {
            try MedicationStore.replaceSchedule(with: slots, in: context)
            saveError = nil
            didSave = true
            return true
        } catch {
            saveError = error
            didSave = false
            return false
        }
    }

    private func reorder() {
        slots = MedicationSchedulePlan.ordered(slots)
        revalidate()
    }


    private func revalidate() {
        do {
            try MedicationSchedulePlan.validate(slots)
            validationMessage = nil
        } catch MedicationScheduleError.noSlots {
            validationMessage = "Add at least one time."
        } catch MedicationScheduleError.duplicateSlot {
            validationMessage = "Two doses are set to the same time."
        } catch MedicationScheduleError.invalidTimeOfDay {
            validationMessage = "One of the times is not a real time of day."
        } catch MedicationScheduleError.invalidDosage {
            validationMessage = "Enter an amount of zero or more."
        } catch {
            validationMessage = "Check the times and try again."
        }
    }
}
