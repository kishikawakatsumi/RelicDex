import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CollectionView: View {
  @Environment(\.modelContext) private var modelContext
  @EnvironmentObject private var incomingShare: IncomingShareNavigator
  @Query(sort: \StoredRelic.capturedAt, order: .reverse)
  private var relics: [StoredRelic]
  /// ビルド側の参照チェック用（使用中の遺物は削除させない）
  @Query private var allBuilds: [StoredBuild]

  /// 各カテゴリ内は OR （複数選択可）、カテゴリ間は AND。
  /// 空のセット = そのカテゴリでは絞り込まない（= すべて通過）。
  @State private var colorFilters: Set<RelicColor> = []
  @State private var sizeFilters: Set<Int> = []           // slotCount: 1=小 / 2=中 / 3=大
  @State private var depthFilters: Set<RelicDepth> = []
  /// 効果フィルタは最大3段のドリルダウン（各 = ベース名のセット、内 OR / 間 AND）
  @State private var effectDrilldowns: [Set<String>] = [[], [], []]
  @State private var searchText: String = ""
  @State private var showingEffectFilter = false
  @State private var showingSort = false
  @AppStorage("relicforge.collection.sort.v1") private var sortConfigData: Data = Data()
  @State private var sortConfig = RelicSortConfig(option: .registered, ascending: false)
  @State private var showingCapture = false
  @State private var showingManualEntry = false
  @State private var favoritesOnly = false
  /// 使用中/お気に入りの遺物の削除を試みた時の警告 alert
  @State private var inUseAlertMessage: String?
  /// Universal Link 経由で開かれたゲストセッション（Backup 系の guestSession とは独立）
  @State private var incomingGuestSession: GuestSessionPayload?

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
          favoritesOnly: $favoritesOnly
        )
        Divider()
        if displayedRelics.isEmpty {
          emptyView
        } else {
          List {
            ForEach(Array(displayedRelics.enumerated()), id: \.element.relic.id) { _, item in
              NavigationLink(destination: RelicDetailView(relic: item.relic)) {
                RelicRow(relic: item.relic,
                         highlight: searchText,
                         inUse: usedRelicIds.contains(item.relic.id))
                  .opacity(item.matched ? 1.0 : 0.45)
              }
            }
            .onDelete(perform: deleteRelics)
          }
          .listStyle(.plain)
        }
      }
      .searchable(text: $searchText, prompt: "Search effect text (e.g., Physical Attack)")
      .navigationTitle("Collection")
      .toolbar {
        if #available(iOS 26.0, *) {
          ToolbarItem(placement: .topBarTrailing) {
            Text("\(matchedCount) / \(relics.count)")
              .font(.subheadline.monospacedDigit())
              .foregroundStyle(.secondary)
          }
          .sharedBackgroundVisibility(.hidden)
        } else {
          ToolbarItem(placement: .topBarTrailing) {
            Text("\(matchedCount) / \(relics.count)")
              .font(.subheadline.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button {
              showingCapture = true
            } label: {
              Label("Add with Camera", systemImage: "viewfinder")
            }
            Button {
              showingManualEntry = true
            } label: {
              Label("Add Manually", systemImage: "rectangle.and.pencil.and.ellipsis")
            }
          } label: {
            Image(systemName: "plus")
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          BackupActionsButton()
        }
      }
      .sheet(isPresented: $showingEffectFilter) {
        EffectFilterSheet(drilldowns: $effectDrilldowns)
      }
      .sheet(isPresented: $showingSort) {
        SortSheet(config: $sortConfig)
      }
      .onAppear {
        // 永続化された sortConfig を復元
        if let restored = try? JSONDecoder().decode(RelicSortConfig.self, from: sortConfigData) {
          sortConfig = restored
        }
      }
      .onChange(of: sortConfig) { _, new in
        sortConfigData = (try? JSONEncoder().encode(new)) ?? Data()
      }
      .sheet(isPresented: $showingManualEntry) {
        ManualRelicEntryView()
      }
      // Universal Link で /s/{key} が開かれたら自動でインポート画面を開く
      .sheet(item: incomingShareBinding) { incoming in
        ImportFromURLView(initialInput: incoming.key,
                          onOpenGuest: { payload in
          // Universal Link 経由のゲスト表示。Backup 系とは別系統で扱う。
          incomingGuestSession = GuestSessionPayload(payload: payload)
        })
      }
      .fullScreenCover(item: $incomingGuestSession) { session in
        GuestSessionShell(payload: session.payload)
      }
      .fullScreenCover(isPresented: $showingCapture) {
        RelicCaptureView {
          showingCapture = false
        }
      }
      .alert("Cannot delete",
             isPresented: Binding(get: { inUseAlertMessage != nil },
                                  set: { if !$0 { inUseAlertMessage = nil } })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(inUseAlertMessage ?? "")
      }
    }
  }

  /// Universal Link で来た key を sheet（item:） に流し込むためのアダプタ
  private struct IncomingShareKey: Identifiable {
    let key: String
    var id: String { key }
  }

  private var incomingShareBinding: Binding<IncomingShareKey?> {
    Binding(
      get: { incomingShare.pendingShareKey.map(IncomingShareKey.init) },
      set: { newValue in incomingShare.pendingShareKey = newValue?.key }
    )
  }

  private var emptyView: some View {
    VStack(spacing: 12) {
      Image(systemName: "tray")
        .font(.system(size: 64))
        .foregroundStyle(.secondary)
      Text(relics.isEmpty
           ? "No relics yet.\nTap + at the top right to add one."
           : "No relics match the filters.")
      .multilineTextAlignment(.leading)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding()
  }

  /// 全ビルドのスロットに含まれている遺物 ID 集合（アイコン表示用）
  private var usedRelicIds: Set<UUID> {
    var s: Set<UUID> = []
    for b in allBuilds {
      for case let id? in b.normalSlotRelicIds + b.deepSlotRelicIds {
        s.insert(id)
      }
    }
    return s
  }

  private func deleteRelics(at offsets: IndexSet) {
    let toDelete = offsets.map { displayedRelics[$0].relic }
    // お気に入り / ビルドで使用中のものは削除をブロックし、まとめて警告する
    var messages: [String] = []
    var deletable: [StoredRelic] = []
    for relic in toDelete {
      if relic.isFavorite {
        messages.append(String(localized: "\"\(relic.displayName)\" is favorited"))
        continue
      }
      let usingBuilds = allBuilds.filter { $0.uses(relicId: relic.id) }
      if usingBuilds.isEmpty {
        deletable.append(relic)
      } else {
        let names = usingBuilds.map { $0.name }.joined(separator: ", ")
        messages.append(String(localized: "\"\(relic.displayName)\" is used in builds: \(names)"))
      }
    }
    for relic in deletable {
      modelContext.delete(relic)
    }
    if !deletable.isEmpty { try? modelContext.save() }
    if !messages.isEmpty {
      inUseAlertMessage = messages.joined(separator: "\n\n") +
        String(localized: "\n\nRemove from favorites or unequip from builds first.")
    }
  }

  /// 検索（テキスト） は **ハードフィルタ** （打鍵意図が強いので非該当は隠す）。
  /// 検索通過した遺物だけが表示対象になる。
  private var visibleRelics: [StoredRelic] {
    let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if q.isEmpty { return Array(relics) }
    return relics.filter { relic in
      let inEffects = relic.effects.contains { $0.text.localizedCaseInsensitiveContains(q) }
      let inName = relic.displayName.localizedCaseInsensitiveContains(q)
      return inEffects || inName
    }
  }

  /// チップ系フィルタ（色 / 大きさ / 種別 / 効果 / お気に入り） は **ソフトフィルタ**。
  /// 該当しないものも非表示にせず、グレー化して下に並べる（BuildRelicPicker と同じ表現）。
  /// 固有遺物は保存時点で `depth == .normal` に正規化されているので、深度フィルタは
  /// 通常の比較だけで OK （旧版で `.unknown` だったレコードはロード時に補正）。
  private func matchesChipFilters(_ relic: StoredRelic) -> Bool {
    if favoritesOnly && !relic.isFavorite { return false }
    if !colorFilters.isEmpty && !colorFilters.contains(relic.color) { return false }
    if !sizeFilters.isEmpty && !sizeFilters.contains(relic.slotCount) { return false }
    if !depthFilters.isEmpty && !depthFilters.contains(relic.depth) { return false }
    let relicBaseNames = Set(relic.effects.map { $0.baseName })
    for drilldown in effectDrilldowns where !drilldown.isEmpty {
      if relicBaseNames.isDisjoint(with: drilldown) { return false }
    }
    return true
  }

  /// リスト表示用: マッチ済みを上に、未マッチを下に。それぞれの群内で sortConfig
  /// に従って並べる。返り値の Bool は「ソフトフィルタにマッチしたか」。
  private var displayedRelics: [(relic: StoredRelic, matched: Bool)] {
    let pool = visibleRelics
    let matched = pool.filter(matchesChipFilters).sorted(by: sortConfig)
    let unmatched = pool.filter { !matchesChipFilters($0) }.sorted(by: sortConfig)
    return matched.map { ($0, true) } + unmatched.map { ($0, false) }
  }

  /// マッチ済み件数（件数バッジ用）。
  private var matchedCount: Int {
    visibleRelics.filter(matchesChipFilters).count
  }
}

