import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;

/// Shared GPS permission + stream helpers (Plot Finder / Pathfinder / Guidance).
class GpsService {
  /// Request permission when the user taps locate / use-my-position.
  /// Surfaces deniedForever with an in-app explanation (not silent).
  static Future<bool> ensurePermission(BuildContext context) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Location is off'),
            content: const Text(
              'Turn on device location (GPS) to find corners and walk a line outdoors.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Geolocator.openLocationSettings();
                },
                child: const Text('Open settings'),
              ),
            ],
          ),
        );
      }
      return false;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission denied. Tap again to retry.'),
          ),
        );
      }
      return false;
    }
    if (perm == LocationPermission.deniedForever) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Location blocked'),
            content: const Text(
              'Location permission is permanently denied. '
              'Open system settings and allow precise location for Pathfinder, '
              'then return and try again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Geolocator.openAppSettings();
                },
                child: const Text('Open app settings'),
              ),
            ],
          ),
        );
      }
      return false;
    }
    return true;
  }

  static Future<Position?> currentPosition(BuildContext context) async {
    if (!await ensurePermission(context)) return null;
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<ll.LatLng?> currentLatLng(BuildContext context) async {
    final p = await currentPosition(context);
    if (p == null) return null;
    return ll.LatLng(p.latitude, p.longitude);
  }

  static Stream<Position> watch({
    LocationAccuracy accuracy = LocationAccuracy.bestForNavigation,
    int distanceFilter = 1,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      ),
    );
  }

  /// Accuracy traffic-light: green ≤8 m, yellow ≤20 m, else red.
  static Color accuracyColor(double? accuracyM) {
    if (accuracyM == null) return Colors.grey;
    if (accuracyM <= 8) return Colors.green;
    if (accuracyM <= 20) return Colors.orange;
    return Colors.red;
  }

  static String accuracyLabel(double? accuracyM) {
    if (accuracyM == null) return 'GPS ±? m';
    return 'GPS ±${accuracyM.toStringAsFixed(0)} m';
  }
}
