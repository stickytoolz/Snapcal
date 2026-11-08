import EventKit
import UIKit

@MainActor
final class CalendarService: ObservableObject {
    let store = EKEventStore()
    @Published var authorized = false
    @Published var calendars: [EKCalendar] = []

    func requestAccess() async -> Bool {
        let ok = (try? await store.requestFullAccessToEvents()) ?? false
        authorized = ok
        if ok { reloadCalendars() }
        return ok
    }

    func reloadCalendars() {
        calendars = store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func calendar(id: String) -> EKCalendar? {
        if !id.isEmpty, let c = store.calendar(withIdentifier: id), c.allowsContentModifications { return c }
        return store.defaultCalendarForNewEvents
    }

    static func date(year: Int, month: Int, day: Int, minutes: Int = 0) -> Date? {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = minutes / 60
        c.minute = minutes % 60
        return Calendar.current.date(from: c)
    }

    /// Marks events that are already in the iPhone calendar so they aren't added twice.
    func markDuplicates(_ events: inout [CandidateEvent], month: Int, year: Int) {
        guard authorized else { return }
        for i in events.indices {
            guard let start = Self.date(year: year, month: month, day: events[i].day),
                  let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { continue }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            let existing = store.events(matching: predicate)
            let title = events[i].title
            let dup = existing.contains { ReadingMerger.similarity($0.title ?? "", title) > 0.8 }
            events[i].isDuplicate = dup
            if dup { events[i].include = false }
        }
    }

    /// Adds the events and returns their identifiers (so they can be undone).
    func add(_ events: [CandidateEvent], month: Int, year: Int, calendarID: String,
             alertMinutes: Int, durationMinutes: Int) throws -> [String] {
        guard let calendar = calendar(id: calendarID) else { throw CalendarError.noCalendar }
        var ids: [EKEvent] = []
        for e in events where e.include {
            let ev = EKEvent(eventStore: store)
            ev.title = e.title
            ev.calendar = calendar
            ev.notes = "Added by SnapCal from your paper calendar.\nWhat it read: \(e.rawText)"
            if e.hasTime {
                guard let start = Self.date(year: year, month: month, day: e.day, minutes: e.startMinutes) else { continue }
                ev.startDate = start
                let endMinutes = e.endMinutes.flatMap { $0 > e.startMinutes ? $0 : nil }
                ev.endDate = endMinutes.flatMap { Self.date(year: year, month: month, day: e.day, minutes: $0) }
                    ?? start.addingTimeInterval(TimeInterval(durationMinutes * 60))
                if alertMinutes >= 0 { ev.addAlarm(EKAlarm(relativeOffset: TimeInterval(-alertMinutes * 60))) }
            } else {
                guard let start = Self.date(year: year, month: month, day: e.day) else { continue }
                ev.isAllDay = true
                ev.startDate = start
                ev.endDate = start
                // All-day events: remind at 9 AM that day.
                if alertMinutes >= 0 { ev.addAlarm(EKAlarm(relativeOffset: 9 * 3600)) }
            }
            try store.save(ev, span: .thisEvent, commit: false)
            ids.append(ev)
        }
        try store.commit()
        return ids.compactMap(\.eventIdentifier)
    }

    func undo(_ ids: [String]) {
        for id in ids {
            if let ev = store.event(withIdentifier: id) { try? store.remove(ev, span: .thisEvent, commit: false) }
        }
        try? store.commit()
    }
}

enum CalendarError: LocalizedError {
    case noCalendar
    var errorDescription: String? { "SnapCal couldn't find a calendar to add events to. Check Settings → Privacy → Calendars." }
}
