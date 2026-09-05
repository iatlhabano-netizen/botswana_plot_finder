import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'area_audit.dart';
import 'offline_tile_provider.dart';
import 'plot_calculator.dart';
import 'plot_exporter.dart';
import 'license_service.dart';
import 'license_screen.dart';
import 'plot_manager.dart';

// ==============================================================
// App
// ==============================================================
void main() => WidgetsFlutterBinding.ensureInitialized().then((_) => runApp(const PlotFinderApp()));

class PlotFinderApp extends StatefulWidget {
  const PlotFinderApp({super.key});
  @override
  State<PlotFinderApp> createState() => _PlotFinderAppState();
}

class _PlotFinderAppState extends State<PlotFinderApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final sp = await SharedPreferences.getInstance();
    final dark = sp.getBool('darkMode') ?? false;
    setState(() => _themeMode = dark ? ThemeMode.dark : ThemeMode.light);
  }

  void _toggleTheme() async {
    final sp = await SharedPreferences.getInstance();
    final isDark = _themeMode == ThemeMode.dark;
    await sp.setBool('darkMode', !isDark);
    setState(() => _themeMode = isDark ? ThemeMode.light : ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Plot Finder',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0070BA)),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0070BA),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: HomeScreen(onToggleTheme: _toggleTheme, isDark: _themeMode == ThemeMode.dark),
    );
  }
}

// ==============================================================
// LoConverter (cached projections, south-orientation via negate)
// ==============================================================
class CountrySystem {
  final String id;
  final String label;
  final List<int> availableZones;
  final String defaultDatum;
  const CountrySystem({required this.id, required this.label, required this.availableZones, required this.defaultDatum});
}

class DatumOption {
  final String key;
  final String label;
  const DatumOption({required this.key, required this.label});
}

class LoConverter {
  static final Map<String, proj4.Projection> _cache = {};

  static const List<CountrySystem> supportedCountries = [
    CountrySystem(id: 'BW', label: 'Botswana', availableZones: [21, 23, 25, 27, 29], defaultDatum: 'bw_cape'),
    CountrySystem(id: 'ZA', label: 'South Africa', availableZones: [17, 19, 21, 23, 25, 27, 29, 31, 33], defaultDatum: 'za_hart94'),
    CountrySystem(id: 'NA', label: 'Namibia', availableZones: [11, 13, 15, 17, 19], defaultDatum: 'na_schwarzeck'),
    CountrySystem(id: 'ZW', label: 'Zimbabwe', availableZones: [27, 29, 31, 33], defaultDatum: 'zw_arc1950'),
    CountrySystem(id: 'SZ', label: 'Eswatini', availableZones: [31], defaultDatum: 'sz_cape'),
    CountrySystem(id: 'LS', label: 'Lesotho', availableZones: [27, 29], defaultDatum: 'ls_cape'),
  ];

  static List<DatumOption> availableDatums(String countryCode) {
    switch (countryCode) {
      case 'ZA': return const [DatumOption(key: 'za_hart94', label: 'Hartebeesthoek94 (Modern)'), DatumOption(key: 'za_cape', label: 'Cape Datum (Legacy)')];
      case 'NA': return const [DatumOption(key: 'na_schwarzeck', label: 'Schwarzeck (Bessel 1841)')];
      case 'ZW': return const [DatumOption(key: 'zw_arc1950', label: 'Arc 1950')];
      case 'SZ': return const [DatumOption(key: 'sz_cape', label: 'Cape Datum')];
      case 'LS': return const [DatumOption(key: 'ls_cape', label: 'Cape Datum')];
      default: return const [DatumOption(key: 'bw_cape', label: 'Cape Datum'), DatumOption(key: 'bw_btrs02', label: 'BTRS02 / WGS84')];
    }
  }

  static String _def(int zone, String dk) {
    switch (dk) {
      case 'za_hart94': case 'bw_btrs02': case 'wgs84':
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 +ellps=WGS84 +units=m +no_defs';
      case 'za_cape': case 'sz_cape': case 'ls_cape':
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 +a=6378249.145 +rf=293.4663076563986 +towgs84=-136,-108,-292,0,0,0,0 +units=m +no_defs';
      case 'na_schwarzeck':
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 +ellps=bessel +towgs84=616,97,-251,0,0,0,0 +units=m +no_defs';
      case 'zw_arc1950':
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 +a=6378249.145 +rf=293.4663076563986 +towgs84=-142.5,-96.2,-291.6,0,0,0,0 +units=m +no_defs';
      default:
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 +a=6378249.145 +rf=293.4663076563986 +towgs84=-87,-105,-189,0,0,0,0 +units=m +no_defs';
    }
  }

  static ll.LatLng toWgs84({required double westing, required double southing, required int zone, required String datumKey}) {
    final k = 'LO${zone}_$datumKey';
    final src = _cache.putIfAbsent(k, () => proj4.Projection.add(k, _def(zone, datumKey)));
    final out = src.transform(proj4.Projection.get('EPSG:4326')!, proj4.Point(x: -westing, y: -southing));
    return ll.LatLng(out.y, out.x);
  }

  static ({double westing, double southing}) fromWgs84(ll.LatLng ll, {required int zone, required String datumKey}) {
    final k = 'LO${zone}_$datumKey';
    final src = _cache.putIfAbsent(k, () => proj4.Projection.add(k, _def(zone, datumKey)));
    final out = proj4.Projection.get('EPSG:4326')!.transform(src, proj4.Point(x: ll.longitude, y: ll.latitude));
    return (westing: -out.x, southing: -out.y);
  }

