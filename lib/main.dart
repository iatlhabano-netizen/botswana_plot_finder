import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:botswana_plot_finder/plot_exporter.dart';
import 'package:botswana_plot_finder/plot_calculator.dart';
import 'package:botswana_plot_finder/area_audit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BotswanaPlotFinderApp());
}

class BotswanaPlotFinderApp extends StatelessWidget {
  const BotswanaPlotFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Botswana Plot Finder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0070BA)),
        useMaterial3: true,
      ),
      home: const MainHomeScreen(),
    );
  }
}

// -------------------------------------------------------------
// Country / Datum Presets
// -------------------------------------------------------------
class CountrySystem {
  final String id;
  final String label;
  final List<int> availableZones;
  final String defaultDatum;

  const CountrySystem({
    required this.id,
    required this.label,
    required this.availableZones,
    required this.defaultDatum,
  });
}

class DatumOption {
  final String key;
  final String label;

  const DatumOption({required this.key, required this.label});
}

// -------------------------------------------------------------
// Coordinate Engine (Multi-Country South-Oriented Lo Proj)
// -------------------------------------------------------------
class LoConverter {
class LoConverter {
  // Cache projections to prevent proj4dart crash on duplicate registration.
  static final Map<String, proj4.Projection> _cache = {};

  static const List<CountrySystem> supportedCountries = [
    CountrySystem(
      id: 'BW',
      label: 'Botswana',
      availableZones: [21, 23, 25, 27, 29],
      defaultDatum: 'bw_cape',
    ),
    CountrySystem(
      id: 'ZA',
      label: 'South Africa',
      availableZones: [17, 19, 21, 23, 25, 27, 29, 31, 33],
      defaultDatum: 'za_hart94',
    ),
    CountrySystem(
      id: 'NA',
      label: 'Namibia',
      availableZones: [11, 13, 15, 17, 19],
      defaultDatum: 'na_schwarzeck',
    ),
    CountrySystem(
      id: 'ZW',
      label: 'Zimbabwe',
      availableZones: [27, 29, 31, 33],
      defaultDatum: 'zw_arc1950',
    ),
    CountrySystem(
      id: 'SZ',
      label: 'Eswatini',
      availableZones: [31],
      defaultDatum: 'sz_cape',
    ),
    CountrySystem(
      id: 'LS',
      label: 'Lesotho',
      availableZones: [27, 29],
      defaultDatum: 'ls_cape',
    ),
  ];

  static List<DatumOption> availableDatums(String countryCode) {
    switch (countryCode) {
      case 'ZA':
        return const [
          DatumOption(key: 'za_hart94', label: 'Hartebeesthoek94 (Modern / WGS84)'),
          DatumOption(key: 'za_cape', label: 'Cape Datum (Legacy / Clarke 1880)'),
        ];
      case 'NA':
        return const [
          DatumOption(key: 'na_schwarzeck', label: 'Schwarzeck (Bessel 1841)'),
        ];
      case 'ZW':
        return const [
          DatumOption(key: 'zw_arc1950', label: 'Arc 1950 (Clarke 1880 Modified)'),
        ];
      case 'SZ':
        return const [
          DatumOption(key: 'sz_cape', label: 'Cape Datum (Clarke 1880)'),
        ];
      case 'LS':
        return const [
          DatumOption(key: 'ls_cape', label: 'Cape Datum (Clarke 1880)'),
        ];
      case 'BW':
      default:
        return const [
          DatumOption(key: 'bw_cape', label: 'Cape Datum (Legacy / Clarke 1880)'),
          DatumOption(key: 'bw_btrs02', label: 'BTRS02 / Modern (WGS84)'),
        ];
    }
  }

