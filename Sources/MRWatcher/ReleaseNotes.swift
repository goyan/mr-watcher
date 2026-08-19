import Foundation

enum ReleaseNotes {
    static let summary = loadSummary()

    private static func loadSummary() -> String {
        guard let url = Bundle.main.url(forResource: "RELEASE_NOTES", withExtension: "md"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return "Notes de version indisponibles."
        }

        let summary = contents
            .split(whereSeparator: \.isNewline)
            .map { line in
                var text = String(line)
                while text.first == "#" {
                    text.removeFirst()
                }
                return text.trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? "Notes de version indisponibles." : summary
    }
}
