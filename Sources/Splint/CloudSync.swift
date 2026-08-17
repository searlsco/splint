import Foundation

/// The slice of `NSUbiquitousKeyValueStore` that `CloudSync` touches,
/// as a seam so tests drive a fake instead of iCloud.
public protocol UbiquitousKeyValueStore: AnyObject {
  func object(forKey aKey: String) -> Any?
  func set(_ anObject: Any?, forKey aKey: String)
  func removeObject(forKey aKey: String)
  @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: UbiquitousKeyValueStore {}

/// Mirrors a fixed set of `UserDefaults` keys into iCloud key-value
/// storage (`NSUbiquitousKeyValueStore`), so every ``Setting`` bound to
/// a mirrored key syncs across the user's devices — and, when two apps
/// declare the same ubiquity key-value store identifier in their
/// entitlements, across apps.
///
/// Hold one instance for the app's lifetime and call ``start()`` at
/// launch. `Setting` already observes `UserDefaults`, so pulled changes
/// propagate to live `Setting` instances (and their views) with no
/// further wiring.
///
/// The invariant is upload-on-mutation, receive-only otherwise: nothing
/// writes to iCloud unless the app explicitly assigns a mirrored
/// ``Setting``'s `value` or calls its `reset()`. Startup pulls whatever
/// iCloud has already delivered and then waits; values (and deletions)
/// arriving later — iCloud's initial download can take arbitrarily long —
/// apply whenever their notification lands. A local-only value simply
/// stays local until the user next changes it, so a fresh install can
/// never clobber a real cloud preference with a locally-seeded default.
/// Conflicts remain last-writer-wins (iCloud's own semantics).
@MainActor
public final class CloudSync {
  private let keys: [String]
  private let store: any UbiquitousKeyValueStore
  private let defaults: UserDefaults
  private let center: NotificationCenter
  // Reachable from `deinit`, which runs nonisolated on `@MainActor`
  // classes in Swift 6. Safe: `NotificationCenter.removeObserver` is
  // thread-safe, and `observers` is only mutated on the main actor by
  // `start()`/`stop()`, which cannot race `deinit` (their caller holds
  // a strong reference).
  private nonisolated(unsafe) var observers: [any NSObjectProtocol] = []

  /// `defaults` must be the same `UserDefaults` **instance** every
  /// mirrored `Setting` uses as its store — automatic with the default
  /// `.standard`, which is a singleton. For a suite
  /// (`UserDefaults(suiteName:)`), create one instance and share it:
  /// mutation signals are matched by instance identity, so a second
  /// instance of the same suite is silently unrecognized.
  public convenience init(
    keys: some Sequence<String>,
    defaults: UserDefaults = .standard,
    store: any UbiquitousKeyValueStore = NSUbiquitousKeyValueStore.default
  ) {
    self.init(keys: keys, defaults: defaults, store: store, center: .default)
  }

  /// Internal seam: production always observes the default center
  /// (where Foundation and `Setting` post); tests inject a fresh
  /// center and post equivalents.
  init(
    keys: some Sequence<String>,
    defaults: UserDefaults,
    store: any UbiquitousKeyValueStore,
    center: NotificationCenter
  ) {
    self.keys = Array(keys)
    self.defaults = defaults
    self.store = store
    self.center = center
  }

  /// Installs both mirror directions and pulls any already-delivered
  /// iCloud values. Call before mutating mirrored Settings: a mutation
  /// made while stopped stays local until the next mutation after
  /// `start()`. Calling again while started is a no-op.
  public func start() {
    guard observers.isEmpty else { return }
    // Both observers deliver on the main queue, so `assumeIsolated` is
    // sound; payloads are extracted before entering isolation because
    // `Notification` itself is not `Sendable`.
    observers.append(
      center.addObserver(
        forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
        object: store, queue: .main
      ) { [weak self] note in
        let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
        MainActor.assumeIsolated { self?.receiveExternalChange(changed, reason: reason) }
      })
    observers.append(
      center.addObserver(
        forName: SettingMutation.didMutate,
        object: defaults, queue: .main
      ) { [weak self] note in
        let key = note.userInfo?[SettingMutation.keyKey] as? String
        MainActor.assumeIsolated { self?.settingMutated(key) }
      })
    store.synchronize()
    pullPresentValues(nil)
  }

  /// Uninstalls both mirror directions; local and iCloud values stay
  /// wherever they are.
  public func stop() {
    for observer in observers { center.removeObserver(observer) }
    observers.removeAll()
  }

  nonisolated deinit {
    for observer in observers { center.removeObserver(observer) }
  }

  /// Uploads the current local state of one explicitly-mutated Setting
  /// key. This is the only path that writes to iCloud: pulled changes
  /// re-enter `Setting` via `_applyExternalChange`, which never emits
  /// the mutation signal, so nothing echoes back.
  private func settingMutated(_ key: String?) {
    guard let key, keys.contains(key) else { return }
    if let local = defaults.object(forKey: key) {
      store.set(local, forKey: key)
    } else {
      store.removeObject(forKey: key)
    }
    store.synchronize()
  }

  private func receiveExternalChange(_ changed: [String]?, reason: Int?) {
    if reason == NSUbiquitousKeyValueStoreQuotaViolationChange
      || reason == NSUbiquitousKeyValueStoreInitialSyncChange
    {
      // Neither reason is evidence of a cloud deletion, so never remove
      // local state here. Quota violation means our own writes were
      // rejected. Initial sync fires while iCloud's first download is
      // still in progress — Apple documents that a write attempted
      // during that window generates this notification — so a listed
      // key with a nil remote value most likely means "not downloaded
      // yet," and deleting would destroy the value the user just chose.
      pullPresentValues(changed)
    } else {
      // Server and account changes are delivered truth: values replace,
      // and a listed key with no remote value is a real deletion (on
      // account change, Apple replaces the store with the new account's
      // data, so a missing key means that account doesn't have it).
      pull(changed)
    }
  }

  /// Applies external iCloud changes to defaults: a listed key's remote
  /// value replaces the local one, and a listed key with no remote value
  /// is a delivered deletion, clearing the local one. A notification
  /// with no changed-key list applies present values only — there,
  /// absence is indistinguishable from not-yet-downloaded.
  private func pull(_ changed: [String]?) {
    guard let changed else { return pullPresentValues(nil) }
    for key in changed where keys.contains(key) {
      let remote = store.object(forKey: key)
      guard !Self.equal(remote, defaults.object(forKey: key)) else { continue }
      if let remote {
        defaults.set(remote, forKey: key)
      } else {
        defaults.removeObject(forKey: key)
      }
    }
  }

  /// Receive-only reconcile: remote values replace local ones, but a
  /// missing remote value proves nothing (iCloud may simply not have
  /// delivered it yet), so local values are left alone.
  private func pullPresentValues(_ changed: [String]?) {
    for key in changed ?? keys where keys.contains(key) {
      guard let remote = store.object(forKey: key),
        !Self.equal(remote, defaults.object(forKey: key))
      else { continue }
      defaults.set(remote, forKey: key)
    }
  }

  /// Property-list equality across the two stores' `Any` payloads: every
  /// plist type bridges to an `NSObject` with value `isEqual(_:)`.
  private static func equal(_ a: Any?, _ b: Any?) -> Bool {
    switch (a, b) {
    case (nil, nil): true
    case (let a?, let b?): (a as? NSObject)?.isEqual(b) ?? false
    default: false
    }
  }
}
