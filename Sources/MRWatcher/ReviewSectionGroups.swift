import Foundation

/// Groupement Jira (To Review / Les autres / Approved) du popover (`MenuBarView.swift`).
/// Déplacé tel quel depuis `StatusView.swift` — la fenêtre principale n'en a plus besoin
/// depuis l'étape 3 (remplacé par les chips), mais le popover le consomme toujours.
struct ReviewSectionGroups {
    let toReview: [MRSummary]
    let others: [MRSummary]
    let approved: [MRSummary]

    init(
        mrs: [MRSummary],
        statuses: [MRKey: MRApprovals],
        jiraStatuses: [MRKey: JiraIssueStatus],
        separatesApproved: Bool
    ) {
        let approvedMRs = separatesApproved
            ? mrs.filter { mr in
                let key = MRKey(projectId: mr.projectId, iid: mr.iid)
                guard let status = statuses[key] else { return false }
                return status.isApprovedByMe && status.myUnresolvedThreads == 0
            }
            : []
        approved = approvedMRs

        let approvedKeys = Set(
            approvedMRs.map { MRKey(projectId: $0.projectId, iid: $0.iid) }
        )
        let activeMRs = mrs.filter { mr in
            !approvedKeys.contains(MRKey(projectId: mr.projectId, iid: mr.iid))
        }
        toReview = activeMRs.filter { mr in
            let key = MRKey(projectId: mr.projectId, iid: mr.iid)
            guard let status = jiraStatuses[key]?.name else { return false }
            return ["to review", "code review"].contains(
                status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
        }
        let toReviewKeys = Set(
            toReview.map { MRKey(projectId: $0.projectId, iid: $0.iid) }
        )
        others = activeMRs.filter { mr in
            !toReviewKeys.contains(MRKey(projectId: mr.projectId, iid: mr.iid))
        }
    }
}
