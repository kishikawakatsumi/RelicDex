import { useEffect, useMemo, useState } from "react";
import "./App.css";
import { BuildEditor } from "./components/BuildEditor";
import { SortControl } from "./components/SortControl";
import { buildEffectFilterSections, effectBaseName, newBuild } from "./lib/build";
import {
  detectInitialLang,
  I18nContext,
  makeTranslator,
  persistLang,
  useI18n,
  type Lang,
} from "./lib/i18n";
import {
  defaultSortConfig,
  sortRelics,
  type RelicSortConfig,
} from "./lib/sort";
import { loadRelicForgeFile } from "./lib/loadFile";
import { loadMaster, type MasterData } from "./lib/loadMaster";
import {
  colorLabel,
  depthLabel,
  effectText,
  relicDisplayName,
  sizeLabel,
} from "./lib/relicName";
import { downloadRelicForgeFile } from "./lib/saveFile";
import { fetchShare, parseShareKeyFromLocation, uploadShare } from "./lib/share";
import type { ExportBuild, ExportPayload, ExportRelic } from "./types/export";

type Tab = "relics" | "builds";

const DRAFT_KEY = "relicforge.draft.v1";
/// 共有モードの編集中状態を「同じタブ内の偶発的なリロード」だけから守る用の
/// sessionStorage キー。タブを閉じれば消える / タブごとに独立。
/// localStorage を使わないのは、別タブで違う共有を開いたときの衝突や、
/// ブラウザを跨いで「自分の編集」と「他人の最新の共有」を取り違えるリスクを避けるため。
const SHARE_EDIT_KEY = "relicforge.share-edit.v1";

interface ShareEditSnapshot {
  shareKey: string;
  payload: ExportPayload;
}

