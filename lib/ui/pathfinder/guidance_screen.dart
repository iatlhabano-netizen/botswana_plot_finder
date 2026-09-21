import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/path_guidance.dart';
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
  double _targetBearing = 0;
  double _heading = 0;
  bool _gpsFix = false;
  bool _overshoot = false;
  bool _permissionDenied = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _targetBearing = PathGuidance.bearingDeg(widget.start, widget.end);
    _distRemain = PathGuidance.distanceM(widget.start, widget.end);
    _startGps();
    _startCompass();
  }

  Future<void> _startGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _error = 'Turn on location services.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _permissionDenied = true);
        return;
      }

      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 1,
        ),
      ).listen((pos) {
        final cur = ll.LatLng(pos.latitude, pos.longitude);
        final start = widget.locateMode ? cur : widget.start;
        setState(() {
          _cur = cur;
          _gpsFix = true;
          _xt = widget.locateMode
              ? 0
              : PathGuidance.crossTrackM(cur, widget.start, widget.end);
          _distRemain = PathGuidance.distanceM(cur, widget.end);
          _targetBearing = PathGuidance.bearingDeg(start, widget.end);
          _overshoot = widget.locateMode
              ? false
              : PathGuidance.isPastEnd(cur, widget.start, widget.end);
        });
      });
    } catch (e) {
      setState(() => _error = 'GPS error: $e');
    }
  }

  void _startCompass() {
    _compassSub = FlutterCompass.events?.listen((event) {
      if (mounted) setState(() => _heading = event.heading ?? 0);
    });
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _compassSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onTrack = !_overshoot && _xt.abs() <= 1.5;
    final arrived = _gpsFix && _distRemain <= 3.0;
    final statusText = !_gpsFix
        ? 'Acquiring GPS…'
        : arrived
            ? 'ARRIVED'
            : _overshoot
                ? 'PASSED TARGET — TURN BACK'
                : widget.locateMode
                    ? 'HEAD TO TARGET'
                    : PathGuidance.crossTrackMessage(_xt);

    final statusColor = !_gpsFix
        ? Colors.grey
        : arrived
            ? Colors.green
            : _overshoot
                ? Colors.orange
                : (widget.locateMode || onTrack)
                    ? Colors.green
                    : Colors.red;

    final line = widget.locateMode
        ? (_cur != null ? [_cur!, widget.end] : [widget.start, widget.end])
        : [widget.start, widget.end];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.locateMode
            ? 'Locate ${widget.endLabel}'
            : '${widget.startLabel} → ${widget.endLabel}'),
        actions: [
          IconButton(
            tooltip: 'Keep screen on',
            icon: const Icon(Icons.screen_lock_portrait),
            onPressed: () {
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Immersive mode — swipe top to exit')),
              );
            },
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
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: _darken(statusColor),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 12),
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
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _metric('Bearing',
                                    '${_targetBearing.toStringAsFixed(0)}°'),
                                _metric('Heading',
                                    '${_heading.toStringAsFixed(0)}°'),
                                if (!widget.locateMode)
                                  _metric(
                                      'XT', '${_xt.abs().toStringAsFixed(1)} m'),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (_gpsFix) _compassRose(),
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

  Widget _permDenied() => const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Location permission is required for live guidance.\n\nOpen system settings and allow precise location for Pathfinder.',
          textAlign: TextAlign.center,
        ),
      );

  Widget _metric(String label, String value) => Column(
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      );

  Widget _compassRose() {
    final headingDiff = (_heading - _targetBearing + 360) % 360;
    final aligned = headingDiff < 8 || headingDiff > 352;
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -_heading * pi / 180,
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
            angle: (_targetBearing - _heading) * pi / 180,
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
