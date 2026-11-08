import SwiftUI

@main
struct SnapCalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.orange)
        }
    }
}

enum Prefs {
    static let calendarID = "calendarID"
    static let alertMinutes = "alertMinutes"
    static let durationMinutes = "durationMinutes"
    static let guessBare = "guessBareNumbers"
    static let useAI = "useAI"
}

struct ContentView: View {
    enum Screen { case home, processing, review, done }

    @StateObject private var calendar = CalendarService()
    @State private var screen: Screen = .home
    @State private var progressText = ""
    @State private var progressValue = 0.0
    @State private var result: ScanResult?
    @State private var addedIDs: [String] = []
    @State private var errorMessage: String?

    @AppStorage(Prefs.useAI) private var useAI = true
    @AppStorage(Prefs.guessBare) private var guessBare = true

    var body: some View {
        Group {
            switch screen {
            case .home:
                HomeView(onImage: process)
            case .processing:
                ProcessingView(text: progressText, value: progressValue)
            case .review:
                if result != nil {
                    ReviewView(result: Binding(get: { result! }, set: { result = $0 }),
                               calendar: calendar,
                               onCancel: { screen = .home; result = nil },
                               onAdded: { ids in addedIDs = ids; screen = .done })
                }
            case .done:
                DoneView(count: addedIDs.count,
                         onUndo: { calendar.undo(addedIDs); addedIDs = []; screen = .review },
                         onFinish: { result = nil; addedIDs = []; screen = .home })
            }
        }
        .animation(.default, value: screen)
        .alert("Couldn't read that photo", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func process(_ image: UIImage) {
        screen = .processing
        progressText = "Getting started…"
        progressValue = 0
        Task {
            do {
                var scan = try await ScanPipeline.run(
                    image: image, options: ScanOptions(useAI: useAI, guessBareNumbers: guessBare),
                    progress: { text, value in progressText = text; progressValue = value })
                if await calendar.requestAccess() {
                    calendar.markDuplicates(&scan.events, month: scan.month, year: scan.year)
                }
                result = scan
                screen = .review
            } catch {
                errorMessage = error.localizedDescription
                screen = .home
            }
        }
    }
}
