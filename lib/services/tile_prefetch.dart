import 'dart:math';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;

/// Offline map download for a bounding box.
///
/// Tile source: CartoCDN Voyager (raster). Chosen instead of bulk OSM tile
/// scraping — Carto's basemap CDN is commonly used for cached field apps;
/// we still attribute OpenStreetMap data. User-Agent identifies Pathfinder.
///
/// Stale period is managed by OfflineTileProvider (60 days).
class TilePrefetch {
  /// Same cache key as OfflineTileProvider so downloaded tiles are reused.
  static final CacheManager cache = CacheManager(
    Config(
      'plot_finder_tiles',
      stalePeriod: const Duration(days: 60),
      maxNrOfCacheObjects: 25000,
    ),
  );

  static const tileUrlTemplate =
      'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

  static const userAgent = 'PathfinderSADC/4.3 (com.pathfinder.sadc; field-offline)';

  /// Pad plot/path bounds by [padKm] and prefetch z=[minZoom]..[maxZoom].
  static Future<TilePrefetchResult> downloadRegion({
    required List<ll.LatLng> points,
    double padKm = 1.5,
    int minZoom = 12,
    int maxZoom = 16,
    void Function(int done, int total)? onProgress,
  }) async {
    if (points.isEmpty) {
      return const TilePrefetchResult(0, 0, 'No points to cover.');
    }
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLon = points.first.longitude, maxLon = points.first.longitude;
    for (final p in points) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLon = min(minLon, p.longitude);
      maxLon = max(maxLon, p.longitude);
    }
    // ~1° lat ≈ 111 km
    final padDeg = padKm / 111.0;
    minLat -= padDeg;
    maxLat += padDeg;
    minLon -= padDeg / max(0.2, cos(minLat * pi / 180));
    maxLon += padDeg / max(0.2, cos(minLat * pi / 180));

    final urls = <String>[];
    for (var z = minZoom; z <= maxZoom; z++) {
      final x0 = _lon2tile(minLon, z);
      final x1 = _lon2tile(maxLon, z);
      final y0 = _lat2tile(maxLat, z);
      final y1 = _lat2tile(minLat, z);
      for (var x = x0; x <= x1; x++) {
        for (var y = y0; y <= y1; y++) {
          urls.add(tileUrlTemplate
              .replaceAll('{z}', '$z')
              .replaceAll('{x}', '$x')
              .replaceAll('{y}', '$y'));
        }
      }
    }

    // Cap to avoid accidental huge downloads
    const hardCap = 2500;
    final capped = urls.length > hardCap;
    final list = capped ? urls.sublist(0, hardCap) : urls;

    var ok = 0;
    var fail = 0;
    final client = http.Client();
    try {
      for (var i = 0; i < list.length; i++) {
        final url = list[i];
        try {
          final resp = await client.get(
            Uri.parse(url),
            headers: {'User-Agent': userAgent},
          );
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            await cache.putFile(
              url,
              resp.bodyBytes,
              fileExtension: 'png',
              maxAge: const Duration(days: 60),
            );
            ok++;
          } else {
            fail++;
          }
        } catch (_) {
          fail++;
        }
        onProgress?.call(i + 1, list.length);
        // Gentle pacing for CDN
        if (i % 8 == 7) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }
    } finally {
      client.close();
    }

    final note = capped
        ? 'Capped at $hardCap tiles (zoom $minZoom–$maxZoom). Zoom out less or smaller area next time.'
        : 'Tiles cached for ~60 days (CartoCDN Voyager / OSM data).';
    return TilePrefetchResult(ok, fail, note);
  }

  static int _lon2tile(double lon, int z) =>
      ((lon + 180.0) / 360.0 * (1 << z)).floor();

  static int _lat2tile(double lat, int z) {
    final latRad = lat * pi / 180;
    return ((1.0 -
                log(tan(latRad) + 1.0 / cos(latRad)) / pi) /
            2.0 *
            (1 << z))
        .floor();
  }
}

class TilePrefetchResult {
  final int saved;
  final int failed;
  final String note;
  const TilePrefetchResult(this.saved, this.failed, this.note);
}
