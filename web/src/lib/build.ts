// ビルド編集用のヘルパー (iOS 側 BuildEditorView / BuildRelicPickerView と同等のロジック)。

import type { MasterData } from "./loadMaster";
import type { ExportBuild, ExportRelic } from "../types/export";
import type { Vessel, VesselSlotColor } from "../types/master";
import type { Lang } from "./i18n";

export type SlotKind = "normal" | "deep";

/// 器スロット色は遺物色を受け入れるか (white = wildcard)
export function vesselSlotAcceptsRelicColor(
  slotColor: VesselSlotColor,
  relicColor: string,
): boolean {
  if (slotColor === "white") return true;
  return slotColor === relicColor;
}

/// スロットに装着できない理由 (色違い / 種別違い / 他スロット装備中)。装着可能なら null。
/// 戻り値は内部識別子であり、UI 表示用の文言ではない (iOS と揃え)。
/// 表示は `isEquippedElsewhere(_:)` 経由で「装備中 / Equipped」のみ出し、
/// 色違い・深層用・通常用は dim (opacity 低下) だけで伝える。
/// 固有遺物は iOS 保存時点で `depth = "normal"` に正規化されているので
/// 特別扱い不要。
export function mismatchReason(
  relic: ExportRelic,
  slotColor: VesselSlotColor,
  slotKind: SlotKind,
  otherEquippedIds: Set<string>,
  currentRelicId: string | null,
): "equipped-elsewhere" | "color-mismatch" | "deep-only" | "normal-only" | null {
  if (otherEquippedIds.has(relic.id) && relic.id !== currentRelicId) {
    return "equipped-elsewhere";
  }
  if (!vesselSlotAcceptsRelicColor(slotColor, relic.color)) {
    return "color-mismatch";
  }
  if (slotKind === "normal" && relic.depth === "deep") return "deep-only";
  if (slotKind === "deep" && relic.depth !== "deep") return "normal-only";
  return null;
}

/// 同じビルドの他スロットに装備済みか。バッジ「装備中 / Equipped」表示判定はこちらだけで行う。
export function isEquippedElsewhere(
  relic: ExportRelic,
  otherEquippedIds: Set<string>,
  currentRelicId: string | null,
): boolean {
  return otherEquippedIds.has(relic.id) && relic.id !== currentRelicId;
}

/// 指定キャラに使える器: 共通 + キャラ専用。表示順は専用 → 共通。
export function vesselsForCharacter(
  characterId: string,
  master: MasterData,
): { generic: Vessel[]; character: Vessel[] } {
  const generic: Vessel[] = [];
  const character: Vessel[] = [];
  for (const v of master.vessels) {
    if (v.characterId == null) generic.push(v);
    else if (v.characterId === characterId) character.push(v);
  }
  return { generic, character };
}

/// ビルドの装備中遺物 ID 集合 (除外スロット指定可)
export function equippedRelicIdsExcluding(
  build: ExportBuild,
  exclude?: { kind: SlotKind; index: number },
): Set<string> {
  const ids = new Set<string>();
  build.normalSlotRelicIds.forEach((rid, i) => {
    if (rid && !(exclude?.kind === "normal" && exclude.index === i)) {
      ids.add(rid);
    }
  });
  build.deepSlotRelicIds.forEach((rid, i) => {
    if (rid && !(exclude?.kind === "deep" && exclude.index === i)) {
      ids.add(rid);
    }
  });
  return ids;
}

export function setSlotRelicId(
  build: ExportBuild,
  kind: SlotKind,
  index: number,
  relicId: string | null,
): ExportBuild {
  const key = kind === "normal" ? "normalSlotRelicIds" : "deepSlotRelicIds";
  const next = [...build[key]];
  next[index] = relicId;
  return { ...build, [key]: next, updatedAt: new Date().toISOString() };
}

/// 効果のベース名 (+N サフィックスを除去) — フィルタ用
export function effectBaseName(text: string): string {
  return text.replace(/[＋+][０-９0-9]+$/u, "");
}

export interface EffectFilterCategory {
  categoryJa: string;
  categoryEn: string;
  baseNames: string[];
}

export interface EffectFilterSection {
  groupJa: string;
  groupEn: string;
  categories: EffectFilterCategory[];
}