// MARK: - FilterBar

struct FilterBar: View {
  @Binding var colorFilters: Set<RelicColor>
  @Binding var sizeFilters: Set<Int>
  @Binding var depthFilters: Set<RelicDepth>
  @Binding var effectDrilldowns: [Set<String>]
  let onTapEffectFilter: () -> Void
  /// ソートシートを開く。bind を渡さないとソートチップは非表示。
  var onTapSort: (() -> Void)? = nil
  /// 表示するチップ。ビルドのスロット用ピッカーなど、色や種別をスロット側で
  /// 固定したい場合は false にしてチップを非表示にできる。
  var showsColor: Bool = true
  var showsDepth: Bool = true
  /// お気に入りのみを表示するフィルタ。bind を渡したときだけチップを表示する。
  var favoritesOnly: Binding<Bool>? = nil

  private var effectTotalCount: Int {
    effectDrilldowns.reduce(0) { $0 + $1.count }
  }
  private var hasEffectFilter: Bool {
    effectDrilldowns.contains(where: { !$0.isEmpty })
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        // お気に入り（アイコン付きトグル）
        if let favoritesOnly {
          Button {
            favoritesOnly.wrappedValue.toggle()
          } label: {
            HStack(spacing: 4) {
              Image(systemName: favoritesOnly.wrappedValue ? "bookmark.fill" : "bookmark")
              Text("Favorites")
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
              favoritesOnly.wrappedValue ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12),
              in: Capsule()
            )
            .foregroundStyle(favoritesOnly.wrappedValue ? Color.accentColor : .primary)
          }
        }
        // 特色（色）
        if showsColor {
          MenuChip(
            title: chipTitle(
              "Characteristics",
              count: colorFilters.count,
              single: colorFilters.first.map(colorLabel)
            ),
            isActive: !colorFilters.isEmpty) {
              Toggle("Red", isOn: bind(.red, in: $colorFilters))
              Toggle("Blue", isOn: bind(.blue, in: $colorFilters))
              Toggle("Yellow", isOn: bind(.yellow, in: $colorFilters))
              Toggle("Green", isOn: bind(.green, in: $colorFilters))
              if !colorFilters.isEmpty {
                Divider()
                Button("Clear Selection", role: .destructive) { colorFilters.removeAll() }
              }
            }
        }
        // 大きさ（スロット数）
        MenuChip(title: chipTitle("Size",
                                  count: sizeFilters.count,
                                  single: sizeFilters.first.map(sizeLabel)
                                 ),
                 isActive: !sizeFilters.isEmpty) {
          Toggle("Small", isOn: bind(1, in: $sizeFilters))
          Toggle("Medium", isOn: bind(2, in: $sizeFilters))
          Toggle("Large", isOn: bind(3, in: $sizeFilters))
          if !sizeFilters.isEmpty {
            Divider()
            Button("Clear Selection", role: .destructive) { sizeFilters.removeAll() }
          }
        }
        // 種別（通常 / 深層）
        if showsDepth {
          MenuChip(title: chipTitle("Type",
                                    count: depthFilters.count,
                                    single: depthFilters.first.map(depthLabel)),
                   isActive: !depthFilters.isEmpty) {
            Toggle("Relic", isOn: bind(.normal, in: $depthFilters))
            Toggle("Depths Relic", isOn: bind(.deep, in: $depthFilters))
            if !depthFilters.isEmpty {
              Divider()
              Button("Clear Selection", role: .destructive) { depthFilters.removeAll() }
            }
          }
        }
        // 効果（3段ドリルダウン、シートを開く）
        TapChip(title: effectChipTitle, isActive: hasEffectFilter, action: onTapEffectFilter)
        // ソートチップ（onTapSort が渡されているときだけ表示）
        if let onTapSort {
          TapChip(title: String(localized: "Sort"), isActive: false, action: onTapSort)
        }
        if hasAnyFilter || hasEffectFilter {
          Button {
            colorFilters.removeAll()
            sizeFilters.removeAll()
            depthFilters.removeAll()
            effectDrilldowns = effectDrilldowns.map { _ in [] }
          } label: {
            Label("Clear", systemImage: "xmark.circle.fill")
              .labelStyle(.iconOnly)
              .padding(.horizontal, 8)
              .padding(.vertical, 6)
              .background(.red.opacity(0.15), in: Capsule())
          }
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
    }
  }

  private var hasAnyFilter: Bool {
    !colorFilters.isEmpty || !sizeFilters.isEmpty || !depthFilters.isEmpty
  }

  private var effectChipTitle: String {
    let total = effectTotalCount
    return total == 0 ? String(localized: "Effects") : String(localized: "Effects (\(total))")
  }

  /// チップに表示するタイトル。0件=カテゴリ名、1件=その値、2件以上=「カテゴリ（N）」
  /// `category` を `LocalizedStringResource` 受けにすることで String Catalog の
  /// 自動抽出対象になり、`String（localized:）` で実行時にロケール翻訳される。
  /// `single`（colorLabel/sizeLabel/depthLabel の戻り値） はすでにローカライズ済み。
  private func chipTitle(_ category: LocalizedStringResource, count: Int, single: String?) -> String {
    let cat = String(localized: category)
    switch count {
    case 0: return cat
    case 1: return single ?? cat
    default: return "\(cat) (\(count))"
    }
  }

  /// Set のメンバーシップを Binding<Bool> で表現するヘルパー（Toggle 用）
  private func bind<T: Hashable>(_ value: T, in set: Binding<Set<T>>) -> Binding<Bool> {
    Binding(
      get: { set.wrappedValue.contains(value) },
      set: { on in
        // フィルタ変更を Menu の閉じるアニメーションから完全に切り離す。
        // disablesAnimations = true にしないと、選択 → 状態変化 → 親が再レイアウト、
        // が menu dismiss アニメーション（~0.3s） と同じトランザクションに乗るため、
        // チップが旧サイズのまま停まり、Capsule の輪郭も切れて見える。
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          if on { set.wrappedValue.insert(value) }
          else { set.wrappedValue.remove(value) }
        }
      }
    )
  }

  private func colorLabel(_ c: RelicColor) -> String {
    switch c {
    case .red:
      String(localized: "Red")
    case .blue:
      String(localized: "Blue")
    case .yellow:
      String(localized: "Yellow")
    case .green:
      String(localized: "Green")
    case .unknown:
      String(localized: "Unknown")
    }
  }

  private func sizeLabel(_ n: Int) -> String {
    switch n {
    case 1:
      String(localized: "Small")
    case 2:
      String(localized: "Medium")
    case 3:
      String(localized: "Large")
    default: "?"
    }
  }

  private func depthLabel(_ d: RelicDepth) -> String {
    switch d {
    case .normal:
      String(localized: "Relic")
    case .deep:
      String(localized: "Depths Relic")
    case .unknown:
      String(localized: "Unknown")
    }
  }
}