function readShareEditSnapshot(): ShareEditSnapshot | null {
  try {
    const raw = sessionStorage.getItem(SHARE_EDIT_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as ShareEditSnapshot;
    if (!parsed.shareKey || !parsed.payload) return null;
    return parsed;
  } catch {
    return null;
  }
}

function writeShareEditSnapshot(snap: ShareEditSnapshot) {
  try {
    sessionStorage.setItem(SHARE_EDIT_KEY, JSON.stringify(snap));
  } catch {
    /* quota / private mode 等は無視 */
  }
}

function clearShareEditSnapshot() {
  try { sessionStorage.removeItem(SHARE_EDIT_KEY); } catch { /* noop */ }
}

/// 共有モード: /s/{key} で開かれた場合は別管理にして、
/// 自分のドラフトとは混ぜずにメモリ上のみで編集する (誤って自分のデータを上書きしないため)。
type LoadOrigin = "draft" | { type: "share"; key: string };

export default function App() {
  return (
    <I18nProvider>
      <AppInner />
    </I18nProvider>
  );
}

function I18nProvider({ children }: { children: React.ReactNode }) {
  const [lang, setLangState] = useState<Lang>(detectInitialLang);
  const setLang = (l: Lang) => {
    setLangState(l);
    persistLang(l);
  };
  const t = useMemo(() => makeTranslator(lang), [lang]);
  const value = useMemo(() => ({ lang, setLang, t }), [lang, t]);
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

function AppInner() {
  const { lang, setLang, t } = useI18n();
  const [master, setMaster] = useState<MasterData | null>(null);
  const [payload, setPayload] = useState<ExportPayload | null>(null);
  const [origin, setOrigin] = useState<LoadOrigin>("draft");
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>("relics");
  const [selectedBuildId, setSelectedBuildId] = useState<string | null>(null);
  const [shareUrl, setShareUrl] = useState<string | null>(null);
  const [sharing, setSharing] = useState(false);

  // マスタ読み込み + (共有 URL なら R2 から、それ以外はローカルドラフト復元)
  useEffect(() => {
    loadMaster()
      .then(setMaster)
      .catch((e) => setError(t("マスタ読み込み失敗: {msg}", { msg: e.message })));

    const shareKey = parseShareKeyFromLocation();
    if (shareKey) {
      setOrigin({ type: "share", key: shareKey });
      // 同じタブ内のリロード救済: sessionStorage に同じ shareKey の編集
      // スナップショットがあればそれを使う。無ければ R2 から fetch。
      const snap = readShareEditSnapshot();
      if (snap && snap.shareKey === shareKey) {
        setPayload(snap.payload);
      } else {
        fetchShare(shareKey)
          .then(setPayload)
          .catch((e) =>
            setError(t("共有データの読み込み失敗: {msg}", { msg: t(e.message) })),
          );
      }
    } else {
      const draft = localStorage.getItem(DRAFT_KEY);
      if (draft) {
        try {
          setPayload(JSON.parse(draft) as ExportPayload);
        } catch {
          // ignore
        }
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 自分のドラフトは localStorage、共有モードの編集は sessionStorage に保存。
  // 共有モードの sessionStorage 利用はタブ内リロード対策のみで、タブ閉じや
  // 他タブ・別ブラウザには波及しない (= 他人の共有データを汚染しない)。
  useEffect(() => {
    if (!payload) return;
    if (origin === "draft") {
      localStorage.setItem(DRAFT_KEY, JSON.stringify(payload));
    } else if (origin.type === "share") {
      writeShareEditSnapshot({ shareKey: origin.key, payload });
    }
  }, [payload, origin]);

  async function handleFile(file: File) {
    setError(null);
    try {
      const p = await loadRelicForgeFile(file);
      setPayload(p);
      setSelectedBuildId(null);
      setOrigin("draft");
      // 共有モードの編集スナップショットは draft に切り替わったタイミングで破棄。
      // (タブ自体は同一なので sessionStorage に古い共有編集が残っているのを掃除)
      clearShareEditSnapshot();
      if (location.pathname !== "/") history.pushState({}, "", "/");
    } catch (e) {
      setError(t("読み込み失敗: {msg}", { msg: (e as Error).message }));
    }
  }

  async function handleShare() {
    if (!payload) return;
    setSharing(true);
    setError(null);
    setShareUrl(null);
    try {
      const { shareUrl } = await uploadShare(payload);
      setShareUrl(shareUrl);
      try { await navigator.clipboard.writeText(shareUrl); } catch { /* noop */ }
    } catch (e) {
      setError(t("共有失敗: {msg}", { msg: (e as Error).message }));
    } finally {
      setSharing(false);
    }
  }

  if (!master) {
    return (
      <div className="page">
        <p>{error ?? t("マスタを読み込み中...")}</p>
      </div>
    );
  }

  return (
    <div className="page">
      <header className="header">
        <h1>RelicForge</h1>
        <div className="header-right">
          <LangToggle lang={lang} onChange={setLang} />
          <FileDrop onFile={handleFile} />
          {payload && (
            <>
              <button className="primary" onClick={() => downloadRelicForgeFile(payload)}>
                {t("書き出し")}
              </button>
              <button className="primary" onClick={handleShare} disabled={sharing}>
                {sharing ? t("共有中...") : t("URL で共有")}
              </button>
            </>
          )}
        </div>
      </header>
      {origin !== "draft" && (
        <div className="banner shared">
          {t("共有された遺物データを表示中。編集はあなたのブラウザに留まります（元のデータには反映されません）。")}
        </div>
      )}
      {shareUrl && (
        <div className="banner share-url">
          {t("共有 URL:")} <a href={shareUrl}>{shareUrl}</a>
          <button className="ghost small" onClick={() => navigator.clipboard.writeText(shareUrl)}>
            {t("コピー")}
          </button>
          <button className="ghost small" onClick={() => setShareUrl(null)}>×</button>
        </div>
      )}
      {error && <p className="error">{error}</p>}
      {payload ? (
        <>
          <nav className="tabs">
            <button className={tab === "relics" ? "active" : ""} onClick={() => setTab("relics")}>
              {t("コレクション（{n}）", { n: payload.relics.length })}
            </button>
            <button className={tab === "builds" ? "active" : ""} onClick={() => setTab("builds")}>
              {t("ビルド（{n}）", { n: payload.builds.length })}
            </button>
            <span className="meta">
              schema v{payload.schemaVersion} ・ {new Date(payload.exportedAt).toLocaleString()}
            </span>
          </nav>
          {tab === "relics" ? (
            <RelicsTab
              payload={payload}
              master={master}
              onToggleFavorite={(id) =>
                setPayload((p) =>
                  p
                    ? {
                        ...p,
                        relics: p.relics.map((r) =>
                          r.id === id ? { ...r, isFavorite: !r.isFavorite ? true : undefined } : r,
                        ),
                      }
                    : p,
                )
              }
            />
          ) : (
            <BuildsTab
              payload={payload}
              master={master}
              selectedBuildId={selectedBuildId}
              onSelect={setSelectedBuildId}
              onCreateBuild={(characterId) => {
                const b = newBuild(characterId);
                setPayload((p) => (p ? { ...p, builds: [b, ...p.builds] } : p));
                setSelectedBuildId(b.id);
              }}
              onUpdateBuild={(next) =>
                setPayload((p) =>
                  p ? { ...p, builds: p.builds.map((b) => (b.id === next.id ? next : b)) } : p,
                )
              }
              onDeleteBuild={(id) => {
                setPayload((p) => (p ? { ...p, builds: p.builds.filter((b) => b.id !== id) } : p));
                if (selectedBuildId === id) setSelectedBuildId(null);
              }}
            />
          )}
        </>
      ) : (
        <p className="empty">
          {t(".relicforge ファイルをドラッグ&ドロップするか、上のボタンから読み込んでください。")}
        </p>
      )}
    </div>
  );
}

function LangToggle({ lang, onChange }: { lang: Lang; onChange: (l: Lang) => void }) {
  // 2 値トグル。chip スタイルで右寄せヘッダに同居しても違和感が出ないサイズ。
  return (
    <div className="lang-toggle" role="group" aria-label="Language">
      <button
        className={lang === "ja" ? "chip active" : "chip"}
        onClick={() => onChange("ja")}
      >
        日本語
      </button>
      <button
        className={lang === "en" ? "chip active" : "chip"}
        onClick={() => onChange("en")}
      >
        English
      </button>
    </div>
  );
}

function FileDrop({ onFile }: { onFile: (file: File) => void }) {
  return (
    <div
      className="dropzone"
      onDragOver={(e) => e.preventDefault()}
      onDrop={(e) => {
        e.preventDefault();
        const f = e.dataTransfer.files[0];
        if (f) onFile(f);
      }}
    >
      <input
        type="file"
        accept=".relicforge"
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f) onFile(f);
        }}
      />
    </div>
  );
}

const COLORS = ["red", "blue", "yellow", "green"] as const;
const SIZES = [1, 2, 3] as const;
const DEPTHS = ["normal", "deep"] as const;

function toggleSet<T>(set: Set<T>, value: T): Set<T> {
  const next = new Set(set);
  if (next.has(value)) next.delete(value);
  else next.add(value);
  return next;
}

function RelicsTab({
  payload, master, onToggleFavorite,
}: {
  payload: ExportPayload;
  master: MasterData;
  onToggleFavorite: (id: string) => void;
}) {
  const { lang, t } = useI18n();
  const [favoritesOnly, setFavoritesOnly] = useState(false);
  const [sortConfig, setSortConfig] = useState<RelicSortConfig>(defaultSortConfig);
  const [colorFilters, setColorFilters] = useState<Set<string>>(new Set());
  const [sizeFilters, setSizeFilters] = useState<Set<number>>(new Set());
  const [depthFilters, setDepthFilters] = useState<Set<string>>(new Set());
  const [effectBaseNames, setEffectBaseNames] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState("");

  const filterSections = useMemo(() => buildEffectFilterSections(master), [master]);

  /// 各 chip 系フィルタはソフト判定。1 つでも非該当があれば該当外。
  /// 固有遺物は iOS 保存時点で depth = "normal" に正規化済みなので特別扱い不要。
  function chipFiltersMatch(r: ExportRelic): boolean {
    if (favoritesOnly && !r.isFavorite) return false;
    if (colorFilters.size > 0 && !colorFilters.has(r.color)) return false;
    if (sizeFilters.size > 0 && !sizeFilters.has(r.slotCount)) return false;
    if (depthFilters.size > 0 && !depthFilters.has(r.depth)) return false;
    if (effectBaseNames.size > 0) {
      const baseNames = new Set<string>();
      for (const e of r.effects) {
        const eff = master.effectsById.get(e.effectId);
        if (eff) baseNames.add(effectBaseName(eff.textJa));
      }
      let any = false;
      for (const want of effectBaseNames) {
        if (baseNames.has(want)) { any = true; break; }
      }
      if (!any) return false;
    }
    return true;
  }

  /// 検索テキストはハードフィルタ (該当しなければリストから消す)。チップ系はソフト。
  const displayed = useMemo(() => {
    const q = search.trim();
    const passSearch = payload.relics.filter((r) => {
      if (!q) return true;
      const name = relicDisplayName(r, master, lang);
      if (name.includes(q)) return true;
      return r.effects.some((e) => {
        const eff = master.effectsById.get(e.effectId);
        return (eff && (eff.textJa.includes(q) || eff.textEn.includes(q))) ?? false;
      });
    });
    const sorted = sortRelics(passSearch, sortConfig);
    const matched = sorted.filter(chipFiltersMatch);
    const unmatched = sorted.filter((r) => !chipFiltersMatch(r));
    return [
      ...matched.map((r) => ({ relic: r, matched: true })),
      ...unmatched.map((r) => ({ relic: r, matched: false })),
    ];
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [payload.relics, favoritesOnly, colorFilters, sizeFilters, depthFilters,
      effectBaseNames, search, sortConfig, master, lang]);
  const matchedCount = displayed.filter((d) => d.matched).length;

  return (
    <>
      <div className="filters">
        <button
          className={favoritesOnly ? "chip active" : "chip"}
          onClick={() => setFavoritesOnly((v) => !v)}
        >
          {t("★ お気に入りのみ")}
        </button>
        {COLORS.map((c) => (
          <button
            key={c}
            className={colorFilters.has(c) ? "chip active" : "chip"}
            onClick={() => setColorFilters((s) => toggleSet(s, c))}
          >
            <span className={`color-dot ${c}`} style={{ marginRight: 4 }} />
            {colorLabel(c, lang)}
          </button>
        ))}
        {SIZES.map((n) => (
          <button
            key={n}
            className={sizeFilters.has(n) ? "chip active" : "chip"}
            onClick={() => setSizeFilters((s) => toggleSet(s, n))}
          >
            {sizeLabel(n, lang)}
          </button>
        ))}
        {DEPTHS.map((d) => (
          <button
            key={d}
            className={depthFilters.has(d) ? "chip active" : "chip"}
            onClick={() => setDepthFilters((s) => toggleSet(s, d))}
          >
            {depthLabel(d, lang)}
          </button>
        ))}
        <details className="effect-filter">
          <summary>{t("効果を選択")}（{effectBaseNames.size}）</summary>
          <div className="effect-options">
            {filterSections.map((section) => (
              <details key={section.groupJa} className="effect-group">
                <summary>{lang === "ja" ? section.groupJa : section.groupEn}</summary>
                <div className="effect-group-body">
                  {section.categories.map((cat) => (
                    <div key={cat.categoryJa} className="effect-category">
                      <h5>{lang === "ja" ? cat.categoryJa : cat.categoryEn}</h5>
                      {cat.baseNames.map((b) => (
                        <label key={b}>
                          <input
                            type="checkbox"
                            checked={effectBaseNames.has(b)}
                            onChange={() => setEffectBaseNames((s) => toggleSet(s, b))}
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
        <span className="meta">{t("{n} 件", { n: matchedCount })}</span>
      </div>
      <ul className="relic-list">
        {displayed.map(({ relic, matched }) => (
          <RelicRow
            key={relic.id}
            relic={relic}
            master={master}
            onToggleFavorite={onToggleFavorite}
            dim={!matched}
          />
        ))}
      </ul>
    </>
  );
}

function RelicRow({
  relic, master, onToggleFavorite, dim,
}: {
  relic: ExportRelic;
  master: MasterData;
  onToggleFavorite: (id: string) => void;
  dim?: boolean;
}) {
  const { lang, t } = useI18n();
  const name = relicDisplayName(relic, master, lang);
  return (
    <li className={`relic-row ${dim ? "soft-dim" : ""}`}>
      {/* iOS と同じ: 文字の入った色付き四角ではなく、小さな色丸ドット 1 つ。
          (RelicPicker / BuildEditor で使っている `.color-dot` パターン) */}
      <span className={`color-dot ${relic.color}`} />
      <div className="relic-body">
        <div className="relic-title">
          <strong>{name}</strong>
          {/* タイトル右端 (旧 meta 位置) にバッジを 1 つだけ出す。
              - 固有遺物 → 紫の「固有」バッジ
              - 深層遺物 → 「深層の遺物」バッジ
              - 通常遺物 → 何も出さない (情報量が無いので省略) */}
          {relic.uniqueId ? (
            <span className="title-badge unique">{t("固有")}</span>
          ) : relic.depth === "deep" ? (
            <span className="title-badge depth">{t("深層の遺物")}</span>
          ) : null}
        </div>
        <ul className="effects">
          {relic.effects.map((e, i) => {
            const eff = master.effectsById.get(e.effectId);
            return (
              <li key={i} className={e.isDemerit ? "demerit" : ""}>
                {eff ? effectText(eff, lang) : `(unknown effect ${e.effectId})`}
              </li>
            );
          })}
        </ul>
      </div>
      <button
        className={`fav-toggle ${relic.isFavorite ? "active" : ""}`}
        onClick={() => onToggleFavorite(relic.id)}
        aria-label={t("お気に入り")}
      >
        ★
      </button>
    </li>
  );
}

function BuildsTab({
  payload, master, selectedBuildId, onSelect,
  onCreateBuild, onUpdateBuild, onDeleteBuild,
}: {
  payload: ExportPayload;
  master: MasterData;
  selectedBuildId: string | null;
  onSelect: (id: string | null) => void;
  onCreateBuild: (characterId: string) => void;
  onUpdateBuild: (next: ExportBuild) => void;
  onDeleteBuild: (id: string) => void;
}) {
  const { lang, t } = useI18n();
  const [characterId, setCharacterId] = useState<string>(
    master.characters[0]?.id ?? "",
  );
  const filtered = useMemo(
    () => payload.builds.filter((b) => b.characterId === characterId),
    [payload.builds, characterId],
  );
  const selected = selectedBuildId
    ? payload.builds.find((b) => b.id === selectedBuildId)
    : null;

  return (
    <div className="builds">
      {/* キャラ選択は左 240px カラムに押し込めず、2 カラムの上に幅いっぱいで
          配置する。ワイド画面で chips が左に固まって見える違和感を解消。 */}
      <div className="char-tabs">
        {master.characters.map((c) => (
          <button
            key={c.id}
            className={c.id === characterId ? "chip active" : "chip"}
            onClick={() => setCharacterId(c.id)}
          >
            {lang === "ja" ? (c.nameJa || c.nameEn) : (c.nameEn || c.nameJa)}
          </button>
        ))}
      </div>
      {filtered.length === 0 ? (
        // ビルドが 0 件のときは 2 カラム grid を出さず、中央寄せの空状態 + CTA。
        // 「左のリストから選択」のメッセージはそもそも選ぶリストが無いので無意味。
        <div className="builds-empty">
          <p>{t("このキャラクターのビルドはまだありません。")}</p>
          <button className="primary" onClick={() => onCreateBuild(characterId)}>
            {t("+ 新規")}
          </button>
        </div>
      ) : (
      <div className="builds-body">
        <div>
          <div className="build-list-header">
          <span className="meta">{t("{n} 件", { n: filtered.length })}</span>
          <button className="primary small" onClick={() => onCreateBuild(characterId)}>
            {t("+ 新規")}
          </button>
        </div>
        <ul className="build-list">
          {filtered
            .slice()
            .sort((a, b) => (a.updatedAt < b.updatedAt ? 1 : -1))
            .map((b) => {
              const vessel = b.vesselId ? master.vesselsById.get(b.vesselId) : undefined;
              const vesselName = vessel
                ? lang === "ja"
                  ? vessel.nameJa || vessel.nameEn
                  : vessel.nameEn || vessel.nameJa
                : null;
              return (
                <li
                  key={b.id}
                  className={selectedBuildId === b.id ? "selected" : ""}
                  onClick={() => onSelect(b.id)}
                >
                  <div className="build-list-row-top">
                    <strong>{b.name || t("名称未設定")}</strong>
                    {/* 器が選択されているときのみ ●●● ●●● で色構成を表示。
                        未選択の場合は wildcard ドットを出さず下段の「献器: 未選択」だけで状態を伝える。 */}
                    {vessel && (
                      <span className="build-list-slots">
                        <span className="slot-dots">
                          {vessel.baseSlots.map((c, i) => (
                            <span key={`b${i}`} className={`slot-dot ${c}`} />
                          ))}
                        </span>
                        <span className="slot-dots">
                          {vessel.deepSlots.map((c, i) => (
                            <span key={`d${i}`} className={`slot-dot ${c}`} />
                          ))}
                        </span>
                      </span>
                    )}
                  </div>
                  <div className="build-list-row-bottom">
                    <span className="meta">
                      {vesselName ?? t("献器: 未選択")}
                    </span>
                    <span className="meta updated-at">
                      {new Date(b.updatedAt).toLocaleString()}
                    </span>
                  </div>
                </li>
              );
            })}
        </ul>
      </div>
        {selected ? (
          <BuildEditor
            build={selected}
            payload={payload}
            master={master}
            onChange={onUpdateBuild}
            onDelete={() => {
              const name = selected.name || t("名称未設定");
              if (confirm(t("「{name}」を削除しますか?", { name }))) {
                onDeleteBuild(selected.id);
              }
            }}
          />
        ) : (
          <p className="empty">{t("左のリストからビルドを選択してください。")}</p>
        )}
      </div>
      )}
    </div>
  );
}
