import AppKit
import SwiftUI
import UsageCore

/// Brand logo of a model provider, bundled in `Contents/Resources/ProviderIcons` by build.sh.
struct ProviderIconView: View {
    let provider: ModelProvider?
    var size: CGFloat = 16
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let icon = provider?.icon, let image = Self.image(named: icon.fileName(dark: colorScheme == .dark)) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityLabel(provider?.rawValue ?? "")
        } else {
            Image(systemName: provider == nil ? "square.stack.3d.up" : "cpu")
                .font(.system(size: size * 0.75))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }

    private static var cache: [String: NSImage] = [:]

    private static func image(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "ProviderIcons"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }
}