  static String? validateLo(double westing, double southing) {
    if (southing < 1500000 || southing > 3200000) return 'X outside SADC range. Check zone/datum.';
    if (westing.abs() > 200000) return 'Y >200 km from CM — check Lo zone.';
    return null;
  }
}

// ==============================================================
// BushNavigator (Cross Track Error + Along Track)
// ==============================================================
class BushNavigator {
  static const double R = 6371000.0;
  static const Distance _d = Distance();

  static double distanceM(ll.LatLng a, ll.LatLng b) => _d.as(ll.LengthUnit.Meter, a, b);

  static double _brg(ll.LatLng a, ll.LatLng b) {
    final la = a.latitude * pi / 180, lb = b.latitude * pi / 180;
    final dl = (b.longitude - a.longitude) * pi / 180;
    return atan2(sin(dl) * cos(lb), cos(la) * sin(lb) - sin(la) * cos(lb) * cos(dl));
  }

  static double bearingDeg(ll.LatLng a, ll.LatLng b) => (_brg(a, b) * 180 / pi + 360) % 360;

  static double crossTrack(ll.LatLng cur, ll.LatLng start, ll.LatLng end) {
    final d13 = distanceM(start, cur) / R;
    return asin(sin(d13) * sin(_brg(start, cur) - _brg(start, end))) * R;
  }

  /// Signed along-track: negative = target is behind you (overshoot).
  static double alongTrack(ll.LatLng cur, ll.LatLng start, ll.LatLng end) {
    final d13 = distanceM(start, cur) / R;
    final d12 = distanceM(start, end) / R;
    final t = _brg(start, cur) - _brg(start, end);
    final cosA = (cos(d13) * cos(d12) + sin(d13) * sin(d12) * cos(t)).clamp(-1.0, 1.0);
    final mag = acos(cosA) * R;
    return cos(t) >= 0 ? mag : -mag;
  }
}

// ==============================================================
// Home Screen (Feature 2: GPS Lo display, Feature 4: Multi-plot, Feature 8: Dark mode toggle)
// ==============================================================
class HomeScreen extends StatefulWidget {
  final VoidCallback onToggleTheme;
  final bool isDark;
  const HomeScreen({super.key, required this.onToggleTheme, required this.isDark});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CountrySystem _selectedCountry = LoConverter.supportedCountries[0];
  int _selectedZone = 25;
  String _selectedDatum = 'bw_cape';
  final List<CornerInput> _corners = [];
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  bool _scanning = false;
  double? _declaredHa;
  LicenseInfo _license = LicenseInfo.expired();

  // Feature 2: GPS stream
  StreamSubscription<Position>? _gpsSub;
  ll.LatLng? _currentPos;

  // Feature 4: Multi-plot
  List<PlotProject> _projects = [];
  PlotProject? _activeProject;

  @override
  void initState() {
    super.initState();
    _restore();
    _loadLicense();
    _startGps();
  }

  @override
  void dispose() {
    _textRecognizer.close();
    _gpsSub?.cancel();
    for (var c in _corners) { c.yController.dispose(); c.xController.dispose(); }
    super.dispose();
  }

