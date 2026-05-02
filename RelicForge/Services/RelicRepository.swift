import Foundation
import SwiftData

@MainActor
final class RelicRepository {
  private let context: ModelContext

  init(context: ModelContext) {
    self.context = context
  }

  /// 認識結果をそのまま保存するショートカット。
  @discardableResult
  func save(recognized: RecognizedRelic) -> StoredRelic {
    save(
      color: recognized.color,
      slotCount: recognized.slotCount,
      depth: recognized.depth,
      uniqueId: recognized.uniqueMatch?.relic.id,
      slots: recognized.resolvedSlots
    )
  }

  @discardableResult
  func save(
    color: RelicColor,
    slotCount: Int,
    depth: RelicDepth,
    uniqueId: String?,
    slots: [ResolvedSlot]
  ) -> StoredRelic {
    let relic = StoredRelic(
      color: color,
      slotCount: slotCount,
      depth: depth,
      uniqueId: uniqueId
    )
    context.insert(relic)

    for (slotIndex, slot) in slots.enumerated() {
      if let main = slot.main {
        let stored = StoredRelicEffect(
          effectId: main.id,
          text: main.textJa,
          category: main.category,
          slotIndex: slotIndex,
          isDemerit: false
        )
        stored.relic = relic
        context.insert(stored)
      }
      if let demerit = slot.demerit {
        let stored = StoredRelicEffect(
          effectId: demerit.id,
          text: demerit.textJa,
          category: demerit.category,
          slotIndex: slotIndex,
          isDemerit: true
        )
        stored.relic = relic
        context.insert(stored)
      }
    }

    try? context.save()
    return relic
  }

  func delete(_ relic: StoredRelic) {
    context.delete(relic)
    try? context.save()
  }
}
