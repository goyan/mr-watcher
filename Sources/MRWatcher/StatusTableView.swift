import SwiftUI

/// Callbacks de la table — la vue ne connaît ni `StateStore`, ni `Task`, ni `NSAlert` :
/// l'orchestration reste dans `StatusView`. `rebase`/`dismissMerged` (config `.author`)
/// et `approve`/`dismissReview` (config `.reviewer`) sont optionnels : chaque mode ne
/// fournit que ce qu'il utilise, plutôt que des closures no-op de complaisance.
struct StatusTableCallbacks {
    let openURL: (String) -> Void
    let refresh: (MRKey) -> Void
    let playAction: (MRKey, ManualPipelineAction) -> Void
    let rebase: ((MRSummary) -> Void)?
    let dismissMerged: ((MRKey) -> Void)?
    let approve: ((MRSummary) -> Void)?
    let dismissReview: ((MRKey) -> Void)?
}

/// Composant bête, deux configurations (plan D3) : `.author` (Mes MRs — sections
/// Ouvertes/Mergées, colonnes Fils/Appro/Retard/Âge) et `.reviewer` (Mes revues/À revoir —
/// liste plate déjà filtrée par chip, colonnes Auteur/Votre implication). `mrLookup` est
/// nécessaire pour `/rebase` et `Approuver` (les NSAlert de confirmation ont besoin du
/// `MRSummary` complet, que le modèle de présentation ne porte pas).
struct StatusTableView: View {
    enum Layout: Equatable {
        case author
        /// `showsDismiss` : uniquement « Mes revues » — jamais « À revoir » (comportement actuel).
        case reviewer(showsDismiss: Bool)
    }

    let layout: Layout
    let openRows: [MRRowModel]
    let mergedRows: [MergedRowModel]
    let mrLookup: [MRKey: MRSummary]
    /// Base de l'URL Jira (`ConfigManager.jiraBaseURL`), sans slash final. Vide tant
    /// que l'utilisateur ne l'a pas renseignée : le ticket reste alors affiché mais
    /// n'est plus un lien (ni bouton, ni curseur de lien, ni tooltip) — on n'invente
    /// pas l'URL d'un employeur particulier.
    let jiraBaseURL: String
    let refreshingKeys: Set<MRKey>
    let manualActions: [MRKey: [ManualPipelineAction]]
    let launchingJobIds: Set<Int>
    let callbacks: StatusTableCallbacks