  // --- GPS (Feature 2) ---
  void _startGps() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((pos) => setState(() => _currentPos = ll.LatLng(pos.latitude, pos.longitude)));
  }

  // --- Persistence ---
  Future<void> _loadLicense() async {
    final info = await LicenseService.load();
    if (mounted) setState(() => _license = info);
  }

  Future<void> _restore() async {
    final sp = await SharedPreferences.getInstance();
    _selectedZone = sp.getInt('zone') ?? 25;
    _selectedDatum = sp.getString('datumKey') ?? 'bw_cape';
    _declaredHa = sp.getDouble('declaredHa');

    // Load projects (Feature 4)
    _projects = await PlotManager.loadAll();
    final activeId = await PlotManager.activeId();
    _activeProject = _projects.where((p) => p.id == activeId).firstOrNull;

    if (_activeProject != null) {
      _corners.clear();
      for (final c in _activeProject!.corners) {
        _corners.add(CornerInput(c['y'] ?? '', c['x'] ?? '');
      }
      final zoneInt = int.tryParse(_activeProject!.zone);
      if (zoneInt != null) _selectedZone = zoneInt;
      _selectedDatum = _activeProject!.datumKey;
    } else if (_corners.isEmpty) {
      _corners.addAll([
        CornerInput('-74283', '2609149'), CornerInput('-74593', '2609153'),
        CornerInput('-74589', '2609473'), CornerInput('-74279', '2609469'),
      ]);
    }
    setState(() {});
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('zone', _selectedZone);
    await sp.setString('datumKey', _selectedDatum);
    if (_declaredHa != null) await sp.setDouble('declaredHa', _declaredHa!);

    // Persist active project (Feature 4)
    if (_activeProject != null) {
      _activeProject!.zone = _selectedZone.toString();
      _activeProject!.datumKey = _selectedDatum;
      _activeProject!.corners.clear();
      for (final c in _corners) {
        _activeProject!.corners.add({'y': c.yController.text, 'x': c.xController.text});
      }
      await PlotManager.saveAll(_projects);
    } else {
      await sp.setStringList('corners', [for (final c in _corners) '${c.yController.text}|${c.xController.text}']);
    }
  }

  void _onCountryChanged(CountrySystem c) {
    setState(() {
      _selectedCountry = c;
      _selectedZone = c.availableZones.contains(_selectedZone) ? _selectedZone : c.availableZones.first;
      _selectedDatum = c.defaultDatum;
    });
    _persist();
  }

  void _addCorner() { setState(() => _corners.add(CornerInput('', ''))); _persist(); }
  void _removeCorner(int i) {
    if (_corners.length > 1) { setState(() => _corners.removeAt(i)); _persist(); }
  }

  // --- Multi-plot management (Feature 4) ---
  void _showPlotManager() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.3,
        expand: false,
        builder: (_, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('My Plots', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Color(0xFF0070BA), size: 30),
                    onPressed: () { Navigator.pop(ctx); _createNewPlot(); },
                  ),
                ],
              ),
            ),
            Expanded(
              child: _projects.isEmpty
                  ? const Center(child: Text('No saved plots yet.\nTap + to create one.', textAlign: TextAlign.center))
                  : ListView.builder(
                      controller: scroll,
                      itemCount: _projects.length,
                      itemBuilder: (_, i) {
                        final p = _projects[i];
                        final isActive = p.id == _activeProject?.id;
                        return ListTile(
                          leading: Icon(Icons.map, color: isActive ? const Color(0xFF0070BA) : Colors.grey),
                          title: Text(p.name, style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
                          subtitle: Text('${p.corners.length} corners · Lo${p.zone}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isActive) const Icon(Icons.check_circle, color: Color(0xFF0070BA), size: 20),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                onPressed: () => _deletePlot(p),
                              ),
                            ],
                          ),
                          onTap: () { Navigator.pop(ctx); _loadPlot(p); },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _createNewPlot() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Plot'),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(hintText: 'e.g. Farm 4273, Phakalane 12', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, nameCtrl.text), child: const Text('Create')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;

    // Save current corners first
    await _persist();

    final project = PlotProject(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.trim(),
      zone: _selectedZone.toString(),
      datumKey: _selectedDatum,
      corners: [for (final c in _corners) {'y': c.yController.text, 'x': c.xController.text}],
    );
    _projects.add(project);
    _activeProject = project;
    await PlotManager.saveAll(_projects);
    await PlotManager.setActive(project.id);
    setState(() {});
    _toast('Plot "${project.name}" created');
  }

  void _loadPlot(PlotProject p) async {
    await _persist(); // save current first
    _activeProject = p;
    await PlotManager.setActive(p.id);
    setState(() {
      _corners.clear();
      for (final c in p.corners) { _corners.add(CornerInput(c['y'] ?? '', c['x'] ?? '')); }
      _selectedZone = int.tryParse(p.zone) ?? 25;
      _selectedDatum = p.datumKey;
    });
  }

  void _deletePlot(PlotProject p) async {
    _projects.remove(p);
    if (_activeProject?.id == p.id) { _activeProject = null; await PlotManager.setActive(''); }
    await PlotManager.saveAll(_projects);
    setState(() {});
    _toast('Deleted "${p.name}"');
  }

  void _toast(String m) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m))); }

  // --- OCR (Feature 3: review dialog, gallery + camera) ---
  Future<void> _scanCertificate() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Photograph the certificate'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
      ])),
    );
    if (source == null || !mounted) return;

    setState(() => _scanning = true);
    try {
      final photo = await ImagePicker().pickImage(source: source, maxWidth: 2600);
      if (photo == null) return;
      final text = (await _textRecognizer.processImage(InputImage.fromFilePath(photo.path))).text;
      String cleaned = text.replaceAll(RegExp(r'[oO](?=\d)'), '0');

      final reYX = RegExp(r'Y\s*[:=]?\s*([+-]?\d[\d\s]{2,9}\d(?:\.\d+)?)\s*[,;:\s]+\s*X\s*[:=]?\s*([+-]?\d[\d\s]{4,9}\d(?:\.\d+)?)', caseSensitive: false);
      final reXY = RegExp(r'X\s*[:=]?\s*([+-]?\d[\d\s]{4,9}\d(?:\.\d+)?)\s*[,;:\s]+\s*Y\s*[:=]?\s*([+-]?\d[\d\s]{2,9}\d(?:\.\d+)?)', caseSensitive: false);

      final parsed = <({double w, double s})>[];
      final spans = <(int, int)>[];
      for (final m in reYX.allMatches(cleaned)) {
        if (spans.any((sp) => m.start < sp.$2 && m.end > sp.$1)) continue;
        final w = double.tryParse(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
        final s = double.tryParse(m.group(2)!.replaceAll(RegExp(r'\s'), ''));
        if (w != null && s != null) { parsed.add((w: w, s: s)); spans.add((m.start, m.end)); }
      }
      for (final m in reXY.allMatches(cleaned)) {
        if (spans.any((sp) => m.start < sp.$2 && m.end > sp.$1)) continue;
        final s = double.tryParse(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
        final w = double.tryParse(m.group(2)!.replaceAll(RegExp(r'\s'), ''));
        if (w != null && s != null) { parsed.add((w: w, s: s)); spans.add((m.start, m.end)); }
      }

      if (!mounted) return;
      if (parsed.isEmpty) { _toast('No coordinate pairs found. Retry with better lighting.'); return; }

      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${parsed.length} coordinate(s) found'),
          content: SizedBox(width: double.maxFinite, height: 200, child: ListView.builder(
            itemCount: parsed.length,
            itemBuilder: (_, i) => ListTile(dense: true,
              leading: CircleAvatar(radius: 12, backgroundColor: const Color(0xFF0070BA), child: Text('${i+1}', style: const TextStyle(color: Colors.white, fontSize: 11))),
              title: Text('Y ${parsed[i].w.toStringAsFixed(0)}   X ${parsed[i].s.toStringAsFixed(0)}')),
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'append'), child: const Text('Append')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'replace'), child: const Text('Replace')),
          ],
        ),
      );
      if (action == null || !mounted) return;

      setState(() {
        if (action == 'replace') { for (final c in _corners) { c.yController.dispose(); c.xController.dispose(); } _corners.clear(); }
        for (final p in parsed) _corners.add(CornerInput(p.w.toStringAsFixed(0), p.s.toStringAsFixed(0)));
      });

      // Auto-detect declared area
      final detectedHa = AreaAuditor.extractStatedArea(cleaned);
      if (detectedHa != null) { setState(() => _declaredHa = detectedHa); _persist(); }
      _toast('${parsed.length} coordinate(s) loaded!');
    } catch (e) {
      _toast('Scan failed: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  List<ll.LatLng> get _points => [for (final c in _corners) ...[() { final w = c.westing; final s = c.southing; if (w == null || s == null) return null; return LoConverter.toWgs84(westing: w, southing: s, zone: _selectedZone, datumKey: _selectedDatum); }()]].whereType<ll.LatLng>().toList();

  void _openPlotMap() {
    final pts = _points;
    if (pts.length < 2) { _toast('Enter at least two valid corners.'); return; }
    final loCorners = _corners.where((c) => c.westing != null && c.southing != null)
        .map((c) => {'Y': c.westing!, 'X': c.southing!}).toList();
    Navigator.push(context, MaterialPageRoute(builder: (_) => PlotMapScreen(
      points: pts, loCorners: loCorners, zone: _selectedZone, datumKey: _selectedDatum, declaredHa: _declaredHa,
      projectName: _activeProject?.name, license: _license,
    )));
  }

  @override
  Widget build(BuildContext context) {
    final datums = LoConverter.availableDatums(_selectedCountry.id);
    final gpsWgs = _currentPos != null ? '${_currentPos!.latitude.toStringAsFixed(6)}, ${_currentPos!.longitude.toStringAsFixed(6)}' : 'Acquiring...';
    String gpsLo = 'Acquiring...';
    if (_currentPos != null) {
      final lo = LoConverter.fromWgs84(_currentPos!, zone: _selectedZone, datumKey: _selectedDatum);
      gpsLo = 'Y: ${lo.westing.toStringAsFixed(0)}  X: ${lo.southing.toStringAsFixed(0)}';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_activeProject?.name ?? 'Plot Finder', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0070BA),
        actions: [
          IconButton(
            icon: Icon(_license.isFieldUnlock ? Icons.verified : Icons.lock_open, color: Colors.white),
            tooltip: 'License',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const LicenseScreen()));
              _loadLicense();
            },
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: !_license.isFieldUnlock,
              label: const Text('Pro', style: TextStyle(fontSize: 8, color: Colors.white)),
              backgroundColor: Colors.orange,
              child: const Icon(Icons.folder_open, color: Colors.white),
            ),
            tooltip: _license.isFieldUnlock ? 'My Plots' : 'My Plots (Field Unlock)',
            onPressed: _showPlotManager,
          ),
          IconButton(icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode, color: Colors.white), tooltip: 'Toggle theme', onPressed: widget.onToggleTheme),
          IconButton(
            icon: const Icon(Icons.camera_alt, color: Colors.white),
            tooltip: 'Scan Certificate',
            onPressed: _scanning ? null : () async {
              if (_license.isFieldUnlock) { _scanCertificate(); return; }
              final go = await LicenseService.require(context, LicenseTier.fieldUnlock, 'Certificate Scanner');
              if (go) _scanCertificate();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Feature 2: Live GPS Display
          // License status row
          if (_license.isActive && _license.tier != LicenseTier.free)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Icon(_license.isPro ? Icons.workspace_premium : Icons.verified, color: _license.isPro ? Colors.amber : const Color(0xFF0070BA), size: 20),
                const SizedBox(width: 6),
                Text(_license.tier.label, style: TextStyle(fontWeight: FontWeight.bold, color: _license.isPro ? Colors.amber.shade800 : const Color(0xFF0070BA))),
              ]),
            ),
          if (_currentPos != null)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.my_location, size: 16), const SizedBox(width: 6),
                    const Text('Current Position', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ]),
                  const SizedBox(height: 6),
                  _gpsRow('WGS84', gpsWgs),
                  _gpsRow('Lo', gpsLo),
                ]),
              ),
            ),
          if (_currentPos != null) const SizedBox(height: 12),

          // Country / Zone / Datum
          Card(elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              DropdownButtonFormField<CountrySystem>(value: _selectedCountry,
                decoration: const InputDecoration(labelText: 'Country', border: OutlineInputBorder()),
                items: LoConverter.supportedCountries.map((c) => DropdownMenuItem(value: c, child: Text('${c.label} (${c.id})'))).toList(),
                onChanged: (v) { if (v != null) _onCountryChanged(v); }),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(value: _selectedCountry.availableZones.contains(_selectedZone) ? _selectedZone : _selectedCountry.availableZones.first,
                decoration: const InputDecoration(labelText: 'Lo Central Meridian', border: OutlineInputBorder()),
                items: _selectedCountry.availableZones.map((z) => DropdownMenuItem(value: z, child: Text('Lo$z'))).toList(),
                onChanged: (v) { setState(() => _selectedZone = v!); _persist(); }),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(value: datums.any((d) => d.key == _selectedDatum) ? _selectedDatum : datums.first.key,
                decoration: const InputDecoration(labelText: 'Datum', border: OutlineInputBorder()),
                items: datums.map((d) => DropdownMenuItem(value: d.key, child: Text(d.label))).toList(),
                onChanged: (v) { setState(() => _selectedDatum = v!); _persist(); }),
            ]))),
          const SizedBox(height: 16),

          // Corner list
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Corner Coordinates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextButton.icon(onPressed: _addCorner, icon: const Icon(Icons.add), label: const Text('Add Corner')),
          ]),
          ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: _corners.length,
            itemBuilder: (_, idx) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                CircleAvatar(radius: 14, backgroundColor: const Color(0xFF0070BA),
                  child: Text('${idx+1}', style: const TextStyle(color: Colors.white, fontSize: 12))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _corners[idx].yController,
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  decoration: InputDecoration(labelText: 'Y (Westing)', contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _corners[idx].xController,
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  decoration: InputDecoration(labelText: 'X (Southing)', contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
                IconButton(icon: const Icon(Icons.copy, size: 18, color: Colors.grey), tooltip: 'Copy coordinates', // Feature 3
                  onPressed: () {
                    final y = _corners[idx].yController.text;
                    final x = _corners[idx].xController.text;
                    Clipboard.setData(ClipboardData(text: 'Y: $y, X: $x'));
                    _toast('Corner ${idx+1} copied');
                  }),
                IconButton(icon: const Icon(Icons.delete, color: Colors.grey), onPressed: () => _removeCorner(idx)),
              ]),
            )),
          const SizedBox(height: 24),

          // View on Map button
          SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0070BA), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: _openPlotMap, icon: const Icon(Icons.map, color: Colors.white),
            label: const Text('View Plot on Map', style: TextStyle(color: Colors.white, fontSize: 16)))),
        ]),
      ),
    );
  }

  Widget _gpsRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    ]),
  );
}

