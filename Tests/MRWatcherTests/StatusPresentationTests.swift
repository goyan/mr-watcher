import Foundation
import XCTest
@testable import MRWatcher

final class StatusPresentationTests: XCTestCase {

    // MARK: - Fixtures

    private func makeAuthor(username: String = "j.dupont", name: String? = "Jean Dupont") -> MRAuthor {
        MRAuthor(username: username, name: name)
    }

    private func makePipeline(status: String) -> EmbeddedPipeline {
        EmbeddedPipeline(id: 1, status: status, webUrl: "https://gitlab.example.test/pipelines/1")
    }

    private func makeMR(
        id: Int = 1,
        iid: Int = 57_020,
        projectId: Int = 10,
        title: String = "fix(plato): correction d'un bug",
        webUrl: String = "https://gitlab.example.test/millenium/-/merge_requests/1",
        notesCount: Int = 0,
        sourceBranch: String = "fix/PROD-30746-correction",
        isDraft: Bool = false,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        mergedAt: Date? = nil,
        headPipeline: EmbeddedPipeline? = nil,
        headSha: String? = "abc123",
        divergedCommitsCount: Int? = nil,
        hasConflicts: Bool = false,
        state: String = "opened",
        author: MRAuthor? = nil
    ) -> MRSummary {
        MRSummary(
            id: id,
            iid: iid,
            projectId: projectId,
            title: title,
            webUrl: webUrl,
            notesCount: notesCount,
            sourceBranch: sourceBranch,
            isDraft: isDraft,
            createdAt: createdAt,
            mergedAt: mergedAt,
            headPipeline: headPipeline,
            headSha: headSha,
            divergedCommitsCount: divergedCommitsCount,
            hasConflicts: hasConflicts,
            state: state,
            author: author
        )
    }

    private func makeApprovals(
        required: Int = 2,
        given: Int = 0,
        unresolvedThreads: Int = 0,
        myUnresolvedThreads: Int = 0,
        otherUnresolvedThreads: Int = 0,
        personalThreadsNeedingRevisit: Int = 0,
        firstMyUnresolvedThreadNoteId: Int? = nil,
        firstPersonalThreadNeedingRevisitNoteId: Int? = nil,
        firstOtherUnresolvedThreadNoteId: Int? = nil,
        isApprovedByMe: Bool = false,
        isApprovedByClaude: Bool = false,
        hasCurrentUserComment: Bool = false
    ) -> MRApprovals {
        MRApprovals(
            required: required,
            given: given,
            unresolvedThreads: unresolvedThreads,
            myUnresolvedThreads: myUnresolvedThreads,
            otherUnresolvedThreads: otherUnresolvedThreads,
            personalThreadsNeedingRevisit: personalThreadsNeedingRevisit,
            firstMyUnresolvedThreadNoteId: firstMyUnresolvedThreadNoteId,
            firstPersonalThreadNeedingRevisitNoteId: firstPersonalThreadNeedingRevisitNoteId,
            firstOtherUnresolvedThreadNoteId: firstOtherUnresolvedThreadNoteId,
            isApprovedByMe: isApprovedByMe,
            isApprovedByClaude: isApprovedByClaude,
            hasCurrentUserComment: hasCurrentUserComment
        )
    }

    // MARK: - 1. Gate Approuver (le test le plus critique)

    func testCanApproveTrueWhenAllConditionsMet() {
        let mr = makeMR(isDraft: false, state: "opened")
        let approvals = makeApprovals(myUnresolvedThreads: 0, isApprovedByMe: false)
        XCTAssertTrue(canApprove(mr: mr, approvals: approvals, testsAreGreen: true))
    }

    func testCanApproveFalseWhenDraft() {
        let mr = makeMR(isDraft: true, state: "opened")
        let approvals = makeApprovals()
        XCTAssertFalse(canApprove(mr: mr, approvals: approvals, testsAreGreen: true))
    }

