import SwiftUI

/// 効果フィルタの編集シート。
/// ゲームと同じく **3 段のドリルダウン** を提供する。
/// - 各ドリルダウン内の選択は OR （どれか1つに該当する効果を持つ遺物がヒット）
/// - ドリルダウン間は AND （すべての非空ドリルダウンを満たす遺物のみ）
struct EffectFilterSheet: View {
  /// 各ドリルダウンの選択状態。要素は効果のベース名（＋N を除いたもの）。
  @Binding var drilldowns: [Set<String>]
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        ForEach(drilldowns.indices, id: \.self) { idx in
          drilldownSection(idx: idx)
        }
      }
      .navigationTitle("Filter")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          if drilldowns.contains(where: { !$0.isEmpty }) {
            Button("Deselect All", role: .destructive) {
              drilldowns = drilldowns.map { _ in [] }
            }
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
    // 全画面ではなく半分くらいで止める。ユーザは上にドラッグで .large まで広げられる。
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  @ViewBuilder
  private func drilldownSection(idx: Int) -> some View {
    let selected = drilldowns[idx]
    Section {
      if selected.isEmpty {
        NavigationLink {
          EffectFilterCategoryView(selected: $drilldowns[idx])
        } label: {
          Label("Select Effect", systemImage: "plus.circle")
            .foregroundStyle(.tint)
        }
      } else {
        ForEach(Array(selected).sorted(), id: \.self) { baseName in
          HStack(spacing: 8) {
            Text(Image(systemName: "circle.fill"))
              .font(.system(size: 5))
              .baselineOffset(3)
              .foregroundStyle(.tertiary)
            Text(MasterDataStore.shared.localizedBaseName(baseName))
              .font(.subheadline)
            Spacer()
            Button {
              drilldowns[idx].remove(baseName)
            } label: {
              Image(systemName: "minus.circle.fill")
                .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
          }
        }
        NavigationLink {
          EffectFilterCategoryView(selected: $drilldowns[idx])
        } label: {
          Label("Select Effect", systemImage: "plus.circle")
            .foregroundStyle(.tint)
        }
        Button("Clear this filter", role: .destructive) {
          drilldowns[idx].removeAll()
        }
      }
    }
  }
}

/// 1段目: カテゴリピッカー（グループ毎にセクション分け）
struct EffectFilterCategoryView: View {
  @Binding var selected: Set<String>
  @State private var localSelected: Set<String> = []
  private let sections = MasterDataStore.shared.effectFilterSections

  var body: some View {
    List {
      ForEach(sections) { section in
        Section(section.localizedName) {
          ForEach(section.categories) { cat in
            NavigationLink {
              EffectFilterListView(category: cat, selected: $selected)
            } label: {
              HStack(spacing: 8) {
                Text(cat.localizedName)
                Spacer()
                let count = cat.effects.filter { localSelected.contains($0.baseName) }.count
                if count > 0 {
                  Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
              }
            }
          }
        }
      }
    }
    .navigationTitle("Selected")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { localSelected = selected }
    .onChange(of: selected) { _, new in localSelected = new }
  }
}

/// 2段目: 効果ベース名ピッカー（タップで複数選択トグル）
///
/// 注: 上位バインディングが `[Set<String>]` のサブスクリプト経由で渡ってくると
/// SwiftUI は初回 push 時にビューを再描画しない既知のクセがあるため、
/// `@State` のローカルコピーで UI を駆動し、変更を双方向に同期する。
struct EffectFilterListView: View {
  let category: EffectFilterCategory
  @Binding var selected: Set<String>
  @State private var localSelected: Set<String> = []

  var body: some View {
    List {
      // セクションヘッダーには現在のカテゴリ名（「能力値」「攻撃力」等） を出す。
      // ナビバーは「選択中」固定にして、どこから来たかをセクションで示す形。
      Section {
        ForEach(category.effects) { item in
          let isSelected = localSelected.contains(item.baseName)
          Button {
            if isSelected {
              localSelected.remove(item.baseName)
            } else {
              localSelected.insert(item.baseName)
            }
            selected = localSelected
          } label: {
            HStack {
              Text(item.localizedName)
                .foregroundStyle(.primary)
              Spacer()
              Image(systemName: "checkmark")
                .foregroundStyle(Color.accentColor)
                .opacity(isSelected ? 1 : 0)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      } header: {
        Text(category.localizedName)
      }
    }
    .navigationTitle("Selected")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { localSelected = selected }
    .onChange(of: selected) { _, new in localSelected = new }
  }
}
