import XCTest
@testable import UsageCore

final class APIKeyLocatorTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func write(_ text: String, to relativePath: String) throws {
        let url = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func settings(baseURL: String, token: String) -> String {
        #"{"env":{"ANTHROPIC_BASE_URL":"\#(baseURL)","ANTHROPIC_AUTH_TOKEN":"\#(token)"}}"#
    }

    func testFindsKeyInClaudeSettingsPointingAtProxy() throws {
        try write(settings(baseURL: "https://llm.tools.cloud.masorange.es", token: "sk-settings"), to: ".claude/settings.json")
        XCTAssertEqual(APIKeyLocator.detect(home: home, environment: [:]), "sk-settings")
    }

    func testIgnoresSettingsForOtherHosts() throws {
        try write(settings(baseURL: "https://api.anthropic.com", token: "sk-other"), to: ".claude/settings.json")
        XCTAssertNil(APIKeyLocator.detect(home: home, environment: [:]))
    }

    func testChecksConfigDirFirstThenProfiles() throws {
        try write(settings(baseURL: "https://llm.tools.cloud.masorange.es/", token: "sk-custom"), to: "custom/settings.json")
        try write(settings(baseURL: "https://llm.tools.cloud.masorange.es", token: "sk-work"), to: ".claude-work/settings.json")
        let custom = home.appendingPathComponent("custom").path
        XCTAssertEqual(APIKeyLocator.detect(home: home, environment: ["CLAUDE_CONFIG_DIR": custom]), "sk-custom")
        XCTAssertEqual(APIKeyLocator.detect(home: home, environment: [:]), "sk-work")
    }

    func testSkipsMalformedSettings() throws {
        try write("{ not json", to: ".claude/settings.json")
        try write(settings(baseURL: "https://llm.tools.cloud.masorange.es", token: "sk-good"), to: ".claude-work/settings.json")
        XCTAssertEqual(APIKeyLocator.detect(home: home, environment: [:]), "sk-good")
    }

    func testFindsLiteralExportInShellProfile() throws {
        try write("""
        export ANTHROPIC_BASE_URL="https://llm.tools.cloud.masorange.es"
        export ANTHROPIC_AUTH_TOKEN="sk-shell" # LiteLLM
        """, to: ".zshrc")
        XCTAssertEqual(APIKeyLocator.detect(home: home, environment: [:]), "sk-shell")
    }

    func testIgnoresVariableExports() throws {
        try write("""
        export ANTHROPIC_BASE_URL="https://llm.tools.cloud.masorange.es"
        export ANTHROPIC_AUTH_TOKEN="$litellm_token"
        export ANTHROPIC_AUTH_TOKEN=$(security find-generic-password -w)
        """, to: ".zshrc")
        XCTAssertNil(APIKeyLocator.detect(home: home, environment: [:]))
    }

    func testIgnoresProfilesWithoutProxyURL() throws {
        try write("export ANTHROPIC_AUTH_TOKEN=sk-elsewhere\n", to: ".bashrc")
        XCTAssertNil(APIKeyLocator.detect(home: home, environment: [:]))
    }
}
