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
        case .garden:   GardenView()
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
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Your garden", systemImage: "leaf")
            } description: {
                Text("Not built yet. ")
            }
            .background { Rectangle().fill(.pageGround).ignoresSafeArea() }
        }
    }
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
