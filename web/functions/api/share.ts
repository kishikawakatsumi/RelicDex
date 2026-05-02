// POST /api/share — 任意のバイト列 (.relicforge ファイル) を受け取り R2 に保存して、
// 短い key を返す。受信側は GET /api/share/{key} で取り出す。

interface Env {
  SHARES: R2Bucket;
}

const MAX_SIZE = 1_000_000; // 1MB (現状 ~50KB なので余裕)

export const onRequestPost: PagesFunction<Env> = async ({ request, env }) => {
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (contentLength > MAX_SIZE) {
    return new Response("file too large", { status: 413 });
  }

  const data = await request.arrayBuffer();
  if (data.byteLength === 0) {
    return new Response("empty body", { status: 400 });
  }
  if (data.byteLength > MAX_SIZE) {
    return new Response("file too large", { status: 413 });
  }

  // 作成者のロケールを保存して OGP 生成時の言語選択に使う。
  // "ja-JP" 等が来ても主言語コードだけに丸める。未指定 / 不明なら "en"。
  const langHeader = request.headers.get("content-language") ?? "";
  const lang = langHeader.split(/[-,;]/)[0]?.trim().toLowerCase() || "en";

  const key = generateKey();
  await env.SHARES.put(key, data, {
    httpMetadata: { contentType: "application/octet-stream" },
    customMetadata: {
      uploadedAt: new Date().toISOString(),
      lang,
    },
  });

  return Response.json({ key }, {
    headers: { "Cache-Control": "no-store" },
  });
};

/// 22 文字の base64url ランダムキー (16 バイト = 128 bit エントロピー)。
function generateKey(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}
