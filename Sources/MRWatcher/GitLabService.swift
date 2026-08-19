import Foundation

enum MRWatcherError: Error {
    case notConfigured
    case invalidHost(String)
    case unauthorized
    case invalidResponse(Int)
    case nonHTTPResponse
}

struct EmbeddedPipeline: Codable {
    let id: Int
    let status: String
    let webUrl: String
    enum CodingKeys: String, CodingKey {
        case id; case status; case webUrl = "web_url"
    }
}

struct ManualPipelineAction: Identifiable, Hashable {
    enum Kind: Hashable {
        case tests
        case autoReview

        var title: String {
            switch self {
            case .tests: "Lancer les tests"
            case .autoReview: "Lancer l'auto review"
            }
        }

        var systemImage: String {
            switch self {
            case .tests: "testtube.2"
            case .autoReview: "wand.and.stars"
            }
        }
    }

    let jobId: Int
    let kind: Kind

    var id: Int { jobId }
}

struct PipelineJobActions {
    let actions: [ManualPipelineAction]
    let buildAffectedStatus: String?
}

struct MRAuthor: Codable {
    let username: String
    let name: String?

    var shortDisplayName: String {
        let nameParts = name?
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init) ?? []
        if let firstName = nameParts.first,
           let lastName = nameParts.dropFirst().first {
            return "\(firstName.capitalized) \(lastName.prefix(1).uppercased())."
        }

        let usernameParts = username.split { "._".contains($0) }
        guard let firstName = usernameParts.first else { return username }
        guard let lastName = usernameParts.dropFirst().first else {
            let hyphenParts = firstName.split(separator: "-")
            guard let hyphenatedLastName = hyphenParts.dropFirst().first else {
                return String(firstName).capitalized
            }
            return "\(String(hyphenParts[0]).capitalized) \(hyphenatedLastName.prefix(1).uppercased())."
        }
        return "\(String(firstName).capitalized) \(lastName.prefix(1).uppercased())."
    }

    var fullDescription: String {
        guard let name, !name.isEmpty else { return username }
        return "\(name) (\(username))"
    }
}

struct MRSummary: Identifiable, Codable {
    let id: Int
    let iid: Int
    let projectId: Int
    let title: String
    let webUrl: String
    let notesCount: Int
    let sourceBranch: String
    let isDraft: Bool
    let createdAt: Date
    let mergedAt: Date?
    let headPipeline: EmbeddedPipeline?
    let divergedCommitsCount: Int?
    let hasConflicts: Bool
    let state: String  // "opened", "merged", "closed"
    let author: MRAuthor?

    enum CodingKeys: String, CodingKey {
        case id, iid, title, state, author
        case projectId = "project_id"
        case webUrl = "web_url"
        case notesCount = "user_notes_count"
        case sourceBranch = "source_branch"
        case isDraft = "draft"
        case createdAt = "created_at"
        case mergedAt = "merged_at"
        case headPipeline = "head_pipeline"
        case divergedCommitsCount = "diverged_commits_count"
        case hasConflicts = "has_conflicts"
    }
}

struct MRApprovals {
    let required: Int
    let given: Int
    let unresolvedThreads: Int
    let myUnresolvedThreads: Int
    let otherUnresolvedThreads: Int
    let firstMyUnresolvedThreadNoteId: Int?
    let firstOtherUnresolvedThreadNoteId: Int?
    let isApprovedByMe: Bool
    let isApprovedByClaude: Bool
    let hasCurrentUserComment: Bool
}

private struct DiscussionResponse: Codable {
    let individualNote: Bool
    let notes: [NoteEntry]
    enum CodingKeys: String, CodingKey { case individualNote = "individual_note"; case notes }
    struct NoteEntry: Codable {
        let id: Int
        let resolvable: Bool
        let resolved: Bool?
        let author: Author
    }
    struct Author: Codable { let username: String }
}

