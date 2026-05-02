// Web SPA の言語切替機構。UI ハードコード文字列・遺物名・効果テキストすべてを
// 同じ言語で表示するため、ユーザの選択を React Context で配下に流す。
//
// 設計:
// - キー = 日本語の文字列をそのまま使う (iOS の String Catalog と同じ思想)
// - JA → 自分自身を返す / EN → 翻訳辞書を引く / 無ければキーをそのまま返す
// - 補間は `{name}` プレースホルダで `t(key, { name: "..." })`
// - 永続化は localStorage、初回は navigator.language を見て JA / EN を判定

import { createContext, useContext } from "react";

export type Lang = "ja" | "en";

const STORAGE_KEY = "relicforge.lang.v1";

/// JA リテラル → EN 訳。キーはコード上に出てくる JA をそのまま使う。
const TRANSLATIONS: Record<string, string> = {
  // header / global
  "書き出し": "Export",
  "URL で共有": "Share via URL",
  "共有中...": "Sharing...",
  "コピー": "Copy",
  "コレクション（{n}）": "Collection ({n})",
  "ビルド（{n}）": "Builds ({n})",
  "マスタを読み込み中...": "Loading master data...",
  "マスタ読み込み失敗: {msg}": "Master load failed: {msg}",
  "共有データの読み込み失敗: {msg}": "Share load failed: {msg}",
  "読み込み失敗: {msg}": "Load failed: {msg}",
  "共有失敗: {msg}": "Share failed: {msg}",
  "共有 URL:": "Share URL:",
  "共有された遺物データを表示中。編集はあなたのブラウザに留まります（元のデータには反映されません）。":
    "Viewing shared data. Edits stay in your browser only (not reflected in the original).",
  ".relicforge ファイルをドラッグ&ドロップするか、上のボタンから読み込んでください。":
    "Drag & drop a .relicforge file, or load one with the button above.",

  // collection / lists
  "★ お気に入りのみ": "★ Favorites only",
  "{n} 件": "{n} items",
  "お気に入り": "Favorite",
  "固有": "Unique",

  // builds tab
  "+ 新規": "+ New",
  "名称未設定": "Untitled",
  "献器: 未選択": "Vessel: Not selected",
  "「{name}」を削除しますか?": 'Delete "{name}"?',
  "左のリストからビルドを選択してください。": "Select a build from the left.",
  "このキャラクターのビルドはまだありません。": "No builds for this character yet.",

  // build editor
  "削除": "Delete",
  "ビルド名": "Build Name",
  "献器": "Vessel",
  "献器を選択": "Select Vessel",
  "基本性能": "Base Properties",
  "遺物効果": "Relic Effect",
  "装備された効果はまだありません。": "No effects equipped yet.",
  "装備なし": "Not equipped",

  // relic picker
  "遺物を選択": "Select Relic",
  "閉じる": "Close",
  "★ お気に入り": "★ Favorites",
  "効果を選択": "Select Effect",
  "選択中": "Selected",
  "フィルタ": "Filter",
  "効果テキストを検索": "Search effect text",
  "装備を外す": "Unequip",
  "該当する遺物がありません。": "No relics match.",
  "装備中": "Equipped",

  // sort
  "ソート": "Sort",
  "登録順": "Order Registered",
  "大きさ順": "Order by Size",
  "色順": "Order by Color",

  // import / share button labels
  "次へ": "Continue",
  "変更": "Edit",
  "URL または key": "URL or key",

  // vessel picker
  "選択を解除": "Clear selection",
  "{name} 専用": "{name} only",
  "共通": "Generic",

  // share errors
  "共有データが見つかりません（期限切れか URL ミスの可能性）":
    "Share data not found (expired or invalid URL)",
  "取得失敗: {status}": "Fetch failed: {status}",

  // color / size / depth labels (used in filter chips etc.)
  "赤色": "Red",
  "青色": "Blue",
  "黄色": "Yellow",
  "緑色": "Green",
  "不明": "Unknown",
  "小": "Small",
  "中": "Medium",
  "大": "Large",
  "深層の遺物": "Depth Relic",
  "遺物": "Relic",
};

export interface I18n {
  lang: Lang;
  setLang: (lang: Lang) => void;
  t: (key: string, vars?: Record<string, string | number>) => string;
}

export const I18nContext = createContext<I18n | null>(null);

export function useI18n(): I18n {
  const ctx = useContext(I18nContext);
  if (!ctx) throw new Error("useI18n called outside <I18nProvider>");
  return ctx;
}

export function useT(): I18n["t"] {
  return useI18n().t;
}

export function detectInitialLang(): Lang {
  if (typeof window === "undefined") return "ja";
  const saved = window.localStorage.getItem(STORAGE_KEY);
  if (saved === "ja" || saved === "en") return saved;
  const nav = (window.navigator?.language ?? "").toLowerCase();
  return nav.startsWith("ja") ? "ja" : "en";
}

export function persistLang(lang: Lang) {
  try {
    window.localStorage.setItem(STORAGE_KEY, lang);
  } catch {
    /* ignore (private mode 等) */
  }
}

export function makeTranslator(lang: Lang): I18n["t"] {
  return (key, vars) => {
    let text = lang === "ja" ? key : (TRANSLATIONS[key] ?? key);
    if (vars) {
      for (const [k, v] of Object.entries(vars)) {
        text = text.replaceAll(`{${k}}`, String(v));
      }
    }
    return text;
  };
}
