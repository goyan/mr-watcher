import SwiftUI

// Tokens visuels partagés par la table à colonnes (plan §2). Calibrés en mode
// sombre d'abord — c'est le mode réellement utilisé. `RowTone` (StatusPresentation.swift,
// Foundation pur) est mappé vers `SemanticTagTone`/`Color` ici, côté vue.

enum DesignTokens {
    /// Survol de ligne — unifie les 0.10/0.16 dispersés dans l'ancien code.
    static let rowHoverFill = Color.secondary.opacity(0.10)
    /// Survol de contrôle (bouton, icône d'action) — unifie les 0.18/0.20.
    static let controlHoverFill = Color.secondary.opacity(0.18)

    static let railWidth: CGFloat = 3
    static let tagCornerRadius: CGFloat = 4
    static let controlCornerRadius: CGFloat = 6

    static let columnGutter: CGFloat = 12
    static let windowHorizontalPadding: CGFloat = 16
    static let rowVerticalPadding: CGFloat = 8
    static let cellGap: CGFloat = 4

    // Toujours minHeight, jamais height : Dynamic Type pousse, ne clippe pas.
    static let openRowMinHeight: CGFloat = 48
    static let mergedRowMinHeight: CGFloat = 36
    static let columnHeaderMinHeight: CGFloat = 28
    static let chipRowMinHeight: CGFloat = 36

    /// Plafond de la colonne Titre (bug §3 étape 4) : au-delà, l'excédent va dans un
    /// `Spacer()` placé juste après elle, pas dans la cellule — sinon le titre se
    /// détache visuellement des colonnes de droite en fenêtre large (observé à 1400 pt).
    static let titleMaxWidth: CGFloat = 620

    /// Largeur minimale réelle de la fenêtre : le maximum des deux configurations de
    /// table (`StatusColumn`/`ReviewColumn`), chacune sommant ses propres colonnes —
    /// jamais un nombre magique recopié à la main (bug §1 étape 4 : `minWidth: 1000`
    /// codé en dur ne suivait pas le budget réel des colonnes, qui le dépassait déjà).
    /// Si une colonne s'élargit plus tard, cette valeur suit automatiquement.
    static var tableMinWidth: CGFloat {
        max(StatusColumn.minimumTableWidth, ReviewColumn.minimumTableWidth)
    }
}

/// Largeurs de colonnes de la table « Mes MRs », partagées entre l'en-tête et les
/// lignes — c'est ce qui garantit l'alignement vertical entre les deux.
enum StatusColumn {
    static let mr: CGFloat = 92
    static let titleMinWidth: CGFloat = 280
    static let state: CGFloat = 128
    static let threads: CGFloat = 44
    static let approvals: CGFloat = 56
    static let diverged: CGFloat = 60
    static let age: CGFloat = 44
    static let actions: CGFloat = 150

    /// rail, MR, Titre, État, Fils, Appro, Retard, Âge, Actions.
    private static let columnCount = 9

    /// Somme réelle des colonnes fixes (Titre à son plancher) + gouttières + padding
    /// horizontal de fenêtre. Voir `DesignTokens.tableMinWidth`.
    static var minimumTableWidth: CGFloat {
        let fixedColumnsTotal = DesignTokens.railWidth + mr + titleMinWidth + state
            + threads + approvals + diverged + age + actions
        return fixedColumnsTotal
            + DesignTokens.columnGutter * CGFloat(columnCount - 1)
            + DesignTokens.windowHorizontalPadding * 2
    }
}

/// Largeurs de colonnes de la ligne mergée simplifiée (pas de rail, pas d'en-tête
/// dédié — cf. maquette étape 0, section « Récemment mergées »).
enum MergedColumn {
    static let mr: CGFloat = 92
    static let titleMinWidth: CGFloat = 280
    static let jira: CGFloat = 128
    static let actions: CGFloat = 30
}

/// Largeurs de colonnes de la table « Mes revues » / « À revoir » — deuxième
/// configuration du même composant `StatusTableView` (focus dette de review, pas
/// santé de pipeline : pas de Fils/Appro/Retard, mais Auteur + Votre implication).
enum ReviewColumn {
    // Mesuré à l'écran (Accessibility API, données réelles) plutôt que repris tel quel
    // du budget plan §D5 : 92+240(titre plancher)+92+132+154+202 dépassait déjà la
    // largeur de fenêtre avant même de corriger la troncature d'« Approuver ». MR et
    // Implication avaient une marge inutilisée (contenu réel ≤ 62 pt et ≤ 90 pt) —
    // récupérée pour financer une colonne Actions qui ne tronque plus le seul bouton
    // à libellé sur une ligne à 5 slots (↻ + ▶ + ✦ + Approuver + ✕ ≈ 212 hors marges).
    static let mr: CGFloat = 65
    static let titleMinWidth: CGFloat = 240
    static let author: CGFloat = 92
    static let state: CGFloat = 132
    static let implication: CGFloat = 120
    static let actions: CGFloat = 230

    /// rail, MR, Titre, Auteur, État, Implication, Actions.
    private static let columnCount = 7

    /// Voir `StatusColumn.minimumTableWidth` / `DesignTokens.tableMinWidth`.
    static var minimumTableWidth: CGFloat {
        let fixedColumnsTotal = DesignTokens.railWidth + mr + titleMinWidth + author
            + state + implication + actions
        return fixedColumnsTotal
            + DesignTokens.columnGutter * CGFloat(columnCount - 1)
            + DesignTokens.windowHorizontalPadding * 2
    }
}

extension RowTone {
    var semanticTagTone: SemanticTagTone {
        switch self {
        case .critical: .critical
        case .attention: .attention
        case .neutral: .neutral
        case .positive: .positive
        case .accent: .accent
        }
    }
}
