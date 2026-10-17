import CoreData
import SwiftUI

struct OnboardingMeds: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: MedicationScheduleModel

    var onContinue: (() -> Void)?

    init(model: MedicationScheduleModel? = nil, onContinue: (() -> Void)? = nil) {
        let resolved = model ?? MedicationScheduleModel(context: PersistenceController.shared.container.viewContext)
        _model = StateObject(wrappedValue: resolved)
        self.onContinue = onContinue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("When do you take your medication?")
                    .font(.displayLarge)
                    .foregroundStyle(Color.textDark)
                    .fixedSize(horizontal: false, vertical: true)
                Text("You can change this later.")
                    .font(.heading)
                    .foregroundStyle(Color.textMedium)
            }
            .padding(.top, Spacing.md)

            ScrollView {
                VStack(spacing: Spacing.sm) {
                    ForEach(model.slots) { slot in
                        SlotRow(
                            slot: slot,
                            onChange: { hour, minute in model.update(slot, hour: hour, minute: minute) },
                            onRemove: { model.remove(slot) }
                        )
                    }
                    addButton
                }
                .padding(.vertical, Spacing.xs)
            }

            if let message = model.validationMessage {
                Text(message)
                    .font(.label)
                    .foregroundStyle(Color.textDark)
            }
            if model.saveError != nil {
                Text("That did not save. Try again.")
                    .font(.label)
                    .foregroundStyle(Color.textDark)
            }

            continueButton
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bgPrimaryColor.ignoresSafeArea())
        .onAppear { model.load() }
    }

    private var addButton: some View {
        Button {
            model.add()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus")
                Text("Add a time")
            }
            .font(.button)
            .foregroundStyle(Color.primaryColor)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background {
                RoundedRectangle(cornerRadius: Radius.primary, style: .continuous)
                    .stroke(Color.secondaryColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var continueButton: some View {
        Button {
            if model.save() {
                onContinue?() ?? dismiss()
            }
        } label: {
            Text("Continue")
                .font(.button)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background {
                    Capsule(style: .continuous)
                        .fill(model.canSave ? Color.primaryColor : Color.secondaryColor)
                }
        }
        .buttonStyle(.plain)
        .disabled(!model.canSave)
    }
}

private struct SlotRow: View {
    let slot: MedicationScheduleSlot
    let onChange: (Int, Int) -> Void
    let onRemove: () -> Void

    @State private var time: Date = .now

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "drop")
                .imageScale(.large)
                .foregroundStyle(Color.textDark)

            DatePicker(
                "Dose time",
                selection: $time,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .onChange(of: time) { _, newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                onChange(parts.hour ?? slot.hour, parts.minute ?? slot.minute)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .imageScale(.large)
                    .foregroundStyle(Color.secondaryColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove this dose time")
        }
        .padding(Spacing.md)
        .frame(minHeight: 72)
        .background {
            RoundedRectangle(cornerRadius: Radius.primary, style: .continuous)
                .fill(.white)
                .stroke(Color.secondaryColor, lineWidth: 2)
        }
        .onAppear {
            time = Calendar.current.date(
                bySettingHour: slot.hour,
                minute: slot.minute,
                second: 0,
                of: Calendar.current.startOfDay(for: .now)
            ) ?? .now
        }
    }
}

#Preview {
    OnboardingMeds(model: MedicationScheduleModel(context: PersistenceController.preview.container.viewContext))
}
