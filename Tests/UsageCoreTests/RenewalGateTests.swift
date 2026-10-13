import XCTest
@testable import UsageCore

final class RenewalGateTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.sync { value += 1 } }
        var count: Int { lock.sync { value } }
    }

    @MainActor
    func testDoesNotStartSilentRenewalWhileInteractiveLoginIsOpen() async {
        let calls = Counter()
        let gate = RenewalGate { calls.increment(); return .renewed }
        gate.interactiveLoginActive = true
        let result = await gate.renew()
        XCTAssertEqual(result, .needsLogin)
        XCTAssertEqual(calls.count, 0)
    }

    @MainActor
    func testConcurrentRenewalsShareOneAttempt() async {
        let calls = Counter()
        let gate = RenewalGate {
            calls.increment()
            try? await Task.sleep(nanoseconds: 100_000_000)
            return .renewed
        }
        async let first = gate.renew()
        async let second = gate.renew()
        let results = await [first, second]
        XCTAssertEqual(results, [.renewed, .renewed])
        XCTAssertEqual(calls.count, 1)
    }

    @MainActor
    func testRenewsAgainAfterPreviousAttemptFinished() async {
        let calls = Counter()
        let gate = RenewalGate { calls.increment(); return .offline }
        _ = await gate.renew()
        _ = await gate.renew()
        XCTAssertEqual(calls.count, 2)
    }
}
