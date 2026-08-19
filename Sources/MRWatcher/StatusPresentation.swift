import Foundation

// Modèle de présentation pur pour la fenêtre principale (table à colonnes).
// Aucune dépendance SwiftUI : testable sans UI. Le mapping RowTone → Color
// vit côté vue (StatusTableView), pas ici.

enum PresentationContext {
    case author
    case reviewer
}

enum RowTone {
    case critical
    case attention
    case neutral
    case positive
    case accent
}

struct DerivedState: Equatable {
    let label: String
    let tone: RowTone
    let detail: String
    /// Vrai quand le libellé résolu vient d'une branche pipeline (CI KO/en cours/attente) —
    /// distinct d'un simple test sur `label` (qui casserait silencieusement si le texte
    /// change), pour permettre à la vue de savoir sans dupliquer la machine d'états
    /// si la pastille doit pointer vers `headPipeline.webUrl`.
    let isPipelineState: Bool
}

struct JiraStatusDisplay: Equatable {
    let label: String
    let tone: RowTone
    let isStale: Bool
}

/// Une ligne cliquable de la cellule « Votre implication » : libellé + tonalité + ancre
/// GitLab optionnelle. Regroupe label/tone/noteId dans une seule source de vérité —
/// la vue ne redérive jamais la priorité pour choisir la couleur ou l'ancre à ouvrir
/// (même principe que `DerivedState.isPipelineState` : pas de re-décision côté vue).
struct ImplicationLine: Equatable {
    let label: String
    let tone: RowTone
    let noteId: Int?
}

struct Implication: Equatable {
    let revisitCount: Int
    let myThreadsCount: Int
    let otherThreadsCount: Int
    let isApprovedByMe: Bool
    let isApprovedByClaude: Bool
    let firstRevisitNoteId: Int?
    let firstMyThreadNoteId: Int?
    let firstOtherThreadNoteId: Int?

    /// Ligne 1 : « À revalider · N fils » (attention) sinon « N fils de vous » (accent)
    /// sinon « Approuvée ✓ » (positive) sinon vide.
    var primary: ImplicationLine? {
        if revisitCount > 0 {
            return ImplicationLine(
                label: "À revalider · \(revisitCount) fil\(revisitCount > 1 ? "s" : "")",
                tone: .attention,
                noteId: firstRevisitNoteId
            )
        }
        if myThreadsCount > 0 {
            return ImplicationLine(
                label: myThreadsCount > 1 ? "\(myThreadsCount) fils de vous" : "1 fil de vous",
                tone: .accent,
                noteId: firstMyThreadNoteId
            )
        }
        if isApprovedByMe {
            return ImplicationLine(label: "Approuvée ✓", tone: .positive, noteId: nil)
        }
        return nil
    }

    var primaryLabel: String? { primary?.label }

    /// Ligne 2 : « N autres » (attention), cliquable vers `firstOtherThreadNoteId`.
    var secondary: ImplicationLine? {
        guard otherThreadsCount > 0 else { return nil }
        return ImplicationLine(
            label: otherThreadsCount > 1 ? "\(otherThreadsCount) autres" : "1 autre",
            tone: .attention,
            noteId: firstOtherThreadNoteId
        )
    }

    var secondaryLabel: String? { secondary?.label }

    /// Ligne 2 : « Claude ✓ » si l'auto review a déjà approuvé.
    var claudeLabel: String? {
        isApprovedByClaude ? "Claude ✓" : nil
    }
}

enum Severity: Int, Comparable {
    // Contexte auteur (Mes MRs ouvertes).
    case authorBlocked
    case authorLate
    case authorOpenThreads
    case authorAwaitingApproval
    case authorReady

    // Contexte reviewer (Mes revues, À revoir).
    case reviewerNeedsRevisit
    case reviewerToReview
    case reviewerAwaitingAuthor
    case reviewerApproved

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ReviewChip: Hashable {
    case all
    case needsRevisit
    case myThreads
    case noReview
    case toReview
    case approved

    var title: String {
        switch self {
        case .all: "Tout"
        case .needsRevisit: "À revalider"
        case .myThreads: "Mes fils"
        case .noReview: "Sans revue"
        case .toReview: "To Review"
        case .approved: "Approuvées"
        }
    }
}

struct MRRowModel: Identifiable, Equatable {
    let key: MRKey
    let iid: Int
    let iidLabel: String
    let ticket: String?
    let projectName: String
    let displayTitle: String
    let authorShortName: String?
    let isDraft: Bool
    let hasConflicts: Bool
    let state: DerivedState
    let jira: JiraStatusDisplay?
    let isJiraLoading: Bool
    let divergedCount: Int?
    let divergedLabel: String?
    let approvalsLabel: String?
    let unresolvedThreadsLabel: String?
    let ageLabel: String
    let implication: Implication
    let canApprove: Bool
    let webUrl: String
    let pipelineWebUrl: String?
    let severity: Severity

