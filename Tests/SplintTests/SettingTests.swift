import Foundation
import Testing

@testable import Splint

@MainActor
@Suite("Setting")
struct SettingTests {
  private func freshStore(_ fn: String = #function) -> UserDefaults {
    let suite = "SplintTests.Setting.\(fn).\(UUID().uuidString)"
    let store = UserDefaults(suiteName: suite)!
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
}
