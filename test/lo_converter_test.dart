import 'package:flutter_test/flutter_test.dart';
import 'package:botswana_plot_finder/core/lo_converter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'dart:math' as math;

/// Golden / control cases for Lo ↔ WGS84.
///
/// Assumptions:
/// - Sample plot is a near-rectangle near Lo25 Cape Datum (Botswana).
/// - Control corners match the in-app Sample button:
///     C1 Y=-74283 X=2609149 … C4 Y=-74279 X=2609469
/// - Round-trip tolerance: ~1–2 m in Lo metres; ~1e-5 deg in lat/lon
///   (proj4dart + Cape towgs84 parameters).
/// - Absolute WGS84 for C1 is a documented snapshot of this converter —
///   if you change datum defs, update these goldens deliberately.
///
/// v4.6.3: bw_cape restored to Pathfinder/Land Board default
/// (-87,-105,-189). v4.6.2 wrongly used SA Cape 1128 (-136,-108,-292).
/// New bw_arcgis = Esri WKID 1114 / EPSG:1114 (-138,-105,-289).
void main() {
  const zone = 25;
  const datum = 'bw_cape';

  // Sample plot corners (Lo metres)
  const sample = [
    (-74283.0, 2609149.0),
    (-74593.0, 2609153.0),
    (-74589.0, 2609473.0),
    (-74279.0, 2609469.0),
  ];

  test('sample C1 converts to documented WGS84 (BW Lo25 Cape)', () {
    final pt = LoConverter.toWgs84(
      westing: sample[0].$1,
      southing: sample[0].$2,
      zone: zone,
      datumKey: datum,
    );
    // Snapshot golden — southern Botswana / greater Gaborone belt
    expect(pt.latitude, closeTo(-23.58, 0.5));
    expect(pt.longitude, closeTo(25.72, 0.5));
    // Tighter golden after restoring Land Board Cape (-87,-105,-189)
    expect(pt.latitude, closeTo(-23.583370327700585, 1e-7));
    expect(pt.longitude, closeTo(25.727130120587024, 1e-7));
  });

  test('round-trip Lo → WGS84 → Lo preserves metres (~2 m)', () {
    for (final (y, x) in sample) {
      final wgs = LoConverter.toWgs84(
        westing: y,
        southing: x,
        zone: zone,
        datumKey: datum,
      );
      final back = LoConverter.fromWgs84(wgs, zone: zone, datumKey: datum);
      expect(back.westing, closeTo(y, 2.0),
          reason: 'Y round-trip for $y/$x');
      expect(back.southing, closeTo(x, 2.0),
          reason: 'X round-trip for $y/$x');
    }
  });

  test('bw_arcgis Arc1950→WGS84 WKID 1114 sample + round-trip', () {
    final pt = LoConverter.toWgs84(
      westing: -74283.0,
      southing: 2609149.0,
      zone: zone,
      datumKey: 'bw_arcgis',
    );
    expect(pt.latitude, closeTo(-23.584363799042357, 1e-7));
    expect(pt.longitude, closeTo(25.727347001501972, 1e-7));
    for (final (y, x) in sample) {
      final wgs = LoConverter.toWgs84(
        westing: y,
        southing: x,
        zone: zone,
        datumKey: 'bw_arcgis',
      );
      final back =
          LoConverter.fromWgs84(wgs, zone: zone, datumKey: 'bw_arcgis');
      expect(back.westing, closeTo(y, 2.0));
      expect(back.southing, closeTo(x, 2.0));
    }
  });

  test('BTRS02 / WGS84 Lo is near identity near central meridian', () {
    // A point on CM Lo25, mid-latitude
    final pt = const ll.LatLng(-24.0, 25.0);
    final lo = LoConverter.fromWgs84(pt, zone: 25, datumKey: 'bw_btrs02');
    // On the CM, westing ≈ 0
    expect(lo.westing.abs(), lessThan(5.0));
    final back = LoConverter.toWgs84(
      westing: lo.westing,
      southing: lo.southing,
      zone: 25,
      datumKey: 'bw_btrs02',
    );
    expect(back.latitude, closeTo(pt.latitude, 1e-5));
    expect(back.longitude, closeTo(pt.longitude, 1e-5));
  });

  test('validateLo flags wild westing / southing', () {
    expect(LoConverter.validateLo(700000, 2600000), isNotNull);
    expect(LoConverter.validateLo(-74283, 100), isNotNull);
    expect(LoConverter.validateLo(-74283, 2609149), isNull);
    // LO25-magnitude westing (~255 km) and negative certificate X
    expect(LoConverter.validateLo(-255124, -7604978), isNull);
    expect(LoConverter.validateLo(-255124, 7604978), isNull);
  });

  test('ZA Hart94 round-trip sanity (Lo29-ish Gauteng belt)', () {
    // Arbitrary but plausible Lo29 Hart94 control near Johannesburg belt
    const y = -90000.0;
    const x = 2900000.0;
    final wgs = LoConverter.toWgs84(
      westing: y,
      southing: x,
      zone: 29,
      datumKey: 'za_hart94',
    );
    expect(wgs.latitude, inInclusiveRange(-35.0, -22.0));
    expect(wgs.longitude, inInclusiveRange(27.0, 32.0));
    final back =
        LoConverter.fromWgs84(wgs, zone: 29, datumKey: 'za_hart94');
    expect(back.westing, closeTo(y, 2.0));
    expect(back.southing, closeTo(x, 2.0));
  });

  test('za_cape stays SA EPSG/ArcGIS 1128 params', () {
    final pt = LoConverter.toWgs84(
      westing: -74283.0,
      southing: 2609149.0,
      zone: zone,
      datumKey: 'za_cape',
    );
    expect(pt.latitude, closeTo(-23.58438681951946, 1e-7));
    expect(pt.longitude, closeTo(25.727312019898676, 1e-7));
  });

  test('negative certificate X matches positive X (southern hemisphere)', () {
    final pos = LoConverter.toWgs84(
      westing: -74283.0,
      southing: 2609149.0,
      zone: zone,
      datumKey: datum,
    );
    final neg = LoConverter.toWgs84(
      westing: -74283.0,
      southing: -2609149.0,
      zone: zone,
      datumKey: datum,
    );
    expect(neg.latitude, closeTo(pos.latitude, 1e-7));
    expect(neg.longitude, closeTo(pos.longitude, 1e-7));
    expect(neg.latitude, lessThan(0));

    final gisPos = LoConverter.toWgs84(
      westing: -74283.0,
      southing: 2609149.0,
      zone: zone,
      datumKey: 'bw_arcgis',
    );
    final gisNeg = LoConverter.toWgs84(
      westing: -74283.0,
      southing: -2609149.0,
      zone: zone,
      datumKey: 'bw_arcgis',
    );
    expect(gisNeg.latitude, closeTo(gisPos.latitude, 1e-7));
    expect(gisNeg.longitude, closeTo(gisPos.longitude, 1e-7));
  });

  test('Cape vs BNGRS02 horizontal delta ~100–300 m at sample', () {
    final cape = LoConverter.toWgs84(
      westing: -74283.0,
      southing: 2609149.0,
      zone: zone,
      datumKey: 'bw_cape',
    );
    final gps = LoConverter.toWgs84(
      westing: -74283.0,
      southing: 2609149.0,
      zone: zone,
      datumKey: 'bw_btrs02',
    );
    final dLat = (cape.latitude - gps.latitude) * math.pi / 180;
    final dLon = (cape.longitude - gps.longitude) * math.pi / 180;
    final lat1 = cape.latitude * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(gps.latitude * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final metres = 2 * 6371000 * math.asin(math.sqrt(a));
    expect(metres, greaterThan(80));
    expect(metres, lessThan(400));
  });

  test('BW datum labels order: Cape, ArcGIS, BNGRS02', () {
    final d = LoConverter.availableDatums('BW');
    expect(d.length, 3);
    expect(d[0].key, 'bw_cape');
    expect(d[0].label.contains('Land Board'), isTrue);
    expect(d[1].key, 'bw_arcgis');
    expect(d[1].label.contains('ArcGIS'), isTrue);
    expect(d[2].key, 'bw_btrs02');
    expect(d[2].label.contains('GPS'), isTrue);
  });
}