  static String _definition(int zone, String datumKey) {
    switch (datumKey) {
      // Modern WGS84-based datums (Hartebeesthoek94, BTRS02)
      case 'za_hart94':
      case 'bw_btrs02':
      case 'wgs84':
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 '
            '+ellps=WGS84 +units=m +no_defs';

      // South Africa / Eswatini / Lesotho Legacy Cape Datum
      case 'za_cape':
      case 'sz_cape':
      case 'ls_cape':
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 '
            '+a=6378249.145 +rf=293.4663076563986 '
            '+towgs84=-136,-108,-292,0,0,0,0 +units=m +no_defs';

      // Namibia Schwarzeck (Bessel 1841)
      case 'na_schwarzeck':
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 '
            '+ellps=bessel +towgs84=616,97,-251,0,0,0,0 +units=m +no_defs';

      // Zimbabwe Arc 1950
      case 'zw_arc1950':
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 '
            '+a=6378249.145 +rf=293.4663076563986 '
            '+towgs84=-142.5,-96.2,-291.6,0,0,0,0 +units=m +no_defs';

      // Botswana Cape Datum — verified 3-param shift (DSM Botswana)
      case 'bw_cape':
      default:
        return '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 '
            '+a=6378249.145 +rf=293.4663076563986 '
            '+towgs84=-87,-105,-189,0,0,0,0 +units=m +no_defs';
    }
  }

  /// Lo (south-oriented Gauss Conform) → WGS84.
  /// [westing] = surveyor's Y, [southing] = surveyor's X.
  /// We avoid +axis=wsu (unreliable in proj4dart) and negate manually:
  /// easting = -westing, northing = -southing.
  static ll.LatLng toWgs84({
    required double westing,
    required double southing,
    required int zone,
    required String datumKey,
  }) {
    final key = 'LO${zone}_$datumKey';
    final projSrc = _cache.putIfAbsent(key, () => proj4.Projection.add(key, _definition(zone, datumKey)));
    final projWgs84 = proj4.Projection.get('EPSG:4326')!;

    final pt = proj4.Point(x: -westing, y: -southing);
    final result = projSrc.transform(projWgs84, pt);
    return ll.LatLng(result.y, result.x);
  }

  /// Reverse: WGS84 → Lo coordinates (for verification).
  static ({double westing, double southing}) fromWgs84(
    ll.LatLng ll, {
    required int zone,
    required String datumKey,
  }) {
    final key = 'LO${zone}_$datumKey';
    final projSrc = _cache.putIfAbsent(key, () => proj4.Projection.add(key, _definition(zone, datumKey)));
    final projWgs84 = proj4.Projection.get('EPSG:4326')!;

    final out = projWgs84.transform(
      projSrc,
      proj4.Point(x: ll.longitude, y: ll.latitude),
    );
    return (westing: -out.x, southing: -out.y);
  }

  /// Plausibility check for Botswana Lo coordinates.
  static String? validateLo(double westing, double southing) {
    if (southing < 1500000 || southing > 3200000) {
      return 'X ≈ ${southing.toStringAsFixed(0)} is outside SADC range (~1.5M–3.2M). Check zone/datum.';
    }
    if (westing.abs() > 200000) {
      return 'Y ≈ ${westing.toStringAsFixed(0)} is >200 km from the CM — check the Lo zone.';
    }
    return null;
  }
}

// -------------------------------------------------------------
// Plot Summary Card (Area & Boundary from raw Lo meters)
// -------------------------------------------------------------
// -------------------------------------------------------------
// Area Audit Banner (mismatch warning)
// -------------------------------------------------------------
class AreaAuditBanner extends StatelessWidget {
  final AreaVerificationResult audit;

  const AreaAuditBanner({super.key, required this.audit});

  @override
  Widget build(BuildContext context) {
    if (audit.statedHectares <= 0) return const SizedBox.shrink();

    final isAlert = audit.isMismatch;
    final bgColor = isAlert ? Colors.amber.shade50 : Colors.green.shade50;
    final borderColor = isAlert ? Colors.orange.shade700 : Colors.green.shade700;
    final iconColor = isAlert ? Colors.orange.shade800 : Colors.green.shade800;

    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isAlert ? Icons.warning_amber_rounded : Icons.verified_user_outlined,
            color: iconColor,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAlert ? 'Area Mismatch Alert' : 'Certificate Boundary Verified',
                  style: TextStyle(fontWeight: FontWeight.bold, color: iconColor, fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  audit.message,
                  style: TextStyle(fontSize: 12, color: isAlert ? Colors.brown.shade900 : Colors.green.shade900),
                ),
                if (isAlert) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Tip: Verify corner numbers follow chronological order and coordinate signs (+/-) are correct.',
                    style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.black54),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// Plot Summary Card (Area & Boundary from raw Lo meters)
// -------------------------------------------------------------
class PlotSummaryCard extends StatelessWidget {
  final PlotCalculationResult summary;

