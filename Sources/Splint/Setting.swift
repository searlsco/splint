import Foundation
import Observation

/// A single typed user preference backed by `UserDefaults`.
///
/// Prefer many small `Setting` instances over a single "settings object":
/// each `Setting` is its own observation point, so views reading one
/// setting do not re-evaluate when an unrelated setting changes.
@Observable
@MainActor
public final class Setting<Value: SettingValue> {
  /// The current value. Writes persist to the underlying store.
  public var value: Value {
    didSet { persist() }
  }

  @ObservationIgnored private let key: String
  @ObservationIgnored private let defaultValue: Value
  @ObservationIgnored private let store: UserDefaults
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
  }

  /// Restore the default value and remove the underlying key from the store.
  public func reset() {
    value = defaultValue
    store.removeObject(forKey: key)
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
