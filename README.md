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

## Walk a line / Pathfinder (v4.4+)
- Interactive map: **Set start** / **Set end** / **Pan** — tap to place endpoints.
- **My location**, **Copy my GPS**, save GPS/start/end as labeled waypoints.
- **Saved points** sheet: rename, delete, copy WGS84 (and Lo if stored), use as start/end.
- Manual WGS84 / Lo entry and guidance (Directions vs Straight line) unchanged.

## Offline maps (v4.3+)
- Basemap tiles use **CartoCDN Voyager** (OSM data) with disk cache (~60 days).
- On any plot/path map, tap **Download map** to prefetch tiles for the current area (padded bbox, z12–16, capped).
- Prefer this over bulk OpenStreetMap tile scraping. Attribution: © OpenStreetMap / CARTO.
- Google Maps is optional (`MAPS_API_KEY` in `android/local.properties` + `--dart-define`); without a key the app shows an in-app dialog and keeps the offline basemap.

## Application ID
Left as `com.example.botswana_plot_finder` to avoid breaking sideload upgrades. userAgent uses `com.pathfinder.sadc`.