// ==============================================================
// CornerInput
// ==============================================================
class CornerInput {
  final TextEditingController yController;
  final TextEditingController xController;
  CornerInput(String y, String x) : yController = TextEditingController(text: y), xController = TextEditingController(text: x);
  double? get westing => double.tryParse(yController.text.trim());
  double? get southing => double.tryParse(xController.text.trim());
}

// ==============================================================
// Plot Map Screen (Feature 1: offline tiles, Feature 3: copy, Feature 5: tap-to-measure, Feature 7: CSV/JSON)
// ==============================================================
class PlotMapScreen extends StatefulWidget {
  final List<ll.LatLng> points;
  final List<Map<String, double>> loCorners;
  final int zone;
  final String datumKey;
  final double? declaredHa;
  final String? projectName;
  final LicenseInfo license;
  PlotMapScreen({super.key, required this.points, required this.loCorners, required this.zone, required this.datumKey, this.declaredHa, this.projectName, LicenseInfo? license})
      : license = license ?? LicenseInfo.expired();

  @override
  State<PlotMapScreen> createState() => _PlotMapScreenState();
}

class _PlotMapScreenState extends State<PlotMapScreen> {
  final MapController _mapCtrl = MapController();
  int? _routeStart, _routeEnd;

  // Feature 5: Tap-to-measure
  bool _measureMode = false;
  ll.LatLng? _measureA;
  ll.LatLng? _measureB;
  double? _measureDist;
  double? _measureBearing;

