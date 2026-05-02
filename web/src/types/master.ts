// マスタ JSON の TypeScript 型定義 (iOS の RelicEffect / UniqueRelic / Nightfarer / Vessel と同等)。

export type RelicColor = "red" | "blue" | "yellow" | "green" | "unknown";
export type RelicDepth = "normal" | "deep" | "unknown";
export type VesselSlotColor = "red" | "blue" | "yellow" | "green" | "white";

export interface RelicEffect {
  id: string;
  textJa: string;
  textEn: string;
  groupJa: string;
  groupEn: string;
  categoryJa: string;
  categoryEn: string;
  category: string;
}

export interface EffectsMasterFile {
  version: number;
  effects: RelicEffect[];
}

export interface UniqueRelic {
  id: string;
  nameJa: string;
  nameEn: string;
  color: RelicColor;
  effects: { textJa: string; effectId: string | null }[];
}

export interface UniqueRelicsMasterFile {
  version: number;
  uniqueRelics: UniqueRelic[];
}

export interface Nightfarer {
  id: string;
  nameJa: string;
  nameEn: string;
  isForsaken: boolean;
}

export interface CharactersMasterFile {
  version: number;
  characters: Nightfarer[];
}

export interface Vessel {
  id: string;
  nameJa: string;
  nameEn: string;
  characterId: string | null;
  baseSlots: VesselSlotColor[];
  deepSlots: VesselSlotColor[];
  isForsaken: boolean;
  descriptionEn: string;
}

export interface VesselsMasterFile {
  version: number;
  vessels: Vessel[];
}

// 遺物タイトル組み立て用の単語マスタ (`title_words.json`)
// JP: `{size}な{color}{depth}` (例: 端正な燃える昏景)
// EN: `[Deep ]{size} {color} {depth}` (例: Deep Polished Burning Scene)
export interface TitleWordsMasterFile {
  version: number;
  sizes: { slotCount: number; ja: string; en: string }[];
  colors: { color: string; ja: string; en: string }[];
  depths: { depth: string; ja: string; en: string; enPrefix?: string }[];
}
