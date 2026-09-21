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
          DatumOption(key: 'bw_cape', label: 'Cape Datum'),
          DatumOption(key: 'bw_btrs02', label: 'BTRS02 / WGS84'),
        ];
    }
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
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 +a=6378249.145 +rf=293.4663076563986 +towgs84=-136,-108,-292,0,0,0,0 +units=m +no_defs';
      case 'na_schwarzeck':
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 +ellps=bessel +towgs84=616,97,-251,0,0,0,0 +units=m +no_defs';
      case 'zw_arc1950':
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 +a=6378249.145 +rf=293.4663076563986 +towgs84=-142.5,-96.2,-291.6,0,0,0,0 +units=m +no_defs';
      default:
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 +a=6378249.145 +rf=293.4663076563986 +towgs84=-87,-105,-189,0,0,0,0 +units=m +no_defs';
    }
  }

  static ll.LatLng toWgs84({
    required double westing,
    required double southing,
    required int zone,
    required String datumKey,
  }) {
    final k = 'LO${zone}_$datumKey';
    final src = _cache.putIfAbsent(k, () => proj4.Projection.add(k, _def(zone, datumKey)));
    final out = src.transform(
      proj4.Projection.get('EPSG:4326')!,
      proj4.Point(x: -westing, y: -southing),
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
    return (westing: -out.x, southing: -out.y);
  }

  static String? validateLo(double westing, double southing) {
    if (southing < 1500000 || southing > 3200000) {
      return 'X outside SADC range. Check zone/datum.';
    }
    if (westing.abs() > 200000) {
      return 'Y >200 km from CM — check Lo zone.';
    }
    return null;
  }
}
