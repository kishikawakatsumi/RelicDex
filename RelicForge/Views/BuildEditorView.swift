import SwiftUI
import SwiftData

/// ビルド編集（Layout A: 縦スクロール）。
/// キャラ名 → 名前入力 → 器選択 → 通常スロット3 → 深層スロット3 → 効果サマリ
struct BuildEditorView: View {
  @Bindable var build: StoredBuild
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss

  @Query private var allRelics: [StoredRelic]

  @State private var showingVesselPicker = false
  @State private var pickingSlot: SlotPickerTarget?
  @State private var showingDeleteConfirm = false

  // ビルド全体で共有するスロットピッカー用フィルタ。
  // スロットを跨いでも前回の絞り込みが維持され、目的の遺物群を順次スロットに
  // 入れていく流れに馴染む。
  @State private var slotSizeFilters: Set<Int> = []
  @State private var slotEffectDrilldowns: [Set<String>] = [[], [], []]
  @State private var slotFavoritesOnly = false

  private let master = MasterDataStore.shared

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        characterHeader
        nameField
        vesselSection
        slotsSection(kind: .normal, title: "Relic")
        slotsSection(kind: .deep,   title: "Depth Relic")
        effectSummarySection
      }
      .padding()
    }
    .navigationTitle(displayName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button(role: .destructive) {
            showingDeleteConfirm = true
          } label: {
            Label("Delete", systemImage: "trash")
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
    .alert("Delete this build?", isPresented: $showingDeleteConfirm) {
      Button("Delete", role: .destructive) {
        modelContext.delete(build)
        try? modelContext.save()
        dismiss()
      }
      Button("Cancel", role: .cancel) {}
    }
    .sheet(isPresented: $showingVesselPicker) {
      VesselPickerView(
        characterId: build.characterId,
        currentVesselId: build.vesselId,
        onSelect: { v in
          build.vesselId = v?.id
          build.updatedAt = .now
          try? modelContext.save()
        }
      )
    }
    .sheet(item: $pickingSlot) { target in
      let vessel = build.vesselId.flatMap { master.vessel(forId: $0) }
      let normalColors = vessel?.baseSlots ?? Array(repeating: .white, count: 3)
      let deepColors = vessel?.deepSlots ?? Array(repeating: .white, count: 3)
      BuildRelicPickerView(
        slotColor: target.color,
        slotKind: target.kind,
        normalSlotColors: normalColors,
        deepSlotColors: deepColors,
        slotIndex: target.index,
        currentRelicId: build.relicId(slotKind: target.kind, index: target.index),
        allRelics: allRelics,
        otherEquippedIds: equippedRelicIdsExcluding(target),
        sizeFilters: $slotSizeFilters,
        effectDrilldowns: $slotEffectDrilldowns,
        favoritesOnly: $slotFavoritesOnly,
        onSelect: { relic in
          // 親の `.onDisappear` で save（） するので、ここでは即時 save しない
          // （毎タップごとに SwiftData の save を走らせるとシート閉じが詰まる）。
          build.setRelicId(relic?.id, slotKind: target.kind, index: target.index)
        }
      )
    }
    .onDisappear {
      try? modelContext.save()
    }
  }

  private var displayName: String {
    build.name.isEmpty ? "Untitled" : build.name
  }

  private var characterHeader: some View {
    HStack(spacing: 8) {
      Image(systemName: "person.fill")
        .foregroundStyle(.secondary)
      if let c = master.character(forId: build.characterId) {
        Text(c.localizedName)
          .font(.title3.weight(.semibold))
      } else {
        Text(build.characterId)
          .font(.title3.weight(.semibold))
      }
    }
  }

  private var nameField: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Build Name").font(.caption).foregroundStyle(.secondary)
      TextField("Untitled", text: $build.name)
        .textFieldStyle(.roundedBorder)
        .onChange(of: build.name) { _, _ in
          build.updatedAt = .now
        }
    }
  }

  // MARK: - 器セクション

  private var vesselSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Vessel").font(.caption).foregroundStyle(.secondary)
      Button {
        showingVesselPicker = true
      } label: {
        HStack {
          if let vid = build.vesselId, let v = master.vessel(forId: vid) {
            VStack(alignment: .leading, spacing: 4) {
              Text(v.localizedName)
                .font(.body)
                .foregroundStyle(.primary)
              // 通常 ●●● と深層 ●●● を少し空けて並べる（文字ラベル無し）
              HStack(spacing: 14) {
                slotColorRow(v.baseSlots)
                slotColorRow(v.deepSlots)
              }
            }
          } else {
            Text("Select Vessel")
              .foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding()
        .background(Color.gray.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
      }
      .buttonStyle(.plain)
    }
  }

  private func slotColorRow(_ colors: [VesselSlotColor]) -> some View {
    HStack(spacing: 3) {
      ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
        Circle().fill(c.swatch).frame(width: 10, height: 10)
          .overlay(Circle().stroke(.secondary.opacity(0.4), lineWidth: 0.5))
      }
    }
  }

  // MARK: - スロットセクション

  private func slotsSection(kind: BuildSlotKind, title: LocalizedStringResource) -> some View {
    let vessel = build.vesselId.flatMap { master.vessel(forId: $0) }
    let colors: [VesselSlotColor] = vessel.map { kind == .normal ? $0.baseSlots : $0.deepSlots }
                                          ?? Array(repeating: .white, count: 3)
    return VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      VStack(spacing: 8) {
        ForEach(0..<3, id: \.self) { i in
          slotRow(kind: kind, index: i, color: colors[safe: i] ?? .white,
                  vesselSelected: vessel != nil)
        }
      }
    }
  }

  private func slotRow(kind: BuildSlotKind, index: Int, color: VesselSlotColor,
                       vesselSelected: Bool) -> some View {
    let relicId = build.relicId(slotKind: kind, index: index)
    let relic = relicId.flatMap { id in allRelics.first(where: { $0.id == id }) }
    let mismatch = relic.flatMap { mismatchReason(for: $0, slotColor: color, slotKind: kind) }
    return Button {
      pickingSlot = SlotPickerTarget(kind: kind, index: index, color: color)
    } label: {
      HStack(spacing: 12) {
        Circle().fill(color.swatch).frame(width: 16, height: 16)
          .overlay(Circle().stroke(.secondary.opacity(0.5), lineWidth: 0.5))
        if let relic {
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
              // 色違い・深層用・通常用のバッジは出さず、グレー化だけで装着不可を伝える。
              Text(relic.displayName).font(.body).foregroundStyle(.primary).lineLimit(1)
            }
            if !relic.effects.isEmpty {
              Text(relicEffectsSummary(relic))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
          }
          .opacity(mismatch != nil ? 0.5 : 1.0)
        } else {
          Text("Empty").foregroundStyle(.secondary)
        }
        Spacer()
        if relic != nil {
          Button {
            build.setRelicId(nil, slotKind: kind, index: index)
            try? modelContext.save()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.tertiary)
          }
          .buttonStyle(.plain)
        }
        Image(systemName: "chevron.right")
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 12).padding(.vertical, 10)
      .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
      .opacity(vesselSelected ? 1.0 : 0.5)
    }
    .disabled(!vesselSelected)
    .buttonStyle(.plain)
  }

  /// スロット色 / 種別と装備中遺物のミスマッチ理由（BuildRelicPickerView と同じ表記）。
  /// 器変更などでスロット色が変わったときに、不整合になった遺物を表示する。
  /// 装着不可かどうかを内部識別子で返す（装着可能なら nil）。
  /// 文字列は disable / opacity / 集計除外判定の `!= nil` チェックにだけ使い、
  /// バッジには出さない（ユーザの指示で色違い・深層用・通常用バッジは非表示）。
  private func mismatchReason(for relic: StoredRelic, slotColor: VesselSlotColor,
                              slotKind: BuildSlotKind) -> String? {
    if !slotColor.accepts(relic.color) { return "color-mismatch" }
    switch slotKind {
    case .normal: if relic.depth == .deep { return "deep-only" }
    case .deep:   if relic.depth != .deep { return "normal-only" }
    }
    return nil
  }

  private func relicEffectsSummary(_ relic: StoredRelic) -> String {
    relic.slotsGrouped.compactMap { $0.main.localizedText }.joined(separator: " / ")
  }

  // MARK: - 効果サマリ

  private var effectSummarySection: some View {
    let groups = aggregatedEffectGroups()
    return VStack(alignment: .leading, spacing: 8) {
      Text("Relic Effect").font(.caption).foregroundStyle(.secondary)
      if groups.isEmpty {
        Text("No effects equipped yet.")
          .font(.caption)
          .foregroundStyle(.tertiary)
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(groups.enumerated()), id: \.offset) { idx, group in
            if idx > 0 {
              Divider().padding(.vertical, 8)
            }
            // Collection や RelicPicker と同じパターン: メイン効果は通常表示、
            // デメリット効果は **smaller font + 12pt 左インデント** で 1 段下げる。
            VStack(alignment: .leading, spacing: 4) {
              ForEach(Array(group.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                  Text(Image(systemName: "circle.fill"))
                    .font(.system(size: 5))
                    .baselineOffset(3)
                    .foregroundStyle(line.isDemerit ? Color.demeritEffect : Color.gray.opacity(0.5))
                  Text(line.text)
                    .font(line.isDemerit ? .caption2 : .caption)
                    .foregroundStyle(line.isDemerit ? Color.demeritEffect : .primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, line.isDemerit ? 12 : 0)
              }
            }
          }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
      }
    }
  }

  /// 各 relic の効果群を 1 グループとしてまとめて返す（デメリット含む）。
  /// 器のスロット色 / 種別と合わない遺物（= 装備不可状態） はサマリから除外する。
  /// View 側でグループの間に Divider を挟んで遺物境界を視覚化するため、
  /// `aggregatedEffectLines（）` のフラット配列ではなく入れ子配列で返す。
  private func aggregatedEffectGroups() -> [[(text: String, isDemerit: Bool)]] {
    let vessel = build.vesselId.flatMap { master.vessel(forId: $0) }
    var groups: [[(String, Bool)]] = []
    func appendGroup(relicId: UUID?, slotColor: VesselSlotColor, kind: BuildSlotKind) {
      guard let rid = relicId,
            let relic = allRelics.first(where: { $0.id == rid }) else { return }
      if mismatchReason(for: relic, slotColor: slotColor, slotKind: kind) != nil { return }
      var group: [(String, Bool)] = []
      for pair in relic.slotsGrouped {
        group.append((pair.main.localizedText, false))
        if let d = pair.demerit { group.append((d.localizedText, true)) }
      }
      if !group.isEmpty { groups.append(group) }
    }
    let normalColors = vessel?.baseSlots ?? Array(repeating: .white, count: 3)
    let deepColors = vessel?.deepSlots ?? Array(repeating: .white, count: 3)
    for (i, rid) in build.normalSlotRelicIds.enumerated() {
      appendGroup(relicId: rid, slotColor: normalColors[safe: i] ?? .white, kind: .normal)
    }
    for (i, rid) in build.deepSlotRelicIds.enumerated() {
      appendGroup(relicId: rid, slotColor: deepColors[safe: i] ?? .white, kind: .deep)
    }
    return groups
  }

  private func equippedRelicIdsExcluding(_ target: SlotPickerTarget) -> Set<UUID> {
    var ids = Set<UUID>()
    for (i, rid) in build.normalSlotRelicIds.enumerated() {
      if let rid, !(target.kind == .normal && target.index == i) { ids.insert(rid) }
    }
    for (i, rid) in build.deepSlotRelicIds.enumerated() {
      if let rid, !(target.kind == .deep && target.index == i) { ids.insert(rid) }
    }
    return ids
  }
}

private struct SlotPickerTarget: Identifiable {
  let kind: BuildSlotKind
  let index: Int
  let color: VesselSlotColor
  var id: String { "\(kind == .normal ? "n" : "d")_\(index)" }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
