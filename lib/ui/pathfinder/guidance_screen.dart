import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/path_guidance.dart';
import '../../services/gps_service.dart';
import '../theme.dart';
import '../widgets/hybrid_map.dart';

/// Live line-following / single-point locate guidance (outdoor UI).
class GuidanceScreen extends StatefulWidget {
  final ll.LatLng start;
  final ll.LatLng end;
  final String startLabel;
  final String endLabel;
  final double? pathLengthM;

  /// When true, start is "wherever you are" — path is continuously
  /// GPS → end (locate one corner pole).
  final bool locateMode;

  const GuidanceScreen({
    super.key,
    required this.start,
    required this.end,
    required this.startLabel,
    required this.endLabel,
    this.pathLengthM,
    this.locateMode = false,
  });

  @override
  State<GuidanceScreen> createState() => _GuidanceScreenState();
}

class _GuidanceScreenState extends State<GuidanceScreen> {
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<CompassEvent>? _compassSub;
  ll.LatLng? _cur;
  double _xt = 0;
  double _distRemain = 0;
  double _targetBearingTrue = 0;
  double _headingMag = 0;
  double? _accuracyM;
  double? _compassAccuracy;
  bool _gpsFix = false;
  bool _overshoot = false;
  bool _permissionDenied = false;
  bool _arrived = false;
  bool? _wasOnPath;
  String? _error;
  final List<double> _headingBuf = [];

  @override
  void initState() {
    super.initState();
    _targetBearingTrue = PathGuidance.bearingDeg(widget.start, widget.end);
    _distRemain = PathGuidance.distanceM(widget.start, widget.end);
    // First paint uses real start→end distance (never force 0 m).
    WakelockPlus.enable();
    _startGps();
    _startCompass();
  }

