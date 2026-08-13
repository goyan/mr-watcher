import Foundation

struct JiraIssueStatus {
    let name: String          // "À tester", "Code review", "Prêt à déployer", "ON PROD"…
    let categoryKey: String   // "new" | "indeterminate" | "done"
    let isStale: Bool         // ticket done (categoryKey == "done") mais MR encore ouverte
}

@MainActor
final class JiraService {
    private let config: ConfigManager
    private let session: URLSession

    init(config: ConfigManager) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: sessionConfig)
    }

    func fetchIssueStatus(issueKey: String) async throws -> JiraIssueStatus {
        guard let email = config.jiraEmail, let token = config.jiraToken else {
            throw URLError(.userAuthenticationRequired)
        }
        let urlString = "https://fonciamillenium.atlassian.net/rest/api/3/issue/\(issueKey)?fields=status"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        let credentials = "\(email):\(token)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fields = json["fields"] as? [String: Any],
              let status = fields["status"] as? [String: Any],
              let name = status["name"] as? String,
              let statusCategory = status["statusCategory"] as? [String: Any],
              let categoryKey = statusCategory["key"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        return JiraIssueStatus(name: name, categoryKey: categoryKey, isStale: categoryKey == "done")
    }
}
