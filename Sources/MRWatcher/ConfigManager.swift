import Foundation
import Security
import Darwin

enum SecureDotEnvFile {
    static func readContents(at url: URL) -> String? {
        let descriptor = url.path.withCString {
            open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        var fileInfo = stat()
        guard fstat(descriptor, &fileInfo) == 0,
              (fileInfo.st_mode & S_IFMT) == S_IFREG,
              fileInfo.st_uid == getuid(),
              (fileInfo.st_mode & 0o077) == 0 else {
            return nil
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        guard let data = try? handle.readToEnd(),
              let contents = String(data: data, encoding: .utf8) else {
            return nil
        }
        return contents
    }

    static func replaceContents(_ contents: String, at url: URL) throws {
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let descriptor = temporaryURL.path.withCString {
            open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { throw posixError() }

        var shouldRemoveTemporaryFile = true
        defer {
            close(descriptor)
            if shouldRemoveTemporaryFile {
                _ = temporaryURL.path.withCString { unlink($0) }
            }
        }

        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else { throw posixError() }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        handle.write(Data(contents.utf8))
        try handle.synchronize()

        let renameResult = temporaryURL.path.withCString { temporaryPath in
            url.path.withCString { destinationPath in
                rename(temporaryPath, destinationPath)
            }
        }
        guard renameResult == 0 else { throw posixError() }
        shouldRemoveTemporaryFile = false
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

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
        guard let contents = SecureDotEnvFile.readContents(at: envURL) else { return [:] }
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
