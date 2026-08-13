import SwiftUI

struct SetupView: View {
    var onDismiss: (() -> Void)? = nil
    var onSaved: (() -> Void)? = nil
    @State private var pat: String = ""
    @State private var host: String = ConfigManager.shared.gitlabHost
    @State private var username: String = ConfigManager.shared.gitlabUsername ?? ""
    @State private var jiraEmail: String = ConfigManager.shared.jiraEmail ?? ""
    @State private var jiraToken: String = ""
    @State private var saved = false
    @State private var errorMsg: String? = nil

    var body: some View {
        Text("Configuration MR Watcher").font(.headline)

        // NOTE: SecureField/TextField may need .window style MenuBarExtra for full interactivity
        SecureField("GITLAB_PAT", text: $pat)

        TextField("GITLAB_HOST", text: $host)

        TextField("GITLAB_USERNAME", text: $username)

        Divider()
        Text("Jira (optionnel)").font(.caption).foregroundStyle(.secondary)
        TextField("JIRA_EMAIL", text: $jiraEmail)
        SecureField("JIRA_API_TOKEN", text: $jiraToken)

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
        // Bug 4: resolve symlink so atomic write targets the real inode
        let url = envURL.resolvingSymlinksInPath()

        do {
            // Bug 1: distinguish "file absent" from "read failure" — abort on failure
            var content = ""
            if fm.fileExists(atPath: envPath) {
                do { content = try String(contentsOf: url, encoding: .utf8) }
                catch { errorMsg = "Lecture de ~/.env impossible : \(error.localizedDescription)"; return }
            }
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { line in
                    !line.hasPrefix("GITLAB_PAT=") &&
                    !line.hasPrefix("GITLAB_HOST=") &&
                    !line.hasPrefix("GITLAB_USERNAME=") &&
                    !line.hasPrefix("export GITLAB_PAT=") &&
                    !line.hasPrefix("export GITLAB_HOST=") &&
                    !line.hasPrefix("export GITLAB_USERNAME=") &&
                    // Ne filtrer Jira que si on va réécrire la valeur
                    (!jiraEmail.isEmpty ? !line.hasPrefix("JIRA_EMAIL=") && !line.hasPrefix("export JIRA_EMAIL=") : true) &&
                    (!jiraToken.isEmpty ? !line.hasPrefix("JIRA_API_TOKEN=") && !line.hasPrefix("export JIRA_API_TOKEN=") : true)
                }
            content = lines.joined(separator: "\n")
            if !content.hasSuffix("\n") && !content.isEmpty { content += "\n" }
            content += "GITLAB_PAT=\(pat)\nGITLAB_HOST=\(h)\nGITLAB_USERNAME=\(username)\n"
            if !jiraEmail.isEmpty { content += "JIRA_EMAIL=\(jiraEmail)\n" }
            if !jiraToken.isEmpty { content += "JIRA_API_TOKEN=\(jiraToken)\n" }
            // Bug 2: create file with 0600 before write so the new inode never has 0644
            if !fm.fileExists(atPath: envPath) {
                fm.createFile(atPath: envPath, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            try content.write(to: url, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: envPath)
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
