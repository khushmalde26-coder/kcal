import SwiftUI
import UIKit

/// Brand colours, defined once in Assets.xcassets/Theme with light and dark variants.
/// Contrast (WCAG): see README "Colour and contrast".
enum Theme {
    /// Milk / near-black brown.
    static let background = Color("Theme/Background")
    /// Oat cards and grouped rows.
    static let surface = Color("Theme/Surface")
    /// Cocoa / Oat.
    static let text = Color("Theme/Text")
    /// Captions and secondary labels (4.5:1+ on Oat and Milk).
    static let secondaryText = Color("Theme/SecondaryText")
    /// Decorative only on light backgrounds (1.9:1 on Milk): never for text there.
    static let blush = Color("Theme/Blush")
    /// Text and icons on a tint-filled control.
    static let onTint = Color("Theme/OnTint")

    static let ringTrack = Color("Theme/RingTrack")
    static let ringGoal = Color("Theme/RingGoal")
    /// Earned-by-activity fill (graphics, 3:1+).
    static let earned = Color("Theme/Earned")
    /// Earned-by-activity text (4.5:1+).
    static let earnedText = Color("Theme/EarnedText")
    static let over = Color("Theme/Over")

    static let protein = Color("Theme/Protein")
    static let carbs = Color("Theme/Carbs")
    static let fat = Color("Theme/Fat")
}

extension View {
    /// Milk background behind a List or Form. Rows get Oat per section
    /// (`.listRowBackground(Theme.surface)`), since it doesn't carry down from the List.
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background)
    }
}

extension Theme {
    /// Navigation titles are UIKit-drawn, so they take the text colour from appearance.
    static func applyNavigationAppearance() {
        guard let text = UIColor(named: "Theme/Text") else { return }
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.foregroundColor: text]
        bar.titleTextAttributes = [.foregroundColor: text]
    }
}
