// 1 ビルドの献器を選ぶモーダル。キャラ専用 → 共通 の順で並べる。

import { createPortal } from "react-dom";
import type { MasterData } from "../lib/loadMaster";
import { vesselsForCharacter } from "../lib/build";
import { useI18n } from "../lib/i18n";
import type { Vessel, VesselSlotColor } from "../types/master";

interface Props {
  characterId: string;
  currentVesselId: string | null;
  master: MasterData;
  onSelect: (vesselId: string | null) => void;
  onClose: () => void;
}

export function VesselPicker({ characterId, currentVesselId, master, onSelect, onClose }: Props) {
  const { lang, t } = useI18n();
  const { generic, character } = vesselsForCharacter(characterId, master);
  const char = master.charactersById.get(characterId);
  const characterName = char
    ? (lang === "ja" ? (char.nameJa || char.nameEn) : (char.nameEn || char.nameJa))
    : characterId;

  // document.body 直下に Portal で出して、親のスタッキングコンテキストや
  // transform の影響を受けずビューポート全体に dim を敷く。
  return createPortal(
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <header className="modal-header">
          <h3>{t("献器を選択")}</h3>
          <button className="ghost" onClick={onClose}>{t("閉じる")}</button>
        </header>
        <div className="picker-list">
          <button className="row remove" onClick={() => { onSelect(null); onClose(); }}>
            {t("選択を解除")}
            {currentVesselId == null && <span className="check">✓</span>}
          </button>
          {character.length > 0 && (
            <>
              <h4 className="section-header">{t("{name} 専用", { name: characterName })}</h4>
              {character.map((v) => (
                <VesselRow key={v.id} v={v} current={currentVesselId} onSelect={(id) => { onSelect(id); onClose(); }} />
              ))}
            </>
          )}
          {generic.length > 0 && (
            <>
              <h4 className="section-header">{t("共通")}</h4>
              {generic.map((v) => (
                <VesselRow key={v.id} v={v} current={currentVesselId} onSelect={(id) => { onSelect(id); onClose(); }} />
              ))}
            </>
          )}
        </div>
      </div>
    </div>,
    document.body,
  );
}

function VesselRow({ v, current, onSelect }: { v: Vessel; current: string | null; onSelect: (id: string) => void }) {
  const { lang } = useI18n();
  const name = lang === "ja" ? (v.nameJa || v.nameEn) : (v.nameEn || v.nameJa);
  return (
    <button className="row" onClick={() => onSelect(v.id)}>
      <div className="row-body">
        <div className="row-title">
          <span>{name}</span>
        </div>
        {/* iOS と同じ ●●● ●●● 形式: 通常/深層のテキストラベルは付けず、
            少し空けた 2 群のドットだけで色構成を伝える。 */}
        <div className="vessel-slots">
          <SlotDots colors={v.baseSlots} />
          <SlotDots colors={v.deepSlots} />
        </div>
      </div>
      {v.id === current && <span className="check">✓</span>}
    </button>
  );
}

function SlotDots({ colors }: { colors: VesselSlotColor[] }) {
  return (
    <span className="slot-dots">
      {colors.map((c, i) => <span key={i} className={`slot-dot ${c}`} />)}
    </span>
  );
}
