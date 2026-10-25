import CoreData
import SwiftUI

struct OnboardingMeds: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: MedicationScheduleModel

    var onContinue: (() -> Void)?

    // "Continue" during onboarding, "Save" when the screen is opened from settings
    private let continueTitle: String

    init(
        model: MedicationScheduleModel? = nil,
        continueTitle: String = "Continue",
        onContinue: (() -> Void)? = nil
    ) {
        let resolved = model ?? MedicationScheduleModel(context: PersistenceController.shared.container.viewContext)
        _model = StateObject(wrappedValue: resolved)
        self.continueTitle = continueTitle
        self.onContinue = onContinue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("When do you take your medication?")
                    .font(.displayMedium)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textDark)
                    .fixedSize(horizontal: false, vertical: true)
                Text("You can change this later.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textQuiet)
            }
            .padding(.top, Spacing.sm)

            Text("Times and amounts")
                .sectionLabelStyle()
                .foregroundStyle(Color.primaryColor)
                .padding(.top, Spacing.lg)
                .padding(.horizontal, Spacing.xxs)
                .padding(.bottom, Spacing.xs + 2)

            ScrollView {
                VStack(spacing: Spacing.sm) {
                    slotCard
                    addButton
                }
                .padding(.bottom, Spacing.xs)
            }
            .scrollBounceBehavior(.basedOnSize)

            if let message = model.validationMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Color.textDark)
                    .padding(.top, Spacing.xs)
            }
            if model.saveError != nil {
                Text("That did not save. Try again.")
                    .font(.footnote)
                    .foregroundStyle(Color.textDark)
                    .padding(.top, Spacing.xs)
            }

            continueButton.padding(.top, Spacing.md)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { Rectangle().fill(.pageGround).ignoresSafeArea() }
        .onAppear { model.load() }
    }

    private var slotCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.slots.enumerated()), id: \.element.id) { index, slot in
                if index > 0 {
                    Rectangle()
                        .fill(Color.hairline)
                        .frame(height: 1)
                }
                SlotRow(
                    slot: slot,
                    onChangeTime: { hour, minute in model.update(slot, hour: hour, minute: minute) },
                    onChangeDosage: { model.update(slot, dosageMg: $0) },
                    onRemove: { model.remove(slot) }
                )
            }
        }
        .padding(.horizontal, 18)
        .background(
            Color.cardSurface,
            in: RoundedRectangle(cornerRadius: Radius.primary, style: .continuous)
        )
    }

    private var addButton: some View {
        Button {
            model.add()
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.primaryColor)
                Text("Add a time")
            }
        }
        .buttonStyle(.softCapsule)
    }

    private var continueButton: some View {
        Button(continueTitle) {
            if model.save() {
                onContinue?() ?? dismiss()
            }
        }
        .buttonStyle(.primaryCapsule)
        .disabled(!model.canSave)
    }
}

private struct SlotRow: View {
    let slot: MedicationScheduleSlot
    let onChangeTime: (Int, Int) -> Void
    let onChangeDosage: (Double) -> Void
    let onRemove: () -> Void

    @State private var time: Date = .now
    @State private var dosage: Double = 0

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "drop")
                .font(.system(size: 20, weight: .regular))
                .frame(width: 26, height: 26)
                .foregroundStyle(Color.primaryColor)

            DatePicker("Dose time", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .onChange(of: time) { _, newValue in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    onChangeTime(parts.hour ?? slot.hour, parts.minute ?? slot.minute)
                }

            HStack(spacing: 2) {
                TextField("0", value: $dosage, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.body)
                    .foregroundStyle(Color.textDark)
                    .frame(width: 42)
                    .accessibilityLabel("Dose in milligrams")
                    .onChange(of: dosage) { _, newValue in onChangeDosage(newValue) }
                Text("mg")
                    .font(.footnote)
                    .foregroundStyle(Color.textQuiet)
            }
            .padding(.horizontal, Spacing.sm)
            .frame(minHeight: 44)
            .background(Color.buttonSoft, in: Capsule(style: .continuous))

            Spacer(minLength: Spacing.xxs)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.chevronTint)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove this dose time")
        }
        .frame(minHeight: 60)
        .padding(.vertical, Spacing.xxs)
        .onAppear {
            time = Calendar.current.date(
                bySettingHour: slot.hour,
                minute: slot.minute,
                second: 0,
                of: Calendar.current.startOfDay(for: .now)
            ) ?? .now
            dosage = slot.dosageMg
        }
    }
}

#Preview {
    OnboardingMeds(model: MedicationScheduleModel(context: PersistenceController.preview.container.viewContext))
}