  const PlotSummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Land Area', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      '${summary.areaHectares.toStringAsFixed(2)} Ha',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0070BA)),
                    ),
                    Text('${summary.areaSqMeters.toStringAsFixed(0)} m\u00b2', style: const TextStyle(fontSize: 12)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Perimeter / Fence', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(
                      '${summary.perimeterMeters.toStringAsFixed(1)} m',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 18),
            const Text('Boundary Segments (Fence Lines):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: summary.segments.map((s) {
                return Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.grey.shade100,
                  label: Text(
                    'C${s.fromCorner} \u2794 C${s.toCorner}: ${s.lengthMeters.toStringAsFixed(1)}m',
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// Bush Navigator (Cross Track Error Math)
// -------------------------------------------------------------
class BushNavigator {
  static const double earthRadius = 6371000.0;

  static double getCrossTrackError(ll.LatLng current, ll.LatLng start, ll.LatLng end) {
    double d13 = _distance(start, current) / earthRadius;
    double theta13 = _bearing(start, current);
    double theta12 = _bearing(start, end);
    return asin(sin(d13) * sin(theta13 - theta12)) * earthRadius;
  }

  static double getDistanceRemaining(ll.LatLng current, ll.LatLng end) {
    return _distance(current, end);
  }

  static double getTargetBearing(ll.LatLng start, ll.LatLng end) {
    return (_bearing(start, end) * 180 / pi + 360) % 360;
  }

  static double _bearing(ll.LatLng p1, ll.LatLng p2) {
    double lat1 = p1.latitude * pi / 180;
    double lat2 = p2.latitude * pi / 180;
    double dLon = (p2.longitude - p1.longitude) * pi / 180;
    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return atan2(y, x);
  }

  static double _distance(ll.LatLng p1, ll.LatLng p2) {
    const distanceCalc = ll.Distance();
    return distanceCalc.as(ll.LengthUnit.Meter, p1, p2);
  }
}

// -------------------------------------------------------------
// Main Screen: Coordinates, OCR & Plot Overview
// -------------------------------------------------------------
class CornerInput {
  TextEditingController yController;
  TextEditingController xController;
  CornerInput(String y, String x)
      : yController = TextEditingController(text: y),
        xController = TextEditingController(text: x);
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  CountrySystem _selectedCountry = LoConverter.supportedCountries[0]; // Botswana
  int _selectedZone = 25;
  String _selectedDatum = 'bw_cape';
  final List<CornerInput> _corners = [
    CornerInput('-74283', '2609149'),
    CornerInput('-74593', '2609153'),
    CornerInput('-74589', '2609473'),
    CornerInput('-74279', '2609469'),
  ];

  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _textRecognizer.close();
    for (var c in _corners) {
      c.yController.dispose();
      c.xController.dispose();
    }
    super.dispose();
  }

  Future<void> _restore() async {
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _selectedZone = sp.getInt('zone') ?? _selectedZone;
      final datumIdx = sp.getInt('datum');
      if (datumIdx != null && datumIdx < _selectedCountry.availableZones.length) {
        final datums = LoConverter.availableDatums(_selectedCountry.id);
        final key = sp.getString('datumKey');
        if (key != null && datums.any((d) => d.key == key)) {
          _selectedDatum = key;
        }
      }
      final rows = sp.getStringList('corners') ?? const <String>[];
      if (rows.isEmpty) {
        _corners.addAll([
          CornerInput('-74283', '2609149'),
          CornerInput('-74593', '2609153'),
          CornerInput('-74589', '2609473'),
          CornerInput('-74279', '2609469'),
        ]);
      } else {
        for (final r in rows) {
          final p = r.split('|');
          if (p.length >= 2) _corners.add(CornerInput(p[0], p[1]));
        }
      }
    });
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('zone', _selectedZone);
    await sp.setString('datumKey', _selectedDatum);
    await sp.setStringList('corners', [
      for (final c in _corners) '${c.yController.text}|${c.xController.text}',
    ]);
  }

