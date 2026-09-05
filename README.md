# Plot Finder — SADC Multi-Country Land Coordinate Tool

Offline-first Flutter app for Android: convert Gauss Conform Lo coordinates to WGS84, scan Land Board certificates via OCR, plot boundaries on an interactive map with area in hectares, and follow cutlines in the bush with real-time GPS cross-track error guidance.

## Supported Countries & Datums

| Country | System / Datum | Central Meridians |
|---|---|---|
| Botswana | Cape Datum (Clarke 1880), BTRS02 / WGS84 | Lo21–Lo29 |
| South Africa | Hartebeesthoek94 (Modern), Cape Datum (Legacy) | Lo17–Lo33 |
| Namibia | Schwarzeck (Bessel 1841) | Lo11–Lo19 |
| Zimbabwe | Arc 1950 (Clarke 1880 Modified) | Lo27–Lo33 |
| Eswatini | Cape Datum (Clarke 1880) | Lo31 |
| Lesotho | Cape Datum (Clarke 1880) | Lo27–Lo29 |

## Features
- **Lo → WGS84 conversion** — multi-country, multi-datum, dynamic zone selection
- **On-device OCR** certificate scanning (ML Kit)
- **Interactive map** with polygon display, area in hectares, corner inspection + Google Maps nav
- **Bush navigation** with real-time cross-track error guidance (VEER LEFT / VEER RIGHT)

## Build
```bash
flutter pub get
flutter run
```
