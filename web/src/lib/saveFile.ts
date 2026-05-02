// 編集後の ExportPayload を `.relicforge` (raw deflate 圧縮 JSON) として
// ブラウザからダウンロードさせる。iOS 側 (`RelicExportService.swift`) と同じ形式。

import type { ExportPayload } from "../types/export";

export async function downloadRelicForgeFile(
  payload: ExportPayload,
  filename: string = makeFilename(),
): Promise<void> {
  // iOS と同様に prettyPrint なしの最小 JSON
  const json = JSON.stringify(payload);
  const stream = new Response(json).body!.pipeThrough(
    new CompressionStream("deflate-raw"),
  );
  const blob = await new Response(stream).blob();
  const url = URL.createObjectURL(blob);
  try {
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
  } finally {
    URL.revokeObjectURL(url);
  }
}

function makeFilename(): string {
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  const stamp =
    `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}` +
    `-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
  return `RelicForge-${stamp}.relicforge`;
}
