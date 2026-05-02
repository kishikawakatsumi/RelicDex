// 1 ビルドの編集 UI (iOS BuildEditorView 相当)。
// キャラ → 名前 → 献器 → 通常スロット 3 → 深層スロット 3 → 効果サマリ。

import { useMemo, useState } from "react";
import type { ExportBuild, ExportPayload, ExportRelic } from "../types/export";
import type { MasterData } from "../lib/loadMaster";
import {
  aggregatedEffectGroups,
  equippedRelicIdsExcluding,
  mismatchReason,
  setSlotRelicId,
  type SlotKind,
} from "../lib/build";
import { useI18n } from "../lib/i18n";
import { relicDisplayName } from "../lib/relicName";
import type { VesselSlotColor } from "../types/master";
import { RelicPicker, emptyFilters, type SharedFilters } from "./RelicPicker";
import { VesselPicker } from "./VesselPicker";

interface Props {
  build: ExportBuild;
  payload: ExportPayload;
  master: MasterData;
  onChange: (next: ExportBuild) => void;
  onDelete: () => void;
}

export function BuildEditor({ build, payload, master, onChange, onDelete }: Props) {
  const { lang, t } = useI18n();
  const [showVesselPicker, setShowVesselPicker] = useState(false);
  const [picking, setPicking] = useState<{ kind: SlotKind; index: number; color: VesselSlotColor } | null>(null);
  const [filters, setFilters] = useState<SharedFilters>(emptyFilters);

  const character = master.charactersById.get(build.characterId);
  const vessel = build.vesselId ? master.vesselsById.get(build.vesselId) : null;
  const vesselSelected = vessel != null;
  const normalColors = vessel?.baseSlots ?? (["white", "white", "white"] as VesselSlotColor[]);
  const deepColors = vessel?.deepSlots ?? (["white", "white", "white"] as VesselSlotColor[]);

  const relicById = useMemo(
    () => new Map(payload.relics.map((r) => [r.id, r])),
    [payload.relics],
  );

  const summaryGroups = useMemo(
    () => aggregatedEffectGroups(build, master, relicById, lang),
    [build, master, relicById, lang],
  );

  function setSlot(kind: SlotKind, index: number, relicId: string | null) {
    onChange(setSlotRelicId(build, kind, index, relicId));
  }

  function setVessel(vesselId: string | null) {
    onChange({ ...build, vesselId: vesselId ?? undefined, updatedAt: new Date().toISOString() });
  }

  const charName = character
    ? (lang === "ja" ? (character.nameJa || character.nameEn) : (character.nameEn || character.nameJa))
    : build.characterId;
  const vesselName = vessel
    ? (lang === "ja" ? (vessel.nameJa || vessel.nameEn) : (vessel.nameEn || vessel.nameJa))
    : "";

  return (
    <section className="build-editor">
      <header className="editor-header">
        <h2>{charName}</h2>
        <button className="ghost danger" onClick={onDelete}>{t("削除")}</button>
      </header>

      <label className="field">
        <span>{t("ビルド名")}</span>
        <input
          type="text"
          value={build.name}
          placeholder={t("名称未設定")}
          onChange={(e) => onChange({ ...build, name: e.target.value, updatedAt: new Date().toISOString() })}
        />
      </label>

      <div className="field">
        <span>{t("献器")}</span>
        <button className="vessel-row" onClick={() => setShowVesselPicker(true)}>
          {vessel ? (
            <div className="vessel-info">
              <strong>{vesselName}</strong>
              {/* iOS と同じ ●●● ●●● 形式: 通常/深層のテキストラベルは付けず、
                  少し空けた 2 群のドットだけで色構成を伝える。 */}
              <div className="vessel-slots">
                <SlotDots colors={vessel.baseSlots} />
                <SlotDots colors={vessel.deepSlots} />
              </div>
            </div>
          ) : (
            <span className="placeholder">{t("献器を選択")}</span>
          )}
          <span className="chev">›</span>
        </button>
      </div>

      <SlotsSection
        title={t("遺物")}
        kind="normal"
        colors={normalColors}
        ids={build.normalSlotRelicIds}
        relicById={relicById}
        master={master}
        vesselSelected={vesselSelected}
        onPick={(i) => setPicking({ kind: "normal", index: i, color: normalColors[i] ?? "white" })}
        onClear={(i) => setSlot("normal", i, null)}
      />
      <SlotsSection
        title={t("深層の遺物")}
        kind="deep"
        colors={deepColors}
        ids={build.deepSlotRelicIds}
        relicById={relicById}
        master={master}
        vesselSelected={vesselSelected}
        onPick={(i) => setPicking({ kind: "deep", index: i, color: deepColors[i] ?? "white" })}
        onClear={(i) => setSlot("deep", i, null)}
      />

      <h3>{t("遺物効果")}</h3>
      {summaryGroups.length === 0 ? (
        <p className="empty">{t("装備された効果はまだありません。")}</p>
      ) : (
        <div className="summary-groups">
          {summaryGroups.map((group, gi) => (
            <ul key={gi} className="summary-list">
              {group.map((line, li) => (
                <li
                  key={li}
                  className={line.isDemerit ? "demerit" : ""}
                >
                  {line.text}
                </li>
              ))}
            </ul>
          ))}
        </div>
      )}

      {showVesselPicker && (
        <VesselPicker
          characterId={build.characterId}
          currentVesselId={build.vesselId ?? null}
          master={master}
          onSelect={setVessel}
          onClose={() => setShowVesselPicker(false)}
        />
      )}
      {picking && (
        <RelicPicker
          slotColor={picking.color}
          slotKind={picking.kind}
          normalSlotColors={normalColors}
          deepSlotColors={deepColors}
          slotIndex={picking.index}
          currentRelicId={
            (picking.kind === "normal" ? build.normalSlotRelicIds : build.deepSlotRelicIds)[picking.index] ?? null
          }
          allRelics={payload.relics}
          otherEquippedIds={equippedRelicIdsExcluding(build, { kind: picking.kind, index: picking.index })}
          master={master}
          filters={filters}
          onFiltersChange={setFilters}
          onSelect={(rid) => setSlot(picking.kind, picking.index, rid)}
          onClose={() => setPicking(null)}
        />
      )}
    </section>
  );
}

