import Foundation
import Security

/// A keychain-backed secret. A struct — not `@Observable` — because
/// credentials are read on demand, not watched by views.
///
/// Wraps `SecItem` with the correct add-or-update dance and accessibility
/// defaults. Raw keychain code is hostile and agent-produced
/// implementations drift wrong; this wrapper is the canonical form.
public struct Credential: Sendable {
  /// The `kSecAttrService` value. Group credentials by app-level concern.
  public let service: String
  /// The `kSecAttrAccount` value. Identifies the specific credential within
  /// a service (e.g. username, provider id).
  public let account: String
  /// When `true`, the credential syncs via iCloud Keychain. Defaults to
  /// `true` for cross-device convenience; pass `false` for device-local
  /// secrets.
  public let synchronizable: Bool

  private let backend: any CredentialBackend

  public init(service: String, account: String, synchronizable: Bool = true) {
    self.init(
      service: service,
      account: account,
      synchronizable: synchronizable,
      backend: SystemKeychainBackend()
    )
  }

  /// Test-only init that accepts a backend stub. Public for cross-target
  /// visibility under `@_spi(Testing)`; not part of the semver surface.
  @_spi(Testing)
  public init(
    service: String,
    account: String,
    synchronizable: Bool,
    backend: any CredentialBackend
  ) {
    self.service = service
    self.account = account
    self.synchronizable = synchronizable
    self.backend = backend
  }

  /// Error thrown on non-success, non-"not found" `SecItem*` status.
  public struct KeychainError: Error, CustomStringConvertible, Equatable {
    public let status: OSStatus
    public init(status: OSStatus) { self.status = status }
    public var description: String { "KeychainError(status: \(status))" }
  }

  /// Read the current value, or `nil` if absent.
  public func read() throws -> String? {
    let (status, data) = backend.read(
      service: service, account: account, synchronizable: synchronizable)
    switch status {
    case errSecSuccess:
      guard let data else { return nil }
      return String(data: data, encoding: .utf8)
    case errSecItemNotFound:
      return nil
    default:
      throw KeychainError(status: status)
    }
  }

  /// Save the value. Creates the item if absent, updates it in place if
  /// present. Does NOT delete-then-add (which would churn the item's
  /// creation date and can cause iCloud Keychain sync conflicts).
  public func save(_ value: String) throws {
    let data = Data(value.utf8)
    let addStatus = backend.add(
      service: service, account: account, synchronizable: synchronizable, data: data)
    switch addStatus {
    case errSecSuccess:
      return
    case errSecDuplicateItem:
      let updateStatus = backend.update(
        service: service, account: account, synchronizable: synchronizable, data: data)
      guard updateStatus == errSecSuccess else {
        throw KeychainError(status: updateStatus)
      }
    default:
      throw KeychainError(status: addStatus)
    }
  }

  /// Delete the credential. Missing items are not an error.
  public func delete() throws {
    let status = backend.delete(
      service: service, account: account, synchronizable: synchronizable)
    switch status {
    case errSecSuccess, errSecItemNotFound:
      return
    default:
      throw KeychainError(status: status)
    }
  }
}

/// Swappable backend for keychain operations. Not part of the semver
/// surface — tests inject stubs via `@_spi(Testing)`; production code
/// always uses ``SystemKeychainBackend``.
@_spi(Testing)
public protocol CredentialBackend: Sendable {
  func read(service: String, account: String, synchronizable: Bool)
    -> (status: OSStatus, data: Data?)
  func add(service: String, account: String, synchronizable: Bool, data: Data) -> OSStatus
  func update(service: String, account: String, synchronizable: Bool, data: Data) -> OSStatus
  func delete(service: String, account: String, synchronizable: Bool) -> OSStatus
}

/// Real backend wrapping `SecItem*`. Hardcodes
/// `kSecAttrAccessibleAfterFirstUnlock` because the OS default has
/// changed across versions and agents tend to pick the wrong value.
@_spi(Testing)
public struct SystemKeychainBackend: CredentialBackend {
  public init() {}

  public func read(service: String, account: String, synchronizable: Bool)
    -> (status: OSStatus, data: Data?)
  {
    var query = baseQuery(service: service, account: account, synchronizable: synchronizable)
    query[kSecReturnData as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    return (status, item as? Data)
  }

  public func add(service: String, account: String, synchronizable: Bool, data: Data) -> OSStatus {
    var query = baseQuery(service: service, account: account, synchronizable: synchronizable)
    query[kSecValueData as String] = data
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    return SecItemAdd(query as CFDictionary, nil)
  }

  public func update(service: String, account: String, synchronizable: Bool, data: Data) -> OSStatus
  {
    let query = baseQuery(service: service, account: account, synchronizable: synchronizable)
    let attrs: [String: Any] = [kSecValueData as String: data]
    return SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
  }

  public func delete(service: String, account: String, synchronizable: Bool) -> OSStatus {
    let query = baseQuery(service: service, account: account, synchronizable: synchronizable)
    return SecItemDelete(query as CFDictionary)
  }

  private func baseQuery(service: String, account: String, synchronizable: Bool) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: synchronizable
        ? kCFBooleanTrue as Any : kCFBooleanFalse as Any,
    ]
  }
}
