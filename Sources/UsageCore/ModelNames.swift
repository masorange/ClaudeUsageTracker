import Foundation

public enum ModelNames {
    /// Human-friendly name for a raw model id, e.g. `anthropic/claude-opus-5-5` → `Opus 5.5`.
    /// Ids that don't follow the `claude-<family>-<version>` pattern are returned without the provider prefix.
    public static func displayName(for id: String) -> String {
        if id.hasPrefix("mcp:") { return id }
        let base = id.split(separator: "/").last.map(String.init) ?? id
        guard base.hasPrefix("claude-") else { return base }
        var parts = base.dropFirst("claude-".count).split(separator: "-").map(String.init)
        if let last = parts.last, last.count == 8, Int(last) != nil {
            parts.removeLast() // date snapshot suffix
        }
        guard let family = parts.first, family.first?.isLetter == true,
              parts.dropFirst().allSatisfy({ Int($0) != nil }) else { return base }
        let name = family.prefix(1).uppercased() + family.dropFirst()
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? name : "\(name) \(version)"
    }
}
