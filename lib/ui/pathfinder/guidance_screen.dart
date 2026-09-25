import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/corridor.dart';
import '../../core/distance_format.dart';
import '../../core/gps_smoother.dart';
import '../../core/guided_path.dart';
import '../../core/line_hysteresis.dart';
import '../../core/line_projector.dart';
import '../../core/path_guidance.dart';
import '../../services/device_bridge.dart';
import '../../services/external_maps.dart';
import '../../services/gps_service.dart';
import '../theme.dart';
import '../widgets/hybrid_map.dart';

enum _LocateUiMode { directions, stayOnLine }

/// Live stay-on-line guidance for pipes / fence / utilities (multi-segment OK).
class GuidanceScreen extends StatefulWidget {
  final ll.LatLng start;
  final ll.LatLng end;
  final String startLabel;
  final String endLabel;
  final double? pathLengthM;

  /// Optional multi-point path (start, vias…, end). When null, uses start+end.
  final List<PathVertex>? vertices;

  /// When true, start is "wherever you are" — GPS → end (locate one pole).
  final bool locateMode;

  /// When true (Walk the line), default to stay-on-line — do not auto-force
  /// Google Directions for typical farm distances.
  final bool preferStayOnLine;

  const GuidanceScreen({
    super.key,
    required this.start,
    required this.end,
    required this.startLabel,
    required this.endLabel,
    this.pathLengthM,
    this.vertices,
    this.locateMode = false,
    this.preferStayOnLine = false,
  });

  GuidedPath get path {
    if (vertices != null && vertices!.length >= 2) {
      return GuidedPath(vertices!);
    }
    return GuidedPath.startEnd(
      start,
      end,
      startLabel: startLabel,
      endLabel: endLabel,
    );
  }

  @override
  State<GuidanceScreen> createState() => _GuidanceScreenState();
}

class _GuidanceScreenState extends State<GuidanceScreen> {
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<CompassEvent>? _compassSub;
  ll.LatLng? _cur;
  ll.LatLng? _projected;
  double _xt = 0;
  double _distRemain = 0;
  double _alongPath = 0;
  double _totalPath = 0;
  double _targetBearingTrue = 0;
  double _headingMag = 0;
  double? _accuracyM;
  double? _compassAccuracy;
  bool _gpsFix = false;
  bool _overshoot = false;
  bool _permissionDenied = false;
  bool _arrived = false;
  LineSide _lineSide = LineSide.onLine;
  int _legIndex = 0;
  String? _error;
  String _segmentLabel = '';
  final List<double> _headingBuf = [];

  bool _modeLocked = false;
  _LocateUiMode _mode = _LocateUiMode.stayOnLine;

  /// User-adjustable base corridor (m); widened further by GPS accuracy.
  double _baseTolM = Corridor.defaultBaseTolM;

  late GuidedPath _path;
  final LineProjector _projector = LineProjector();
  final GpsSmoother _smoother = GpsSmoother();
  final DualEma _ema = DualEma();
  final LineHysteresis _hyst = LineHysteresis();
  final CorridorWidthFilter _corridorFilter = CorridorWidthFilter();
  final HybridMapController _mapCtrl = HybridMapController();

  bool _sunlight = false;
  bool _showCompass = false;
  DateTime? _lastFixAt;
  Timer? _staleTimer;
  double? _displayCorridor;
  double? _deviceDeclination;
  DateTime? _declinationAt;

  @override
  void initState() {
    super.initState();
    _path = widget.path;
    _totalPath = widget.pathLengthM ?? _path.totalLengthM;
    _distRemain = _totalPath;
    _targetBearingTrue = PathGuidance.bearingDeg(widget.start, widget.end);
    _segmentLabel = _path.segmentCount > 0 ? _path.segmentLabel(0) : '';

    if (widget.preferStayOnLine || !widget.locateMode) {
      _mode = _LocateUiMode.stayOnLine;
      _modeLocked = true;
    } else {
      _applyAutoMode();
    }

    WakelockPlus.enable();
    _startGps();
    _startCompass();
    _staleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _applyAutoMode() {
    if (_modeLocked) return;
    _mode = DistanceFormat.preferRoadDirections(_distRemain)
        ? _LocateUiMode.directions
        : _LocateUiMode.stayOnLine;
  }

  Future<void> _startGps() async {
    try {
      if (!await GpsService.ensurePermission(context)) {
        if (mounted) setState(() => _permissionDenied = true);
        return;
      }

      try {
        final seed = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
        );
        if (mounted) _onPos(seed);
      } catch (_) {}

      _gpsSub = GpsService.watch(
        accuracy: LocationAccuracy.bestForNavigation,
        // 0 = every GNSS fix. A 1 m filter hid the sub-metre corrections a
        // ±1.8 m corridor actually needs, and froze the hero while you stood
        // still and stepped sideways.
        distanceFilter: 0,
      ).listen(_onPos);
    } catch (e) {
      if (mounted) setState(() => _error = 'GPS error: $e');
    }
  }