/// マスタ効果から `groupJa → categoryJa → baseName` の階層構造を作る。
/// 並び順は元 TSV (= master.effects 配列) の出現順を保持し、ベース名で重複排除する。
/// iOS 側 MasterDataStore.buildFilterSections と同じロジック。
export function buildEffectFilterSections(master: MasterData): EffectFilterSection[] {
  const groupOrder: string[] = [];
  const groupEnByJa = new Map<string, string>();
  const categoryOrder = new Map<string, string[]>();        // group -> [category]
  const categoryEnByJa = new Map<string, string>();          // categoryJa -> categoryEn
  const baseNameOrder = new Map<string, string[]>();         // "group/category" -> [baseName]
  const seen = new Map<string, Set<string>>();               // "group/category" -> seen baseNames

  for (const e of master.effects) {
    const g = e.groupJa;
    const c = e.categoryJa;
    const base = effectBaseName(e.textJa);
    if (!categoryOrder.has(g)) {
      groupOrder.push(g);
      categoryOrder.set(g, []);
      groupEnByJa.set(g, e.groupEn);
    }
    const cats = categoryOrder.get(g)!;
    if (!cats.includes(c)) {
      cats.push(c);
      categoryEnByJa.set(c, e.categoryEn);
    }
    const key = `${g}/${c}`;
    if (!seen.has(key)) {
      seen.set(key, new Set());
      baseNameOrder.set(key, []);
    }
    const seenSet = seen.get(key)!;
    if (!seenSet.has(base)) {
      seenSet.add(base);
      baseNameOrder.get(key)!.push(base);
    }
  }
  return groupOrder.map((g) => ({
    groupJa: g,
    groupEn: groupEnByJa.get(g) ?? g,
    categories: (categoryOrder.get(g) ?? []).map((c) => ({
      categoryJa: c,
      categoryEn: categoryEnByJa.get(c) ?? c,
      baseNames: baseNameOrder.get(`${g}/${c}`) ?? [],
    })),
  }));
}

/// 6 スロットの効果を **遺物ごとに** グループ化して集計 (色/種別不一致は除外)。
/// iOS の `aggregatedEffectGroups()` と同形: `[[{text, isDemerit}]]`。
/// グループ間に divider を入れ、デメリット行はインデントして表示する用途。
export function aggregatedEffectGroups(
  build: ExportBuild,
  master: MasterData,
  relicById: Map<string, ExportRelic>,
  lang: Lang,
): { text: string; isDemerit: boolean }[][] {
  const vessel = build.vesselId ? master.vesselsById.get(build.vesselId) : null;
  const normalColors = vessel?.baseSlots ?? (["white", "white", "white"] as VesselSlotColor[]);
  const deepColors = vessel?.deepSlots ?? (["white", "white", "white"] as VesselSlotColor[]);
  const groups: { text: string; isDemerit: boolean }[][] = [];
  const appendRelic = (rid: string | null, slotColor: VesselSlotColor, kind: SlotKind) => {
    if (!rid) return;
    const relic = relicById.get(rid);
    if (!relic) return;
    if (mismatchReason(relic, slotColor, kind, new Set(), relic.id) != null) return;
    const lines: { text: string; isDemerit: boolean }[] = [];
    for (const e of relic.effects) {
      const eff = master.effectsById.get(e.effectId);
      if (eff) {
        const text = lang === "ja" ? eff.textJa : eff.textEn;
        lines.push({ text, isDemerit: !!e.isDemerit });
      }
    }
    if (lines.length > 0) groups.push(lines);
  };
  build.normalSlotRelicIds.forEach((rid, i) => appendRelic(rid, normalColors[i] ?? "white", "normal"));
  build.deepSlotRelicIds.forEach((rid, i) => appendRelic(rid, deepColors[i] ?? "white", "deep"));
  return groups;
}

export function newBuild(characterId: string): ExportBuild {
  const now = new Date().toISOString();
  return {
    id: crypto.randomUUID(),
    name: "",
    characterId,
    normalSlotRelicIds: [null, null, null],
    deepSlotRelicIds: [null, null, null],
    createdAt: now,
    updatedAt: now,
  };
}
