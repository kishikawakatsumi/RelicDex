// 遺物リストのソート設定 (iOS RelicSortOption / RelicSortConfig 相当)。

import type { ExportRelic } from "../types/export";

export type RelicSortOption = "registered" | "size" | "color";

export interface RelicSortConfig {
  option: RelicSortOption;
  ascending: boolean;
}

export const defaultSortConfig: RelicSortConfig = {
  option: "registered",
  ascending: false,  // 登録順は新しい→古いをデフォルト
};

/// 並び替え用の色順序: 赤 → 青 → 黄 → 緑 → unknown (ユーザ指定)。
export function colorSortIndex(color: string): number {
  switch (color) {
    case "red": return 0;
    case "blue": return 1;
    case "yellow": return 2;
    case "green": return 3;
    default: return 4;
  }
}

export function sortRelics<T extends ExportRelic>(
  list: readonly T[],
  config: RelicSortConfig,
): T[] {
  const asc = config.ascending;
  const arr = [...list];
  switch (config.option) {
    case "registered":
      return arr.sort((a, b) =>
        asc
          ? a.capturedAt.localeCompare(b.capturedAt)
          : b.capturedAt.localeCompare(a.capturedAt),
      );
    case "size":
      // 同じサイズ内は登録の新しい順
      return arr.sort((a, b) => {
        if (a.slotCount !== b.slotCount) {
          return asc ? a.slotCount - b.slotCount : b.slotCount - a.slotCount;
        }
        return b.capturedAt.localeCompare(a.capturedAt);
      });
    case "color":
      return arr.sort((a, b) => {
        const ai = colorSortIndex(a.color);
        const bi = colorSortIndex(b.color);
        if (ai !== bi) return asc ? ai - bi : bi - ai;
        return b.capturedAt.localeCompare(a.capturedAt);
      });
  }
}

export function sortLabel(option: RelicSortOption): string {
  switch (option) {
    case "registered": return "登録順";
    case "size":       return "大きさ順";
    case "color":      return "色順";
  }
}
