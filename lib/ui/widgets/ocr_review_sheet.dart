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
  final int? suggestedZone;
  const OcrReviewOutcome({
    required this.pairs,
    required this.rawText,
    required this.action,
    this.declaredHectares,
    this.suggestedZone,
  });
}

/// Sentinel used when the user picks "Paste coordinate text" (no camera).
class _PasteSource {
  const _PasteSource();
}

/// Shared OCR scan + review for Plot Finder and Area Calculator.
class OcrReviewFlow {
  /// Pick source → show loading during ML Kit → review sheet → Accept/Edit.
  static Future<OcrReviewOutcome?> scanAndReview({
    required BuildContext context,
    required OcrService ocr,
  }) async {
    final source = await showModalBottomSheet<Object>(
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
          ListTile(
            leading: const Icon(Icons.paste),
            title: const Text('Paste coordinate text'),
            subtitle: const Text('Skip camera — paste Y/X or beacon table'),
            onTap: () => Navigator.pop(ctx, const _PasteSource()),
          ),
        ]),
      ),
    );
    if (source == null || !context.mounted) return null;

    if (source is _PasteSource) {
      return _pasteAndReview(context: context);
    }

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
      result = await ocr.scan(source as ImageSource);
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

    // Empty pairs but non-empty raw OCR → fallback review (do not snackbar-bail).
    if (result.pairs.isEmpty) {
      if (result.rawText.trim().isEmpty) {
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

    return showOcrReviewSheet(context: context, result: result);
  }

  static Future<OcrReviewOutcome?> _pasteAndReview({
    required BuildContext context,
  }) async {
    final pasted = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Paste coordinate text'),
          content: SizedBox(
            width: double.maxFinite,
            child: TextField(
              controller: ctrl,
              maxLines: 12,
              decoration: const InputDecoration(
                hintText:
                    'Paste Y/X lines or a beacon table (e.g. A  -255124  -7604978)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Parse'),
            ),
          ],
        );
      },
    );
    if (pasted == null || !context.mounted) return null;
    if (pasted.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing pasted.')),
      );
      return null;
    }
    final result = OcrService.parseRecognizedText(pasted);
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
  late List<TextEditingController> _y;
  late List<TextEditingController> _x;
  late final TextEditingController _ha;
  late final TextEditingController _paste;
  late String _rawText;
  late int? _suggestedZone;
  bool _rawExpanded = false;

  @override
  void initState() {
    super.initState();
    _rawText = widget.result.rawText;
    _suggestedZone = widget.result.suggestedZone;
    _y = [
      for (final p in widget.result.pairs)
        TextEditingController(text: formatLoCoord(p.westing))
    ];
    _x = [
      for (final p in widget.result.pairs)
        TextEditingController(text: formatLoCoord(p.southing))
    ];
    // Empty-pairs fallback: start with one blank editable row.
    if (_y.isEmpty) {
      _y.add(TextEditingController());
      _x.add(TextEditingController());
    }
    _ha = TextEditingController(
      text: widget.result.declaredHectares?.toStringAsFixed(2) ?? '',
    );
    _paste = TextEditingController(text: _rawText);
    // Expand raw when parse failed so user can edit/re-parse.
    _rawExpanded = widget.result.pairs.isEmpty;
  }

  @override
  void dispose() {
    for (final c in [..._y, ..._x, _ha, _paste]) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyPairs(List<ParsedLoPair> pairs, {double? ha, int? zone}) {
    for (final c in [..._y, ..._x]) {
      c.dispose();
    }
    setState(() {
      _y = [
        for (final p in pairs)
          TextEditingController(text: formatLoCoord(p.westing))
      ];
      _x = [
        for (final p in pairs)
          TextEditingController(text: formatLoCoord(p.southing))
      ];
      if (_y.isEmpty) {
        _y.add(TextEditingController());
        _x.add(TextEditingController());
      }
      if (ha != null) _ha.text = ha.toStringAsFixed(2);
      if (zone != null) _suggestedZone = zone;
    });
  }

  void _parseAgain() {
    final text = _paste.text;
    final result = OcrService.parseRecognizedText(text);
    _rawText = result.rawText;
    _applyPairs(
      result.pairs,
      ha: result.declaredHectares,
      zone: result.suggestedZone,
    );
    if (result.pairs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Still no Y/X pairs. Edit the text or enter corners manually.'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Parsed ${result.pairs.length} corner(s).')),
      );
    }
  }

  void _addRow() {
    setState(() {
      _y.add(TextEditingController());
      _x.add(TextEditingController());
    });
  }

  List<ParsedLoPair>? _collect() {
    final pairs = <ParsedLoPair>[];
    for (var i = 0; i < _y.length; i++) {
      final yt = _y[i].text.trim();
      final xt = _x[i].text.trim();
      if (yt.isEmpty && xt.isEmpty) continue;
      final w = tryParseLoNumber(yt);
      final s = tryParseLoNumber(xt);
      if (w == null || s == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fix Y/X on row ${i + 1} before accepting.')),
        );
        return null;
      }
      pairs.add(ParsedLoPair(westing: w, southing: s));
    }
    if (pairs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enter at least one Y/X corner before accepting.')),
      );
      return null;
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
        rawText: _rawText,
        action: action,
        suggestedZone: _suggestedZone,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final emptyParse = widget.result.pairs.isEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              emptyParse
                  ? 'OCR found text — fix or paste corners'
                  : 'Review scanned corners',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              emptyParse
                  ? 'No Y/X pairs were parsed automatically. Edit the raw text '
                      'and tap Parse again, or type corners manually below.'
                  : 'Check Y (westing) / X (southing) before filling the form. '
                      'Decimals from the certificate are kept.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_suggestedZone != null) ...[
              const SizedBox(height: 6),
              Text('Suggested Lo zone: Lo$_suggestedZone',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: PathfinderTheme.seed,
                        fontWeight: FontWeight.w600,
                      )),
            ],
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
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addRow,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add row'),
              ),
            ),
            const SizedBox(height: 8),
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
              title: const Text('Raw OCR / paste text'),
              initiallyExpanded: false,
              onExpansionChanged: (v) => setState(() => _rawExpanded = v),
              children: [
                TextField(
                  controller: _paste,
                  maxLines: 8,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Paste or edit OCR text here',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: _parseAgain,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Parse again'),
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
