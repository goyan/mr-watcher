import Foundation

struct JiraIssueStatus {
    let name: String          // "À tester", "Code review", "Prêt à déployer", "ON PROD"…
    let categoryKey: String   // "new" | "indeterminate" | "done"
    let isStale: Bool         // ticket done (categoryKey == "done") mais MR encore ouverte
}

@MainActor
final class JiraService {
    private let acliPath: String

    init(config: ConfigManager) {
        let candidates = ["/opt/homebrew/bin/acli", "/usr/local/bin/acli"]
        acliPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/acli"
    }

    var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: acliPath) }

    var availabilityErrorDescription: String {
        "La commande acli est introuvable ou non exécutable : \(acliPath)"
    }

    func sanitizedErrorDescription(for error: Error) -> String {
        Self.sanitize(error.localizedDescription)
    }

    func fetchIssueStatus(issueKey: String) async throws -> JiraIssueStatus {
        guard issueKey.range(of: #"^[A-Z][A-Z0-9]{1,20}-[0-9]{1,10}$"#, options: .regularExpression) != nil else {
            throw URLError(.badURL)
        }
        let path = acliPath
        let data = try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: path)
                    proc.arguments = ["jira", "workitem", "view", issueKey, "--fields", "status", "--json"]
                    proc.environment = [
                        "HOME": NSHomeDirectory(),
                        "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                    ]
                    let outPipe = Pipe()
                    let errPipe = Pipe()
                    proc.standardOutput = outPipe
                    proc.standardError = errPipe
                    proc.terminationHandler = { p in
                        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                        if p.terminationStatus == 0 {
                            continuation.resume(returning: outData)
                        } else {
                            let errMsg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "acli error"
                            continuation.resume(throwing: URLError(
                                .badServerResponse,
                                userInfo: [NSLocalizedDescriptionKey: Self.sanitize(errMsg)]
                            ))
                        }
                    }
                    do {
                        try proc.run()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            },
            onCancel: {
                // Process terminates naturally when the continuation is abandoned
            }
        )

        struct Response: Codable {
            struct Fields: Codable {
                struct Status: Codable {
                    let name: String
                    struct Category: Codable {
                        let key: String
                    }
                    let statusCategory: Category
                }
                let status: Status
            }
            let fields: Fields
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let categoryKey = decoded.fields.status.statusCategory.key
        return JiraIssueStatus(
            name: decoded.fields.status.name,
            categoryKey: categoryKey,
            isStale: categoryKey == "done"
        )
    }

    nonisolated private static func sanitize(_ description: String) -> String {
        let secretValue = #"(?:[^\s"'&,}\]]+)"#
        let secretName = #"(?:access[ _-]?token|refresh[ _-]?token|token|api[ _-]?key|apikey|pat|password|passwd)"#
        return description
            .replacingOccurrences(
                of: #"(?im)(authorization\s*:\s*)(?:bearer\s+)?.*$"#,
                with: "$1<redacted>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)\bbearer\s+[A-Za-z0-9._~+/-]+=*\b"#,
                with: "Bearer <redacted>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)\b(?:bearer|pat)\s+"# + secretValue,
                with: "<redacted>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)([?&]"# + secretName + #"=)"# + secretValue,
                with: "$1<redacted>",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)(["']?"# + secretName + #"["']?\s*[:=]\s*["']?)"# + secretValue,
                with: "$1<redacted>",
                options: .regularExpression
            )
    }
}
