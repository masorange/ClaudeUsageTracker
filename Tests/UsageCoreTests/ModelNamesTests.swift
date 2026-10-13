import XCTest
@testable import UsageCore

final class ModelNamesTests: XCTestCase {
    func testDisplayNames() {
        let cases: [(String, String)] = [
            ("anthropic/claude-opus-5-5", "Opus 5.5"),
            ("vertex_ai/claude-sonnet-5-5", "Sonnet 5.5"),
            ("claude-haiku-4-5-20251001", "Haiku 4.5"),
            ("anthropic/claude-fable-5-1", "Fable 5.1"),
            ("anthropic/claude-opus-5", "Opus 5"),
            ("claude-3-5-sonnet-20241022", "claude-3-5-sonnet-20241022"),
            ("openai/gpt-5", "gpt-5"),
            ("mcp: grafana-query_loki_logs", "mcp: grafana-query_loki_logs"),
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(ModelNames.displayName(for: raw), expected, raw)
        }
    }
}
