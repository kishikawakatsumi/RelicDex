// 遺物名の組み立て (ロケール対応版)。
// title_words.json マスタの単語を、引数で渡された Lang に合わせて並べる。
// JP: `{size}な{color}{depth}` (例: 端正な燃える昏景)
// EN: `[Deep ]{size} {color} {depth}` (例: Deep Polished Burning Scene)

import type { MasterData } from "./loadMaster";
import type { ExportRelic } from "../types/export";
import type { RelicEffect } from "../types/master";
import type { Lang } from "./i18n";

/// 効果テキストを指定言語で返す。
export function effectText(e: RelicEffect, lang: Lang): string {
  return lang === "ja" ? e.textJa : e.textEn;
}

export function relicDisplayName(r: ExportRelic, master: MasterData, lang: Lang): string {
  if (r.uniqueId) {
    const u = master.uniqueRelicsById.get(r.uniqueId);
    if (u) return lang === "ja" ? u.nameJa : u.nameEn;
  }
  return composeFromWords(r.slotCount, r.color, r.depth, master, lang);
}

function composeFromWords(
  slotCount: number,
  color: string,
  depth: string,
  master: MasterData,
  lang: Lang,
): string {
  const sizeWord = master.titleWords.sizes.find((s) => s.slotCount === slotCount);
  const colorWord = master.titleWords.colors.find((c) => c.color === color);
  const depthWord = master.titleWords.depths.find((d) => d.depth === depth);
  if (lang === "ja") {
    return `${sizeWord?.ja ?? "?"}な${colorWord?.ja ?? "?"}${depthWord?.ja ?? "?"}`;
  }
  const size = sizeWord?.en ?? "?";
  const col = colorWord?.en ?? "?";
  const dep = depthWord?.en ?? "?";
  const prefix = depthWord?.enPrefix;
  return prefix ? `${prefix} ${size} ${col} ${dep}` : `${size} ${col} ${dep}`;
}

// 以下は UI ラベル用 (フィルタチップ等)。
export function colorLabel(c: string, lang: Lang): string {
  if (lang === "ja") {
    return { red: "赤色", blue: "青色", yellow: "黄色", green: "緑色" }[c] ?? "不明";
  }
  return { red: "Red", blue: "Blue", yellow: "Yellow", green: "Green" }[c] ?? "Unknown";
}

export function sizeLabel(n: number, lang: Lang): string {
  if (lang === "ja") {
    return { 1: "小", 2: "中", 3: "大" }[n] ?? "?";
  }
  return { 1: "Small", 2: "Medium", 3: "Large" }[n] ?? "?";
}

export function depthLabel(d: string, lang: Lang): string {
  if (lang === "ja") {
    return d === "deep" ? "深層の遺物" : d === "normal" ? "遺物" : "不明";
  }
  return d === "deep" ? "Depths Relic" : d === "normal" ? "Relic" : "Unknown";
}