    var id: MRKey { key }
}

struct MergedRowModel: Identifiable, Equatable {
    let key: MRKey
    let iidLabel: String
    let displayTitle: String
    let jira: JiraStatusDisplay?
    let dateLabel: String
    let webUrl: String

    var id: MRKey { key }
}

// MARK: - Machine d'états

/// Deux machines distinctes selon le contexte (premier match gagnant) — le retard
/// (`diverged > 0`) ne figure QUE dans la machine auteur : je ne rebase pas la MR
/// d'un autre en tant que reviewer (correctif plan §9.5).
func derivedState(
    mr: MRSummary,
    approvals: MRApprovals?,
    context: PresentationContext
) -> DerivedState {
    let detail = stateDetailSegments(mr: mr, approvals: approvals).joined(separator: " · ")
    let pipelineStatus = mr.headPipeline?.status
    let hasKnownDivergence = (mr.divergedCommitsCount ?? 0) > 0

    if mr.hasConflicts {
        return DerivedState(label: "Conflit", tone: .critical, detail: detail, isPipelineState: false)
    }
    if pipelineStatus == "failed" {
        return DerivedState(label: "CI KO", tone: .critical, detail: detail, isPipelineState: true)
    }
    if context == .author, hasKnownDivergence {
        return DerivedState(label: "Rebase requis", tone: .attention, detail: detail, isPipelineState: false)
    }
    if pipelineStatus == "running" {
        return DerivedState(label: "CI en cours", tone: .attention, detail: detail, isPipelineState: true)
    }
    if pipelineStatus == "pending" {
        return DerivedState(label: "CI attente", tone: .attention, detail: detail, isPipelineState: true)
    }
    if let approvals, approvals.given < approvals.required {
        return DerivedState(label: "En attente de revue", tone: .neutral, detail: detail, isPipelineState: false)
    }
    return DerivedState(label: "Prête à merger", tone: .positive, detail: detail, isPipelineState: false)
}

private func stateDetailSegments(mr: MRSummary, approvals: MRApprovals?) -> [String] {
    var segments: [String] = []
    if mr.hasConflicts {
        segments.append("Conflit")
    }
    switch mr.headPipeline?.status {
    case "failed": segments.append("CI KO")
    case "running": segments.append("CI en cours")
    case "pending": segments.append("CI attente")
    case "success": segments.append("CI OK")
    default: break
    }
    if let diverged = mr.divergedCommitsCount, diverged > 0 {
        segments.append(diverged == 1 ? "1 commit de retard" : "\(diverged) commits de retard")
    }
    if let approvals {
        segments.append("\(approvals.given)/\(approvals.required) approbations")
    }
    return segments
}

// MARK: - Gate Approuver

/// Porte à l'identique le prédicat de `StatusView.canApproveReview` (StatusView.swift:979).
/// `testsAreGreen` est évalué par l'appelant : la sémantique de repli reste dans `StateStore`.
func canApprove(
    mr: MRSummary,
    approvals: MRApprovals?,
    testsAreGreen: Bool
) -> Bool {
    guard mr.state == "opened",
          !mr.isDraft,
          testsAreGreen,
          let approvals else {
        return false
    }
    return approvals.myUnresolvedThreads == 0 && !approvals.isApprovedByMe
}

// MARK: - Gravité

private func authorSeverity(mr: MRSummary, approvals: MRApprovals?) -> Severity {
    if mr.hasConflicts || mr.headPipeline?.status == "failed" {
        return .authorBlocked
    }
    if let diverged = mr.divergedCommitsCount, diverged > 0 {
        return .authorLate
    }
    if let approvals, approvals.unresolvedThreads > 0 {
        return .authorOpenThreads
    }
    if let approvals, approvals.given < approvals.required {
        return .authorAwaitingApproval
    }
    return .authorReady
}

private func reviewerSeverity(approvals: MRApprovals?) -> Severity {
    guard let approvals else { return .reviewerToReview }
    if approvals.personalThreadsNeedingRevisit > 0 {
        return .reviewerNeedsRevisit
    }
    if !approvals.isApprovedByMe, approvals.myUnresolvedThreads == 0 {
        return .reviewerToReview
    }
    if approvals.myUnresolvedThreads > 0 {
        return .reviewerAwaitingAuthor
    }
    return .reviewerApproved
}

// MARK: - Chips

func matchesChip(
    _ chip: ReviewChip,
    approvals: MRApprovals?,
    jiraStatus: JiraIssueStatus?
) -> Bool {
    switch chip {
    case .all:
        return true
    case .needsRevisit:
        return (approvals?.personalThreadsNeedingRevisit ?? 0) > 0
    case .myThreads:
        return (approvals?.myUnresolvedThreads ?? 0) > 0
    case .noReview:
        guard let approvals else { return false }
        return approvals.given == 0 && !approvals.hasCurrentUserComment
    case .toReview:
        guard let jiraStatus else { return false }
        let normalized = jiraStatus.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["to review", "code review"].contains(normalized)
    case .approved:
        guard let approvals else { return false }
        return approvals.isApprovedByMe && approvals.myUnresolvedThreads == 0
    }
}

func chipCounts(
    for chips: [ReviewChip],
    mrs: [MRSummary],
    approvals: [MRKey: MRApprovals],
    jiraStatuses: [MRKey: JiraIssueStatus]
) -> [ReviewChip: Int] {
    var counts: [ReviewChip: Int] = [:]
    for chip in chips {
        counts[chip] = mrs.filter { mr in
            let key = MRKey(projectId: mr.projectId, iid: mr.iid)
            return matchesChip(chip, approvals: approvals[key], jiraStatus: jiraStatuses[key])
        }.count
    }
    return counts
}

// MARK: - Dérivés

private func extractTicket(from mr: MRSummary) -> String? {
    findTicket(in: mr.sourceBranch) ?? findTicket(in: mr.title)
}

private func findTicket(in value: String) -> String? {
    guard let range = value.range(of: #"PROD-\d+"#, options: .regularExpression) else {
        return nil
    }
    return String(value[range])
}

private func deriveProjectName(from mr: MRSummary) -> String {
    guard let url = URL(string: mr.webUrl) else { return "projet" }
    let segments = url.path.split(separator: "/")
    guard let dashIndex = segments.firstIndex(of: "-"), dashIndex > segments.startIndex else {
        return "projet"
    }
    return String(segments[segments.index(before: dashIndex)])
}

/// Retire un suffixe `(PROD-xxxxx)` / `[PROD-xxxxx]` / ` PROD-xxxxx` en fin de titre,
/// uniquement s'il correspond exactement au ticket déjà extrait — un ticket différent
/// reste affiché.
private func stripRedundantTicketSuffix(from title: String, ticket: String?) -> String {
    guard let ticket else { return title }
    let candidateSuffixes = ["(\(ticket))", "[\(ticket)]", " \(ticket)"]
    for suffix in candidateSuffixes where title.hasSuffix(suffix) {
        let stripped = String(title.dropLast(suffix.count))
        return stripped.trimmingCharacters(in: .whitespaces)
    }
    return title
}

private func ageLabel(since date: Date, now: Date) -> String {
    let hours = Int(now.timeIntervalSince(date) / 3_600)
    if hours < 1 { return "<1h" }
    if hours < 24 { return "\(hours)h" }
    return "\(hours / 24)j"
}

/// Borné : au-delà de 999, la colonne Retard affiche `999+` (plan §9.6) — la valeur
/// exacte reste disponible via `divergedCount` pour le tooltip.
private func divergedLabel(for count: Int?) -> String? {
    guard let count, count > 0 else { return nil }
    return count > 999 ? "999+" : "\(count)"
}

private func approvalsLabel(for approvals: MRApprovals?) -> String? {
    guard let approvals else { return nil }
    return "\(approvals.given)/\(approvals.required)"
}

private func unresolvedThreadsLabel(for approvals: MRApprovals?) -> String? {
    guard let approvals, approvals.unresolvedThreads > 0 else { return nil }
    return "\(approvals.unresolvedThreads)"
}

private func implication(from approvals: MRApprovals?) -> Implication {
    Implication(
        revisitCount: approvals?.personalThreadsNeedingRevisit ?? 0,
        myThreadsCount: approvals?.myUnresolvedThreads ?? 0,
        otherThreadsCount: approvals?.otherUnresolvedThreads ?? 0,
        isApprovedByMe: approvals?.isApprovedByMe ?? false,
        isApprovedByClaude: approvals?.isApprovedByClaude ?? false,
        firstRevisitNoteId: approvals?.firstPersonalThreadNeedingRevisitNoteId,
        firstMyThreadNoteId: approvals?.firstMyUnresolvedThreadNoteId,
        firstOtherThreadNoteId: approvals?.firstOtherUnresolvedThreadNoteId
    )
}

/// Copie pure (sans SwiftUI) de `jiraTagTone` (SemanticTag.swift) — le mapping vers
/// `SemanticTagTone`/`Color` reste côté vue, ce fichier n'importe pas SwiftUI.
private func jiraRowTone(name: String, categoryKey: String, isOpen: Bool, isStale: Bool) -> RowTone {
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

private func jiraStatusDisplay(for status: JiraIssueStatus, isOpen: Bool) -> JiraStatusDisplay {
    JiraStatusDisplay(
        label: status.name,
        tone: jiraRowTone(name: status.name, categoryKey: status.categoryKey, isOpen: isOpen, isStale: status.isStale),
        isStale: status.isStale
    )
}

// MARK: - Builder

private func makeRowModel(
    mr: MRSummary,
    key: MRKey,
    severity: Severity,
    approvals: MRApprovals?,
    jiraStatus: JiraIssueStatus?,
    isJiraLoading: Bool,
    testsAreGreen: Bool,
    context: PresentationContext,
    now: Date
) -> MRRowModel {
    let ticket = extractTicket(from: mr)
    return MRRowModel(
        key: key,
        iid: mr.iid,
        iidLabel: "!\(mr.iid)",
        ticket: ticket,
        projectName: deriveProjectName(from: mr),
        displayTitle: stripRedundantTicketSuffix(from: mr.title, ticket: ticket),
        authorShortName: mr.author?.shortDisplayName,
        isDraft: mr.isDraft,
        hasConflicts: mr.hasConflicts,
        state: derivedState(mr: mr, approvals: approvals, context: context),
        jira: jiraStatus.map { jiraStatusDisplay(for: $0, isOpen: true) },
        isJiraLoading: isJiraLoading,
        divergedCount: mr.divergedCommitsCount,
        divergedLabel: divergedLabel(for: mr.divergedCommitsCount),
        approvalsLabel: approvalsLabel(for: approvals),
        unresolvedThreadsLabel: unresolvedThreadsLabel(for: approvals),
        ageLabel: ageLabel(since: mr.createdAt, now: now),
        implication: implication(from: approvals),
        canApprove: canApprove(mr: mr, approvals: approvals, testsAreGreen: testsAreGreen),
        webUrl: mr.webUrl,
        pipelineWebUrl: mr.headPipeline?.webUrl,
        severity: severity
    )
}

/// Construit les lignes de la table pour les MRs **ouvertes** (`state == "opened"`),
/// triées par gravité selon le contexte. Les MRs mergées passent par `buildMergedRows`.
func buildRows(
    mrs: [MRSummary],
    approvals: [MRKey: MRApprovals],
    jiraStatuses: [MRKey: JiraIssueStatus],
    jiraLoadingKeys: Set<MRKey>,
    testsAreGreen: (MRKey) -> Bool,
    context: PresentationContext,
    now: Date
) -> [MRRowModel] {
    let ranked = mrs
        .filter { $0.state == "opened" }
        .map { mr -> (mr: MRSummary, key: MRKey, severity: Severity) in
            let key = MRKey(projectId: mr.projectId, iid: mr.iid)
            let mrApprovals = approvals[key]
            let severity = context == .author
                ? authorSeverity(mr: mr, approvals: mrApprovals)
                : reviewerSeverity(approvals: mrApprovals)
            return (mr, key, severity)
        }
        .sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity < rhs.severity
            }
            switch context {
            case .author:
                return lhs.mr.createdAt > rhs.mr.createdAt
            case .reviewer:
                return lhs.mr.createdAt < rhs.mr.createdAt
            }
        }

