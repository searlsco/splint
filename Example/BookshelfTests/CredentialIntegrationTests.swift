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

  @Test func canClearIsFalseInUnknownState() {
    let (status, _) = makeStatus()
    // State is .unknown until refresh() runs.
    #expect(status.canClear == false)
  }

  @Test func canClearIsFalseAfterRefreshWithNoStoredToken() {
    let (status, _) = makeStatus()
    status.refresh()
    #expect(status.canClear == false)
  }

  @Test func canClearIsTrueAfterSave() {
    let (status, _) = makeStatus()
    status.save("secret-token")
    #expect(status.canClear == true)
  }

  @Test func refreshWithNoStoredTokenReportsNotSet() {
    let (status, _) = makeStatus()
    status.refresh()
    #expect(status.state == .notSet)
  }

  @Test func saveReportsSaved() {
    let (status, _) = makeStatus()
    status.save("secret-token")
    #expect(status.state == .saved)
  }

  @Test func refreshAfterSaveReportsSaved() {
    let (status, _) = makeStatus()
    status.save("secret-token")
    status.refresh()
    #expect(status.state == .saved)
  }

  @Test func clearResetsStatusToNotSet() {
    let (status, _) = makeStatus()
    status.save("secret-token")
    status.clear()
    #expect(status.state == .notSet)
  }

  @Test func saveOverwritesPreviousValue() throws {
    let (status, _) = makeStatus()
    status.save("first")
    status.save("second")
    #expect(try status.credential.read() == "second")
  }

  @Test func saveSurfacesBackendErrorsInState() {
    let backend = FailingBackend(addStatus: errSecAuthFailed)
    let (status, _) = makeStatus(backend: backend)
    status.save("secret-token")
    if case .error = status.state { /* ok */ } else {
      Issue.record("expected .error state, got \(String(describing: status.state))")
    }
  }

  @Test func refreshSurfacesBackendErrorsInState() {
    let backend = FailingBackend(readStatus: errSecAuthFailed)
    let (status, _) = makeStatus(backend: backend)
    status.refresh()
    if case .error = status.state { /* ok */ } else {
      Issue.record("expected .error state, got \(String(describing: status.state))")
    }
  }

  @Test func clearSurfacesBackendErrorsInState() {
    let backend = FailingBackend(deleteStatus: errSecAuthFailed)
    let (status, _) = makeStatus(backend: backend)
    status.clear()
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
  var readStatus: OSStatus = errSecItemNotFound
  var addStatus: OSStatus = errSecSuccess
  var updateStatus: OSStatus = errSecSuccess
  var deleteStatus: OSStatus = errSecSuccess
  func read(service: String, account: String, synchronizable: Bool)
    -> (status: OSStatus, data: Data?)
  { (readStatus, nil) }
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
