import Foundation
import Testing

@_spi(Testing) @testable import Splint

@Suite("Credential")
struct CredentialTests {
  private func makeCredential() -> Credential {
    // Unique per-test account to avoid keychain pollution between runs.
    // `synchronizable: false` keeps tests off iCloud Keychain.
    Credential(
      service: "co.searls.splint.tests",
      account: "test-\(UUID().uuidString)",
      synchronizable: false
    )
  }

  @Test func saveThenReadReturnsValue() throws {
    let c = makeCredential()
    defer { try? c.delete() }
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
    defer { try? c.delete() }
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
