import Foundation
import KcalCore

/// Food lookups.
///
/// Open Food Facts covers barcoded products. Generic foods come from the bundled UK
/// CoFID dataset when the device region is the UK, otherwise from USDA.
/// Both are free but rate limited (OFF search: about 10 requests a minute per IP;
/// USDA: 1,000 an hour per key, shared by every install). That is fine for
/// development and a small beta but not for a public launch, see README.
struct FoodDatabase {
    var session: URLSession = .shared

    private static let userAgent = "Kcal/0.1 (iOS; contact: support@kcal.app)"

    private var usdaKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "KcalUSDAAPIKey") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "DEMO_KEY"
    }

    enum LookupError: LocalizedError {
        case badResponse(Int)
        var errorDescription: String? {
            switch self {
            case .badResponse(let code): "The food database returned an error (\(code))."
            }
        }
    }

    func product(barcode: String) async throws -> FoodCandidate? {
        var url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode)")!
        url.append(queryItems: [URLQueryItem(name: "fields", value: OFFProduct.fields)])
        do {
            let data = try await get(url)
            return try JSONDecoder().decode(OFFProductResponse.self, from: data).product?.candidate()
        } catch LookupError.badResponse(404) {
            // Open Food Facts answers 404 for unknown barcodes.
            return nil
        }
    }

    static var isUK: Bool { Locale.current.region?.identifier == "GB" }

    /// McCance and Widdowson's CoFID, loaded once on first use (about 2,900 foods).
    nonisolated static let cofid: CoFIDIndex? = {
        guard let url = Bundle.main.url(forResource: "cofid", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? CoFIDIndex(json: data)
    }()

    static func cofidCandidate(named name: String) -> FoodCandidate? {
        cofid?.food(named: name)?.candidate
    }

    /// Instant, offline generic foods. Empty outside the UK, where USDA is used instead.
    func localSearch(_ query: String) -> [FoodCandidate] {
        guard Self.isUK, query.count >= 2 else { return [] }
        return Self.cofid?.search(query) ?? []
    }

    /// Remote results: USDA generic foods (outside the UK) first, then branded products.
    /// In the UK, products sold there are ranked first without dropping the rest.
    /// A failure in one source does not hide the other.
    func search(_ query: String) async -> [FoodCandidate] {
        async let generic = Self.isUK ? [] : try? usda(query)
        async let branded = try? openFoodFacts(query)
        var products = await branded ?? []
        if Self.isUK {
            let sold = products.map { $0.countries.contains("en:united-kingdom") }
            products = zip(products, sold).enumerated()
                .sorted { ($0.element.1 ? 0 : 1, $0.offset) < ($1.element.1 ? 0 : 1, $1.offset) }
                .map(\.element.0)
        }
        let results = (await generic ?? []) + products
        var seen = Set<String>()
        return results.filter { seen.insert($0.name.lowercased() + ($0.brand ?? "")).inserted }
    }

    private func openFoodFacts(_ query: String) async throws -> [FoodCandidate] {
        var url = URL(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        url.append(queryItems: [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "20"),
            URLQueryItem(name: "fields", value: OFFProduct.fields),
        ])
        let data = try await get(url)
        return try JSONDecoder().decode(OFFSearchResponse.self, from: data).products.compactMap { $0.candidate() }
    }

    private func usda(_ query: String) async throws -> [FoodCandidate] {
        var url = URL(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        url.append(queryItems: [
            URLQueryItem(name: "api_key", value: usdaKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy"),
            URLQueryItem(name: "pageSize", value: "15"),
        ])
        let data = try await get(url)
        return try JSONDecoder().decode(FDCSearchResponse.self, from: data).foods.compactMap { $0.candidate() }
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw LookupError.badResponse(status) }
        return data
    }
}
