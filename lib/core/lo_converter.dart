import 'package:latlong2/latlong.dart' as ll;
import 'package:proj4dart/proj4dart.dart' as proj4;

class CountrySystem {
  final String id;
  final String label;
  final List<int> availableZones;
  final String defaultDatum;
  const CountrySystem({
    required this.id,
    required this.label,
    required this.availableZones,
    required this.defaultDatum,
  });
}

class DatumOption {
  final String key;
  final String label;
  const DatumOption({required this.key, required this.label});
}

/// Gauss Conform (Lo) ↔ WGS84 converter for SADC countries.
/// Math preserved from prior releases — do not regress.
class LoConverter {
  static final Map<String, proj4.Projection> _cache = {};

  /// Plausible |southing| (X) for SADC Lo certificates (metres from equator).
  static const double minSouthingAbs = 1e6;
  static const double maxSouthingAbs = 9.5e6;

  /// Plausible |westing| (Y) from zone central meridian (metres).
  static const double maxWestingAbs = 6e5;

  static const List<CountrySystem> supportedCountries = [
    CountrySystem(id: 'BW', label: 'Botswana', availableZones: [21, 23, 25, 27, 29], defaultDatum: 'bw_cape'),
    CountrySystem(id: 'ZA', label: 'South Africa', availableZones: [17, 19, 21, 23, 25, 27, 29, 31, 33], defaultDatum: 'za_hart94'),
    CountrySystem(id: 'NA', label: 'Namibia', availableZones: [11, 13, 15, 17, 19], defaultDatum: 'na_schwarzeck'),
    CountrySystem(id: 'ZW', label: 'Zimbabwe', availableZones: [27, 29, 31, 33], defaultDatum: 'zw_arc1950'),
    CountrySystem(id: 'SZ', label: 'Eswatini', availableZones: [31], defaultDatum: 'sz_cape'),
    CountrySystem(id: 'LS', label: 'Lesotho', availableZones: [27, 29], defaultDatum: 'ls_cape'),
  ];

  static List<DatumOption> availableDatums(String countryCode) {
    switch (countryCode) {
      case 'ZA':
        return const [
          DatumOption(key: 'za_hart94', label: 'Hartebeesthoek94 (Modern)'),
          DatumOption(key: 'za_cape', label: 'Cape Datum (Legacy)'),
        ];
      case 'NA':
        return const [DatumOption(key: 'na_schwarzeck', label: 'Schwarzeck (Bessel 1841)')];
      case 'ZW':
        return const [DatumOption(key: 'zw_arc1950', label: 'Arc 1950')];
      case 'SZ':
        return const [DatumOption(key: 'sz_cape', label: 'Cape Datum')];
      case 'LS':
        return const [DatumOption(key: 'ls_cape', label: 'Cape Datum')];
      default:
        return const [
          DatumOption(key: 'bw_cape', label: 'Cape / BTRS (Land Board Lo)'),
          DatumOption(key: 'bw_btrs02', label: 'BNGRS02 / WGS84 (GPS)'),
        ];
    }
  }

  /// Certificates often print negative X (southing). For Lo magnitudes in the
  /// SADC range, use absolute southing so the projection stays in the southern
  /// hemisphere. Westing sign is preserved (negative Y = east of CM).
  static double normalizeSouthing(double southing) {
    final a = southing.abs();
    if (a >= minSouthingAbs && a <= maxSouthingAbs) return a;
    return southing;
  }

  static String _def(int zone, String dk) {
    switch (dk) {
      case 'za_hart94':
      case 'bw_btrs02':
      case 'wgs84':
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs';
      case 'za_cape':
      case 'sz_cape':
      case 'ls_cape':
      case 'bw_cape':
        // EPSG Cape → WGS84 Helmert (same as ZA Cape / EPSG:4222→4326 common params)
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 +a=6378249.145 +rf=293.4663076563986 +towgs84=-136,-108,-292,0,0,0,0 +units=m +no_defs';
      case 'na_schwarzeck':
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 +ellps=bessel +towgs84=616,97,-251,0,0,0,0 +units=m +no_defs';
      case 'zw_arc1950':
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 +a=6378249.145 +rf=293.4663076563986 +towgs84=-142.5,-96.2,-291.6,0,0,0,0 +units=m +no_defs';
      default:
        // Fallback: same EPSG Cape Helmert as bw_cape / za_cape
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 +a=6378249.145 +rf=293.4663076563986 +towgs84=-136,-108,-292,0,0,0,0 +units=m +no_defs';
    }
  }

  static ll.LatLng toWgs84({
    required double westing,
    required double southing,
    required int zone,
    required String datumKey,
  }) {
    final x = normalizeSouthing(southing);
    final k = 'LO${zone}_$datumKey';
    final src = _cache.putIfAbsent(k, () => proj4.Projection.add(k, _def(zone, datumKey)));
    final out = src.transform(
      proj4.Projection.get('EPSG:4326')!,
      proj4.Point(x: -westing, y: -x),
    );
    return ll.LatLng(out.y, out.x);
  }

  static ({double westing, double southing}) fromWgs84(
    ll.LatLng point, {
    required int zone,
    required String datumKey,
  }) {
    final k = 'LO${zone}_$datumKey';
    final src = _cache.putIfAbsent(k, () => proj4.Projection.add(k, _def(zone, datumKey)));
    final out = proj4.Projection.get('EPSG:4326')!.transform(
      src,
      proj4.Point(x: point.longitude, y: point.latitude),
    );
    // Projection returns positive southing magnitude for southern latitudes.
    return (westing: -out.x, southing: normalizeSouthing(-out.y));
  }

  static String? validateLo(double westing, double southing) {
    final x = southing.abs();
    if (x < minSouthingAbs || x > maxSouthingAbs) {
      return 'X outside SADC range. Check zone/datum.';
    }
    if (westing.abs() > maxWestingAbs) {
      return 'Y >600 km from CM — check Lo zone.';
    }
    return null;
  }
}
