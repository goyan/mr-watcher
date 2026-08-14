import SwiftUI

struct SetupView: View {
    var onDismiss: (() -> Void)? = nil
    var onSaved: (() -> Void)? = nil
    @State private var pat: String = ""
    @State private var host: String = ConfigManager.shared.gitlabHost
    @State private var username: String = ConfigManager.shared.gitlabUsername ?? ""
    @State private var saved = false
    @State private var errorMsg: String? = nil

    var body: some View {
        Text("Configuration MR Watcher").font(.headline)

        // NOTE: SecureField/TextField may need .window style MenuBarExtra for full interactivity
        SecureField("GITLAB_PAT", text: $pat)

        TextField("GITLAB_HOST", text: $host)

        TextField("GITLAB_USERNAME", text: $username)

        if let err = errorMsg {
            Text("⚠️ \(err)").foregroundStyle(.red).font(.caption)
        }

        Button(saved ? "✅ Sauvegardé" : "Sauvegarder") {
            save()
        }
        .disabled(pat.isEmpty || host.isEmpty || username.isEmpty || saved)

        if onDismiss != nil {
            Button("Annuler") { onDismiss?() }
        }
    }

    private func save() {
        var h = host
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        if h.hasSuffix("/") { h = String(h.dropLast()) }

        // Bug 3: use homeDirectoryForCurrentUser (safe when launched by LaunchServices)
        let fm = FileManager.default
        let envURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(".env")
        let envPath = envURL.path

        do {
            // Bug 1: distinguish "file absent" from "read failure" — abort on failure
            var content = ""
            if fm.fileExists(atPath: envPath) {
                guard let secureContents = SecureDotEnvFile.readContents(at: envURL) else {
                    errorMsg = "~/.env doit appartenir à l'utilisateur et être en 0600"
                    return
                }
                content = secureContents
            }
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { line in
                    !line.hasPrefix("GITLAB_PAT=") &&
                    !line.hasPrefix("GITLAB_HOST=") &&
                    !line.hasPrefix("GITLAB_USERNAME=") &&
                    !line.hasPrefix("export GITLAB_PAT=") &&
                    !line.hasPrefix("export GITLAB_HOST=") &&
                    !line.hasPrefix("export GITLAB_USERNAME=")
                }
            content = lines.joined(separator: "\n")
            if !content.hasSuffix("\n") && !content.isEmpty { content += "\n" }
            content += "GITLAB_PAT=\(pat)\nGITLAB_HOST=\(h)\nGITLAB_USERNAME=\(username)\n"
            try SecureDotEnvFile.replaceContents(content, at: envURL)
            errorMsg = nil
            saved = true
            ConfigManager.shared.reload()
            onSaved?()
            // Dismiss reconfiguration sheet after a brief moment to show the saved feedback
            if onDismiss != nil {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.8))
                    onDismiss?()
                }
            }
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
