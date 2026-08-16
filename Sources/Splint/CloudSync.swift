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
/// Conflict policy is last-writer-wins (iCloud's own semantics). On
/// ``start()``, existing iCloud values pull immediately. Local-only values
/// wait briefly for iCloud's initial download before uploading (first-run
/// migration of a previously local-only preference). Afterward local writes push and
/// external iCloud changes pull, each reconciled by value equality so
/// echo loops terminate on the first quiet pass.
@MainActor
public final class CloudSync {
  typealias InitialReconcileScheduler = (
    @escaping @MainActor @Sendable () -> Void
  ) -> Void

  private let keys: [String]
  private let store: any UbiquitousKeyValueStore
  // Reachable from `deinit`, which runs nonisolated on `@MainActor`
  // classes in Swift 6. Safe: `NotificationCenter.removeObserver` is
  // thread-safe and `observers` is never mutated after `start()`.
  private nonisolated(unsafe) let defaults: UserDefaults
  private let center: NotificationCenter
  private let scheduleInitialReconcile: InitialReconcileScheduler
  private nonisolated(unsafe) var observers: [any NSObjectProtocol] = []
  private var initialReconcileGeneration = 0
  private var initialReconcileCompleted = false

  /// `center` must be the center that receives Foundation's
  /// `UserDefaults.didChangeNotification` posts (the default center) in
  /// production; tests inject a fresh center and post equivalents.
  public convenience init(
    keys: some Sequence<String>,
    defaults: UserDefaults = .standard,
    store: any UbiquitousKeyValueStore = NSUbiquitousKeyValueStore.default,
    center: NotificationCenter = .default
  ) {
    self.init(
      keys: keys, defaults: defaults, store: store, center: center,
      scheduleInitialReconcile: Self.scheduleAfterInitialSyncDelay)
  }

  // coverage:ignore-start — Production clock timing is replaced by the injected scheduler in tests.
  private static func scheduleAfterInitialSyncDelay(
    _ action: @escaping @MainActor @Sendable () -> Void
  ) {
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(5))
      action()
    }
  }
  // coverage:ignore-end

  init(
    keys: some Sequence<String>, defaults: UserDefaults, store: any UbiquitousKeyValueStore,
    center: NotificationCenter,
    scheduleInitialReconcile: @escaping InitialReconcileScheduler
  ) {
    self.keys = Array(keys)
    self.defaults = defaults
    self.store = store
    self.center = center
    self.scheduleInitialReconcile = scheduleInitialReconcile
  }

  /// Installs both mirror directions and runs the startup reconcile.
  /// Calling again while started is a no-op.
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
        forName: UserDefaults.didChangeNotification,
        object: defaults, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.push() }
      })
    store.synchronize()
    pullPresentValues(nil)
    deferInitialReconcile()
  }

  /// Uninstalls both mirror directions; local and iCloud values stay
  /// wherever they are.
  public func stop() {
    for observer in observers { center.removeObserver(observer) }
    observers.removeAll()
    initialReconcileGeneration += 1
    initialReconcileCompleted = false
  }

  nonisolated deinit {
    for observer in observers { center.removeObserver(observer) }
  }

  /// Applies external iCloud changes to defaults. A notification with no
  /// changed-key list reconciles every mirrored key.
  private func pull(_ changed: [String]?) {
    for key in changed ?? keys where keys.contains(key) {
      let remote = store.object(forKey: key)
      guard !Self.equal(remote, defaults.object(forKey: key)) else { continue }
      if let remote {
        defaults.set(remote, forKey: key)
      } else {
        defaults.removeObject(forKey: key)
      }
    }
  }

  private func receiveExternalChange(_ changed: [String]?, reason: Int?) {
    if reason == NSUbiquitousKeyValueStoreInitialSyncChange {
      initialReconcileCompleted = false
      pullPresentValues(changed)
      deferInitialReconcile()
    } else {
      pull(changed)
    }
  }

  private func pullPresentValues(_ changed: [String]?) {
    for key in changed ?? keys where keys.contains(key) {
      guard let remote = store.object(forKey: key),
        !Self.equal(remote, defaults.object(forKey: key))
      else { continue }
      defaults.set(remote, forKey: key)
    }
  }

  private func deferInitialReconcile() {
    initialReconcileGeneration += 1
    let generation = initialReconcileGeneration
    scheduleInitialReconcile { [weak self] in
      guard let self, generation == initialReconcileGeneration, !observers.isEmpty else { return }
      finishInitialReconcile()
    }
  }

  private func finishInitialReconcile() {
    var wrote = false
    for key in keys {
      if let remote = store.object(forKey: key) {
        guard !Self.equal(remote, defaults.object(forKey: key)) else { continue }
        defaults.set(remote, forKey: key)
      } else if let local = defaults.object(forKey: key) {
        wrote = true
        store.set(local, forKey: key)
      }
    }
    initialReconcileCompleted = true
    if wrote { store.synchronize() }
  }

  /// Pushes local values that differ from iCloud's. Fires on every
  /// same-process defaults change (Foundation's notification isn't
  /// key-scoped), so equality is what keeps it cheap and loop-free: a
  /// pull-provoked notification finds nothing to push.
  private func push() {
    guard initialReconcileCompleted else { return }
    var wrote = false
    for key in keys {
      let local = defaults.object(forKey: key)
      guard !Self.equal(local, store.object(forKey: key)) else { continue }
      wrote = true
      if let local {
        store.set(local, forKey: key)
      } else {
        store.removeObject(forKey: key)
      }
    }
    if wrote { store.synchronize() }
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
