import Foundation
import Testing

@testable import Splint

/// Dictionary-backed stand-in for `NSUbiquitousKeyValueStore` (the seam
/// exists so tests never touch iCloud). Call counters expose whether the
/// sync wrote or flushed when it shouldn't have.
private final class FakeUbiquitousStore: UbiquitousKeyValueStore {
  var values: [String: Any] = [:]
  var setCount = 0
  var synchronizeCount = 0

  func object(forKey aKey: String) -> Any? { values[aKey] }
  func set(_ anObject: Any?, forKey aKey: String) {
    setCount += 1
    values[aKey] = anObject
  }
  func removeObject(forKey aKey: String) { values[aKey] = nil }
  func synchronize() -> Bool {
    synchronizeCount += 1
    return true
  }
}

@MainActor
private final class DeferredActions {
  private(set) var actions: [@MainActor @Sendable () -> Void] = []

  func schedule(_ action: @escaping @MainActor @Sendable () -> Void) {
    actions.append(action)
  }

  func runLast() {
    actions.removeLast()()
  }

  func runFirst() {
    actions.removeFirst()()
  }
}

@MainActor
@Suite("CloudSync")
struct CloudSyncTests {
  private let defaults: UserDefaults
  private let suite: String
  /// Fresh per test: Foundation posts `UserDefaults.didChangeNotification`
  /// only to the default center, where parallel tests would cross-talk, so
  /// each test posts its own equivalents here.
  private let center = NotificationCenter()
  private let store = FakeUbiquitousStore()
  private let deferredActions = DeferredActions()

  init() {
    suite = "SplintTests.CloudSync.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
  }

  private func sync(keys: [String] = ["mirrored"]) -> CloudSync {
    CloudSync(
      keys: keys, defaults: defaults, store: store, center: center,
      scheduleInitialReconcile: deferredActions.schedule)
  }

  private func postDefaultsChange() {
    center.post(name: UserDefaults.didChangeNotification, object: defaults)
  }