    func testCanApproveFalseWhenMRClosed() {
        let mr = makeMR(isDraft: false, state: "closed")
        let approvals = makeApprovals()
        XCTAssertFalse(canApprove(mr: mr, approvals: approvals, testsAreGreen: true))
    }

    func testCanApproveFalseWhenMRMerged() {
        let mr = makeMR(isDraft: false, state: "merged")
        let approvals = makeApprovals()
        XCTAssertFalse(canApprove(mr: mr, approvals: approvals, testsAreGreen: true))
    }

    func testCanApproveFalseWhenTestsAreNotGreen() {
        let mr = makeMR(isDraft: false, state: "opened")
        let approvals = makeApprovals()
        XCTAssertFalse(canApprove(mr: mr, approvals: approvals, testsAreGreen: false))
    }

    func testCanApproveFalseWhenMyUnresolvedThreadsRemain() {
        let mr = makeMR(isDraft: false, state: "opened")
        let approvals = makeApprovals(myUnresolvedThreads: 1)
        XCTAssertFalse(canApprove(mr: mr, approvals: approvals, testsAreGreen: true))
    }

    func testCanApproveFalseWhenAlreadyApprovedByMe() {
        let mr = makeMR(isDraft: false, state: "opened")
        let approvals = makeApprovals(myUnresolvedThreads: 0, isApprovedByMe: true)
        XCTAssertFalse(canApprove(mr: mr, approvals: approvals, testsAreGreen: true))
    }

    func testCanApproveFalseWhenApprovalsAbsent() {
        let mr = makeMR(isDraft: false, state: "opened")
        XCTAssertFalse(canApprove(mr: mr, approvals: nil, testsAreGreen: true))
    }

    // MARK: - 2. Machine d'états

    func testDerivedStateConflictWinsOverEverythingElse() {
        let mr = makeMR(
            headPipeline: makePipeline(status: "failed"),
            divergedCommitsCount: 12,
            hasConflicts: true
        )
        let state = derivedState(mr: mr, approvals: nil, context: .author)
        XCTAssertEqual(state.label, "Conflit")
        XCTAssertEqual(state.tone, .critical)
    }

    func testDerivedStateCiFailedWinsOverDivergenceAndReview() {
        let mr = makeMR(headPipeline: makePipeline(status: "failed"), divergedCommitsCount: 12)
        let approvals = makeApprovals(required: 2, given: 0)
        let state = derivedState(mr: mr, approvals: approvals, context: .author)
        XCTAssertEqual(state.label, "CI KO")
    }

    func testDerivedStateDivergedNilIsNotTreatedAsZero() {
        let mr = makeMR(divergedCommitsCount: nil)
        let state = derivedState(mr: mr, approvals: nil, context: .author)
        XCTAssertNotEqual(state.label, "Rebase requis")
        XCTAssertEqual(state.label, "Prête à merger")
    }

    func testDerivedStateDivergedZeroIsNotRebaseRequired() {
        let mr = makeMR(divergedCommitsCount: 0)
        let state = derivedState(mr: mr, approvals: nil, context: .author)
        XCTAssertNotEqual(state.label, "Rebase requis")
    }

    func testDerivedStateSameDataDiffersByContext() {
        // Correctif plan §9.5 : le retard ne doit PAS figurer dans la machine reviewer.
        let mr = makeMR(headPipeline: makePipeline(status: "success"), divergedCommitsCount: 183)
        let approvals = makeApprovals(required: 2, given: 0)

        let authorState = derivedState(mr: mr, approvals: approvals, context: .author)
        let reviewerState = derivedState(mr: mr, approvals: approvals, context: .reviewer)

        XCTAssertEqual(authorState.label, "Rebase requis")
        XCTAssertEqual(reviewerState.label, "En attente de revue")
    }