  void _onCountryChanged(CountrySystem newCountry) {
    setState(() {
      _selectedCountry = newCountry;
      _selectedZone = newCountry.availableZones.contains(_selectedZone)
          ? _selectedZone
          : newCountry.availableZones.first;
      _selectedDatum = newCountry.defaultDatum;
    });
    _persist();
  }

  void _addCorner() {
    setState(() {
      _corners.add(CornerInput('', ''));
    });
    _persist();
  }

  void _removeCorner(int index) {
    if (_corners.length > 1) {
      setState(() {
        _corners.removeAt(index);
      });
      _persist();
    }
  }

  double? _declaredHa;
  bool _scanning = false;

  Future<void> _scanCertificate() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Photograph the certificate'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null || !mounted) return;

    setState(() => _scanning = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, maxWidth: 2600);
      if (picked == null) return;

      final inputImage = InputImage.fromFilePath(picked.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      String text = recognizedText.text.replaceAll(RegExp(r'[oO](?=\d)'), '0');

      // Match Y...X order
      final regexYX = RegExp(
        r'Y\s*[:=]?\s*([+-]?\d[\d\s]{2,9}\d(?:\.\d+)?)\s*[,;:\s]+\s*X\s*[:=]?\s*([+-]?\d[\d\s]{4,9}\d(?:\.\d+)?)',
        caseSensitive: false,
      );
      // Match X...Y order (reversed certificate)
      final regexXY = RegExp(
        r'X\s*[:=]?\s*([+-]?\d[\d\s]{4,9}\d(?:\.\d+)?)\s*[,;:\s]+\s*Y\s*[:=]?\s*([+-]?\d[\d\s]{2,9}\d(?:\.\d+)?)',
        caseSensitive: false,
      );

      final parsed = <({double westing, double southing})>[];
      final spans = <(int, int)>[];

      for (final m in regexYX.allMatches(text)) {
        if (spans.any((s) => m.start < s.$2 && m.end > s.$1)) continue;
        final yv = double.tryParse(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
        final xv = double.tryParse(m.group(2)!.replaceAll(RegExp(r'\s'), ''));
        if (yv != null && xv != null) { parsed.add((westing: yv, southing: xv)); spans.add((m.start, m.end)); }
      }
      for (final m in regexXY.allMatches(text)) {
        if (spans.any((s) => m.start < s.$2 && m.end > s.$1)) continue;
        final xv = double.tryParse(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
        final yv = double.tryParse(m.group(2)!.replaceAll(RegExp(r'\s'), ''));
        if (yv != null && xv != null) { parsed.add((westing: yv, southing: xv)); spans.add((m.start, m.end)); }
      }

      if (!mounted) return;
      if (parsed.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No coordinate pairs recognised. Fill the frame, avoid glare, retry.')),
        );
        return;
      }

      // Auto-detect declared area from certificate text
      final detectedHa = AreaAuditor.extractStatedArea(text);
      if (detectedHa != null) setState(() => _declaredHa = detectedHa);

      // Show review dialog — nothing is overwritten until user confirms
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${parsed.length} coordinate pair(s) found'),
          content: SizedBox(
            width: double.maxFinite,
            height: 240,
            child: ListView.builder(
              itemCount: parsed.length,
              itemBuilder: (_, i) => ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 12,
                  backgroundColor: const Color(0xFF0070BA),
                  child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
                title: Text('Y ${parsed[i].westing.toStringAsFixed(0)}   X ${parsed[i].southing.toStringAsFixed(0)}'),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'append'), child: const Text('Append')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'replace'), child: const Text('Replace all')),
          ],
        ),
      );
      if (action == null || action == 'cancel' || !mounted) return;

      setState(() {
        if (action == 'replace') {
          for (final c in _corners) { c.yController.dispose(); c.xController.dispose(); }
          _corners.clear();
        }
        for (final p in parsed) {
          _corners.add(CornerInput(p.westing.toStringAsFixed(0), p.southing.toStringAsFixed(0)));
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${parsed.length} coordinate(s) loaded!')),
      );

      // If we detected a declared area, show audit result
      if (detectedHa != null) {
        final loCorners = _corners
            .where((c) => c.yController.text.isNotEmpty && c.xController.text.isNotEmpty)
            .map((c) => {'Y': double.parse(c.yController.text), 'X': double.parse(c.xController.text)})
            .toList();
        if (loCorners.length >= 3) {
          final result = PlotCalculator.calculateFromLo(loCorners);
          final audit = AreaAuditor.auditArea(
            computedHectares: result.areaHectares,
            statedHectares: detectedHa,
          );
          if (audit.isMismatch && mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Area Mismatch'),
                content: Text(audit.message),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  List<ll.LatLng> _getConvertedCoordinates() {
    List<ll.LatLng> points = [];
    for (var corner in _corners) {
      final y = double.tryParse(corner.yController.text.trim());
      final x = double.tryParse(corner.xController.text.trim());
      if (y != null && x != null) {
        points.add(LoConverter.toWgs84(westing: y, southing: x, zone: _selectedZone, datumKey: _selectedDatum));
      }
    }
    return points;
  }

  List<Map<String, double>> _getRawLoCorners() {
    List<Map<String, double>> lo = [];
    for (var corner in _corners) {
      final y = double.tryParse(corner.yController.text.trim());
      final x = double.tryParse(corner.xController.text.trim());
      if (y != null && x != null) {
        lo.add({'Y': y, 'X': x});
      }
    }
    return lo;
  }

  void _openPlotMap() {
    final points = _getConvertedCoordinates();
    final loCorners = _getRawLoCorners();
    if (points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide valid coordinates first.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlotMapScreen(
          points: points,
          loCorners: loCorners,
          zone: _selectedZone,
          datumKey: _selectedDatum,
          declaredHa: _declaredHa,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final datums = LoConverter.availableDatums(_selectedCountry.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plot Finder', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0070BA),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt, color: Colors.white),
            tooltip: 'Scan Certificate',
            onPressed: _scanCertificate,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Country selector
                    DropdownButtonFormField<CountrySystem>(
                      value: _selectedCountry,
                      decoration: const InputDecoration(labelText: 'Country', border: OutlineInputBorder()),
                      items: LoConverter.supportedCountries.map((c) {
                        return DropdownMenuItem(value: c, child: Text('${c.label} (${c.id})'));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) _onCountryChanged(val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Zone selector (dynamic per country)
                    DropdownButtonFormField<int>(
                      value: _selectedCountry.availableZones.contains(_selectedZone)
                          ? _selectedZone
                          : _selectedCountry.availableZones.first,
                      decoration: const InputDecoration(labelText: 'Lo Central Meridian', border: OutlineInputBorder()),
                      items: _selectedCountry.availableZones.map((z) {
                        return DropdownMenuItem(value: z, child: Text('Lo$z'));
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedZone = val!),
                    ),
                    const SizedBox(height: 12),

                    // Datum selector (dynamic per country)
                    DropdownButtonFormField<String>(
                      value: datums.any((d) => d.key == _selectedDatum) ? _selectedDatum : datums.first.key,
                      decoration: const InputDecoration(labelText: 'Survey Datum', border: OutlineInputBorder()),
                      items: datums.map((d) {
                        return DropdownMenuItem(value: d.key, child: Text(d.label));
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedDatum = val!),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Corner Coordinates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: _addCorner,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Corner'),
                ),
              ],
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _corners.length,
              itemBuilder: (context, idx) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: const Color(0xFF0070BA),
                        child: Text('${idx + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _corners[idx].yController,
                          keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Y (Westing)',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _corners[idx].xController,
                          keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                          decoration: InputDecoration(
                            labelText: 'X (Southing)',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.grey),
                        onPressed: () => _removeCorner(idx),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0070BA),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _openPlotMap,
                icon: const Icon(Icons.map, color: Colors.white),
                label: const Text('View Plot on Map', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// Map Screen: Displays Corners, Area, and Point-to-Point Mode
// -------------------------------------------------------------
class PlotMapScreen extends StatefulWidget {
  final List<ll.LatLng> points;
  final List<Map<String, double>> loCorners;
  final int zone;
  final String datumKey;
  final double? declaredHa;

  const PlotMapScreen({
    super.key,
    required this.points,
    required this.loCorners,
    required this.zone,
    required this.datumKey,
    this.declaredHa,
  });

  @override
  State<PlotMapScreen> createState() => _PlotMapScreenState();
}

class _PlotMapScreenState extends State<PlotMapScreen> {
  final MapController _mapController = MapController();
  int? _routeStartIdx;
  int? _routeEndIdx;

  void _launchGoogleMapsNavigation(ll.LatLng pt) async {
    final uri = Uri.parse('google.navigation:q=${pt.latitude},${pt.longitude}');
    final fallbackUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${pt.latitude},${pt.longitude}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
    }
  }

  void _startBushGuidance() {
    if (_routeStartIdx == null || _routeEndIdx == null || _routeStartIdx == _routeEndIdx) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select two different corners (Start and Target).')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BushGuidanceScreen(
          startPoint: widget.points[_routeStartIdx!],
          endPoint: widget.points[_routeEndIdx!],
          startLabel: 'Corner ${_routeStartIdx! + 1}',
          endLabel: 'Corner ${_routeEndIdx! + 1}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.points.isNotEmpty ? widget.points.first : const ll.LatLng(-23.58, 25.72);
    final summary = PlotCalculator.calculateFromLo(widget.loCorners);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plot Boundary', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0070BA),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.share, color: Colors.white),
            tooltip: 'Export Coordinates',
            onSelected: (choice) async {
              if (widget.points.isEmpty) return;

              if (choice == 'kml') {
                final kmlData = PlotExporter.generateKml(widget.points);
                await PlotExporter.shareFile(
                  content: kmlData,
                  fileName: 'plot_boundary.kml',
                  mimeType: 'application/vnd.google-earth.kml+xml',
                );
              } else if (choice == 'gpx') {
                final gpxData = PlotExporter.generateGpx(widget.points);
                await PlotExporter.shareFile(
                  content: gpxData,
                  fileName: 'plot_boundary.gpx',
                  mimeType: 'application/gpx+xml',
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'kml',
                child: Row(
                  children: [
                    Icon(Icons.public, color: Color(0xFF0070BA)),
                    SizedBox(width: 8),
                    Text('Export to Google Earth (.KML)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'gpx',
                child: Row(
                  children: [
                    Icon(Icons.gps_fixed, color: Color(0xFF0070BA)),
                    SizedBox(width: 8),
                    Text('Export to Garmin GPS (.GPX)'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.botswana_plot_finder',
              ),
                            SimpleAttributionWidget(
                source: const Text('OpenStreetMap contributors'),
                onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright')),
              ),
              if (widget.points.length >= 3)
                PolygonLayer(
                  polygons: [
                    Polygon(
                      points: widget.points,
                      color: Colors.blue.withOpacity(0.2),
                      borderColor: const Color(0xFF0070BA),
                      borderStrokeWidth: 3,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: widget.points.asMap().entries.map((entry) {
                  int idx = entry.key;
                  ll.LatLng pt = entry.value;
                  return Marker(
                    point: pt,
                    width: 80,
                    height: 80,
                    child: GestureDetector(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          builder: (ctx) => Container(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Corner ${idx + 1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                Text('Lat: ${pt.latitude.toStringAsFixed(6)}'),
                                Text('Lon: ${pt.longitude.toStringAsFixed(6)}'),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () => _launchGoogleMapsNavigation(pt),
                                  icon: const Icon(Icons.navigation),
                                  label: const Text('Drive with Google Maps'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.black26)),
                            child: Text('C${idx + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                          const Icon(Icons.location_pin, color: Colors.red, size: 36),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlotSummaryCard(summary: summary),
                if (widget.declaredHa != null)
                  AreaAuditBanner(
                    audit: AreaAuditor.auditArea(
                      computedHectares: summary.areaHectares,
                      statedHectares: widget.declaredHa!,
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Straight Bush Run (Pipes / Fence / Wires)', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _routeStartIdx,
                            decoration: const InputDecoration(labelText: 'From Point', border: OutlineInputBorder()),
                            items: List.generate(
                              widget.points.length,
                              (i) => DropdownMenuItem(value: i, child: Text('Corner ${i + 1}')),
                            ),
                            onChanged: (val) => setState(() => _routeStartIdx = val),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _routeEndIdx,
                            decoration: const InputDecoration(labelText: 'To Point', border: OutlineInputBorder()),
                            items: List.generate(
                              widget.points.length,
                              (i) => DropdownMenuItem(value: i, child: Text('Corner ${i + 1}')),
                            ),
                            onChanged: (val) => setState(() => _routeEndIdx = val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        onPressed: _startBushGuidance,
                        icon: const Icon(Icons.compass_calibration, color: Colors.white),
                        label: const Text('Start Bush Line Guidance', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// Live Bush Tracker (Line Following Screen)
// -------------------------------------------------------------
class BushGuidanceScreen extends StatefulWidget {
  final ll.LatLng startPoint;
  final ll.LatLng endPoint;
  final String startLabel;
  final String endLabel;

  const BushGuidanceScreen({
    super.key,
    required this.startPoint,
    required this.endPoint,
    required this.startLabel,
    required this.endLabel,
  });

  @override
  State<BushGuidanceScreen> createState() => _BushGuidanceScreenState();
}

class _BushGuidanceScreenState extends State<BushGuidanceScreen> {
  StreamSubscription<Position>? _positionStream;
  double _crossTrackError = 0.0;
  double _distanceRemaining = 0.0;
  double _targetBearing = 0.0;
  bool _hasGpsFix = false;

  @override
  void initState() {
    super.initState();
    _startLiveTracking();
  }

  void _startLiveTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    _targetBearing = BushNavigator.getTargetBearing(widget.startPoint, widget.endPoint);

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      final current = ll.LatLng(position.latitude, position.longitude);
      setState(() {
        _hasGpsFix = true;
        _crossTrackError = BushNavigator.getCrossTrackError(current, widget.startPoint, widget.endPoint);
        _distanceRemaining = BushNavigator.getDistanceRemaining(current, widget.endPoint);
      });
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool onTrack = _crossTrackError.abs() <= 1.5;
    String correctionMessage = _crossTrackError > 0
        ? 'VEER LEFT ${(_crossTrackError).abs().toStringAsFixed(1)} m'
        : 'VEER RIGHT ${(_crossTrackError).abs().toStringAsFixed(1)} m';

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.startLabel} \u2794 ${widget.endLabel}', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0070BA),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Compass Cutline Bearing: ${_targetBearing.toStringAsFixed(0)}\u00B0',
                style: const TextStyle(fontSize: 20, color: Colors.grey, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: !_hasGpsFix
                      ? Colors.grey.shade200
                      : onTrack
                          ? Colors.green.shade100
                          : Colors.red.shade100,
                ),
                child: Icon(
                  !_hasGpsFix
                      ? Icons.gps_not_fixed
                      : onTrack
                          ? Icons.check_circle
                          : Icons.navigation,
                  size: 90,
                  color: !_hasGpsFix
                      ? Colors.grey
                      : onTrack
                          ? Colors.green
                          : Colors.red,
                ),
              ),
              const SizedBox(height: 32),
              if (!_hasGpsFix)
                const Text('Acquiring high-accuracy GPS fix in the field...', style: TextStyle(fontSize: 16))
              else ...[
                Text(
                  onTrack ? 'ON STRAIGHT CUTLINE' : correctionMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: onTrack ? Colors.green.shade800 : Colors.red.shade800,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Distance to Endpoint: ${_distanceRemaining.toStringAsFixed(1)} m',
                  style: const TextStyle(fontSize: 18, color: Colors.black87),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
