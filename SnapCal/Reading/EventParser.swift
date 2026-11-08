import Foundation

/// Turns the lines written in one day box into events with times.
enum EventParser {

    struct ParsedTime {
        let start: Int
        let end: Int?
        let range: Range<String.Index>
    }

    static let holidays: [String] = [
        "new year's day", "new years day", "new year's eve", "new years eve", "martin luther king", "mlk day",
        "groundhog day", "valentine's day", "valentines day", "presidents day", "presidents' day",
        "st. patrick's day", "st patricks day", "daylight saving", "good friday", "easter", "palm sunday",
        "ash wednesday", "mother's day", "mothers day", "memorial day", "flag day", "father's day",
        "fathers day", "juneteenth", "independence day", "labor day", "columbus day", "indigenous peoples",
        "halloween", "veterans day", "thanksgiving", "christmas", "hanukkah", "kwanzaa", "full moon",
        "new moon", "first quarter", "last quarter", "election day", "earth day", "cinco de mayo",
        "rosh hashanah", "yom kippur", "passover", "boxing day", "spring begins", "summer begins",
        "autumn begins", "fall begins", "winter begins", "tax day", "april fools", "patriot day",
        "pearl harbor", "black friday", "arbor day", "armed forces day", "groundhog", "st. valentine",
    ]

    static func isHoliday(_ text: String) -> Bool {
        let k = ReadingMerger.key(text)
        guard !k.isEmpty else { return false }
        return holidays.contains { h in
            let hk = ReadingMerger.key(h)
            return k.contains(hk) || ReadingMerger.similarity(k, hk) > 0.8
        }
    }

    /// Fixes common reader mistakes in times, e.g. "3prn" → "3pm", "1O:3O" → "10:30".
    static func normalize(_ s: String) -> String {
        var t = s
        for (a, b) in [("prn", "pm"), ("arn", "am"), ("p.m.", "pm"), ("a.m.", "am"), ("P.M.", "pm"), ("A.M.", "am")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        // O or o between/after digits → 0, l or I between digits → 1
        if let re = try? NSRegularExpression(pattern: "(?<=\\d[:.]?)[Oo]|[Oo](?=\\d)") {
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "0")
        }
        return t
    }

    static func guessHour(_ h: Int) -> Int {
        // 8–11 → morning, 12–7 → afternoon/evening.
        if h == 12 { return 12 }
        if h >= 1 && h <= 7 { return h + 12 }
        return h
    }

    static func apply(_ hour: Int, _ meridiem: String?) -> Int? {
        guard (0...23).contains(hour) else { return nil }
        guard let m = meridiem?.lowercased(), let c = m.first else { return hour }
        guard (1...12).contains(hour) else { return nil }
        if c == "a" { return hour == 12 ? 0 : hour }
        return hour == 12 ? 12 : hour + 12
    }

