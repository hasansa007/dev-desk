import Foundation
import XCTest
@testable import DeskCore

private final class ConcurrencyProbe {
    private let lock = NSLock()
    private var running = 0
    private var highest = 0

    var peak: Int { lock.withLock { highest } }

    func enter() {
        lock.withLock {
            running += 1
            highest = max(highest, running)
        }
    }

    func leave() { lock.withLock { running -= 1 } }
}

final class CommandGateTests: XCTestCase {
    func testGateNeverAdmitsMoreThanItsLimit() async {
        let gate = CommandGate(limit: 3)
        let probe = ConcurrencyProbe()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    guard (try? await gate.acquire()) != nil else { return }
                    probe.enter()
                    try? await Task.sleep(nanoseconds: 20_000_000)
                    probe.leave()
                    await gate.release()
                }
            }
        }
        XCTAssertLessThanOrEqual(probe.peak, 3)
        XCTAssertGreaterThanOrEqual(probe.peak, 2)
    }

    func testCancelledWaiterThrowsAndDoesNotKeepTheFreedSlot() async throws {
        let gate = CommandGate(limit: 1)
        try await gate.acquire()
        let waiter = Task { try await gate.acquire() }
        try await Task.sleep(nanoseconds: 50_000_000)
        waiter.cancel()
        do {
            try await waiter.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {}

        await gate.release()
        let reacquired = Task { () throws -> Bool in
            try await gate.acquire()
            return true
        }
        let watchdog = Task {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            reacquired.cancel()
        }
        let result = try? await reacquired.value
        watchdog.cancel()
        XCTAssertEqual(result, true, "the cancelled waiter must not keep the slot")
    }

    func testEveryProcessRunnerSharesOneProcessWideGate() {
        XCTAssertTrue(ProcessRunner().gate === CommandGate.shared)
        XCTAssertTrue(ProcessRunner().gate === ProcessRunner().gate)
    }

    func testProcessRunnerRunsNoMoreCommandsThanItsGateAllows() async throws {
        let runner = ProcessRunner(gate: CommandGate(limit: 2))
        let started = Date()
        try await withThrowingTaskGroup(of: CommandResult.self) { group in
            for _ in 0..<4 {
                group.addTask { try await runner.run("sleep", ["0.3"], in: nil, timeout: 5) }
            }
            for try await result in group { XCTAssertTrue(result.succeeded) }
        }
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.55, "4 × 0.3s through 2 slots needs two waves")
    }

    func testCancellingARunTerminatesTheChildAndThrowsCancellationError() async {
        let started = Date()
        let run = Task { try await ProcessRunner().run("sleep", ["5"], in: nil, timeout: 10) }
        try? await Task.sleep(nanoseconds: 300_000_000)
        run.cancel()
        do {
            _ = try await run.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testCancelledRunGivesItsGateSlotBack() async throws {
        let runner = ProcessRunner(gate: CommandGate(limit: 1))
        let run = Task { try await runner.run("sleep", ["5"], in: nil, timeout: 10) }
        try await Task.sleep(nanoseconds: 300_000_000)
        run.cancel()
        _ = try? await run.value
        let started = Date()
        let echo = try await runner.run("echo", ["freed"], in: nil, timeout: 5)
        XCTAssertEqual(echo.stdout, "freed\n")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }
}
