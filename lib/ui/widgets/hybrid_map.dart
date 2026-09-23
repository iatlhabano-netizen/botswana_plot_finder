import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart' as ll;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/maps_config.dart';
import '../../services/offline_tile_provider.dart';
import '../../services/tile_prefetch.dart';

class MapMarkerData {
  final ll.LatLng point;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const MapMarkerData({
    required this.point,
    required this.label,
    this.color = Colors.red,
    this.onTap,
  });
}


/// Imperative camera helpers for guidance recenter FAB.
class HybridMapController {
  void Function(ll.LatLng target, {double? zoom})? _move;
  void Function()? _fit;

  void _attach({
    required void Function(ll.LatLng target, {double? zoom}) move,
    required void Function() fit,
  }) {
    _move = move;
    _fit = fit;
  }

  void moveTo(ll.LatLng target, {double? zoom}) => _move?.call(target, zoom: zoom);

  void fitFeatures() => _fit?.call();
}

class HybridMap extends StatefulWidget {
  final ll.LatLng center;
  final double initialZoom;
  final List<ll.LatLng> polygon;
  final List<ll.LatLng> polyline;
  final List<MapMarkerData> markers;
  final ll.LatLng? userLocation;
  final void Function(ll.LatLng)? onTap;
  final bool showOfflineBanner;
  final bool fitToFeatures;
  final bool showDownloadButton;
  /// GPS accuracy circle radius around [userLocation] (metres).
  final double? accuracyM;
  /// Optional second polyline (e.g. user → foot of perpendicular).
  final List<ll.LatLng> secondaryPolyline;
  /// Corridor / overlay polygon colours (default plot green).
  final Color polygonStroke;
  final Color polygonFill;
  /// When false, centre/user updates never re-fit the camera (guidance mode).
  final bool refitOnUpdate;
  /// Optional controller for recenter FAB.
  final HybridMapController? controller;

  const HybridMap({
    super.key,
    required this.center,
    this.initialZoom = 15,
    this.polygon = const [],
    this.polyline = const [],
    this.markers = const [],
    this.userLocation,
    this.onTap,
    this.showOfflineBanner = true,
    this.fitToFeatures = true,
    this.showDownloadButton = true,
    this.accuracyM,
    this.secondaryPolyline = const [],
    this.polygonStroke = const Color(0xFF0B6E4F),
    this.polygonFill = const Color(0xFF0B6E4F),
    this.refitOnUpdate = true,
    this.controller,
  });

  @override
  State<HybridMap> createState() => _HybridMapState();
}

class _HybridMapState extends State<HybridMap> {
  bool _preferOsm = false;
  bool _loaded = false;
  bool _fitted = false;
  bool _downloading = false;
  gmaps.GoogleMapController? _gCtrl;
  final MapController _osmCtrl = MapController();

  bool get _useGoogle =>
      MapsConfig.isGoogleMapsConfigured && !_preferOsm;

  List<ll.LatLng> get _allPoints {
    final pts = <ll.LatLng>[
      ...widget.polygon,
      ...widget.polyline,
      ...widget.markers.map((m) => m.point),
    ];
    if (widget.userLocation != null) pts.add(widget.userLocation!);
    return pts;
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(move: _moveTo, fit: _forceFit);
    _loadPref();
  }

