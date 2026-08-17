import Foundation
import Testing

@testable import Splint

/// Dictionary-backed stand-in for `NSUbiquitousKeyValueStore` (the seam
/// exists so tests never touch iCloud). Call counters expose whether the
/// sync wrote or flushed when it shouldn't have.
private final class FakeUbiquitousStore: UbiquitousKeyValueStore {
  var values: [String: Any] = [:]
  var setCount = 0
  var removeCount = 0
  var synchronizeCount = 0

  func object(forKey aKey: String) -> Any? { values[aKey] }
  func set(_ anObject: Any?, forKey aKey: String) {
    setCount += 1
    values[aKey] = anObject
  }
  func removeObject(forKey aKey: String) {
    removeCount += 1
    values[aKey] = nil
  }
  func synchronize() -> Bool {
    synchronizeCount += 1
    return true
  }
}

/// `Setting`'s KVO callback hops to the main actor via
/// `DispatchQueue.main.async`; this sentinel lands after it (FIFO), so
/// awaiting it guarantees pending external-change applications ran.
@MainActor
private func drainMain() async {
  await withCheckedContinuation { c in
    DispatchQueue.main.async { c.resume() }
  }
}

@MainActor
@Suite("CloudSync")
struct CloudSyncTests {
  private let defaults: UserDefaults
  private let suite: String
  /// Fresh per test: Foundation posts `UserDefaults.didChangeNotification`
  /// only to the default center, where parallel tests would cross-talk, so
  /// each test posts its own equivalents here. Tests that exercise real
  /// `Setting` instances use `.default` instead (Setting posts its
  /// mutation signal there); those stay parallel-safe because CloudSync
  /// filters both observations by this test's unique store and defaults.
  private let center = NotificationCenter()
  private let store = FakeUbiquitousStore()

  init() {
    suite = "SplintTests.CloudSync.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
  }

  private func sync(
    keys: [String] = ["mirrored"], center: NotificationCenter? = nil
  ) -> CloudSync {
    CloudSync(keys: keys, defaults: defaults, store: store, center: center ?? self.center)
  }

  private func postSettingMutation(key: String) {
    center.post(
      name: SettingMutation.didMutate, object: defaults,
      userInfo: [SettingMutation.keyKey: key])
  }

