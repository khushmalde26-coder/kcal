import Foundation

/// A piece of recognised text with a normalised bounding box (0...1, y grows upward,
/// which is Vision's convention).
public struct TextFragment: Equatable, Sendable {
    public var text: String
    public var minX: Double
    public var midY: Double
    public var height: Double

    public init(text: String, minX: Double, midY: Double, height: Double) {
        self.text = text
        self.minX = minX
        self.midY = midY
        self.height = height
    }
}

/// Vision returns table cells as separate observations ("Protein", "6.3g", "1.9g").
/// The parser needs whole rows, so fragments on the same visual line are joined.
public enum TextRowGrouper {
    public static func rows(from fragments: [TextFragment]) -> [String] {
        guard !fragments.isEmpty else { return [] }
        let heights = fragments.map(\.height).sorted()
        let tolerance = max(heights[heights.count / 2] * 0.5, 0.002)

        var rows: [[TextFragment]] = []
        for fragment in fragments.sorted(by: { $0.midY > $1.midY }) {
            if let last = rows.indices.last {
                let rowY = rows[last].map(\.midY).reduce(0, +) / Double(rows[last].count)
                if abs(fragment.midY - rowY) <= tolerance {
                    rows[last].append(fragment)
                    continue
                }
            }
            rows.append([fragment])
        }

        return rows.map { row in
            row.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ")
        }
    }
}