  double get _tol =>
      _displayCorridor ??
      Corridor.halfWidthM(baseTolM: _baseTolM, accuracyM: _accuracyM);

  double get _declinationDeg =>
      _deviceDeclination ?? PathGuidance.botswanaDeclinationDeg;

  bool get _gpsStale {
    if (_lastFixAt == null) return false;
    return DateTime.now().difference(_lastFixAt!).inSeconds > 8;
  }

  void _onPos(Position pos) {
    final raw = ll.LatLng(pos.latitude, pos.longitude);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final smoothed = _smoother.update(raw, pos.accuracy, nowMs);
    final cur = smoothed?.position ?? raw;
    final acc = smoothed?.accuracyM ?? pos.accuracy;
    final arrivalR = PathGuidance.arrivalRadiusM(acc);

    double xt;
    double distRemain;
    double alongPath;
    double total;
    double bearing;
    bool overshoot;
    bool arrived;
    String segLabel;
    ll.LatLng? projected;
    var leg = _legIndex;

    if (widget.locateMode) {
      xt = 0.0;
      distRemain = PathGuidance.distanceM(cur, widget.end);
      alongPath = 0;
      total = distRemain;
      bearing = PathGuidance.bearingDeg(cur, widget.end);
      overshoot = false;
      arrived = distRemain <= arrivalR;
      segLabel = '→ ${widget.endLabel}';
      projected = null;
    } else {
      final prevLeg = _projector.activeLeg;
      final proj = _projector.project(cur, _path.points, labels: _path.labels);
      if (proj == null) return;

      // Cross-track is signed in the active leg's frame. Blending across a
      // bend mixes two directions and can announce the wrong side.
      if (proj.legIndex != prevLeg) {
        _ema.reset();
      }
      final ema = _ema.update(proj.crossTrackM, proj.alongPathM);
      xt = ema.cross;
      alongPath = ema.along.clamp(0.0, proj.totalM);
      distRemain = max(0.0, proj.totalM - alongPath);
      total = proj.totalM;
      bearing = proj.segmentBearingDeg;
      overshoot = proj.pastEnd;
      arrived = PathGuidance.distanceM(cur, widget.end) <= arrivalR ||
          (distRemain <= arrivalR &&
              proj.legIndex == _path.segmentCount - 1);
      segLabel = proj.segmentLabel;
      projected = proj.projected;
      leg = proj.legIndex;

      if (leg != prevLeg) {
        HapticFeedback.selectionClick();
      }
    }

    final rawCorridor = Corridor.halfWidthM(
      baseTolM: _baseTolM,
      accuracyM: acc,
    );
    final corridor = _corridorFilter.update(rawCorridor);

    final prevSide = _lineSide;
    final side = widget.locateMode
        ? LineSide.onLine
        : _hyst.update(xt, corridor);

    if (!widget.locateMode && prevSide != side && !arrived) {
      // Corridor leave: stronger haptic + beep (debounced in DeviceBridge).
      // Other side changes (e.g. LEFT↔RIGHT, re-enter): light tick only.
      if (prevSide == LineSide.onLine && side != LineSide.onLine) {
        HapticFeedback.mediumImpact();
        DeviceBridge.beep();
      } else {
        HapticFeedback.lightImpact();
      }
    }
    if (!_arrived && arrived) {
      HapticFeedback.mediumImpact();
    }

    _maybeRefreshDeclination(cur);

    if (!mounted) return;
    setState(() {
      _cur = cur;
      _gpsFix = true;
      _lastFixAt = DateTime.now();
      _accuracyM = acc;
      _xt = xt;
      _distRemain = distRemain;
      _alongPath = alongPath;
      _totalPath = total;
      _targetBearingTrue = bearing;
      _overshoot = overshoot;
      _arrived = arrived;
      _segmentLabel = segLabel;
      _projected = projected;
      _legIndex = leg;
      _lineSide = side;
      _displayCorridor = corridor;
      if (widget.locateMode) _applyAutoMode();
    });
  }

