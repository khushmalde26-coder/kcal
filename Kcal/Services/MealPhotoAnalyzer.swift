import UIKit
import KcalCore

/// One food the model thinks is on the plate, with an estimated portion.
struct MealPhotoItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var grams: Double
    var per100: Nutrients

    enum CodingKeys: String, CodingKey { case name, grams, per100 }
}

/// Meal photo recognition needs a cloud vision model. The API key must not ship in
/// the app, so the app talks to a small backend that holds the key, checks the
/// request comes from a real install (App Attest), rate limits, and calls the model.
/// Until that backend exists `isAvailable` is false and the UI hides the feature.
struct MealPhotoAnalyzer {
    var session: URLSession = .shared

    private var endpoint: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "KcalMealPhotoEndpoint") as? String)
            .flatMap { $0.isEmpty ? nil : URL(string: $0) }
    }

    var isAvailable: Bool { endpoint != nil }

    enum AnalyzeError: LocalizedError {
        case unavailable, encoding, server(Int)
        var errorDescription: String? {
            switch self {
            case .unavailable: "Meal photos aren't available yet."
            case .encoding: "That photo couldn't be prepared."
            case .server(let code): "Couldn't analyse the photo (\(code))."
            }
        }
    }

    func analyze(_ image: UIImage) async throws -> [MealPhotoItem] {
        guard let endpoint else { throw AnalyzeError.unavailable }
        // 1024px on the long side is plenty for food recognition and keeps uploads small.
        guard let jpeg = image.resized(maxSide: 1024).jpegData(compressionQuality: 0.7) else {
            throw AnalyzeError.encoding
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        let (data, response) = try await session.upload(for: request, from: jpeg)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AnalyzeError.server(status) }
        return try JSONDecoder().decode([MealPhotoItem].self, from: data)
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return self }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
