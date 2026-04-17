import SwiftUI
import Splint

/// Two `Setting` instances — one `Bool`, one `String` — each observed
/// independently via `@Bindable`. There is no `SettingsStore`: each
/// setting is its own observation point. The genre Picker is fed from
/// the catalog's distinct genres so the demo stays self-consistent.
public struct SettingsView: View {
  @Environment(\.showCoversSetting) private var showCovers
  @Environment(\.preferredGenreSetting) private var preferredGenre
  @Environment(\.bookCatalog) private var catalog
  @Environment(\.apiCredentialStatus) private var apiCredentialStatus

  public init() {}

  private var genres: [String] {
    Self.buildGenres(catalogItems: catalog?.items ?? [], persisted: preferredGenre?.value)
  }

  /// The Picker's option list. Always includes `"All"` and — critically
  /// — the currently persisted value, so opening Settings before the
  /// catalog loads (or with a value left over from a prior build)
  /// never leaves the Picker without a matching tag.
  static func buildGenres(catalogItems: [Book], persisted: String?) -> [String] {
    var set = Set(catalogItems.map(\.genre))
    if let persisted { set.insert(persisted) }
    return ["All"] + set.subtracting(["All"]).sorted()
  }

  public var body: some View {
    Form {
      Section("Display") {
        if let showCovers {
          @Bindable var s = showCovers
          Toggle("Show Covers", isOn: $s.value)
        }
      }
      Section("Filters") {
        if let preferredGenre {
          @Bindable var g = preferredGenre
          Picker("Preferred Genre", selection: $g.value) {
            ForEach(genres, id: \.self) { Text($0).tag($0) }
          }
        }
      }
      Section("API") {
        if let apiCredentialStatus {
          APITokenRow(status: apiCredentialStatus)
        }
      }
    }
    .navigationTitle("Settings")
  }
}

/// Demonstrates `Credential` as a device-local keychain round-trip. Holds a
/// transient `draft` so the `SecureField` doesn't bind to the saved value.
private struct APITokenRow: View {
  let status: CredentialStatus
  @State private var draft = ""

  var body: some View {
    SecureField("API token", text: $draft)
    HStack {
      Button("Save") {
        status.save(draft)
        draft = ""
      }
      .disabled(draft.isEmpty)
      Button("Clear", role: .destructive) {
        status.clear()
      }
      .disabled(status.state == .notSet)
    }
    Text(statusText)
      .font(.footnote)
      .foregroundStyle(.secondary)
  }

  private var statusText: String {
    switch status.state {
    case .unknown: return "…"
    case .saved: return "Saved"
    case .notSet: return "Not set"
    case .error(let message): return "Error: \(message)"
    }
  }
}