  void _onMapTap(TapPosition tp, ll.LatLng latlng) {
    if (!_measureMode) return;
    setState(() {
      if (_measureA == null || _measureB != null) {
        _measureA = latlng;
        _measureB = null;
        _measureDist = null;
        _measureBearing = null;
      } else {
        _measureB = latlng;
        _measureDist = BushNavigator.distanceM(_measureA!, latlng);
        _measureBearing = BushNavigator.bearingDeg(_measureA!, latlng);
      }
    });
  }

  void _launchNav(ll.LatLng pt) async {
    final uri = Uri.parse('google.navigation:q=${pt.latitude},${pt.longitude}');
    final fallback = Uri.parse('https://www.google.com/maps/search/?api=1&query=${pt.latitude},${pt.longitude}');
    if (await canLaunchUrl(uri)) { await launchUrl(uri); }
    else { await launchUrl(fallback, mode: LaunchMode.externalApplication); }
  }

  // Feature 3: Copy coordinates
  void _copyCoords(ll.LatLng pt) {
    final lo = LoConverter.fromWgs84(pt, zone: widget.zone, datumKey: widget.datumKey);
    final text = 'WGS84: ${pt.latitude.toStringAsFixed(6)}, ${pt.longitude.toStringAsFixed(6)}\nLo: Y ${lo.westing.toStringAsFixed(0)}, X ${lo.southing.toStringAsFixed(0)}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coordinates copied')));
  }

  // Feature 7: CSV/JSON export
  void _exportCsv() {
    final csv = PlotExporter.generateCsv(
      westings: widget.loCorners.map((c) => c['Y']!).toList(),
      southings: widget.loCorners.map((c) => c['X']!).toList(),
      latitudes: widget.points.map((p) => p.latitude).toList(),
      longitudes: widget.points.map((p) => p.longitude).toList(),
      areaHectares: PlotCalculator.calculateFromLo(widget.loCorners).areaHectares,
    );
    PlotExporter.shareFile(content: csv, fileName: 'plot_data.csv', mimeType: 'text/csv');
  }

  void _exportJson() {
    final summary = PlotCalculator.calculateFromLo(widget.loCorners);
    final json = PlotExporter.generateJson(
      zone: widget.zone, datumKey: widget.datumKey,
      westings: widget.loCorners.map((c) => c['Y']!).toList(),
      southings: widget.loCorners.map((c) => c['X']!).toList(),
      latitudes: widget.points.map((p) => p.latitude).toList(),
      longitudes: widget.points.map((p) => p.longitude).toList(),
      areaHectares: summary.areaHectares, perimeterMeters: summary.perimeterMeters,
    );
    PlotExporter.shareFile(content: json, fileName: 'plot_data.json', mimeType: 'application/json');
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.points.isNotEmpty ? widget.points.first : const ll.LatLng(-23.58, 25.72);
    final summary = PlotCalculator.calculateFromLo(widget.loCorners);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectName ?? 'Plot Boundary', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0070BA),
        actions: [
          // Feature 5: Measure toggle
          IconButton(
            icon: Icon(_measureMode ? Icons.straighten : Icons.straighten, color: _measureMode ? Colors.yellow : Colors.white),
            tooltip: _measureMode ? 'Exit measure' : 'Measure distance',
            onPressed: () => setState(() { _measureMode = !_measureMode; _measureA = null; _measureB = null; _measureDist = null; }),
          ),
          // Feature 7: Export menu (KML, GPX, CSV, JSON) — gated
          if (_license.isFieldUnlock)
          PopupMenuButton<String>(
            icon: const Icon(Icons.share, color: Colors.white), tooltip: 'Export',
            onSelected: (c) async {
              if (c == 'kml') { PlotExporter.shareFile(content: PlotExporter.generateKml(widget.points), fileName: 'plot_boundary.kml', mimeType: 'application/vnd.google-earth.kml+xml'); }
              else if (c == 'gpx') { PlotExporter.shareFile(content: PlotExporter.generateGpx(widget.points), fileName: 'plot_boundary.gpx', mimeType: 'application/gpx+xml'); }
              else if (c == 'csv') { _exportCsv(); }
              else if (c == 'json') { _exportJson(); }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'kml', child: Row(children: [Icon(Icons.public, color: Color(0xFF0070BA)), SizedBox(width: 8), Text('KML (Google Earth)')])),
              PopupMenuItem(value: 'gpx', child: Row(children: [Icon(Icons.gps_fixed, color: Color(0xFF0070BA)), SizedBox(width: 8), Text('GPX (Garmin GPS)')])),
              PopupMenuItem(value: 'csv', child: Row(children: [Icon(Icons.table_chart, color: Color(0xFF0070BA)), SizedBox(width: 8), Text('CSV (Excel)')])),
              PopupMenuItem(value: 'json', child: Row(children: [Icon(Icons.code, color: Color(0xFF0070BA)), SizedBox(width: 8), Text('JSON (Survey software)')])),
            ],
          ),
        ],
      ),
      body: Stack(children: [
        // Feature 1: Offline tile caching
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(initialCenter: center, initialZoom: 15.0, onTap: _onMapTap),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              tileProvider: OfflineTileProvider(),
              userAgentPackageName: 'com.example.plot_finder',
            ),
            if (widget.points.length >= 3)
              PolygonLayer(polys: [Polygon(points: widget.points, color: Colors.blue.withOpacity(0.2), borderColor: const Color(0xFF0070BA), borderStrokeWidth: 3)]),
            MarkerLayer(markers: widget.points.asMap().entries.map((e) => Marker(
              point: e.value, width: 80, height: 80,
              child: GestureDetector(
                onTap: () => _showCornerSheet(e.key, e.value),
                child: Column(children: [
                  Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.black26)),
                    child: Text('C${e.key+1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                  const Icon(Icons.location_pin, color: Colors.red, size: 36),
                ]),
              ),
            )).toList()),
            // Feature 5: Measure markers
            if (_measureA != null)
              Marker(point: _measureA!, width: 30, height: 30, child: const Icon(Icons.circle, color: Colors.green, size: 24)),
            if (_measureB != null)
              Marker(point: _measureB!, width: 30, height: 30, child: const Icon(Icons.circle, color: Colors.red, size: 24)),
            if (_measureA != null && _measureB != null)
              PolylineLayer(polylines: [Polyline(points: [_measureA!, _measureB!], color: Colors.orange, strokeWidth: 3)]),
            // OSM Attribution
            SimpleAttributionWidget(source: const Text('OpenStreetMap'), onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright'))),
          ],
        ),

        // Feature 5: Measure result overlay
        if (_measureDist != null)
          Positioned(top: 12, left: 12, child: Card(
            color: Colors.orange.shade50,
            child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_measureDist!.toStringAsFixed(1)} m', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange)),
              Text('${_measureBearing!.toStringAsFixed(0)}°', style: const TextStyle(fontSize: 14, color: Colors.grey)),
            ])),
          )),

        // Feature 5: Measure mode indicator
        if (_measureMode)
          Positioned(top: 12, right: 12, child: Chip(
            avatar: const Icon(Icons.straighten, size: 16),
            label: Text(_measureA == null ? 'Tap point A' : 'Tap point B'),
            backgroundColor: Colors.orange.shade100,
          )),

        // Area summary card
        Positioned(top: 12, left: _measureMode ? 12 : 12, right: _measureMode ? 120 : 12, child: Column(children: [
          PlotSummaryCard(summary: summary),
          if (widget.declaredHa != null)
            AreaAuditBanner(audit: AreaAuditor.auditArea(computedHectares: summary.areaHectares, statedHectares: widget.declaredHa!)),
        ])),

        // Bush run controls
        Positioned(bottom: 16, left: 16, right: 16, child: Card(
          elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Bush Line Guidance', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: DropdownButtonFormField<int>(value: _routeStart,
                decoration: const InputDecoration(labelText: 'From', border: OutlineInputBorder()),
                items: List.generate(widget.points.length, (i) => DropdownMenuItem(value: i, child: Text('C${i+1}'))),
                onChanged: (v) => setState(() => _routeStart = v))),
              const SizedBox(width: 8),
              Expanded(child: DropdownButtonFormField<int>(value: _routeEnd,
                decoration: const InputDecoration(labelText: 'To', border: OutlineInputBorder()),
                items: List.generate(widget.points.length, (i) => DropdownMenuItem(value: i, child: Text('C${i+1}'))),
                onChanged: (v) => setState(() => _routeEnd = v))),
            ]),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () async {
                if (_routeStart == null || _routeEnd == null || _routeStart == _routeEnd) { _toast('Select two different corners.'); return; }
                if (!widget._license.isFieldUnlock) {
                  final go = await LicenseService.require(context, LicenseTier.fieldUnlock, 'Bush Navigation');
                  if (!go) return;
                }
                if (!context.mounted) return;
                Navigator.push(context, MaterialPageRoute(builder: (_) => BushGuidanceScreen(
                  startPoint: widget.points[_routeStart!], endPoint: widget.points[_routeEnd!],
                  startLabel: 'C${_routeStart!+1}', endLabel: 'C${_routeEnd!+1}')));
              },
              icon: const Icon(Icons.compass_calibration, color: Colors.white),
              label: const Text('Start Guidance', style: TextStyle(color: Colors.white)),
            )),
          ])),
        )),
      ]),
    );
  }

  void _showCornerSheet(int idx, ll.LatLng pt) {
    final lo = LoConverter.fromWgs84(pt, zone: widget.zone, datumKey: widget.datumKey);
    showModalBottomSheet(context: context, builder: (ctx) => Container(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Corner ${idx+1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text('Lat: ${pt.latitude.toStringAsFixed(7)}'),
        Text('Lon: ${pt.longitude.toStringAsFixed(7)}'),
        Text('Lo Y: ${lo.westing.toStringAsFixed(0)}  X: ${lo.southing.toStringAsFixed(0)}'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: ElevatedButton.icon(
            onPressed: () { _copyCoords(pt); Navigator.pop(ctx); },
            icon: const Icon(Icons.copy), label: const Text('Copy'))),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton.icon(
            onPressed: () { _launchNav(pt); Navigator.pop(ctx); },
            icon: const Icon(Icons.navigation), label: const Text('Navigate'))),
        ]),
      ]),
    ));
  }

  void _toast(String m) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m))); }
}

