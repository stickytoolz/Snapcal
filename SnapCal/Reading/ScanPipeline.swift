import UIKit
import VisionKit

struct ScanOptions {
    var useAI: Bool
    var guessBareNumbers: Bool
}

/// The whole "photo → list of events" process.
enum ScanPipeline {

    static func run(image original: UIImage, options: ScanOptions,
                    progress: @escaping @MainActor (String, Double) -> Void) async throws -> ScanResult {
        await progress("Straightening the photo…", 0.02)
        let page = await Task.detached(priority: .userInitiated) {
            ImageTools.flattenIfNeeded(original.normalizedUp())
        }.value

        await progress("Finding the dates…", 0.08)
        let (words, bitmap) = await Task.detached(priority: .userInitiated) {
            (TextReaders.pageWords(page), GrayBitmap(image: page))
        }.value
        let grid = try GridLocator.locate(words: words, bitmap: bitmap)

        // Words from the full-page read, grouped by day box (reader #4).
        var pageLines: [Int: [String]] = [:]
        do {
            var byCellLine: [Int: [Int: [PageWord]]] = [:]
            for w in words {
                let c = CGPoint(x: w.box.midX, y: w.box.midY)
                guard let cell = grid.cells.values.first(where: { $0.rect.contains(c) }) else { continue }
                if cell.numberBox.contains(c), w.text.allSatisfy({ $0.isNumber }) { continue }
                byCellLine[cell.day, default: [:]][w.lineID, default: []].append(w)
            }
            for (day, lines) in byCellLine {
                let sorted = lines.values.sorted { ($0.first?.box.minY ?? 0) < ($1.first?.box.minY ?? 0) }
                pageLines[day] = sorted.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            }
        }

        let useLiveText = TextReaders.liveTextSupported
        var analyzer: ImageAnalyzer? = nil
        if useLiveText { analyzer = await MainActor.run { ImageAnalyzer() } }
        let useAI = options.useAI && AICleanup.isAvailable
        var readersUsed = ["Apple Vision", "Apple Vision (raw)"]
        if useLiveText { readersUsed.append("Apple Live Text") }
        readersUsed.append("Full-page pass")
        if useAI { readersUsed.append("Apple Intelligence cleanup") }

        var events: [CandidateEvent] = []
        let days = grid.cells.keys.sorted()
        for (i, day) in days.enumerated() {
            guard let cell = grid.cells[day] else { continue }
            await progress("Reading day \(day)…", 0.12 + 0.83 * Double(i) / Double(days.count))

            let inset = cell.rect.insetBy(dx: cell.rect.width * 0.03, dy: cell.rect.height * 0.03)
            let ink = bitmap?.inkFraction(in: cell.rect.insetBy(dx: cell.rect.width * 0.08, dy: cell.rect.height * 0.08),
                                          excluding: [cell.numberBox]) ?? 1
            let fromPage = pageLines[day] ?? []
            if ink < 0.004 && fromPage.isEmpty { continue }

            guard let crop = ImageTools.crop(page, rect: inset, masks: [cell.numberBox]) else { continue }
            let (corrected, raw) = await Task.detached(priority: .userInitiated) {
                (TextReaders.visionLines(crop, languageCorrection: true),
                 TextReaders.visionLines(crop, languageCorrection: false))
            }.value
            var live: [String] = []
            if let analyzer { live = await TextReaders.liveTextLines(crop, analyzer: analyzer) }

            let strip = { (lines: [String]) -> [String] in lines.map { stripDayNumber($0, day: day) } }
            let merged = ReadingMerger.merge([strip(corrected), strip(live), strip(raw), strip(fromPage)])
            guard !merged.isEmpty else { continue }

            var drafts = EventParser.parse(lines: merged, guessBareNumbers: options.guessBareNumbers)
            var cleaned = false
            if useAI, let ai = await AICleanup.clean(lines: merged), !ai.isEmpty {
                // Keep the rule-based time if the AI didn't find one.
                drafts = ai.enumerated().map { idx, d in
                    var d = d
                    if d.start == nil, idx < drafts.count, ReadingMerger.similarity(drafts[idx].title, d.title) > 0.5 {
                        d.start = drafts[idx].start
                        d.end = drafts[idx].end
                    }
                    return d
                }
                cleaned = true
            }

            let thumb = ImageTools.crop(page, rect: inset, minWidth: 0)
            for d in drafts {
                let holiday = EventParser.isHoliday(d.title)
                events.append(CandidateEvent(
                    day: day, title: d.title, hasTime: d.start != nil,
                    startMinutes: d.start ?? 9 * 60, endMinutes: d.end,
                    include: !holiday, confidence: d.confidence, rawText: d.raw.joined(separator: " / "),
                    cropImage: thumb, isHoliday: holiday, aiCleaned: cleaned))
            }
        }
        await progress("Done", 1)
        return ScanResult(month: grid.month, year: grid.year, monthConfident: grid.monthConfident,
                          events: events, pageImage: page, readersUsed: readersUsed)
    }

    /// Removes the printed day number if a reader picked it up at the start of a line.
    static func stripDayNumber(_ line: String, day: Int) -> String {
        let t = line.trimmingCharacters(in: .whitespaces)
        let d = String(day)
        if t == d { return "" }
        if t.hasPrefix(d + " ") {
            let rest = t.dropFirst(d.count + 1)
            // Keep "3 pm" style times.
            let lower = rest.lowercased()
            if lower.hasPrefix("am") || lower.hasPrefix("pm") || lower.hasPrefix("a ") || lower.hasPrefix("p ") { return t }
            return String(rest)
        }
        return t
    }
}
