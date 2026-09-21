import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/lo_converter.dart';
import '../../core/distance_format.dart';
import '../../core/path_guidance.dart';
import '../../services/gps_service.dart';
import '../theme.dart';
import '../widgets/hybrid_map.dart';
import 'guidance_screen.dart';

enum _PointSource { gps, wgs84, lo }

class PathfinderScreen extends StatefulWidget {
  final ll.LatLng? initialStart;
  final ll.LatLng? initialEnd;
  final String? startLabel;
  final String? endLabel;

  const PathfinderScreen({
    super.key,
    this.initialStart,
    this.initialEnd,
    this.startLabel,
    this.endLabel,
  });

  @override
  State<PathfinderScreen> createState() => _PathfinderScreenState();
}

class _PathfinderScreenState extends State<PathfinderScreen> {
  _PointSource _startSrc = _PointSource.gps;
  _PointSource _endSrc = _PointSource.wgs84;

  final _startLat = TextEditingController();
  final _startLon = TextEditingController();
  final _endLat = TextEditingController();
  final _endLon = TextEditingController();
  final _startY = TextEditingController();
  final _startX = TextEditingController();
  final _endY = TextEditingController();
  final _endX = TextEditingController();

  int _zone = 25;
  String _datum = 'bw_cape';
  CountrySystem _country = LoConverter.supportedCountries.first;

  ll.LatLng? _gps;
  StreamSubscription<Position>? _gpsSub;
  String? _startName;
  String? _endName;

  @override
  void initState() {
    super.initState();
    _startName = widget.startLabel;
    _endName = widget.endLabel;
    if (widget.initialStart != null) {
      _startSrc = _PointSource.wgs84;
      _startLat.text = widget.initialStart!.latitude.toStringAsFixed(7);
      _startLon.text = widget.initialStart!.longitude.toStringAsFixed(7);
    }
    if (widget.initialEnd != null) {
      _endSrc = _PointSource.wgs84;
      _endLat.text = widget.initialEnd!.latitude.toStringAsFixed(7);
      _endLon.text = widget.initialEnd!.longitude.toStringAsFixed(7);
    }
    // GPS starts when user selects GPS source or taps locate — not in initState.
  }

