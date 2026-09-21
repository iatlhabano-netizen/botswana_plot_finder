import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui/home_hub.dart';
import 'ui/theme.dart';

class PathfinderApp extends StatefulWidget {
  const PathfinderApp({super.key});

  @override
  State<PathfinderApp> createState() => _PathfinderAppState();
}

class _PathfinderAppState extends State<PathfinderApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final sp = await SharedPreferences.getInstance();
    final dark = sp.getBool('darkMode');
    if (dark == null) return;
    setState(() => _themeMode = dark ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> toggleTheme() async {
    final sp = await SharedPreferences.getInstance();
    final next = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await sp.setBool('darkMode', next == ThemeMode.dark);
    setState(() => _themeMode = next);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pathfinder',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: PathfinderTheme.light(),
      darkTheme: PathfinderTheme.dark(),
      home: HomeHub(
        onToggleTheme: toggleTheme,
        isDark: _themeMode == ThemeMode.dark,
      ),
    );
  }
}