// ==============================================================
// Area Audit Banner
// ==============================================================
class AreaAuditBanner extends StatelessWidget {
  final AreaVerificationResult audit;
  const AreaAuditBanner({super.key, required this.audit});
  @override
  Widget build(BuildContext context) {
    if (audit.statedHectares <= 0) return const SizedBox.shrink();
    final isAlert = audit.isMismatch;
    final bg = isAlert ? Colors.amber.shade50 : Colors.green.shade50;
    final border = isAlert ? Colors.orange.shade700 : Colors.green.shade700;
    final ic = isAlert ? Colors.orange.shade800 : Colors.green.shade800;
    return Container(
      margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: border, width: 1.2)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(isAlert ? Icons.warning_amber_rounded : Icons.verified_user_outlined, color: ic, size: 24),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isAlert ? 'Area Mismatch Alert' : 'Certificate Verified', style: TextStyle(fontWeight: FontWeight.bold, color: ic, fontSize: 13)),
          const SizedBox(height: 3),
          Text(audit.message, style: TextStyle(fontSize: 12, color: isAlert ? Colors.brown.shade900 : Colors.green.shade900)),
          if (isAlert) const SizedBox(height: 4),
          if (isAlert) const Text('Verify corner order and coordinate signs.', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.black54)),
        ])),
      ]),
    );
  }
}

