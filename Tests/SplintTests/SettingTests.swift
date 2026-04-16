import Foundation
import Testing

@_spi(Internal) @testable import Splint

/// Drain one main-queue turn. The `Setting` KVO callback hops to main
/// via `DispatchQueue.main.async`; this sentinel lands after it (FIFO),
/// guaranteeing the callback has run when the continuation resumes. No
/// hard sleep — purely event-driven.
@MainActor
private func drainMain() async {
  await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
    DispatchQueue.main.async { c.resume() }
  }
}

/// `UserDefaults` is documented thread-safe but isn't marked
/// `Sendable`. Wrap to make off-main captures explicit for Swift 6
/// strict concurrency.
private struct SendableStore: @unchecked Sendable {
  let store: UserDefaults
  init(_ store: UserDefaults) { self.store = store }
}

/// `UserDefaults` subclass that counts `set(_:forKey:)` invocations.
/// Used by `selfWriteDoesNotLoop` to catch regressions of the
/// re-entry guard — a regression would show up as `setCount > 1` for
/// a single local write, instead of hanging the runner.
private final class CountingUserDefaults: UserDefaults, @unchecked Sendable {
  private let lock = NSLock()
  private var _setCount = 0
  var setCount: Int { lock.withLock { _setCount } }

  override func set(_ value: Any?, forKey defaultName: String) {
    lock.withLock { _setCount += 1 }
    super.set(value, forKey: defaultName)
  }
}

@MainActor
@Suite("Setting")
struct SettingTests {
  private func freshStore(_ fn: String = #function) -> UserDefaults {
    let suite = "SplintTests.Setting.\(fn).\(UUID().uuidString)"
    let store = UserDefaults(suiteName: suite)!
    store.removePersistentDomain(forName: suite)
    return store
  }

  private func freshCountingStore(_ fn: String = #function) -> CountingUserDefaults {
    let suite = "SplintTests.Setting.\(fn).\(UUID().uuidString)"
    let store = CountingUserDefaults(suiteName: suite)!
    store.removePersistentDomain(forName: suite)
    return store
  }

  @Test func readsDefaultWhenKeyAbsent() {
    let store = freshStore()
    let s = Setting<Int>("count", default: 5, store: store)
    #expect(s.value == 5)
  }

  @Test func persistsOnWrite() {
    let store = freshStore()
    let s = Setting<String>("name", default: "A", store: store)
    s.value = "B"
    #expect(store.string(forKey: "name") == "B")
  }

  @Test func readsPersistedValueOnInit() {
    let store = freshStore()
    store.set(42, forKey: "count")
    let s = Setting<Int>("count", default: 0, store: store)
    #expect(s.value == 42)
  }

  @Test func resetRestoresDefaultAndRemovesKey() {
    let store = freshStore()
    let s = Setting<Bool>("flag", default: false, store: store)
    s.value = true
    #expect(store.object(forKey: "flag") != nil)
    s.reset()
    #expect(s.value == false)
    #expect(store.object(forKey: "flag") == nil)
  }

  enum Theme: String, SettingValue {
    case light, dark
  }

  @Test func rawRepresentableEnumRoundTrips() {
    let store = freshStore()
    let s = Setting<Theme>("theme", default: .light, store: store)
    #expect(s.value == .light)
    s.value = .dark
    // Re-read via a fresh Setting on the same store.
    let s2 = Setting<Theme>("theme", default: .light, store: store)
    #expect(s2.value == .dark)
  }

  @Test func rawRepresentableEnumResetRemovesKey() {
    let store = freshStore()
    let s = Setting<Theme>("theme", default: .light, store: store)
    s.value = .dark
    s.reset()
    #expect(s.value == .light)
    #expect(store.object(forKey: "theme") == nil)
  }

  // MARK: - Issue #5: multi-instance synchronization

  /// Issue footgun #1. Outer integration test: two `Setting` instances
  /// bound to the same key/store must stay in sync via UserDefaults
  /// KVO. Writes through either instance — or directly to the
  /// underlying store — propagate to all observers.
  @Test func multipleInstancesStaySynchronized() async {
    let store = freshStore()
    let a = Setting<Bool>("flag", default: false, store: store)
    let b = Setting<Bool>("flag", default: false, store: store)

    a.value = true
    await drainMain()
    #expect(b.value == true, "B should observe A's write")

    b.value = false
    await drainMain()
    #expect(a.value == false, "A should observe B's write")

    store.set(true, forKey: "flag")
    await drainMain()
    #expect(a.value == true, "A should observe direct store write")
    #expect(b.value == true, "B should observe direct store write")
  }

