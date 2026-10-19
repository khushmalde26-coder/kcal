import UIKit
import Vision
import KcalCore

/// On-device OCR for nutrition panels. Nothing leaves the phone.
enum LabelReader {
    enum ReadError: LocalizedError {
        case unreadableImage
        case noText
        var errorDescription: String? {
            switch self {
            case .unreadableImage: "That photo couldn't be read."
            case .noText: "No text found. Try again closer to the label, with less glare."
            }
        }
    }

    static func read(_ image: UIImage) async throws -> ParsedLabel {
        let rows = try await rows(in: image)
        return NutritionLabelParser.parse(lines: rows)
    }

    static func rows(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { throw ReadError.unreadableImage }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction "fixes" numbers and units into words.
        request.usesLanguageCorrection = false

        let observations = try await request.perform(on: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
        let fragments = observations.compactMap { observation -> TextFragment? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox.cgRect
            return TextFragment(text: text, minX: box.minX, midY: box.midY, height: box.height)
        }
        guard !fragments.isEmpty else { throw ReadError.noText }
        return TextRowGrouper.rows(from: fragments)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