    func testDerivedStateDraftIsNotAStateOfItsOwn() {
        let mrDraft = makeMR(isDraft: true, headPipeline: makePipeline(status: "failed"))
        let state = derivedState(mr: mrDraft, approvals: nil, context: .author)
        // Le draft n'intervient pas dans la machine : CI KO reste CI KO même en draft.
        XCTAssertEqual(state.label, "CI KO")
    }

    func testDerivedStateApprovalsAbsentSkipsToNextReachableTier() {
        let mr = makeMR(headPipeline: makePipeline(status: "success"))
        let state = derivedState(mr: mr, approvals: nil, context: .author)
        XCTAssertEqual(state.label, "Prête à merger")
    }

    func testDerivedStateCiRunningAndPending() {
        let running = makeMR(headPipeline: makePipeline(status: "running"))
        XCTAssertEqual(derivedState(mr: running, approvals: nil, context: .author).label, "CI en cours")

        let pending = makeMR(headPipeline: makePipeline(status: "pending"))
        XCTAssertEqual(derivedState(mr: pending, approvals: nil, context: .author).label, "CI attente")
    }

    func testDerivedStateDetailDecomposesAllSegments() {
        let mr = makeMR(headPipeline: makePipeline(status: "running"), divergedCommitsCount: 183)
        let approvals = makeApprovals(required: 2, given: 0)
        let state = derivedState(mr: mr, approvals: approvals, context: .author)
        XCTAssertEqual(state.detail, "CI en cours · 183 commits de retard · 0/2 approbations")
    }