    @State private var hoveredRow: MRKey?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            switch layout {
            case .author:
                // Deux `Section` distinctes, pas une seule : l'en-tête de colonnes
                // annonce les colonnes d'« Ouvertes », pas celles — différentes — de
                // « Récemment mergées ». Chacune épingle son propre header (bug §2).
                if !openRows.isEmpty {
                    Section {
                        ForEach(openRows) { row in
                            openRowView(row)
                            Divider().padding(.horizontal, DesignTokens.windowHorizontalPadding)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 0) {
                            sectionHeader("Ouvertes (\(openRows.count))")
                            columnHeader
                        }
                        .background(.background)
                    }
                }

                if !mergedRows.isEmpty {
                    Section {
                        ForEach(mergedRows) { row in
                            mergedRowView(row)
                            Divider().padding(.horizontal, DesignTokens.windowHorizontalPadding)
                        }
                    } header: {
                        sectionHeader("Récemment mergées (\(mergedRows.count))")
                            .background(.background)
                    }
                }
            case .reviewer(let showsDismiss):
                Section {
                    ForEach(openRows) { row in
                        reviewerRowView(row, showsDismiss: showsDismiss)
                        Divider().padding(.horizontal, DesignTokens.windowHorizontalPadding)
                    }
                } header: {
                    reviewerColumnHeader
                }
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: DesignTokens.columnGutter) {
            Color.clear.frame(width: DesignTokens.railWidth)
            Text("MR")
                .frame(width: StatusColumn.mr, alignment: .leading)
            Text("Titre")
                .frame(minWidth: StatusColumn.titleMinWidth, maxWidth: DesignTokens.titleMaxWidth, alignment: .leading)
            // L'excédent de largeur va ici, pas dans la cellule Titre (bug §3) : les
            // colonnes chiffrées restent groupées et collées à droite.
            Spacer(minLength: 0)
            Text("État")
                .frame(width: StatusColumn.state, alignment: .leading)
            Text("Fils")
                .frame(width: StatusColumn.threads, alignment: .trailing)
            Text("Appro")
                .frame(width: StatusColumn.approvals, alignment: .trailing)
            Text("Retard")
                .frame(width: StatusColumn.diverged, alignment: .trailing)
            Text("Âge")
                .frame(width: StatusColumn.age, alignment: .trailing)
            Text("Actions")
                .frame(width: StatusColumn.actions, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, DesignTokens.windowHorizontalPadding)
        .frame(minHeight: DesignTokens.columnHeaderMinHeight)
        .background(.background)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.windowHorizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 6)
    }

    // MARK: - Ligne ouverte

    @ViewBuilder
    private func openRowView(_ row: MRRowModel) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.columnGutter) {
            RoundedRectangle(cornerRadius: DesignTokens.railWidth / 2)
                .fill(row.state.tone.semanticTagTone.foreground)
                .frame(width: DesignTokens.railWidth)

            mrCell(iidLabel: row.iidLabel, webUrl: row.webUrl)
                .frame(width: StatusColumn.mr, alignment: .leading)

            titleCell(row)
                .frame(minWidth: StatusColumn.titleMinWidth, maxWidth: DesignTokens.titleMaxWidth, alignment: .leading)

            Spacer(minLength: 0)

            stateTag(row.state, pipelineWebUrl: row.pipelineWebUrl)
                .frame(width: StatusColumn.state, alignment: .leading)

            figureCell(row.unresolvedThreadsLabel, accessibilityPrefix: "Fils non résolus", color: .secondary)
                .frame(width: StatusColumn.threads, alignment: .trailing)

            figureCell(row.approvalsLabel, accessibilityPrefix: "Approbations", color: SemanticTagTone.positive.foreground)
                .frame(width: StatusColumn.approvals, alignment: .trailing)

            figureCell(row.divergedLabel, accessibilityPrefix: "Retard", color: SemanticTagTone.attention.foreground)
                .frame(width: StatusColumn.diverged, alignment: .trailing)

            figureCell(row.ageLabel, accessibilityPrefix: "Âge", color: .secondary)
                .frame(width: StatusColumn.age, alignment: .trailing)

            openActionsCell(row)
                .frame(width: StatusColumn.actions, alignment: .trailing)
        }
        .padding(.horizontal, DesignTokens.windowHorizontalPadding)
        .padding(.vertical, DesignTokens.rowVerticalPadding)
        .frame(minHeight: DesignTokens.openRowMinHeight)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.tagCornerRadius)
                .fill(hoveredRow == row.key ? DesignTokens.rowHoverFill : .clear)
        }
        .contentShape(Rectangle())
        .onHover { isHovering in
            hoveredRow = isHovering ? row.key : nil
        }
        // Résumé VoiceOver complet de la ligne (identifiant, titre, état, chiffres) —
        // les boutons internes restent atteignables individuellement (« interagir
        // avec le groupe »), .contain ne les fusionne pas en un bloc muet.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(openRowAccessibilitySummary(row))
    }

    private func openRowAccessibilitySummary(_ row: MRRowModel) -> String {
        var parts = [
            "Merge request \(row.iidLabel)",
            row.displayTitle,
            "État : \(row.state.label)"
        ]
        if let approvalsLabel = row.approvalsLabel {
            parts.append("Approbations : \(approvalsLabel)")
        }
        if let divergedLabel = row.divergedLabel {
            parts.append("Retard : \(divergedLabel) commits")
        }
        if let unresolvedThreadsLabel = row.unresolvedThreadsLabel {
            parts.append("Fils non résolus : \(unresolvedThreadsLabel)")
        }
        parts.append("Âge : \(row.ageLabel)")
        if row.isDraft {
            parts.append("Draft")
        }
        return parts.joined(separator: ", ")
    }

    /// Cible unique sur toute la cellule (correctif ergonomie : deux liens empilés —
    /// `!IID` et le ticket — dans 65 pt de large ne laissaient aucune marge de clic ;
    /// mesuré via l'API Accessibilité, la cellule était pleine, pas seulement étroite).
    /// Le ticket a rejoint le tag Jira en ligne 2 de la cellule Titre (`ticketTag`).
    private func mrCell(iidLabel: String, webUrl: String) -> some View {
        Button {
            callbacks.openURL(webUrl)
        } label: {
            Text(verbatim: iidLabel)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Ouvrir \(iidLabel) dans GitLab")
        .immediateTooltip("Ouvrir \(iidLabel) dans GitLab")
        .accessibilityLabel("Ouvrir la merge request \(iidLabel) dans GitLab")
    }

    /// `nil` tant que `jiraBaseURL` n'est pas renseignée — on n'invente pas une URL.
    private func jiraURL(for ticket: String) -> String? {
        guard !jiraBaseURL.isEmpty else { return nil }
        return "\(jiraBaseURL)/browse/\(ticket)"
    }

    @ViewBuilder
    private func titleCell(_ row: MRRowModel) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.cellGap) {
            Button {
                callbacks.openURL(row.webUrl)
            } label: {
                Text(row.displayTitle)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(row.displayTitle)
            .immediateTooltip(row.displayTitle)
            .accessibilityLabel("Ouvrir la merge request \(row.iidLabel), \(row.displayTitle), dans GitLab")

            HStack(spacing: DesignTokens.cellGap) {
                if row.isDraft {
                    SemanticTag(title: "Draft", systemImage: "pencil", tone: .neutral)
                }
                ticketTag(ticket: row.ticket, jira: row.jira, isJiraLoading: row.isJiraLoading)
            }
        }
    }

    @ViewBuilder
    private func openActionsCell(_ row: MRRowModel) -> some View {
        HStack(spacing: DesignTokens.cellGap + 2) {
            Spacer(minLength: 0)

            actionIcon(
                systemImage: "arrow.clockwise",
                help: "Actualiser \(row.iidLabel)",
                isLoading: refreshingKeys.contains(row.key)
            ) {
                callbacks.refresh(row.key)
            }

            ForEach(manualActions[row.key] ?? []) { action in
                actionIcon(
                    systemImage: action.kind.systemImage,
                    help: "\(action.kind.title) pour \(row.iidLabel)",
                    isLoading: launchingJobIds.contains(action.jobId)
                ) {
                    callbacks.playAction(row.key, action)
                }
            }

            // Masqué sur conflit : `hasConflicts` brut, jamais un test sur le libellé
            // affiché (un libellé traduit ou reformulé masquerait silencieusement la règle).
            if let divergedCount = row.divergedCount,
               divergedCount > 0,
               !row.hasConflicts,
               let mr = mrLookup[row.key] {
                actionIcon(
                    systemImage: "arrow.triangle.2.circlepath",
                    help: "Lancer /rebase pour \(row.iidLabel) (\(divergedCount) commit\(divergedCount == 1 ? "" : "s") de retard)"
                ) {
                    callbacks.rebase?(mr)
                }
            }
        }
    }

    // MARK: - Ligne mergée

    @ViewBuilder
    private func mergedRowView(_ row: MergedRowModel) -> some View {
        HStack(alignment: .center, spacing: DesignTokens.columnGutter) {
            Color.clear.frame(width: DesignTokens.railWidth)

            mrCell(iidLabel: row.iidLabel, webUrl: row.webUrl)
                .frame(width: MergedColumn.mr, alignment: .leading)

            Button {
                callbacks.openURL(row.webUrl)
            } label: {
                Text(row.displayTitle)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(row.displayTitle)
            .immediateTooltip(row.displayTitle)
            .accessibilityLabel("Ouvrir la merge request \(row.iidLabel), \(row.displayTitle), dans GitLab")
            .frame(minWidth: MergedColumn.titleMinWidth, maxWidth: .infinity, alignment: .leading)

            ticketTag(ticket: row.ticket, jira: row.jira, isJiraLoading: false)
                .frame(width: MergedColumn.jira, alignment: .leading)

            Text(row.dateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)

            actionIcon(
                systemImage: "xmark",
                help: "Retirer \(row.iidLabel) de la liste"
            ) {
                callbacks.dismissMerged?(row.key)
            }
            .frame(width: MergedColumn.actions, alignment: .trailing)
        }
        .padding(.horizontal, DesignTokens.windowHorizontalPadding)
        .padding(.vertical, DesignTokens.rowVerticalPadding)
        .frame(minHeight: DesignTokens.mergedRowMinHeight)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.tagCornerRadius)
                .fill(hoveredRow == row.key ? DesignTokens.rowHoverFill : .clear)
        }
        .contentShape(Rectangle())
        .onHover { isHovering in
            hoveredRow = isHovering ? row.key : nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(mergedRowAccessibilitySummary(row))
    }

    private func mergedRowAccessibilitySummary(_ row: MergedRowModel) -> String {
        var parts = ["Merge request \(row.iidLabel)", row.displayTitle]
        if let jira = row.jira {
            parts.append("Statut Jira : \(jira.label)")
        }
        parts.append(row.dateLabel)
        return parts.joined(separator: ", ")
    }

    // MARK: - Ligne reviewer

    private var reviewerColumnHeader: some View {
        HStack(spacing: DesignTokens.columnGutter) {
            Color.clear.frame(width: DesignTokens.railWidth)
            Text("MR")
                .frame(width: ReviewColumn.mr, alignment: .leading)
            Text("Titre")
                .frame(minWidth: ReviewColumn.titleMinWidth, maxWidth: DesignTokens.titleMaxWidth, alignment: .leading)
            // Bug §3 : l'excédent va ici, pas dans la cellule Titre.
            Spacer(minLength: 0)
            Text("Auteur")
                .frame(width: ReviewColumn.author, alignment: .leading)
            Text("État")
                .frame(width: ReviewColumn.state, alignment: .leading)
            Text("Votre implication")
                .frame(width: ReviewColumn.implication, alignment: .leading)
            Text("Actions")
                .frame(width: ReviewColumn.actions, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, DesignTokens.windowHorizontalPadding)
        .frame(minHeight: DesignTokens.columnHeaderMinHeight)
        .background(.background)
    }

    @ViewBuilder
    private func reviewerRowView(_ row: MRRowModel, showsDismiss: Bool) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.columnGutter) {
            RoundedRectangle(cornerRadius: DesignTokens.railWidth / 2)
                .fill(row.state.tone.semanticTagTone.foreground)
                .frame(width: DesignTokens.railWidth)

            mrCell(iidLabel: row.iidLabel, webUrl: row.webUrl)
                .frame(width: ReviewColumn.mr, alignment: .leading)

            reviewerTitleCell(row)
                .frame(minWidth: ReviewColumn.titleMinWidth, maxWidth: DesignTokens.titleMaxWidth, alignment: .leading)

            Spacer(minLength: 0)

            Text(row.authorShortName ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: ReviewColumn.author, alignment: .leading)
                .accessibilityLabel("Auteur : \(row.authorShortName ?? "inconnu")")

            stateTag(row.state, pipelineWebUrl: row.pipelineWebUrl)
                .frame(width: ReviewColumn.state, alignment: .leading)

            implicationCell(row)
                .frame(width: ReviewColumn.implication, alignment: .leading)

            reviewerActionsCell(row, showsDismiss: showsDismiss)
                .frame(width: ReviewColumn.actions, alignment: .trailing)
        }
        .padding(.horizontal, DesignTokens.windowHorizontalPadding)
        .padding(.vertical, DesignTokens.rowVerticalPadding)
        .frame(minHeight: DesignTokens.openRowMinHeight)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.tagCornerRadius)
                .fill(hoveredRow == row.key ? DesignTokens.rowHoverFill : .clear)
        }
        .contentShape(Rectangle())
        .onHover { isHovering in
            hoveredRow = isHovering ? row.key : nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(reviewerRowAccessibilitySummary(row))
    }

    private func reviewerRowAccessibilitySummary(_ row: MRRowModel) -> String {
        var parts = ["Merge request \(row.iidLabel)", row.displayTitle]
        if let authorName = row.authorShortName {
            parts.append("Auteur : \(authorName)")
        }
        parts.append("État : \(row.state.label)")
        if let primaryLabel = row.implication.primaryLabel {
            parts.append("Implication : \(primaryLabel)")
        }
        if let secondaryLabel = row.implication.secondaryLabel {
            parts.append(secondaryLabel)
        }
        if row.implication.claudeLabel != nil {
            parts.append("Approuvée par Claude")
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func reviewerTitleCell(_ row: MRRowModel) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.cellGap) {
            Button {
                callbacks.openURL(row.webUrl)
            } label: {
                Text(row.displayTitle)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(row.displayTitle)
            .immediateTooltip(row.displayTitle)
            .accessibilityLabel("Ouvrir la merge request \(row.iidLabel), \(row.displayTitle), dans GitLab")

            HStack(spacing: DesignTokens.cellGap) {
                ticketTag(ticket: row.ticket, jira: row.jira, isJiraLoading: row.isJiraLoading)
                // Le retard n'est pas une colonne en revue (correctif plan §9.5) : méta
                // discrète non teintée, pas de pastille — je ne rebase pas la MR d'un autre.
                if let divergedLabel = row.divergedLabel, let divergedCount = row.divergedCount {
                    Text("\(divergedLabel) \(divergedCount == 1 ? "retard" : "retards")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if row.isDraft {
                    SemanticTag(title: "Draft", systemImage: "pencil", tone: .neutral)
                }
            }
        }
    }

    @ViewBuilder
    private func implicationCell(_ row: MRRowModel) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.cellGap) {
            if let primary = row.implication.primary {
                implicationLineView(primary, webUrl: row.webUrl)
            }
            HStack(spacing: DesignTokens.cellGap) {
                if let secondary = row.implication.secondary {
                    implicationLineView(secondary, webUrl: row.webUrl)
                }
                if let claudeLabel = row.implication.claudeLabel {
                    Text(claudeLabel)
                        .font(.caption)
                        .foregroundStyle(SemanticTagTone.positive.foreground)
                }
            }
        }
    }

    /// Une ligne de la cellule Implication : `label`/`tone`/`noteId` viennent groupés
    /// de `ImplicationLine` (StatusPresentation.swift) — jamais redérivés ici. Pas de
    /// lien si l'ancre est `nil` (comportement actuel, ex. « Approuvée ✓ »). Cible
    /// étendue à toute la largeur de la colonne (`maxWidth: .infinity` + `contentShape`,
    /// correctif ergonomie) — sans fusionner primaire et secondaire, qui restent deux
    /// lignes/ancres distinctes portées par deux appels séparés.
    @ViewBuilder
    private func implicationLineView(_ line: ImplicationLine, webUrl: String) -> some View {
        if let noteId = line.noteId {
            Button {
                callbacks.openURL("\(webUrl)#note_\(noteId)")
            } label: {
                Text(line.label)
                    .font(.caption)
                    .foregroundStyle(line.tone.semanticTagTone.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ouvrir le fil dans GitLab")
            .immediateTooltip("Ouvrir le fil dans GitLab")
        } else {
            Text(line.label)
                .font(.caption)
                .foregroundStyle(line.tone.semanticTagTone.foreground)
        }
    }

    @ViewBuilder
    private func reviewerActionsCell(_ row: MRRowModel, showsDismiss: Bool) -> some View {
        HStack(spacing: DesignTokens.cellGap + 2) {
            Spacer(minLength: 0)

            actionIcon(
                systemImage: "arrow.clockwise",
                help: "Actualiser \(row.iidLabel)",
                isLoading: refreshingKeys.contains(row.key)
            ) {
                callbacks.refresh(row.key)
            }

            ForEach(manualActions[row.key] ?? []) { action in
                actionIcon(
                    systemImage: action.kind.systemImage,
                    help: "\(action.kind.title) pour \(row.iidLabel)",
                    isLoading: launchingJobIds.contains(action.jobId)
                ) {
                    callbacks.playAction(row.key, action)
                }
            }

            // Toujours visible, désactivé si le gate échoue : la position ne bouge
            // jamais d'une ligne à l'autre (contrairement à l'ancien comportement,
            // qui retirait le bouton — changement voulu, cf. étape 3).
            Button {
                if let mr = mrLookup[row.key] {
                    callbacks.approve?(mr)
                }
            } label: {
                // fixedSize : ce bouton ne doit jamais tronquer son texte (seule action
                // à libellé) — quitte à ce que la ligne déborde légèrement dans le cas
                // le plus chargé (5 slots) à la largeur plancher de la fenêtre.
                Text("Approuver")
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!row.canApprove)
            .help("Approuver \(row.iidLabel) dans GitLab")
            .immediateTooltip("Approuver \(row.iidLabel) dans GitLab")
            .accessibilityLabel("Approuver la merge request \(row.iidLabel) dans GitLab")

            if showsDismiss {
                actionIcon(systemImage: "xmark", help: "Masquer \(row.iidLabel) de mes revues") {
                    callbacks.dismissReview?(row.key)
                }
            }
        }
    }

    // MARK: - Cellules partagées

    @ViewBuilder
    private func figureCell(_ label: String?, accessibilityPrefix: String, color: Color) -> some View {
        // Aucun placeholder, pas même un tiret : une donnée absente laisse la cellule vide.
        if let label {
            Text(label)
                .font(.callout.monospacedDigit())
                .foregroundStyle(color)
                .accessibilityLabel("\(accessibilityPrefix) : \(label)")
        } else {
            Color.clear
                .accessibilityHidden(true)
        }
    }

    /// Pastille État — cliquable vers `headPipeline.webUrl` uniquement quand l'état
    /// affiché vient réellement d'une branche pipeline (`state.isPipelineState`), pas
    /// d'un test sur le libellé. Le tooltip `state.detail` reste dans les deux cas.
    @ViewBuilder
    private func stateTag(_ state: DerivedState, pipelineWebUrl: String?) -> some View {
        let tag = SemanticTag(
            title: state.label,
            systemImage: stateSystemImage(for: state.label),
            tone: state.tone.semanticTagTone
        )
        if state.isPipelineState, let pipelineWebUrl {
            Button {
                callbacks.openURL(pipelineWebUrl)
            } label: {
                tag
            }
            .buttonStyle(.plain)
            .help(state.detail)
            .immediateTooltip(state.detail)
            .accessibilityLabel("\(state.label). Ouvrir le pipeline dans GitLab.")
        } else {
            tag
                .help(state.detail)
                .immediateTooltip(state.detail)
        }
    }

    /// Contenu (hors vue) de la pastille ticket+statut : calculé à part d'un
    /// `@ViewBuilder`, qui n'accepte pas un `if/else` ne construisant que des
    /// affectations sans vue.
    private func ticketTagContent(
        ticket: String,
        jira: JiraStatusDisplay?,
        isJiraLoading: Bool
    ) -> (label: String, tone: RowTone, systemImage: String) {
        if let jira {
            return ("\(ticket) · \(jira.label)", jira.tone, jiraSystemImage(for: jira))
        }
        if isJiraLoading {
            return ("\(ticket) · Jira...", .neutral, "ticket")
        }
        return (ticket, .neutral, "ticket")
    }

    /// Fusionne le ticket et son statut Jira dans une seule pastille cliquable
    /// (`PROD-30065 · Code review`), motif déjà utilisé par le popover
    /// (`MenuBarView.jiraButton`) — une seule cible plutôt que deux liens empilés
    /// (`!IID` / ticket) qui ne laissaient aucune marge de clic. Statut sans ticket :
    /// impossible par construction (le statut vient du ticket), pas de cas à inventer.
    @ViewBuilder
    private func ticketTag(ticket: String?, jira: JiraStatusDisplay?, isJiraLoading: Bool) -> some View {
        if let ticket {
            let content = ticketTagContent(ticket: ticket, jira: jira, isJiraLoading: isJiraLoading)
            let label = content.label
            let tone = content.tone
            let systemImage = content.systemImage

            if let url = jiraURL(for: ticket) {
                Button {
                    callbacks.openURL(url)
                } label: {
                    SemanticTag(title: label, systemImage: systemImage, tone: tone.semanticTagTone)
                }
                .buttonStyle(.plain)
                .help("Ouvrir \(ticket) dans Jira")
                .immediateTooltip("Ouvrir \(ticket) dans Jira")
            } else {
                // Pas d'URL Jira configurée : la pastille reste affichée, mais sans
                // lien — ni bouton, ni curseur de lien, ni tooltip (pas de contrôle
                // qui a l'air actif et ne réagit pas).
                SemanticTag(title: label, systemImage: systemImage, tone: tone.semanticTagTone)
            }
        }
    }

    private func actionIcon(
        systemImage: String,
        help: String,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
            }
            .frame(width: 16, height: 16)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isLoading)
        .help(help)
        .immediateTooltip(help)
        .accessibilityLabel(help)
    }

    private func stateSystemImage(for label: String) -> String {
        switch label {
        case "Conflit": "exclamationmark.triangle.fill"
        case "CI KO": "xmark.circle.fill"
        case "Rebase requis": "arrow.down.circle.fill"
        case "CI en cours": "arrow.triangle.2.circlepath"
        case "CI attente": "clock.fill"
        case "En attente de revue": "hand.thumbsup"
        case "Prête à merger": "checkmark.circle.fill"
        default: "circle"
        }
    }

    private func jiraSystemImage(for jira: JiraStatusDisplay) -> String {
        if jira.isStale { return "exclamationmark.triangle.fill" }
        return switch jira.tone {
        case .positive: "checkmark.circle.fill"
        case .neutral: "circle"
        default: "clock.fill"
        }
    }
}