  void _maybeRefreshDeclination(ll.LatLng at) {
    final now = DateTime.now();
    if (_declinationAt != null &&
        now.difference(_declinationAt!).inSeconds < 60) {
      return;
    }
    _declinationAt = now;
    DeviceBridge.declination(at).then((deg) {
      if (!mounted || deg == null) return;
      setState(() => _deviceDeclination = deg);
    });
  }

  void _nudgeCorridor(double delta) {
    setState(() {
      _baseTolM = (_baseTolM + delta).clamp(0.5, 12.0);
      _displayCorridor = _corridorFilter.snap(
        Corridor.halfWidthM(baseTolM: _baseTolM, accuracyM: _accuracyM),
      );
    });
  }

  void _startCompass() {
    _compassSub = FlutterCompass.events?.listen((event) {
      final h = event.heading;
      if (h == null) return;
      _headingBuf.add(h);
      if (_headingBuf.length > 7) _headingBuf.removeAt(0);
      final smoothed = PathGuidance.smoothHeading(_headingBuf);
      if (mounted) {
        setState(() {
          _headingMag = smoothed;
          _compassAccuracy = event.accuracy;
        });
      }
    });
  }

  Future<void> _openMaps() async {
    await ExternalMaps.openNavigation(widget.end);
  }

  void _setMode(_LocateUiMode m) {
    setState(() {
      _modeLocked = true;
      _mode = m;
    });
  }

  void _recenter() {
    final t = _cur ?? widget.end;
    _mapCtrl.moveTo(t, zoom: 17);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _gpsSub?.cancel();
    _compassSub?.cancel();
    _staleTimer?.cancel();
    super.dispose();
  }

  List<MapMarkerData> get _markers {
    final out = <MapMarkerData>[];
    if (widget.locateMode) {
      out.add(MapMarkerData(
        point: widget.end,
        label: widget.endLabel,
        color: PathfinderTheme.accent,
      ));
      return out;
    }
    final verts = _path.vertices;
    for (var i = 0; i < verts.length; i++) {
      final v = verts[i];
      final isStart = i == 0;
      final isEnd = i == verts.length - 1;
      out.add(MapMarkerData(
        point: v.point,
        label: _path.defaultVertexLabel(i),
        color: isStart
            ? Colors.green
            : isEnd
                ? PathfinderTheme.accent
                : Colors.orange,
      ));
    }
    if (_projected != null) {
      out.add(MapMarkerData(
        point: _projected!,
        label: 'On line',
        color: Colors.white,
      ));
    }
    return out;
  }

  List<ll.LatLng> get _polyline {
    if (widget.locateMode) {
      return _cur != null ? [_cur!, widget.end] : [widget.start, widget.end];
    }
    return _path.points;
  }

  List<ll.LatLng> get _corridorPoly {
    if (widget.locateMode) return const [];
    return Corridor.polygon(_path.points, _tol);
  }

  List<ll.LatLng> get _offsetIndicator {
    if (widget.locateMode || _cur == null || _projected == null || !_gpsFix) {
      return const [];
    }
    if (_xt.abs() < 0.3) return const [];
    return [_cur!, _projected!];
  }

  String get _heroText {
    if (!_gpsFix) return 'Acquiring GPS…';
    if (_arrived) {
      return 'ARRIVED (±${PathGuidance.arrivalRadiusM(_accuracyM).toStringAsFixed(0)} m)';
    }
    if (_overshoot) return 'PASSED END — TURN BACK';
    if (widget.locateMode) {
      return PathGuidance.headingAwareMessage(
        headingMagDeg: _headingMag,
        desiredTrueBearingDeg: _targetBearingTrue,
        xtM: null,
        declinationDeg: _declinationDeg,
      );
    }
    switch (_lineSide) {
      case LineSide.onLine:
        return 'ON LINE';
      case LineSide.left:
        return 'LEFT ${_xt.abs().toStringAsFixed(1)} m';
      case LineSide.right:
        return 'RIGHT ${_xt.abs().toStringAsFixed(1)} m';
    }
  }

