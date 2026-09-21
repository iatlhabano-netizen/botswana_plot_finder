import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/lo_converter.dart';
import '../../services/ocr_service.dart';
import '../../services/plot_calculator.dart';
import '../theme.dart';

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
  String? _error;
  double? _declaredHa;
  bool _scanning = false;

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
    for (var i = 0; i < _corners.length; i++) {
      final w = double.tryParse(_corners[i].y.text.trim());
      final s = double.tryParse(_corners[i].x.text.trim());
      if (w == null || s == null) {
        setState(() {
          _result = null;
          _error = 'Corner ${i + 1}: enter valid Y and X (Lo metres).';
        });
        return;
      }
      lo.add({'Y': w, 'X': s});
    }
    if (lo.length < 3) {
      setState(() {
        _result = null;
        _error = 'Need at least 3 corners for a polygon area.';
      });
      return;
    }
    setState(() {
      _error = null;
      _result = PlotCalculator.calculateFromLo(lo);
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
            title: const Text('Upload picture from gallery'),
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
          _corners.add(_CornerRow(
            yText: p.westing.toStringAsFixed(0),
            xText: p.southing.toStringAsFixed(0),
          ));
        }
        if (result.declaredHectares != null) {
          _declaredHa = result.declaredHectares;
        }
        _result = null;
        _error = null;
      });
      _toast('${result.pairs.length} corner(s) loaded — review, then calculate');
    } on OcrException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Scan failed. Try another photo or check camera/gallery permissions.');
      debugPrint('Area Calculator scan error: $e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final datums = LoConverter.availableDatums(_country.id);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Area Calculator'),
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
            'Enter plot corners in Lo (Y westing, X southing), or scan a '
            'Land Board certificate / photo of coordinates. '
            'Area is computed on the Lo plane (survey metres) via shoelace — '
            'standard for Land Board certificates.',
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
            label: Text(_scanning
                ? 'Scanning…'
                : 'Scan certificate / photo'),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
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
                          labelText: 'Datum', border: OutlineInputBorder()),
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
              child: Row(children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: PathfinderTheme.seed,
                  child: Text('${i + 1}',
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _corners[i].y,
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Y (Westing)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _corners[i].x,
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'X (Southing)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
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
            );
          }),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _calculate,
            icon: const Icon(Icons.square_foot),
            label: const Text('Calculate area'),
          ),
          if (_declaredHa != null) ...[
            const SizedBox(height: 8),
            Text(
              'Certificate declared area: ${_declaredHa!.toStringAsFixed(2)} Ha',
              style: TextStyle(color: Colors.blueGrey.shade700),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text('Plot area', style: TextStyle(fontSize: 14)),
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
                        'Declared on certificate: ${_declaredHa!.toStringAsFixed(2)} Ha',
                        style: const TextStyle(fontSize: 13),
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
                            'Area: ${_result!.areaHectares.toStringAsFixed(4)} Ha '
                            '(${_result!.areaSqMeters.toStringAsFixed(1)} m²)\n'
                            'Perimeter: ${_result!.perimeterMeters.toStringAsFixed(1)} m\n'
                            'Lo$_zone / $_datum';
                        Clipboard.setData(ClipboardData(text: text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy result'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WGS84 corners (reference)',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    ...List.generate(_corners.length, (i) {
                      final w = double.tryParse(_corners[i].y.text.trim());
                      final s = double.tryParse(_corners[i].x.text.trim());
                      if (w == null || s == null) return const SizedBox.shrink();
                      final pt = LoConverter.toWgs84(
                        westing: w,
                        southing: s,
                        zone: _zone,
                        datumKey: _datum,
                      );
                      return Text(
                        'C${i + 1}: ${pt.latitude.toStringAsFixed(6)}, ${pt.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
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