private struct ApprovalsResponse: Codable {
    let approvalsRequired: Int
    let approvalsLeft: Int
    let approvedBy: [ApprovedByEntry]
    enum CodingKeys: String, CodingKey {
        case approvalsRequired = "approvals_required"
        case approvalsLeft = "approvals_left"
        case approvedBy = "approved_by"
    }
    struct ApprovedByEntry: Codable { let user: ApproverUser }
    struct ApproverUser: Codable {
        let username: String
        let name: String?
    }
}

private struct EventResponse: Codable {
    let actionName: String?
    let targetType: String?
    let targetTitle: String?
    let projectId: Int?

    enum CodingKeys: String, CodingKey {
        case actionName = "action_name"
        case targetType = "target_type"
        case targetTitle = "target_title"
        case projectId = "project_id"
    }
}

private struct CurrentUserResponse: Codable {
    let id: Int
}

private struct CommentEventTarget: Hashable {
    let projectId: Int
    let title: String
}

struct SameOriginRedirectPolicy {
    private struct Origin: Equatable {
        let scheme: String
        let host: String
        let port: Int?
    }

    static func permitsRedirect(from originalURL: URL?, to redirectURL: URL?) -> Bool {
        guard let originalURL,
              let redirectURL,
              let originalOrigin = origin(for: originalURL),
              let redirectOrigin = origin(for: redirectURL) else {
            return false
        }
        return originalOrigin == redirectOrigin
    }

    private static func origin(for url: URL) -> Origin? {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !scheme.isEmpty,
              !host.isEmpty else {
            return nil
        }

        let normalizedHost = host.hasSuffix(".") ? String(host.dropLast()) : host
        let effectivePort = url.port ?? defaultPort(for: scheme)
        return Origin(scheme: scheme, host: normalizedHost, port: effectivePort)
    }

    private static func defaultPort(for scheme: String) -> Int? {
        switch scheme {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }
}

private final class SameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard SameOriginRedirectPolicy.permitsRedirect(
            from: task.originalRequest?.url,
            to: request.url
        ) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

final class GitLabService {
    private let config: ConfigManager
    private let redirectDelegate: SameOriginRedirectDelegate
    private let session: URLSession
    // Limits project-level title searches after comment events are deduplicated.
    private static let maximumCommentEventLookupCount = 50
    private static let commentEventLookupBatchSize = 8

    init(config: ConfigManager) {
        self.config = config
        self.redirectDelegate = SameOriginRedirectDelegate()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        self.session = URLSession(
            configuration: cfg,
            delegate: redirectDelegate,
            delegateQueue: nil
        )
    }

    func fetchMyOpenMRs() async throws -> [MRSummary] {
        let (pat, username) = await MainActor.run { (config.gitlabPAT, config.gitlabUsername) }
        guard let pat, let username else { throw MRWatcherError.notConfigured }
        let host = await MainActor.run { config.gitlabHost }

        let url = try buildURL(host: host, path: "/api/v4/merge_requests", query: [
            "author_username": username,
            "state": "opened",
            "per_page": "50"
        ])
        var request = URLRequest(url: url)
        request.setValue(pat, forHTTPHeaderField: "PRIVATE-TOKEN")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([MRSummary].self, from: data)
    }

    func fetchOpenReviewableMRs() async throws -> [MRSummary] {
        let (pat, labels) = await MainActor.run {
            (config.gitlabPAT, config.reviewLabels)
        }
        guard let pat else { throw MRWatcherError.notConfigured }
        let host = await MainActor.run { config.gitlabHost }

        var seenKeys: Set<MRKey> = []
        var mrs: [MRSummary] = []
        for label in labels {
            let url = try buildURL(host: host, path: "/api/v4/merge_requests", query: [
                "scope": "all",
                "state": "opened",
                "labels": label,
                "per_page": "50"
            ])
            var request = URLRequest(url: url)
            request.setValue(pat, forHTTPHeaderField: "PRIVATE-TOKEN")

            let (data, response) = try await session.data(for: request)
            try validateResponse(response)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            for mr in try decoder.decode([MRSummary].self, from: data) {
                let key = MRKey(projectId: mr.projectId, iid: mr.iid)
                if seenKeys.insert(key).inserted {
                    mrs.append(mr)
                }
            }
        }
        return mrs
    }