  private func postExternalChange(keys: [String]?, reason: Int? = nil) {
    var userInfo: [AnyHashable: Any]?
    if let keys { userInfo = [NSUbiquitousKeyValueStoreChangedKeysKey: keys] }
    if let reason { userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] = reason }
    center.post(
      name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: store, userInfo: userInfo)
  }

  // MARK: - Receive-only startup

  @Test func startNeverUploadsALocalOnlyValue() {
    defaults.set("local", forKey: "mirrored")
    let sync = sync()
    sync.start()

    #expect(store.values["mirrored"] == nil)
    #expect(store.setCount == 0)
    #expect(defaults.string(forKey: "mirrored") == "local")
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

  // MARK: - Pulling external changes

  @Test func aCloudValueArrivingArbitrarilyLateReplacesTheLocalValue() {
    defaults.set("local", forKey: "mirrored")
    let sync = sync()
    sync.start()

    store.values["mirrored"] = "cloud, eventually"
    postExternalChange(keys: ["mirrored"])

    #expect(defaults.string(forKey: "mirrored") == "cloud, eventually")
    #expect(store.setCount == 0)
  }

  @Test func aCloudDeletionClearsTheLocalValue() {
    defaults.set("stale", forKey: "mirrored")
    store.values["mirrored"] = "stale"
    let sync = sync()
    sync.start()
    store.values["mirrored"] = nil
    postExternalChange(keys: ["mirrored"])

    #expect(defaults.object(forKey: "mirrored") == nil)
  }

  @Test func externalChangesWithoutAKeyListPullEveryPresentMirroredKey() {
    let sync = sync(keys: ["a", "b"])
    sync.start()
    store.values["a"] = 1
    store.values["b"] = 2
    postExternalChange(keys: nil)

    #expect(defaults.integer(forKey: "a") == 1)
    #expect(defaults.integer(forKey: "b") == 2)
  }

  @Test func externalChangesWithoutAKeyListDoNotTreatAbsenceAsDeletion() {
    defaults.set("local", forKey: "mirrored")
    let sync = sync()
    sync.start()
    postExternalChange(keys: nil)

    #expect(defaults.string(forKey: "mirrored") == "local")
  }

  @Test func externalChangesToUnmirroredKeysAreIgnored() {
    let sync = sync()
    sync.start()
    store.values["unmirrored"] = "noise"
    postExternalChange(keys: ["unmirrored"])

    #expect(defaults.object(forKey: "unmirrored") == nil)
  }

  @Test func initialSyncDeliveriesApplyValuesAndDeletions() {
    defaults.set("stale", forKey: "mirrored")
    store.values["other"] = "downloaded"
    let sync = sync(keys: ["mirrored", "other"])
    sync.start()
    #expect(defaults.string(forKey: "mirrored") == "stale")

    postExternalChange(
      keys: ["mirrored", "other"], reason: NSUbiquitousKeyValueStoreInitialSyncChange)

    #expect(defaults.string(forKey: "other") == "downloaded")
    #expect(defaults.object(forKey: "mirrored") == nil)
    #expect(store.setCount == 0)
  }

  @Test func accountChangeToAnAccountWithoutTheKeyClearsTheLocalValue() {
    defaults.set("previous account's", forKey: "mirrored")
    store.values["mirrored"] = "previous account's"
    let sync = sync()
    sync.start()
    store.values["mirrored"] = nil
    postExternalChange(keys: ["mirrored"], reason: NSUbiquitousKeyValueStoreAccountChange)

    #expect(defaults.object(forKey: "mirrored") == nil)
    #expect(store.setCount == 0)
  }

  @Test func quotaViolationsNeverDeleteLocalValues() {
    defaults.set("rejected upload", forKey: "mirrored")
    let sync = sync()
    sync.start()
    postExternalChange(
      keys: ["mirrored"], reason: NSUbiquitousKeyValueStoreQuotaViolationChange)

    #expect(defaults.string(forKey: "mirrored") == "rejected upload")
  }

  // MARK: - Pushing explicit Setting mutations

  @Test func assigningAMirroredSettingUploadsExactlyThatKey() {
    let sync = sync(center: .default)
    sync.start()
    let setting = Setting("mirrored", default: "", store: defaults)

    setting.value = "chosen"

    #expect(store.values["mirrored"] as? String == "chosen")
    #expect(store.setCount == 1)
  }

  @Test func assigningAnUnmirroredSettingNeverUploads() {
    let sync = sync(center: .default)
    sync.start()
    let setting = Setting("unmirrored", default: "", store: defaults)

    setting.value = "kept local"

    #expect(store.values.isEmpty)
    #expect(store.setCount == 0)
  }

  @Test func aDirectUserDefaultsWriteNeverUploads() {
    let sync = sync(center: .default)
    sync.start()

    defaults.set("written behind Setting's back", forKey: "mirrored")

    #expect(store.values.isEmpty)
    #expect(store.setCount == 0)
    #expect(store.synchronizeCount == 1)  // start()'s pull request only
  }

  @Test func resetRemovesTheUbiquitousKeyWithoutUploadingTheDefault() {
    defaults.set("chosen", forKey: "mirrored")
    store.values["mirrored"] = "chosen"
    let sync = sync(center: .default)
    sync.start()
    let setting = Setting("mirrored", default: "factory", store: defaults)

    setting.reset()

    #expect(store.values["mirrored"] == nil)
    #expect(store.removeCount == 1)
    #expect(store.setCount == 0)
    #expect(defaults.object(forKey: "mirrored") == nil)
    #expect(setting.value == "factory")
  }

  @Test func aPulledCloudChangeNeverEchoesBackToTheCloud() async {
    let sync = sync(center: .default)
    sync.start()
    let setting = Setting("mirrored", default: "", store: defaults)

    store.values["mirrored"] = "external"
    NotificationCenter.default.post(
      name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: store,
      userInfo: [NSUbiquitousKeyValueStoreChangedKeysKey: ["mirrored"]])
    await drainMain()

    #expect(setting.value == "external")
    #expect(store.setCount == 0)
  }

  @Test func multipleSettingsOnOneKeySyncLocallyWithASingleUpload() async {
    let sync = sync(center: .default)
    sync.start()
    let a = Setting("mirrored", default: "", store: defaults)
    let b = Setting("mirrored", default: "", store: defaults)

    a.value = "from a"
    await drainMain()

    #expect(b.value == "from a")
    #expect(store.values["mirrored"] as? String == "from a")
    #expect(store.setCount == 1)
  }

  // MARK: - Lifecycle

  @Test func stopSilencesBothDirections() {
    let sync = sync()
    sync.start()
    sync.stop()

    defaults.set("local", forKey: "mirrored")
    postSettingMutation(key: "mirrored")
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

    defaults.set("local", forKey: "mirrored")
    postSettingMutation(key: "mirrored")
    #expect(store.values["mirrored"] == nil)

    store.values["mirrored"] = "cloud"
    postExternalChange(keys: ["mirrored"])
    #expect(defaults.string(forKey: "mirrored") == "local")
  }

  @Test func mutationsForAnotherDefaultsStoreAreIgnored() {
    let otherSuite = "SplintTests.CloudSync.other.\(UUID().uuidString)"
    let other = UserDefaults(suiteName: otherSuite)!
    defer { other.removePersistentDomain(forName: otherSuite) }
    other.set("someone else's", forKey: "mirrored")
    let sync = sync()
    sync.start()

    center.post(
      name: SettingMutation.didMutate, object: other,
      userInfo: [SettingMutation.keyKey: "mirrored"])

    #expect(store.values.isEmpty)
  }
}
