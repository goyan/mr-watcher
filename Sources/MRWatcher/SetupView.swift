import SwiftUI

struct SetupView: View {
    var onDismiss: (() -> Void)? = nil
    var onSaved: (() -> Void)? = nil
    @State private var pat: String = ""
    @State private var host: String = ConfigManager.shared.gitlabHost
    @State private var username: String = ConfigManager.shared.gitlabUsername ?? ""
    @State private var reviewLabels: String = ConfigManager.shared.reviewLabelsInput
    @State private var jiraBaseURL: String = ConfigManager.shared.jiraBaseURL
    @State private var ticketPrefix: String = ConfigManager.shared.ticketPrefix
    @State private var saved = false
    @State private var errorMsg: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("GitLab") {
                    SecureField("Token d'accès", text: $pat)
                    Text("Laissez vide pour conserver le token actuel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Hôte GitLab", text: $host, prompt: Text("gitlab.exemple.com"))

                    TextField("Nom d'utilisateur", text: $username, prompt: Text("prenom.nom"))
                }

                Section("Labels à surveiller") {
                    TextField("", text: $reviewLabels, prompt: Text("Indigo, indigo"), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(1...3)
                }

                Section("Jira") {
                    TextField("URL Jira", text: $jiraBaseURL, prompt: Text("https://votre-org.atlassian.net"))
                    Text("Laissez vide si vous n'utilisez pas Jira : les tickets resteront affichés, sans être cliquables.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Préfixe de ticket", text: $ticketPrefix, prompt: Text(ConfigManager.defaultTicketPrefix))
                    Text("Cherché dans le nom de branche puis dans le titre de la MR. Par défaut : PROD, donnant PROD-12345.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let err = errorMsg {
                    Text("⚠️ \(err)")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .onChange(of: pat) { _, _ in saved = false }
            .onChange(of: host) { _, _ in saved = false }
            .onChange(of: username) { _, _ in saved = false }
            .onChange(of: reviewLabels) { _, _ in saved = false }
            .onChange(of: jiraBaseURL) { _, _ in saved = false }
            .onChange(of: ticketPrefix) { _, _ in saved = false }

            Divider()

            HStack {
                if onDismiss != nil {
                    Button("Annuler") { onDismiss?() }
                }

                Spacer()

                Button(saved ? "✅ Sauvegardé" : "Sauvegarder") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(saved)
            }
            .padding()
        }
    }

    private func save() {
        // Réglages GitLab : uniquement si les trois champs sont renseignés, comme
        // avant la fusion des boutons — le token n'est jamais réaffiché, donc un
        // champ vide signifie « je ne change pas mon token », pas « efface-le ».
        if !pat.isEmpty, !host.isEmpty, !username.isEmpty {
            guard saveGitLabConfig() else { return }
        }

        ConfigManager.shared.saveReviewLabels(reviewLabels)
        reviewLabels = ConfigManager.shared.reviewLabelsInput

        ConfigManager.shared.saveJiraBaseURL(jiraBaseURL)
        ConfigManager.shared.saveTicketPrefix(ticketPrefix)
        jiraBaseURL = ConfigManager.shared.jiraBaseURL
        ticketPrefix = ConfigManager.shared.ticketPrefix

        errorMsg = nil
        saved = true
        onSaved?()
        // Dismiss reconfiguration sheet after a brief moment to show the saved feedback
        if onDismiss != nil {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.8))
                onDismiss?()
            }
        }
    }

    /// Écrit `~/.env` (GITLAB_PAT/HOST/USERNAME) et recharge `ConfigManager`.
    /// Retourne `false` si l'écriture a échoué (`errorMsg` déjà renseigné).
    private func saveGitLabConfig() -> Bool {
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
                    return false
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
            ConfigManager.shared.reload()
            return true
        } catch {
            errorMsg = error.localizedDescription
            return false
        }
    }
}
