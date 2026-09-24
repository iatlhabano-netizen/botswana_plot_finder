import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/lo_converter.dart';
import '../../core/lo_format.dart';
import '../../core/polygon_validation.dart';
import '../../services/area_audit.dart';
import '../../services/ocr_service.dart';
import '../../services/plot_calculator.dart';
import '../plot_finder/plot_finder_screen.dart';
import '../theme.dart';
import '../widgets/hybrid_map.dart';
import '../widgets/ocr_review_sheet.dart';

class _CornerRow {
  final TextEditingController y;
  final TextEditingController x;
  _CornerRow({String yText = '', String xText = ''})
      : y = TextEditingController(text: yText),
        x = TextEditingController(text: xText);
  void dispose() {
    y.dispose();
    x.dispose();
  }
}

/// Dedicated Lo polygon area calculator (hectares + m²) with certificate OCR.
class AreaCalculatorScreen extends StatefulWidget {
  const AreaCalculatorScreen({super.key});

  @override
  State<AreaCalculatorScreen> createState() => _AreaCalculatorScreenState();
}

class _AreaCalculatorScreenState extends State<AreaCalculatorScreen> {
  CountrySystem _country = LoConverter.supportedCountries.first;
  int _zone = 25;
  String _datum = 'bw_cape';
  final List<_CornerRow> _corners = [
    _CornerRow(),
    _CornerRow(),
    _CornerRow(),
    _CornerRow(),
  ];
  final OcrService _ocr = OcrService();
  PlotCalculationResult? _result;
  List<String> _errors = [];
  List<String> _warnings = [];
  double? _declaredHa;
  bool _scanning = false;
  bool _showPreview = false;

