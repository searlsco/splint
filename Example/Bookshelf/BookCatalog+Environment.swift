import SwiftUI
import Splint

/// Environment plumbing for the Bookshelf catalog, lenses, and shared
/// Splint instances. Views read these via `@Environment`; `ContentView`
/// writes them via `.environment()` so every descendant observes the
/// same source of truth.

extension EnvironmentValues {
  @Entry public var bookCatalog: Catalog<Book, BookCriteria>? = nil
  @Entry public var searchLens: Lens<Book>? = nil
  @Entry public var genreLens: Lens<Book>? = nil
  @Entry public var bookSelection: Selection<String>? = nil
  @Entry public var showCoversSetting: Setting<Bool>? = nil
  @Entry public var preferredGenreSetting: Setting<String>? = nil
  @Entry public var apiCredentialStatus: CredentialStatus? = nil
}
