import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/lo_format.dart';
import '../../core/models.dart';
import '../../services/ocr_service.dart';
import '../theme.dart';

/// Result of the OCR propose → Accept/Edit flow.
class OcrReviewOutcome {
  final List<ParsedLoPair> pairs;
  final double? declaredHectares;
  final String rawText;
  /// 'replace' | 'append'
  final String action;
  const OcrReviewOutcome({
    required this.pairs,
    required this.rawText,
    required this.action,
    this.declaredHectares,
  });
}

/// Shared OCR scan + review for Plot Finder and Area Calculator.
class OcrReviewFlow {
  /// Pick source → show loading during ML Kit → review sheet → Accept/Edit.
  static Future<OcrReviewOutcome?> scanAndReview({
    required BuildContext context,
    required OcrService ocr,
  }) async {
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
    if (source == null || !context.mounted) return null;

    // Loading dialog while ML Kit runs
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Reading certificate…')),
          ],
        ),
      ),
    );

    OcrScanResult? result;
    Object? error;
    try {
      result = await ocr.scan(source);
    } catch (e) {
      error = e;
    }
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!context.mounted) return null;

    if (error != null) {
      final msg = error is OcrException
          ? error.message
          : 'Scan failed. Try another photo or check camera/gallery permissions.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return null;
    }
    if (result == null) return null;
    if (result.pairs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No coordinates found. Try better lighting or clearer numbers.'),
        ),
      );
      return null;
    }

    return showOcrReviewSheet(context: context, result: result);
  }

  static Future<OcrReviewOutcome?> showOcrReviewSheet({
    required BuildContext context,
    required OcrScanResult result,
  }) {
    return showModalBottomSheet<OcrReviewOutcome>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _OcrReviewBody(result: result),
    );
  }
}

class _OcrReviewBody extends StatefulWidget {
  final OcrScanResult result;
  const _OcrReviewBody({required this.result});

  @override
  State<_OcrReviewBody> createState() => _OcrReviewBodyState();
}

class _OcrReviewBodyState extends State<_OcrReviewBody> {
  late final List<TextEditingController> _y;
  late final List<TextEditingController> _x;
  late final TextEditingController _ha;
  bool _rawExpanded = false;

  @override
  void initState() {
    super.initState();
    _y = [
      for (final p in widget.result.pairs)
        TextEditingController(text: formatLoCoord(p.westing))
    ];
    _x = [
      for (final p in widget.result.pairs)
        TextEditingController(text: formatLoCoord(p.southing))
    ];
    _ha = TextEditingController(
      text: widget.result.declaredHectares?.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void dispose() {
    for (final c in [..._y, ..._x, _ha]) {
      c.dispose();
    }
    super.dispose();
  }

  List<ParsedLoPair>? _collect() {
    final pairs = <ParsedLoPair>[];
    for (var i = 0; i < _y.length; i++) {
      final w = double.tryParse(_y[i].text.trim());
      final s = double.tryParse(_x[i].text.trim());
      if (w == null || s == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fix Y/X on row ${i + 1} before accepting.')),
        );
        return null;
      }
      pairs.add(ParsedLoPair(westing: w, southing: s));
    }
    return pairs;
  }

  void _accept(String action) {
    final pairs = _collect();
    if (pairs == null) return;
    final ha = double.tryParse(_ha.text.trim());
    Navigator.pop(
      context,
      OcrReviewOutcome(
        pairs: pairs,
        declaredHectares: ha ?? widget.result.declaredHectares,
        rawText: widget.result.rawText,
        action: action,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Review scanned corners',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Check Y (westing) / X (southing) before filling the form. '
              'Decimals from the certificate are kept.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FixedColumnWidth(36),
                1: FlexColumnWidth(),
                2: FlexColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                const TableRow(children: [
                  Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text('#',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text('Y (Westing)',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text('X (Southing)',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                ]),
                for (var i = 0; i < _y.length; i++)
                  TableRow(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: PathfinderTheme.seed,
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 4),
                      child: TextField(
                        controller: _y[i],
                        keyboardType: const TextInputType.numberWithOptions(
                            signed: true, decimal: true),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 4),
                      child: TextField(
                        controller: _x[i],
                        keyboardType: const TextInputType.numberWithOptions(
                            signed: true, decimal: true),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ]),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ha,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Declared area (Ha) — optional',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              title: const Text('Raw OCR text'),
              initiallyExpanded: false,
              onExpansionChanged: (v) => setState(() => _rawExpanded = v),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: SelectableText(
                    widget.result.rawText.isEmpty
                        ? '(empty)'
                        : widget.result.rawText,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ],
            ),
            if (_rawExpanded) const SizedBox(height: 4),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _accept('append'),
                    child: const Text('Append'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _accept('replace'),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
