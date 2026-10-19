import SwiftUI

/// ContentUnavailableView with the Kcal mark instead of an SF Symbol.
struct BrandEmptyState: View {
    let title: String
    let message: Text

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                Image("LogoMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
            }
        } description: {
            message
        }
    }
}
