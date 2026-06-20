import SwiftUI

// MARK: - Orbit Design System
//
// A small, reusable visual foundation for Orbit. The goal is a calm, warm,
// slightly futuristic feel — clean cards, restrained borders, gentle spacing,
// and a premium typographic hierarchy — without redesigning every screen.
//
// Screens should prefer these primitives over ad-hoc styling so future UI
// refreshes stay consistent. Everything here is presentation-only: no data,
// networking, or behavior lives in this layer.

/// Consistent spacing scale (points). Use these instead of raw numbers so
/// rhythm stays uniform across screens.
enum OrbitSpacing {
    /// 4 — hairline gaps inside compact controls.
    static let xxs: CGFloat = 4
    /// 8 — tight spacing between closely related elements.
    static let xs: CGFloat = 8
    /// 12 — default spacing inside a card or row.
    static let sm: CGFloat = 12
    /// 16 — standard screen padding and section spacing.
    static let md: CGFloat = 16
    /// 24 — separation between major sections.
    static let lg: CGFloat = 24
    /// 32 — generous breathing room around hero content.
    static let xl: CGFloat = 32
}

/// Corner radius scale (points). Continuous corners are used everywhere for a
/// softer, more modern silhouette.
enum OrbitRadius {
    /// 8 — chips, small badges, inline controls.
    static let sm: CGFloat = 8
    /// 12 — cards and surfaces.
    static let md: CGFloat = 12
    /// 16 — large featured surfaces.
    static let lg: CGFloat = 16
    /// Effectively pill-shaped; pair with `Capsule()` where possible.
    static let pill: CGFloat = 999
}

/// Typography roles. Headers use a rounded design for a warmer, more personal
/// tone while body copy stays in the system default for legibility.
enum OrbitTypography {
    /// Prominent screen-level heading.
    static let screenTitle = Font.system(.largeTitle, design: .rounded).weight(.semibold)
    /// Section header inside a screen.
    static let sectionTitle = Font.system(.headline, design: .rounded)
    /// Title inside a card.
    static let cardTitle = Font.system(.headline, design: .rounded)
    /// Standard body copy.
    static let body = Font.body
    /// Secondary / supporting copy.
    static let caption = Font.caption
    /// Small emphasized label used inside badges and chips.
    static let badge = Font.caption.weight(.semibold)
}

/// Semantic colors with built-in light/dark variants. Warm neutrals keep the
/// app feeling personal rather than clinical.
enum OrbitColor {
    /// App background base — warm paper in light, warm near-black in dark.
    static let background = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
            : UIColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1)
    })

    /// A slightly lifted background tone used to softly layer the backdrop.
    static let backgroundElevated = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
            : UIColor(red: 0.99, green: 0.98, blue: 0.97, alpha: 1)
    })

    /// Card / surface fill that sits above the background.
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)

    /// Restrained hairline border for surfaces.
    static let border = Color(uiColor: .separator).opacity(0.7)

    /// Brand accent (defers to the system/app accent).
    static let accent = Color.accentColor
}

// MARK: - Surfaces

/// Calm card styling: surface fill, soft continuous corners, a hairline border,
/// and a very subtle shadow. Use via `.orbitCardStyle()`.
struct OrbitCardStyle: ViewModifier {
    var padding: CGFloat = OrbitSpacing.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(OrbitColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: OrbitRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: OrbitRadius.md, style: .continuous)
                    .stroke(OrbitColor.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

extension View {
    /// Applies the standard Orbit card surface treatment.
    func orbitCardStyle(padding: CGFloat = OrbitSpacing.md) -> some View {
        modifier(OrbitCardStyle(padding: padding))
    }

    /// Applies the subtle layered Orbit app background behind a screen.
    func orbitBackground() -> some View {
        background(OrbitBackground().ignoresSafeArea())
    }
}

/// Full-width "floating card" surface for list rows (Inbox memories, Bills,
/// etc.): surface fill, continuous corners, a hairline border, and a soft
/// shadow, with an optional accent highlight for freshly created items. Pair
/// with `.orbitListCardRow()` when the card is a `List` row.
struct OrbitFloatingCardStyle: ViewModifier {
    var isHighlighted: Bool = false
    var padding: CGFloat = OrbitSpacing.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHighlighted ? Color.accentColor.opacity(0.12) : OrbitColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: OrbitRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: OrbitRadius.md, style: .continuous)
                    .stroke(
                        isHighlighted ? Color.accentColor.opacity(0.6) : OrbitColor.border,
                        lineWidth: isHighlighted ? 1.5 : 1
                    )
            }
            .shadow(color: .black.opacity(0.04), radius: 5, x: 0, y: 2)
    }
}

extension View {
    /// Applies the Orbit full-width floating card surface (for list rows).
    func orbitFloatingCard(
        isHighlighted: Bool = false,
        padding: CGFloat = OrbitSpacing.md
    ) -> some View {
        modifier(OrbitFloatingCardStyle(isHighlighted: isHighlighted, padding: padding))
    }

    /// Strips default `List` row chrome so an `orbitFloatingCard` reads as a
    /// standalone card floating on the Orbit background, with calm vertical gaps.
    func orbitListCardRow() -> some View {
        listRowInsets(EdgeInsets(
            top: OrbitSpacing.xs,
            leading: OrbitSpacing.md,
            bottom: OrbitSpacing.xs,
            trailing: OrbitSpacing.md
        ))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

/// Subtle, layered app background. A warm neutral base with a barely-there
/// top highlight — enough to add depth without a loud gradient.
struct OrbitBackground: View {
    var body: some View {
        LinearGradient(
            colors: [OrbitColor.backgroundElevated, OrbitColor.background],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Components

/// Small capsule badge for counts, statuses, and tags. Tinted faintly so it
/// reads as an accent, not a button.
struct OrbitBadge: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(OrbitTypography.badge)
            .foregroundStyle(tint)
            .padding(.horizontal, OrbitSpacing.xs)
            .padding(.vertical, OrbitSpacing.xxs)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Consistent section header with an icon, a title, and an optional trailing
/// accessory (e.g. a count badge).
struct OrbitSectionHeader<Accessory: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var accessory: () -> Accessory

    init(
        _ title: String,
        systemImage: String? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory
    }

    var body: some View {
        HStack {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .font(OrbitTypography.sectionTitle)
            } else {
                Text(title)
                    .font(OrbitTypography.sectionTitle)
            }

            Spacer()

            accessory()
        }
    }
}

extension OrbitSectionHeader where Accessory == EmptyView {
    /// Convenience initializer for a header with no trailing accessory.
    init(_ title: String, systemImage: String? = nil) {
        self.init(title, systemImage: systemImage) { EmptyView() }
    }
}

// MARK: - Preview

struct OrbitDesignSystem_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrbitSpacing.lg) {
                OrbitSectionHeader("Open Todos", systemImage: "checklist") {
                    OrbitBadge(text: "3 open")
                }

                VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                    Text("Daily Plan")
                        .font(OrbitTypography.cardTitle)
                    Text("A calm, warm surface for everyday content.")
                        .font(OrbitTypography.body)
                        .foregroundStyle(.secondary)
                    HStack(spacing: OrbitSpacing.xs) {
                        OrbitBadge(text: "New", tint: .accentColor)
                        OrbitBadge(text: "Due today", tint: .orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .orbitCardStyle()
            }
            .padding(OrbitSpacing.md)
        }
        .orbitBackground()
        .previewDisplayName("Orbit Design System")
    }
}
