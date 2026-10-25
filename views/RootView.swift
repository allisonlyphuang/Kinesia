import CoreData
import SwiftUI

struct RootView: View {

    private enum Tab: CaseIterable, Identifiable {
        case today
        case garden
        case insights

        var id: Self { self }

        var title: String {
            switch self {
            case .today:    return "Today"
            case .garden:   return "Garden"
            case .insights: return "Insights"
            }
        }

        var symbol: String {
            switch self {
            case .today:    return "house"
            case .garden:   return "leaf"
            case .insights: return "chart.bar"
            }
        }
    }

    @State private var selection: Tab = .today
    @State private var showingOpening = true
    @State private var showingMedicine = false
    @Namespace private var pill
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        ZStack {
            content
                .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }

            if showingOpening {
                OpeningView { exit in
                    switch exit {
                    case .today:
                        selection = .today
                    case .garden:
                        selection = .garden
                    case .medicine:
                        selection = .today
                        showingMedicine = true
                    }
                    withAnimation(.easeOut(duration: 0.3)) { showingOpening = false }
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingMedicine) {
            NavigationStack { MedicationLogView() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .today:    HomeView(onOpenGarden: { selection = .garden })
        case .garden:   GardenView(context: context)
        case .insights: ClinicianReportView()
        }
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 20, weight: .regular))
                        Text(tab.title)
                            .font(.caption2)
                            .fontWeight(selection == tab ? .semibold : .medium)
                    }
                    .foregroundStyle(selection == tab ? Color.textDark : Color.textQuiet)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .contentShape(Rectangle())
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(Color.buttonSoft)
                                .matchedGeometryEffect(id: "selectedTab", in: pill)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs + 2)
        .animation(.snappy(duration: 0.25), value: selection)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Color.cardSurface
                Rectangle()
                    .fill(Color.hairline)
                    .frame(height: 1)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct GardenView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = HomeSummaryModel()
    private let context: NSManagedObjectContext

    private var completedCount: Int { model.summary.doneToday.count }

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header

                if model.loadFailed {
                    unavailableState
                } else {
                    gardenCard
                    activitiesSection

                    if model.summary.hasHistory {
                        streakSection
                    }
                }
            }
            .padding(.horizontal, GameChrome.gutter)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.lg)
        }
        .gameGround()
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            reload()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                reload()
            }
        }
    }

    private func reload() {
        model.reload(in: context)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Your garden")
                .font(.displayMedium)
                .fontWeight(.medium)
                .foregroundStyle(Color.textDark)

            Text("A little growth from today’s activities")
                .font(.body)
                .foregroundStyle(Color.textQuiet)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gardenCard: some View {
        VStack(spacing: Spacing.xs) {
            Image("gardenStage\(completedCount)")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                // The shared illustration canvas reserves room for the later foliage.
                // Remove only that transparent headroom from the smaller stages' layout.
                .padding(.top, completedCount == 0 ? -75 : (completedCount == 1 ? -20 : 0))
                .accessibilityHidden(true)

            Text(stageTitle)
                .font(.heading)
                .foregroundStyle(Color.textDark)

            Text("\(completedCount) of \(CheckInTask.allCases.count) activities completed today")
                .font(.subheadline)
                .foregroundStyle(Color.textQuiet)

            ProgressView(value: Double(completedCount), total: Double(CheckInTask.allCases.count))
                .tint(Color.primaryColor)
                .frame(maxWidth: 180)
                .padding(.top, Spacing.xxs)
                .accessibilityLabel("Today’s activities")
                .accessibilityValue("\(completedCount) of \(CheckInTask.allCases.count) completed")
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.bottom, Spacing.xs)
    }

    private var streakSection: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "leaf")
                .font(.heading)
                .foregroundStyle(Color.primaryColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("\(model.summary.streak)-day activity streak")
                    .font(.subheading)
                    .foregroundStyle(Color.textDark)
                Text("Based on days with a saved session")
                    .font(.footnote)
                    .foregroundStyle(Color.textQuiet)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Today’s activities")
                .sectionLabelStyle()
                .foregroundStyle(Color.primaryColor)
                .padding(.horizontal, Spacing.xxs)

            VStack(spacing: 0) {
                activityRow(.plants, title: "Bradykinesia", symbol: "hand.tap")
                rowSeparator
                activityRow(.fireflies, title: "Akinesia", symbol: "sparkles")
                rowSeparator
                activityRow(.constellation, title: "Dexterity", symbol: "point.3.connected.trianglepath.dotted")
            }
            .padding(.horizontal, Spacing.md)
            .background(
                Color.cardSurface,
                in: RoundedRectangle(cornerRadius: Radius.primary, style: .continuous)
            )
        }
    }

    private func activityRow(_ task: CheckInTask, title: String, symbol: String) -> some View {
        let isComplete = model.summary.doneToday.contains(task)

        return HStack(spacing: Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(Color.primaryColor)
                .frame(width: 28, height: 28)

            Text(title)
                .font(.body)
                .foregroundStyle(Color.textDark)

            Spacer(minLength: Spacing.xs)

            HStack(spacing: Spacing.xxs) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                Text(isComplete ? "Done" : "Not yet")
                    .font(.subheadline.weight(isComplete ? .semibold : .regular))
            }
            .foregroundStyle(isComplete ? Color.primaryColor : Color.textQuiet)
        }
        .frame(minHeight: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isComplete ? "Completed today" : "Not completed today")
    }

    private var rowSeparator: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("Garden activity unavailable", systemImage: "leaf")
                .font(.heading)
                .foregroundStyle(Color.textDark)

            Text("Your saved activity couldn’t be read just now. Try opening this tab again.")
                .font(.body)
                .foregroundStyle(Color.textQuiet)
                .fixedSize(horizontal: false, vertical: true)
        }
        .gameCard()
    }

    private var stageTitle: String {
        switch completedCount {
        case 0: return model.summary.hasHistory ? "A new day to grow" : "Ready to grow"
        case 1: return "A first leaf"
        case 2: return "Growing steadily"
        default: return "Today’s garden is full"
        }
    }
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