  private func postExternalChange(keys: [String]?, reason: Int? = nil) {
    var userInfo: [AnyHashable: Any]?
    if let keys { userInfo = [NSUbiquitousKeyValueStoreChangedKeysKey: keys] }
    if let reason { userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] = reason }
    center.post(
      name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: store, userInfo: userInfo)
  }

  @Test func startDefersUploadingALocalOnlyValue() {
    defaults.set("local", forKey: "mirrored")
    let sync = sync()
    sync.start()

    #expect(store.values["mirrored"] == nil)

    deferredActions.runLast()

    #expect(store.values["mirrored"] as? String == "local")
  }

  @Test func cloudValueArrivingBeforeDeferredReconcileWins() {
    defaults.set("local", forKey: "mirrored")
    let sync = sync()
    sync.start()

    store.values["mirrored"] = "cloud"
    deferredActions.runLast()

    #expect(defaults.string(forKey: "mirrored") == "cloud")
    #expect(store.values["mirrored"] as? String == "cloud")
  }

  @Test func publicInitializerStartsAndStops() {
    let sync = CloudSync(keys: ["mirrored"], defaults: defaults, store: store, center: center)

    sync.start()
    sync.stop()
  }

  @Test func initialSyncNotificationRestartsTheDeferredReconcile() {
    defaults.set("local", forKey: "mirrored")
    let sync = sync()
    sync.start()

    postExternalChange(keys: [], reason: NSUbiquitousKeyValueStoreInitialSyncChange)
    deferredActions.runFirst()

    #expect(store.values["mirrored"] == nil)

    deferredActions.runLast()

    #expect(store.values["mirrored"] as? String == "local")
  }

  @Test func startPrefersTheCloudValueWhenBothExist() {
    defaults.set("local", forKey: "mirrored")
    store.values["mirrored"] = "cloud"
    let sync = sync()
    sync.start()

    #expect(defaults.string(forKey: "mirrored") == "cloud")
  }

  @Test func startWithNeitherValueWritesNothing() {
    let sync = sync()
    sync.start()

    #expect(defaults.object(forKey: "mirrored") == nil)
    #expect(store.values.isEmpty)
    #expect(store.setCount == 0)
  }

  @Test func startLeavesUnmirroredCloudKeysAlone() {
    store.values["unmirrored"] = "cloud"
    let sync = sync()
    sync.start()

    #expect(defaults.object(forKey: "unmirrored") == nil)
  }

  @Test func startingTwiceDoesNotReRunTheCloudWinsReconcile() {
    store.values["mirrored"] = "cloud"
    let sync = sync()
    sync.start()
    defaults.set("newer local", forKey: "mirrored")
    sync.start()

    #expect(defaults.string(forKey: "mirrored") == "newer local")
  }

  @Test func localWritesPushToTheCloud() {
    let sync = sync()
    sync.start()
    deferredActions.runLast()
    defaults.set(42, forKey: "mirrored")
    postDefaultsChange()

    #expect(store.values["mirrored"] as? Int == 42)
  }

  @Test func localRemovalsRemoveFromTheCloud() {
    defaults.set("kept", forKey: "mirrored")
    let sync = sync()
    sync.start()
    deferredActions.runLast()
    defaults.removeObject(forKey: "mirrored")
    postDefaultsChange()

    #expect(store.values["mirrored"] == nil)
  }

  @Test func externalChangesApplyToDefaults() {
    let sync = sync()
    sync.start()
    store.values["mirrored"] = "from another device"
    postExternalChange(keys: ["mirrored"])

    #expect(defaults.string(forKey: "mirrored") == "from another device")
  }

  @Test func externalRemovalsClearDefaults() {
    defaults.set("stale", forKey: "mirrored")
    store.values["mirrored"] = "stale"
    let sync = sync()
    sync.start()
    store.values["mirrored"] = nil
    postExternalChange(keys: ["mirrored"])

    #expect(defaults.object(forKey: "mirrored") == nil)
  }

  @Test func externalChangesWithoutAKeyListReconcileEveryMirroredKey() {
    let sync = sync(keys: ["a", "b"])
    sync.start()
    store.values["a"] = 1
    store.values["b"] = 2
    postExternalChange(keys: nil)

    #expect(defaults.integer(forKey: "a") == 1)
    #expect(defaults.integer(forKey: "b") == 2)
  }

  @Test func externalChangesToUnmirroredKeysAreIgnored() {
    let sync = sync()
    sync.start()
    store.values["unmirrored"] = "noise"
    postExternalChange(keys: ["unmirrored"])

    #expect(defaults.object(forKey: "unmirrored") == nil)
  }

  // The pull writes defaults, which in production immediately re-posts
  // didChangeNotification; equality is what stops the bounce from writing
  // back to the cloud.
  @Test func aPulledChangeDoesNotEchoBackToTheCloud() {
    let sync = sync()
    sync.start()
    deferredActions.runLast()
    store.values["mirrored"] = "external"
    postExternalChange(keys: ["mirrored"])
    let writesBefore = store.setCount
    postDefaultsChange()

    #expect(store.setCount == writesBefore)
  }

  @Test func quietDefaultsChangesDoNotFlushTheCloudStore() {
    let sync = sync()
    sync.start()
    deferredActions.runLast()
    let flushesBefore = store.synchronizeCount
    defaults.set("unrelated", forKey: "unmirrored")
    postDefaultsChange()

    #expect(store.synchronizeCount == flushesBefore)
  }

  @Test func stopSilencesBothDirections() {
    let sync = sync()
    sync.start()
    sync.stop()
    deferredActions.runLast()

    defaults.set("local", forKey: "mirrored")
    postDefaultsChange()
    #expect(store.values["mirrored"] == nil)

    store.values["mirrored"] = "cloud"
    postExternalChange(keys: ["mirrored"])
    #expect(defaults.string(forKey: "mirrored") == "local")
  }

  @Test func deallocationSilencesBothDirections() {
    var sync: CloudSync? = sync()
    sync?.start()
    sync = nil
    _ = sync
    deferredActions.runLast()

    store.values["mirrored"] = "cloud"
    postExternalChange(keys: ["mirrored"])
    #expect(defaults.object(forKey: "mirrored") == nil)
  }
}
