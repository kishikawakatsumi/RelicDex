import Foundation

@MainActor
enum RelicExportService {
  static let fileExtension = "relicforge"
  static let schemaVersion = 1

  static func writeExportFile(relics: [StoredRelic], builds: [StoredBuild]) throws -> URL {
    let compressed = try makeExportData(relics: relics, builds: builds)
    let stamp = Self.filenameStamp(from: Date())
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("RelicForge-\(stamp).\(Self.fileExtension)")
    try compressed.write(to: url, options: .atomic)
    return url
  }

  static func makeExportData(relics: [StoredRelic], builds: [StoredBuild]) throws -> Data {
    let payload = ExportPayload(
      schemaVersion: Self.schemaVersion,
      exportedAt: Date(),
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
      relics: relics.map(ExportRelic.init(from:)),
      builds: builds.map(ExportBuild.init(from:))
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let json = try encoder.encode(payload)
    return try (json as NSData).compressed(using: .zlib) as Data
  }

  private static func filenameStamp(from date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "yyyyMMdd-HHmmss"
    return f.string(from: date)
  }
}

struct ExportPayload: Codable {
  let schemaVersion: Int
  let exportedAt: Date
  let appVersion: String
  let relics: [ExportRelic]
  let builds: [ExportBuild]
}

struct ExportRelic: Codable {
  let id: UUID
  let color: String
  let slotCount: Int
  let depth: String
  let uniqueId: String?
  let isFavorite: Bool?
  let capturedAt: Date
  let effects: [ExportEffect]

  enum CodingKeys: String, CodingKey {
    case id, color, slotCount, depth, uniqueId, isFavorite, capturedAt, effects
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(color, forKey: .color)
    try c.encode(slotCount, forKey: .slotCount)
    try c.encode(depth, forKey: .depth)
    try c.encodeIfPresent(uniqueId, forKey: .uniqueId)
    try c.encodeIfPresent(isFavorite, forKey: .isFavorite)
    try c.encode(capturedAt, forKey: .capturedAt)
    try c.encode(effects, forKey: .effects)
  }
}

struct ExportEffect: Codable {
  let effectId: String
  let slotIndex: Int
  let isDemerit: Bool?

  enum CodingKeys: String, CodingKey {
    case effectId, slotIndex, isDemerit
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(effectId, forKey: .effectId)
    try c.encode(slotIndex, forKey: .slotIndex)
    try c.encodeIfPresent(isDemerit, forKey: .isDemerit)
  }
}

struct ExportBuild: Codable {
  let id: UUID
  let name: String
  let characterId: String
  let vesselId: String?
  let normalSlotRelicIds: [UUID?]
  let deepSlotRelicIds: [UUID?]
  let createdAt: Date
  let updatedAt: Date

  enum CodingKeys: String, CodingKey {
    case id, name, characterId, vesselId, normalSlotRelicIds, deepSlotRelicIds, createdAt, updatedAt
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(name, forKey: .name)
    try c.encode(characterId, forKey: .characterId)
    try c.encodeIfPresent(vesselId, forKey: .vesselId)
    try c.encode(normalSlotRelicIds, forKey: .normalSlotRelicIds)
    try c.encode(deepSlotRelicIds, forKey: .deepSlotRelicIds)
    try c.encode(createdAt, forKey: .createdAt)
    try c.encode(updatedAt, forKey: .updatedAt)
  }
}

extension ExportRelic {
  init(from r: StoredRelic) {
    self.id = r.id
    self.color = r.colorRaw
    self.slotCount = r.slotCount
    self.depth = r.depthRaw
    self.uniqueId = r.uniqueId
    self.isFavorite = r.isFavorite ? true : nil
    self.capturedAt = r.capturedAt
    self.effects = r.effects
      .sorted { ($0.slotIndex, $0.isDemerit ? 1 : 0) < ($1.slotIndex, $1.isDemerit ? 1 : 0) }
      .map { e in
        ExportEffect(
          effectId: e.effectId,
          slotIndex: e.slotIndex,
          isDemerit: e.isDemerit ? true : nil
        )
      }
  }
}

extension ExportBuild {
  init(from b: StoredBuild) {
    self.id = b.id
    self.name = b.name
    self.characterId = b.characterId
    self.vesselId = b.vesselId
    self.normalSlotRelicIds = b.normalSlotRelicIds
    self.deepSlotRelicIds = b.deepSlotRelicIds
    self.createdAt = b.createdAt
    self.updatedAt = b.updatedAt
  }
}
