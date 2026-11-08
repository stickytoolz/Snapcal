import UIKit

struct DayCell {
    let day: Int
    /// The whole box for this day, normalized top-left coordinates.
    let rect: CGRect
    /// Where the printed day number is (so we can ignore it).
    let numberBox: CGRect
}

struct CalendarGrid {
    var cells: [Int: DayCell]
    var month: Int
    var year: Int
    /// False when we had to guess the month — the review screen asks the person to check it.
    var monthConfident: Bool
}

enum GridError: LocalizedError {
    case noDates
    var errorDescription: String? {
        "SnapCal couldn't find the printed dates on this calendar. Try again with the whole month in the picture, straight-on, with good light."
    }
}

/// Finds the day boxes of a month calendar from the printed day numbers.
enum GridLocator {

    private struct NumberMark {
        let value: Int
        let box: CGRect
        var cx: Double { box.midX }
        var cy: Double { box.midY }
    }

    static let monthNames: [(String, Int)] = [
        ("january", 1), ("february", 2), ("march", 3), ("april", 4), ("may", 5), ("june", 6),
        ("july", 7), ("august", 8), ("september", 9), ("october", 10), ("november", 11), ("december", 12),
        ("jan", 1), ("feb", 2), ("mar", 3), ("apr", 4), ("jun", 6), ("jul", 7), ("aug", 8),
        ("sep", 9), ("sept", 9), ("oct", 10), ("nov", 11), ("dec", 12),
    ]

    /// Weekday index with Sunday = 0.
    static let weekdayNames: [String: Int] = [
        "sun": 0, "sunday": 0, "mon": 1, "monday": 1, "tue": 2, "tues": 2, "tuesday": 2,
        "wed": 3, "weds": 3, "wednesday": 3, "thu": 4, "thur": 4, "thurs": 4, "thursday": 4,
        "fri": 5, "friday": 5, "sat": 6, "saturday": 6,
    ]

