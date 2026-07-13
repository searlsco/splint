import Foundation
import Observation

/// A single typed user preference backed by `UserDefaults`.
///
/// Prefer many small `Setting` instances over a single "settings object":
/// each `Setting` is its own observation point, so views reading one
/// setting do not re-evaluate when an unrelated setting changes.
///
/// Multiple `Setting` instances bound to the same key stay in sync
/// automatically via `UserDefaults` key-value observation. A write to
/// one instance — or a direct `UserDefaults.set(_:forKey:)` from
/// anywhere — propagates to every other `Setting` on that key. When the
/// store is an App Group suite (`UserDefaults(suiteName: "group.…")`),
/// the same mechanism keeps Settings in sync between the host app and
/// its extensions via `userdefaultsd`.
///
/// Keys containing a dot (e.g. `"learner.targetLanguage"`) can't use
/// KVO — it treats the dot as key-path traversal and never fires — so
/// they sync via `UserDefaults.didChangeNotification` instead. That
/// fallback is same-process only: cross-process App Group sync
/// requires a dot-free key.
@Observable
@MainActor
public final class Setting<Value: SettingValue> {
  /// The current value. Writes persist to the underlying store.
  public var value: Value {
    didSet {
      // Skip persisting when we're applying an externally-observed
      // change — otherwise we'd write back the same value we just
      // observed and bounce KVO indefinitely.
      guard !isApplyingExternalChange else { return }
      persist()
    }
  }

  @ObservationIgnored private var isApplyingExternalChange = false
  @ObservationIgnored private let key: String
  @ObservationIgnored private let defaultValue: Value
  // `store` and `observer` must be reachable from `deinit`, which runs
  // nonisolated on `@MainActor` classes in Swift 6. Both are
  // thread-safe to touch from `deinit`: `UserDefaults.removeObserver`
  // is documented as thread-safe, and `observer` is never mutated
  // after `init` returns.
  @ObservationIgnored private nonisolated(unsafe) let store: UserDefaults
  @ObservationIgnored private let observer: SettingObserver
  /// Non-nil only for dotted keys, which use the notification fallback
  /// instead of KVO. `NotificationCenter.removeObserver` is
  /// thread-safe, so `deinit` may touch this.
  @ObservationIgnored private nonisolated(unsafe) var notificationToken: (any NSObjectProtocol)?
  @ObservationIgnored private let read: (UserDefaults, String) -> Value?
  @ObservationIgnored private let write: (UserDefaults, String, Value) -> Void

  public init(
    _ key: String,
    default defaultValue: Value,
    store: UserDefaults = .standard
  ) {
    let read: (UserDefaults, String) -> Value? = { s, k in s.object(forKey: k) as? Value }
    let write: (UserDefaults, String, Value) -> Void = { s, k, v in s.set(v, forKey: k) }
    self.key = key
    self.defaultValue = defaultValue
    self.store = store
    self.read = read
    self.write = write
    self.value = read(store, key) ?? defaultValue
    self.observer = SettingObserver()
    installObserver()
  }

  /// Internal designated init used by the `RawRepresentable` extension.
  @_spi(Internal)
  public init(
    _ key: String,
    default defaultValue: Value,
    store: UserDefaults,
    read: @escaping (UserDefaults, String) -> Value?,
    write: @escaping (UserDefaults, String, Value) -> Void
  ) {
    self.key = key
    self.defaultValue = defaultValue
    self.store = store
    self.read = read
    self.write = write
    self.value = read(store, key) ?? defaultValue
    self.observer = SettingObserver()
    installObserver()
  }

