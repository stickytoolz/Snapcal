import Foundation

/// Combines what several text readers saw in one day box, keeping what most of them agree on.
enum ReadingMerger {

    struct MergedLine {
        let text: String
        /// Every version of this line the readers produced (handy for the AI cleanup).
        let variants: [String]
        let votes: Int
        let confidence: Double
    }

    static func key(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(key(a)), y = Array(key(b))
        if x.isEmpty && y.isEmpty { return 1 }
        if x.isEmpty || y.isEmpty { return 0 }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                cur[j] = Swift.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return 1 - Double(prev[y.count]) / Double(Swift.max(x.count, y.count))
    }

    /// - Parameter readings: one list of lines per reader, in priority order (most trusted first).
    static func merge(_ readings: [[String]]) -> [MergedLine] {
        struct Member { let reader: Int; let text: String; let order: Double }
        var clusters: [[Member]] = []
        let activeReaders = Swift.max(1, readings.filter { !$0.isEmpty }.count)

        for (r, lines) in readings.enumerated() {
            for (i, raw) in lines.enumerated() {
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key(line).isEmpty else { continue }
                let order = lines.count > 1 ? Double(i) / Double(lines.count - 1) : 0.5
                var bestIndex: Int? = nil
                var bestSim = 0.55
                for (ci, cluster) in clusters.enumerated() where !cluster.contains(where: { $0.reader == r }) {
                    let sim = cluster.map { similarity($0.text, line) }.max() ?? 0
                    if sim > bestSim { bestSim = sim; bestIndex = ci }
                }
                let m = Member(reader: r, text: line, order: order)
                if let bi = bestIndex { clusters[bi].append(m) } else { clusters.append([m]) }
            }
        }

        let ordered = clusters.sorted { a, b in
            let oa = a.map(\.order).reduce(0, +) / Double(a.count)
            let ob = b.map(\.order).reduce(0, +) / Double(b.count)
            return oa < ob
        }

        return ordered.compactMap { cluster in
            // The version most readers spelled the same way; ties go to the most trusted reader.
            var groups: [String: [Member]] = [:]
            for m in cluster { groups[key(m.text), default: []].append(m) }
            let winner = groups.values.max { a, b in
                if a.count != b.count { return a.count < b.count }
                return (a.map(\.reader).min() ?? 99) > (b.map(\.reader).min() ?? 99)
            }
            guard let chosen = winner?.min(by: { $0.reader < $1.reader }) else { return nil }
            let votes = Set(cluster.map(\.reader)).count
            let letters = chosen.text.filter { $0.isLetter }.count
            let hasDigit = chosen.text.contains { $0.isNumber }
            if letters < 2 && !hasDigit { return nil }
            if votes == 1 && key(chosen.text).count < 3 { return nil }
            return MergedLine(text: chosen.text, variants: cluster.map(\.text), votes: votes,
                              confidence: Double(votes) / Double(activeReaders))
        }
    }
}
