// `.relicforge` ファイル (zlib raw deflate 圧縮 JSON) のスキーマ。
// iOS 側の `RelicExportService.swift` の ExportPayload と完全に対応。
// schemaVersion 1 (未リリース固定)。

export interface ExportPayload {
  schemaVersion: number;
  exportedAt: string;        // ISO8601
  appVersion: string;
  relics: ExportRelic[];
  builds: ExportBuild[];
}

export interface ExportRelic {
  id: string;                // UUID
  color: string;             // RelicColor.rawValue
  slotCount: number;
  depth: string;             // RelicDepth.rawValue
  uniqueId?: string;         // 省略時は undefined
  isFavorite?: boolean;      // 省略時は false 扱い
  capturedAt: string;        // ISO8601
  effects: ExportEffect[];
}

export interface ExportEffect {
  effectId: string;
  slotIndex: number;
  isDemerit?: boolean;       // 省略時は false 扱い
}

export interface ExportBuild {
  id: string;                // UUID
  name: string;
  characterId: string;
  vesselId?: string;         // 省略時は undefined
  normalSlotRelicIds: (string | null)[];  // length 3
  deepSlotRelicIds: (string | null)[];    // length 3
  createdAt: string;         // ISO8601
  updatedAt: string;
}