  /// Issue footgun #2. A single self-write must produce exactly one
  /// underlying `store.set` call. Without the `isApplyingExternalChange`
  /// re-entry guard, the KVO callback would set `value` again, fire
  /// `didSet`, persist again — an infinite feedback loop. Relies on
  /// `[weak self]` self-termination (the local Setting deallocates at
  /// end of scope, breaking any in-flight chain) rather than a
  /// `.timeLimit` trait.
  @Test func selfWriteDoesNotLoop() async {
    let store = freshCountingStore()
    let s = Setting<Bool>("flag", default: false, store: store)
    s.value = true
    await drainMain()
    #expect(store.setCount == 1, "self-write must hit the store exactly once")
    #expect(s.value == true, "self-write must take effect locally")
  }

  /// Issue footgun #3. The equality guard inside `_applyExternalChange()`
  /// must skip redundant assignments when the underlying store value
  /// already matches `value`. Tested directly through the SPI rather
  /// than depending on `userdefaultsd` daemon timing.
  @Test func equalityGuardSkipsRedundantApplications() async {
    let store = freshCountingStore()
    let s = Setting<Bool>("flag", default: false, store: store)
    s.value = true
    await drainMain()
    let baselineWrites = store.setCount

    // Drive the external-change path repeatedly with no change to the
    // underlying value; the guard should make every call a no-op.
    s._applyExternalChange()
    s._applyExternalChange()
    s._applyExternalChange()

    #expect(s.value == true, "value must stay put")
    #expect(store.setCount == baselineWrites, "no additional persist calls")
  }

  /// Issue footgun #4. A direct `UserDefaults.set` write — bypassing
  /// every `Setting` instance — must still propagate to the Setting
  /// via KVO.
  @Test func externalStoreWriteReflectsInSetting() async {
    let store = freshStore()
    let s = Setting<Bool>("flag", default: true, store: store)
    store.set(false, forKey: "flag")
    await drainMain()
    #expect(s.value == false)
  }

  // (Issue footgun #5, App Group cross-process sync, deliberately not
  // automated. SPM tests can't acquire an App Group entitlement
  // without restructuring to xcodebuild + a host app target. Cross-
  // process sync is documented in README as the OS guarantee that
  // standard KVO on a shared suite leverages.)

  /// Issue footgun #6. Dropping the last strong reference to a
  /// `Setting` must trigger `deinit`, which removes the KVO observer
  /// from the store. After release, writes to the store must not
  /// crash even though our observer is gone.
  @Test func deinitRemovesObserver() async {
    let store = freshStore()
    weak var weakSetting: Setting<Bool>?
    do {
      let s = Setting<Bool>("flag", default: false, store: store)
      weakSetting = s
      s.value = true
    }
    // Allow any in-flight KVO-dispatched blocks to clear.
    await drainMain()
    #expect(weakSetting == nil, "Setting must deallocate when last strong ref drops")

    // If `removeObserver` regressed, this write would call into freed
    // memory and crash. The assertion is implicit (no crash).
    store.set(false, forKey: "flag")
    await drainMain()
  }

  /// Issue footgun #7. Many `Setting` instances created and dropped in
  /// a tight loop must all deallocate. Catches regressions where a
  /// retain cycle (e.g., the observer closure capturing `self`
  /// strongly) prevents `deinit`.
  @Test func manySettingsDeinitCleanly() async {
    let store = freshStore()
    var weakProbes: [() -> Bool] = []
    do {
      var settings: [Setting<Int>] = []
      for i in 0..<100 {
        let s = Setting<Int>("k_\(i)", default: 0, store: store)
        // `[weak s]` makes the probe non-retaining; the closure
        // returns true once the underlying instance is gone.
        weakProbes.append { [weak s] in s == nil }
        settings.append(s)
      }
      _ = settings
    }
    await drainMain()
    let leaked = weakProbes.filter { !$0() }.count
    #expect(leaked == 0, "expected all 100 Settings to deallocate, \(leaked) leaked")
  }

