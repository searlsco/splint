import Foundation
import Security
import Testing

@_spi(Testing) import Splint
@testable import Bookshelf

/// Drives the same round-trip the Settings UI drives: save → read → delete,
/// using an injected in-memory `CredentialBackend` so CI doesn't touch the
/// real keychain.
@MainActor
@Suite("Bookshelf credential integration")
struct CredentialIntegrationTests {
  private func makeStatus(backend: any CredentialBackend = InMemoryBackend())
    -> (status: CredentialStatus, backend: any CredentialBackend)
  {
    let cred = Credential(
      service: "co.searls.bookshelf.tests",
      account: "api-token",
      synchronizable: false,
      backend: backend
    )
    return (CredentialStatus(credential: cred), backend)
  }

  @Test func refreshWithNoStoredTokenReportsNotSet() {
    let (status, _) = makeStatus()
    status.refresh()
    #expect(status.state == .notSet)
  }

  @Test func saveThenRefreshReportsSaved() {
    let (status, _) = makeStatus()
    status.save("secret-token")
    #expect(status.state == .saved)
    status.refresh()
    #expect(status.state == .saved)
  }

  @Test func clearResetsStatusToNotSet() {
    let (status, _) = makeStatus()
    status.save("secret-token")
    status.clear()
    #expect(status.state == .notSet)
  }

  @Test func saveOverwritesPreviousValue() {
    let backend = InMemoryBackend()
    let (status, _) = makeStatus(backend: backend)
    status.save("first")
    status.save("second")
    #expect(backend.currentValue() == "second")
  }

  @Test func saveSurfacesBackendErrorsInState() {
    let backend = FailingBackend(addStatus: errSecAuthFailed)
    let (status, _) = makeStatus(backend: backend)
    status.save("secret-token")
    if case .error = status.state { /* ok */ } else {
      Issue.record("expected .error state, got \(String(describing: status.state))")
    }
  }
}

// MARK: - Test backends

/// Thread-unsafe by design — tests are `@MainActor`-serialized and each test
/// gets its own instance.
private final class InMemoryBackend: CredentialBackend, @unchecked Sendable {
  private var storage: [String: Data] = [:]
  private func key(_ service: String, _ account: String, _ sync: Bool) -> String {
    "\(service)|\(account)|\(sync)"
  }
  func currentValue() -> String? {
    storage.values.first.flatMap { String(data: $0, encoding: .utf8) }
  }
  func read(service: String, account: String, synchronizable: Bool)
    -> (status: OSStatus, data: Data?)
  {
    if let data = storage[key(service, account, synchronizable)] {
      return (errSecSuccess, data)
    }
    return (errSecItemNotFound, nil)
  }
  func add(service: String, account: String, synchronizable: Bool, data: Data) -> OSStatus {
    let k = key(service, account, synchronizable)
    if storage[k] != nil { return errSecDuplicateItem }
    storage[k] = data
    return errSecSuccess
  }
  func update(service: String, account: String, synchronizable: Bool, data: Data) -> OSStatus {
    let k = key(service, account, synchronizable)
    guard storage[k] != nil else { return errSecItemNotFound }
    storage[k] = data
    return errSecSuccess
  }
  func delete(service: String, account: String, synchronizable: Bool) -> OSStatus {
    let k = key(service, account, synchronizable)
    if storage.removeValue(forKey: k) == nil { return errSecItemNotFound }
    return errSecSuccess
  }
}

private struct FailingBackend: CredentialBackend {
  var addStatus: OSStatus = errSecSuccess
  func read(service: String, account: String, synchronizable: Bool)
    -> (status: OSStatus, data: Data?)
  { (errSecItemNotFound, nil) }
  func add(service: String, account: String, synchronizable: Bool, data: Data) -> OSStatus {
    addStatus
  }
  func update(service: String, account: String, synchronizable: Bool, data: Data) -> OSStatus {
    errSecSuccess
  }
  func delete(service: String, account: String, synchronizable: Bool) -> OSStatus {
    errSecSuccess
  }
}
