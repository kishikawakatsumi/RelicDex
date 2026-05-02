// `.relicforge` ファイル (raw deflate 圧縮の JSON) を読み込む。
// iOS 側は `(json as NSData).compressed(using: .zlib)` を使っており、
// これは raw deflate (gzip / zlib ヘッダなし) を生成する。
// ブラウザでは `DecompressionStream("deflate-raw")` で解凍できる。

import type { ExportPayload } from "../types/export";

export async function loadRelicForgeFile(file: File): Promise<ExportPayload> {
  const buf = await file.arrayBuffer();
  const stream = new Response(buf).body!.pipeThrough(
    new DecompressionStream("deflate-raw"),
  );
  const text = await new Response(stream).text();
  return JSON.parse(text) as ExportPayload;
}
