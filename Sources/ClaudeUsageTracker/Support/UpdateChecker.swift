import AppKit
import Foundation

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}

/// Checks GitHub for a newer release of the app.
@MainActor
final class UpdateChecker: ObservableObject {
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/masorange/ClaudeUsageTracker/releases/latest")!

    @Published private(set) var updateAvailable = false
    @Published private(set) var latestVersion = ""
    private var releasePage: URL?

    func check() async {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        latestVersion = latest
        releasePage = page
        updateAvailable = Self.isNewer(latest, than: AppInfo.version)
    }

    func openReleasePage() {
        if let releasePage { NSWorkspace.shared.open(releasePage) }
    }

    static func isNewer(_ latest: String, than current: String) -> Bool {
        let lhs = latest.split(separator: ".").compactMap { Int($0) }
        let rhs = current.split(separator: ".").compactMap { Int($0) }
        guard lhs.count >= 3, rhs.count >= 3 else { return false }
        return lhs.lexicographicallyPrecedes(rhs) == false && lhs != rhs
    }
}
