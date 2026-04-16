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

  public init(service: String, account: String, synchronizable: Bool = true) {
    self.service = service
    self.account = account
    self.synchronizable = synchronizable
  }

  /// Error thrown on non-success, non-"not found" `SecItem*` status.
  public struct KeychainError: Error, CustomStringConvertible, Equatable {
    public let status: OSStatus
    public var description: String { "KeychainError(status: \(status))" }
  }

  /// Read the current value, or `nil` if absent.
  public func read() throws -> String? {
    var query = baseQuery()
    query[kSecReturnData as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      guard let data = item as? Data else { return nil }
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
    var addQuery = baseQuery()
    addQuery[kSecValueData as String] = data
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    switch addStatus {
    case errSecSuccess:
      return
    case errSecDuplicateItem:
      let attrs: [String: Any] = [kSecValueData as String: data]
      let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attrs as CFDictionary)
      guard updateStatus == errSecSuccess else {
        throw KeychainError(status: updateStatus)
      }
    default:
      throw KeychainError(status: addStatus)
    }
  }

  /// Delete the credential. Missing items are not an error.
  public func delete() throws {
    let status = SecItemDelete(baseQuery() as CFDictionary)
    switch status {
    case errSecSuccess, errSecItemNotFound:
      return
    default:
      throw KeychainError(status: status)
    }
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any,
    ]
  }
}
