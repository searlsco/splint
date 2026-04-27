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

  /// Run an async operation, transferring its result into the Job's
  /// ``value``.
  ///
  /// Cancels any in-flight work. ``phase`` transitions to
  /// ``Phase/running`` immediately, then ``Phase/completed`` or
  /// ``Phase/failed(_:)`` when `task` resolves.
  ///
  /// The `task` closure is marked `sending` rather than `@Sendable`.
  /// This uses region-based isolation (Swift 6.0+) to let the closure
  /// capture non-`Sendable` values — like `@MainActor`-isolated
  /// services or view state — at the call site, as long as those
  /// values are in a disconnected isolation region when `run` is
  /// called. In practice: capture what you need once, do not also
  /// reference it from elsewhere after passing it in. See
  /// [SE-0430](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0430-transferring-parameters-and-results.md).
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

  /// Suspend until the most recent ``run(priority:task:)`` (if any)
  /// reaches a terminal ``Phase`` — `.completed` or `.failed`. Returns
  /// immediately if no run has been kicked off, or if the most recent
  /// run already finished. ``cancel()`` and ``reset()`` clear the
  /// underlying task, so calls following them also return
  /// immediately.
  ///
  /// Use this to sequence "run then proceed" flows in production
  /// code: `.refreshable` closures, multi-step async pipelines, or
  /// view-driven async work where the next step needs the prior
  /// ``value``.
  ///
  /// ```swift
  /// job.run { await fetchUser() }
  /// await job.awaitSettled()
  /// // job.value (or job.phase == .failed) now reflects the run
  /// ```
  ///
  /// Does not propagate cancellation. If the calling `Task` is
  /// cancelled mid-await, this method still waits for the in-flight
  /// task to finish — the task is owned by the job and continues
  /// regardless. Callers needing to bail early on cancellation should
  /// follow with `try Task.checkCancellation()`.
  public func awaitSettled() async {
    await runningTask?.value
  }
}
