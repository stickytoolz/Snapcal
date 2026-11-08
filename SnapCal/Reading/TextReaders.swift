import UIKit
import Vision
import VisionKit

/// One word found on the full page, with its box in normalized top-left coordinates.
struct PageWord {
    let text: String
    let box: CGRect
    let confidence: Float
    /// Which line on the page this word came from (words from the same Vision line share this).
    let lineID: Int
}

enum TextReaders {

    // MARK: Apple Vision

    static func visionObservations(_ cg: CGImage, languageCorrection: Bool) -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = languageCorrection
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        return request.results ?? []
    }

    static func toTopLeft(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    }

    /// Reads the whole page and splits every line into words with their own boxes.
    static func pageWords(_ image: UIImage) -> [PageWord] {
        guard let cg = image.cgImage else { return [] }
        var words: [PageWord] = []
        let observations = visionObservations(cg, languageCorrection: false)
        for (lineID, obs) in observations.enumerated() {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let s = candidate.string
            var index = s.startIndex
            while index < s.endIndex {
                guard let start = s[index...].firstIndex(where: { !$0.isWhitespace }) else { break }
                let end = s[start...].firstIndex(where: { $0.isWhitespace }) ?? s.endIndex
                let range = start..<end
                let box: CGRect
                if let rectObs = try? candidate.boundingBox(for: range) {
                    box = toTopLeft(rectObs.boundingBox)
                } else {
                    box = toTopLeft(obs.boundingBox)
                }
                words.append(PageWord(text: String(s[range]), box: box, confidence: candidate.confidence, lineID: lineID))
                index = end
            }
        }
        return words
    }

    /// Reads a cropped day box and returns its lines from top to bottom.
    static func visionLines(_ image: UIImage, languageCorrection: Bool) -> [String] {
        guard let cg = image.cgImage else { return [] }
        let observations = visionObservations(cg, languageCorrection: languageCorrection)
            .filter { ($0.topCandidates(1).first?.confidence ?? 0) > 0.2 }
            .sorted { a, b in
                if abs(a.boundingBox.midY - b.boundingBox.midY) > 0.04 { return a.boundingBox.midY > b.boundingBox.midY }
                return a.boundingBox.minX < b.boundingBox.minX
            }
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }

    // MARK: Apple Live Text

    static var liveTextSupported: Bool { ImageAnalyzer.isSupported }

    @MainActor
    static func liveTextLines(_ image: UIImage, analyzer: ImageAnalyzer) async -> [String] {
        let config = ImageAnalyzer.Configuration([.text])
        guard let analysis = try? await analyzer.analyze(image, configuration: config) else { return [] }
        return analysis.transcript
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
