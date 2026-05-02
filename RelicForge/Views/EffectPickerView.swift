import SwiftUI

/// 効果を選び直すピッカー。
/// - OCR の上位候補（元のスコア付き） を最優先で提示
/// - その下に **グループ → カテゴリ → 効果** のドリルダウン（フィルタ画面と同じ形）
/// - 検索（上部の SearchField） を入れたときだけフラット一覧になる
/// - メイン用ピッカーでは debuff カテゴリ群を除外、デメリット用では debuff のみ表示
/// - デメリット用は「デメリット無し」を選べる（`onPick（nil）`）
struct EffectPickerView: View {
  enum Mode {
    case main      // 通常効果から選ぶ（debuff 以外）
    case demerit   // デメリット効果から選ぶ（debuff のみ）
  }

  let title: LocalizedStringResource
  let ocrText: String?
  let candidates: [EffectMatch]
  let currentEffect: RelicEffect?
  let mode: Mode
  /// nil で「デメリットなし」を表現できる（mode == .demerit のみ有効）
  let allowNil: Bool
  let onPick: (RelicEffect?) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var search: String = ""

  private let allEffects: [RelicEffect] = MasterDataStore.shared.effects

  var body: some View {
    NavigationStack {
      List {
        if let ocrText, !ocrText.isEmpty {
          Section("OCR Source") {
            Text(ocrText)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }

        if mode == .demerit, allowNil {
          Section {
            Button {
              onPick(nil)
              dismiss()
            } label: {
              Label("No demerit", systemImage: "minus.circle")
                .foregroundStyle(.red)
            }
          }
        }

        if search.isEmpty {
          // OCR 高得点候補（検索中は隠す: 検索結果と二重表示を避ける）
          if !relevantCandidates.isEmpty {
            Section("OCR Top Candidates") {
              ForEach(relevantCandidates) { match in
                Button {
                  onPick(match.effect)
                  dismiss()
                } label: {
                  candidateRow(match.effect,
                               scoreSuffix: String(format: "%.0f%%", match.score * 100))
                }
                .buttonStyle(.plain)
              }
            }
          }

          // ドリルダウン（グループ毎に Section、行 = カテゴリ → タップで効果一覧へ）
          ForEach(visibleGroups) { section in
            Section(section.localizedName) {
              ForEach(section.categories) { cat in
                NavigationLink {
                  EffectPickerCategoryView(
                    category: cat,
                    effects: effects(in: cat),
                    currentEffect: currentEffect,
                    onPick: { effect in
                      onPick(effect)
                      dismiss()
                    }
                  )
                } label: {
                  Text(cat.localizedName)
                }
              }
            }
          }
        } else {
          // 検索中はフラット表示（カテゴリ横断でヒットを確認しやすいように、
          // この時だけ group/category サブテキストを残す）
          Section("Results (\(filtered.count))") {
            ForEach(filtered) { effect in
              Button {
                onPick(effect)
                dismiss()
              } label: {
                searchResultRow(effect)
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
      .listStyle(.insetGrouped)
      .searchable(text: $search, prompt: "Search effect text")
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }

  // MARK: - データ抽出

  private var relevantCandidates: [EffectMatch] {
    candidates.filter { match in
      switch mode {
      case .main:    return match.effect.category != .demerits
      case .demerit: return match.effect.category == .demerits
      }
    }
  }

  /// 表示するグループ群。
  /// debuff カテゴリ「のみ」で構成されたグループ = デメリットグループ。
  private var visibleGroups: [EffectFilterSection] {
    let sections = MasterDataStore.shared.effectFilterSections
    return sections.filter { section in
      let groupEffects = allEffects.filter { $0.groupJa == section.groupJa }
      let isDebuffGroup = !groupEffects.isEmpty
        && groupEffects.allSatisfy { $0.category == .demerits }
      switch mode {
      case .main:    return !isDebuffGroup
      case .demerit: return isDebuffGroup
      }
    }
  }

  private func effects(in cat: EffectFilterCategory) -> [RelicEffect] {
    allEffects.filter { $0.groupJa == cat.groupJa && $0.categoryJa == cat.categoryJa }
  }

  private var filtered: [RelicEffect] {
    let pool: [RelicEffect]
    switch mode {
    case .main:    pool = allEffects.filter { $0.category != .demerits }
    case .demerit: pool = allEffects.filter { $0.category == .demerits }
    }
    let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
    if q.isEmpty { return pool }
    return pool.filter {
      $0.textJa.localizedCaseInsensitiveContains(q) || $0.textEn.localizedCaseInsensitiveContains(q)
    }
  }

  // MARK: - 行

  /// OCR 候補行（% スコア付き）
  @ViewBuilder
  private func candidateRow(_ effect: RelicEffect, scoreSuffix: String?) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(effect.localizedText)
        .font(.body)
        .foregroundStyle(.primary)
      Spacer()
      if let scoreSuffix {
        Text(scoreSuffix)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      if effect.id == currentEffect?.id {
        Image(systemName: "checkmark")
          .foregroundStyle(Color.accentColor)
      }
    }
    .contentShape(Rectangle())
  }

  /// 検索結果行（group / category サブラベル付き — 横断結果で文脈を保つため）
  @ViewBuilder
  private func searchResultRow(_ effect: RelicEffect) -> some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(effect.localizedText)
          .font(.body)
          .foregroundStyle(.primary)
        Text("\(effect.localizedGroupName) / \(effect.localizedCategoryName)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if effect.id == currentEffect?.id {
        Image(systemName: "checkmark")
          .foregroundStyle(Color.accentColor)
      }
    }
    .contentShape(Rectangle())
  }
}

/// ドリルダウン 2 段目: 1 カテゴリ内の効果一覧。タップで onPick → シート閉じる。
struct EffectPickerCategoryView: View {
  let category: EffectFilterCategory
  let effects: [RelicEffect]
  let currentEffect: RelicEffect?
  let onPick: (RelicEffect) -> Void

  var body: some View {
    List {
      ForEach(effects) { effect in
        Button {
          onPick(effect)
        } label: {
          HStack {
            Text(effect.localizedText)
              .foregroundStyle(.primary)
            Spacer()
            if effect.id == currentEffect?.id {
              Image(systemName: "checkmark")
                .foregroundStyle(Color.accentColor)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .navigationTitle(category.localizedName)
    .navigationBarTitleDisplayMode(.inline)
  }
}

private extension RelicEffect {
  var localizedGroupName: String {
    Locale.current.language.languageCode?.identifier == "ja" ? groupJa : groupEn
  }
  var localizedCategoryName: String {
    Locale.current.language.languageCode?.identifier == "ja" ? categoryJa : categoryEn
  }
}