  /// Wire the KVO bridge. Called from every designated init once all
  /// stored properties are initialized, so it's safe to capture `self`
  /// and register with the store.
  private func installObserver() {
    observer.onChange = { [weak self] in
      // KVO fires on whatever thread performed the write (or a
      // background queue for cross-process `userdefaultsd`
      // callbacks), so we always hop to the main actor.
      //
      // `DispatchQueue.main.async` (not `Task { @MainActor in … }`) is
      // load-bearing: the test suite drains the main queue with a
      // FIFO sentinel, which relies on dispatch ordering that Tasks
      // do not guarantee. Don't "modernize" this without also
      // replacing the test drain.
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          self?._applyExternalChange()
        }
      }
    }
    if key.contains(".") {
      // KVO interprets a dot as nested key-path traversal, so it never
      // fires for a defaults key like "learner.targetLanguage" (the
      // write persists; the observation is just silently dead). Fall
      // back to `didChangeNotification`, which fires for every
      // same-process defaults change; `_applyExternalChange()`'s
      // re-read + equality guard make the extra callbacks no-ops.
      // Trade-off: unlike KVO, this does NOT observe other processes,
      // so App Group host↔extension sync requires a dot-free key.
      // `object: nil` because distinct `UserDefaults(suiteName:)`
      // instances of the same suite post as distinct objects.
      let onChange = observer.onChange
      notificationToken = NotificationCenter.default.addObserver(
        forName: UserDefaults.didChangeNotification, object: nil, queue: nil
      ) { _ in onChange?() }
    } else {
      // Do NOT pass `.initial` — each init already seeded `value` by
      // reading the store directly.
      store.addObserver(observer, forKeyPath: key, options: [.new], context: nil)
    }
  }

  nonisolated deinit {
    if let notificationToken {
      NotificationCenter.default.removeObserver(notificationToken)
    } else {
      store.removeObserver(observer, forKeyPath: key)
    }
  }

  /// Restore the default value and remove the underlying key from the store.
  public func reset() {
    value = defaultValue
    store.removeObject(forKey: key)
  }

  /// Apply an externally-observed change to `value`. The KVO callback
  /// funnels through here; exposed via `@_spi(Internal)` so the
  /// equality guard can be unit-tested without depending on
  /// `userdefaultsd` timing.
  ///
  /// Disambiguates two distinct nil-from-`read` cases:
  /// - Key truly absent → reset to `defaultValue` (this is how
  ///   ``reset()`` propagates to other Setting instances).
  /// - Key present with an undecodable value (wrong type, or for
  ///   `RawRepresentable`, an unknown raw case) → ignore. Refusing to
  ///   touch `value` here is what prevents an external garbage write
  ///   from silently clobbering a valid user preference.
  @_spi(Internal)
  public func _applyExternalChange() {
    let new: Value
    if store.object(forKey: key) == nil {
      // Key removed (or never set) — fall back to the default so
      // observers see resets propagated from other instances.
      new = defaultValue
    } else if let decoded = read(store, key) {
      new = decoded
    } else {
      // Key has a value but it's not decodable as `Value` (wrong
      // type, or unknown enum case). Leave `value` untouched.
      return
    }
    // `Value: Equatable` via `SettingValue`. Skipping when unchanged
    // prevents redundant assignments (and the didSet work that would
    // follow) from double-fired KVO callbacks.
    guard new != value else { return }
    isApplyingExternalChange = true
    value = new
    isApplyingExternalChange = false
  }

  private func persist() {
    write(store, key, value)
  }
}

extension Setting where Value: RawRepresentable, Value.RawValue: SettingValue {
  /// `RawRepresentable` convenience: reads and writes via `rawValue` so that
  /// a previously-persisted enum setting round-trips correctly. Without this,
  /// the base `as? Value` cast fails (the store holds the raw value, not the
  /// enum) and the setting silently falls back to its default on every
  /// launch.
  public convenience init(
    _ key: String,
    default defaultValue: Value,
    store: UserDefaults = .standard
  ) {
    self.init(
      key,
      default: defaultValue,
      store: store,
      read: { s, k in
        guard let raw = s.object(forKey: k) as? Value.RawValue else { return nil }
        return Value(rawValue: raw)
      },
      write: { s, k, v in
        s.set(v.rawValue, forKey: k)
      }
    )
  }
}

/// KVO→closure bridge. Exists only to let `Setting` observe a single
/// UserDefaults key; the `@unchecked Sendable` is safe because
/// `onChange` is only written during `Setting.init` (before the
/// observer is registered) and read from the KVO callback.
private final class SettingObserver: NSObject, @unchecked Sendable {
  var onChange: (() -> Void)?

  override func observeValue(
    forKeyPath keyPath: String?,
    of object: Any?,
    change: [NSKeyValueChangeKey: Any]?,
    context: UnsafeMutableRawPointer?
  ) {
    onChange?()
  }
}