  /// Issue footgun #8. The `RawRepresentable` init path must wire up
  /// KVO identically to the standard init. Two enum-typed Settings on
  /// the same key must stay in sync, and a raw-string write to the
  /// store must propagate as well.
  @Test func rawRepresentableEnumsSyncCorrectly() async {
    let store = freshStore()
    let a = Setting<Theme>("theme", default: .light, store: store)
    let b = Setting<Theme>("theme", default: .light, store: store)

    a.value = .dark
    await drainMain()
    #expect(b.value == .dark, "B should observe A's enum write")

    store.set("light", forKey: "theme")
    await drainMain()
    #expect(a.value == .light, "A should observe direct raw-string write")
    #expect(b.value == .light, "B should observe direct raw-string write")
  }

  /// Issue footgun #9. An external write of a wrong-typed value must
  /// be silently ignored — `value` must not be touched. Critically,
  /// `value` must NOT silently revert to `defaultValue` either; this
  /// regression test seeds `value` to something different from
  /// `defaultValue` first so the wrong-typed write would actually
  /// flip it if the implementation conflated "undecodable" with "key
  /// absent".
  @Test func typeMismatchedExternalWriteIsIgnored() async {
    let store = freshStore()
    let s = Setting<Bool>("flag", default: false, store: store)
    // Move `value` to the non-default position via a legitimate write.
    store.set(true, forKey: "flag")
    await drainMain()
    #expect(s.value == true, "precondition: legitimate write took effect")

    // Now smuggle in a wrong-typed value. The only correct response
    // is "leave `value` alone" — falling back to `defaultValue`
    // (false) here would silently destroy the user's preference.
    store.set("not a bool", forKey: "flag")
    await drainMain()

    #expect(s.value == true, "undecodable external write must not clobber value")
  }

  /// Issue footgun #9 (reset-propagation companion). After a key
  /// removal — distinct from a wrong-typed write — `value` must fall
  /// back to `defaultValue`. This is the same nil-from-`read` shape
  /// that the wrong-type case produces, so the implementation must
  /// disambiguate by checking key presence in the store.
  @Test func keyRemovalExternallyResetsToDefault() async {
    let store = freshStore()
    let s = Setting<Bool>("flag", default: false, store: store)
    store.set(true, forKey: "flag")
    await drainMain()
    #expect(s.value == true, "precondition: legitimate write took effect")

    store.removeObject(forKey: "flag")
    await drainMain()

    #expect(s.value == false, "external key removal must reset to default")
  }

  /// Issue footgun #10. A write made from a background `Task.detached`
  /// must propagate to the main-actor Setting without crashes or data
  /// races. Verifies the `DispatchQueue.main.async` + `assumeIsolated`
  /// bridge handles off-main KVO callbacks.
  @Test func concurrentBackgroundWriteUpdatesOnMain() async {
    let store = freshStore()
    let s = Setting<Bool>("flag", default: false, store: store)

    // `UserDefaults` isn't `Sendable`, but its setters are documented
    // as thread-safe. Wrap to make the cross-actor capture explicit
    // for Swift 6 strict concurrency.
    let sendable = SendableStore(store)
    await Task.detached {
      sendable.store.set(true, forKey: "flag")
    }.value

    await drainMain()
    #expect(s.value == true)
  }

  /// Issue footgun #11. With KVO wired in, the default-when-key-absent
  /// path must still produce the default. (Re-asserted alongside the
  /// pre-existing `readsDefaultWhenKeyAbsent` test.)
  @Test func defaultWhenKeyAbsentAfterKVOInit() {
    let store = freshStore()
    let s = Setting<Int>("missing", default: 7, store: store)
    #expect(s.value == 7)
  }

  /// Issue footgun #12. `reset()` removes the key from the store,
  /// which must propagate to other Setting instances on the same
  /// key — they should fall back to their default.
  @Test func resetClearsKeyAndNotifiesOtherInstances() async {
    let store = freshStore()
    let a = Setting<Theme>("theme", default: .light, store: store)
    let b = Setting<Theme>("theme", default: .light, store: store)

    a.value = .dark
    await drainMain()
    #expect(b.value == .dark)

    b.reset()
    await drainMain()
    #expect(b.value == .light, "B reset locally")
    #expect(a.value == .light, "A should observe B's reset (key removed)")
  }
}
