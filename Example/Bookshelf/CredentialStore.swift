import Foundation
import Splint

/// `kSecAttrService` for the Bookshelf demo credential. Grouped under the
/// app's bundle identifier so it can't collide with other services.
public let bookshelfCredentialService = "co.searls.splint.Bookshelf"
/// `kSecAttrAccount` for the Bookshelf demo API token.
public let bookshelfCredentialAccount = "api-token"

/// Observable status for a single `Credential`. Views read `state` and call
/// `save`/`clear`/`refresh`; the throwing keychain surface stays inside this
/// type so SwiftUI never sees a `throws` in a binding path.
@MainActor
@Observable
public final class CredentialStatus {
  public enum State: Equatable {
    case unknown
    case saved
    case notSet
    case error(String)
  }

  public private(set) var state: State = .unknown
  public let credential: Credential

  public init(credential: Credential) {
    self.credential = credential
  }

  public func refresh() {
    do {
      state = (try credential.read() != nil) ? .saved : .notSet
    } catch {
      state = .error(String(describing: error))
    }
  }

  public func save(_ value: String) {
    do {
      try credential.save(value)
      state = .saved
    } catch {
      state = .error(String(describing: error))
    }
  }

  public func clear() {
    do {
      try credential.delete()
      state = .notSet
    } catch {
      state = .error(String(describing: error))
    }
  }
}
