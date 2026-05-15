import SwiftUI

/// 候補を「固有遺物」としてマークするためのピッカー。OCR がタイトルを読めず
/// 非固有として扱われたが、画像を見れば人間には固有遺物と分かるケースで使う。
/// 選択された固有遺物の name / color / slot 数 / 効果は master データで確定して
/// いるので、ユーザーは名前を選ぶだけで済む。
struct UniqueRelicPickerView: View {
  /// 現在選択中の固有遺物 ID (nil = 非固有)
  let current: String?
  /// スキャン元の言語に合わせて表示するためのヒント
  let prefersJapanese: Bool
  /// 選択結果。nil で「非固有に戻す」。
  let onPick: (UniqueRelic?) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var search: String = ""

  private var uniques: [UniqueRelic] { MasterDataStore.shared.uniqueRelics }

  private var filtered: [UniqueRelic] {
    let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return uniques }
    return uniques.filter {
      $0.nameJa.localizedCaseInsensitiveContains(q)
        || $0.nameEn.localizedCaseInsensitiveContains(q)
    }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          Button {
            onPick(nil)
            dismiss()
          } label: {
            HStack {
              Image(systemName: "circle.slash")
                .foregroundStyle(.secondary)
              Text("Not a unique relic")
              Spacer()
              if current == nil {
                Image(systemName: "checkmark")
                  .foregroundStyle(Color.accentColor)
              }
            }
          }
          .foregroundStyle(.primary)
        }

        Section {
          ForEach(filtered) { u in
            Button {
              onPick(u)
              dismiss()
            } label: {
              HStack(spacing: 10) {
                Circle()
                  .fill(u.color.swatch)
                  .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                  Text(prefersJapanese ? u.nameJa : u.nameEn)
                    .foregroundStyle(.primary)
                  Text("◆ \(u.slotCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if u.id == current {
                  Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                }
              }
            }
            .foregroundStyle(.primary)
          }
        } header: {
          Text("Unique relics (\(filtered.count))")
        }
      }
      .listStyle(.insetGrouped)
      .searchable(text: $search,
                  placement: .navigationBarDrawer(displayMode: .always))
      .navigationTitle("Select unique relic")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }
}
