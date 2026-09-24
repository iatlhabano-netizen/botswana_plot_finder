import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/lo_converter.dart';
import '../../core/lo_format.dart';
import '../../core/polygon_validation.dart';
import '../../services/external_maps.dart';
import '../../services/gps_service.dart';
import '../../services/ocr_service.dart';
import '../../services/plot_manager.dart';
import '../license/license_screen.dart';
import '../pathfinder/guidance_screen.dart';
import '../pathfinder/pathfinder_screen.dart';
import '../theme.dart';
import '../widgets/ocr_review_sheet.dart';
import 'plot_map_screen.dart';

class _CornerCtrls {
  final TextEditingController y;
  final TextEditingController x;
  _CornerCtrls(String yText, String xText)
      : y = TextEditingController(text: yText),
        x = TextEditingController(text: xText);
  double? get westing => double.tryParse(y.text.trim());
  double? get southing => double.tryParse(x.text.trim());
  void dispose() {
    y.dispose();
    x.dispose();
  }
}

class PlotFinderScreen extends StatefulWidget {
  const PlotFinderScreen({super.key});

  @override
  State<PlotFinderScreen> createState() => _PlotFinderScreenState();
}

class _PlotFinderScreenState extends State<PlotFinderScreen> {
  CountrySystem _country = LoConverter.supportedCountries.first;
  int _zone = 25;
  String _datum = 'bw_cape';
  final List<_CornerCtrls> _corners = [];
  final OcrService _ocr = OcrService();
  bool _scanning = false;
  bool _gpsStarting = false;
  double? _declaredHa;
  StreamSubscription<Position>? _gpsSub;
  ll.LatLng? _currentPos;
  double? _gpsAccuracy;
  List<PlotProject> _projects = [];
  PlotProject? _active;
  bool _advancedOpen = false;

  static const _sampleCorners = [
    ('-74283', '2609149'),
    ('-74593', '2609153'),
    ('-74589', '2609473'),
    ('-74279', '2609469'),
  ];

  @override
  void initState() {
    super.initState();
    // Do NOT start GPS in initState — wait for user tap (locate / use my position).
    _restore();
  }

