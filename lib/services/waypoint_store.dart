import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';

/// Persists labeled waypoints (SharedPreferences JSON).
class WaypointStore {
  static const _key = 'saved_waypoints_v1';

  static Future<List<SavedWaypoint>> loadAll() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) =>
              SavedWaypoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAll(List<SavedWaypoint> points) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _key,
      jsonEncode(points.map((p) => p.toJson()).toList()),
    );
  }

  static Future<SavedWaypoint> add(SavedWaypoint point) async {
    final all = await loadAll();
    all.insert(0, point);
    await saveAll(all);
    return point;
  }

  static Future<void> update(SavedWaypoint point) async {
    final all = await loadAll();
    final i = all.indexWhere((p) => p.id == point.id);
    if (i < 0) return;
    all[i] = point;
    await saveAll(all);
  }

  static Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((p) => p.id == id);
    await saveAll(all);
  }

  static Future<SavedWaypoint?> rename(String id, String label) async {
    final all = await loadAll();
    final i = all.indexWhere((p) => p.id == id);
    if (i < 0) return null;
    final updated = all[i].copyWith(label: label.trim());
    all[i] = updated;
    await saveAll(all);
    return updated;
  }
}
