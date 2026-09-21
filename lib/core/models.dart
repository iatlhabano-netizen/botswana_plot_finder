import 'package:latlong2/latlong.dart' as ll;

class GeoPoint {
  final ll.LatLng wgs84;
  final String label;
  final double? loWesting;
  final double? loSouthing;

  const GeoPoint({
    required this.wgs84,
    required this.label,
    this.loWesting,
    this.loSouthing,
  });

  double get latitude => wgs84.latitude;
  double get longitude => wgs84.longitude;
}

class PathEndpoints {
  final GeoPoint start;
  final GeoPoint end;
  const PathEndpoints({required this.start, required this.end});
}

class ParsedLoPair {
  final double westing;
  final double southing;
  const ParsedLoPair({required this.westing, required this.southing});
}
