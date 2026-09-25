import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart' as ll;

/// Android helpers that stay off the Dart geodesy path:
/// a short corridor beep, and magnetic declination from the platform
/// geomagnetic model (World Magnetic Model via [GeomagneticField]).
///
/// Falls back quietly when the channel is missing (tests, non-Android).
class DeviceBridge {
  static const _channel = MethodChannel('pathfinder/device');
  static DateTime? _lastBeep;

  /// Cooldown between corridor-leave beeps (ms).
  static const int beepCooldownMs = 1600;

  /// Test helper: clear debounce state.
  @visibleForTesting
  static void resetBeepCooldown() => _lastBeep = null;

  /// Audible beep. Cooldown stops a boundary flicker from machine-gunning.
  static Future<void> beep() async {
    final now = DateTime.now();
    if (_lastBeep != null &&
        now.difference(_lastBeep!).inMilliseconds < beepCooldownMs) {
      return;
    }
    _lastBeep = now;
    try {
      await _channel.invokeMethod<void>('beep');
    } catch (_) {
      SystemSound.play(SystemSoundType.alert);
    }
  }

  /// Declination in degrees, west negative (same sign as PathGuidance).
  /// Null when the platform cannot answer.
  static Future<double?> declination(ll.LatLng at, {double altitudeM = 0}) async {
    try {
      final v = await _channel.invokeMethod<num>('declination', {
        'lat': at.latitude,
        'lon': at.longitude,
        'alt': altitudeM,
      });
      if (v == null) return null;
      final deg = v.toDouble();
      if (deg.isNaN || deg.abs() > 40) return null;
      return deg;
    } catch (_) {
      return null;
    }
  }
}