    static func clean(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func locate(words: [PageWord], bitmap: GrayBitmap?, now: Date = Date()) throws -> CalendarGrid {
        // 1. Every word that looks like a day number 1–31.
        var marks: [NumberMark] = []
        for w in words {
            let t = w.text.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;*"))
            guard t.count <= 2, t.allSatisfy({ $0.isNumber }), let v = Int(t), (1...31).contains(v) else { continue }
            marks.append(NumberMark(value: v, box: w.box))
        }
        guard marks.count >= 6 else { throw GridError.noDates }

        // 2. Spacing between columns (px) and rows (py) from pairs of numbers.
        let typicalHeight = median(marks.map { $0.box.height }) ?? 0.02
        var colSteps: [Double] = []
        var rowSteps: [Double] = []
        for a in marks {
            for b in marks where b.value > a.value {
                let d = b.value - a.value
                let dx = b.cx - a.cx, dy = b.cy - a.cy
                if d <= 6, abs(dy) < typicalHeight * 1.2, dx > 0 {
                    colSteps.append(dx / Double(d))
                } else if d % 7 == 0, d <= 28, dy > 0, abs(dx) < max(typicalHeight * 1.5, 0.02) {
                    rowSteps.append(dy / Double(d / 7))
                }
            }
        }
        guard let px = median(colSteps), px > 0.03,
              let py = median(rowSteps), py > 0.03 else { throw GridError.noDates }

        // 3. Find which column the 1st is in, and where the grid starts, using the most agreeing numbers.
        func position(_ v: Int, _ s: Int) -> (col: Int, row: Int) {
            ((v - 1 + s) % 7, (v - 1 + s) / 7)
        }
        var best: (s: Int, ox: Double, oy: Double, support: [NumberMark], error: Double)? = nil
        for c in marks {
            for s in 0..<7 {
                let p = position(c.value, s)
                let ox = c.cx - Double(p.col) * px
                let oy = c.cy - Double(p.row) * py
                var support: [NumberMark] = []
                var err = 0.0
                var seen = Set<Int>()
                for d in marks where !seen.contains(d.value) {
                    let q = position(d.value, s)
                    let ex = abs(ox + Double(q.col) * px - d.cx) / px
                    let ey = abs(oy + Double(q.row) * py - d.cy) / py
                    if ex < 0.25 && ey < 0.25 {
                        support.append(d)
                        seen.insert(d.value)
                        err += ex + ey
                    }
                }
                if best == nil || support.count > best!.support.count
                    || (support.count == best!.support.count && err < best!.error) {
                    best = (s, ox, oy, support, err)
                }
            }
        }
        guard let fit = best, fit.support.count >= 6 else { throw GridError.noDates }
        let s = fit.s

        // Refine the origin with every agreeing number.
        let ox = median(fit.support.map { $0.cx - Double(position($0.value, s).col) * px }) ?? fit.ox
        let oy = median(fit.support.map { $0.cy - Double(position($0.value, s).row) * py }) ?? fit.oy
        let maxSeenRow = fit.support.map { position($0.value, s).row }.max() ?? 4
        let numberSize = CGSize(
            width: median(fit.support.map { $0.box.width }) ?? px * 0.15,
            height: median(fit.support.map { $0.box.height }) ?? py * 0.15)
        let supportByValue = Dictionary(fit.support.map { ($0.value, $0) }, uniquingKeysWith: { a, _ in a })

        // 4. Look for the printed grid lines to know exactly where each box starts.
        let lastRow = max(maxSeenRow, 4)
        let lineX = bitmap.flatMap { gridLinePhase(bitmap: $0, vertical: true, pitch: px,
                                                   along: (ox - px, ox + 7 * px),
                                                   across: (oy - 0.3 * py, oy + (Double(lastRow) + 0.6) * py)) }
        let lineY = bitmap.flatMap { gridLinePhase(bitmap: $0, vertical: false, pitch: py,
                                                   along: (oy - py, oy + Double(lastRow + 2) * py),
                                                   across: (ox - 0.4 * px, ox + 6.6 * px)) }

        // Weekday headings help place boxes when there are no grid lines.
        var headerOffsets: [Double] = []
        var weekStartMonday: Bool? = nil
        var headerHits: [(weekday: Int, cx: Double)] = []
        for w in words {
            if let wd = weekdayNames[clean(w.text)], w.box.midY < oy {
                headerHits.append((wd, w.box.midX))
            }
        }
        if headerHits.count >= 3, let first = headerHits.min(by: { $0.cx < $1.cx }) {
            weekStartMonday = first.weekday == 1
            let startWeekday = weekStartMonday == true ? 1 : 0
            for h in headerHits {
                let col = (h.weekday - startWeekday + 7) % 7
                headerOffsets.append(h.cx - (ox + Double(col) * px))
            }
        }
        let headerOffset = median(headerOffsets)

        // 5. Build each day's box.
        let month = guessMonth(words: words, firstColumn: s, weekStartMonday: weekStartMonday,
                               maxDay: fit.support.map { $0.value }.max() ?? 28, now: now)
        let daysInMonth = Self.daysIn(month: month.month, year: month.year)
        var cells: [Int: DayCell] = [:]
        for day in 1...daysInMonth {
            var p = position(day, s)
            // Calendars that only have 5 rows share the last box ("23/30").
            if p.row > lastRow { p.row = lastRow }
            let ncx = supportByValue[day]?.cx ?? (ox + Double(p.col) * px)
            let ncy = supportByValue[day]?.cy ?? (oy + Double(p.row) * py)
            let numberBox = supportByValue[day]?.box ?? CGRect(
                x: ncx - numberSize.width / 2, y: ncy - numberSize.height / 2,
                width: numberSize.width, height: numberSize.height)

            let left: Double
            if let phase = lineX {
                left = phase + floor((ncx - phase) / px) * px
            } else if let off = headerOffset {
                left = ncx + off - px / 2
            } else {
                left = numberBox.minX - px * 0.08
            }
            let top: Double
            if let phase = lineY {
                top = phase + floor((ncy - phase) / py) * py
            } else {
                top = numberBox.minY - numberBox.height * 0.4
            }
            let rect = CGRect(x: left, y: top, width: px, height: py)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !rect.isNull, rect.width > 0.01, rect.height > 0.01 else { continue }
            if cells[day] == nil {
                cells[day] = DayCell(day: day, rect: rect, numberBox: numberBox.insetBy(dx: -numberBox.width * 0.25, dy: -numberBox.height * 0.25))
            }
        }
        guard cells.count >= 20 else { throw GridError.noDates }
        return CalendarGrid(cells: cells, month: month.month, year: month.year, monthConfident: month.confident)
    }

    /// Finds the position of evenly spaced dark lines. Returns the normalized position of one line, or nil.
    private static func gridLinePhase(bitmap: GrayBitmap, vertical: Bool, pitch: Double,
                                      along: (Double, Double), across: (Double, Double)) -> Double? {
        let alongSize = vertical ? bitmap.width : bitmap.height
        let acrossSize = vertical ? bitmap.height : bitmap.width
        let a0 = max(0, Int(along.0 * Double(alongSize))), a1 = min(alongSize - 1, Int(along.1 * Double(alongSize)))
        let c0 = max(0, Int(across.0 * Double(acrossSize))), c1 = min(acrossSize - 1, Int(across.1 * Double(acrossSize)))
        guard a1 - a0 > 20, c1 - c0 > 20 else { return nil }
        let pitchPx = pitch * Double(alongSize)
        guard pitchPx > 8 else { return nil }

        // Darkness profile along the axis.
        var profile = [Double](repeating: 0, count: alongSize)
        for a in a0...a1 {
            var sum = 0
            var c = c0
            while c <= c1 {
                let v = vertical ? bitmap.value(a, c) : bitmap.value(c, a)
                sum += 255 - Int(v)
                c += 2
            }
            profile[a] = Double(sum) / Double((c1 - c0) / 2 + 1)
        }
        let window = Array(profile[a0...a1])
        guard let typical = median(window), typical >= 0 else { return nil }

        var bestPhase = 0, bestScore = -1.0
        for phase in 0..<Int(pitchPx) {
            var total = 0.0, count = 0
            var x = Double(a0 + phase)
            while x <= Double(a1) {
                let i = Int(x)
                let lo = max(a0, i - 1), hi = min(a1, i + 1)
                total += profile[lo...hi].max() ?? 0
                count += 1
                x += pitchPx
            }
            if count >= 3 {
                let score = total / Double(count)
                if score > bestScore { bestScore = score; bestPhase = phase }
            }
        }
        // Lines must be clearly darker than the rest of the page.
        guard bestScore > typical * 1.6 + 6 else { return nil }
        return Double(a0 + bestPhase) / Double(alongSize)
    }

    // MARK: Month and year

    static func daysIn(month: Int, year: Int) -> Int {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        let cal = Calendar(identifier: .gregorian)
        guard let date = cal.date(from: comps), let range = cal.range(of: .day, in: .month, for: date) else { return 31 }
        return range.count
    }

    /// Weekday of the 1st, Sunday = 0.
    static func firstWeekday(month: Int, year: Int) -> Int {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        let cal = Calendar(identifier: .gregorian)
        guard let date = cal.date(from: comps) else { return 0 }
        return cal.component(.weekday, from: date) - 1
    }

    private static func guessMonth(words: [PageWord], firstColumn s: Int, weekStartMonday: Bool?,
                                   maxDay: Int, now: Date) -> (month: Int, year: Int, confident: Bool) {
        let cal = Calendar(identifier: .gregorian)
        let thisYear = cal.component(.year, from: now)
        let thisMonth = cal.component(.month, from: now)

        // The biggest month name printed on the page is usually the title.
        var foundMonth: Int? = nil
        var biggest = 0.0
        for w in words {
            let t = clean(w.text)
            if let m = monthNames.first(where: { $0.0 == t })?.1, Double(w.box.height) > biggest {
                foundMonth = m
                biggest = Double(w.box.height)
            }
        }
        var foundYear: Int? = nil
        for w in words {
            let t = clean(w.text)
            if t.count == 4, let y = Int(t), (2000...2100).contains(y) { foundYear = y }
        }

        func matches(_ m: Int, _ y: Int) -> Bool {
            let fw = firstWeekday(month: m, year: y)
            let ok: Bool
            switch weekStartMonday {
            case .some(true): ok = (fw + 6) % 7 == s
            case .some(false): ok = fw == s
            case .none: ok = fw == s || (fw + 6) % 7 == s
            }
            return ok && daysIn(month: m, year: y) >= maxDay
        }

        if let m = foundMonth, let y = foundYear { return (m, y, true) }
        if let m = foundMonth {
            for y in [thisYear, thisYear + 1, thisYear - 1] where matches(m, y) { return (m, y, true) }
            return (m, thisYear, false)
        }
        // No month name: pick the nearest month whose layout fits.
        for offset in [0, 1, -1, 2, 3, -2, 4, 5, 6, 7, 8, 9, 10, 11] {
            var comps = DateComponents()
            comps.year = thisYear
            comps.month = thisMonth + offset
            comps.day = 1
            guard let d = cal.date(from: comps) else { continue }
            let m = cal.component(.month, from: d), y = cal.component(.year, from: d)
            if let fy = foundYear, fy != y { continue }
            if matches(m, y) { return (m, y, false) }
        }
        return (thisMonth, foundYear ?? thisYear, false)
    }
}

func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let s = values.sorted()
    let mid = s.count / 2
    return s.count % 2 == 0 ? (s[mid - 1] + s[mid]) / 2 : s[mid]
}

func median(_ values: [CGFloat]) -> CGFloat? {
    median(values.map { Double($0) }).map { CGFloat($0) }
}
