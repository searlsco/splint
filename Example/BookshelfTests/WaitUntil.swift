import Foundation
import Testing

/// Polls `condition` until it returns true or `timeout` elapses, yielding
/// cooperatively between checks so `@MainActor` Task updates can land.
/// On timeout, fails at the call site rather than returning silently.
@MainActor
func waitUntil(
  timeout: Duration = .seconds(2),
  _ condition: () -> Bool,
  sourceLocation: SourceLocation = #_sourceLocation
) async {
  let deadline = ContinuousClock.now.advanced(by: timeout)
  while ContinuousClock.now < deadline {
    if condition() { return }
    try? await Task.sleep(for: .milliseconds(5))
  }
  #expect(condition(), "waitUntil timed out after \(timeout)", sourceLocation: sourceLocation)
}
