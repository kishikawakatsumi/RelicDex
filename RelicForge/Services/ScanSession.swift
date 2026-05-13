import Foundation
import SwiftUI
internal import Combine

/// ライブスキャン中に蓄積する候補。確定 = 自動追加でこのリストに乗る。
/// ユーザーは後から一覧で確認 / 不要なものを除外 / 効果を選び直して、
/// まとめて永続化する。
struct ScanCandidate: Identifiable {
  let id: UUID
  let recognized: RecognizedRelic
  let addedAt: Date
  /// 一覧での「保存対象」フラグ。デフォルトは true。
  var isSelected: Bool
  /// ユーザーがOCR結果を上書きするための編集状態。
  /// 初期値は `RecognizedRelic.resolvedSlots` の通り。
  var edits: CandidateEdits

  // タイトル属性 (size/color/depth/unique) の override。
  // OCR が誤認識した場合、ユーザーがスキャン候補画面の Menu で直接修正できる。
  // recognized は immutable のまま残し、保存時はこちらの値を使う。
  var color: RelicColor
  var slotCount: Int
  var depth: RelicDepth
  var uniqueId: String?

  init(recognized: RecognizedRelic) {
    self.id = UUID()
    self.recognized = recognized
    self.addedAt = .now
    self.isSelected = true
    self.color = recognized.color
    // recognized.slotCount が 0 (= parse 失敗) のときは安全策で 2 (端正) を default
    let initSlot = max(1, min(3, recognized.slotCount == 0 ? 2 : recognized.slotCount))
    self.slotCount = initSlot
    self.depth = recognized.depth == .unknown ? .normal : recognized.depth
    self.uniqueId = recognized.uniqueMatch?.relic.id
    var e = CandidateEdits(from: recognized)
    e.resize(to: initSlot)
    self.edits = e
  }

  /// 編集を反映した最終的なスロット配列（保存・表示時に使う）。
  /// `slotCount` 上書きが反映されるよう、表示時は先頭 `slotCount` 件に絞る。
  var finalSlots: [ResolvedSlot] {
    Array(edits.apply().prefix(slotCount))
  }

  /// override 値から組み立てた title。スキャン元の言語で表示する。
  var displayName: String {
    let ja = recognized.isJapaneseScan
    return MasterDataStore.shared.relicName(
      slotCount: slotCount, color: color, depth: depth,
      uniqueId: uniqueId, forJapanese: ja
    )
  }
}

/// 候補内の各スロットの上書き内容。
struct CandidateEdits: Equatable {
  /// スロットごとのメイン効果（length = スロット数）。nil は「効果なし」。
  var mains: [RelicEffect?]
  /// スロットごとのデメリット効果（length = スロット数）。nil = デメリット無し。
  var demerits: [RelicEffect?]

  init(from recognized: RecognizedRelic) {
    let resolved = recognized.resolvedSlots
    self.mains = resolved.map { $0.main }
    self.demerits = resolved.map { $0.demerit }
  }

  /// `n` 件分にサイズを揃える (不足は nil で埋め、過剰は末尾を切り捨て)。
  /// OCR で検出された効果数と title の slotCount が食い違ったまま編集画面に
  /// 入ると「N 番目のスロットを編集しても保存先が存在せず無視される」現象が
  /// 起きるので、init 直後 / slotCount 変更後に必ずこれを呼ぶ。
  mutating func resize(to n: Int) {
    while mains.count < n { mains.append(nil) }
    while mains.count > n { mains.removeLast() }
    while demerits.count < n { demerits.append(nil) }
    while demerits.count > n { demerits.removeLast() }
  }

  func apply() -> [ResolvedSlot] {
    let n = max(mains.count, demerits.count)
    return (0..<n).map { i in
      ResolvedSlot(
        main: i < mains.count ? mains[i] : nil,
        demerit: i < demerits.count ? demerits[i] : nil
      )
    }
  }
}

@MainActor
final class ScanSession: ObservableObject {
  @Published var candidates: [ScanCandidate] = []

  var selectedCount: Int { candidates.filter { $0.isSelected }.count }
  var count: Int { candidates.count }

  func add(_ recognized: RecognizedRelic) {
    candidates.append(ScanCandidate(recognized: recognized))
  }

  func remove(id: UUID) {
    candidates.removeAll { $0.id == id }
  }

  func setSelected(_ selected: Bool, id: UUID) {
    if let i = candidates.firstIndex(where: { $0.id == id }) {
      candidates[i].isSelected = selected
    }
  }

  func selectAll(_ selected: Bool) {
    for i in candidates.indices { candidates[i].isSelected = selected }
  }

  func clear() {
    candidates.removeAll()
  }

  /// 選択中の候補だけをリポジトリに保存。編集された効果を反映する。
  @discardableResult
  func commitSelected(to repository: RelicRepository) -> Int {
    let toSave = candidates.filter { $0.isSelected }
    for c in toSave {
      // override 値を優先 (recognized ではなく)。OCR 誤認識をユーザーが
      // 修正していた場合、その結果が保存される。
      repository.save(
        color: c.color,
        slotCount: c.slotCount,
        depth: c.depth,
        uniqueId: c.uniqueId,
        slots: c.finalSlots
      )
    }
    candidates.removeAll { c in toSave.contains(where: { $0.id == c.id }) }
    return toSave.count
  }
}
