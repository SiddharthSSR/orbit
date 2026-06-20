import SwiftUI

/// A simple content card. Styling is delegated to the shared `.orbitCardStyle()`
/// surface (warm fill, continuous `OrbitRadius.md` corners, a hairline
/// `OrbitColor.border`, and a soft shadow) so it stays consistent with the rest
/// of the Orbit design system.
struct OrbitCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .orbitCardStyle()
    }
}

