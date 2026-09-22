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

/// User-saved labeled coordinate (Pathfinder waypoints).
class SavedWaypoint {
  final String id;
  final String label;
  final double lat;
  final double lng;
  final DateTime createdAt;
  final double? loY;
  final double? loX;
  final int? zone;
  final String? datum;

  const SavedWaypoint({
    required this.id,
    required this.label,
    required this.lat,
    required this.lng,
    required this.createdAt,
    this.loY,
    this.loX,
    this.zone,
    this.datum,
  });

  ll.LatLng get wgs84 => ll.LatLng(lat, lng);

  bool get hasLo => loY != null && loX != null;

  /// WGS84 copy string: `lat, lng`
  String get wgs84Copy =>
      '${lat.toStringAsFixed(7)}, ${lng.toStringAsFixed(7)}';

  /// Lo copy string when available.
  String? get loCopy {
    if (!hasLo) return null;
    final z = zone != null ? ' Lo$zone' : '';
    final d = (datum != null && datum!.isNotEmpty) ? ' ($datum)' : '';
    return 'Y ${loY!.toStringAsFixed(3)}, X ${loX!.toStringAsFixed(3)}$z$d';
  }

  SavedWaypoint copyWith({
    String? id,
    String? label,
    double? lat,
    double? lng,
    DateTime? createdAt,
    double? loY,
    double? loX,
    int? zone,
    String? datum,
  }) {
    return SavedWaypoint(
      id: id ?? this.id,
      label: label ?? this.label,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      createdAt: createdAt ?? this.createdAt,
      loY: loY ?? this.loY,
      loX: loX ?? this.loX,
      zone: zone ?? this.zone,
      datum: datum ?? this.datum,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'lat': lat,
        'lng': lng,
        'createdAt': createdAt.toIso8601String(),
        if (loY != null) 'loY': loY,
        if (loX != null) 'loX': loX,
        if (zone != null) 'zone': zone,
        if (datum != null) 'datum': datum,
      };

  factory SavedWaypoint.fromJson(Map<String, dynamic> json) {
    return SavedWaypoint(
      id: json['id'] as String,
      label: (json['label'] ?? 'Waypoint').toString(),
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      loY: (json['loY'] as num?)?.toDouble(),
      loX: (json['loX'] as num?)?.toDouble(),
      zone: (json['zone'] as num?)?.toInt(),
      datum: json['datum']?.toString(),
    );
  }
}
