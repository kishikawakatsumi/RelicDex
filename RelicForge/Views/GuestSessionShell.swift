import SwiftUI
import SwiftData

/// 共有 URL から取得した ExportPayload を **in-memory の ModelContainer** に展開し、
/// 通常のタブ UI（RootTabView） をその上に被せて編集できるようにするシェル。
/// 自分の永続データは一切触らないので、相談用に他人のビルドを試したり、
/// 受け取ったデータをベースに新しいビルドを組んで再共有するのに使う。
struct GuestSessionShell: View {
  @Environment(\.dismiss) private var dismiss

  /// in-memory コンテナ。GuestSessionShell の生存期間と同じ寿命。
  @State private var container: ModelContainer
  @State private var loadError: String?

  init(payload: ExportPayload) {
    do {
      let config = ModelConfiguration(isStoredInMemoryOnly: true)
      let c = try ModelContainer(
        for: StoredRelic.self, StoredRelicEffect.self, StoredBuild.self,
        configurations: config
      )
      try RelicImportService.replaceAll(with: payload, in: c.mainContext)
      _container = State(initialValue: c)
      _loadError = State(initialValue: nil)
    } catch {
      // 万一失敗してもクラッシュさせない: 空のコンテナで開いてエラー表示
      let fallback = try! ModelContainer(
        for: StoredRelic.self, StoredRelicEffect.self, StoredBuild.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
      )
      _container = State(initialValue: fallback)
      _loadError = State(initialValue: error.localizedDescription)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      banner
      if let loadError {
        Text("Load failed: \(loadError)")
          .padding()
          .foregroundStyle(.red)
      }
      RootTabView()
    }
    .modelContainer(container)
  }

  private var banner: some View {
    // 「ゲストモード = 別人のデータを覗いている / 一時的な世界」を Nightreign の
    // 世界観に寄せたインディゴでさりげなく示す。
    // bar マテリアル（ナビゲーションバーと同じ） の上に薄くインディゴを重ねて、
    // アイコンと下部のラインで色を強調する。
    HStack(spacing: 8) {
      Image(systemName: "person.2.fill")
        .foregroundStyle(.indigo)
      Text("Guest Mode ・ Edits are not saved on this device")
        .font(.footnote.weight(.medium))
        .lineLimit(2)
      Spacer()
      Button("Exit") { dismiss() }
        .font(.footnote.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(.indigo)
        .controlSize(.small)
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
    .background {
      ZStack {
        Rectangle().fill(.bar)
        Rectangle().fill(Color.indigo.opacity(0.18))
      }
    }
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color.indigo.opacity(0.55))
        .frame(height: 1)
    }
  }
}
