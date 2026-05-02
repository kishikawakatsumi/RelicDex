// 1 つのスロットに装備する遺物を選ぶモーダル。
// 色/種別はソフト制約 (装着不可は灰色化)。サイズ・効果・お気に入りで絞り込める。

import { useMemo, useState } from "react";
import { createPortal } from "react-dom";
import type { ExportEffect, ExportRelic } from "../types/export";
import type { MasterData } from "../lib/loadMaster";
import type { VesselSlotColor } from "../types/master";
import {
  buildEffectFilterSections,
  effectBaseName,
  isEquippedElsewhere,
  mismatchReason,
  type SlotKind,
} from "../lib/build";
import { useI18n } from "../lib/i18n";
import { effectText, relicDisplayName, sizeLabel } from "../lib/relicName";
import { defaultSortConfig, sortRelics, type RelicSortConfig } from "../lib/sort";
import { SortControl } from "./SortControl";

/// slotIndex で効果をグルーピング (iOS `StoredRelic.slotsGrouped` と同等)。
/// インデックス順、各スロットは main → optional demerit のペアで返す。
function slotsGrouped(effects: ExportEffect[]): { main: ExportEffect; demerit?: ExportEffect }[] {
  const bySlot = new Map<number, ExportEffect[]>();
  for (const e of effects) {
    const arr = bySlot.get(e.slotIndex) ?? [];
    arr.push(e);
    bySlot.set(e.slotIndex, arr);
  }
  return [...bySlot.keys()]
    .sort((a, b) => a - b)
    .flatMap((idx) => {
      const inSlot = bySlot.get(idx)!;
      const main = inSlot.find((e) => !e.isDemerit);
      if (!main) return [];
      const demerit = inSlot.find((e) => e.isDemerit);
      return [{ main, demerit }];
    });
}

export interface SharedFilters {
  sizes: Set<number>;
  effectBaseNames: Set<string>;
  favoritesOnly: boolean;
}

export function emptyFilters(): SharedFilters {
  return { sizes: new Set(), effectBaseNames: new Set(), favoritesOnly: false };
}

interface Props {
  slotColor: VesselSlotColor;
  slotKind: SlotKind;
  /// 通常 3 + 深層 3 のスロット色 (iOS と同様、●●● ●●● 形式のヘッダで表示する)。
  normalSlotColors?: VesselSlotColor[];
  deepSlotColors?: VesselSlotColor[];
  /// 選択中スロット index (0..2)。slotKind と組み合わせて該当ドットをアクセントリングで強調。
  slotIndex?: number;
  currentRelicId: string | null;
  allRelics: ExportRelic[];
  otherEquippedIds: Set<string>;
  master: MasterData;
  filters: SharedFilters;
  onFiltersChange: (next: SharedFilters) => void;
  onSelect: (relicId: string | null) => void;
  onClose: () => void;
}

