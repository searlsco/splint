import Foundation
import Testing

@_spi(Testing) @testable import Splint

@Suite("Credential")
struct CredentialTests {
  // The SwiftPM test runner is unsigned, so it has no
  // `keychain-access-groups` entitlement and cannot reach the
  // data-protection keychain. Round trips run against an in-memory backend.
  private func makeCredential() -> Credential {
    Credential(service: "s", account: "a", synchronizable: false, backend: InMemoryBackend())
  }

  @Test func saveThenReadReturnsValue() throws {
    let c = makeCredential()
    try c.save("hello")
    #expect(try c.read() == "hello")
  }

  @Test func deleteThenReadReturnsNil() throws {
    let c = makeCredential()
    try c.save("x")
    try c.delete()
    #expect(try c.read() == nil)
  }

  @Test func saveOverwritesExistingValue() throws {
    let c = makeCredential()
    try c.save("first")
    try c.save("second")
    #expect(try c.read() == "second")
  }

  @Test func readReturnsNilWhenAbsent() throws {
    let c = makeCredential()
    #expect(try c.read() == nil)
  }

  @Test func deleteAbsentIsNotAnError() throws {
    let c = makeCredential()
    try c.delete()
    try c.delete()
  }

  // MARK: - Error paths (injected backend)

  @Test func readThrowsKeychainErrorOnBackendFailure() {
    let backend = StubBackend(readStatus: errSecAuthFailed)
    let c = Credential(service: "s", account: "a", synchronizable: false, backend: backend)
    #expect(throws: Credential.KeychainError(status: errSecAuthFailed)) {
      _ = try c.read()
    }
  }

  @Test func saveThrowsKeychainErrorOnAddFailure() {
    let backend = StubBackend(addStatus: errSecAuthFailed)
    let c = Credential(service: "s", account: "a", synchronizable: false, backend: backend)
    #expect(throws: Credential.KeychainError(status: errSecAuthFailed)) {
      try c.save("v")
    }
  }

  @Test func saveThrowsKeychainErrorOnUpdateFailure() {
    // Add returns duplicate → update returns error → throws.
    let backend = StubBackend(addStatus: errSecDuplicateItem, updateStatus: errSecParam)
    let c = Credential(service: "s", account: "a", synchronizable: false, backend: backend)
    #expect(throws: Credential.KeychainError(status: errSecParam)) {
      try c.save("v")
    }
  }

  @Test func deleteThrowsKeychainErrorOnBackendFailure() {
    let backend = StubBackend(deleteStatus: errSecAuthFailed)
    let c = Credential(service: "s", account: "a", synchronizable: false, backend: backend)
    #expect(throws: Credential.KeychainError(status: errSecAuthFailed)) {
      try c.delete()
    }
  }

  // MARK: - System backend

  @Test(arguments: [false, true])
  func systemBackendTargetsDataProtectionKeychain(synchronizable: Bool) {
    let query = SystemKeychainBackend().baseQuery(
      service: "s", account: "a", synchronizable: synchronizable)
    #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
  }

  @Test func systemBackendOperationsReachDataProtectionKeychain() {
    // An unsigned process may write to the legacy login keychain (where
    // these items used to land), but the data-protection keychain demands
    // the `keychain-access-groups` entitlement, so every write is refused
    // and nothing is stored. The exact status depends on the host.
    let b = SystemKeychainBackend()
    let (service, account) = ("co.searls.splint.tests", "test-\(UUID().uuidString)")
    defer { _ = b.delete(service: service, account: account, synchronizable: false) }
    #expect(b.add(service: service, account: account, synchronizable: false, data: Data("x".utf8)) != errSecSuccess)
    #expect(b.read(service: service, account: account, synchronizable: false).data == nil)
    #expect(b.update(service: service, account: account, synchronizable: false, data: Data("y".utf8)) != errSecSuccess)
    #expect(b.delete(service: service, account: account, synchronizable: false) != errSecSuccess)
  }

  @Test func publicInitSyncsByDefaultAndUsesSystemKeychain() {
    #expect(Credential(service: "s", account: "a").synchronizable)
    let c = Credential(service: "co.searls.splint.tests", account: "test-\(UUID().uuidString)", synchronizable: false)
    defer { try? c.delete() }
    #expect(throws: Credential.KeychainError.self) {
      try c.save("x")
    }
  }

  @Test func keychainErrorExposesStatusAndDescribesItself() {
    let e = Credential.KeychainError(status: -25300)
    #expect(e.status == -25300)
    #expect(e.description.contains("-25300"))
    #expect(e == Credential.KeychainError(status: -25300))
    #expect(e != Credential.KeychainError(status: 0))
  }
}

// A `CredentialBackend` that returns canned OSStatus values for each
// operation. Used to exercise Credential's error branches without
// poking the real keychain.
private struct StubBackend: CredentialBackend {
  var readStatus: OSStatus = errSecSuccess
  var readData: Data? = nil
  var addStatus: OSStatus = errSecSuccess
  var updateStatus: OSStatus = errSecSuccess
  var deleteStatus: OSStatus = errSecSuccess

  func read(service: String, account: String, synchronizable: Bool)
    -> (status: OSStatus, data: Data?)
  {
    (readStatus, readData)
  }

  func add(service: String, account: String, synchronizable: Bool, data: Data) -> OSStatus {
    addStatus
  }

  func update(service: String, account: String, synchronizable: Bool, data: Data) -> OSStatus {
    updateStatus
  }

  func delete(service: String, account: String, synchronizable: Bool) -> OSStatus {
    deleteStatus
  }
}

// A `CredentialBackend` that behaves like the keychain for one process:
// add fails on duplicates, update and delete fail when absent.
private final class InMemoryBackend: CredentialBackend, @unchecked Sendable {
  private let lock = NSLock()
  private var items: [String: Data] = [:]

  private func key(_ service: String, _ account: String, _ synchronizable: Bool) -> String {
    "\(service)|\(account)|\(synchronizable)"
  }

  func read(service: String, account: String, synchronizable: Bool)
    -> (status: OSStatus, data: Data?)
  {
    lock.withLock {
      guard let data = items[key(service, account, synchronizable)] else { return (errSecItemNotFound, nil) }
      return (errSecSuccess, data)
    }
  }

  func add(service: String, account: String, synchronizable: Bool, data: Data) -> OSStatus {
    lock.withLock {
      let k = key(service, account, synchronizable)
      guard items[k] == nil else { return errSecDuplicateItem }
      items[k] = data
      return errSecSuccess
    }
  }

  func update(service: String, account: String, synchronizable: Bool, data: Data) -> OSStatus {
    lock.withLock {
      let k = key(service, account, synchronizable)
      guard items[k] != nil else { return errSecItemNotFound }
      items[k] = data
      return errSecSuccess
    }
  }

  func delete(service: String, account: String, synchronizable: Bool) -> OSStatus {
    lock.withLock { items.removeValue(forKey: key(service, account, synchronizable)) == nil ? errSecItemNotFound : errSecSuccess }
  }
}
