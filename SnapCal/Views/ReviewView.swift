import SwiftUI

struct ReviewView: View {
    @Binding var result: ScanResult
    @ObservedObject var calendar: CalendarService
    let onCancel: () -> Void
    let onAdded: ([String]) -> Void

    @AppStorage(Prefs.calendarID) private var calendarID = ""
    @AppStorage(Prefs.alertMinutes) private var alertMinutes = 60
    @AppStorage(Prefs.durationMinutes) private var durationMinutes = 60

    @State private var editing: CandidateEvent.ID?
    @State private var showPage = false
    @State private var errorMessage: String?

    private var includedCount: Int { result.events.filter(\.include).count }
    private var monthName: String { Calendar.current.monthSymbols[result.month - 1] }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    monthPicker
                    if !result.monthConfident {
                        Label("SnapCal guessed the month. Make sure it's right.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                    Button { showPage = true } label: {
                        HStack {
                            Image(uiImage: result.pageImage)
                                .resizable().scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text("View your photo")
                        }
                    }
                } footer: {
                    Text("Read with: " + result.readersUsed.joined(separator: ", "))
                }

                if result.events.isEmpty {
                    Section {
                        Text("No handwriting found. You can add events yourself with the + button.")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(days, id: \.self) { day in
                    Section(header: Text(dayHeader(day))) {
                        ForEach(eventIDs(day), id: \.self) { id in
                            EventRow(event: binding(id))
                                .contentShape(Rectangle())
                                .onTapGesture { editing = id }
                        }
                        .onDelete { offsets in deleteEvents(day: day, offsets: offsets) }
                    }
                }
            }
            .navigationTitle("Check & Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .primaryAction) {
                    Button { addManual() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add an event")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text(includedCount == 0 ? "Nothing selected" : "Add \(includedCount) to Calendar")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(includedCount == 0)
                .padding()
                .background(.bar)
            }
            .sheet(item: Binding(get: { editing.map { EditID(id: $0) } }, set: { editing = $0?.id })) { item in
                EventEditView(event: binding(item.id), daysInMonth: GridLocator.daysIn(month: result.month, year: result.year))
            }
            .sheet(isPresented: $showPage) {
                NavigationStack {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: result.pageImage).resizable().scaledToFit()
                            .frame(width: UIScreen.main.bounds.width * 2)
                    }
                    .toolbar { Button("Done") { showPage = false } }
                }
            }
            .alert("Couldn't add events", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private struct EditID: Identifiable { let id: UUID }

    private var days: [Int] { Array(Set(result.events.map(\.day))).sorted() }

    private func dayHeader(_ day: Int) -> String {
        guard let date = CalendarService.date(year: result.year, month: result.month, day: day) else { return "\(day)" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }

    private var monthPicker: some View {
        HStack {
            Menu {
                ForEach(1...12, id: \.self) { m in
                    Button(Calendar.current.monthSymbols[m - 1]) { setMonth(m, result.year) }
                }
            } label: {
                Text(monthName).font(.title2.bold())
            }
            Menu {
                let y = Calendar.current.component(.year, from: Date())
                ForEach((y - 1)...(y + 2), id: \.self) { yr in
                    Button(String(yr)) { setMonth(result.month, yr) }
                }
            } label: {
                Text(String(result.year)).font(.title2.bold())
            }
            Spacer()
        }
    }

    private func setMonth(_ m: Int, _ y: Int) {
        result.month = m
        result.year = y
        result.monthConfident = true
        let maxDay = GridLocator.daysIn(month: m, year: y)
        for i in result.events.indices where result.events[i].day > maxDay { result.events[i].include = false }
        calendar.markDuplicates(&result.events, month: m, year: y)
    }

    private func eventIDs(_ day: Int) -> [UUID] {
        result.events.filter { $0.day == day }.map(\.id)
    }

    private func binding(_ id: UUID) -> Binding<CandidateEvent> {
        Binding(
            get: {
                result.events.first { $0.id == id }
                    ?? CandidateEvent(day: 1, title: "", hasTime: false, startMinutes: 0, endMinutes: nil,
                                      include: false, confidence: 1, rawText: "")
            },
            set: { newValue in
                if let i = result.events.firstIndex(where: { $0.id == id }) { result.events[i] = newValue }
            })
    }

    private func deleteEvents(day: Int, offsets: IndexSet) {
        let ids = eventIDs(day)
        let remove = Set(offsets.map { ids[$0] })
        result.events.removeAll { remove.contains($0.id) }
    }

    private func addManual() {
        let today = Calendar.current.component(.day, from: Date())
        let e = CandidateEvent(day: min(today, GridLocator.daysIn(month: result.month, year: result.year)),
                               title: "", hasTime: false, startMinutes: 9 * 60, endMinutes: nil,
                               include: true, confidence: 1, rawText: "Typed in")
        result.events.append(e)
        editing = e.id
    }

    private func save() {
        do {
            let ids = try calendar.add(result.events.filter { !$0.title.isEmpty }, month: result.month, year: result.year,
                                       calendarID: calendarID, alertMinutes: alertMinutes, durationMinutes: durationMinutes)
            onAdded(ids)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EventRow: View {
    @Binding var event: CandidateEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { event.include.toggle() } label: {
                Image(systemName: event.include ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(event.include ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title.isEmpty ? "(no title)" : event.title)
                    .font(.headline)
                    .foregroundStyle(event.include ? .primary : .secondary)
                Text(event.hasTime ? timeText : "All day")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if event.isDuplicate { badge("Already in calendar", .blue) }
                    if event.isHoliday { badge("Printed holiday?", .purple) }
                    if event.needsCheck { badge("Double-check", .orange) }
                }
            }
            Spacer()
            if let crop = event.cropImage {
                Image(uiImage: crop)
                    .resizable().scaledToFit()
                    .frame(width: 84, height: 64)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
        }
        .padding(.vertical, 4)
    }

    private var timeText: String {
        if let end = event.endMinutes { return "\(event.startMinutes.timeLabel) – \(end.timeLabel)" }
        return event.startMinutes.timeLabel
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct EventEditView: View {
    @Binding var event: CandidateEvent
    let daysInMonth: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let crop = event.cropImage {
                    Section("What's written on the calendar") {
                        Image(uiImage: crop).resizable().scaledToFit()
                            .frame(maxHeight: 220)
                            .frame(maxWidth: .infinity)
                            .background(Color.white)
                    }
                }
                Section("Event") {
                    TextField("Title", text: $event.title)
                        .font(.title3)
                    Picker("Day", selection: $event.day) {
                        ForEach(1...daysInMonth, id: \.self) { Text("\($0)").tag($0) }
                    }
                    Toggle("Add to calendar", isOn: $event.include)
                }
                Section("Time") {
                    Toggle("Has a time", isOn: $event.hasTime)
                    if event.hasTime {
                        DatePicker("Starts", selection: minutesBinding(\.startMinutes), displayedComponents: .hourAndMinute)
                        Toggle("Has an end time", isOn: Binding(
                            get: { event.endMinutes != nil },
                            set: { event.endMinutes = $0 ? min(event.startMinutes + 60, 23 * 60 + 59) : nil }))
                        if event.endMinutes != nil {
                            DatePicker("Ends", selection: Binding(
                                get: { date(event.endMinutes ?? event.startMinutes) },
                                set: { event.endMinutes = minutes($0) }), displayedComponents: .hourAndMinute)
                        }
                    }
                }
                Section {
                    Text("Readers saw: \(event.rawText)").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func date(_ m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }

    private func minutes(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func minutesBinding(_ key: WritableKeyPath<CandidateEvent, Int>) -> Binding<Date> {
        Binding(get: { date(event[keyPath: key]) }, set: { event[keyPath: key] = minutes($0) })
    }
}
