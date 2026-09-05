import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

/// TileProvider that caches tiles to disk using flutter_cache_manager.
/// Tiles are fetched from OSM and stored locally for offline use.
class OfflineTileProvider extends TileProvider {
  static const _cacheDuration = Duration(days: 7);
  final CacheManager _cacheManager;

  OfflineTileProvider({CacheManager? cacheManager})
      : _cacheManager = cacheManager ??
            DefaultCacheManager(
              config: const Config(
                'plot_finder_tiles',
                stalePeriod: _cacheDuration,
                maxNrOfCacheObjects: 10000,
              ),
            );

  @override
  ImageProvider<Object> getImage(TileImageRequest coordinates, ImageProvider? fallback) {
    final url = coordinates.url;
    if (url.isEmpty) return super.getImage(coordinates, fallback);

    return OfflineTileImageProvider(
      url: url,
      cacheManager: _cacheManager,
    );
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
      codec: () async {
        final file = await cacheManager.getSingleFile(key.url);
        if (file.existsSync()) {
          final bytes = await file.readAsBytes();
          return decode(bytes);
        }
        // Fallback: fetch from network and cache
        final response = await http.get(Uri.parse(key.url));
        if (response.statusCode == 200) {
          await cacheManager.putFile(
            key.url,
            response.bodyBytes,
            fileExtension: 'png',
          );
          return decode(Uint8List.fromList(response.bodyBytes));
        }
        throw StateError('Failed to load tile: ${key.url}');
      }(),
      informationCollector: () => [
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('Image URL', key.url),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineTileImageProvider && url == other.url);

  @override
  int get hashCode => url.hashCode;
}