struct MenuChip<Content: View>: View {
  let title: String
  let isActive: Bool
  @ViewBuilder var content: () -> Content

  var body: some View {
    HStack {
      Menu {
        content()
      } label: {
        HStack(spacing: 4) {
          Text(title).font(.subheadline.weight(.medium).monospacedDigit())
          Image(systemName: "chevron.down").font(.caption2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12),
                    in: Capsule())
        .foregroundStyle(isActive ? Color.accentColor : .primary)
      }
      .buttonStyle(.plain)
    }
  }
}

struct TapChip: View {
  let title: String
  let isActive: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Text(title).font(.subheadline.weight(.medium).monospacedDigit())
        Image(systemName: "chevron.right").font(.caption2)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(
        isActive ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12),
        in: Capsule()
      )
      .foregroundStyle(isActive ? Color.accentColor : .primary)
    }
  }
}

struct RelicRow: View {
  let relic: StoredRelic
  let highlight: String
  var inUse: Bool = false

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ColorBadge(color: relic.color, slotCount: relic.slotCount, depth: relic.depth)
        .frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(relic.displayName)
            .font(.headline)
            .lineLimit(1)
          if relic.isUnique {
            Text("Unique")
              .font(.caption2.weight(.bold))
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(.purple.opacity(0.18), in: Capsule())
              .foregroundStyle(.purple)
          }
          if relic.depth == .deep {
            Text("Deep")
              .font(.caption2.weight(.bold))
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(.indigo.opacity(0.18), in: Capsule())
              .foregroundStyle(.indigo)
          }
          Spacer()
          Text("◆ \(relic.slotCount)")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        if relic.effects.isEmpty {
          Text("(none)")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          let slots = relic.slotsGrouped
          ForEach(Array(slots.enumerated()), id: \.offset) { _, pair in
            VStack(alignment: .leading, spacing: 3) {
              HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Image(systemName: "circle.fill"))
                  .font(.system(size: 5))
                  .baselineOffset(3)
                  .foregroundStyle(.tertiary)
                Text(highlighted(pair.main.localizedText, query: highlight))
                  .font(.caption)
                  .multilineTextAlignment(.leading)
                  .fixedSize(horizontal: false, vertical: true)
              }
              if let demerit = pair.demerit {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                  Text(Image(systemName: "circle.fill"))
                    .font(.system(size: 5))
                    .baselineOffset(3)
                    .foregroundStyle(Color.demeritEffect)
                  Text(highlighted(demerit.localizedText, query: highlight))
                    .font(.caption2)
                    .foregroundStyle(Color.demeritEffect)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 12)
              }
            }
          }
        }
        HStack(spacing: 4) {
          Spacer()
          iconSlot(systemName: "wineglass.fill", show: inUse)
          iconSlot(systemName: "bookmark.fill", show: relic.isFavorite)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
      }
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private func iconSlot(systemName: String, show: Bool) -> some View {
    Image(systemName: systemName)
      .frame(width: 14, alignment: .trailing)
      .opacity(show ? 1 : 0)
  }

  private func highlighted(_ text: String, query: String) -> AttributedString {
    var attr = AttributedString(text)
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty,
          let range = attr.range(of: q, options: .caseInsensitive) else {
      return attr
    }
    attr[range].backgroundColor = .yellow.opacity(0.4)
    return attr
  }
}
