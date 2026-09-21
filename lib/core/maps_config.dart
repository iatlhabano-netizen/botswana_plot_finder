/// Google Maps API key configuration.
///
/// Android native key (required for google_maps_flutter tiles):
///   Add to android/local.properties:
///     MAPS_API_KEY=your_key_here
///   It is injected into AndroidManifest via build.gradle manifestPlaceholders.
///
/// Flutter-side awareness (chooses Google Maps vs OSM fallback):
///   Pass the same value at build time:
///     flutter build apk --dart-define=MAPS_API_KEY=your_key_here
///   Or leave empty — the app falls back to Offline OSM (flutter_map).
///
/// Do NOT commit real API keys. Never invent secrets.
class MapsConfig {
  static const String apiKey =
      String.fromEnvironment('MAPS_API_KEY', defaultValue: '');

  /// True when a non-empty key was supplied via --dart-define.
  static bool get isGoogleMapsConfigured => apiKey.trim().isNotEmpty;

  /// Preference key for forcing OSM even when a Google key exists (offline bush).
  static const preferOsmKey = 'prefer_osm_map';
}
