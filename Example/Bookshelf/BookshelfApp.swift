import SwiftData
import SwiftUI

/// App entry point. Shows the full DI chain: the app constructs the
/// client, passes it to `ContentView`'s `init`, and `ContentView`
/// constructs its `Catalog` with the client's fetch closure. No
/// singletons, no service locators, no late-binding.
@main
struct BookshelfApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView(client: .live)
    }
    .modelContainer(for: Favorite.self)
  }
}
