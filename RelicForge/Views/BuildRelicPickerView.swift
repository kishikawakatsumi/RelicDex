import SwiftUI

/// ビルドのスロットに装備する遺物を選択するシート。
/// スロット色（white は全色受け入れ） と通常/深層はスロット側で固定されているため
/// ハードフィルタとして適用し、サイズ/効果はコレクションと同じ FilterBar で
/// ユーザーが絞り込めるようにする。
struct BuildRelicPickerView: View {
  let slotColor: VesselSlotColor
  let slotKind: BuildSlotKind
  /// 通常 3 スロット + 深層 3 スロットの色。セクションヘッダで「●●● ●●● 形式に
  /// すべて並べて、選択中スロットだけアクセントリングで強調」する用。
  let normalSlotColors: [VesselSlotColor]
  let deepSlotColors: [VesselSlotColor]
  /// 選択中のスロットインデックス（0..2）。kind と組み合わせて位置を決める。
  let slotIndex: Int
  let currentRelicId: UUID?
  let allRelics: [StoredRelic]
  let otherEquippedIds: Set<UUID>
  // フィルタはビルド単位で共有。スロットを跨いでも維持される。
  @Binding var sizeFilters: Set<Int>
  @Binding var effectDrilldowns: [Set<String>]
  @Binding var favoritesOnly: Bool
  let onSelect: (StoredRelic?) -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var searchText: String = ""