  String get _heroAction {
    if (!_gpsFix || _arrived || widget.locateMode) return '';
    if (_overshoot) return 'turn back toward the end marker';
    return PathGuidance.stayOnLineAction(_xt, onTrackTolM: _tol);
  }

  Color get _heroColor {
    if (!_gpsFix) return Colors.grey;
    if (_arrived) return Colors.green;
    if (_overshoot) return Colors.orange;
    if (widget.locateMode) {
      return _heroText == 'ON PATH' ? Colors.green : Colors.red;
    }
    switch (_lineSide) {
      case LineSide.onLine:
        return Colors.green;
      case LineSide.left:
      case LineSide.right:
        return _xt.abs() > _tol * 2 ? Colors.deepOrange : Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tol = _tol;
    final statusText = _heroText;
    final statusColor = _heroColor;
    final onLine = statusText == 'ON LINE' || statusText == 'ON PATH';
    final magTarget = PathGuidance.trueToMagnetic(
      _targetBearingTrue,
      declinationDeg: _declinationDeg,
    );
    final needsCalib =
        _compassAccuracy != null && _compassAccuracy! < 0;
    final farAway = DistanceFormat.preferRoadDirections(_distRemain);
    final distLabel = DistanceFormat.format(_distRemain);
    final title = widget.locateMode
        ? 'Locate ${widget.endLabel}'
        : (_path.segmentCount > 1
            ? 'Walk the line (${_path.vertices.length} pts)'
            : '${widget.startLabel} → ${widget.endLabel}');

    final theme = _sunlight
        ? ThemeData(
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.amber,
              brightness: Brightness.light,
              
            ),
            scaffoldBackgroundColor: Colors.white,
          )
        : Theme.of(context);

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: _sunlight ? Colors.white : null,
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              tooltip: _sunlight ? 'Normal contrast' : 'Sunlight / high contrast',
              onPressed: () => setState(() => _sunlight = !_sunlight),
              icon: Icon(_sunlight ? Icons.wb_sunny : Icons.wb_sunny_outlined),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: GpsService.accuracyColor(_accuracyM)
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: GpsService.accuracyColor(_accuracyM)),
                  ),
                  child: Text(
                    GpsService.accuracyLabel(_accuracyM),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _darken(GpsService.accuracyColor(_accuracyM)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_gpsStale)
              MaterialBanner(
                content: Text(
                  'GPS signal stale'
                  '${_lastFixAt != null ? ' (${DateTime.now().difference(_lastFixAt!).inSeconds}s)' : ''}'
                  ' — step into the open',
                ),
                backgroundColor: Colors.orange.shade100,
                actions: [
                  TextButton(
                    onPressed: () => setState(() {}),
                    child: const Text('OK'),
                  ),
                ],
              ),
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  HybridMap(
                    center: widget.start,
                    initialZoom: 16,
                    polyline: _polyline,
                    polygon: _corridorPoly,
                    polygonStroke: const Color(0xFFFF7A1A),
                    polygonFill: const Color(0xFFFF7A1A),
                    secondaryPolyline: _offsetIndicator,
                    userLocation: _cur,
                    accuracyM: _accuracyM,
                    fitToFeatures: true,
                    refitOnUpdate: false,
                    showDownloadButton: false,
                    showOfflineBanner: false,
                    markers: _markers,
                    controller: _mapCtrl,
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'recenter_guide',
                      tooltip: 'Recenter on me',
                      onPressed: _recenter,
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 5,
              child: Container(
                width: double.infinity,
                color: _sunlight
                    ? Colors.white
                    : Theme.of(context).colorScheme.surface,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _permissionDenied
                    ? _permDenied()
                    : _error != null
                        ? Center(
                            child: Text(_error!, textAlign: TextAlign.center))
                        : Column(
                            children: [
                              if (widget.locateMode || farAway)
                                SegmentedButton<_LocateUiMode>(
                                  segments: const [
                                    ButtonSegment(
                                      value: _LocateUiMode.directions,
                                      label: Text('Directions'),
                                      icon: Icon(Icons.directions_car,
                                          size: 18),
                                    ),
                                    ButtonSegment(
                                      value: _LocateUiMode.stayOnLine,
                                      label: Text('On line'),
                                      icon: Icon(Icons.straighten, size: 18),
                                    ),
                                  ],
                                  selected: {_mode},
                                  onSelectionChanged: (s) =>
                                      _setMode(s.first),
                                )
                              else
                                SegmentedButton<_LocateUiMode>(
                                  segments: const [
                                    ButtonSegment(
                                      value: _LocateUiMode.stayOnLine,
                                      label: Text('Stay on line'),
                                      icon: Icon(Icons.straighten, size: 18),
                                    ),
                                    ButtonSegment(
                                      value: _LocateUiMode.directions,
                                      label: Text('Directions'),
                                      icon: Icon(Icons.directions_car,
                                          size: 18),
                                    ),
                                  ],
                                  selected: {_mode},
                                  onSelectionChanged: (s) =>
                                      _setMode(s.first),
                                ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: _mode == _LocateUiMode.directions
                                    ? _directionsPane(distLabel, farAway)
                                    : _stayOnLinePane(
                                        statusText,
                                        statusColor,
                                        distLabel,
                                        magTarget,
                                        needsCalib,
                                        farAway,
                                        tol,
                                        onLine,
                                      ),
                              ),
                            ],
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _directionsPane(String distLabel, bool farAway) {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          Text(
            distLabel,
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            widget.locateMode
                ? 'straight-line to ${widget.endLabel}'
                : 'remaining along path',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (farAway) ...[
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "You're $distLabel away — get road directions first",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Drive close, then switch to Stay on line for pipe/fence laying.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _openMaps,
                      icon: const Icon(Icons.map),
                      label: const Text('Open in Google Maps'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => _setMode(_LocateUiMode.stayOnLine),
                      child: const Text('Use stay-on-line guidance anyway'),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _openMaps,
              icon: const Icon(Icons.map),
              label: const Text('Open in Google Maps'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _setMode(_LocateUiMode.stayOnLine),
              child: const Text('Switch to stay-on-line'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stayOnLinePane(
    String statusText,
    Color statusColor,
    String distLabel,
    double magTarget,
    bool needsCalib,
    bool farAway,
    double tol,
    bool onLine,
  ) {
    final progressFrac =
        _totalPath <= 0 ? 0.0 : (_alongPath / _totalPath).clamp(0.0, 1.0);
    final cum = _path.cumulativeM;

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (farAway && widget.locateMode) ...[
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "You're $distLabel away — get road directions first",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.orange.shade900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _openMaps,
                      icon: const Icon(Icons.map, size: 18),
                      label: const Text('Open in Google Maps'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          // —— Hero status ——
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: _sunlight ? 0.25 : 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor, width: 3),
            ),
            child: Column(
              children: [
                Text(
                  statusText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: _darken(statusColor),
                    letterSpacing: 0.8,
                  ),
                ),
                if (_heroAction.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _heroAction,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _darken(statusColor).withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!widget.locateMode) ...[
            const SizedBox(height: 10),
            _lateralGauge(xt: _xt, corridor: tol),
          ],
          const SizedBox(height: 10),
          if (!widget.locateMode) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${DistanceFormat.format(_alongPath)} of '
                    '${DistanceFormat.format(_totalPath)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '$distLabel left',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Progress with bend ticks
            SizedBox(
              height: 14,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progressFrac,
                      minHeight: 10,
                      backgroundColor: Colors.grey.shade300,
                      color: onLine ? Colors.green : PathfinderTheme.sky,
                    ),
                  ),
                  if (_totalPath > 0)
                    for (var i = 1; i < cum.length - 1; i++)
                      Positioned(
                        left: (cum[i] / _totalPath).clamp(0.0, 1.0) *
                            (MediaQuery.sizeOf(context).width - 32),
                        top: 0,
                        bottom: 0,
                        child: Container(width: 2, color: Colors.black54),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    'Leg ${_legIndex + 1}/${max(1, _path.segmentCount)}'
                    '${_segmentLabel.isNotEmpty ? ' · $_segmentLabel' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    'GPS ±${(_accuracyM ?? 0).toStringAsFixed(1)} m',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(
              distLabel,
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.bold,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              'to ${widget.endLabel}',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 4),
          if (!widget.locateMode)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Narrower corridor',
                  onPressed: () => _nudgeCorridor(-0.5),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  'Corridor ±${tol.toStringAsFixed(1)} m',
                  style: const TextStyle(fontSize: 13),
                ),
                IconButton(
                  tooltip: 'Wider corridor',
                  onPressed: () => _nudgeCorridor(0.5),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _metric('Bearing', '${_targetBearingTrue.toStringAsFixed(0)}°'),
              if (_showCompass)
                _metric('Heading', '${_headingMag.toStringAsFixed(0)}°'),
              if (!widget.locateMode)
                _metric('Offset', '${_xt.abs().toStringAsFixed(1)} m'),
            ],
          ),
          TextButton.icon(
            onPressed: () => setState(() => _showCompass = !_showCompass),
            icon: Icon(
              _showCompass ? Icons.explore : Icons.explore_outlined,
              size: 18,
            ),
            label: Text(_showCompass ? 'Hide compass' : 'Show compass (optional)'),
          ),
          if (_showCompass) ...[
            Text(
              'Compass is secondary — stay-on-line uses cross-track, not turn-by-turn.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (needsCalib ||
                (_compassAccuracy != null && (_compassAccuracy!).abs() > 30))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Compass accuracy looks poor — wave the phone in a figure-8.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 12, color: Colors.orange.shade800),
                ),
              ),
            if (_gpsFix) _compassRose(magTarget),
          ],
          if (!_gpsFix)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _openMaps,
            icon: const Icon(Icons.map, size: 18),
            label: const Text('Open in Google Maps'),
          ),
        ],
      ),
    );
  }

  /// Lateral gauge: center line + corridor band + offset puck.
  Widget _lateralGauge({required double xt, required double corridor}) {
    final span = max(corridor * 3, 6.0); // half-span of gauge in metres
    final puck = (xt / span).clamp(-1.0, 1.0); // -1 left … +1 right
    final band = (corridor / span).clamp(0.0, 1.0);

    return Column(
      children: [
        SizedBox(
          height: 36,
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              final mid = w / 2;
              final bandW = band * w;
              final puckX = mid + puck * (w / 2);
              return Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  Positioned(
                    left: mid - bandW / 2,
                    width: bandW,
                    child: Container(
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                  Positioned(
                    left: mid - 1,
                    child: Container(width: 2, height: 28, color: Colors.black87),
                  ),
                  Positioned(
                    left: puckX - 10,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _heroColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(blurRadius: 3, color: Colors.black26),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('◀ LEFT', style: TextStyle(fontSize: 10)),
            Text('LINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            Text('RIGHT ▶', style: TextStyle(fontSize: 10)),
          ],
        ),
      ],
    );
  }

  Widget _permDenied() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Location permission is required for live guidance.\n\n'
              'Open system settings and allow precise location for Pathfinder.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Geolocator.openAppSettings(),
              child: const Text('Open app settings'),
            ),
          ],
        ),
      );

  Widget _metric(String label, String value) => Column(
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(value,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      );

  Widget _compassRose(double magTarget) {
    final headingDiff = (_headingMag - magTarget + 360) % 360;
    final aligned = headingDiff < 8 || headingDiff > 352;
    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -_headingMag * pi / 180,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: aligned ? Colors.green : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: const Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                      top: 2,
                      child: Text('N',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.red))),
                  Positioned(
                      bottom: 2,
                      child: Text('S', style: TextStyle(fontSize: 11))),
                  Positioned(
                      left: 6, child: Text('W', style: TextStyle(fontSize: 11))),
                  Positioned(
                      right: 6, child: Text('E', style: TextStyle(fontSize: 11))),
                ],
              ),
            ),
          ),
          Transform.rotate(
            angle: (magTarget - _headingMag) * pi / 180,
            child: Icon(Icons.navigation,
                size: 36,
                color: aligned ? Colors.green : PathfinderTheme.sky),
          ),
        ],
      ),
    );
  }
}

Color _darken(Color c) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness * 0.65).clamp(0.0, 1.0)).toColor();
}
