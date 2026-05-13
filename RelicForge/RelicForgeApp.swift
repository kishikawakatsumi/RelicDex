import SwiftUI
import SwiftData

@main
struct RelicForgeApp: App {
  @StateObject private var incomingShare = IncomingShareNavigator()

  var body: some Scene {
    WindowGroup {
      RootTabView()
        .environmentObject(incomingShare)
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
          if let url = activity.webpageURL {
            incomingShare.handle(url: url)
          }
        }
        .onOpenURL { url in
          incomingShare.handle(url: url)
        }
    }
    .modelContainer(for: [StoredRelic.self, StoredRelicEffect.self, StoredBuild.self])
  }
}
