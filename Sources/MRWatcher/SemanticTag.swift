import SwiftUI

enum SemanticTagTone {
    case positive
    case attention
    case critical
    case neutral
    case accent

    var foreground: Color {
        switch self {
        case .positive: .green
        case .attention: .orange
        case .critical: .red
        case .neutral: .secondary
        case .accent: .blue
        }
    }

    var background: Color {
        foreground.opacity(0.12)
    }
}

struct SemanticTag: View {
    let title: String
    let systemImage: String
    let tone: SemanticTagTone

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tone.background, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityElement(children: .combine)
    }
}

struct TagFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let requiredWidth = lineWidth == 0 ? size.width : lineWidth + spacing + size.width

            if requiredWidth > maxWidth, lineWidth > 0 {
                totalHeight += lineHeight + spacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth = requiredWidth
                lineHeight = max(lineHeight, size.height)
            }
        }

        return CGSize(
            width: proposal.width ?? lineWidth,
            height: totalHeight + lineHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + spacing + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }

            if x > bounds.minX {
                x += spacing
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width
            lineHeight = max(lineHeight, size.height)
        }
    }
}

func behindTagTitle(_ count: Int) -> String {
    "\(count) retard\(count == 1 ? "" : "s")"
}

func jiraTagTone(
    name: String,
    categoryKey: String,
    isOpen: Bool,
    isStale: Bool
) -> SemanticTagTone {
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if ["abandon", "bloqu", "blocked", "cancel"].contains(where: normalizedName.contains) {
        return .critical
    }
    if ["on prod", "prêt", "pret", "ready"].contains(where: normalizedName.contains) {
        return .positive
    }
    if isOpen && isStale {
        return .attention
    }
    switch categoryKey {
    case "done":
        return .positive
    case "new":
        return .neutral
    default:
        return .attention
    }
}
