import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/lo_converter.dart';
import '../../services/external_maps.dart';
import '../../services/ocr_service.dart';
import '../../services/plot_manager.dart';
import '../license/license_screen.dart';
import '../pathfinder/guidance_screen.dart';
import '../pathfinder/pathfinder_screen.dart';
import '../theme.dart';
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
  double? _declaredHa;
  StreamSubscription<Position>? _gpsSub;
  ll.LatLng? _currentPos;
  List<PlotProject> _projects = [];
  PlotProject? _active;

  @override
  void initState() {
    super.initState();
    _restore();
    _startGps();
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

  Future<void> _startGps() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      if (mounted) {
        setState(() => _currentPos = ll.LatLng(pos.latitude, pos.longitude));
      }
    });
  }

  Future<void> _restore() async {
    final sp = await SharedPreferences.getInstance();
    _zone = sp.getInt('zone') ?? 25;
    _datum = sp.getString('datumKey') ?? 'bw_cape';
    _declaredHa = sp.getDouble('declaredHa');
    _projects = await PlotManager.loadAll();
    final activeId = await PlotManager.activeId();
    _active = _projects.where((p) => p.id == activeId).firstOrNull;

    if (_active != null) {
      _corners.clear();
      for (final c in _active!.corners) {
        _corners.add(_CornerCtrls(c['y'] ?? '', c['x'] ?? ''));
      }
      _zone = int.tryParse(_active!.zone) ?? _zone;
      _datum = _active!.datumKey;
    } else if (_corners.isEmpty) {
      _corners.addAll([
        _CornerCtrls('-74283', '2609149'),
        _CornerCtrls('-74593', '2609153'),
        _CornerCtrls('-74589', '2609473'),
        _CornerCtrls('-74279', '2609469'),
      ]);
    }
    if (mounted) setState(() {});
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

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _scan() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Photograph certificate / notes'),
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
      final result = await _ocr.scan(source);
      if (!mounted) return;
      if (result == null) return;
      if (result.pairs.isEmpty) {
        _toast('No coordinates found. Try better lighting or clearer numbers.');
        return;
      }

      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${result.pairs.length} coordinate(s) found'),
          content: SizedBox(
            width: double.maxFinite,
            height: 220,
            child: ListView.builder(
              itemCount: result.pairs.length,
              itemBuilder: (_, i) {
                final p = result.pairs[i];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 12,
                    backgroundColor: PathfinderTheme.seed,
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11)),
                  ),
                  title: Text(
                      'Y ${p.westing.toStringAsFixed(0)}   X ${p.southing.toStringAsFixed(0)}'),
                );
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'append'),
                child: const Text('Append')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'replace'),
                child: const Text('Replace')),
          ],
        ),
      );
      if (action == null || !mounted) return;

      setState(() {
        if (action == 'replace') {
          for (final c in _corners) {
            c.dispose();
          }
          _corners.clear();
        }
        for (final p in result.pairs) {
          _corners.add(_CornerCtrls(
            p.westing.toStringAsFixed(0),
            p.southing.toStringAsFixed(0),
          ));
        }
        if (result.declaredHectares != null) {
          _declaredHa = result.declaredHectares;
        }
      });
      await _persist();
      _toast('${result.pairs.length} corner(s) loaded');
    } on OcrException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Scan failed. Try another photo or check camera/gallery permissions.');
      debugPrint('Plot Finder scan error: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _openMap() {
    final pts = _points;
    if (pts.length < 2) {
      _toast('Enter at least two valid corners.');
      return;
    }
    final lo = [
      for (final c in _corners)
        if (c.westing != null && c.southing != null)
          {'Y': c.westing!, 'X': c.southing!}
    ];
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
            Text('Lo  Y ${w.toStringAsFixed(0)}  X ${s.toStringAsFixed(0)}'),
            Text(
                'WGS84  ${pt.latitude.toStringAsFixed(7)}, ${pt.longitude.toStringAsFixed(7)}'),
            if (warn != null) ...[
              const SizedBox(height: 8),
              Text(warn, style: TextStyle(color: Colors.orange.shade800)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
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
              },
              icon: const Icon(Icons.my_location),
              label: const Text('Locate this corner'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlotMapScreen(
                      points: _points,
                      loCorners: [
                        for (final c in _corners)
                          if (c.westing != null && c.southing != null)
                            {'Y': c.westing!, 'X': c.southing!}
                      ],
                      zone: _zone,
                      datumKey: _datum,
                      declaredHa: _declaredHa,
                      projectName: _active?.name,
                      focusIndex: idx,
                    ),
                  ),
                );
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
              label: const Text('Pathfinder setup…'),
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
        title: Text(_active?.name ?? 'Plot Finder'),
        actions: [
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
          if (_currentPos != null)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Current GPS',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                        'WGS84  ${_currentPos!.latitude.toStringAsFixed(6)}, ${_currentPos!.longitude.toStringAsFixed(6)}'),
                    Builder(builder: (_) {
                      final lo = LoConverter.fromWgs84(
                        _currentPos!,
                        zone: _zone,
                        datumKey: _datum,
                      );
                      return Text(
                          'Lo  Y ${lo.westing.toStringAsFixed(0)}  X ${lo.southing.toStringAsFixed(0)}');
                    }),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                      labelText: 'Lo Central Meridian',
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
                      labelText: 'Datum', border: OutlineInputBorder()),
                  items: datums
                      .map((d) =>
                          DropdownMenuItem(value: d.key, child: Text(d.label)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _datum = v!);
                    _persist();
                  },
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('Corners (Y westing / X southing)',
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
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: PathfinderTheme.seed,
                      child: Text('${idx + 1}',
                          style: const TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _corners[idx].y,
                        keyboardType: const TextInputType.numberWithOptions(
                            signed: true, decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Y',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _persist(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _corners[idx].x,
                        keyboardType: const TextInputType.numberWithOptions(
                            signed: true, decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'X',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _persist(),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Locate this corner',
                      icon: const Icon(Icons.my_location, color: PathfinderTheme.accent),
                      onPressed: () {
                        final c = _corners[idx];
                        final w = c.westing;
                        final s = c.southing;
                        if (w == null || s == null) {
                          _toast('Enter valid Y/X first');
                          return;
                        }
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
                      },
                    ),
                    IconButton(
                      tooltip: 'More actions',
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
              ),
            );
          }),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _openMap,
            icon: const Icon(Icons.map),
            label: const Text('View plot on map'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _scan,
            icon: const Icon(Icons.document_scanner),
            label: const Text('Scan Land Board certificate / notes'),
          ),
          const SizedBox(height: 10),
          if (_points.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Converted WGS84',
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
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