// ==============================================================
// Plot Summary Card
// ==============================================================
class PlotSummaryCard extends StatelessWidget {
  final PlotCalculationResult summary;
  const PlotSummaryCard({super.key, required this.summary});
  @override
  Widget build(BuildContext context) {
    return Card(elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Total Land Area', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text('${summary.areaHectares.toStringAsFixed(2)} Ha', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0070BA))),
            Text('${summary.areaSqMeters.toStringAsFixed(0)} m²', style: const TextStyle(fontSize: 12)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('Perimeter', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text('${summary.perimeterMeters.toStringAsFixed(1)} m', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ]),
        ]),
        const Divider(height: 18),
        const Text('Fence Lines:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: summary.segments.map((s) => Chip(
          visualDensity: VisualDensity.compact, backgroundColor: Colors.grey.shade100,
          label: Text('C${s.fromCorner} → C${s.toCorner}: ${s.lengthMeters.toStringAsFixed(1)}m', style: const TextStyle(fontSize: 11)),
        )).toList()),
      ])),
    );
  }
}

// ==============================================================
// Bush Guidance Screen (Feature 6: Compass overlay)
// ==============================================================
class BushGuidanceScreen extends StatefulWidget {
  final ll.LatLng startPoint, endPoint;
  final String startLabel, endLabel;
  const BushGuidanceScreen({super.key, required this.startPoint, required this.endPoint, required this.startLabel, required this.endLabel});

