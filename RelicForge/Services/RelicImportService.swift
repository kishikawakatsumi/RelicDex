import Foundation
import SwiftData

@MainActor
enum RelicImportService {
  enum ImportError: LocalizedError {
    case invalidURL
    case fetchFailed(Int)
    case decompressionFailed
    case decodeFailed
    case unsupportedSchema(Int)

    var errorDescription: String? {
      switch self {
      case .invalidURL:
        String(localized: "Failed to parse URL")
      case .fetchFailed(let s):
        String(localized: "Fetch failed (HTTP \(s))")
      case .decompressionFailed:
        String(localized: "Failed to decompress data")
      case .decodeFailed:
        String(localized: "Failed to parse data")
      case .unsupportedSchema(let v):
        String(localized: "Unsupported schema version (\(v))")
      }
    }
  }

  static func fetch(from input: String) async throws -> ExportPayload {
    let key = try extractKey(from: input)
    let apiURL = RelicShareService.baseURL.appendingPathComponent("api/share/\(key)")

    let (data, response) = try await URLSession.shared.data(from: apiURL)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200...299).contains(status) else {
      throw ImportError.fetchFailed(status)
    }
    return try decode(compressed: data)
  }

  static func loadFile(at fileURL: URL) throws -> ExportPayload {
    let data = try Data(contentsOf: fileURL)
    return try decode(compressed: data)
  }

  private static func decode(compressed data: Data) throws -> ExportPayload {
    guard let decompressed = try? (data as NSData).decompressed(using: .zlib) as Data else {
      throw ImportError.decompressionFailed
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let payload: ExportPayload
    do {
      payload = try decoder.decode(ExportPayload.self, from: decompressed)
    } catch {
      throw ImportError.decodeFailed
    }
    guard payload.schemaVersion == RelicExportService.schemaVersion else {
      throw ImportError.unsupportedSchema(payload.schemaVersion)
    }
    return payload
  }

  static func extractKey(from input: String) throws -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    // /s/{key} 形式
    if let url = URL(string: trimmed), url.pathComponents.count >= 2 {
      let parts = url.pathComponents
      if let i = parts.firstIndex(of: "s"), i + 1 < parts.count {
        let candidate = parts[i + 1]
        if candidate.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil {
          return candidate
        }
      }
    }

    if trimmed.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil {
      return trimmed
    }
    throw ImportError.invalidURL
  }

  static func replaceAll(with payload: ExportPayload, in context: ModelContext) throws {
    let master = MasterDataStore.shared

    try context.delete(model: StoredRelic.self)
    try context.delete(model: StoredRelicEffect.self)
    try context.delete(model: StoredBuild.self)

    for r in payload.relics {
      let color = RelicColor(rawValue: r.color) ?? .unknown
      let depth = RelicDepth(rawValue: r.depth) ?? .unknown
      let stored = StoredRelic(
        id: r.id,
        color: color,
        slotCount: r.slotCount,
        depth: depth,
        uniqueId: r.uniqueId,
        capturedAt: r.capturedAt,
        isFavorite: r.isFavorite ?? false
      )
      context.insert(stored)
      for e in r.effects {
        let masterEffect = master.effect(forId: e.effectId)
        let storedEffect = StoredRelicEffect(
          effectId: e.effectId,
          text: masterEffect?.textJa ?? "",
          category: masterEffect?.category ?? .unknown,
          slotIndex: e.slotIndex,
          isDemerit: e.isDemerit ?? false
        )
        storedEffect.relic = stored
        context.insert(storedEffect)
      }
    }

    for b in payload.builds {
      let build = StoredBuild(
        id: b.id,
        name: b.name,
        characterId: b.characterId,
        vesselId: b.vesselId,
        createdAt: b.createdAt,
        updatedAt: b.updatedAt
      )
      build.normalSlot1RelicId = b.normalSlotRelicIds.indices.contains(0) ? b.normalSlotRelicIds[0] : nil
      build.normalSlot2RelicId = b.normalSlotRelicIds.indices.contains(1) ? b.normalSlotRelicIds[1] : nil
      build.normalSlot3RelicId = b.normalSlotRelicIds.indices.contains(2) ? b.normalSlotRelicIds[2] : nil
      build.deepSlot1RelicId = b.deepSlotRelicIds.indices.contains(0) ? b.deepSlotRelicIds[0] : nil
      build.deepSlot2RelicId = b.deepSlotRelicIds.indices.contains(1) ? b.deepSlotRelicIds[1] : nil
      build.deepSlot3RelicId = b.deepSlotRelicIds.indices.contains(2) ? b.deepSlotRelicIds[2] : nil
      context.insert(build)
    }

    try context.save()
  }
}
