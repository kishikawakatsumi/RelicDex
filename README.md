# RelicForge

[![Available on the App Store](https://img.shields.io/badge/Download-App_Store-0a84ff)](https://apps.apple.com/us/app/relicforge/id6765926303)

Scan, catalog, and forge builds from your *Elden Ring Nightreign* relic
collection — powered by on-device OCR.

Point your iPhone at the relic detail panel on the in-game screen and
RelicForge reads the effects, color, size, and depth right off the screen
and turns them into a searchable, build-able local collection.

- **App Store** — <https://apps.apple.com/us/app/relicforge/id6765926303>
- **Web companion** — <https://relicforge.pages.dev>

## Features

- 📷 **Camera-based recognition.** Live OCR using Apple's Vision framework
  recognizes relic titles and effects from the in-game screen. No manual
  entry, no internet required.
- 🗂 **Collection.** Filter by color, size, depth, or effect; sort by
  registered order, size, or color; mark favorites.
- 🏗 **Build planner.** Pick a Nightfarer and a vessel. Slots only accept
  relics that fit the vessel's color and depth (whites accept any color);
  effects are aggregated into a per-build summary.
- 🔗 **Share via URL.** Export your collection and builds as a
  `.relicforge` file or a short share URL backed by Cloudflare R2; the web
  companion lets non-iOS users view shared payloads in the browser.
- 🌐 **Localized.** UI in English / Japanese; effect text follows the
  scanned game's language regardless of device locale.

## Project layout

```
RelicForge/         iOS app (SwiftUI + SwiftData, iOS 17.6+)
  Models/           SwiftData @Models (StoredRelic, StoredBuild, ...)
  Views/            All SwiftUI views (Collection, BuildEditor, Capture, ...)
  Services/         OCR, recognizer, repository, share, master loaders
  Resources/        Bundled JSON masters (effects, unique relics, vessels, ...)
  Localizable.xcstrings  String catalog (JA/EN)

web/                Web companion (Vite + React 19 + TypeScript)
  src/              SPA source
  functions/        Cloudflare Pages Functions (share API + OGP)
  public/master/    Same JSON masters as the iOS bundle (regenerated together)

scripts/            Master regeneration (Python; reads TSV, writes both
                    RelicForge/Resources/*.json and web/public/master/*.json)

.github/workflows/  CI: deploy `web/` to Cloudflare Pages on push to main
```

## iOS

Open `RelicForge.xcodeproj` in Xcode 26+ and run the `RelicForge` scheme on
an iPhone or the simulator. Deployment target: iOS 17.6+.

The simulator branch in `RelicCaptureView` falls back to a bundled sample
image (`sample_relic.png`) when no real camera is available, so the scan
flow is testable end-to-end on the simulator for screenshots.

## Web

```sh
cd web
npm install
npm run dev          # local dev server
npm run build        # type-check + Vite build
npm run deploy       # wrangler pages deploy ./dist
```

Pushes to `main` that touch `web/**` are auto-deployed via
`.github/workflows/deploy-web.yml` (requires `CLOUDFLARE_API_TOKEN` and
`CLOUDFLARE_ACCOUNT_ID` repository secrets).

## Master data

`scripts/generate_master.py` reads the source TSV files (kept locally,
not committed), normalizes / de-duplicates effects, derives a category
key per row, and writes:

- `RelicForge/Resources/effects.json`
- `RelicForge/Resources/unique_relics.json`
- `RelicForge/Resources/title_words.json` (etc.)
- `web/public/master/*.json` (same content for the web companion)

Effect IDs are content-stable hashes (`e_{sha256[:8]}`) so re-runs do not
shift IDs already stored in the SwiftData database.

## License

[CC0 1.0 Universal](LICENSE) — dedicated to the public domain. No rights
reserved; use, modify, and redistribute freely.