    func fetchMyRecentlyMergedMRs() async throws -> [MRSummary] {
        let (pat, username) = await MainActor.run { (config.gitlabPAT, config.gitlabUsername) }
        guard let pat, let username else { throw MRWatcherError.notConfigured }
        let host = await MainActor.run { config.gitlabHost }

        let url = try buildURL(host: host, path: "/api/v4/merge_requests", query: [
            "author_username": username,
            "state": "merged",
            "order_by": "updated_at",
            "sort": "desc",
            "per_page": "10"
        ])
        var request = URLRequest(url: url)
        request.setValue(pat, forHTTPHeaderField: "PRIVATE-TOKEN")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([MRSummary].self, from: data)
    }

    func fetchMyCommentedMRKeys(maxPages: Int) async throws -> Set<MRKey> {
        let pat = await MainActor.run { config.gitlabPAT }
        guard let pat else { throw MRWatcherError.notConfigured }
        let host = await MainActor.run { config.gitlabHost }
        guard maxPages > 0 else { return [] }

        var targets: Set<CommentEventTarget> = []
        for page in 1...maxPages {
            let url = try buildURL(host: host, path: "/api/v4/events", query: [
                "action": "commented",
                "per_page": "100",
                "page": String(page)
            ])
            var request = URLRequest(url: url)
            request.setValue(pat, forHTTPHeaderField: "PRIVATE-TOKEN")

            let (data, response) = try await session.data(for: request)
            try validateResponse(response)

            let events = try JSONDecoder().decode([EventResponse].self, from: data)
            targets.formUnion(events.compactMap { event in
                let actionName = event.actionName?.lowercased() ?? ""
                let targetType = event.targetType?
                    .lowercased()
                    .replacingOccurrences(of: "_", with: "") ?? ""
                guard actionName.hasPrefix("commented"),
                      ["diffnote", "discussionnote", "note"].contains(targetType),
                      let projectId = event.projectId,
                      let targetTitle = event.targetTitle?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      projectId > 0,
                      !targetTitle.isEmpty else {
                    return nil
                }
                return CommentEventTarget(projectId: projectId, title: targetTitle)
            })

            if events.count < 100 { break }
        }

        var keys: Set<MRKey> = []
        let sortedTargets = targets.sorted {
            $0.projectId == $1.projectId
                ? $0.title < $1.title
                : $0.projectId < $1.projectId
        }
        let targetsToResolve = Array(
            sortedTargets.prefix(Self.maximumCommentEventLookupCount)
        )
        for batchStart in stride(
            from: 0,
            to: targetsToResolve.count,
            by: Self.commentEventLookupBatchSize
        ) {
            let batchEnd = min(
                batchStart + Self.commentEventLookupBatchSize,
                targetsToResolve.count
            )
            let batch = targetsToResolve[batchStart..<batchEnd]
            let resolvedKeys = await withTaskGroup(of: MRKey?.self) { group in
                for target in batch {
                    group.addTask { [self] in
                        try? await resolveOpenMRKey(
                            projectId: target.projectId,
                            title: target.title,
                            host: host,
                            pat: pat
                        )
                    }
                }

                var batchKeys: [MRKey] = []
                for await key in group {
                    if let key {
                        batchKeys.append(key)
                    }
                }
                return batchKeys
            }
            keys.formUnion(resolvedKeys)
        }
        return keys
    }

