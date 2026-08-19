import SwiftUI

/// Rangée de chips de filtre (plan D2). Prédicats et compteurs viennent de
/// `StatusPresentation.swift` (`ReviewChip`, `chipCounts`) — cette vue ne fait
/// qu'afficher des valeurs déjà calculées et notifier la sélection.
///
/// Une chip à compteur zéro reste affichée, grisée et désactivée : les positions
/// ne bougent jamais, l'œil apprend leur emplacement.
struct FilterChipsView: View {
    let chips: [ReviewChip]
    let counts: [ReviewChip: Int]
    @Binding var selection: ReviewChip

    var body: some View {
        HStack(spacing: 7) {
            ForEach(chips, id: \.self) { chip in
                let count = counts[chip] ?? 0
                FilterChip(
                    title: chip.title,
                    count: count,
                    isSelected: selection == chip
                ) {
                    selection = chip
                }
                .disabled(count == 0)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.windowHorizontalPadding)
        .frame(minHeight: DesignTokens.chipRowMinHeight, alignment: .leading)
    }
}

private struct FilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    private var accessibilitySummary: String {
        "\(title), \(count)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                // verbatim : un Int interpolé dans un Text("...") littéral construit une
                // LocalizedStringKey, qui applique le séparateur de milliers français
                // (c'est le bug déjà payé sur !IID — cf. plan §9.3a). Sans risque tant
                // que le compteur reste petit, mais on ferme la classe partout.
                Text(verbatim: "\(count)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.caption)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.38)
        // Idem : un littéral interpolé passé à accessibilityLabel résout aussi vers
        // LocalizedStringKey — construire la chaîne en amont évite l'ambiguïté.
        .accessibilityLabel(accessibilitySummary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
