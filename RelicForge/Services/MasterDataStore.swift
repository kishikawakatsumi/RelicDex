import Foundation

final class MasterDataStore {
  static let shared = MasterDataStore()

  let effects: [RelicEffect]
  let uniqueRelics: [UniqueRelic]
  let characters: [Nightfarer]
  let vessels: [Vessel]
  let effectFilterSections: [EffectFilterSection]
  let titleWords: TitleWordsMasterFile

  private let effectsById: [String: RelicEffect]
  private let charactersById: [String: Nightfarer]
  private let vesselsById: [String: Vessel]
  private let uniqueRelicsById: [String: UniqueRelic]

  private init() {
    let decoder = JSONDecoder()

    var effects: [RelicEffect] = []
    if let url = Bundle.main.url(forResource: "effects", withExtension: "json"),
       let data = try? Data(contentsOf: url),
       let file = try? decoder.decode(EffectsMasterFile.self, from: data) {
      effects = file.effects
    }
    self.effects = effects
    self.effectsById = Dictionary(uniqueKeysWithValues: effects.map { ($0.id, $0) })

    var uniqueRelics: [UniqueRelic] = []
    if let url = Bundle.main.url(forResource: "unique_relics", withExtension: "json"),
       let data = try? Data(contentsOf: url),
       let file = try? decoder.decode(UniqueRelicsMasterFile.self, from: data) {
      uniqueRelics = file.uniqueRelics
    }
    self.uniqueRelics = uniqueRelics
    self.uniqueRelicsById = Dictionary(uniqueKeysWithValues: uniqueRelics.map { ($0.id, $0) })

    var characters: [Nightfarer] = []
    if let url = Bundle.main.url(forResource: "characters", withExtension: "json"),
       let data = try? Data(contentsOf: url),
       let file = try? decoder.decode(CharactersMasterFile.self, from: data) {
      characters = file.characters
    }
    self.characters = characters
    self.charactersById = Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0) })

    var vessels: [Vessel] = []
    if let url = Bundle.main.url(forResource: "vessels", withExtension: "json"),
       let data = try? Data(contentsOf: url),
       let file = try? decoder.decode(VesselsMasterFile.self, from: data) {
      vessels = file.vessels
    }
    self.vessels = vessels
    self.vesselsById = Dictionary(uniqueKeysWithValues: vessels.map { ($0.id, $0) })

    self.effectFilterSections = Self.buildFilterSections(from: effects)

    // タイトル単語マスタ
    var titleWords = TitleWordsMasterFile(version: 1, sizes: [], colors: [], depths: [])
    if let url = Bundle.main.url(forResource: "title_words", withExtension: "json"),
       let data = try? Data(contentsOf: url),
       let file = try? decoder.decode(TitleWordsMasterFile.self, from: data) {
      titleWords = file
    }
    self.titleWords = titleWords
  }

  private static func buildFilterSections(from effects: [RelicEffect]) -> [EffectFilterSection] {
    var byGroup: [String: [String: [String]]] = [:]
    var groupOrder: [String] = []
    var groupCategoryOrder: [String: [String]] = [:]
    var seenBase: [String: Set<String>] = [:]
    var groupEnByJa: [String: String] = [:]
    var categoryEnByJa: [String: String] = [:]
    var baseNameEnByJa: [String: String] = [:]

    for effect in effects {
      let g = effect.groupJa
      let c = effect.categoryJa
      let base = effect.baseName

      if byGroup[g] == nil {
        byGroup[g] = [:]
        groupOrder.append(g)
        groupCategoryOrder[g] = []
      }
      if byGroup[g]?[c] == nil {
        byGroup[g]?[c] = []
        groupCategoryOrder[g]?.append(c)
      }
      let key = g + "/" + c
      if seenBase[key] == nil { seenBase[key] = [] }
      if !seenBase[key]!.contains(base) {
        seenBase[key]!.insert(base)
        byGroup[g]?[c]?.append(base)
      }
      if groupEnByJa[g] == nil { groupEnByJa[g] = effect.groupEn }
      if categoryEnByJa[key] == nil { categoryEnByJa[key] = effect.categoryEn }
      if baseNameEnByJa[base] == nil {
        baseNameEnByJa[base] = RelicEffect.stripVariantSuffix(effect.textEn)
      }
    }

    return groupOrder.compactMap { g in
      guard let categoriesInOrder = groupCategoryOrder[g], !categoriesInOrder.isEmpty else { return nil }
      let groupEn = groupEnByJa[g] ?? g
      let cats = categoriesInOrder.compactMap { c -> EffectFilterCategory? in
        guard let bases = byGroup[g]?[c], !bases.isEmpty else { return nil }
        return EffectFilterCategory(
          groupJa: g,
          groupEn: groupEn,
          categoryJa: c,
          categoryEn: categoryEnByJa["\(g)/\(c)"] ?? c,
          effects: bases.map { base in
            EffectFilterItem(baseName: base, baseNameEn: baseNameEnByJa[base] ?? base)
          }
        )
      }
      return EffectFilterSection(groupJa: g, groupEn: groupEn, categories: cats)
    }
  }

  func localizedBaseName(_ ja: String) -> String {
    if Locale.current.language.languageCode?.identifier == "ja" { return ja }
    for section in effectFilterSections {
      for cat in section.categories {
        if let item = cat.effects.first(where: { $0.baseName == ja }) {
          return item.baseNameEn
        }
      }
    }
    return ja
  }

  func effect(forId id: String) -> RelicEffect? {
    effectsById[id]
  }

  func uniqueRelic(forId id: String) -> UniqueRelic? {
    uniqueRelicsById[id]
  }

  func localizedRelicName(
    slotCount: Int,
    color: RelicColor,
    depth: RelicDepth,
    uniqueId: String? = nil
  ) -> String {
    relicName(
      slotCount: slotCount,
      color: color,
      depth: depth,
      uniqueId: uniqueId,
      forJapanese: Self.isJapanese
    )
  }

  func relicName(
    slotCount: Int,
    color: RelicColor,
    depth: RelicDepth,
    uniqueId: String? = nil,
    forJapanese: Bool
  ) -> String {
    if let uniqueId, let unique = uniqueRelicsById[uniqueId] {
      return forJapanese ? unique.nameJa : unique.nameEn
    }
    return forJapanese
      ? composeJapaneseTitle(slotCount: slotCount, color: color, depth: depth)
      : composeEnglishTitle(slotCount: slotCount, color: color, depth: depth)
  }

  private func composeJapaneseTitle(slotCount: Int, color: RelicColor, depth: RelicDepth) -> String {
    let size = titleWords.sizes.first { $0.slotCount == slotCount }?.ja ?? "?"
    let col = titleWords.colors.first { $0.color == color.rawValue }?.ja ?? "?"
    let dep = titleWords.depths.first { $0.depth == depth.rawValue }?.ja ?? "?"
    return "\(size)な\(col)\(dep)"
  }

  private func composeEnglishTitle(slotCount: Int, color: RelicColor, depth: RelicDepth) -> String {
    let size = titleWords.sizes.first { $0.slotCount == slotCount }?.en ?? "?"
    let col = titleWords.colors.first { $0.color == color.rawValue }?.en ?? "?"
    let depthEntry = titleWords.depths.first { $0.depth == depth.rawValue }
    let dep = depthEntry?.en ?? "?"
    if let prefix = depthEntry?.enPrefix, !prefix.isEmpty {
      return "\(prefix) \(size) \(col) \(dep)"
    }
    return "\(size) \(col) \(dep)"
  }

  private static var isJapanese: Bool {
    Locale.current.language.languageCode?.identifier == "ja"
  }

  func character(forId id: String) -> Nightfarer? {
    charactersById[id]
  }

  func vessel(forId id: String) -> Vessel? {
    vesselsById[id]
  }

  func vessels(forCharacter characterId: String) -> [Vessel] {
    vessels.filter { $0.availableFor(characterId: characterId) }
  }

  func resolvedEffects(for unique: UniqueRelic) -> [RelicEffect] {
    unique.effects.map { ref in
      if let id = ref.effectId, let e = effectsById[id] { return e }
      return RelicEffect(
        id: "unresolved_\(ref.textJa.hashValue)",
        textJa: ref.textJa,
        textEn: ref.textJa,
        groupJa: "Unique Relic",
        groupEn: "Unique Relic",
        categoryJa: "Unknown",
        categoryEn: "Unknown",
        category: .unknown
      )
    }
  }
}
