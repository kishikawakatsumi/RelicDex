import SwiftUI

struct RootTabView: View {
  var body: some View {
    TabView {
      CollectionView()
        .toolbarBackground(.visible, for: .tabBar)
        .tabItem { Label("Collection", systemImage: "tray.full") }
      BuildListView()
        .toolbarBackground(.visible, for: .tabBar)
        .tabItem { Label("Builds", systemImage: "hammer") }
    }
  }
}
