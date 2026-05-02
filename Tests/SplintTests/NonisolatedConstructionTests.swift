import Testing

@testable import Splint

/// Compilation success IS the contract: this suite is intentionally NOT
/// `@MainActor`-isolated, so any `init` it calls must be `nonisolated`.
/// If a covered type's `init` regresses to main-actor isolation, this
/// file fails to build — which is what proves the guarantee.
///
/// Property reads on the constructed instances would require re-entering
/// the main actor; this suite does not exercise them. The point is the
/// init call site, not post-init behavior (covered by the per-type suites).
@Suite("Nonisolated construction")
struct NonisolatedConstructionTests {
  @Test func selectionConstructsFromNonisolatedContext() {
    let selection = Selection<String>()
    _ = selection
  }

  @Test func jobConstructsFromNonisolatedContext() {
    let job = Job<Int>()
    _ = job
  }
}
