import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages multiple named plots persisted via SharedPreferences.
class PlotProject {
  final String id;
  final String name;
  String zone;
  String datumKey;
  final List<Map<String, String>> corners; // {y, x}

  PlotProject({
    required this.id,
    required this.name,
    required this.zone,
    required this.datumKey,
    required this.corners,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'zone': zone,
        'datumKey': datumKey,
        'corners': corners,
      };

  factory PlotProject.fromJson(Map<String, dynamic> json) => PlotProject(
        id: json['id'] as String,
        name: json['name'] as String,
        zone: (json['zone'] ?? '25').toString(),
        datumKey: (json['datumKey'] ?? 'bw_cape').toString(),
        corners: (json['corners'] as List? ?? [])
            .map((c) => Map<String, String>.from(c as Map))
            .toList(),
      );
}

class PlotManager {
  static const _key = 'plot_projects';
  static const _activeKey = 'active_plot_id';

  static Future<List<PlotProject>> loadAll() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => PlotProject.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAll(List<PlotProject> projects) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _key,
      jsonEncode(projects.map((p) => p.toJson()).toList()),
    );
  }

  static Future<String?> activeId() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_activeKey);
  }

  static Future<void> setActive(String id) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_activeKey, id);
  }
}