    func fetchOpenMRsApprovedByCurrentUser(maxPages: Int) async throws -> [MRSummary] {
        let pat = await MainActor.run { config.gitlabPAT }
        guard let pat else { throw MRWatcherError.notConfigured }
        let host = await MainActor.run { config.gitlabHost }
        guard maxPages > 0 else { return [] }

        let userURL = try buildURL(host: host, path: "/api/v4/user", query: [:])
        var userRequest = URLRequest(url: userURL)
        userRequest.setValue(pat, forHTTPHeaderField: "PRIVATE-TOKEN")
        let (userData, userResponse) = try await session.data(for: userRequest)
        try validateResponse(userResponse)
        let user = try JSONDecoder().decode(CurrentUserResponse.self, from: userData)

        var seenKeys: Set<MRKey> = []
        var mrs: [MRSummary] = []
        var requestedPages: Set<Int> = []
        var page = 1
        while requestedPages.count < maxPages, requestedPages.insert(page).inserted {
            let url = try buildURL(host: host, path: "/api/v4/merge_requests", query: [
                "scope": "all",
                "state": "opened",
                "approved_by_ids[]": String(user.id),
                "per_page": "100",
                "page": String(page)
            ])
            var request = URLRequest(url: url)
            request.setValue(pat, forHTTPHeaderField: "PRIVATE-TOKEN")

            let (data, response) = try await session.data(for: request)
            try validateResponse(response)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            for mr in try decoder.decode([MRSummary].self, from: data) {
                let key = MRKey(projectId: mr.projectId, iid: mr.iid)
                if seenKeys.insert(key).inserted {
                    mrs.append(mr)
                }
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  let nextPageValue = httpResponse.value(forHTTPHeaderField: "X-Next-Page"),
                  let nextPage = Int(nextPageValue),
                  nextPage > 0 else {
                break
            }
            page = nextPage
        }
        return mrs
    }

    private func resolveOpenMRKey(
        projectId: Int,
        title: String,
        host: String,
        pat: String
    ) async throws -> MRKey? {
        let url = try buildURL(
            host: host,
            path: "/api/v4/projects/\(projectId)/merge_requests",
            query: [
                "state": "opened",
                "search": title,
                "per_page": "100"
            ]
        )
        var request = URLRequest(url: url)
        request.setValue(pat, forHTTPHeaderField: "PRIVATE-TOKEN")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let matches = try decoder.decode([MRSummary].self, from: data).filter {
            $0.title == title
        }
        guard matches.count == 1, let match = matches.first else { return nil }
        return MRKey(projectId: match.projectId, iid: match.iid)
    }

    func fetchApprovals(projectId: Int, mrIid: Int) async throws -> MRApprovals {
        let (pat, username) = await MainActor.run { (config.gitlabPAT, config.gitlabUsername) }
        guard let pat, let username else { throw MRWatcherError.notConfigured }
        let host = await MainActor.run { config.gitlabHost }

        let approvalsUrl = try buildURL(
            host: host,
            path: "/api/v4/projects/\(projectId)/merge_requests/\(mrIid)/approvals",
            query: [:]
        )
        let approvalsRequest = {
            var r = URLRequest(url: approvalsUrl)
            r.setValue(pat, forHTTPHeaderField: "PRIVATE-TOKEN")
            return r
        }()

        async let approvalsResult = session.data(for: approvalsRequest)
        async let discussionsResult = fetchAllDiscussions(
            projectId: projectId,
            mrIid: mrIid,
            host: host,
            pat: pat
        )

        let (approvalsData, approvalsResponse) = try await approvalsResult
        try validateResponse(approvalsResponse)

        let decoded = try JSONDecoder().decode(ApprovalsResponse.self, from: approvalsData)
        let humanApprovals = decoded.approvedBy.filter { entry in
            let u = entry.user.username
            return !u.contains("_bot_") && !u.hasSuffix("-bot") && !u.hasPrefix("bot-")
        }

        let discussions = try await discussionsResult
        let hasCurrentUserComment = discussions.contains { discussion in
            discussion.notes.contains {
                $0.author.username.caseInsensitiveCompare(username) == .orderedSame
            }
        }
        var myUnresolvedThreads = 0
        var otherUnresolvedThreads = 0
        var firstMyUnresolvedThreadNoteId: Int?
        var firstOtherUnresolvedThreadNoteId: Int?
        for discussion in discussions {
            guard !discussion.individualNote,
                  let firstNote = discussion.notes.first,
                  firstNote.resolvable,
                  firstNote.resolved == false else {
                continue
            }

            if firstNote.author.username.caseInsensitiveCompare(username) == .orderedSame {
                myUnresolvedThreads += 1
                if firstMyUnresolvedThreadNoteId == nil {
                    firstMyUnresolvedThreadNoteId = firstNote.id
                }
            } else {
                otherUnresolvedThreads += 1
                if firstOtherUnresolvedThreadNoteId == nil {
                    firstOtherUnresolvedThreadNoteId = firstNote.id
                }
            }
        }

        let given = humanApprovals.count
        let required = given + decoded.approvalsLeft
        return MRApprovals(
            required: required,
            given: given,
            unresolvedThreads: myUnresolvedThreads + otherUnresolvedThreads,
            myUnresolvedThreads: myUnresolvedThreads,
            otherUnresolvedThreads: otherUnresolvedThreads,
            firstMyUnresolvedThreadNoteId: firstMyUnresolvedThreadNoteId,
            firstOtherUnresolvedThreadNoteId: firstOtherUnresolvedThreadNoteId,
            isApprovedByMe: decoded.approvedBy.contains {
                $0.user.username.caseInsensitiveCompare(username) == .orderedSame
            },
            isApprovedByClaude: decoded.approvedBy.contains {
                $0.user.name?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare("claude") == .orderedSame
            },
            hasCurrentUserComment: hasCurrentUserComment
        )
    }

    private func fetchAllDiscussions(
        projectId: Int,
        mrIid: Int,
        host: String,
        pat: String
    ) async throws -> [DiscussionResponse] {
        var discussions: [DiscussionResponse] = []
        var requestedPages: Set<Int> = []
        var page = 1

        while requestedPages.insert(page).inserted {
            let url = try buildURL(
                host: host,
                path: "/api/v4/projects/\(projectId)/merge_requests/\(mrIid)/discussions",
                query: [
                    "page": String(page),
                    "per_page": "100"
                ]
            )
            var request = URLRequest(url: url)
            request.setValue(pat, forHTTPHeaderField: "PRIVATE-TOKEN")

            let (data, response) = try await session.data(for: request)
            try validateResponse(response)
            discussions += try JSONDecoder().decode([DiscussionResponse].self, from: data)

            guard let httpResponse = response as? HTTPURLResponse,
                  let nextPageHeader = httpResponse.value(forHTTPHeaderField: "X-Next-Page")?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  let nextPage = Int(nextPageHeader),
                  nextPage > 0,
                  !requestedPages.contains(nextPage) else {
                break
            }
            page = nextPage
        }

        return discussions
    }

    func fetchMRDetail(projectId: Int, mrIid: Int) async throws -> MRSummary {
        let pat = await MainActor.run { config.gitlabPAT }
        guard let pat else { throw MRWatcherError.notConfigured }
        let host = await MainActor.run { config.gitlabHost }

        let url = try buildURL(
            host: host,
            path: "/api/v4/projects/\(projectId)/merge_requests/\(mrIid)",
            query: ["include_diverged_commits_count": "true"]
        )
        var request = URLRequest(url: url)
        request.setValue(pat, forHTTPHeaderField: "PRIVATE-TOKEN")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MRSummary.self, from: data)
    }

