import SwiftUI
import Splint

/// Two `Setting` instances — one `Bool`, one `String` — each observed
/// independently via `@Bindable`. There is no `SettingsStore`: each
/// setting is its own observation point.
public struct SettingsView: View {
  @Environment(\.showCoversSetting) private var showCovers
  @Environment(\.preferredGenreSetting) private var preferredGenre

  public init() {}

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
          TextField("Preferred Genre", text: $g.value)
        }
      }
    }
    .navigationTitle("Settings")
  }
}
