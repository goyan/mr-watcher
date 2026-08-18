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

    enum CodingKeys: String, CodingKey {
        case id, iid, title, state
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
}

private struct DiscussionResponse: Codable {
    let individualNote: Bool
    let notes: [NoteEntry]
    enum CodingKeys: String, CodingKey { case individualNote = "individual_note"; case notes }
    struct NoteEntry: Codable { let resolvable: Bool; let resolved: Bool? }
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
    struct ApproverUser: Codable { let username: String }
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

    func fetchApprovals(projectId: Int, mrIid: Int) async throws -> MRApprovals {
        let pat = await MainActor.run { config.gitlabPAT }
        guard let pat else { throw MRWatcherError.notConfigured }
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

        let discussionsUrl = try buildURL(
            host: host,
            path: "/api/v4/projects/\(projectId)/merge_requests/\(mrIid)/discussions",
            query: ["per_page": "100"]
        )
        let discussionsRequest = {
            var r = URLRequest(url: discussionsUrl)
            r.setValue(pat, forHTTPHeaderField: "PRIVATE-TOKEN")
            return r
        }()

        async let approvalsResult = session.data(for: approvalsRequest)
        async let discussionsResult = session.data(for: discussionsRequest)

        let (approvalsData, approvalsResponse) = try await approvalsResult
        try validateResponse(approvalsResponse)

        let (discussionsData, discussionsResponse) = try await discussionsResult
        try validateResponse(discussionsResponse)

        let decoded = try JSONDecoder().decode(ApprovalsResponse.self, from: approvalsData)
        let humanApprovals = decoded.approvedBy.filter { entry in
            let u = entry.user.username
            return !u.contains("_bot_") && !u.hasSuffix("-bot") && !u.hasPrefix("bot-")
        }

        let discussions = try JSONDecoder().decode([DiscussionResponse].self, from: discussionsData)
        let unresolvedCount = discussions.filter { discussion in
            guard !discussion.individualNote,
                  let firstNote = discussion.notes.first,
                  firstNote.resolvable else { return false }
            return firstNote.resolved == false
        }.count

        let given = humanApprovals.count
        let required = given + decoded.approvalsLeft
        return MRApprovals(
            required: required,
            given: given,
            unresolvedThreads: unresolvedCount
        )
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

    func findBuildAffectedJob(projectId: Int, pipelineId: Int) async throws -> (id: Int, status: String)? {
        let pat = await MainActor.run { config.gitlabPAT }
        guard let pat else { throw MRWatcherError.notConfigured }
        let host = await MainActor.run { config.gitlabHost }

        let url = try buildURL(
            host: host,
            path: "/api/v4/projects/\(projectId)/pipelines/\(pipelineId)/jobs",
            query: ["per_page": "100"]
        )
        var request = URLRequest(url: url)
        request.setValue(pat, forHTTPHeaderField: "PRIVATE-TOKEN")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        struct JobEntry: Codable {
            let id: Int
            let name: String
            let status: String
        }
        let jobs = try JSONDecoder().decode([JobEntry].self, from: data)
        return jobs.first { $0.name == "build affected" }.map { ($0.id, $0.status) }
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