  @override
  void dispose() {
    _ocr.dispose();
    _gpsSub?.cancel();
    for (final c in _corners) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _ensureGps() async {
    if (_gpsSub != null) return;
    setState(() => _gpsStarting = true);
    try {
      if (!await GpsService.ensurePermission(context)) return;
      final seed = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _currentPos = ll.LatLng(seed.latitude, seed.longitude);
          _gpsAccuracy = seed.accuracy;
        });
      }
      _gpsSub = GpsService.watch(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ).listen((pos) {
        if (mounted) {
          setState(() {
            _currentPos = ll.LatLng(pos.latitude, pos.longitude);
            _gpsAccuracy = pos.accuracy;
          });
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get GPS fix yet.')),
        );
      }
    } finally {
      if (mounted) setState(() => _gpsStarting = false);
    }
  }

  Future<void> _restore() async {
    final sp = await SharedPreferences.getInstance();
    _zone = sp.getInt('zone') ?? 25;
    _datum = sp.getString('datumKey') ?? 'bw_cape';
    _declaredHa = sp.getDouble('declaredHa');
    _projects = await PlotManager.loadAll();
    final activeId = await PlotManager.activeId();
    _active = _projects.where((p) => p.id == activeId).firstOrNull;

    if (_active != null && _active!.corners.isNotEmpty) {
      _corners.clear();
      for (final c in _active!.corners) {
        _corners.add(_CornerCtrls(c['y'] ?? '', c['x'] ?? ''));
      }
      _zone = int.tryParse(_active!.zone) ?? _zone;
      _datum = _active!.datumKey;
    } else if (_corners.isEmpty) {
      // Empty first launch — Sample only behind explicit button (match Area Calculator).
      _corners.add(_CornerCtrls('', ''));
    }
    if (mounted) setState(() {});
  }

  void _fillSample() {
    for (final c in _corners) {
      c.dispose();
    }
    _corners
      ..clear()
      ..addAll([
        for (final s in _sampleCorners) _CornerCtrls(s.$1, s.$2),
      ]);
    setState(() {});
    _persist();
    _toast('Sample Lo25 Cape plot loaded — review before navigating.');
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('zone', _zone);
    await sp.setString('datumKey', _datum);
    if (_declaredHa != null) await sp.setDouble('declaredHa', _declaredHa!);
    if (_active != null) {
      _active!.zone = _zone.toString();
      _active!.datumKey = _datum;
      _active!.corners
        ..clear()
        ..addAll([
          for (final c in _corners) {'y': c.y.text, 'x': c.x.text}
        ]);
      await PlotManager.saveAll(_projects);
    }
  }

  List<ll.LatLng> get _points {
    final out = <ll.LatLng>[];
    for (final c in _corners) {
      final w = c.westing;
      final s = c.southing;
      if (w == null || s == null) continue;
      out.add(LoConverter.toWgs84(
        westing: w,
        southing: s,
        zone: _zone,
        datumKey: _datum,
      ));
    }
    return out;
  }

  List<Map<String, double>> get _loCorners => [
        for (final c in _corners)
          if (c.westing != null && c.southing != null)
            {'Y': c.westing!, 'X': c.southing!}
      ];

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final outcome =
          await OcrReviewFlow.scanAndReview(context: context, ocr: _ocr);
      if (outcome == null || !mounted) return;
      setState(() {
        if (outcome.action == 'replace') {
          for (final c in _corners) {
            c.dispose();
          }
          _corners.clear();
        }
        for (final p in outcome.pairs) {
          _corners.add(_CornerCtrls(
            formatLoCoord(p.westing),
            formatLoCoord(p.southing),
          ));
        }
        if (outcome.declaredHectares != null) {
          _declaredHa = outcome.declaredHectares;
        }
        if (outcome.suggestedZone != null &&
            _country.availableZones.contains(outcome.suggestedZone)) {
          _zone = outcome.suggestedZone!;
        }
      });
      await _persist();
      _toast('${outcome.pairs.length} corner(s) accepted');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _openMap() {
    final lo = _loCorners;
    final issues = PolygonValidation.validateLoCorners(lo);
    final blocking = issues.where((i) => i.blocking).toList();
    if (blocking.isNotEmpty) {
      _toast(blocking.map((i) => i.message).join('\n'));
      return;
    }
    if (issues.isNotEmpty) {
      _toast(issues.map((i) => i.message).join('\n'));
    }
    final pts = _points;
    if (pts.length < 2) {
      _toast('Enter at least two valid corners.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlotMapScreen(
          points: pts,
          loCorners: lo,
          zone: _zone,
          datumKey: _datum,
          declaredHa: _declaredHa,
          projectName: _active?.name,
        ),
      ),
    );
  }

  Future<void> _locateCorner(int idx) async {
    final c = _corners[idx];
    final w = c.westing;
    final s = c.southing;
    if (w == null || s == null) {
      _toast('Enter valid Y/X first');
      return;
    }
    await _ensureGps();
    if (!mounted) return;
    final pt = LoConverter.toWgs84(
        westing: w, southing: s, zone: _zone, datumKey: _datum);
    final start = _currentPos ?? pt;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GuidanceScreen(
          start: start,
          end: pt,
          startLabel: 'You',
          endLabel: 'C${idx + 1}',
          locateMode: true,
        ),
      ),
    );
  }

  void _showCornerActions(int idx) {
    final c = _corners[idx];
    final w = c.westing;
    final s = c.southing;
    if (w == null || s == null) {
      _toast('Enter valid Y/X for this corner first.');
      return;
    }
    final warn = LoConverter.validateLo(w, s);
    final pt = LoConverter.toWgs84(
      westing: w,
      southing: s,
      zone: _zone,
      datumKey: _datum,
    );

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Corner ${idx + 1}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Lo  Y ${formatLoCoord(w)}  X ${formatLoCoord(s)}'),
            Text(
                'GPS  ${pt.latitude.toStringAsFixed(7)}, ${pt.longitude.toStringAsFixed(7)}'),
            if (warn != null) ...[
              const SizedBox(height: 8),
              Text(warn, style: TextStyle(color: Colors.orange.shade800)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () {
                Navigator.pop(ctx);
                _locateCorner(idx);
              },
              icon: const Icon(Icons.my_location),
              label: const Text('Locate this corner'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _openMap();
              },
              icon: const Icon(Icons.map),
              label: const Text('Show on plot map'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                ExternalMaps.openNavigation(pt);
              },
              icon: const Icon(Icons.navigation),
              label: const Text('Open in Google Maps / nav'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PathfinderScreen(
                      initialEnd: pt,
                      endLabel: 'C${idx + 1}',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.explore),
              label: const Text('Walk a line setup…'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(
                  text:
                      'C${idx + 1}: Y $w, X $s | ${pt.latitude.toStringAsFixed(7)}, ${pt.longitude.toStringAsFixed(7)}',
                ));
                Navigator.pop(ctx);
                _toast('Copied');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy coordinates'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final datums = LoConverter.availableDatums(_country.id);
    return Scaffold(
      appBar: AppBar(
        title: Text(_active?.name ?? 'Find my plot'),
        actions: [
          TextButton(
            onPressed: _fillSample,
            child: const Text('Sample', style: TextStyle(color: Colors.white)),
          ),
          IconButton(
            tooltip: 'License',
            icon: const Icon(Icons.verified_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LicenseScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Scan certificate',
            onPressed: _scanning ? null : _scan,
            icon: _scanning
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.document_scanner),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OutlinedButton.icon(
            onPressed: _gpsStarting ? null : _ensureGps,
            icon: _gpsStarting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.gps_fixed),
            label: Text(_currentPos == null
                ? 'Use my position (GPS)'
                : 'GPS on · ${GpsService.accuracyLabel(_gpsAccuracy)}'),
          ),
          if (_currentPos != null) ...[
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Current position',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                        '${_currentPos!.latitude.toStringAsFixed(6)}, ${_currentPos!.longitude.toStringAsFixed(6)}'),
                    Builder(builder: (_) {
                      final lo = LoConverter.fromWgs84(
                        _currentPos!,
                        zone: _zone,
                        datumKey: _datum,
                      );
                      return Text(
                          'Lo  Y ${formatLoCoord(lo.westing)}  X ${formatLoCoord(lo.southing)}');
                    }),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          ExpansionTile(
            title: const Text('Country / Lo zone / datum'),
            subtitle: Text('${_country.label} · Lo$_zone'),
            initiallyExpanded: _advancedOpen,
            onExpansionChanged: (v) => setState(() => _advancedOpen = v),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Column(children: [
                  DropdownButtonFormField<CountrySystem>(
                    value: _country,
                    decoration: const InputDecoration(
                        labelText: 'Country', border: OutlineInputBorder()),
                    items: LoConverter.supportedCountries
                        .map((c) => DropdownMenuItem(
                            value: c, child: Text('${c.label} (${c.id})')))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _country = v;
                        _zone = v.availableZones.contains(_zone)
                            ? _zone
                            : v.availableZones.first;
                        _datum = v.defaultDatum;
                      });
                      _persist();
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _country.availableZones.contains(_zone)
                        ? _zone
                        : _country.availableZones.first,
                    decoration: const InputDecoration(
                        labelText: 'Lo central meridian',
                        border: OutlineInputBorder()),
                    items: _country.availableZones
                        .map((z) =>
                            DropdownMenuItem(value: z, child: Text('Lo$z')))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _zone = v!);
                      _persist();
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: datums.any((d) => d.key == _datum)
                        ? _datum
                        : datums.first.key,
                    decoration: const InputDecoration(
                      labelText: 'Datum',
                      border: OutlineInputBorder(),
                      helperText:
                          'Land Board default → Cape/BTRS; ArcGIS ArcMap/Pro → ArcGIS Arc1950→WGS84 (WKID 1114); GPS maps → BNGRS02/WGS84',
                      helperMaxLines: 2,
                    ),
                    items: datums
                        .map((d) => DropdownMenuItem(
                            value: d.key, child: Text(d.label)))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _datum = v!);
                      _persist();
                    },
                  ),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text('Corners',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() => _corners.add(_CornerCtrls('', '')));
                  _persist();
                },
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          ...List.generate(_corners.length, (idx) {
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: PathfinderTheme.seed,
                          child: Text('${idx + 1}',
                              style: const TextStyle(color: Colors.white)),
                        ),
                        const SizedBox(width: 8),
                        Text('Corner ${idx + 1}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        IconButton(
                          tooltip: 'More',
                          icon: const Icon(Icons.more_vert),
                          onPressed: () => _showCornerActions(idx),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _corners.length <= 1
                              ? null
                              : () {
                                  setState(() {
                                    _corners.removeAt(idx).dispose();
                                  });
                                  _persist();
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _corners[idx].y,
                      keyboardType: const TextInputType.numberWithOptions(
                          signed: true, decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Y (Westing)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _persist(),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _corners[idx].x,
                      keyboardType: const TextInputType.numberWithOptions(
                          signed: true, decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'X (Southing)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _persist(),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: () => _locateCorner(idx),
                        icon: const Icon(Icons.my_location, size: 22),
                        label: const Text('Locate this corner'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openMap,
            icon: const Icon(Icons.map),
            label: const Text('View plot on map'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _scanning ? null : _scan,
            icon: const Icon(Icons.document_scanner),
            label: const Text('Scan Land Board certificate / notes'),
          ),
          if (_points.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Converted positions',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    ..._points.asMap().entries.map((e) => Text(
                          'C${e.key + 1}: ${e.value.latitude.toStringAsFixed(6)}, ${e.value.longitude.toStringAsFixed(6)}',
                          style: const TextStyle(fontFamily: 'monospace'),
                        )),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
