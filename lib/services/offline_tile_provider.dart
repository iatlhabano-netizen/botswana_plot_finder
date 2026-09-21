import 'dart:ui' show Codec, ImmutableBuffer;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_map/flutter_map.dart';

/// TileProvider that caches basemap tiles to disk via flutter_cache_manager.
///
/// Default display URL is CartoCDN Voyager (same as TilePrefetch) so
/// "Download map for this area" and on-view caching share one store.
/// OSM data © OpenStreetMap contributors; tiles © CARTO.
class OfflineTileProvider extends TileProvider {
  static const staleDays = 60;

  static final CacheManager defaultCache = CacheManager(
    Config(
      'plot_finder_tiles',
      stalePeriod: const Duration(days: staleDays),
      maxNrOfCacheObjects: 25000,
    ),
  );

  /// Offline-friendly raster basemap (prefer over bulk OSM tile scraping).
  static const cartoVoyagerUrl =
      'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

  final CacheManager _cacheManager;

  OfflineTileProvider({CacheManager? cacheManager})
      : _cacheManager = cacheManager ?? defaultCache;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return OfflineTileImageProvider(url: url, cacheManager: _cacheManager);
  }
}

class OfflineTileImageProvider extends ImageProvider<OfflineTileImageProvider> {
  final String url;
  final CacheManager cacheManager;

  const OfflineTileImageProvider({
    required this.url,
    required this.cacheManager,
  });

  @override
  Future<OfflineTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    OfflineTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1.0,
      informationCollector: () => [
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('Image URL', key.url),
      ],
    );
  }

  Future<Codec> _load(
    OfflineTileImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final file = await key.cacheManager.getSingleFile(key.url);
    final bytes = await file.readAsBytes();
    final buffer = await ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineTileImageProvider && url == other.url);

  @override
  int get hashCode => url.hashCode;
}
