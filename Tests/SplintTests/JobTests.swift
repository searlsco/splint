import Foundation
import Testing

@testable import Splint

private struct Boom: Error {
  let msg: String
}

extension Boom: LocalizedError {
  var errorDescription: String? { msg }
}

@MainActor
@Suite("Job")
struct JobTests {
  /// Poll until `condition` returns true or timeout elapses. Yields
  /// cooperatively so that @MainActor Task updates can land.
  private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool
  ) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

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
}
