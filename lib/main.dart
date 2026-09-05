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
// Coordinate Engine (Cape Datum / WGS84 South-Oriented Lo Proj)
// -------------------------------------------------------------
class LoConverter {
  static ll.LatLng toWgs84(double yWesting, double xSouthing, {int zone = 25, String datum = 'cape'}) {
    String projDef;
    if (datum == 'cape') {
      projDef = '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 +axis=wsu +ellps=clrk80 +towgs84=-160,-22,-302,0,0,0,0 +units=m +no_defs';
    } else {
      projDef = '+proj=tmerc +lat_0=0 +lon_0=$zone +k=1 +x_0=0 +y_0=0 +axis=wsu +datum=WGS84 +units=m +no_defs';
    }

    final projSrc = proj4.Projection.add('LO_${zone}_$datum', projDef);
    final projWgs84 = proj4.Projection.get('EPSG:4326')!;

    // Pass [Y, X] into transformation because axis=wsu maps X=Westing, Y=Southing
    final pt = proj4.Point(x: yWesting, y: xSouthing);
    final result = projSrc.transform(projWgs84, pt);

    return ll.LatLng(result.y, result.x); // y = Latitude, x = Longitude
  }
}

// -------------------------------------------------------------
// Area Calculator (Shoelace formula in hectares)
// -------------------------------------------------------------
class PlotArea {
  // Great-circle shoelace area approximation using local UTM-like planar
  // projection centered at the polygon centroid.
  static double toHectares(List<ll.LatLng> points) {
    if (points.length < 3) return 0.0;

    // Center of the polygon for a local equirectangular approximation.
    double lat0 = points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    double lon0 = points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;

    const double mPerDegLat = 111132.0;
    double mPerDegLon = 111132.0 * cos(lat0 * pi / 180);

    double sum = 0.0;
    for (int i = 0; i < points.length; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % points.length];
      final x1 = (p1.longitude - lon0) * mPerDegLon;
      final y1 = (p1.latitude - lat0) * mPerDegLat;
      final x2 = (p2.longitude - lon0) * mPerDegLon;
      final y2 = (p2.latitude - lat0) * mPerDegLat;
      sum += (x1 * y2 - x2 * y1);
    }

    double areaSqm = sum.abs() / 2.0;
    return areaSqm / 10000.0; // hectares
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
  int _selectedZone = 25;
  String _selectedDatum = 'cape';
  final List<CornerInput> _corners = [
    CornerInput('-74283', '2609149'),
    CornerInput('-74593', '2609153'),
    CornerInput('-74589', '2609473'),
    CornerInput('-74279', '2609469'),
  ];

  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void dispose() {
    _textRecognizer.close();
    for (var c in _corners) {
      c.yController.dispose();
      c.xController.dispose();
    }
    super.dispose();
  }

  void _addCorner() {
    setState(() {
      _corners.add(CornerInput('', ''));
    });
  }

  void _removeCorner(int index) {
    if (_corners.length > 1) {
      setState(() {
        _corners.removeAt(index);
      });
    }
  }

  Future<void> _scanCertificate() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera);
    if (photo == null) return;

    final inputImage = InputImage.fromFilePath(photo.path);
    final recognizedText = await _textRecognizer.processImage(inputImage);

    String text = recognizedText.text.replaceAll(RegExp(r'[oO](?=\d)'), '0');
    final regex = RegExp(
      r'Y\s*[:=\s]*([+-]?\d{4,6}(?:\.\d+)?)\s*[,;\s]*X\s*[:=\s]*([+]?\d{6,8}(?:\.\d+)?)',
      caseSensitive: false,
    );

    final matches = regex.allMatches(text);
    if (matches.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No coordinate pairs recognized. Try adjusting photo lighting.')),
        );
      }
      return;
    }

    setState(() {
      _corners.clear();
      for (final match in matches) {
        _corners.add(CornerInput(match.group(1)!, match.group(2)!));
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Found and loaded ${matches.length} coordinates!')),
      );
    }
  }

  List<ll.LatLng> _getConvertedCoordinates() {
    List<ll.LatLng> points = [];
    for (var corner in _corners) {
      final y = double.tryParse(corner.yController.text.trim());
      final x = double.tryParse(corner.xController.text.trim());
      if (y != null && x != null) {
        points.add(LoConverter.toWgs84(y, x, zone: _selectedZone, datum: _selectedDatum));
      }
    }
    return points;
  }

  void _openPlotMap() {
    final points = _getConvertedCoordinates();
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
          zone: _selectedZone,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Botswana Plot Finder', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                    DropdownButtonFormField<int>(
                      value: _selectedZone,
                      decoration: const InputDecoration(labelText: 'Lo Central Meridian', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 21, child: Text('Lo21 (Western Kalahari / Ghanzi)')),
                        DropdownMenuItem(value: 23, child: Text('Lo23 (Ngamiland / Kgalagadi)')),
                        DropdownMenuItem(value: 25, child: Text('Lo25 (Gaborone / Kweneng / Lephephe)')),
                        DropdownMenuItem(value: 27, child: Text('Lo27 (Francistown / Central District)')),
                        DropdownMenuItem(value: 29, child: Text('Lo29 (Tuli Block / Selebi-Phikwe)')),
                      ],
                      onChanged: (val) => setState(() => _selectedZone = val!),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedDatum,
                      decoration: const InputDecoration(labelText: 'Survey Datum', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'cape', child: Text('Cape Datum (Legacy titles / Clarke 1880)')),
                        DropdownMenuItem(value: 'wgs84', child: Text('WGS84 / BTRS02 (Modern Surveys)')),
                      ],
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
  final int zone;

  const PlotMapScreen({super.key, required this.points, required this.zone});

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
    final areaHectares = PlotArea.toHectares(widget.points);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plot Boundary', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0070BA),
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
            top: 16,
            left: 16,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  'Area: ${areaHectares.toStringAsFixed(3)} ha',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
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
      distanceFilter: 1, // trigger recalculation every 1 meter moved
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
        title: Text('${widget.startLabel} ➔${widget.endLabel}', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF0070BA),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Compass Cutline Bearing: ${_targetBearing.toStringAsFixed(0)}°',
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
