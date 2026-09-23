# Pathfinder — SADC Plot & Bush Navigation

Offline-capable Flutter Android app for Botswana / SADC land work:

1. **Plot Finder** — Lo (Gauss Conform) → WGS84, certificate OCR, map corners, **Locate this corner** live guidance to a single pole  
2. **Pathfinder** — two endpoints (GPS / WGS84 / Lo), geodesic cutline, cross-track left/right guidance  
3. **Area Calculator** — dedicated Lo polygon area tool (hectares + m²)

## Google Maps API key (optional)

Do **not** invent or commit secrets. Without a key the app uses **cached OSM** (`flutter_map`) and still shows coordinates + “Open in Maps”.

### Android native key

In `android/local.properties` (local only, gitignored pattern):

```
MAPS_API_KEY=your_Maps_SDK_for_Android_key
```

`android/app/build.gradle` injects it into `AndroidManifest` as `com.google.android.geo.API_KEY`.

### Flutter-side (choose Google Maps vs OSM)

Pass the same value at build time:

```bash
flutter build apk --release --split-per-abi \
  --dart-define=MAPS_API_KEY="$(grep '^MAPS_API_KEY=' android/local.properties | cut -d= -f2-)"
```

If `MAPS_API_KEY` is empty, `HybridMap` defaults to offline-friendly OSM.

## Build

```bash
flutter pub get
flutter build apk --release --split-per-abi
```

## Countries / datums

Botswana, South Africa, Namibia, Zimbabwe, Eswatini, Lesotho — Cape / Hartebeesthoek94 / Schwarzeck / Arc 1950 / BTRS02 as applicable.

## Walk a line / Pathfinder (v4.6+)
- **Stay-on-line rebuild**: geodesic/ENU cross-track (positive = RIGHT), multi-leg projector with switchCost (~2.5 m) + dwell (≥2 fixes), GPS ENU smoother, dual EMA, Schmitt ON LINE (enter ~0.85× / exit ~1.12× corridor).
- Corridor = max(user base, k×accuracy), user ±, clamped ~0.5–12 m; map **corridor polygon** + foot-of-perpendicular + accuracy circle.
- Guidance hero: **ON LINE / LEFT x.x m / RIGHT x.x m** + action subtitle, lateral **gauge**, progress with **bend ticks**, leg chip, stale-GPS banner, sunlight/high-contrast toggle, wakelock; compass optional/secondary.
- Map-first setup: Start → Add bend → End, length, **Walk the line**.

## Walk a line / Pathfinder (v4.5+)
- **Stay-on-line first** for laying water pipe, fence, or utilities — not primarily compass-to-end.
- Map: **Start** / **Add bend** / **End** / **Pan**. Multi-point paths (A → via → B).
- Prominent path length; primary CTA **Walk the line**.
- Guidance hero: huge **ON LINE** / **LEFT x.x m** / **RIGHT x.x m**, plus along-path progress and remaining distance.
- Corridor widens with GPS accuracy; optional ± corridor control.
- Typed WGS84 / Lo under **Advanced**. Saved points can be start / end / via.

## Offline maps (v4.3+)
- Basemap tiles use **CartoCDN Voyager** (OSM data) with disk cache (~60 days).
- On any plot/path map, tap **Download map** to prefetch tiles for the current area (padded bbox, z12–16, capped).
- Prefer this over bulk OpenStreetMap tile scraping. Attribution: © OpenStreetMap / CARTO.
- Google Maps is optional (`MAPS_API_KEY` in `android/local.properties` + `--dart-define`); without a key the app shows an in-app dialog and keeps the offline basemap.

## Application ID
Left as `com.example.botswana_plot_finder` to avoid breaking sideload upgrades. userAgent uses `com.pathfinder.sadc`.