    static func findTime(in text: String, guessBareNumbers: Bool) -> ParsedTime? {
        let ns = NSRange(text.startIndex..., in: text)
        func match(_ pattern: String) -> NSTextCheckingResult? {
            (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]))?.firstMatch(in: text, range: ns)
        }
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            guard m.range(at: i).location != NSNotFound, let r = Range(m.range(at: i), in: text) else { return nil }
            return String(text[r])
        }
        func range(_ m: NSTextCheckingResult) -> Range<String.Index> { Range(m.range, in: text)! }

        // "3-5pm", "10:30 - 11:30am", "2pm to 4pm"
        if let m = match("\\b(\\d{1,2})(?:[:.](\\d{2}))?\\s*(am|pm|a|p)?\\s*(?:-|–|to)\\s*(\\d{1,2})(?:[:.](\\d{2}))?\\s*(am|pm|a|p)\\b"),
           let h1 = Int(group(m, 1) ?? ""), let h2 = Int(group(m, 4) ?? "") {
            let m1 = Int(group(m, 2) ?? "") ?? 0, m2 = Int(group(m, 5) ?? "") ?? 0
            let endMer = group(m, 6)
            if let eh = apply(h2, endMer) {
                var sh = apply(h1, group(m, 3) ?? endMer) ?? h1
                if sh * 60 + m1 > eh * 60 + m2, group(m, 3) == nil { sh = apply(h1, "am") ?? h1 }
                return ParsedTime(start: sh * 60 + m1, end: eh * 60 + m2, range: range(m))
            }
        }
        // "3pm", "3:30 pm", "10a", "7p"
        if let m = match("\\b(\\d{1,2})(?:[:.](\\d{2}))?\\s*(am|pm|a|p)\\b"),
           let h = Int(group(m, 1) ?? ""), let hh = apply(h, group(m, 3)) {
            let mm = Int(group(m, 2) ?? "") ?? 0
            if mm < 60 { return ParsedTime(start: hh * 60 + mm, end: nil, range: range(m)) }
        }
        // "noon", "midnight"
        if let m = match("\\bnoon\\b") { return ParsedTime(start: 12 * 60, end: nil, range: range(m)) }
        // "3:30" with no am/pm
        if let m = match("\\b(\\d{1,2}):(\\d{2})\\b"), let h = Int(group(m, 1) ?? ""), let mm = Int(group(m, 2) ?? ""),
           h <= 23, mm < 60 {
            let hh = h <= 12 ? guessHour(h) : h
            return ParsedTime(start: hh * 60 + mm, end: nil, range: range(m))
        }
        // "@ 3", "at 3"
        if let m = match("(?:@|\\bat)\\s*(\\d{1,2})\\b"), let h = Int(group(m, 1) ?? ""), (1...12).contains(h) {
            return ParsedTime(start: guessHour(h) * 60, end: nil, range: range(m))
        }
        // "Dentist 3" or "3 Dentist"
        if guessBareNumbers {
            if let m = match("(?<=\\s)(\\d{1,2})\\s*$"), let h = Int(group(m, 1) ?? ""), (1...12).contains(h) {
                return ParsedTime(start: guessHour(h) * 60, end: nil, range: range(m))
            }
            if let m = match("^\\s*(\\d{1,2})(?=\\s+[A-Za-z])"), let h = Int(group(m, 1) ?? ""), (1...12).contains(h) {
                return ParsedTime(start: guessHour(h) * 60, end: nil, range: range(m))
            }
        }
        return nil
    }

    static func cleanTitle(_ s: String) -> String {
        let collapsed = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: " -–—@,:;.|/\\*~_"))
    }

    struct Draft {
        var title: String
        var start: Int?
        var end: Int?
        var raw: [String]
        var confidence: Double
    }

    static func parse(lines: [ReadingMerger.MergedLine], guessBareNumbers: Bool) -> [Draft] {
        var drafts: [Draft] = []
        var pendingTime: ParsedTime? = nil

        for line in lines {
            let text = normalize(line.text)
            let time = findTime(in: text, guessBareNumbers: guessBareNumbers)
            var title = text
            if let t = time { title.removeSubrange(t.range) }
            title = cleanTitle(title)

            if title.filter({ $0.isLetter }).count < 2 {
                // A line with only a time: give it to the event above, or hold it for the next line.
                if let t = time {
                    if let last = drafts.indices.last, drafts[last].start == nil {
                        drafts[last].start = t.start
                        drafts[last].end = t.end
                        drafts[last].raw.append(line.text)
                    } else {
                        pendingTime = t
                    }
                }
                continue
            }

            let continues = title.first.map { $0.isLowercase || "&+".contains($0) } ?? false
            if continues, time == nil, let last = drafts.indices.last {
                drafts[last].title += " " + title
                drafts[last].raw.append(line.text)
                drafts[last].confidence = min(drafts[last].confidence, line.confidence)
                continue
            }

            let t = time ?? pendingTime
            pendingTime = nil
            drafts.append(Draft(title: title, start: t?.start, end: t?.end, raw: [line.text], confidence: line.confidence))
        }
        return drafts
    }
}