  @override
  State<BushGuidanceScreen> createState() => _BushGuidanceScreenState();
}

class _BushGuidanceScreenState extends State<BushGuidanceScreen> {
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<CompassEvent>? _compassSub;
  double _xt = 0, _distRemain = 0, _targetBearing = 0;
  double _heading = 0; // Feature 6: compass heading
  bool _gpsFix = false;
  bool _overshoot = false;

  @override
  void initState() {
    super.initState();
    _targetBearing = BushNavigator.bearingDeg(widget.startPoint, widget.endPoint);
    _startGps();
    _startCompass();
  }

  void _startGps() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) return;

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 1),
    ).listen((pos) {
      final cur = ll.LatLng(pos.latitude, pos.longitude);
      setState(() {
        _gpsFix = true;
        _xt = BushNavigator.crossTrack(cur, widget.startPoint, widget.endPoint);
        _distRemain = BushNavigator.distanceM(cur, widget.endPoint);
        _overshoot = BushNavigator.alongTrack(cur, widget.startPoint, widget.endPoint) >
            BushNavigator.distanceM(widget.startPoint, widget.endPoint);
      });
    });
  }

  void _startCompass() {
    if (!FlutterCompass.isSupported) return;
    _compassSub = FlutterCompass.events?.listen((event) {
      if (mounted) setState(() => _heading = event.heading ?? 0);
    });
  }

  @override
  void dispose() { _gpsSub?.cancel(); _compassSub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final onTrack = !_overshoot && _xt.abs() <= 1.5;
    final veer = _xt > 0 ? 'VEER LEFT ${_xt.abs().toStringAsFixed(1)} m' : 'VEER RIGHT ${_xt.abs().toStringAsFixed(1)} m';
    final headingDiff = (_heading - _targetBearing + 360) % 360;
    final headingCorrect = headingDiff < 5 || headingDiff > 355;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.startLabel} → ${widget.endLabel}', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0070BA),
      ),
      body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        // Feature 6: Compass + bearing display
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Bearing: ${_targetBearing.toStringAsFixed(0)}°', style: const TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(width: 16),
          Text('Heading: ${_heading.toStringAsFixed(0)}°', style: TextStyle(fontSize: 18, color: headingCorrect ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 24),

        // Feature 6: Compass rose
        if (_gpsFix) SizedBox(width: 160, height: 160, child: Stack(alignment: Alignment.center, children: [
          Transform.rotate(angle: -_heading * pi / 180, child: Container(
            width: 150, height: 150,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey.shade300, width: 3)),
            child: Stack(alignment: Alignment.center, children: [
              const Positioned(top: 4, child: Text('N', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red))),
              const Positioned(bottom: 4, child: Text('S', style: TextStyle(fontSize: 12, color: Colors.grey))),
              const Positioned(left: 4, child: Text('W', style: TextStyle(fontSize: 12, color: Colors.grey))),
              const Positioned(right: 4, child: Text('E', style: TextStyle(fontSize: 12, color: Colors.grey))),
              // Target bearing arrow
              Transform.rotate(angle: (_targetBearing - _heading) * pi / 180, child:
                const Icon(Icons.navigation, size: 40, color: Color(0xFF0070BA))),
            ]),
          )),
          Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: Colors.grey)),
            child: const Icon(Icons.my_location, size: 10)),
        ])),
        if (!_gpsFix) const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
        const SizedBox(height: 32),

        // Status indicator
        AnimatedContainer(duration: const Duration(milliseconds: 300), padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(shape: BoxShape.circle,
            color: !_gpsFix ? Colors.grey.shade200 : onTrack ? Colors.green.shade100 : Colors.red.shade100),
          child: Icon(
            !_gpsFix ? Icons.gps_not_fixed : onTrack ? Icons.check_circle : _overshoot ? Icons.flag : Icons.navigation,
            size: 72, color: !_gpsFix ? Colors.grey : onTrack ? Colors.green : _overshoot ? Colors.orange : Colors.red),
        ),
        const SizedBox(height: 24),

        if (!_gpsFix)
          const Text('Acquiring GPS fix...', style: TextStyle(fontSize: 16))
        else ...[
          Text(_overshoot ? 'PASSED TARGET — TURN BACK' : onTrack ? 'ON STRAIGHT CUTLINE' : veer,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
              color: _overshoot ? Colors.orange.shade800 : onTrack ? Colors.green.shade800 : Colors.red.shade800)),
          const SizedBox(height: 12),
          Text('${_distRemain.toStringAsFixed(1)} m to endpoint', style: const TextStyle(fontSize: 18, color: Colors.black87)),
          const SizedBox(height: 8),
          Text('Cross-track: ${_xt.abs().toStringAsFixed(1)} m ${_xt > 0 ? '(right of line)' : '(left of line)'}',
            style: const TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      ]))));
  }
}