  @override
  void didUpdateWidget(covariant HybridMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      widget.controller?._attach(move: _moveTo, fit: _forceFit);
    }
    final markersChanged = oldWidget.markers.length != widget.markers.length ||
        !_samePoints(
          oldWidget.markers.map((m) => m.point).toList(),
          widget.markers.map((m) => m.point).toList(),
        );
    final pathChanged = oldWidget.polygon != widget.polygon ||
        oldWidget.polyline != widget.polyline ||
        markersChanged;
    // Only re-fit when path features change — never on every GPS centre tick.
    if (widget.refitOnUpdate && pathChanged) {
      _fitted = false;
      if (!_useGoogle) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitOsm());
      } else {
        _fitGoogle();
      }
    }
  }

  void _forceFit() {
    _fitted = false;
    if (!_useGoogle) {
      _fitOsm();
    } else {
      _fitGoogle();
    }
  }

  void _moveTo(ll.LatLng target, {double? zoom}) {
    if (_useGoogle) {
      _gCtrl?.animateCamera(
        gmaps.CameraUpdate.newLatLngZoom(
          gmaps.LatLng(target.latitude, target.longitude),
          zoom ?? widget.initialZoom,
        ),
      );
    } else {
      _osmCtrl.move(target, zoom ?? _osmCtrl.camera.zoom);
    }
  }

  Future<void> _loadPref() async {
    final sp = await SharedPreferences.getInstance();
    setState(() {
      _preferOsm = sp.getBool(MapsConfig.preferOsmKey) ?? false;
      _loaded = true;
    });
  }

  Future<void> setPreferOsm(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(MapsConfig.preferOsmKey, v);
    setState(() {
      _preferOsm = v;
      _fitted = false;
    });
  }

  LatLngBounds? _boundsOf(List<ll.LatLng> pts) {
    if (pts.length < 2) return null;
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLon = pts.first.longitude, maxLon = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    // Pad slightly
    final dLat = (maxLat - minLat).abs() * 0.15 + 0.0005;
    final dLon = (maxLon - minLon).abs() * 0.15 + 0.0005;
    return LatLngBounds(
      ll.LatLng(minLat - dLat, minLon - dLon),
      ll.LatLng(maxLat + dLat, maxLon + dLon),
    );
  }

  void _fitOsm() {
    if (!widget.fitToFeatures || _fitted) return;
    final b = _boundsOf(_allPoints);
    if (b == null) return;
    try {
      _osmCtrl.fitCamera(
        CameraFit.bounds(bounds: b, padding: const EdgeInsets.all(36)),
      );
      _fitted = true;
    } catch (_) {}
  }

  Future<void> _fitGoogle() async {
    if (!widget.fitToFeatures || _fitted || _gCtrl == null) return;
    final pts = _allPoints;
    if (pts.length < 2) return;
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLon = pts.first.longitude, maxLon = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLon) minLon = p.longitude;
      if (p.longitude > maxLon) maxLon = p.longitude;
    }
    try {
      await _gCtrl!.animateCamera(
        gmaps.CameraUpdate.newLatLngBounds(
          gmaps.LatLngBounds(
            southwest: gmaps.LatLng(minLat, minLon),
            northeast: gmaps.LatLng(maxLat, maxLon),
          ),
          48,
        ),
      );
      _fitted = true;
    } catch (_) {}
  }


  bool _samePoints(List<ll.LatLng> a, List<ll.LatLng> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].latitude != b[i].latitude ||
          a[i].longitude != b[i].longitude) {
        return false;
      }
    }
    return true;
  }

  Future<void> _downloadArea() async {
    final pts = _allPoints;
    if (pts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to download yet — add a plot or path.')),
      );
      return;
    }
    setState(() => _downloading = true);
    try {
      final result = await TilePrefetch.downloadRegion(
        points: pts,
        onProgress: (done, total) {
          // quiet — snack at end
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Downloaded ${result.saved} map tiles'
            '${result.failed > 0 ? " (${result.failed} failed)" : ""}. '
            '${result.note}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Map download failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _showMissingKeyDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Google Maps not configured'),
        content: const Text(
          'No Google Maps API key is set for this build. '
          'Pathfinder uses the offline-friendly Carto/OSM basemap instead. '
          'Coordinates, Locate guidance, and external map links still work.\n\n'
          'To enable Google tiles, add MAPS_API_KEY to android/local.properties '
          'and rebuild with --dart-define=MAPS_API_KEY=…',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        if (_useGoogle) _buildGoogle() else _buildOsm(),
        if (widget.showOfflineBanner)
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: _MapModeBanner(
              usingGoogle: _useGoogle,
              hasKey: MapsConfig.isGoogleMapsConfigured,
              onToggleOsm: () => setPreferOsm(!_preferOsm),
              onMissingKey: _showMissingKeyDialog,
            ),
          ),
        if (widget.showDownloadButton)
          Positioned(
            bottom: 12,
            right: 12,
            child: FloatingActionButton.extended(
              heroTag: 'download_tiles',
              onPressed: _downloading ? null : _downloadArea,
              icon: _downloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_for_offline),
              label: Text(_downloading ? 'Saving…' : 'Download map'),
            ),
          ),
      ],
    );
  }

  Widget _buildGoogle() {
    final poly = widget.polygon.length >= 3
        ? {
            gmaps.Polygon(
              polygonId: const gmaps.PolygonId('plot'),
              points: widget.polygon
                  .map((p) => gmaps.LatLng(p.latitude, p.longitude))
                  .toList(),
              strokeWidth: 2,
              strokeColor: widget.polygonStroke,
              fillColor: widget.polygonFill.withValues(alpha: 0.18),
            )
          }
        : <gmaps.Polygon>{};

    final line = <gmaps.Polyline>{};
    if (widget.polyline.length >= 2) {
      line.add(gmaps.Polyline(
        polylineId: const gmaps.PolylineId('path'),
        points: widget.polyline
            .map((p) => gmaps.LatLng(p.latitude, p.longitude))
            .toList(),
        width: 5,
        color: const Color(0xFFE85D04),
      ));
    }
    if (widget.secondaryPolyline.length >= 2) {
      line.add(gmaps.Polyline(
        polylineId: const gmaps.PolylineId('xt'),
        points: widget.secondaryPolyline
            .map((p) => gmaps.LatLng(p.latitude, p.longitude))
            .toList(),
        width: 3,
        color: const Color(0xFF58B6E8),
        patterns: [gmaps.PatternItem.dash(12), gmaps.PatternItem.gap(8)],
      ));
    }

    final circles = <gmaps.Circle>{};
    if (widget.userLocation != null &&
        widget.accuracyM != null &&
        widget.accuracyM! > 0) {
      circles.add(gmaps.Circle(
        circleId: const gmaps.CircleId('acc'),
        center: gmaps.LatLng(
          widget.userLocation!.latitude,
          widget.userLocation!.longitude,
        ),
        radius: widget.accuracyM!,
        strokeWidth: 1,
        strokeColor: const Color(0xFF58B6E8).withValues(alpha: 0.6),
        fillColor: const Color(0xFF58B6E8).withValues(alpha: 0.1),
      ));
    }

    final markers = <gmaps.Marker>{};
    for (var i = 0; i < widget.markers.length; i++) {
      final m = widget.markers[i];
      markers.add(
        gmaps.Marker(
          markerId: gmaps.MarkerId('m$i'),
          position: gmaps.LatLng(m.point.latitude, m.point.longitude),
          infoWindow: gmaps.InfoWindow(title: m.label),
          onTap: m.onTap,
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            _hueFor(m.color),
          ),
        ),
      );
    }
    if (widget.userLocation != null) {
      markers.add(
        gmaps.Marker(
          markerId: const gmaps.MarkerId('me'),
          position: gmaps.LatLng(
            widget.userLocation!.latitude,
            widget.userLocation!.longitude,
          ),
          icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueAzure,
          ),
          infoWindow: const gmaps.InfoWindow(title: 'You'),
        ),
      );
    }

    return gmaps.GoogleMap(
      initialCameraPosition: gmaps.CameraPosition(
        target: gmaps.LatLng(widget.center.latitude, widget.center.longitude),
        zoom: widget.initialZoom,
      ),
      polygons: poly,
      polylines: line,
      circles: circles,
      markers: markers,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      mapType: gmaps.MapType.hybrid,
      onMapCreated: (c) {
        _gCtrl = c;
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitGoogle());
      },
      onTap: widget.onTap == null
          ? null
          : (p) => widget.onTap!(ll.LatLng(p.latitude, p.longitude)),
    );
  }

  Widget _buildOsm() {
    return FlutterMap(
      mapController: _osmCtrl,
      options: MapOptions(
        initialCenter: widget.center,
        initialZoom: widget.initialZoom,
        onMapReady: _fitOsm,
        onTap: widget.onTap == null
            ? null
            : (tap, latlng) => widget.onTap!(latlng),
      ),
      children: [
        TileLayer(
          urlTemplate: OfflineTileProvider.cartoVoyagerUrl,
          tileProvider: OfflineTileProvider(),
          userAgentPackageName: 'com.pathfinder.sadc',
        ),
        if (widget.polygon.length >= 3)
          PolygonLayer(polygons: [
            Polygon(
              points: widget.polygon,
              color: widget.polygonFill.withValues(alpha: 0.18),
              borderColor: widget.polygonStroke,
              borderStrokeWidth: 2,
            ),
          ]),
        if (widget.polyline.length >= 2 || widget.secondaryPolyline.length >= 2)
          PolylineLayer(polylines: [
            if (widget.polyline.length >= 2)
              Polyline(
                points: widget.polyline,
                color: const Color(0xFFE85D04),
                strokeWidth: 5,
              ),
            if (widget.secondaryPolyline.length >= 2)
              Polyline(
                points: widget.secondaryPolyline,
                color: const Color(0xFF58B6E8),
                strokeWidth: 3,
                strokeCap: StrokeCap.round,
              ),
          ]),
        if (widget.userLocation != null &&
            widget.accuracyM != null &&
            widget.accuracyM! > 0)
          CircleLayer(circles: [
            CircleMarker(
              point: widget.userLocation!,
              radius: widget.accuracyM!,
              useRadiusInMeter: true,
              color: const Color(0xFF58B6E8).withValues(alpha: 0.12),
              borderColor: const Color(0xFF58B6E8).withValues(alpha: 0.55),
              borderStrokeWidth: 1,
            ),
          ]),
        MarkerLayer(
          markers: [
            ...widget.markers.map(
              (m) => Marker(
                point: m.point,
                width: 72,
                height: 72,
                child: GestureDetector(
                  onTap: m.onTap,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.black26),
                        ),
                        child: Text(
                          m.label,
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Icon(Icons.location_pin, color: m.color, size: 34),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.userLocation != null)
              Marker(
                point: widget.userLocation!,
                width: 40,
                height: 40,
                child: const Icon(Icons.my_location,
                    color: Colors.blueAccent, size: 28),
              ),
          ],
        ),
        SimpleAttributionWidget(
          source: const Text('© OSM / CARTO'),
          onTap: () =>
              launchUrl(Uri.parse('https://openstreetmap.org/copyright')),
        ),
      ],
    );
  }

  double _hueFor(Color c) {
    if (c == Colors.green || c == Colors.greenAccent) {
      return gmaps.BitmapDescriptor.hueGreen;
    }
    if (c == Colors.orange || c == Colors.deepOrange) {
      return gmaps.BitmapDescriptor.hueOrange;
    }
    if (c == Colors.blue || c == Colors.blueAccent) {
      return gmaps.BitmapDescriptor.hueAzure;
    }
    return gmaps.BitmapDescriptor.hueRed;
  }
}

class _MapModeBanner extends StatelessWidget {
  final bool usingGoogle;
  final bool hasKey;
  final VoidCallback onToggleOsm;
  final VoidCallback onMissingKey;

  const _MapModeBanner({
    required this.usingGoogle,
    required this.hasKey,
    required this.onToggleOsm,
    required this.onMissingKey,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String title;
    String subtitle;
    if (usingGoogle) {
      title = 'Google Maps';
      subtitle = 'Tap to use offline cached basemap';
    } else if (!hasKey) {
      title = 'Offline basemap (Carto/OSM)';
      subtitle = 'No Google key — tap for details. Download map for bush use.';
    } else {
      title = 'Offline basemap (cached)';
      subtitle = 'Tap to switch to Google Maps';
    }

    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(10),
      color: cs.surface.withValues(alpha: 0.94),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: !hasKey && !usingGoogle
            ? onMissingKey
            : (hasKey || usingGoogle ? onToggleOsm : onMissingKey),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                usingGoogle ? Icons.map : Icons.offline_pin,
                color: cs.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