function SlotsSection({
  title, kind, colors, ids, relicById, master, vesselSelected, onPick, onClear,
}: {
  title: string;
  kind: SlotKind;
  colors: VesselSlotColor[];
  ids: (string | null)[];
  relicById: Map<string, ExportRelic>;
  master: MasterData;
  vesselSelected: boolean;
  onPick: (index: number) => void;
  onClear: (index: number) => void;
}) {
  const { lang, t } = useI18n();
  return (
    <div>
      <h3>{title}</h3>
      <ul className="slots">
        {ids.map((rid, i) => {
          const color = colors[i] ?? "white";
          const relic = rid ? relicById.get(rid) ?? null : null;
          // ミスマッチ理由はバッジ表示しない (iOS と揃える)。色違い/深層用などは
          // dim (opacity 低下) だけで視覚的に伝える。
          const mismatch = relic ? mismatchReason(relic, color, kind, new Set(), relic.id) : null;
          return (
            <li key={i} className={vesselSelected ? "" : "disabled"}>
              <button
                className="slot-button"
                disabled={!vesselSelected}
                onClick={() => onPick(i)}
              >
                <span className={`slot-dot ${color}`} />
                {relic ? (
                  <div className={`slot-relic ${mismatch ? "mismatch" : ""}`}>
                    <strong>{relicDisplayName(relic, master, lang)}</strong>
                  </div>
                ) : (
                  <span className="placeholder">{t("装備なし")}</span>
                )}
                <span className="chev">›</span>
              </button>
              {relic && (
                <button className="ghost clear" onClick={() => onClear(i)}>×</button>
              )}
            </li>
          );
        })}
      </ul>
    </div>
  );
}

function SlotDots({ colors }: { colors: VesselSlotColor[] }) {
  return (
    <span className="slot-dots">
      {colors.map((c, i) => <span key={i} className={`slot-dot ${c}`} />)}
    </span>
  );
}