  Future<void> _startGps() async {
    try {
      if (!await GpsService.ensurePermission(context)) {
        if (mounted) setState(() => _permissionDenied = true);
        return;
      }

      // Seed with a current fix so locate mode does not flash 0 m from start==end.
      try {
        final seed = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
        );
        if (mounted) _onPos(seed);
      } catch (_) {}

      _gpsSub = GpsService.watch(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ).listen(_onPos);
    } catch (e) {
      if (mounted) setState(() => _error = 'GPS error: $e');
    }
  }

  void _onPos(Position pos) {
    final cur = ll.LatLng(pos.latitude, pos.longitude);
    final start = widget.locateMode ? cur : widget.start;
    final xt = widget.locateMode
        ? 0.0
        : PathGuidance.crossTrackM(cur, widget.start, widget.end);
    final dist = PathGuidance.distanceM(cur, widget.end);
    final bearing = PathGuidance.bearingDeg(start, widget.end);
    final overshoot = widget.locateMode
        ? false
        : PathGuidance.isPastEnd(cur, widget.start, widget.end);
    final arrivalR = PathGuidance.arrivalRadiusM(pos.accuracy);
    final arrived = dist <= arrivalR;
    final onPath = !overshoot &&
        (widget.locateMode
            ? PathGuidance.signedTurnDeg(
                      _headingMag,
                      PathGuidance.trueToMagnetic(bearing),
                    ).abs() <=
                20
            : xt.abs() <= 1.5);

    // Haptics on transitions
    if (_wasOnPath != null && _wasOnPath != onPath && !arrived) {
      HapticFeedback.lightImpact();
    }
    if (!_arrived && arrived) {
      HapticFeedback.mediumImpact();
    }
    _wasOnPath = onPath;

    if (!mounted) return;
    setState(() {
      _cur = cur;
      _gpsFix = true;
      _accuracyM = pos.accuracy;
      _xt = xt;
      _distRemain = dist;
      _targetBearingTrue = bearing;
      _overshoot = overshoot;
      _arrived = arrived;
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

  @override
  void dispose() {
    WakelockPlus.disable();
    _gpsSub?.cancel();
    _compassSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final arrivalR = PathGuidance.arrivalRadiusM(_accuracyM);
    final statusText = !_gpsFix
        ? 'Acquiring GPS…'
        : _arrived
            ? 'ARRIVED (±${arrivalR.toStringAsFixed(0)} m)'
            : _overshoot
                ? 'PASSED TARGET — TURN BACK'
                : PathGuidance.headingAwareMessage(
                    headingMagDeg: _headingMag,
                    desiredTrueBearingDeg: _targetBearingTrue,
                    xtM: widget.locateMode ? null : _xt,
                  );

    final onPath = statusText == 'ON PATH';
    final statusColor = !_gpsFix
        ? Colors.grey
        : _arrived
            ? Colors.green
            : _overshoot
                ? Colors.orange
                : onPath
                    ? Colors.green
                    : Colors.red;

    final line = widget.locateMode
        ? (_cur != null ? [_cur!, widget.end] : [widget.start, widget.end])
        : [widget.start, widget.end];

    final magTarget =
        PathGuidance.trueToMagnetic(_targetBearingTrue);
    final needsCalib =
        _compassAccuracy != null && _compassAccuracy! < 0; // platform-dependent

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.locateMode
            ? 'Locate ${widget.endLabel}'
            : '${widget.startLabel} → ${widget.endLabel}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: GpsService.accuracyColor(_accuracyM).withValues(alpha: 0.2),
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
          Expanded(
            flex: 5,
            child: HybridMap(
              center: _cur ?? widget.end,
              initialZoom: 16,
              polyline: line,
              userLocation: _cur,
              fitToFeatures: true,
              showDownloadButton: false,
              markers: [
                if (!widget.locateMode)
                  MapMarkerData(
                    point: widget.start,
                    label: widget.startLabel,
                    color: Colors.green,
                  ),
                MapMarkerData(
                  point: widget.end,
                  label: widget.endLabel,
                  color: PathfinderTheme.accent,
                ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: _permissionDenied
                  ? _permDenied()
                  : _error != null
                      ? Center(child: Text(_error!, textAlign: TextAlign.center))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              statusText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: _darken(statusColor),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_distRemain.toStringAsFixed(1)} m',
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            Text(
                              widget.locateMode
                                  ? 'to ${widget.endLabel}'
                                  : 'to endpoint',
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _metric('Bearing (true)',
                                    '${_targetBearingTrue.toStringAsFixed(0)}°'),
                                _metric('Mag target',
                                    '${magTarget.toStringAsFixed(0)}°'),
                                _metric('Heading (mag)',
                                    '${_headingMag.toStringAsFixed(0)}°'),
                                if (!widget.locateMode)
                                  _metric(
                                      'XT', '${_xt.abs().toStringAsFixed(1)} m'),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Compass is magnetic · path bearing is true '
                              '(Botswana declination ≈ 13° W)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            if (needsCalib ||
                                (_compassAccuracy != null &&
                                    (_compassAccuracy!).abs() > 30))
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Compass accuracy looks poor — wave the phone in a figure-8 to calibrate.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange.shade800),
                                ),
                              ),
                            const SizedBox(height: 12),
                            if (_gpsFix) _compassRose(magTarget),
                            if (!_gpsFix)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: CircularProgressIndicator(),
                              ),
                          ],
                        ),
            ),
          ),
        ],
      ),
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
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -_headingMag * pi / 180,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: aligned ? Colors.green : Colors.grey.shade400,
                  width: 3,
                ),
              ),
              child: const Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                      top: 4,
                      child: Text('N',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.red))),
                  Positioned(bottom: 4, child: Text('S')),
                  Positioned(left: 8, child: Text('W')),
                  Positioned(right: 8, child: Text('E')),
                ],
              ),
            ),
          ),
          Transform.rotate(
            angle: (magTarget - _headingMag) * pi / 180,
            child: Icon(Icons.navigation,
                size: 48,
                color: aligned ? Colors.green : PathfinderTheme.sky),
          ),
        ],
      ),
    );
  }
}

Color _darken(Color c) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness * 0.45).clamp(0.0, 1.0)).toColor();
}