  Future<void> _startGps() async {
    if (_gpsSub != null) return;
    if (!await GpsService.ensurePermission(context)) return;
    try {
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() => _gps = ll.LatLng(pos.latitude, pos.longitude));
      }
    } catch (_) {}
    _gpsSub = GpsService.watch(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    ).listen((pos) {
      if (mounted) {
        setState(() => _gps = ll.LatLng(pos.latitude, pos.longitude));
      }
    });
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    for (final c in [
      _startLat, _startLon, _endLat, _endLon,
      _startY, _startX, _endY, _endX,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  ll.LatLng? _resolve({
    required _PointSource src,
    required TextEditingController lat,
    required TextEditingController lon,
    required TextEditingController y,
    required TextEditingController x,
    required bool isStart,
  }) {
    switch (src) {
      case _PointSource.gps:
        return _gps;
      case _PointSource.wgs84:
        final la = double.tryParse(lat.text.trim());
        final lo = double.tryParse(lon.text.trim());
        if (la == null || lo == null) return null;
        return ll.LatLng(la, lo);
      case _PointSource.lo:
        final w = double.tryParse(y.text.trim());
        final s = double.tryParse(x.text.trim());
        if (w == null || s == null) return null;
        return LoConverter.toWgs84(
          westing: w,
          southing: s,
          zone: _zone,
          datumKey: _datum,
        );
    }
  }

  ll.LatLng? get _start => _resolve(
        src: _startSrc,
        lat: _startLat,
        lon: _startLon,
        y: _startY,
        x: _startX,
        isStart: true,
      );

  ll.LatLng? get _end => _resolve(
        src: _endSrc,
        lat: _endLat,
        lon: _endLon,
        y: _endY,
        x: _endX,
        isStart: false,
      );

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _startGuidance({bool locateMode = false}) {
    final end = _end;
    if (end == null) {
      _toast('Set a valid end point.');
      return;
    }
    ll.LatLng start;
    if (locateMode) {
      // ensure GPS then retry message if still null
      // (caller should have awaited; we kick off here)
      if (_gps == null) {
        _startGps();
        _toast('Getting GPS — tap Locate again once position appears.');
        return;
      }
      start = _gps!;
    } else {
      final s = _start;
      if (s == null) {
        _toast('Set a valid start point (or use GPS).');
        return;
      }
      start = s;
    }
    final dist = PathGuidance.distanceM(start, end);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GuidanceScreen(
          start: start,
          end: end,
          startLabel: locateMode
              ? 'You'
              : (_startName ??
                  (_startSrc == _PointSource.gps ? 'GPS' : 'Start')),
          endLabel: _endName ?? 'Target',
          pathLengthM: dist,
          locateMode: locateMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final start = _start;
    final end = _end;
    final dist = (start != null && end != null)
        ? PathGuidance.distanceM(start, end)
        : null;
    final bearing = (start != null && end != null)
        ? PathGuidance.bearingDeg(start, end)
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Walk a line')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Straight-line bush route between two points. '
            'Use “Locate from GPS” when you only have one corner pole to find.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          _endpointCard(
            title: 'Start',
            source: _startSrc,
            onSource: (v) {
              setState(() => _startSrc = v);
              if (v == _PointSource.gps) _startGps();
            },
            lat: _startLat,
            lon: _startLon,
            y: _startY,
            x: _startX,
            useGpsHint: _gps != null
                ? '${_gps!.latitude.toStringAsFixed(5)}, ${_gps!.longitude.toStringAsFixed(5)}'
                : 'Acquiring…',
          ),
          const SizedBox(height: 12),
          _endpointCard(
            title: 'End / corner pole',
            source: _endSrc,
            onSource: (v) => setState(() => _endSrc = v),
            lat: _endLat,
            lon: _endLon,
            y: _endY,
            x: _endX,
            useGpsHint: null,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                DropdownButtonFormField<CountrySystem>(
                  value: _country,
                  decoration: const InputDecoration(
                      labelText: 'Country (for Lo)', border: OutlineInputBorder()),
                  items: LoConverter.supportedCountries
                      .map((c) => DropdownMenuItem(
                          value: c, child: Text(c.label)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _country = v;
                      _zone = v.availableZones.contains(_zone)
                          ? _zone
                          : v.availableZones.first;
                      _datum = v.defaultDatum;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _country.availableZones.contains(_zone)
                          ? _zone
                          : _country.availableZones.first,
                      decoration: const InputDecoration(
                          labelText: 'Lo zone', border: OutlineInputBorder()),
                      items: _country.availableZones
                          .map((z) => DropdownMenuItem(
                              value: z, child: Text('Lo$z')))
                          .toList(),
                      onChanged: (v) => setState(() => _zone = v!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: LoConverter.availableDatums(_country.id)
                              .any((d) => d.key == _datum)
                          ? _datum
                          : LoConverter.availableDatums(_country.id).first.key,
                      decoration: const InputDecoration(
                          labelText: 'Datum', border: OutlineInputBorder()),
                      items: LoConverter.availableDatums(_country.id)
                          .map((d) => DropdownMenuItem(
                              value: d.key, child: Text(d.label)))
                          .toList(),
                      onChanged: (v) => setState(() => _datum = v!),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
          if (dist != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(children: [
                      const Text('Geodesic'),
                      Text(DistanceFormat.format(dist),
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                    ]),
                    Column(children: [
                      const Text('Bearing'),
                      Text('${bearing!.toStringAsFixed(0)}°',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: HybridMap(
                  center: start!,
                  initialZoom: 14,
                  polyline: [start, end!],
                  markers: [
                    MapMarkerData(
                        point: start, label: 'A', color: Colors.green),
                    MapMarkerData(
                        point: end,
                        label: 'B',
                        color: PathfinderTheme.accent),
                  ],
                  showOfflineBanner: false,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _startGuidance(locateMode: false),
            icon: const Icon(Icons.explore),
            label: const Text('Follow straight path (A → B)'),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: () => _startGuidance(locateMode: true),
            icon: const Icon(Icons.my_location),
            label: const Text('Locate end from my GPS'),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _endpointCard({
    required String title,
    required _PointSource source,
    required ValueChanged<_PointSource> onSource,
    required TextEditingController lat,
    required TextEditingController lon,
    required TextEditingController y,
    required TextEditingController x,
    required String? useGpsHint,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<_PointSource>(
              segments: [
                if (useGpsHint != null)
                  const ButtonSegment(
                      value: _PointSource.gps,
                      label: Text('GPS'),
                      icon: Icon(Icons.gps_fixed, size: 16)),
                const ButtonSegment(
                    value: _PointSource.wgs84,
                    label: Text('WGS84'),
                    icon: Icon(Icons.public, size: 16)),
                const ButtonSegment(
                    value: _PointSource.lo,
                    label: Text('Lo'),
                    icon: Icon(Icons.grid_on, size: 16)),
              ],
              selected: {source},
              onSelectionChanged: (s) => onSource(s.first),
            ),
            const SizedBox(height: 10),
            if (source == _PointSource.gps)
              Text('Using live GPS: ${useGpsHint ?? "…"}')
            else if (source == _PointSource.wgs84)
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: lat,
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Latitude', border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: lon,
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Longitude', border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ])
            else
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: y,
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Y (Westing)', border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: x,
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'X (Southing)',
                        border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}
