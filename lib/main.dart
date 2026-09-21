import 'package:flutter/material.dart';
import 'app.dart';

export 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PathfinderApp());
}

/// Back-compat aliases for older tests / tooling.
typedef BotswanaPlotFinderApp = PathfinderApp;
typedef PlotFinderApp = PathfinderApp;
