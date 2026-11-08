import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

extension UIImage {
    /// Redraws the image so its pixels are upright (orientation .up) and not larger than `maxDimension`.
    func normalizedUp(maxDimension: CGFloat = 4000) -> UIImage {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: newSize))
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

enum ImageTools {
    /// If the photo shows a page at an angle, straighten it like a document scanner would.
    static func flattenIfNeeded(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        try? handler.perform([request])
        guard let obs = request.results?.first, obs.confidence > 0.6 else { return image }

        let pts = [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft]
        var area: CGFloat = 0
        for i in 0..<4 {
            let a = pts[i], b = pts[(i + 1) % 4]
            area += a.x * b.y - b.x * a.y
        }
        area = abs(area) / 2
        // Only straighten when the page is a big part of the photo but not already filling it.
        guard area > 0.3, area < 0.92 else { return image }

        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = CIImage(cgImage: cg)
        filter.topLeft = CGPoint(x: obs.topLeft.x * w, y: obs.topLeft.y * h)
        filter.topRight = CGPoint(x: obs.topRight.x * w, y: obs.topRight.y * h)
        filter.bottomLeft = CGPoint(x: obs.bottomLeft.x * w, y: obs.bottomLeft.y * h)
        filter.bottomRight = CGPoint(x: obs.bottomRight.x * w, y: obs.bottomRight.y * h)
        guard let output = filter.outputImage else { return image }
        let context = CIContext()
        guard let result = context.createCGImage(output, from: output.extent) else { return image }
        return UIImage(cgImage: result)
    }

    /// Crops a region given in normalized top-left coordinates, painting `masks` (also normalized) white.
    static func crop(_ image: UIImage, rect: CGRect, masks: [CGRect] = [], minWidth: CGFloat = 700) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        let pixelRect = CGRect(x: rect.minX * W, y: rect.minY * H, width: rect.width * W, height: rect.height * H)
            .integral.intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard pixelRect.width > 4, pixelRect.height > 4, let cropped = cg.cropping(to: pixelRect) else { return nil }

        // Upscale small crops so the text readers see bigger letters.
        let scale = max(1, minWidth / pixelRect.width)
        let outSize = CGSize(width: (pixelRect.width * scale).rounded(), height: (pixelRect.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: outSize, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: outSize))
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: outSize))
            UIColor.white.setFill()
            for m in masks {
                let local = CGRect(
                    x: (m.minX * W - pixelRect.minX) * scale,
                    y: (m.minY * H - pixelRect.minY) * scale,
                    width: m.width * W * scale,
                    height: m.height * H * scale)
                ctx.fill(local)
            }
        }
    }
}

/// A small grayscale copy of the page, used to find grid lines and ink.
struct GrayBitmap {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(image: UIImage, maxWidth: Int = 1200) {
        guard let cg = image.cgImage else { return nil }
        let scale = min(1, Double(maxWidth) / Double(cg.width))
        let w = max(1, Int(Double(cg.width) * scale))
        let h = max(1, Int(Double(cg.height) * scale))
        var buffer = [UInt8](repeating: 255, count: w * h)
        let ok: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        width = w
        height = h
        pixels = buffer
    }

    @inline(__always) func value(_ x: Int, _ y: Int) -> UInt8 {
        pixels[y * width + x]
    }

    /// Fraction of "ink" pixels inside a normalized rect, ignoring `exclude` rects.
    func inkFraction(in rect: CGRect, excluding exclude: [CGRect]) -> Double {
        let x0 = max(0, Int(rect.minX * Double(width))), x1 = min(width - 1, Int(rect.maxX * Double(width)))
        let y0 = max(0, Int(rect.minY * Double(height))), y1 = min(height - 1, Int(rect.maxY * Double(height)))
        guard x1 > x0 + 2, y1 > y0 + 2 else { return 0 }
        let ex = exclude.map { CGRect(x: $0.minX * Double(width), y: $0.minY * Double(height),
                                      width: $0.width * Double(width), height: $0.height * Double(height)) }
        var values: [UInt8] = []
        values.reserveCapacity((x1 - x0) * (y1 - y0) / 4)
        var y = y0
        while y <= y1 {
            var x = x0
            while x <= x1 {
                let p = CGPoint(x: x, y: y)
                if !ex.contains(where: { $0.contains(p) }) { values.append(value(x, y)) }
                x += 2
            }
            y += 2
        }
        guard values.count > 20 else { return 0 }
        let sorted = values.sorted()
        let background = Int(sorted[Int(Double(sorted.count) * 0.85)])
        let threshold = background - 70
        guard threshold > 0 else { return 0 }
        let dark = values.reduce(0) { $0 + (Int($1) < threshold ? 1 : 0) }
        return Double(dark) / Double(values.count)
    }
}
