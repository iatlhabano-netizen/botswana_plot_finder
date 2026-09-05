# Botswana Plot Finder

Offline-first Flutter app for Android: convert Lo coordinates, scan Land Board certificates via OCR, plot boundaries on a map, and follow cutlines in the bush.

## Features
- **Lo → WGS84 conversion** (Cape Datum / WGS84, zones Lo21–Lo29)
- **On-device OCR** certificate scanning (ML Kit)
- **Interactive map** with polygon display, area in hectares, and corner inspection
- **Bush navigation** with real-time cross-track error guidance (VEER LEFT / VEER RIGHT)

## Build
```bash
flutter pub get
flutter run
```
