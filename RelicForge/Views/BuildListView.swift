import SwiftUI
import SwiftData

/// ビルド一覧。キャラクターごとにセグメント分け。
/// "+" でそのキャラ用の新規ビルド（名称未設定） を作成して即編集に入る。
struct BuildListView: View {
  @Environment(\.modelContext) private var modelContext

  @Query(sort: \StoredBuild.updatedAt, order: .reverse)
  private var builds: [StoredBuild]

  @State private var selectedCharacterId: String?
  @State private var pendingNewBuild: StoredBuild?

  private let master = MasterDataStore.shared

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        characterPicker
        Divider()
        if filteredBuilds.isEmpty {
          emptyView
        } else {
          List {
            ForEach(filteredBuilds) { build in
              NavigationLink(destination: BuildEditorView(build: build)) {
                BuildRow(build: build)
              }
            }
            .onDelete(perform: deleteBuilds)
          }
          .listStyle(.plain)
        }
      }
      .navigationTitle("Builds")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: createBuild) {
            Image(systemName: "plus")
          }
          .disabled(currentCharacterId == nil)
        }
        ToolbarItem(placement: .topBarTrailing) {
          BackupActionsButton()
        }
      }
      .navigationDestination(item: $pendingNewBuild) { build in
        BuildEditorView(build: build)
      }
    }
    .onAppear {
      if selectedCharacterId == nil {
        selectedCharacterId = master.characters.first?.id
      }
    }
  }

  private var currentCharacterId: String? { selectedCharacterId }

  private var filteredBuilds: [StoredBuild] {
    guard let cid = currentCharacterId else { return [] }
    return builds
      .filter { $0.characterId == cid }
      .sorted { $0.updatedAt > $1.updatedAt }
  }

  private var characterPicker: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(master.characters) { c in
          let isSelected = c.id == selectedCharacterId
          Button {
            selectedCharacterId = c.id
          } label: {
            Text(c.localizedName)
              .font(.subheadline.weight(.medium))
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background(isSelected ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12),
                          in: Capsule())
              .foregroundStyle(isSelected ? Color.accentColor : .primary)
          }
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
    }
  }

  private var emptyView: some View {
    VStack(spacing: 12) {
      Image(systemName: "hammer")
        .font(.system(size: 64))
        .foregroundStyle(.secondary)
      Text("No builds for this character yet.\nTap + at the top right to create one.")
        .multilineTextAlignment(.leading)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }

  private func createBuild() {
    guard let cid = currentCharacterId else { return }
    let build = StoredBuild(characterId: cid)
    modelContext.insert(build)
    try? modelContext.save()
    pendingNewBuild = build
  }

  private func deleteBuilds(at offsets: IndexSet) {
    for idx in offsets {
      modelContext.delete(filteredBuilds[idx])
    }
    try? modelContext.save()
  }
}

private struct BuildRow: View {
  let build: StoredBuild

  private let master = MasterDataStore.shared

  var body: some View {
    let vessel = build.vesselId.flatMap { master.vessel(forId: $0) }
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(build.name)
          .font(.headline)
          .lineLimit(1)
        Spacer()
        // 器の色構成を ●●● ●●● で表示（BuildRelicPicker のヘッダと同じ表現）。
        // 未選択時は dots を出さず、下段の "Vessel: Not selected" のみで状態を伝える
        //（white x 6 のワイルドカード表示は誤読を招くため出さない）。
        if let vessel {
          HStack(spacing: 10) {
            slotDots(colors: vessel.baseSlots)
            slotDots(colors: vessel.deepSlots)
          }
        }
      }
      HStack(spacing: 6) {
        if let vessel {
          Text(vessel.localizedName).lineLimit(1)
        } else {
          Text("Vessel: Not selected").foregroundStyle(.tertiary)
        }
        Spacer()
        Text(build.updatedAt, format: .dateTime.year().month().day().hour().minute().second())
          .monospacedDigit()
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private func slotDots(colors: [VesselSlotColor]) -> some View {
    HStack(spacing: 3) {
      ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
        Circle()
          .fill(color.swatch)
          .frame(width: 8, height: 8)
          .overlay(Circle().stroke(.secondary.opacity(0.4), lineWidth: 0.5))
      }
    }
  }

}