  @override
  void dispose() {
    _ocr.dispose();
    for (final c in _corners) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _calculate() {
    final lo = <Map<String, double>>[];
    final bad = <String>[];
    for (var i = 0; i < _corners.length; i++) {
      final w = double.tryParse(_corners[i].y.text.trim());
      final s = double.tryParse(_corners[i].x.text.trim());
      if (w == null || s == null) {
        bad.add('Corner ${i + 1}: enter valid Y and X (Lo metres).');
      } else {
        lo.add({'Y': w, 'X': s});
      }
    }
    // Validate ALL bad corners at once
    final issues = PolygonValidation.validateLoCorners(
      lo.length == _corners.length ? lo : lo,
    );
    // If some corners failed parse, still report those
    final blocking = [
      ...bad,
      ...issues.where((i) => i.blocking).map((i) => i.message),
    ];
    final warnings = issues.where((i) => !i.blocking).map((i) => i.message).toList();

    if (blocking.isNotEmpty || lo.length < 3) {
      setState(() {
        _result = null;
        _errors = blocking.isEmpty
            ? ['Need at least 3 valid corners for a polygon area.']
            : blocking;
        _warnings = warnings;
      });
      return;
    }

    setState(() {
      _errors = [];
      _warnings = warnings;
      _result = PlotCalculator.calculateFromLo(lo);
      _showPreview = true;
    });
  }

  void _fillSample() {
    final samples = [
      ('-74283', '2609149'),
      ('-74593', '2609153'),
      ('-74589', '2609473'),
      ('-74279', '2609469'),
    ];
    while (_corners.length < samples.length) {
      _corners.add(_CornerRow());
    }
    for (var i = 0; i < samples.length; i++) {
      _corners[i].y.text = samples[i].$1;
      _corners[i].x.text = samples[i].$2;
    }
    setState(() {});
    _calculate();
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
          _corners.add(_CornerRow(
            yText: formatLoCoord(p.westing),
            xText: formatLoCoord(p.southing),
          ));
        }
        if (outcome.declaredHectares != null) {
          _declaredHa = outcome.declaredHectares;
        }
        if (outcome.suggestedZone != null &&
            _country.availableZones.contains(outcome.suggestedZone)) {
          _zone = outcome.suggestedZone!;
        }
        _result = null;
        _errors = [];
        _warnings = [];
      });
      _toast('${outcome.pairs.length} corner(s) accepted — review, then calculate');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  List<ll.LatLng> get _wgsPoints {
    final out = <ll.LatLng>[];
    for (final c in _corners) {
      final w = double.tryParse(c.y.text.trim());
      final s = double.tryParse(c.x.text.trim());
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

  void _sendToPlotFinder() {
    // Persist corners into shared prefs so Plot Finder can pick them up via a
    // simple clipboard + toast instruction; also push Plot Finder with message.
    final buf = StringBuffer();
    for (var i = 0; i < _corners.length; i++) {
      buf.writeln('${_corners[i].y.text.trim()} ${_corners[i].x.text.trim()}');
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlotFinderScreen()),
    );
    _toast(
      'Opened Find my plot. Corners also copied — paste or re-scan if needed. '
      'Tip: use Sample/scan there, or manually enter the same Y/X.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final datums = LoConverter.availableDatums(_country.id);
    final audit = (_result != null && _declaredHa != null)
        ? AreaAuditor.auditArea(
            computedHectares: _result!.areaHectares,
            statedHectares: _declaredHa!,
          )
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calculate area'),
        actions: [
          IconButton(
            tooltip: 'Scan certificate / photo',
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
          TextButton(
            onPressed: _fillSample,
            child: const Text('Sample', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Enter plot corners in Lo metres (Y westing, X southing), or scan a '
            'Land Board certificate. Area uses the shoelace formula on the Lo plane — '
            'the same planimetric hectares as the certificate. '
            'Changing zone/datum does not change Lo hectares (only the map conversion).',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _scanning ? null : _scan,
            icon: _scanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.document_scanner),
            label: Text(_scanning ? 'Scanning…' : 'Scan certificate / photo'),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                DropdownButtonFormField<CountrySystem>(
                  value: _country,
                  decoration: const InputDecoration(
                      labelText: 'Country (for map conversion)',
                      border: OutlineInputBorder()),
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
                  },
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _country.availableZones.contains(_zone)
                          ? _zone
                          : _country.availableZones.first,
                      decoration: const InputDecoration(
                          labelText: 'Lo zone', border: OutlineInputBorder()),
                      items: _country.availableZones
                          .map((z) => DropdownMenuItem(
                              value: z, child: Text('Lo$z')))
                          .toList(),
                      onChanged: (v) => setState(() => _zone = v!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
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
                      onChanged: (v) => setState(() => _datum = v!),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text('Corners (Lo metres)',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _corners.add(_CornerRow())),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          ...List.generate(_corners.length, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  Row(children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: PathfinderTheme.seed,
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    Text('Corner ${i + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    IconButton(
                      onPressed: _corners.length <= 3
                          ? null
                          : () {
                              setState(() {
                                _corners.removeAt(i).dispose();
                              });
                            },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ]),
                  TextField(
                    controller: _corners[i].y,
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Y (Westing)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _corners[i].x,
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'X (Southing)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _calculate,
            icon: const Icon(Icons.square_foot),
            label: const Text('Calculate area'),
          ),
          if (_errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._errors.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $e',
                      style: TextStyle(color: Colors.red.shade700)),
                )),
          ],
          if (_warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._warnings.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $e',
                      style: TextStyle(color: Colors.orange.shade800)),
                )),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text('Calculated area', style: TextStyle(fontSize: 14)),
                    Text(
                      '${_result!.areaHectares.toStringAsFixed(4)} Ha',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_result!.areaSqMeters.toStringAsFixed(1)} m²',
                      style: const TextStyle(fontSize: 18),
                    ),
                    if (_declaredHa != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Certificate declared: ${_declaredHa!.toStringAsFixed(2)} Ha',
                        style: const TextStyle(fontSize: 14),
                      ),
                      if (audit != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            audit.message,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: audit.isMismatch
                                  ? Colors.orange.shade900
                                  : Colors.green.shade800,
                            ),
                          ),
                        ),
                    ],
                    const Divider(height: 24),
                    Text(
                      'Perimeter ${_result!.perimeterMeters.toStringAsFixed(1)} m',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: _result!.segments
                          .map((s) => Chip(
                                label: Text(
                                  'C${s.fromCorner}→C${s.toCorner}: ${s.lengthMeters.toStringAsFixed(1)} m',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        final text =
                            'Calculated: ${_result!.areaHectares.toStringAsFixed(4)} Ha '
                            '(${_result!.areaSqMeters.toStringAsFixed(1)} m²)\n'
                            'Perimeter: ${_result!.perimeterMeters.toStringAsFixed(1)} m\n'
                            '${_declaredHa != null ? "Certificate: ${_declaredHa!.toStringAsFixed(2)} Ha\n" : ""}'
                            'Lo$_zone / $_datum';
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy result'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _sendToPlotFinder,
                      icon: const Icon(Icons.grid_on),
                      label: const Text('Send corners to Find my plot'),
                    ),
                  ],
                ),
              ),
            ),
            if (_showPreview && _wgsPoints.length >= 3) ...[
              const SizedBox(height: 12),
              Text('Map preview',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              SizedBox(
                height: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: HybridMap(
                    center: _wgsPoints.first,
                    polygon: _wgsPoints,
                    fitToFeatures: true,
                    showDownloadButton: true,
                    markers: [
                      for (var i = 0; i < _wgsPoints.length; i++)
                        MapMarkerData(
                          point: _wgsPoints[i],
                          label: 'C${i + 1}',
                          color: PathfinderTheme.accent,
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Map positions (from Lo + zone/datum)',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    ...List.generate(_corners.length, (i) {
                      final w = double.tryParse(_corners[i].y.text.trim());
                      final s = double.tryParse(_corners[i].x.text.trim());
                      if (w == null || s == null) {
                        return const SizedBox.shrink();
                      }
                      final pt = LoConverter.toWgs84(
                        westing: w,
                        southing: s,
                        zone: _zone,
                        datumKey: _datum,
                      );
                      return Text(
                        'C${i + 1}: ${pt.latitude.toStringAsFixed(6)}, ${pt.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                      );
                    }),
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
