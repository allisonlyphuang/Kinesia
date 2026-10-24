import CoreData
import SwiftUI

struct HomeView: View {

    @Environment(\.managedObjectContext) private var context
    @StateObject private var model = HomeSummaryModel()
    @State private var showingSchedule = false

    let onOpenGarden: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    gardenCard.padding(.top, Spacing.lg)

                    if model.loadFailed {
                        Text("Couldn\u{2019}t read your history.")
                            .font(.footnote)
                            .foregroundStyle(Color.textQuiet)
                            .padding(.top, Spacing.sm)
                    }

                    sectionLabel(
                        "Today\u{2019}s check-in",
                        trailing: model.summary.checkedInToday ? "All done" : nil
                    )
                    .padding(.top, Spacing.lg)
                    checkInList
                    sectionLabel("Medicine").padding(.top, Spacing.lg)
                    medicineList
                }
                .padding(.horizontal, 22)
                .padding(.bottom, Spacing.lg)
            }
            .background { Rectangle().fill(.pageGround).ignoresSafeArea() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image("brandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundStyle(Color.primaryColor)
                        .accessibilityLabel("Kinesia")
                }
                // On the logo, lose the capsule that iOS creates by default behind toolbar items
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSchedule = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Color.primaryColor)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showingSchedule) {
            NavigationStack {
                OnboardingMeds(continueTitle: "Save")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingSchedule = false }
                        }
                    }
            }
        }
        .onAppear { model.reload(in: context) }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            model.reload(in: context)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(greeting)
                .fontWeight(.medium)
                .foregroundStyle(Color.textDark)
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .fontWeight(.regular)
                .foregroundStyle(Color.primaryColor)
        }
        .font(.displayMedium)
        .padding(.top, Spacing.sm)
    }

    // MARK: Garden
    @ViewBuilder
    private var gardenCard: some View {
        if !model.summary.hasHistory, let next = nextTask {
            NavigationLink { testView(for: next) } label: { gardenCardFace }
                .buttonStyle(.plain)
        } else {
            Button(action: onOpenGarden) { gardenCardFace }
                .buttonStyle(.plain)
        }
    }

    private var gardenCardFace: some View {
        ZStack {
            GeometryReader { proxy in
                Image("openingBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .overlay(.gardenCardScrim)
            }
            .accessibilityHidden(true)

            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Your garden")
                        .sectionLabelStyle()
                        .foregroundStyle(Color.textOnPhotoQuiet)

                    gardenHeadline

                    if let day = model.summary.dayNumber {
                        Text("Day \(day)")
                            .font(.subheadline)
                            .foregroundStyle(Color.textOnPhotoQuiet)
                    }
                }
                Spacer(minLength: Spacing.sm)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textOnPhoto)
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 124)
        .clipShape(RoundedRectangle(cornerRadius: Radius.primary, style: .continuous))
    }

    @ViewBuilder
    private var gardenHeadline: some View {
        if !model.summary.hasHistory {
            Text("Begin your first check-in")
                .font(.heading)
                .foregroundStyle(Color.textOnPhoto)
        } else if model.summary.streak > 0 {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs + 2) {
                Text("\(model.summary.streak)")
                    .font(.displayLarge)
                Text(model.summary.streak == 1 ? "day in a row" : "days in a row")
                    .font(.subheadline)
                    .foregroundStyle(Color.textOnPhotoQuiet)
            }
            .foregroundStyle(Color.textOnPhoto)
        } else {
            Text("Start again today")
                .font(.heading)
                .foregroundStyle(Color.textOnPhoto)
        }
    }

    // MARK: Lists

    private var checkInList: some View {
        listCard {
            row(.fireflies, icon: Image(systemName: "sparkle")) { AkinesiaTestView() }
            separator
            row(.constellation, icon: Image(systemName: "point.3.connected.trianglepath.dotted")) { DexterityTestView() }
            separator
            row(.ripples, icon: RipplesGlyph()) { BradykinesiaTestView() }
        }
    }

    private var medicineList: some View {
        listCard {
            NavigationLink { MedicationLogView() } label: {
                rowContent(
                    title: "Log medicine",
                    icon: Image(systemName: "pills"),
                    value: model.summary.nextDose.map { $0.formatted(date: .omitted, time: .shortened) }
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func listCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 18)
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

    private func row<Destination: View>(
        _ task: CheckInTask,
        icon: some View,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            rowContent(
                title: task.title,
                icon: icon,
                value: model.summary.doneToday.contains(task) ? "Done" : nil
            )
        }
        .buttonStyle(.plain)
    }

    private func rowContent(title: String, icon: some View, value: String?) -> some View {
        HStack(spacing: Spacing.sm + 2) {
            icon
                .font(.system(size: 20, weight: .regular))
                .frame(width: 26, height: 26)
                .foregroundStyle(Color.primaryColor)

            Text(title)
                .font(.body)
                .foregroundStyle(Color.textDark)

            Spacer(minLength: Spacing.xs)

            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Color.textQuiet)
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.chevronTint)
        }
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    private func sectionLabel(_ text: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
            if let trailing {
                Spacer(minLength: Spacing.xs)
                Text(trailing)
            }
        }
        .sectionLabelStyle()
        .foregroundStyle(Color.primaryColor)
        .padding(.horizontal, Spacing.xxs)
        .padding(.bottom, Spacing.xs + 2)
    }

    // MARK: Routing

  
    private var nextTask: CheckInTask? {
        CheckInTask.allCases.first { !model.summary.doneToday.contains($0) }
    }

    @ViewBuilder
    private func testView(for task: CheckInTask) -> some View {
        switch task {
        case .fireflies:     AkinesiaTestView()
        case .constellation: DexterityTestView()
        case .ripples:       BradykinesiaTestView()
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        default:      return "Good evening"
        }
    }
}

struct RipplesGlyph: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().strokeBorder(lineWidth: 1.6).frame(width: side)
                Circle().strokeBorder(lineWidth: 1.6).frame(width: side * 0.61)
                Circle().strokeBorder(lineWidth: 1.6).frame(width: side * 0.22)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

#Preview {
    HomeView(onOpenGarden: {})
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