export function RelicPicker(props: Props) {
  const {
    slotColor,
    slotKind,
    normalSlotColors,
    deepSlotColors,
    slotIndex,
    currentRelicId,
    allRelics,
    otherEquippedIds,
    master,
    filters,
    onFiltersChange,
    onSelect,
    onClose,
  } = props;
  const { lang, t } = useI18n();
  const [search, setSearch] = useState("");
  const [sortConfig, setSortConfig] = useState<RelicSortConfig>(defaultSortConfig);

  // フィルタは TSV 順 (master.effects の並び順) のまま、
  // groupJa → categoryJa → baseName の 3 階層で表示する。
  const filterSections = useMemo(() => buildEffectFilterSections(master), [master]);

  /// チップ系フィルタ (お気に入り/サイズ/効果) はソフト判定。
  /// 該当しない遺物もリストには表示し、dim 表示するだけ (iOS と揃える)。
  function chipFiltersMatch(r: ExportRelic): boolean {
    if (filters.favoritesOnly && !r.isFavorite) return false;
    if (filters.sizes.size > 0 && !filters.sizes.has(r.slotCount)) return false;
    if (filters.effectBaseNames.size > 0) {
      const baseNames = new Set<string>();
      for (const e of r.effects) {
        const eff = master.effectsById.get(e.effectId);
        if (eff) baseNames.add(effectBaseName(eff.textJa));
      }
      for (const want of filters.effectBaseNames) {
        if (baseNames.has(want)) return true;
      }
      return false;
    }
    return true;
  }

  /// 検索テキストはハードフィルタ (該当しなければ非表示)。
  const filtered = useMemo(() => {
    const q = search.trim();
    const passSearch = allRelics.filter((r) => {
      if (!q) return true;
      const name = relicDisplayName(r, master, lang);
      const inName = name.includes(q);
      const inEffects = r.effects.some((e) => {
        const eff = master.effectsById.get(e.effectId);
        return (eff && (eff.textJa.includes(q) || eff.textEn.includes(q))) ?? false;
      });
      return inName || inEffects;
    });
    // 4 段ソート: 1) 現在装備中 → 2) スロット適合 → 3) チップ該当 → 4) sortConfig
    // 同じグループ内では sortConfig (登録順 / サイズ / 色) で並び替える。
    const withinGroupSorted = sortRelics(passSearch, sortConfig);
    return withinGroupSorted.sort((a, b) => {
      if ((a.id === currentRelicId) !== (b.id === currentRelicId)) {
        return a.id === currentRelicId ? -1 : 1;
      }
      const aSlotOK = mismatchReason(a, slotColor, slotKind, otherEquippedIds, currentRelicId) == null;
      const bSlotOK = mismatchReason(b, slotColor, slotKind, otherEquippedIds, currentRelicId) == null;
      if (aSlotOK !== bSlotOK) return aSlotOK ? -1 : 1;
      const aChipOK = chipFiltersMatch(a);
      const bChipOK = chipFiltersMatch(b);
      if (aChipOK !== bChipOK) return aChipOK ? -1 : 1;
      return 0;  // sortRelics で順序済みなので維持 (Array.sort は安定とは限らないが
                 // 現代のエンジン V8/JSC は安定実装)
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [allRelics, filters, search, sortConfig, currentRelicId, slotColor, slotKind, otherEquippedIds, master, lang]);

  function toggleSet<T>(set: Set<T>, value: T): Set<T> {
    const next = new Set(set);
    if (next.has(value)) next.delete(value);
    else next.add(value);
    return next;
  }

  // document.body 直下にレンダリングして親のスタッキングコンテキスト
  // (transform / filter / contain など) の影響を完全に切り離す。これで
  // `position: fixed; inset: 0` がビューポート全体 (status bar / URL bar
  // 含む) を確実にカバーできる。
  return createPortal(
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <header className="modal-header">
          <h3>{t("遺物を選択")}</h3>
          <button className="ghost" onClick={onClose}>{t("閉じる")}</button>
        </header>
        <div className="filters">
          <button
            className={filters.favoritesOnly ? "chip active" : "chip"}
            onClick={() => onFiltersChange({ ...filters, favoritesOnly: !filters.favoritesOnly })}
          >
            {t("★ お気に入り")}
          </button>
          {[1, 2, 3].map((n) => (
            <button
              key={n}
              className={filters.sizes.has(n) ? "chip active" : "chip"}
              onClick={() => onFiltersChange({ ...filters, sizes: toggleSet(filters.sizes, n) })}
            >
              {sizeLabel(n, lang)}
            </button>
          ))}
          <details className="effect-filter">
            <summary>{t("効果（{n}）", { n: filters.effectBaseNames.size })}</summary>
            <div className="effect-options">
              {filterSections.map((section) => (
                <details key={section.groupJa} className="effect-group">
                  <summary>{section.groupJa}</summary>
                  <div className="effect-group-body">
                    {section.categories.map((cat) => (
                      <div key={cat.categoryJa} className="effect-category">
                        <h5>{cat.categoryJa}</h5>
                        {cat.baseNames.map((b) => (
                          <label key={b}>
                            <input
                              type="checkbox"
                              checked={filters.effectBaseNames.has(b)}
                              onChange={() =>
                                onFiltersChange({
                                  ...filters,
                                  effectBaseNames: toggleSet(filters.effectBaseNames, b),
                                })
                              }
                            />
                            {b}
                          </label>
                        ))}
                      </div>
                    ))}
                  </div>
                </details>
              ))}
            </div>
          </details>
          <SortControl config={sortConfig} onChange={setSortConfig} />
          <input
            className="search"
            placeholder={t("効果テキストを検索")}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        {/* iOS と同じ ●●● ●●● 形式の section header: 通常 3 + 深層 3 のスロット色を
            並べ、選択中スロットだけアクセント色のリングで囲む。器が選ばれていない
            場合 (slot 色配列が無い) は出さない。 */}
        {normalSlotColors && deepSlotColors && (
          <div className="picker-slots-header">
            <span className="slot-dots picker-slots-group">
              {normalSlotColors.map((c, i) => {
                const selected = slotKind === "normal" && i === slotIndex;
                return (
                  <span
                    key={`n${i}`}
                    className={`slot-dot ${c} ${selected ? "selected" : ""}`}
                  />
                );
              })}
            </span>
            <span className="slot-dots picker-slots-group">
              {deepSlotColors.map((c, i) => {
                const selected = slotKind === "deep" && i === slotIndex;
                return (
                  <span
                    key={`d${i}`}
                    className={`slot-dot ${c} ${selected ? "selected" : ""}`}
                  />
                );
              })}
            </span>
          </div>
        )}
        <div className="picker-list">
          <button
            className="row remove"
            onClick={() => { onSelect(null); onClose(); }}
          >
            {t("装備を外す")}
            {currentRelicId == null && <span className="check">✓</span>}
          </button>
          {filtered.length === 0 ? (
            <p className="empty-row">{t("該当する遺物がありません。")}</p>
          ) : (
            filtered.map((relic) => {
              const mismatch = mismatchReason(relic, slotColor, slotKind, otherEquippedIds, currentRelicId);
              const chipOK = chipFiltersMatch(relic);
              // ソフト dim 条件: スロット適合しない or チップフィルタ非該当。
              // スロット適合しない場合のみ disabled にする (タップ不可)。
              const dim = mismatch != null || !chipOK;
              const slotDisabled = mismatch != null;
              const showEquippedBadge = isEquippedElsewhere(relic, otherEquippedIds, currentRelicId);
              return (
                <button
                  key={relic.id}
                  className={`row ${slotDisabled ? "disabled" : ""} ${dim ? "dim" : ""}`}
                  disabled={slotDisabled}
                  onClick={() => { onSelect(relic.id); onClose(); }}
                >
                  <span className={`color-dot ${relic.color}`} />
                  <div className="row-body">
                    <div className="row-title">
                      <span>{relicDisplayName(relic, master, lang)}</span>
                      {relic.uniqueId && <span className="badge unique">{t("固有")}</span>}
                      {/* iOS と揃え: 色違い・深層用・通常用などのバッジは出さず、
                          「装備中 / Equipped」だけ残す。それ以外は dim だけで表現。 */}
                      {showEquippedBadge && <span className="badge equipped">{t("装備中")}</span>}
                      <span className="meta">◆{relic.slotCount}</span>
                    </div>
                    {/* iOS の CollectionView / BuildRelicPicker と同じパターン: */}
                    {/* slotIndex で main + demerit をペアにし、main は bullet ⚫ */}
                    {/* (灰)、demerit は bullet ⚫ (シアン) + 1 段インデント + 小さめフォントで */}
                    {/* 視覚的にしっかり区別する。複数行に折り返した時も判読しやすい。 */}
                    <ul className="effect-slots">
                      {slotsGrouped(relic.effects).map((pair, i) => {
                        const main = master.effectsById.get(pair.main.effectId);
                        const dem = pair.demerit
                          ? master.effectsById.get(pair.demerit.effectId)
                          : null;
                        return (
                          <li key={i} className="effect-slot">
                            <div className="effect-main">
                              <span className="bullet" />
                              <span>{main ? effectText(main, lang) : "(unknown)"}</span>
                            </div>
                            {dem && (
                              <div className="effect-demerit">
                                <span className="bullet" />
                                <span>{effectText(dem, lang)}</span>
                              </div>
                            )}
                          </li>
                        );
                      })}
                    </ul>
                  </div>
                  {relic.id === currentRelicId && <span className="check">✓</span>}
                </button>
              );
            })
          )}
        </div>
      </div>
    </div>,
    document.body,
  );
}
