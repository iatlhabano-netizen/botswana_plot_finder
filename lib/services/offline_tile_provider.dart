import 'dart:ui' show Codec, ImmutableBuffer;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_map/flutter_map.dart';

/// TileProvider that caches OSM tiles to disk via flutter_cache_manager.
class OfflineTileProvider extends TileProvider {
  static final CacheManager _defaultCache = CacheManager(
    Config(
      'plot_finder_tiles',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 10000,
    ),
  );

  final CacheManager _cacheManager;

  OfflineTileProvider({CacheManager? cacheManager})
      : _cacheManager = cacheManager ?? _defaultCache;

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
