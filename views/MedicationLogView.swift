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
            VStack(alignment: .leading, spacing: 0) {
                header

                if model.loadError != nil {
                    loadFailure.padding(.top, Spacing.lg)
                } else if model.hasSchedule {
                    sectionLabel("Today\u{2019}s doses").padding(.top, Spacing.lg)
                    doseList
                    nextDoseSummary
                } else {
                    emptySchedule.padding(.top, Spacing.lg)
                }

                if !model.unscheduledDoses.isEmpty {
                    sectionLabel("Extra doses today").padding(.top, Spacing.lg)
                    unscheduledList
                }

                if let error = model.actionError {
                    errorBanner(error).padding(.top, Spacing.md)
                }

                extraDoseButton.padding(.top, Spacing.lg)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, Spacing.lg)
        }
        .background { Rectangle().fill(.pageGround).ignoresSafeArea() }
        .onAppear { model.load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Log medication")
                .fontWeight(.medium)
                .foregroundStyle(Color.textDark)
            Text(model.day, format: .dateTime.weekday(.wide).day().month(.wide))
                .fontWeight(.regular)
                .foregroundStyle(Color.primaryColor)
        }
        .font(.displayMedium)
        .padding(.top, Spacing.sm)
    }

    // MARK: Doses

    private var doseList: some View {
        listCard {
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { separator }
                DoseRowView(
                    row: row,
                    onTake: { model.markTaken(row) },
                    onSkip: { model.markSkipped(row) },
                    onClear: { model.clear(row) }
                )
            }
        }
    }

    @ViewBuilder
    private var nextDoseSummary: some View {
        Text(nextDoseLine)
            .font(.subheadline)
            .foregroundStyle(Color.textQuiet)
            .padding(.top, Spacing.sm)
            .padding(.horizontal, Spacing.xxs)
    }

    private var nextDoseLine: String {
        guard let next = model.nextDose else { return "Every dose today has been recorded." }
        return "Your next dose is at \(next.scheduledDate.formatted(date: .omitted, time: .shortened))."
    }

    private var unscheduledList: some View {
        listCard {
            ForEach(Array(model.unscheduledDoses.enumerated()), id: \.element.objectID) { index, log in
                if index > 0 { separator }
                HStack(spacing: Spacing.sm + 2) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 20, weight: .regular))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(Color.primaryColor)
                    Text(log.takenDate.formatted(date: .omitted, time: .shortened))
                        .font(.body)
                        .foregroundStyle(Color.textDark)
                    Spacer(minLength: Spacing.xs)
                    Button("Undo") { model.clearUnscheduled(log) }
                        .font(.subheadline)
                        .foregroundStyle(Color.primaryColor)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(
                            "Remove the extra dose at \(log.takenDate.formatted(date: .omitted, time: .shortened))"
                        )
                }
                .buttonStyle(.plain)
                .frame(minHeight: 60)
            }
        }
    }

    // MARK: Standing states

    // A failed read leaves no rows, which looks exactly like a patient who never set a
    // schedule. Saying so keeps the empty state from telling them to enter one again.
    private var loadFailure: some View {
        noticeCard {
            Text("Couldn\u{2019}t read today\u{2019}s doses.")
                .font(.body)
                .foregroundStyle(Color.textDark)
        }
    }

    private var emptySchedule: some View {
        noticeCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("No dose times set")
                    .font(.subheading)
                    .foregroundStyle(Color.textDark)
                Text("Add your dose times")
                    .font(.body)
                    .foregroundStyle(Color.textQuiet)
                NavigationLink("Set dose times") { OnboardingMeds() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primaryColor)
                    .padding(.top, Spacing.xxs)
            }
        }
    }

    private func errorBanner(_ error: Error) -> some View {
        noticeCard {
            Text(Self.message(for: error))
                .font(.footnote)
                .foregroundStyle(Color.textDark)
        }
    }

    private var extraDoseButton: some View {
        Button {
            model.logUnscheduledDose()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.primaryColor)
                Text("Log an extra dose")
            }
        }
        .buttonStyle(.softCapsule)
    }

    // MARK: Containers

    private func listCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 18)
            .background(
                Color.cardSurface,
                in: RoundedRectangle(cornerRadius: Radius.primary, style: .continuous)
            )
    }

    private func noticeCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                Color.cardSurface,
                in: RoundedRectangle(cornerRadius: Radius.primary, style: .continuous)
            )
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .sectionLabelStyle()
            .foregroundStyle(Color.primaryColor)
            .padding(.horizontal, Spacing.xxs)
            .padding(.bottom, Spacing.xs + 2)
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
        HStack(spacing: Spacing.sm + 2) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .frame(width: 26, height: 26)
                .foregroundStyle(Color.primaryColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.scheduledDate.formatted(date: .omitted, time: .shortened))
                    .font(.body)
                    .foregroundStyle(Color.textDark)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color.textQuiet)
                }
            }

            Spacer(minLength: Spacing.xs)

            if row.isRecorded {
                Button("Undo", action: onClear)
                    .font(.subheadline)
                    .foregroundStyle(Color.primaryColor)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Undo the \(timeForVoice) dose")
            } else {
                Button(action: onSkip) {
                    Text("Did not take")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textDark)
                        .padding(.horizontal, Spacing.sm)
                        .frame(minHeight: 44)
                        .background(Color.buttonSoft, in: Capsule(style: .continuous))
                }
                .accessibilityLabel("Mark the \(timeForVoice) dose as not taken")

                Button(action: onTake) {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textLight)
                        .frame(width: 44, height: 44)
                        .background(Color.primaryColor, in: Circle())
                }
                .accessibilityLabel("Log the \(timeForVoice) dose as taken")
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 60)
        .padding(.vertical, Spacing.xs)
    }

    private var icon: String {
        switch row.state {
        case .pending: return "drop"
        case .taken:   return "drop.fill"
        case .skipped: return "drop.triangle"
        }
    }

    
    private var detail: String? {
        switch row.state {
        case .pending:
            return dosage
        case .taken(let at):
            let taken = "taken at \(at.formatted(date: .omitted, time: .shortened))"
            return [dosage, taken].compactMap { $0 }.joined(separator: " \u{00B7} ")
        case .skipped:
            return [dosage, "not taken"].compactMap { $0 }.joined(separator: " \u{00B7} ")
        }
    }

    private var dosage: String? {
        guard row.dosageMg > 0 else { return nil }
        return "\(row.dosageMg.formatted(.number.precision(.fractionLength(0...2)))) mg"
    }

    private var timeForVoice: String {
        row.scheduledDate.formatted(date: .omitted, time: .shortened)
    }
}

#Preview {
    NavigationStack {
        MedicationLogView(model: MedicationDayModel(context: PersistenceController.preview.container.viewContext))
    }
}
