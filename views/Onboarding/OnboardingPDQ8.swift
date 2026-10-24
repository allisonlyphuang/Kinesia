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
        VStack(alignment: .leading, spacing: 0) {
            progress.padding(.top, Spacing.sm)

            Text("In the last month")
                .sectionLabelStyle()
                .foregroundStyle(Color.primaryColor)
                .padding(.top, Spacing.lg)
                .padding(.horizontal, Spacing.xxs)

            Text(model.currentItem.prompt)
                .font(.displayMedium)
                .fontWeight(.medium)
                .foregroundStyle(Color.textDark)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Spacing.xs)

            ScrollView {
                VStack(spacing: Spacing.sm - 2) {
                    ForEach(PDQ8Response.allCases) { response in
                        ResponseRow(
                            response: response,
                            isSelected: model.currentResponse == response,
                            action: { model.select(response) }
                        )
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
            .scrollBounceBehavior(.basedOnSize)
            .padding(.top, Spacing.md)

            if model.saveError != nil {
                Text("That did not save. Try again.")
                    .font(.footnote)
                    .foregroundStyle(Color.textDark)
                    .padding(.top, Spacing.xs)
            }

            navigation.padding(.top, Spacing.md)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { Rectangle().fill(.pageGround).ignoresSafeArea() }
        // The system back button draws a white capsule on the cream ground, so it is
        // replaced with a plain chevron.
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primaryColor)
                }
                .accessibilityLabel("Back to your dose times")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var progress: some View {
        HStack(spacing: Spacing.xs - 2) {
            ForEach(model.items) { item in
                Capsule(style: .continuous)
                    .fill(model.response(for: item) == nil ? Color.hairline : Color.primaryColor)
                    .frame(height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Question \(model.currentIndex + 1) of \(model.items.count)")
    }

    private var navigation: some View {
        HStack(spacing: Spacing.sm - 2) {
            if model.currentIndex > 0 {
                Button("Back") { model.goBack() }
                    .buttonStyle(.softCapsule)
                    .frame(width: 118)
            }

            Button(model.isLastItem ? "Finish" : "Next") {
                if model.isLastItem {
                    if model.submit() { onFinish?() ?? dismiss() }
                } else {
                    model.advance()
                }
            }
            .buttonStyle(.primaryCapsule)
            .disabled(!canContinue)
        }
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
                    .font(.body)
                    .fontWeight(isSelected ? .medium : .regular)
                    .foregroundStyle(isSelected ? Color.textLight : Color.textDark)
                Spacer(minLength: Spacing.xs)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textLight)
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 60)
            .background(
                isSelected ? Color.primaryColor : Color.buttonSoft,
                in: RoundedRectangle(cornerRadius: Radius.primary, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    OnboardingPDQ8(model: PDQ8Model(context: PersistenceController.preview.container.viewContext))
}
