import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
@Generable
struct AIDayEvents {
    @Guide(description: "Each separate event written in this calendar day box. Empty if nothing real is written.")
    var events: [AIEvent]
}

@available(iOS 26.0, *)
@Generable
struct AIEvent {
    @Guide(description: "Short event title with obvious spelling mistakes fixed. Do not include the time. Do not invent words.")
    var title: String
    @Guide(description: "Start time in 24-hour HH:mm format, or an empty string if no time is written.")
    var startTime: String
    @Guide(description: "End time in 24-hour HH:mm format, or an empty string if no end time is written.")
    var endTime: String
}

@available(iOS 26.0, *)
enum AICleanupEngine {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func clean(lines: [ReadingMerger.MergedLine]) async -> [EventParser.Draft]? {
        guard isAvailable, !lines.isEmpty else { return nil }
        let instructions = """
        You read handwriting from one day box of a paper wall calendar. Several text readers looked at \
        the same handwriting and each line below lists what they saw. Work out the real events. \
        Fix obvious misreadings (for example "Dentlst" is "Dentist"). Never add events or details that are not written. \
        A number like "3" next to an appointment is usually a time; times from 1 to 7 without am/pm are usually in the afternoon.
        """
        var prompt = "Readings for this day box, top to bottom:\n"
        for (i, line) in lines.enumerated() {
            let versions = Array(Set(line.variants)).prefix(4).map { "\"\($0)\"" }.joined(separator: " / ")
            prompt += "Line \(i + 1): \(versions)\n"
        }
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt, generating: AIDayEvents.self)
            let rawJoined = lines.flatMap(\.variants).joined(separator: " ")
            let hasDigits = rawJoined.contains { $0.isNumber } || rawJoined.lowercased().contains("noon")
            return response.content.events.compactMap { e in
                let title = EventParser.cleanTitle(e.title)
                guard title.filter({ $0.isLetter }).count >= 2 else { return nil }
                // Guard against made-up events: the title must look like something the readers saw.
                let words = title.lowercased().split(separator: " ").map(String.init)
                let seen = words.contains { w in
                    rawJoined.lowercased().contains(w) || lines.flatMap(\.variants).contains {
                        ReadingMerger.similarity($0, w) > 0.6 || $0.lowercased().split(separator: " ").contains { ReadingMerger.similarity(String($0), w) > 0.7 }
                    }
                }
                guard seen else { return nil }
                let start = hasDigits ? minutes(e.startTime) : nil
                let end = hasDigits ? minutes(e.endTime) : nil
                let confidence = lines.map(\.confidence).max() ?? 0.5
                return EventParser.Draft(title: title, start: start, end: end, raw: lines.map(\.text), confidence: confidence)
            }
        } catch {
            return nil
        }
    }

    private static func minutes(_ s: String) -> Int? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }
}
#endif

enum AICleanup {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return AICleanupEngine.isAvailable }
        #endif
        return false
    }

    static func clean(lines: [ReadingMerger.MergedLine]) async -> [EventParser.Draft]? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return await AICleanupEngine.clean(lines: lines) }
        #endif
        return nil
    }
}
