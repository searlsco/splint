import Testing

@testable import Splint

@Suite("Phase")
struct PhaseTests {
  @Test func idleEqualsIdle() {
    #expect(Phase.idle == Phase.idle)
  }

  @Test func runningEqualsRunning() {
    #expect(Phase.running == Phase.running)
  }

  @Test func completedEqualsCompleted() {
    #expect(Phase.completed == Phase.completed)
  }

  @Test func failedEqualsFailedWithSameMessage() {
    #expect(Phase.failed("boom") == Phase.failed("boom"))
  }

  @Test func failedDiffersByMessage() {
    #expect(Phase.failed("x") != Phase.failed("y"))
  }

  @Test func differentCasesNotEqual() {
    #expect(Phase.idle != Phase.running)
    #expect(Phase.completed != Phase.failed("x"))
  }

  @Test func phaseIsSendable() {
    // Compile-time check: Phase must satisfy Sendable.
    func requireSendable<T: Sendable>(_: T.Type) {}
    requireSendable(Phase.self)
  }
}
