import CoreData
import SwiftUI

struct OnboardingPDQ8: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: PDQ8Model

    var onFinish: (() -> Void)?

    init(model: PDQ8Model? = nil, onFinish: (() -> Void)? = nil) {
        let resolved = model ?? PDQ8Model(context: PersistenceController.shared.container.viewContext)
        _model = StateObject(wrappedValue: resolved)
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            progress

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("In the last month")
                    .font(.heading)
                    .foregroundStyle(Color.textMedium)
                Text(model.currentItem.prompt)
                    .font(.displayMedium)
                    .foregroundStyle(Color.textDark)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(spacing: Spacing.sm) {
                    ForEach(PDQ8Response.allCases) { response in
                        ResponseRow(
                            response: response,
                            isSelected: model.currentResponse == response,
                            action: { model.select(response) }
                        )
                    }
                }
            }

            if model.saveError != nil {
                Text("That did not save. Try again.")
                    .font(.label)
                    .foregroundStyle(Color.textDark)
            }

            navigation
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bgPrimaryColor.ignoresSafeArea())
    }

    private var progress: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(model.items) { item in
                Capsule(style: .continuous)
                    .fill(model.response(for: item) == nil ? Color.clear : Color.primaryColor)
                    .stroke(Color.primaryColor, lineWidth: 1)
                    .frame(height: 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Question \(model.currentIndex + 1) of \(model.items.count)")
    }

    private var navigation: some View {
        HStack(spacing: Spacing.sm) {
            if model.currentIndex > 0 {
                Button("Back") { model.goBack() }
                    .font(.button)
                    .foregroundStyle(Color.primaryColor)
                    .frame(height: 64)
                    .padding(.horizontal, Spacing.lg)
                    .background {
                        Capsule(style: .continuous).stroke(Color.secondaryColor, lineWidth: 2)
                    }
            }

            Button {
                if model.isLastItem {
                    if model.submit() { onFinish?() ?? dismiss() }
                } else {
                    model.advance()
                }
            } label: {
                Text(model.isLastItem ? "Finish" : "Next")
                    .font(.button)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background {
                        Capsule(style: .continuous)
                            .fill(canContinue ? Color.primaryColor : Color.secondaryColor)
                    }
            }
            .disabled(!canContinue)
        }
        .buttonStyle(.plain)
    }

    private var canContinue: Bool {
        model.isLastItem ? model.isComplete : model.currentResponse != nil
    }
}

private struct ResponseRow: View {
    let response: PDQ8Response
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(response.label)
                    .font(.heading)
                    .foregroundStyle(isSelected ? .white : Color.primaryColor)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.white)
                        .font(.system(.body, weight: .bold))
                }
            }
            .padding(.horizontal, Spacing.md)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background {
                RoundedRectangle(cornerRadius: Radius.primary, style: .continuous)
                    .fill(isSelected ? Color.primaryColor : Color.clear)
                    .stroke(Color.primaryColor, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    OnboardingPDQ8(model: PDQ8Model(context: PersistenceController.preview.container.viewContext))
}
