import Foundation
import Observation

/// An observable async-operation lifecycle. Replaces the `isLoading` /
/// `error` / `data` trio that tends to drift onto a view model and become a
/// god-object seed.
///
/// Two stored properties — ``phase`` (lifecycle) and ``value`` (result) —
/// are observed independently: views reading only one do not re-evaluate
/// when the other changes.
@Observable
@MainActor
public final class Job<Value: Sendable> {
  /// Current lifecycle phase.
  public private(set) var phase: Phase = .idle
  /// Last successful result, if any. Persists across ``cancel()`` and
  /// across subsequent failures — only ``reset()`` clears it.
  public private(set) var value: Value?

  @ObservationIgnored private var runningTask: Task<Void, Never>?

  public init() {}

  /// Run `task`. Cancels any in-flight work. Phase transitions to
  /// ``Phase/running`` immediately, then ``Phase/completed`` or
  /// ``Phase/failed(_:)`` when `task` resolves.
  public func run(
    priority: TaskPriority? = nil,
    task: sending @escaping () async throws -> Value
  ) {
    runningTask?.cancel()
    phase = .running
    runningTask = Task(priority: priority) { [weak self] in
      do {
        let result = try await task()
        guard !Task.isCancelled else { return }
        self?.value = result
        self?.phase = .completed
      } catch {
        guard !Task.isCancelled else { return }
        self?.phase = .failed(error.localizedDescription)
      }
    }
  }

  /// Cancel the in-flight task and return to ``Phase/idle``. Preserves
  /// ``value`` so that a cancelled retry does not wipe a prior success.
  public func cancel() {
    runningTask?.cancel()
    runningTask = nil
    phase = .idle
  }

  /// Cancel and clear ``value``. Use when navigating away and the result
  /// is no longer relevant.
  public func reset() {
    cancel()
    value = nil
  }

  /// The error message if ``phase`` is ``Phase/failed(_:)``, otherwise `nil`.
  public var error: String? {
    if case .failed(let e) = phase { e } else { nil }
  }

  /// Whether the job is currently running.
  public var isRunning: Bool {
    if case .running = phase { true } else { false }
  }
}
