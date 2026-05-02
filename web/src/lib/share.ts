// 共有 API クライアント。`.relicforge` のバイト列を R2 に PUT して短い key を取得し、
// 受信側は GET /api/share/{key} で取り戻す。

import type { ExportPayload } from "../types/export";

/// 編集中の payload を圧縮し、Pages Functions 経由で R2 にアップロードして key を返す。
/// 戻り値の `shareUrl` は他人と共有してそのまま開ける形式。
export async function uploadShare(payload: ExportPayload): Promise<{ key: string; shareUrl: string }> {
  const json = JSON.stringify(payload);
  const stream = new Response(json).body!.pipeThrough(
    new CompressionStream("deflate-raw"),
  );
  const blob = await new Response(stream).blob();

  // OGP の言語選択に使う: 共有作成者のロケールを「観てほしい言語」として伝える。
  // ブラウザの navigator.language ("ja-JP" など) を主言語コードのみに丸めて送る。
  const lang = (navigator.language || "en").split("-")[0];
  const res = await fetch("/api/share", {
    method: "POST",
    headers: {
      "Content-Type": "application/octet-stream",
      "Content-Language": lang,
    },
    body: blob,
  });
  if (!res.ok) {
    throw new Error(`upload failed: ${res.status} ${await res.text().catch(() => "")}`);
  }
  const data = (await res.json()) as { key: string };
  const shareUrl = `${location.origin}/s/${data.key}`;
  return { key: data.key, shareUrl };
}

/// 共有 URL から key を取り出して R2 経由で payload を取得し、解凍 + パースする。
export async function fetchShare(key: string): Promise<ExportPayload> {
  const res = await fetch(`/api/share/${encodeURIComponent(key)}`);
  if (res.status === 404) throw new Error("共有データが見つかりません（期限切れか URL ミスの可能性）");
  if (!res.ok) throw new Error(`取得失敗: ${res.status}`);
  const buf = await res.arrayBuffer();
  const stream = new Response(buf).body!.pipeThrough(
    new DecompressionStream("deflate-raw"),
  );
  const text = await new Response(stream).text();
  return JSON.parse(text) as ExportPayload;
}

/// 現在の URL が `/s/{key}` 形式なら key を返す。
export function parseShareKeyFromLocation(): string | null {
  const m = location.pathname.match(/^\/s\/([A-Za-z0-9_-]{1,64})\/?$/);
  return m ? m[1] : null;
}
