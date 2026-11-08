import UIKit

struct CandidateEvent: Identifiable {
    let id = UUID()
    var day: Int
    var title: String
    var hasTime: Bool
    /// Minutes after midnight.
    var startMinutes: Int
    var endMinutes: Int?
    var include: Bool
    /// 0...1 — how many of the readers agreed.
    var confidence: Double
    var rawText: String
    var cropImage: UIImage?
    var isHoliday = false
    var isDuplicate = false
    var aiCleaned = false

    var needsCheck: Bool { confidence < 0.5 }
}

struct ScanResult {
    var month: Int
    var year: Int
    var monthConfident: Bool
    var events: [CandidateEvent]
    var pageImage: UIImage
    var readersUsed: [String]
}

extension Int {
    /// "3:30 PM" for minutes after midnight.
    var timeLabel: String {
        let h = self / 60, m = self % 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", h12, m, h < 12 ? "AM" : "PM")
    }
}
