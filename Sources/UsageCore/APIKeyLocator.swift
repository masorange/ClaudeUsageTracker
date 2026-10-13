import Foundation

/// Finds the user's LiteLLM key in their Claude Code configuration so they don't have to paste it.
public enum APIKeyLocator {
    public static let proxyHost = "llm.tools.cloud.masorange.es"
    private static let shellProfiles = [".zshrc", ".zprofile", ".zshenv", ".bashrc", ".bash_profile"]
    private static let exportPrefix = "export ANTHROPIC_AUTH_TOKEN="

    public static func detect(home: URL, environment: [String: String]) -> String? {
        for file in settingsFiles(home: home, environment: environment) {
            if let key = keyFromSettings(file) { return key }
        }
        for name in shellProfiles {
            if let key = keyFromShellProfile(home.appendingPathComponent(name)) { return key }
        }
        return nil
    }

    /// `$CLAUDE_CONFIG_DIR`, `~/.claude`, then every `~/.claude-*` profile, in that order.
    static func settingsFiles(home: URL, environment: [String: String]) -> [URL] {
        var directories: [URL] = []
        if let custom = environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            directories.append(URL(fileURLWithPath: (custom as NSString).expandingTildeInPath))
        }
        directories.append(home.appendingPathComponent(".claude"))
        let profiles = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        directories += profiles.filter { $0.hasPrefix(".claude-") }.sorted().map { home.appendingPathComponent($0) }
        return directories.map { $0.appendingPathComponent("settings.json") }
    }

    static func keyFromSettings(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = json["env"] as? [String: Any],
              let baseURL = env["ANTHROPIC_BASE_URL"] as? String,
              URL(string: baseURL)?.host == proxyHost else { return nil }
        let key = (env["ANTHROPIC_AUTH_TOKEN"] as? String) ?? (env["ANTHROPIC_API_KEY"] as? String)
        return key.flatMap(usable)
    }

    /// Direct Anthropic keys must never be sent to the company proxy.
    private static func usable(_ key: String) -> String? {
        key.isEmpty || key.hasPrefix("sk-ant-") ? nil : key
    }

    /// Only literal values: exports built from variables or command substitution are ignored.
    static func keyFromShellProfile(_ url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8), text.contains(proxyHost) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(exportPrefix) else { continue }
            var value = String(trimmed.dropFirst(exportPrefix.count))
            // The value ends at the first unquoted separator: `; export …`, `&& …`, ` # comment`.
            if let end = value.firstIndex(where: { ";&| \t#".contains($0) }) { value = String(value[..<end]) }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            guard !value.contains("$"), !value.contains("`"), let key = usable(value) else { continue }
            return key
        }
        return nil
    }
}
