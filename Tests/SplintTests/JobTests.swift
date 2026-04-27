import Foundation
import Testing

@testable import Splint

private struct Boom: Error {
  let msg: String
}

extension Boom: LocalizedError {
  var errorDescription: String? { msg }
}

/// Intentionally non-`Sendable`: a reference type with a mutable stored
/// property and no `Sendable` conformance. Under `@Sendable` this could
/// not be captured by `Job.run`'s closure; `sending` transfers it safely.
private final class NonSendableBox {
  var value: Int = 42
}

/// A small `@MainActor`-isolated service, mirroring the real-world
/// pattern of a view capturing an `@Environment` client and handing it
/// to `Job.run`.
@MainActor
private final class FakeMainActorService {
  func fetch() -> Int { 7 }
}

@MainActor
@Suite("Job")
struct JobTests {
  @Test func runTransitionsPhaseIdleToCompleted() async {
    let job = Job<Int>()
    #expect(job.phase == .idle)
    job.run { 42 }
    await waitUntil { job.phase == .completed }
    #expect(job.phase == .completed)
  }

  @Test func successfulRunSetsValue() async {
    let job = Job<Int>()
    job.run { 7 }
    await waitUntil { job.value == 7 }
    #expect(job.value == 7)
  }

  @Test func failedRunTransitionsToFailedWithMessage() async {
    let job = Job<Int>()
    job.run { throw Boom(msg: "nope") }
    await waitUntil {
      if case .failed = job.phase { true } else { false }
    }
    #expect(job.phase == .failed("nope"))
    #expect(job.value == nil)
  }

  @Test func cancelSetsPhaseIdlePreservesValue() async {
    let job = Job<Int>()
    job.run { 1 }
    await waitUntil { job.value == 1 }
    job.cancel()
    #expect(job.phase == .idle)
    #expect(job.value == 1)
  }

  @Test func cancelOnNeverRunIsNoop() {
    let job = Job<Int>()
    job.cancel()
    #expect(job.phase == .idle)
    #expect(job.value == nil)
  }

  @Test func resetClearsValueAndPhase() async {
    let job = Job<Int>()
    job.run { 9 }
    await waitUntil { job.value == 9 }
    job.reset()
    #expect(job.phase == .idle)
    #expect(job.value == nil)
  }

  @Test func runWhileRunningCancelsPrevious() async {
    let job = Job<Int>()
    job.run {
      try await Task.sleep(for: .milliseconds(200))
      return 1
    }
    job.run { 2 }
    await waitUntil { job.value == 2 }
    #expect(job.value == 2)
    #expect(job.phase == .completed)
  }

  @Test func errorConvenienceReturnsMessage() async {
    let job = Job<Int>()
    job.run { throw Boom(msg: "x") }
    await waitUntil {
      if case .failed = job.phase { true } else { false }
    }
    #expect(job.error == "x")
  }

  @Test func errorConvenienceNilWhenNotFailed() {
    let job = Job<Int>()
    #expect(job.error == nil)
  }

  @Test func isRunningReturnsCorrectBool() async {
    let job = Job<Int>()
    #expect(job.isRunning == false)
    job.run {
      try await Task.sleep(for: .milliseconds(100))
      return 1
    }
    await waitUntil { job.isRunning }
    #expect(job.isRunning == true)
    await waitUntil { !job.isRunning }
    #expect(job.isRunning == false)
  }

  @Test func valuePersistsAfterSubsequentFailure() async {
    let job = Job<Int>()
    job.run { 1 }
    await waitUntil { job.value == 1 }
    job.run { throw Boom(msg: "later") }
    await waitUntil {
      if case .failed = job.phase { true } else { false }
    }
    #expect(job.value == 1)
    #expect(job.phase == .failed("later"))
  }

  /// Proves the `priority:` argument is forwarded to the underlying
  /// `Task(priority:)`. `.background` is used because it sits far below
  /// the `@MainActor` context's inherited QoS — observing it inside the
  /// task can only happen if the parameter actually reached
  /// `Task(priority:)`.
  @Test func runForwardsPriorityToUnderlyingTask() async {
    let job = Job<TaskPriority>()
    job.run(priority: .background) { Task.currentPriority }
    await waitUntil { job.phase == .completed }
    #expect(job.value == .background)
  }

  /// Compile-guard for SE-0430: the `task:` parameter is `sending`, not
  /// `@Sendable`. A non-`Sendable` reference captured into the closure
  /// must compile here. The `#expect` is incidental — the load-bearing
  /// assertion is that this file compiles at all. Reverting `sending` →
  /// `@Sendable` on ``Job/run(priority:task:)`` would break compilation.
  @Test("compile-guard: closure may capture non-Sendable value (sending)")
  func compileGuardNonSendableCapture() async {
    let box = NonSendableBox()
    let job = Job<Int>()
    job.run { box.value }
    await waitUntil { job.phase == .completed }
    #expect(job.value == 42)
  }

  /// Compile-guard for SE-0430: a `@MainActor`-isolated service
  /// (analogous to an `@Environment` client in a SwiftUI view) can be
  /// captured by the `sending` closure. The `#expect` is incidental —
  /// the load-bearing assertion is that this file compiles.
  /// `FakeMainActorService` is not `Sendable`; under `@Sendable` the
  /// capture would fail.
  @Test("compile-guard: closure may capture @MainActor service (sending)")
  func compileGuardMainActorCapture() async {
    let service = FakeMainActorService()
    let job = Job<Int>()
    job.run { await service.fetch() }
    await waitUntil { job.phase == .completed }
    #expect(job.value == 7)
  }

  @Test func awaitSettledWaitsForInFlightRun() async {
    let gate = AsyncGate()
    let job = Job<Int>()
    job.run {
      await gate.wait()
      return 42
    }
    await waitUntil { job.phase == .running }
    Task { await gate.open() }
    await job.awaitSettled()
    #expect(job.phase == .completed)
    #expect(job.value == 42)
  }

  @Test func awaitSettledReturnsImmediatelyWhenIdle() async {
    let job = Job<Int>()
    await job.awaitSettled()
    #expect(job.phase == .idle)
  }

  @Test func awaitSettledReturnsAfterFailure() async {
    let job = Job<Int>()
    job.run { throw Boom(msg: "nope") }
    await job.awaitSettled()
    #expect(job.phase == .failed("nope"))
  }

  /// If a run is superseded while `awaitSettled()` is suspended, the
  /// method must continue waiting until the job reaches a settled
  /// phase — not return when the cancelled task resolves while a new
  /// task is still running.
  @Test func awaitSettledWaitsThroughSupersede() async {
    let gate2 = AsyncGate()
    let job = Job<String>()
    job.run {
      while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
      throw CancellationError()
    }
    await waitUntil { job.phase == .running }
    let settled = Task { @MainActor in
      await job.awaitSettled()
      return job.phase
    }
    try? await Task.sleep(for: .milliseconds(50))
    job.run {
      await gate2.wait()
      return "second"
    }
    try? await Task.sleep(for: .milliseconds(50))
    Task { await gate2.open() }
    let observedPhase = await settled.value
    #expect(observedPhase == .completed)
    #expect(job.value == "second")
  }
}
