import Foundation
import Security

@MainActor
final class ConfigManager {
    static let shared = ConfigManager()

    private let keychainService = "mr-watcher"
    private let defaultHost = "gitlab.factory.fonciamillenium.net"

    private(set) var gitlabPAT: String?
    private(set) var gitlabHost: String = ""
    private(set) var gitlabUsername: String?

    var isConfigured: Bool {
        gitlabPAT != nil && gitlabUsername != nil
    }

    private init() {
        reload()
    }

    func reload() {
        let envValues = loadDotEnv()
        gitlabPAT = envValues["GITLAB_PAT"] ?? keychainValue(forKey: "GITLAB_PAT")
        let rawHost = envValues["GITLAB_HOST"] ?? keychainValue(forKey: "GITLAB_HOST") ?? defaultHost
        gitlabHost = normalizeHost(rawHost)
        gitlabUsername = envValues["GITLAB_USERNAME"] ?? keychainValue(forKey: "GITLAB_USERNAME")
    }

    private func normalizeHost(_ raw: String) -> String {
        var h = raw.trimmingCharacters(in: .whitespaces)
        for prefix in ["https://", "http://"] {
            if h.hasPrefix(prefix) { h = String(h.dropFirst(prefix.count)) }
        }
        return h.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func loadDotEnv() -> [String: String] {
        let envURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".env")
        guard let contents = try? String(contentsOf: envURL, encoding: .utf8) else { return [:] }
        return parseEnvContents(contents)
    }

    private func parseEnvContents(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            // Strip `export ` prefix
            if trimmed.hasPrefix("export ") {
                trimmed = String(trimmed.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            var value = String(parts[1])
            // Strip inline comment (unquoted)
            if !value.hasPrefix("\"") && !value.hasPrefix("'"), let commentIdx = value.firstIndex(of: "#") {
                value = String(value[..<commentIdx])
            }
            value = value.trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes
            if value.count >= 2 {
                let first = value[value.startIndex], last = value[value.index(before: value.endIndex)]
                if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                    value = String(value.dropFirst().dropLast())
                }
            }
            result[key] = value
        }
        return result
    }

    private func keychainValue(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService as CFString,
            kSecAttrAccount: key as CFString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
