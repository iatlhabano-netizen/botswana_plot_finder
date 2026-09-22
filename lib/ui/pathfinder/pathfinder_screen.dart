import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/lo_converter.dart';
import '../../core/distance_format.dart';
import '../../core/guided_path.dart';
import '../../core/path_guidance.dart';
import '../../services/gps_service.dart';
import '../../services/line_job_store.dart';
import '../theme.dart';
import '../widgets/hybrid_map.dart';
import 'guidance_screen.dart';
import 'saved_waypoints_sheet.dart';

enum _PointSource { gps, wgs84, lo, map }

enum _MapTapMode { setStart, addVia, setEnd, pan }

const _kDefaultCenter = ll.LatLng(-22.3285, 24.6849);

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
  _PointSource _startSrc = _PointSource.wgs84;
  _PointSource _endSrc = _PointSource.wgs84;
  _MapTapMode _mapMode = _MapTapMode.setStart;

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
  double? _gpsAccuracyM;
  StreamSubscription<Position>? _gpsSub;
  String? _startName;
  String? _endName;
  ll.LatLng? _startMap;
  ll.LatLng? _endMap;

  /// Intermediate bend points (between start and end), in order.
  final List<PathVertex> _vias = [];

  int _fitToken = 0;
  bool _advancedOpen = false;

  @override
  void initState() {
    super.initState();
    _startName = widget.startLabel;
    _endName = widget.endLabel;
    if (widget.initialStart != null) {
      _startSrc = _PointSource.wgs84;
      _startMap = widget.initialStart;
      _startLat.text = widget.initialStart!.latitude.toStringAsFixed(7);
      _startLon.text = widget.initialStart!.longitude.toStringAsFixed(7);
    }
    if (widget.initialEnd != null) {
      _endSrc = _PointSource.wgs84;
      _endMap = widget.initialEnd;
      _endLat.text = widget.initialEnd!.latitude.toStringAsFixed(7);
      _endLon.text = widget.initialEnd!.longitude.toStringAsFixed(7);
      if (widget.initialStart != null) {
        _mapMode = _MapTapMode.pan;
      }
    }
  }

  Future<void> _startGps() async {
    if (_gpsSub != null) return;
    if (!await GpsService.ensurePermission(context)) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
      if (mounted) {
        setState(() {
          _gps = ll.LatLng(pos.latitude, pos.longitude);
          _gpsAccuracyM = pos.accuracy;
        });
      }
    } catch (_) {}
    _gpsSub = GpsService.watch(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    ).listen((pos) {
      if (mounted) {
        setState(() {
          _gps = ll.LatLng(pos.latitude, pos.longitude);
          _gpsAccuracyM = pos.accuracy;
        });
      }
    });
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    for (final c in [
      _startLat,
      _startLon,
      _endLat,
      _endLon,
      _startY,
      _startX,
      _endY,
      _endX,
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
    required ll.LatLng? mapPt,
  }) {
    switch (src) {
      case _PointSource.gps:
        return _gps;
      case _PointSource.map:
        return mapPt;
      case _PointSource.wgs84:
        if (mapPt != null &&
            lat.text.trim().isEmpty &&
            lon.text.trim().isEmpty) {
          return mapPt;
        }
        final la = double.tryParse(lat.text.trim());
        final lo = double.tryParse(lon.text.trim());
        if (la == null || lo == null) return mapPt;
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
        mapPt: _startMap,
      );

  ll.LatLng? get _end => _resolve(
        src: _endSrc,
        lat: _endLat,
        lon: _endLon,
        y: _endY,
        x: _endX,
        mapPt: _endMap,
      );

  GuidedPath? get _guidedPath {
    final s = _start;
    final e = _end;
    if (s == null || e == null) return null;
    return GuidedPath([
      PathVertex(s, label: _startName ?? 'Start'),
      ..._vias,
      PathVertex(e, label: _endName ?? 'End'),
    ]);
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _applyPoint({
    required bool isStart,
    required ll.LatLng pt,
    required _PointSource src,
    String? name,
    double? loY,
    double? loX,
  }) {
    setState(() {
      if (isStart) {
        _startSrc = src;
        _startMap = pt;
        _startName = name;
        _startLat.text = pt.latitude.toStringAsFixed(7);
        _startLon.text = pt.longitude.toStringAsFixed(7);
        if (loY != null) _startY.text = loY.toStringAsFixed(3);
        if (loX != null) _startX.text = loX.toStringAsFixed(3);
      } else {
        _endSrc = src;
        _endMap = pt;
        _endName = name;
        _endLat.text = pt.latitude.toStringAsFixed(7);
        _endLon.text = pt.longitude.toStringAsFixed(7);
        if (loY != null) _endY.text = loY.toStringAsFixed(3);
        if (loX != null) _endX.text = loX.toStringAsFixed(3);
      }
      _fitToken++;
    });
  }

  void _addVia(ll.LatLng pt, {String? label}) {
    setState(() {
      _vias.add(PathVertex(
        pt,
        label: label ?? 'Via ${_vias.length + 1}',
      ));
      _fitToken++;
    });
  }

  void _onMapTap(ll.LatLng pt) {
    switch (_mapMode) {
      case _MapTapMode.pan:
        return;
      case _MapTapMode.setStart:
        _applyPoint(isStart: true, pt: pt, src: _PointSource.map);
        _toast('Start placed');
        if (_end == null) {
          setState(() => _mapMode = _MapTapMode.setEnd);
        }
        break;
      case _MapTapMode.setEnd:
        _applyPoint(isStart: false, pt: pt, src: _PointSource.map);
        _toast('End placed');
        setState(() => _mapMode = _MapTapMode.pan);
        break;
      case _MapTapMode.addVia:
        if (_start == null) {
          _toast('Set start first');
          return;
        }
        if (_end == null) {
          // Treat as end if no end yet
          _applyPoint(isStart: false, pt: pt, src: _PointSource.map);
          _toast('End placed (set end before adding bends)');
          setState(() => _mapMode = _MapTapMode.pan);
          return;
        }
        _addVia(pt);
        _toast('Bend / via added');
        break;
    }
  }

  Future<void> _useGpsAs(bool isStart) async {
    await _startGps();
    if (_gps == null) {
      _toast('Waiting for GPS fix…');
      return;
    }
    _applyPoint(
      isStart: isStart,
      pt: _gps!,
      src: _PointSource.gps,
      name: 'My GPS',
    );
    _toast(isStart ? 'Start = my GPS' : 'End = my GPS');
  }

  Future<void> _useGpsAsVia() async {
    await _startGps();
    if (_gps == null) {
      _toast('Waiting for GPS fix…');
      return;
    }
    if (_start == null || _end == null) {
      _toast('Set start and end before adding a via');
      return;
    }
    _addVia(_gps!, label: 'GPS via');
    _toast('Via = my GPS');
  }

  Future<void> _showMyLocation() async {
    await _startGps();
    if (_gps == null) {
      _toast('Waiting for GPS fix…');
      return;
    }
    final acc = _gpsAccuracyM != null
        ? ' (±${_gpsAccuracyM!.toStringAsFixed(0)} m)'
        : '';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('My location'),
        content: SelectableText(
          '${_gps!.latitude.toStringAsFixed(7)}, '
          '${_gps!.longitude.toStringAsFixed(7)}$acc',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(
                text:
                    '${_gps!.latitude.toStringAsFixed(7)}, ${_gps!.longitude.toStringAsFixed(7)}',
              ));
              if (ctx.mounted) Navigator.pop(ctx);
              _toast('GPS coordinates copied');
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await promptAndSaveWaypoint(
                context,
                lat: _gps!.latitude,
                lng: _gps!.longitude,
                suggestedLabel: 'My GPS',
              );
            },
            child: const Text('Save'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyCoords(ll.LatLng? pt, String which) async {
    if (pt == null) {
      _toast('No $which point to copy.');
      return;
    }
    final text =
        '${pt.latitude.toStringAsFixed(7)}, ${pt.longitude.toStringAsFixed(7)}';
    await Clipboard.setData(ClipboardData(text: text));
    _toast('$which coordinates copied');
  }

  Future<void> _copyMyGps() async {
    await _startGps();
    if (_gps == null) {
      _toast('Waiting for GPS fix…');
      return;
    }
    await _copyCoords(_gps, 'GPS');
  }

  Future<void> _savePoint({
    required ll.LatLng? pt,
    required String suggested,
    bool includeLo = false,
    TextEditingController? y,
    TextEditingController? x,
  }) async {
    if (pt == null) {
      _toast('Nothing to save yet.');
      return;
    }
    double? loY;
    double? loX;
    if (includeLo && y != null && x != null) {
      loY = double.tryParse(y.text.trim());
      loX = double.tryParse(x.text.trim());
    }
    await promptAndSaveWaypoint(
      context,
      lat: pt.latitude,
      lng: pt.longitude,
      suggestedLabel: suggested,
      loY: loY,
      loX: loX,
      zone: (loY != null && loX != null) ? _zone : null,
      datum: (loY != null && loX != null) ? _datum : null,
    );
  }

  Future<void> _saveJob() async {
    final path = _guidedPath;
    if (path == null) {
      _toast('Set start and end first');
      return;
    }
    final ctrl = TextEditingController(
      text: 'Pipe ${_vias.isEmpty ? "line" : "path"} '
          '${DateTime.now().day}/${DateTime.now().month}',
    );
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save path job'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Label',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (label == null || label.trim().isEmpty) return;
    await LineJobStore.add(LineJob(
      id: 'job_${DateTime.now().millisecondsSinceEpoch}',
      label: label.trim(),
      path: path,
      createdAt: DateTime.now(),
    ));
    _toast('Saved “${label.trim()}”');
  }

  void _openSavedPoints() {
    SavedWaypointsSheet.show(
      context,
      onPick: (wp, action) {
        if (action == WaypointPickAction.useAsStart) {
          _applyPoint(
            isStart: true,
            pt: wp.wgs84,
            src: _PointSource.wgs84,
            name: wp.label,
            loY: wp.loY,
            loX: wp.loX,
          );
          _toast('Start = ${wp.label}');
        } else if (action == WaypointPickAction.useAsEnd) {
          _applyPoint(
            isStart: false,
            pt: wp.wgs84,
            src: _PointSource.wgs84,
            name: wp.label,
            loY: wp.loY,
            loX: wp.loX,
          );
          _toast('End = ${wp.label}');
        } else if (action == WaypointPickAction.useAsVia) {
          if (_start == null || _end == null) {
            _toast('Set start and end before adding a via');
            return;
          }
          _addVia(wp.wgs84, label: wp.label);
          _toast('Via = ${wp.label}');
        }
      },
    );
  }

  void _startGuidance({bool locateMode = false}) {
    final end = _end;
    if (end == null) {
      _toast('Set a valid end point.');
      return;
    }
    ll.LatLng start;
    if (locateMode) {
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

    final path = locateMode
        ? GuidedPath.startEnd(start, end,
            startLabel: 'You', endLabel: _endName ?? 'Target')
        : _guidedPath!;
    final dist = path.totalLengthM;

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
          preferStayOnLine: !locateMode,
          vertices: locateMode ? null : path.vertices,
        ),
      ),
    );
  }

  ll.LatLng get _mapCenter {
    final path = _guidedPath;
    if (path != null) {
      final pts = path.points;
      var lat = 0.0, lon = 0.0;
      for (final p in pts) {
        lat += p.latitude;
        lon += p.longitude;
      }
      return ll.LatLng(lat / pts.length, lon / pts.length);
    }
    return _start ?? _end ?? _gps ?? _kDefaultCenter;
  }

  @override
  Widget build(BuildContext context) {
    final start = _start;
    final end = _end;
    final path = _guidedPath;
    final dist = path?.totalLengthM;
    final bearing = (start != null && end != null && _vias.isEmpty)
        ? PathGuidance.bearingDeg(start, end)
        : null;

    final markers = <MapMarkerData>[];
    if (start != null) {
      markers.add(MapMarkerData(
        point: start,
        label: _startName ?? 'Start',
        color: Colors.green,
      ));
    }
    for (var i = 0; i < _vias.length; i++) {
      markers.add(MapMarkerData(
        point: _vias[i].point,
        label: _vias[i].label ?? 'Via ${i + 1}',
        color: Colors.orange,
      ));
    }
    if (end != null) {
      markers.add(MapMarkerData(
        point: end,
        label: _endName ?? 'End',
        color: PathfinderTheme.accent,
      ));
    }

    final polyline = path?.points ?? <ll.LatLng>[];
    final canAddVia = start != null && end != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Walk a line'),
        actions: [
          IconButton(
            tooltip: 'Saved points',
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: _openSavedPoints,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Lay pipe, fence, or utilities on a straight (or bent) line. '
            'Tap Start → End on the map, add bends if needed, then Walk the line '
            'for live ON LINE / LEFT / RIGHT offset.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),

          Text('Map', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<_MapTapMode>(
            segments: [
              const ButtonSegment(
                value: _MapTapMode.setStart,
                label: Text('Start'),
                icon: Icon(Icons.flag, size: 16),
              ),
              ButtonSegment(
                value: _MapTapMode.addVia,
                label: const Text('Add bend'),
                icon: const Icon(Icons.add_location_alt, size: 16),
                enabled: canAddVia || start != null,
              ),
              const ButtonSegment(
                value: _MapTapMode.setEnd,
                label: Text('End'),
                icon: Icon(Icons.flag_outlined, size: 16),
              ),
              const ButtonSegment(
                value: _MapTapMode.pan,
                label: Text('Pan'),
                icon: Icon(Icons.pan_tool_alt, size: 16),
              ),
            ],
            selected: {_mapMode},
            onSelectionChanged: (s) {
              final m = s.first;
              if (m == _MapTapMode.addVia && !canAddVia && start == null) {
                _toast('Set start first');
                return;
              }
              setState(() => _mapMode = m);
            },
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 300,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: HybridMap(
                key: ValueKey('pf_map_$_fitToken'),
                center: _mapCenter,
                initialZoom: path != null ? 13 : 6.5,
                polyline: polyline,
                markers: markers,
                userLocation: _gps,
                onTap: _mapMode == _MapTapMode.pan ? null : _onMapTap,
                fitToFeatures: path != null,
                showOfflineBanner: true,
                showDownloadButton: false,
              ),
            ),
          ),
          if (_mapMode != _MapTapMode.pan)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                switch (_mapMode) {
                  _MapTapMode.setStart => 'Tap the map to place or move Start.',
                  _MapTapMode.setEnd => 'Tap the map to place or move End.',
                  _MapTapMode.addVia =>
                    'Tap to add a bend (via) before End — for dog-legs in the pipe/fence.',
                  _MapTapMode.pan => '',
                },
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),

          // Vertex list
          if (path != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < path.vertices.length; i++)
                    ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: i == 0
                            ? Colors.green
                            : i == path.vertices.length - 1
                                ? PathfinderTheme.accent
                                : Colors.orange,
                        child: Text(
                          i == 0
                              ? 'S'
                              : i == path.vertices.length - 1
                                  ? 'E'
                                  : '$i',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white),
                        ),
                      ),
                      title: Text(path.defaultVertexLabel(i)),
                      subtitle: Text(
                        '${path.vertices[i].point.latitude.toStringAsFixed(5)}, '
                        '${path.vertices[i].point.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: i > 0 && i < path.vertices.length - 1
                          ? IconButton(
                              tooltip: 'Remove via',
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () => setState(() {
                                _vias.removeAt(i - 1);
                                _fitToken++;
                              }),
                            )
                          : null,
                    ),
                  if (_vias.length >= 2)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Text(
                        'Reorder: remove and re-add bends in order (kept simple).',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _showMyLocation,
                icon: const Icon(Icons.my_location, size: 18),
                label: const Text('My location'),
              ),
              OutlinedButton.icon(
                onPressed: () => _useGpsAs(true),
                icon: const Icon(Icons.gps_fixed, size: 18),
                label: const Text('GPS → Start'),
              ),
              OutlinedButton.icon(
                onPressed: () => _useGpsAs(false),
                icon: const Icon(Icons.gps_fixed, size: 18),
                label: const Text('GPS → End'),
              ),
              if (canAddVia)
                OutlinedButton.icon(
                  onPressed: _useGpsAsVia,
                  icon: const Icon(Icons.add_location_alt, size: 18),
                  label: const Text('GPS → Via'),
                ),
              OutlinedButton.icon(
                onPressed: _copyMyGps,
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy GPS'),
              ),
              OutlinedButton.icon(
                onPressed: () => _savePoint(pt: _gps, suggested: 'My GPS'),
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: const Text('Save GPS'),
              ),
              OutlinedButton.icon(
                onPressed: _openSavedPoints,
                icon: const Icon(Icons.bookmarks_outlined, size: 18),
                label: const Text('Saved points'),
              ),
            ],
          ),
          if (_gps != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.gps_fixed,
                      size: 16,
                      color: GpsService.accuracyColor(_gpsAccuracyM)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${_gps!.latitude.toStringAsFixed(5)}, '
                      '${_gps!.longitude.toStringAsFixed(5)}'
                      '${_gpsAccuracyM != null ? "  ${GpsService.accuracyLabel(_gpsAccuracyM)}" : ""}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),

          if (dist != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'Path length',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      DistanceFormat.format(dist),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_vias.isNotEmpty)
                      Text(
                        '${_vias.length + 2} points · ${_vias.length} bend'
                        '${_vias.length == 1 ? "" : "s"}',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else if (bearing != null)
                      Text(
                        'Bearing ${bearing.toStringAsFixed(0)}° true',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: path == null ? null : () => _startGuidance(locateMode: false),
            icon: const Icon(Icons.straighten),
            label: const Text('Walk the line'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: () => _startGuidance(locateMode: true),
            icon: const Icon(Icons.my_location),
            label: const Text('Locate end from my GPS'),
          ),
          if (path != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _saveJob,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save path job'),
            ),
          ],

          const SizedBox(height: 16),
          ExpansionTile(
            initiallyExpanded: _advancedOpen,
            onExpansionChanged: (v) => setState(() => _advancedOpen = v),
            title: const Text('Advanced — typed WGS84 / Lo'),
            subtitle: const Text('Manual coordinates & survey fields'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Column(
                  children: [
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
                      resolved: start,
                      name: _startName,
                      onUseGps: () => _useGpsAs(true),
                      onCopy: () => _copyCoords(start, 'Start'),
                      onSave: () => _savePoint(
                        pt: start,
                        suggested: _startName ?? 'Start',
                        includeLo: _startSrc == _PointSource.lo,
                        y: _startY,
                        x: _startX,
                      ),
                      onPickSaved: _openSavedPoints,
                      useGpsHint: _gps != null
                          ? '${_gps!.latitude.toStringAsFixed(5)}, ${_gps!.longitude.toStringAsFixed(5)}'
                          : 'Tap “Use my GPS”',
                    ),
                    const SizedBox(height: 12),
                    _endpointCard(
                      title: 'End',
                      source: _endSrc,
                      onSource: (v) {
                        setState(() => _endSrc = v);
                        if (v == _PointSource.gps) _startGps();
                      },
                      lat: _endLat,
                      lon: _endLon,
                      y: _endY,
                      x: _endX,
                      resolved: end,
                      name: _endName,
                      onUseGps: () => _useGpsAs(false),
                      onCopy: () => _copyCoords(end, 'End'),
                      onSave: () => _savePoint(
                        pt: end,
                        suggested: _endName ?? 'End',
                        includeLo: _endSrc == _PointSource.lo,
                        y: _endY,
                        x: _endX,
                      ),
                      onPickSaved: _openSavedPoints,
                      useGpsHint: _gps != null
                          ? '${_gps!.latitude.toStringAsFixed(5)}, ${_gps!.longitude.toStringAsFixed(5)}'
                          : 'Tap “Use my GPS”',
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(children: [
                          DropdownButtonFormField<CountrySystem>(
                            value: _country,
                            decoration: const InputDecoration(
                                labelText: 'Country (for Lo)',
                                border: OutlineInputBorder()),
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
                                    labelText: 'Lo zone',
                                    border: OutlineInputBorder()),
                                items: _country.availableZones
                                    .map((z) => DropdownMenuItem(
                                        value: z, child: Text('Lo$z')))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _zone = v!),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: LoConverter.availableDatums(_country.id)
                                        .any((d) => d.key == _datum)
                                    ? _datum
                                    : LoConverter.availableDatums(_country.id)
                                        .first
                                        .key,
                                decoration: const InputDecoration(
                                    labelText: 'Datum',
                                    border: OutlineInputBorder()),
                                items: LoConverter.availableDatums(_country.id)
                                    .map((d) => DropdownMenuItem(
                                        value: d.key, child: Text(d.label)))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _datum = v!),
                              ),
                            ),
                          ]),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
    required ll.LatLng? resolved,
    required String? name,
    required VoidCallback onUseGps,
    required VoidCallback onCopy,
    required VoidCallback onSave,
    required VoidCallback onPickSaved,
    required String? useGpsHint,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name != null && name.isNotEmpty ? '$title · $name' : title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Use my GPS',
                  onPressed: onUseGps,
                  icon: const Icon(Icons.gps_fixed),
                ),
                IconButton(
                  tooltip: 'Copy coords',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy),
                ),
                IconButton(
                  tooltip: 'Save as waypoint',
                  onPressed: onSave,
                  icon: const Icon(Icons.bookmark_add_outlined),
                ),
                IconButton(
                  tooltip: 'Pick saved',
                  onPressed: onPickSaved,
                  icon: const Icon(Icons.bookmarks_outlined),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<_PointSource>(
              segments: const [
                ButtonSegment(
                    value: _PointSource.gps,
                    label: Text('GPS'),
                    icon: Icon(Icons.gps_fixed, size: 16)),
                ButtonSegment(
                    value: _PointSource.wgs84,
                    label: Text('WGS84'),
                    icon: Icon(Icons.public, size: 16)),
                ButtonSegment(
                    value: _PointSource.lo,
                    label: Text('Lo'),
                    icon: Icon(Icons.grid_on, size: 16)),
                ButtonSegment(
                    value: _PointSource.map,
                    label: Text('Map'),
                    icon: Icon(Icons.map, size: 16)),
              ],
              selected: {source},
              onSelectionChanged: (s) => onSource(s.first),
            ),
            const SizedBox(height: 10),
            if (source == _PointSource.gps)
              Text('Using live GPS: ${useGpsHint ?? "…"}')
            else if (source == _PointSource.map)
              Text(
                resolved == null
                    ? 'Choose Start/End above and tap the map.'
                    : '${resolved.latitude.toStringAsFixed(6)}, '
                        '${resolved.longitude.toStringAsFixed(6)}',
              )
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
            if (resolved != null &&
                source != _PointSource.wgs84 &&
                source != _PointSource.map) ...[
              const SizedBox(height: 6),
              Text(
                '→ ${resolved.latitude.toStringAsFixed(6)}, '
                '${resolved.longitude.toStringAsFixed(6)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