  // 色/種別はスロット側で固定なので bind せず、ローカルの空集合を維持してチップも隠す
  @State private var colorFilters: Set<RelicColor> = []
  @State private var depthFilters: Set<RelicDepth> = []
  @State private var showingEffectFilter = false
  @State private var showingSort = false
  @AppStorage("relicforge.relicpicker.sort.v1") private var sortConfigData: Data = Data()
  @State private var sortConfig = RelicSortConfig(option: .registered, ascending: false)

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        FilterBar(
          colorFilters: $colorFilters,
          sizeFilters: $sizeFilters,
          depthFilters: $depthFilters,
          effectDrilldowns: $effectDrilldowns,
          onTapEffectFilter: { showingEffectFilter = true },
          onTapSort: { showingSort = true },
          showsColor: false,
          showsDepth: false,
          favoritesOnly: $favoritesOnly
        )
        Divider()
        List {
          Section {
            Button(role: .destructive) {
              onSelect(nil)
              dismiss()
            } label: {
              HStack {
                Text("Unequip")
                Spacer()
                if currentRelicId == nil {
                  Image(systemName: "checkmark").foregroundStyle(.tint)
                }
              }
            }
          }
          Section {
            let candidates = filteredRelics
            if candidates.isEmpty {
              Text("No relics match.")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
              ForEach(candidates) { relic in
                let mismatch = mismatchReason(for: relic)
                let chipOK = chipFiltersMatch(relic)
                let dim = mismatch != nil || !chipOK
                // バッジは「他スロット装備中」のときだけ「装備中 / Equipped」で表示。
                // 色違い・深層用・通常用はバッジを出さず、グレー化だけで伝える。
                let equippedBadge = isEquippedElsewhere(relic)
                Button {
                  onSelect(relic)
                  dismiss()
                } label: {
                  relicRow(relic, badgeText: equippedBadge ? String(localized: "Equipped") : nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .opacity(dim ? 0.45 : 1.0)
                }
                .buttonStyle(.plain)
                .disabled(mismatch != nil)
              }
            }
          } header: {
            sectionHeader
          }
        }
      }
      .searchable(text: $searchText, prompt: "Search effect text")
      .navigationTitle("Select Relic")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Close") { dismiss() }
        }
      }
      .sheet(isPresented: $showingEffectFilter) {
        EffectFilterSheet(drilldowns: $effectDrilldowns)
      }
      .sheet(isPresented: $showingSort) {
        SortSheet(config: $sortConfig)
      }
      .onAppear {
        if let restored = try? JSONDecoder().decode(RelicSortConfig.self, from: sortConfigData) {
          sortConfig = restored
        }
      }
      .onChange(of: sortConfig) { _, new in
        sortConfigData = (try? JSONEncoder().encode(new)) ?? Data()
      }
    }
  }

  /// スロットの説明ヘッダ。
  /// 通常 3 スロット + 深層 3 スロットの色ドット（●●● ●●●） を並べて、
  /// 現在編集中のスロットだけアクセント色のリングで囲み「何番目を選んでいるか」を
  /// 文字なしで視覚化する。器画面の表現と同じ。
  @ViewBuilder
  private var sectionHeader: some View {
    HStack(spacing: 14) {  // 通常群と深層群の間に少し広いギャップ
      slotDots(colors: normalSlotColors, kind: .normal)
      slotDots(colors: deepSlotColors, kind: .deep)
    }
    .textCase(nil)  // セクションヘッダ既定の大文字化を抑制
  }

  @ViewBuilder
  private func slotDots(colors: [VesselSlotColor], kind: BuildSlotKind) -> some View {
    HStack(spacing: 4) {
      ForEach(Array(colors.enumerated()), id: \.offset) { idx, color in
        let isSelected = (kind == slotKind && idx == slotIndex)
        Circle()
          .fill(color.swatch)
          .frame(width: 12, height: 12)
          .overlay(
            Circle().stroke(.secondary.opacity(0.4), lineWidth: 0.5)
          )
          .overlay(
            Circle()
              .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
              .frame(width: 18, height: 18)
          )
          .frame(width: 18, height: 18)
      }
    }
  }

  /// スロットに装着できない理由を内部識別子で返す（装着可能なら nil）。
  /// 戻り値の文字列は **disable / opacity 判定にだけ** 使い、UI 表示はしない
  /// （バッジ表示は `isEquippedElsewhere（_:）` の結果のみ）。
  private func mismatchReason(for relic: StoredRelic) -> String? {
    if otherEquippedIds.contains(relic.id) && relic.id != currentRelicId {
      return "equipped-elsewhere"
    }
    if !slotColor.accepts(relic.color) { return "color-mismatch" }
    switch slotKind {
    case .normal: if relic.depth == .deep { return "deep-only" }
    case .deep:   if relic.depth != .deep { return "normal-only" }
    }
    return nil
  }

  /// 同じビルドの別スロットに既装備かどうか。バッジ表示はこちらだけで判定する。
  private func isEquippedElsewhere(_ relic: StoredRelic) -> Bool {
    otherEquippedIds.contains(relic.id) && relic.id != currentRelicId
  }

  /// チップ系フィルタ（お気に入り / 大きさ / 効果） は **ソフトフィルタ**。
  /// CollectionView と同じく、非該当もリストには出してグレー化で下に並べる。
  private func chipFiltersMatch(_ relic: StoredRelic) -> Bool {
    if favoritesOnly && !relic.isFavorite { return false }
    if !sizeFilters.isEmpty && !sizeFilters.contains(relic.slotCount) { return false }
    // 効果フィルタが 1 つも active でないときは Set 構築を丸ごと省略する
    //（2000 件 × 効果 ~6 個の Set 作りが open 直後の待ち時間に効いてくる）。
    let activeDrilldowns = effectDrilldowns.filter { !$0.isEmpty }
    if activeDrilldowns.isEmpty { return true }
    let relicBaseNames = Set(relic.effects.map { $0.baseName })
    for drilldown in activeDrilldowns {
      if relicBaseNames.isDisjoint(with: drilldown) { return false }
    }
    return true
  }

  private var filteredRelics: [StoredRelic] {
    let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

    // ハードフィルタは検索テキストのみ。
    // チップ（お気に入り/大きさ/効果） と スロット制約（色/種別/重複） はソフト
    // にして、非該当もグレー化で並べる。
    let filtered = allRelics.filter { relic in
      if q.isEmpty { return true }
      if relic.displayName.localizedCaseInsensitiveContains(q) { return true }
      return relic.effects.contains { $0.text.localizedCaseInsensitiveContains(q) }
    }

    // 比較器の中で `mismatchReason` / `chipFiltersMatch` を毎回叩くと、
    // それぞれが Set 構築や Set.contains を伴うため n log n の呼び出しが効いて
    // 2000 件規模で体感遅延になる。各 relic の判定値を 1 回だけ計算して
    // タプルに包み、比較器は事前計算値だけで決着させる。
    struct Sortable { let relic: StoredRelic; let isCurrent: Bool; let slotOK: Bool; let chipOK: Bool }
    let prepared: [Sortable] = filtered.map { relic in
      Sortable(
        relic: relic,
        isCurrent: relic.id == currentRelicId,
        slotOK: mismatchReason(for: relic) == nil,
        chipOK: chipFiltersMatch(relic)
      )
    }

    return prepared
      .sorted { a, b in
        // 1） 現在装備中 → 2） スロット装着可能 → 3） チップ該当 → 4） sortConfig
        if a.isCurrent != b.isCurrent { return a.isCurrent }
        if a.slotOK != b.slotOK { return a.slotOK }
        if a.chipOK != b.chipOK { return a.chipOK }
        return sortConfigOrders(a.relic, before: b.relic)
      }
      .map { $0.relic }
  }

  /// `RelicSortConfig` を使った 2 要素比較。配列 allocate を避けるため
  /// `[a, b].sorted（by: config）.first?.id == a.id` のイディオムから乗り換える。
  /// ロジックは `Array.sorted（by:）` 拡張と一致させる。
  private func sortConfigOrders(_ a: StoredRelic, before b: StoredRelic) -> Bool {
    let asc = sortConfig.ascending
    switch sortConfig.option {
    case .registered:
      return asc ? a.capturedAt < b.capturedAt : a.capturedAt > b.capturedAt
    case .size:
      if a.slotCount != b.slotCount {
        return asc ? a.slotCount < b.slotCount : a.slotCount > b.slotCount
      }
      return a.capturedAt > b.capturedAt
    case .color:
      let ai = a.color.sortIndex, bi = b.color.sortIndex
      if ai != bi { return asc ? ai < bi : ai > bi }
      return a.capturedAt > b.capturedAt
    }
  }

  private func relicRow(_ relic: StoredRelic, badgeText: String?) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Circle().fill(relic.color.swatch)
        .frame(width: 14, height: 14)
        .overlay(Circle().stroke(.secondary.opacity(0.4), lineWidth: 0.5))
        .padding(.top, 4)
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(relic.displayName).font(.body).foregroundStyle(.primary).lineLimit(1)
          if relic.isUnique {
            Text("Unique")
              .font(.caption2.weight(.bold))
              .padding(.horizontal, 5).padding(.vertical, 1)
              .background(.purple.opacity(0.18), in: Capsule())
              .foregroundStyle(.purple)
          }
          if let badgeText {
            Text(badgeText)
              .font(.caption2.weight(.bold))
              .padding(.horizontal, 5).padding(.vertical, 1)
              .background(.gray.opacity(0.25), in: Capsule())
              .foregroundStyle(.secondary)
          }
          Spacer()
          if relic.id == currentRelicId {
            Image(systemName: "checkmark").foregroundStyle(.tint)
          }
          Text("◆\(relic.slotCount)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        // 表示は CollectionView の RelicRow と同じパターンに揃える:
        // バレット（⚫） で main をマーク、demerit は 1 段インデント + smaller font +
        // demeritEffect 色 で main と視覚的にしっかり区別する。
        ForEach(Array(relic.slotsGrouped.enumerated()), id: \.offset) { _, pair in
          VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text(Image(systemName: "circle.fill"))
                .font(.system(size: 5))
                .baselineOffset(3)
                .foregroundStyle(.tertiary)
              Text(pair.main.localizedText)
                .font(.caption)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            }
            if let demerit = pair.demerit {
              HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Image(systemName: "circle.fill"))
                  .font(.system(size: 5))
                  .baselineOffset(3)
                  .foregroundStyle(Color.demeritEffect)
                Text(demerit.localizedText)
                  .font(.caption2)
                  .foregroundStyle(Color.demeritEffect)
                  .multilineTextAlignment(.leading)
                  .lineLimit(2)
              }
              .padding(.leading, 12)
            }
          }
        }
      }
    }
    .padding(.vertical, 2)
  }
}
