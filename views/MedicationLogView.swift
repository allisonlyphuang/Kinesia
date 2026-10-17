import CoreData
import SwiftUI

struct MedicationLogView: View {
    @Environment(\.managedObjectContext) private var context
    @StateObject private var model: MedicationDayModel

    init(model: MedicationDayModel? = nil) {
        let resolved = model ?? MedicationDayModel(context: PersistenceController.shared.container.viewContext)
        _model = StateObject(wrappedValue: resolved)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header

                if model.hasSchedule {
                    doseList
                    nextDoseSummary
                } else {
                    emptySchedule
                }

                if !model.unscheduledDoses.isEmpty {
                    unscheduledSection
                }

                if let error = model.actionError {
                    errorBanner(error)
                }

                extraDoseButton
            }
            .padding(Spacing.lg)
        }
        .background(Color.bgPrimaryColor.ignoresSafeArea())
        .onAppear { model.load() }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Log medication")
                .font(.displayLarge)
                .foregroundStyle(Color.primaryColor)
            Text(model.day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.heading)
                .foregroundStyle(Color.textMedium)
        }
    }

    private var doseList: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider().padding(.horizontal, Spacing.md)
                }
                DoseRowView(
                    row: row,
                    onTake: { model.markTaken(row) },
                    onSkip: { model.markSkipped(row) },
                    onClear: { model.clear(row) }
                )
            }
        }
        .background {
            RoundedRectangle(cornerRadius: Radius.primary, style: .continuous)
                .fill(.white)
                .stroke(Color.secondaryColor, lineWidth: 2)
        }
    }

    @ViewBuilder
    private var nextDoseSummary: some View {
        if let next = model.nextDose {
            Text("Your next dose is at \(next.scheduledDate.formatted(date: .omitted, time: .shortened)).")
                .font(.heading)
                .foregroundStyle(Color.primaryColor)
        } else {
            Text("Every dose today has been recorded.")
                .font(.heading)
                .foregroundStyle(Color.primaryColor)
        }
    }

    private var emptySchedule: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("No dose times set")
                .font(.subheading)
                .foregroundStyle(Color.textDark)
            Text("Add your dose times")
                .font(.body)
                .foregroundStyle(Color.textMedium)
            NavigationLink("Set dose times") { OnboardingMeds() }
                .font(.button)
                .foregroundStyle(Color.accentBlue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Radius.primary, style: .continuous)
                .fill(Color.bgSecondaryColor)
        }
    }

    private var unscheduledSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Extra doses today")
                .font(.subheading)
                .foregroundStyle(Color.textDark)
            ForEach(model.unscheduledDoses, id: \.objectID) { log in
                Text(log.takenDate.formatted(date: .omitted, time: .shortened))
                    .font(.body)
                    .foregroundStyle(Color.textMedium)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var extraDoseButton: some View {
        Button {
            model.logUnscheduledDose()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus")
                Text("Log an extra dose")
            }
            .font(.button)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background {
                Capsule(style: .continuous).fill(Color.primaryColor)
            }
        }
        .buttonStyle(.plain)
    }

    private func errorBanner(_ error: Error) -> some View {
        Text(Self.message(for: error))
            .font(.label)
            .foregroundStyle(Color.textDark)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.sm)
            .background {
                RoundedRectangle(cornerRadius: Radius.primary, style: .continuous)
                    .fill(Color.bgSecondaryColor)
            }
    }

    static func message(for error: Error) -> String {
        switch error {
        case MedicationStoreError.doseAlreadyLogged:
            return "That dose is already recorded for today."
        case MedicationStoreError.scheduleInactive:
            return "That dose time is no longer on your schedule."
        case MedicationStoreError.unresolvableScheduledTime:
            return "That time does not exist on this day because the clocks changed."
        default:
            return "Failed to save, try again."
        }
    }
}

private struct DoseRowView: View {
    let row: MedicationDayModel.Row
    let onTake: () -> Void
    let onSkip: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .imageScale(.large)
                .foregroundStyle(Color.primaryColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.scheduledDate.formatted(date: .omitted, time: .shortened))
                    .font(.heading)
                    .foregroundStyle(Color.primaryColor)
                Text(detail)
                    .font(.label)
                    .foregroundStyle(Color.textMedium)
            }

            Spacer(minLength: Spacing.xs)

            if row.isRecorded {
                Button("Undo", action: onClear)
                    .font(.label)
                    .foregroundStyle(Color.accentBlue)
            } else {
                Button(action: onSkip) {
                    Text("Skipped")
                        .font(.label)
                        .foregroundStyle(Color.textMedium)
                }
                Button(action: onTake) {
                    Image(systemName: "checkmark.circle")
                        .imageScale(.large)
                        .foregroundStyle(Color.primaryColor)
                }
                .accessibilityLabel("Log the \(row.scheduledDate.formatted(date: .omitted, time: .shortened)) dose as taken")
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 60)
        .padding(Spacing.md)
    }

    private var icon: String {
        switch row.state {
        case .pending: return "drop"
        case .taken:   return "drop.fill"
        case .skipped: return "drop.triangle"
        }
    }

    private var detail: String {
        switch row.state {
        case .pending:
            return row.label ?? "Not recorded yet"
        case .taken(let at):
            return "Taken at \(at.formatted(date: .omitted, time: .shortened))"
        case .skipped:
            return "Skipped"
        }
    }
}

#Preview {
    MedicationLogView(model: MedicationDayModel(context: PersistenceController.preview.container.viewContext))
}