    return ranked.map { entry in
        makeRowModel(
            mr: entry.mr,
            key: entry.key,
            severity: entry.severity,
            approvals: approvals[entry.key],
            jiraStatus: jiraStatuses[entry.key],
            isJiraLoading: jiraLoadingKeys.contains(entry.key),
            testsAreGreen: testsAreGreen(entry.key),
            context: context,
            now: now
        )
    }
}

/// Construit les lignes de la section « Récemment mergées », triées par `mergedAt` décroissant.
func buildMergedRows(
    mrs: [MRSummary],
    jiraStatuses: [MRKey: JiraIssueStatus],
    now: Date
) -> [MergedRowModel] {
    mrs
        .filter { $0.state == "merged" }
        .sorted { ($0.mergedAt ?? $0.createdAt) > ($1.mergedAt ?? $1.createdAt) }
        .map { mr in
            let key = MRKey(projectId: mr.projectId, iid: mr.iid)
            let ticket = extractTicket(from: mr)
            let createdLabel = "Créée : \(ageLabel(since: mr.createdAt, now: now))"
            let dateLabel: String
            if let mergedAt = mr.mergedAt {
                dateLabel = "Mergée : \(ageLabel(since: mergedAt, now: now)) · \(createdLabel)"
            } else {
                dateLabel = createdLabel
            }
            return MergedRowModel(
                key: key,
                iidLabel: "!\(mr.iid)",
                displayTitle: stripRedundantTicketSuffix(from: mr.title, ticket: ticket),
                jira: jiraStatuses[key].map { jiraStatusDisplay(for: $0, isOpen: false) },
                dateLabel: dateLabel,
                webUrl: mr.webUrl
            )
        }
}