    func fetchManualPipelineActions(
        projectId: Int,
        pipelineId: Int
    ) async throws -> PipelineJobActions {
        let pat = await MainActor.run { config.gitlabPAT }
        guard let pat else { throw MRWatcherError.notConfigured }
        let host = await MainActor.run { config.gitlabHost }

        struct JobEntry: Codable {
            let id: Int
            let name: String
            let status: String
        }

        var actions: [ManualPipelineAction] = []
        var buildAffectedStatus: String?
        var requestedPages: Set<Int> = []
        var page = 1

        while requestedPages.insert(page).inserted {
            let url = try buildURL(
                host: host,
                path: "/api/v4/projects/\(projectId)/pipelines/\(pipelineId)/jobs",
                query: [
                    "page": String(page),
                    "per_page": "100"
                ]
            )
            var request = URLRequest(url: url)
            request.setValue(pat, forHTTPHeaderField: "PRIVATE-TOKEN")

            let (data, response) = try await session.data(for: request)
            try validateResponse(response)

            let jobs = try JSONDecoder().decode([JobEntry].self, from: data)
            if let buildAffectedJob = jobs.first(where: {
                $0.name.caseInsensitiveCompare("build affected") == .orderedSame
            }) {
                buildAffectedStatus = buildAffectedJob.status.lowercased()
            }
            actions += jobs.compactMap { job in
                guard job.status.lowercased() == "manual" else {
                    return nil
                }
                switch job.name.lowercased() {
                case "build affected":
                    return ManualPipelineAction(jobId: job.id, kind: .tests)
                case "auto review":
                    return ManualPipelineAction(jobId: job.id, kind: .autoReview)
                default:
                    return nil
                }
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  let nextPageHeader = httpResponse.value(forHTTPHeaderField: "X-Next-Page")?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  let nextPage = Int(nextPageHeader),
                  nextPage > 0,
                  !requestedPages.contains(nextPage) else {
                break
            }
            page = nextPage
        }

        return PipelineJobActions(
            actions: actions,
            buildAffectedStatus: buildAffectedStatus
        )
    }

    func findBuildAffectedJob(projectId: Int, pipelineId: Int) async throws -> (id: Int, status: String)? {
        let result = try await fetchManualPipelineActions(
            projectId: projectId,
            pipelineId: pipelineId
        )
        guard let action = result.actions.first(where: { $0.kind == .tests }),
              let status = result.buildAffectedStatus else {
            return nil
        }
        return (action.jobId, status)
    }

    func playJob(projectId: Int, jobId: Int) async throws {
        let pat = await MainActor.run { config.gitlabPAT }
        guard let pat else { throw MRWatcherError.notConfigured }
        let host = await MainActor.run { config.gitlabHost }

        let url = try buildURL(host: host, path: "/api/v4/projects/\(projectId)/jobs/\(jobId)/play", query: [:])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(pat, forHTTPHeaderField: "PRIVATE-TOKEN")
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    func rebase(projectId: Int, mrIid: Int) async throws {
        let pat = await MainActor.run { config.gitlabPAT }
        guard let pat else { throw MRWatcherError.notConfigured }
        let host = await MainActor.run { config.gitlabHost }
        let url = try buildURL(host: host, path: "/api/v4/projects/\(projectId)/merge_requests/\(mrIid)/notes", query: [:])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(pat, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["body": "/rebase"])
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    func approve(projectId: Int, mrIid: Int) async throws {
        let pat = await MainActor.run { config.gitlabPAT }
        guard let pat else { throw MRWatcherError.notConfigured }
        let host = await MainActor.run { config.gitlabHost }
        let url = try buildURL(
            host: host,
            path: "/api/v4/projects/\(projectId)/merge_requests/\(mrIid)/approve",
            query: [:]
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(pat, forHTTPHeaderField: "PRIVATE-TOKEN")
        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    private func buildURL(host: String, path: String, query: [String: String]) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw MRWatcherError.invalidHost(host) }
        return url
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw MRWatcherError.nonHTTPResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw MRWatcherError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw MRWatcherError.invalidResponse(http.statusCode) }
    }
}

extension MRWatcherError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "PAT non configuré"
        case .invalidHost(let h): return "Hôte invalide : \(h)"
        case .unauthorized: return "Non autorisé (PAT invalide ou scope manquant)"
        case .invalidResponse(let code): return "Erreur HTTP \(code)"
        case .nonHTTPResponse: return "Réponse non-HTTP"
        }
    }
}
