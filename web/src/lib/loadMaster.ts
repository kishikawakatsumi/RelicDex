// マスタ JSON 4 種類を `/master/` から fetch してまとめて返す。
// iOS と同一ファイルが web/public/master/ に同期されている (scripts 経由)。

import type {
  CharactersMasterFile,
  EffectsMasterFile,
  Nightfarer,
  RelicEffect,
  TitleWordsMasterFile,
  UniqueRelic,
  UniqueRelicsMasterFile,
  Vessel,
  VesselsMasterFile,
} from "../types/master";

export interface MasterData {
  effects: RelicEffect[];
  effectsById: Map<string, RelicEffect>;
  uniqueRelics: UniqueRelic[];
  uniqueRelicsById: Map<string, UniqueRelic>;
  characters: Nightfarer[];
  charactersById: Map<string, Nightfarer>;
  vessels: Vessel[];
  vesselsById: Map<string, Vessel>;
  titleWords: TitleWordsMasterFile;
}

export async function loadMaster(): Promise<MasterData> {
  const base = `${import.meta.env.BASE_URL}master`;
  const [effects, uniques, chars, vessels, titleWords] = await Promise.all([
    fetchJson<EffectsMasterFile>(`${base}/effects.json`),
    fetchJson<UniqueRelicsMasterFile>(`${base}/unique_relics.json`),
    fetchJson<CharactersMasterFile>(`${base}/characters.json`),
    fetchJson<VesselsMasterFile>(`${base}/vessels.json`),
    fetchJson<TitleWordsMasterFile>(`${base}/title_words.json`),
  ]);

  return {
    effects: effects.effects,
    effectsById: byId(effects.effects, (e) => e.id),
    uniqueRelics: uniques.uniqueRelics,
    uniqueRelicsById: byId(uniques.uniqueRelics, (u) => u.id),
    characters: chars.characters,
    charactersById: byId(chars.characters, (c) => c.id),
    vessels: vessels.vessels,
    vesselsById: byId(vessels.vessels, (v) => v.id),
    titleWords,
  };
}

async function fetchJson<T>(url: string): Promise<T> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`failed to fetch ${url}: ${res.status}`);
  return (await res.json()) as T;
}

function byId<T>(items: T[], key: (t: T) => string): Map<string, T> {
  const m = new Map<string, T>();
  for (const it of items) m.set(key(it), it);
  return m;
}