    /// Correctif : le masquage de `/rebase` sur conflit doit s'appuyer sur `hasConflicts`
    /// brut, jamais sur un test de `state.label` — un libellé traduit ou reformulé
    /// masquerait silencieusement la règle métier (StatusTableView.swift).
    func testRowModelExposesRawHasConflictsEvenWhenDiverged() {
        let now = Date()
        let mr = makeMR(createdAt: now, divergedCommitsCount: 12, hasConflicts: true)
        let rows = buildRows(
            mrs: [mr], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertEqual(rows.first?.state.label, "Conflit")
        XCTAssertEqual(rows.first?.hasConflicts, true)
    }

    func testRowModelHasConflictsFalseWhenNoConflict() {
        let now = Date()
        let mr = makeMR(createdAt: now, hasConflicts: false)
        let rows = buildRows(
            mrs: [mr], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertEqual(rows.first?.hasConflicts, false)
    }

    /// `isPipelineState` distingue les libellés produits par la branche pipeline
    /// (cliquables vers `headPipeline.webUrl`) des autres — sans dépendre du texte.
    func testDerivedStateIsPipelineStateOnlyForCiBranches() {
        XCTAssertTrue(derivedState(mr: makeMR(headPipeline: makePipeline(status: "failed")), approvals: nil, context: .author).isPipelineState)
        XCTAssertTrue(derivedState(mr: makeMR(headPipeline: makePipeline(status: "running")), approvals: nil, context: .author).isPipelineState)
        XCTAssertTrue(derivedState(mr: makeMR(headPipeline: makePipeline(status: "pending")), approvals: nil, context: .author).isPipelineState)

        XCTAssertFalse(derivedState(mr: makeMR(hasConflicts: true), approvals: nil, context: .author).isPipelineState)
        XCTAssertFalse(derivedState(mr: makeMR(divergedCommitsCount: 5), approvals: nil, context: .author).isPipelineState)
        XCTAssertFalse(derivedState(mr: makeMR(), approvals: nil, context: .author).isPipelineState)
        XCTAssertFalse(
            derivedState(
                mr: makeMR(),
                approvals: makeApprovals(required: 2, given: 0),
                context: .author
            ).isPipelineState
        )
    }

    func testRowModelExposesPipelineWebUrl() {
        let now = Date()
        let pipeline = EmbeddedPipeline(id: 1, status: "running", webUrl: "https://gitlab.example.test/pipelines/1")
        let mr = makeMR(createdAt: now, headPipeline: pipeline)
        let rows = buildRows(
            mrs: [mr], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertEqual(rows.first?.pipelineWebUrl, "https://gitlab.example.test/pipelines/1")
    }

    // MARK: - 3. Gravité et tri

    func testAuthorSeverityOrderBlockedLateThreadsAwaitingReady() {
        let now = Date()
        let blocked = makeMR(iid: 1, createdAt: now, hasConflicts: true)
        let late = makeMR(iid: 2, createdAt: now, divergedCommitsCount: 5)
        let openThreads = makeMR(iid: 3, createdAt: now)
        let awaitingApproval = makeMR(iid: 4, createdAt: now)
        let ready = makeMR(iid: 5, createdAt: now)

        let approvals: [MRKey: MRApprovals] = [
            MRKey(projectId: 10, iid: 3): makeApprovals(required: 1, given: 1, unresolvedThreads: 1),
            MRKey(projectId: 10, iid: 4): makeApprovals(required: 2, given: 0),
            MRKey(projectId: 10, iid: 5): makeApprovals(required: 1, given: 1)
        ]

        let rows = buildRows(
            mrs: [ready, awaitingApproval, openThreads, late, blocked],
            approvals: approvals,
            jiraStatuses: [:],
            jiraLoadingKeys: [],
            testsAreGreen: { _ in true },
            context: .author,
            now: now
        )

        XCTAssertEqual(rows.map(\.iid), [1, 2, 3, 4, 5])
    }

    func testAuthorSeverityIntraTierSortsByCreatedAtDescending() {
        let now = Date()
        let older = makeMR(iid: 1, createdAt: now.addingTimeInterval(-10_000))
        let newer = makeMR(iid: 2, createdAt: now)

        let rows = buildRows(
            mrs: [older, newer],
            approvals: [:],
            jiraStatuses: [:],
            jiraLoadingKeys: [],
            testsAreGreen: { _ in true },
            context: .author,
            now: now
        )

        XCTAssertEqual(rows.map(\.iid), [2, 1])
    }

    func testReviewerSeverityOrderRevisitToReviewAwaitingApproved() {
        let now = Date()
        let needsRevisit = makeMR(iid: 1, createdAt: now)
        let toReview = makeMR(iid: 2, createdAt: now)
        let awaitingAuthor = makeMR(iid: 3, createdAt: now)
        let approved = makeMR(iid: 4, createdAt: now)

        let approvals: [MRKey: MRApprovals] = [
            MRKey(projectId: 10, iid: 1): makeApprovals(personalThreadsNeedingRevisit: 1),
            MRKey(projectId: 10, iid: 2): makeApprovals(myUnresolvedThreads: 0, isApprovedByMe: false),
            MRKey(projectId: 10, iid: 3): makeApprovals(myUnresolvedThreads: 1),
            MRKey(projectId: 10, iid: 4): makeApprovals(myUnresolvedThreads: 0, isApprovedByMe: true)
        ]

        let rows = buildRows(
            mrs: [approved, awaitingAuthor, toReview, needsRevisit],
            approvals: approvals,
            jiraStatuses: [:],
            jiraLoadingKeys: [],
            testsAreGreen: { _ in true },
            context: .reviewer,
            now: now
        )

        XCTAssertEqual(rows.map(\.iid), [1, 2, 3, 4])
    }

    func testReviewerSeverityIntraTierSortsByCreatedAtAscending() {
        let now = Date()
        let older = makeMR(iid: 1, createdAt: now.addingTimeInterval(-10_000))
        let newer = makeMR(iid: 2, createdAt: now)

        let rows = buildRows(
            mrs: [newer, older],
            approvals: [:],
            jiraStatuses: [:],
            jiraLoadingKeys: [],
            testsAreGreen: { _ in true },
            context: .reviewer,
            now: now
        )

        XCTAssertEqual(rows.map(\.iid), [1, 2])
    }

    func testMergedRowsAreSortedByMergedAtDescending() {
        let now = Date()
        let mergedFirst = makeMR(
            iid: 1,
            createdAt: now.addingTimeInterval(-100_000),
            mergedAt: now.addingTimeInterval(-50_000),
            state: "merged"
        )
        let mergedLast = makeMR(
            iid: 2,
            createdAt: now.addingTimeInterval(-90_000),
            mergedAt: now.addingTimeInterval(-10_000),
            state: "merged"
        )

        let rows = buildMergedRows(mrs: [mergedFirst, mergedLast], jiraStatuses: [:], now: now)

        XCTAssertEqual(rows.map(\.key.iid), [2, 1])
    }

    func testBuildRowsExcludesMergedMRs() {
        let now = Date()
        let opened = makeMR(iid: 1, createdAt: now, state: "opened")
        let merged = makeMR(iid: 2, createdAt: now, state: "merged")

        let rows = buildRows(
            mrs: [opened, merged],
            approvals: [:],
            jiraStatuses: [:],
            jiraLoadingKeys: [],
            testsAreGreen: { _ in true },
            context: .author,
            now: now
        )

        XCTAssertEqual(rows.map(\.iid), [1])
    }

    // MARK: - 4. Chips

    func testChipAllAlwaysMatches() {
        XCTAssertTrue(matchesChip(.all, approvals: nil, jiraStatus: nil))
    }

    func testChipNeedsRevisitPredicate() {
        XCTAssertTrue(matchesChip(.needsRevisit, approvals: makeApprovals(personalThreadsNeedingRevisit: 1), jiraStatus: nil))
        XCTAssertFalse(matchesChip(.needsRevisit, approvals: makeApprovals(personalThreadsNeedingRevisit: 0), jiraStatus: nil))
        XCTAssertFalse(matchesChip(.needsRevisit, approvals: nil, jiraStatus: nil))
    }

    func testChipMyThreadsPredicate() {
        XCTAssertTrue(matchesChip(.myThreads, approvals: makeApprovals(myUnresolvedThreads: 2), jiraStatus: nil))
        XCTAssertFalse(matchesChip(.myThreads, approvals: makeApprovals(myUnresolvedThreads: 0), jiraStatus: nil))
    }

    func testChipNoReviewExcludesWhenApprovalsNotLoaded() {
        // Approvals non chargées : exclue de la chip (mais resterait dans Tout).
        XCTAssertFalse(matchesChip(.noReview, approvals: nil, jiraStatus: nil))
    }

    func testChipNoReviewPredicate() {
        XCTAssertTrue(matchesChip(.noReview, approvals: makeApprovals(given: 0, hasCurrentUserComment: false), jiraStatus: nil))
        XCTAssertFalse(matchesChip(.noReview, approvals: makeApprovals(given: 1, hasCurrentUserComment: false), jiraStatus: nil))
        XCTAssertFalse(matchesChip(.noReview, approvals: makeApprovals(given: 0, hasCurrentUserComment: true), jiraStatus: nil))
    }

    func testChipToReviewPredicateNormalizesJiraName() {
        let jira = JiraIssueStatus(name: "  Code Review  ", categoryKey: "indeterminate", isStale: false)
        XCTAssertTrue(matchesChip(.toReview, approvals: nil, jiraStatus: jira))

        let other = JiraIssueStatus(name: "À tester", categoryKey: "indeterminate", isStale: false)
        XCTAssertFalse(matchesChip(.toReview, approvals: nil, jiraStatus: other))
    }

    func testChipApprovedPredicate() {
        XCTAssertTrue(matchesChip(.approved, approvals: makeApprovals(myUnresolvedThreads: 0, isApprovedByMe: true), jiraStatus: nil))
        XCTAssertFalse(matchesChip(.approved, approvals: makeApprovals(myUnresolvedThreads: 1, isApprovedByMe: true), jiraStatus: nil))
        XCTAssertFalse(matchesChip(.approved, approvals: nil, jiraStatus: nil))
    }

    func testChipCountsAggregatesAcrossMRs() {
        let now = Date()
        let mrA = makeMR(iid: 1, projectId: 10, createdAt: now)
        let mrB = makeMR(iid: 2, projectId: 10, createdAt: now)
        let approvals: [MRKey: MRApprovals] = [
            MRKey(projectId: 10, iid: 1): makeApprovals(personalThreadsNeedingRevisit: 1),
            MRKey(projectId: 10, iid: 2): makeApprovals()
        ]

        let counts = chipCounts(
            for: [.all, .needsRevisit],
            mrs: [mrA, mrB],
            approvals: approvals,
            jiraStatuses: [:]
        )

        XCTAssertEqual(counts[.all], 2)
        XCTAssertEqual(counts[.needsRevisit], 1)
    }

    // MARK: - 5. Dérivés

    func testIidLabelHasNoThousandsSeparator() {
        let now = Date()
        let mr = makeMR(iid: 57_020, createdAt: now)
        let rows = buildRows(
            mrs: [mr],
            approvals: [:],
            jiraStatuses: [:],
            jiraLoadingKeys: [],
            testsAreGreen: { _ in true },
            context: .author,
            now: now
        )
        XCTAssertEqual(rows.first?.iidLabel, "!57020")
    }

    func testTicketFoundInBranch() {
        let now = Date()
        let mr = makeMR(title: "fix(plato): sans mention", sourceBranch: "fix/PROD-30746-correction", createdAt: now)
        let rows = buildRows(
            mrs: [mr], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertEqual(rows.first?.ticket, "PROD-30746")
    }

    func testTicketFallsBackToTitleWhenAbsentFromBranch() {
        let now = Date()
        let mr = makeMR(title: "fix(plato): correctif (PROD-30065)", sourceBranch: "fix/no-ticket", createdAt: now)
        let rows = buildRows(
            mrs: [mr], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertEqual(rows.first?.ticket, "PROD-30065")
    }

    func testTicketNilWhenAbsentFromBothBranchAndTitle() {
        let now = Date()
        let mr = makeMR(title: "fix(plato): correctif générique", sourceBranch: "fix/no-ticket", createdAt: now)
        let rows = buildRows(
            mrs: [mr], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertNil(rows.first?.ticket)
    }

    func testDisplayTitleStripsParenthesizedTicketWhenMatching() {
        let now = Date()
        let mr = makeMR(
            title: "fix(plato): portfolio transfer shows 0 buildings (PROD-30065)",
            sourceBranch: "fix/PROD-30065-portfolio",
            createdAt: now
        )
        let rows = buildRows(
            mrs: [mr], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertEqual(rows.first?.displayTitle, "fix(plato): portfolio transfer shows 0 buildings")
    }

    func testDisplayTitleStripsBracketedTicketWhenMatching() {
        let now = Date()
        let mr = makeMR(
            title: "fix(ms-fees): repricing over future dues [PROD-31008]",
            sourceBranch: "fix/PROD-31008-repricing",
            createdAt: now
        )
        let rows = buildRows(
            mrs: [mr], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertEqual(rows.first?.displayTitle, "fix(ms-fees): repricing over future dues")
    }

    func testDisplayTitleStripsBareTicketSuffixWhenMatching() {
        let now = Date()
        let mr = makeMR(
            title: "fix(plato): correction PROD-30914",
            sourceBranch: "fix/PROD-30914-correction",
            createdAt: now
        )
        let rows = buildRows(
            mrs: [mr], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertEqual(rows.first?.displayTitle, "fix(plato): correction")
    }

    func testDisplayTitleKeepsSuffixWhenTicketDiffersFromExtracted() {
        let now = Date()
        let mr = makeMR(
            title: "fix(plato): correction (PROD-11111)",
            sourceBranch: "fix/PROD-30914-correction",
            createdAt: now
        )
        let rows = buildRows(
            mrs: [mr], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertEqual(rows.first?.ticket, "PROD-30914")
        XCTAssertEqual(rows.first?.displayTitle, "fix(plato): correction (PROD-11111)")
    }

    func testProjectNameExtractedFromWebUrl() {
        let now = Date()
        let mr = makeMR(
            webUrl: "https://gitlab.example.test/millenium/plato/-/merge_requests/57020",
            createdAt: now
        )
        let rows = buildRows(
            mrs: [mr], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertEqual(rows.first?.projectName, "plato")
    }

    func testProjectNameFallsBackWhenUrlHasNoDashSegment() {
        let now = Date()
        let mr = makeMR(webUrl: "https://gitlab.example.test/millenium/plato", createdAt: now)
        let rows = buildRows(
            mrs: [mr], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertEqual(rows.first?.projectName, "projet")
    }

    func testDivergedLabelNilWhenZeroOrAbsent() {
        let now = Date()
        let zero = makeMR(iid: 1, createdAt: now, divergedCommitsCount: 0)
        let absent = makeMR(iid: 2, createdAt: now, divergedCommitsCount: nil)
        let rows = buildRows(
            mrs: [zero, absent], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertNil(rows[0].divergedLabel)
        XCTAssertNil(rows[1].divergedLabel)
    }

    func testDivergedLabelIsBoundedBeyond999() {
        let now = Date()
        let mr = makeMR(createdAt: now, divergedCommitsCount: 9_344)
        let rows = buildRows(
            mrs: [mr], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertEqual(rows.first?.divergedLabel, "999+")
        XCTAssertEqual(rows.first?.divergedCount, 9_344)
    }

    func testDivergedLabelShowsRawValueBelowBound() {
        let now = Date()
        let mr = makeMR(createdAt: now, divergedCommitsCount: 183)
        let rows = buildRows(
            mrs: [mr], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertEqual(rows.first?.divergedLabel, "183")
    }

    func testAgeLabelUnderOneHour() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mr = makeMR(createdAt: now.addingTimeInterval(-1_800))
        let rows = buildRows(
            mrs: [mr], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertEqual(rows.first?.ageLabel, "<1h")
    }

    func testAgeLabelInHours() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mr = makeMR(createdAt: now.addingTimeInterval(-5 * 3_600))
        let rows = buildRows(
            mrs: [mr], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertEqual(rows.first?.ageLabel, "5h")
    }

    func testAgeLabelInDays() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mr = makeMR(createdAt: now.addingTimeInterval(-3 * 24 * 3_600))
        let rows = buildRows(
            mrs: [mr], approvals: [:], jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .author, now: now
        )
        XCTAssertEqual(rows.first?.ageLabel, "3j")
    }

    func testImplicationLabelsSingularAndPlural() {
        let oneRevisit = implicationFor(personalThreadsNeedingRevisit: 1)
        XCTAssertEqual(oneRevisit.primaryLabel, "À revalider · 1 fil")

        let twoRevisits = implicationFor(personalThreadsNeedingRevisit: 2)
        XCTAssertEqual(twoRevisits.primaryLabel, "À revalider · 2 fils")

        let oneMyThread = implicationFor(myUnresolvedThreads: 1)
        XCTAssertEqual(oneMyThread.primaryLabel, "1 fil de vous")

        let twoMyThreads = implicationFor(myUnresolvedThreads: 2)
        XCTAssertEqual(twoMyThreads.primaryLabel, "2 fils de vous")

        let oneOther = implicationFor(otherUnresolvedThreads: 1)
        XCTAssertEqual(oneOther.secondaryLabel, "1 autre")

        let threeOthers = implicationFor(otherUnresolvedThreads: 3)
        XCTAssertEqual(threeOthers.secondaryLabel, "3 autres")

        let approved = implicationFor(isApprovedByMe: true)
        XCTAssertEqual(approved.primaryLabel, "Approuvée ✓")

        let empty = implicationFor()
        XCTAssertNil(empty.primaryLabel)
        XCTAssertNil(empty.secondaryLabel)

        let claudeApproved = implicationFor(isApprovedByClaude: true)
        XCTAssertEqual(claudeApproved.claudeLabel, "Claude ✓")
    }

    /// `.primary`/`.secondary` regroupent tone + ancre GitLab dans la même source que
    /// le libellé — la vue (StatusTableView) ne doit jamais re-choisir l'ancre elle-même.
    func testImplicationPrimaryAndSecondaryCarryToneAndNoteId() {
        let now = Date()
        let mr = makeMR(createdAt: now)
        let approvals = makeApprovals(
            unresolvedThreads: 3,
            myUnresolvedThreads: 1,
            otherUnresolvedThreads: 2,
            personalThreadsNeedingRevisit: 1,
            firstMyUnresolvedThreadNoteId: 111,
            firstPersonalThreadNeedingRevisitNoteId: 222,
            firstOtherUnresolvedThreadNoteId: 333
        )
        let rows = buildRows(
            mrs: [mr],
            approvals: [MRKey(projectId: mr.projectId, iid: mr.iid): approvals],
            jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .reviewer, now: now
        )
        let implication = rows[0].implication

        // Revisit gagne sur myThreads (même priorité que primaryLabel) : tone attention, ancre du revisit.
        XCTAssertEqual(implication.primary?.tone, .attention)
        XCTAssertEqual(implication.primary?.noteId, 222)

        XCTAssertEqual(implication.secondary?.tone, .attention)
        XCTAssertEqual(implication.secondary?.noteId, 333)
    }

    func testImplicationPrimaryMyThreadsToneIsAccentWithCorrectAnchor() {
        let now = Date()
        let mr = makeMR(createdAt: now)
        let approvals = makeApprovals(
            unresolvedThreads: 1,
            myUnresolvedThreads: 1,
            firstMyUnresolvedThreadNoteId: 999
        )
        let rows = buildRows(
            mrs: [mr],
            approvals: [MRKey(projectId: mr.projectId, iid: mr.iid): approvals],
            jiraStatuses: [:], jiraLoadingKeys: [],
            testsAreGreen: { _ in true }, context: .reviewer, now: now
        )
        let implication = rows[0].implication
        XCTAssertEqual(implication.primary?.tone, .accent)
        XCTAssertEqual(implication.primary?.noteId, 999)
    }

    func testImplicationPrimaryApprovedHasNoAnchor() {
        let implication = implicationFor(isApprovedByMe: true)
        XCTAssertEqual(implication.primary?.tone, .positive)
        XCTAssertNil(implication.primary?.noteId)
    }

    private func implicationFor(
        personalThreadsNeedingRevisit: Int = 0,
        myUnresolvedThreads: Int = 0,
        otherUnresolvedThreads: Int = 0,
        isApprovedByMe: Bool = false,
        isApprovedByClaude: Bool = false
    ) -> Implication {
        let now = Date()
        let mr = makeMR(createdAt: now)
        let approvals = makeApprovals(
            unresolvedThreads: myUnresolvedThreads + otherUnresolvedThreads,
            myUnresolvedThreads: myUnresolvedThreads,
            otherUnresolvedThreads: otherUnresolvedThreads,
            personalThreadsNeedingRevisit: personalThreadsNeedingRevisit,
            isApprovedByMe: isApprovedByMe,
            isApprovedByClaude: isApprovedByClaude
        )
        let rows = buildRows(
            mrs: [mr],
            approvals: [MRKey(projectId: mr.projectId, iid: mr.iid): approvals],
            jiraStatuses: [:],
            jiraLoadingKeys: [],
            testsAreGreen: { _ in true },
            context: .reviewer,
            now: now
        )
        return rows[0].implication
    }
}
