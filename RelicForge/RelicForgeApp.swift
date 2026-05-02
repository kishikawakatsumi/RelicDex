import SwiftUI
import SwiftData

@main
struct RelicForgeApp: App {
  @StateObject private var incomingShare = IncomingShareNavigator()

  var body: some Scene {
    WindowGroup {
      RootTabView()
        .environmentObject(incomingShare)
        // Universal Links（relicforge.pages.dev/s/{key}） で起動した場合
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
          if let url = activity.webpageURL { incomingShare.handle(url: url) }
        }
        // カスタム URL スキーム（将来用） や、外部から共有 URL を直接渡された場合
        .onOpenURL { url in
          incomingShare.handle(url: url)
        }
    }
    .modelContainer(for: [StoredRelic.self, StoredRelicEffect.self, StoredBuild.self])
  }
}
