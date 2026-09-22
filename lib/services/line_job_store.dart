import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/guided_path.dart';

/// Light persistence for multi-point pipe/fence jobs.
class LineJobStore {
  static const _key = 'line_jobs_v1';

  static Future<List<LineJob>> loadAll() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => LineJob.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAll(List<LineJob> jobs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _key,
      jsonEncode(jobs.map((j) => j.toJson()).toList()),
    );
  }

  static Future<LineJob> add(LineJob job) async {
    final all = await loadAll();
    all.insert(0, job);
    // Cap at 20 recent jobs
    if (all.length > 20) all.removeRange(20, all.length);
    await saveAll(all);
    return job;
  }

  static Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((j) => j.id == id);
    await saveAll(all);
  }
}
