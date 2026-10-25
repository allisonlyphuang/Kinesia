import CoreData
import SwiftUI

struct OpeningView: View {

    // Variable region/footer changes based on 3 possible states: first time user, returning user, user that has completed everything
    enum Exit {
        case today
        case garden
        case medicine
    }

    @Environment(\.managedObjectContext) private var context
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var model = HomeSummaryModel()
    @State private var showingOnboarding = false

    let onExit: (Exit) -> Void

    var body: some View {
        ZStack {
            background
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: Spacing.lg)
                        lockup
                        Spacer(minLength: Spacing.xl)
                        slot
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.lg)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .task { model.reload(in: context) }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingFlow {
                hasCompletedOnboarding = true
                showingOnboarding = false
                onExit(.today)
            }
        }
    }

    // Constant portion

    private var background: some View {
        GeometryReader { proxy in
            Image("openingBackground")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay(.openingScrim)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var lockup: some View {
        VStack(spacing: Spacing.sm) {
            Text("Kinesia")
                .font(.system(size: 58, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(Color.textOnPhoto)

            Text("A gamified Parkinson\u{2019}s tracker built for both patients and clinicians.")
                .font(.subheadline)
                .fontWeight(.light)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textOnPhotoQuiet)
                .frame(maxWidth: 286)

            Image("brandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 78)
                .foregroundStyle(Color.textOnPhoto)
                .padding(.top, Spacing.xs)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    // Variable portion

    @ViewBuilder
    private var slot: some View {
        if !hasCompletedOnboarding {
            primaryButton("Get started") { showingOnboarding = true }
        } else if model.summary.checkedInToday {
            checkedInSlot
        } else {
            returningSlot
        }
    }

    private var returningSlot: some View {
        VStack(spacing: Spacing.md) {
            VStack(spacing: Spacing.xxs) {
                Text(greeting)
                    .font(.heading)
                    .foregroundStyle(Color.textOnPhoto)

                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline)
                    .foregroundStyle(Color.textOnPhotoQuiet)

                if let progress = progressLine {
                    Text(progress)
                        .font(.footnote)
                        .foregroundStyle(Color.textOnPhotoQuiet)
                        .padding(.top, Spacing.xxs)
                }
            }
            .multilineTextAlignment(.center)

            primaryButton("Log medicine") { onExit(.medicine) }
            quietButton("Start today\u{2019}s check-in") { onExit(.today) }
        }
    }

    private var checkedInSlot: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark.circle")
                    .font(.heading)
                Text("Today\u{2019}s check-in is done")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(Color.textOnPhoto)
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.md)
            .frame(maxWidth: .infinity)
            .background(Color.textOnPhoto.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.primary, style: .continuous))

            primaryButton("Open your garden") { onExit(.garden) }
            quietButton("Log medicine") { onExit(.medicine) }
        }
    }

    // Pieces
    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.button)
                .foregroundStyle(Color.primaryColor)
                .frame(maxWidth: .infinity, minHeight: 54)
        }
        .background(Color.textOnPhoto, in: Capsule())
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.textOnPhoto)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var progressLine: String? {
        guard !model.loadFailed, let day = model.summary.dayNumber else { return nil }
        let streak = model.summary.streak
        guard streak > 1 else { return "Day \(day)" }
        return "Day \(day) \u{00B7} \(streak)-day streak"
    }
}

private struct OnboardingFlow: View {
    private enum Step: Hashable { case questionnaire }

    @State private var path: [Step] = []
    let onFinish: () -> Void

    var body: some View {
        NavigationStack(path: $path) {
            OnboardingMeds(onContinue: { path.append(.questionnaire) })
                .navigationDestination(for: Step.self) { _ in
                    OnboardingPDQ8(onFinish: onFinish)
                }
        }
    }
}

#Preview {
    OpeningView { _ in }
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
