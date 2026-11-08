import SwiftUI
import EventKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = CalendarService()

    @AppStorage(Prefs.calendarID) private var calendarID = ""
    @AppStorage(Prefs.alertMinutes) private var alertMinutes = 60
    @AppStorage(Prefs.durationMinutes) private var durationMinutes = 60
    @AppStorage(Prefs.guessBare) private var guessBare = true
    @AppStorage(Prefs.useAI) private var useAI = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Add events to") {
                    if service.authorized {
                        Picker("Calendar", selection: $calendarID) {
                            Text("Default calendar").tag("")
                            ForEach(service.calendars, id: \.calendarIdentifier) { cal in
                                Text(cal.title).tag(cal.calendarIdentifier)
                            }
                        }
                    } else {
                        Text("SnapCal needs calendar access. You'll be asked the first time you scan.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Reminders") {
                    Picker("Remind me", selection: $alertMinutes) {
                        Text("No reminder").tag(-1)
                        Text("At the time").tag(0)
                        Text("15 minutes before").tag(15)
                        Text("30 minutes before").tag(30)
                        Text("1 hour before").tag(60)
                        Text("2 hours before").tag(120)
                        Text("1 day before").tag(1440)
                    }
                    Picker("Events last", selection: $durationMinutes) {
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                }
                Section {
                    Toggle("Treat lone numbers as times", isOn: $guessBare)
                } footer: {
                    Text("\"Dentist 3\" becomes 3:00 PM. Numbers 8–11 are morning, 12–7 are afternoon/evening.")
                }
                Section {
                    Toggle("Apple Intelligence cleanup", isOn: $useAI)
                        .disabled(!AICleanup.isAvailable)
                } footer: {
                    Text(AICleanup.isAvailable
                         ? "Uses the free AI built into your iPhone to fix misread words. Runs on your phone; nothing is uploaded."
                         : "Not available on this iPhone (needs iPhone 15 Pro or newer with Apple Intelligence turned on).")
                }
                Section {
                    Text("Everything happens on your iPhone. Your photos never leave your phone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .task {
                if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
                    service.authorized = true
                    service.reloadCalendars()
                }
            }
        }
    }
}
