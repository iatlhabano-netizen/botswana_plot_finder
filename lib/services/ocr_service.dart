import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../core/lo_format.dart' as lo_fmt;
import '../core/models.dart';
import 'area_audit.dart';

class OcrScanResult {
  final List<ParsedLoPair> pairs;
  final double? declaredHectares;
  final String rawText;
  /// Lo zone inferred from certificate headers like "LO 25" / "System LO25".
  final int? suggestedZone;
  const OcrScanResult({
    required this.pairs,
    required this.rawText,
    this.declaredHectares,
    this.suggestedZone,
  });
}

/// User-facing OCR failure (never leaks raw PlatformException stacks).
class OcrException implements Exception {
  final String message;
  const OcrException(this.message);
  @override
  String toString() => message;
}

/// On-device Land Board certificate / handwritten Lo OCR via ML Kit.
class OcrService {
  TextRecognizer? _recognizer;
  final ImagePicker _picker;

  OcrService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  TextRecognizer get _textRecognizer =>
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);

  /// Pick an image and run OCR + Lo parsing. Returns null if user cancels.
  Future<OcrScanResult?> scan(ImageSource source) async {
    final XFile? photo;
    try {
      photo = await _picker.pickImage(
        source: source,
        maxWidth: 3200,
        maxHeight: 3200,
        // Force JPEG recompression on Android — avoids HEIC/null-bitmap NPEs
        // inside ML Kit InputImage.fromFilePath.
        imageQuality: 95,
        requestFullMetadata: false,
      );
    } on PlatformException catch (e) {
      throw OcrException(_friendlyPickerError(e, source));
    } catch (e) {
      throw OcrException('Could not open the camera or gallery. ($e)');
    }
    if (photo == null) return null;
    return scanXFile(photo);
  }

  /// OCR a picked/local image file with full null/empty/decode guards.
  Future<OcrScanResult> scanXFile(XFile photo) async {
    final path = photo.path.trim();
    if (path.isEmpty) {
      throw const OcrException(
          'No image was selected. Please try again.');
    }

    // Prefer reading bytes first — validates the picker actually returned data.
    Uint8List bytes;
    try {
      bytes = await photo.readAsBytes();
    } catch (e) {
      throw const OcrException(
          'Could not read the selected image. Please try another photo.');
    }
    if (bytes.isEmpty) {
      throw const OcrException(
          'The selected image is empty. Please take or choose another photo.');
    }

    // Ensure a real on-disk JPEG/PNG that ML Kit can open (cache copy).
    final File localFile = await _materializeLocalImage(path, bytes);

    if (!await localFile.exists() || await localFile.length() == 0) {
      throw const OcrException(
          'Image file is missing or empty after save. Please try again.');
    }

    final String text;
    try {
      final input = InputImage.fromFilePath(localFile.path);
      final recognized = await _textRecognizer.processImage(input);
      text = recognized.text;
    } on PlatformException catch (e) {
      debugPrint('OCR PlatformException: ${e.code} ${e.message}');
      throw OcrException(_friendlyMlKitError(e));
    } catch (e) {
      debugPrint('OCR failed: $e');
      if (e is OcrException) rethrow;
      throw const OcrException(
          'Text recognition failed. Try a clearer, well-lit photo of the coordinates.');
    }

    return parseRecognizedText(text);
  }

  /// Pure parsing of OCR text into Lo pairs + declared hectares (testable).
  static OcrScanResult parseRecognizedText(String text) {
    // Zone headers like "LO25" must be read before O→0, which turns them
    // into "L025" and hides the zone.
    final zoneOnRaw = detectSuggestedZone(text);
    final cleaned = cleanupOcrDigitConfusions(
      text.replaceAll(RegExp(r'[oO](?=\d)'), '0'),
    );
    final pairs = parseLoCoordinates(cleaned);
    return OcrScanResult(
      pairs: pairs,
      rawText: cleaned,
      declaredHectares: AreaAuditor.extractStatedArea(cleaned),
      suggestedZone: zoneOnRaw ?? detectSuggestedZone(cleaned),
    );
  }

  /// Fix common OCR letter/digit swaps inside numeric contexts.
  ///
  /// `l`/`I` → `1`, and `S`/`s` → `5` when flanked by digits (or after a sign).
  static String cleanupOcrDigitConfusions(String text) {
    var s = text;
    // l or I between digits / after sign / before digit group
    s = s.replaceAllMapped(
      RegExp(r'(?<=[\d+-])[lI](?=\d)'),
      (_) => '1',
    );
    s = s.replaceAllMapped(
      RegExp(r'(?<=\d)[lI](?=[\d.\s]|$)'),
      (_) => '1',
    );
    // S/s as 5 between digits (not in words like "System" — require digit neighborship)
    s = s.replaceAllMapped(
      RegExp(r'(?<=\d)[Ss](?=\d)'),
      (_) => '5',
    );
    return s;
  }

  /// Detect Lo zone from headers: "LO 25", "System LO25", "LO. 27°", "LO25".
  static int? detectSuggestedZone(String text) {
    final m = RegExp(
      r'(?:system\s+)?lo\.?\s*([0-9]{2})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return null;
    final z = int.tryParse(m.group(1)!);
    if (z == null) return null;
    const known = {11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31, 33};
    return known.contains(z) ? z : null;
  }

  /// Botswana Lo plausible southing |X| (metres from equator, Capricorn belt).
  static const double _minSouthingAbs = 1000000;
  static const double _maxSouthingAbs = 9500000;

  /// Botswana Lo plausible westing |Y| (metres from zone central meridian).
  static const double _maxWestingAbs = 600000;

  /// Reject tiny OCR junk while still accepting a beacon a few metres from
  /// the zone central meridian. Pairing already requires a Lo-scale southing,
  /// so a 1 km floor was dropping real near-CM corners (Y under 1 000 m).
  static const double _minWestingAbs = 0.5;

  /// Collapse OCR artifacts in Lo numbers (implementation in lo_format.dart).
  /// Kept on [OcrService] so existing call sites and tests stay stable.
  static String normalizeLoNumberText(String text) =>
      lo_fmt.normalizeLoNumberText(text);

  static bool _isPlausibleSouthing(double v) {
    final a = v.abs();
    return a >= _minSouthingAbs && a <= _maxSouthingAbs;
  }

  static bool _isPlausibleWesting(double v) {
    final a = v.abs();
    return a >= _minWestingAbs && a <= _maxWestingAbs;
  }


  static ParsedLoPair? _pairFromTwo(double a, double b) {
    if (_isPlausibleWesting(a) && _isPlausibleSouthing(b)) {
      return ParsedLoPair(westing: a, southing: b);
    }
    if (_isPlausibleSouthing(a) && _isPlausibleWesting(b)) {
      return ParsedLoPair(westing: b, southing: a);
    }
    return null;
  }

  /// True for DMS-style bearings / directions e.g. `1.20.43` or `12.05.10`.
  static final RegExp _bearingLike = RegExp(r'\d+\.\d+\.\d+');

  /// Extract Y/X (westing/southing) Lo pairs from cleaned OCR text.
  static List<ParsedLoPair> parseLoCoordinates(String cleaned) {
    final text = normalizeLoNumberText(cleaned);

    final reYX = RegExp(
      r'Y\s*[:=]?\s*([+-]?\d{1,12}(?:\.\d+)?)\s*[,;:\s]+\s*X\s*[:=]?\s*([+-]?\d{1,12}(?:\.\d+)?)',
      caseSensitive: false,
    );
    final reXY = RegExp(
      r'X\s*[:=]?\s*([+-]?\d{1,12}(?:\.\d+)?)\s*[,;:\s]+\s*Y\s*[:=]?\s*([+-]?\d{1,12}(?:\.\d+)?)',
      caseSensitive: false,
    );

    final parsed = <ParsedLoPair>[];
    final spans = <(int, int)>[];

    for (final m in reYX.allMatches(text)) {
      if (spans.any((sp) => m.start < sp.$2 && m.end > sp.$1)) continue;
      final w = double.tryParse(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
      final s = double.tryParse(m.group(2)!.replaceAll(RegExp(r'\s'), ''));
      if (w != null && s != null) {
        final pair = _pairFromTwo(w, s) ?? ParsedLoPair(westing: w, southing: s);
        // Only keep plausible Lo magnitudes from labeled Y/X (avoids +0,00 junk).
        if (_isPlausibleWesting(pair.westing) &&
            _isPlausibleSouthing(pair.southing)) {
          parsed.add(pair);
          spans.add((m.start, m.end));
        }
      }
    }
    for (final m in reXY.allMatches(text)) {
      if (spans.any((sp) => m.start < sp.$2 && m.end > sp.$1)) continue;
      final s = double.tryParse(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
      final w = double.tryParse(m.group(2)!.replaceAll(RegExp(r'\s'), ''));
      if (w != null && s != null) {
        final pair = _pairFromTwo(w, s) ?? ParsedLoPair(westing: w, southing: s);
        if (_isPlausibleWesting(pair.westing) &&
            _isPlausibleSouthing(pair.southing)) {
          parsed.add(pair);
          spans.add((m.start, m.end));
        }
      }
    }

    // Beacon / Land Board table rows (header optional):
    //   A  -255124.38   -7604978.00
    //   A  +103208.35   +2702523.47
    // Merge Y/X-labeled hits with letter-labeled beacon rows so a single
    // accidental "Y … X …" match cannot drop the remaining A/B/C/D corners.
    final beaconPairs = _parseBeaconTablePairs(text);
    final columnPairs = _parseColumnMajor(text);
    // Column-major (all Y, then all X) is merged in, not used as a
    // short-circuit, so a real beacon row is never dropped.
    final merged = _mergeUniquePairs(parsed, [...beaconPairs, ...columnPairs]);
    if (merged.isNotEmpty) return merged;

    // Bare number pairs (handwritten lists): large X + Y
    final nums = RegExp(r'[+-]?\d{4,10}(?:\.\d+)?')
        .allMatches(text)
        .map((m) => double.tryParse(m.group(0)!))
        .whereType<double>()
        .toList();
    for (var i = 0; i + 1 < nums.length; i++) {
      final pair = _pairFromTwo(nums[i], nums[i + 1]);
      if (pair != null) {
        parsed.add(pair);
        i++;
      }
    }

    return parsed;
  }


  /// Append [extra] pairs not already present in [base] (0.05 m tolerance).
  static List<ParsedLoPair> _mergeUniquePairs(
    List<ParsedLoPair> base,
    List<ParsedLoPair> extra,
  ) {
    final out = <ParsedLoPair>[...base];
    for (final p in extra) {
      final dup = out.any((q) =>
          (q.westing - p.westing).abs() < 0.05 &&
          (q.southing - p.southing).abs() < 0.05);
      if (!dup) out.add(p);
    }
    return out;
  }

  /// Parse Land Board beacon / co-ordinate table rows into Lo pairs.
  ///
  /// Only letter-labeled rows (A/B/C…) are accepted here so handwritten
  /// bare lists still flow through the sequential bare-pair path.
  /// Allows optional Y/X column tags after the beacon letter.
  ///
  /// ML Kit often splits a table row so the beacon letter and Y sit on one
  /// line and X on the next (or the letter alone, then Y, then X). Those
  /// rows are stitched before giving up — otherwise one intact corner makes
  /// [parseLoCoordinates] return early and drop the split ones.
  static List<ParsedLoPair> _parseBeaconTablePairs(String text) {
    final pairs = <ParsedLoPair>[];
    final labeledRow = RegExp(
      r'^[A-Za-z]\b(?:\s*[YyXx]\b)?\s*'
      r'([+-]?\d{1,12}(?:\.\d+)?)\s+'
      r'(?:[XxYy]\b\s*)?'
      r'([+-]?\d{1,12}(?:\.\d+)?)',
    );
    final letterAndOne = RegExp(
      r'^[A-Za-z]\b(?:\s*[YyXx]\b)?\s*([+-]?\d{1,12}(?:\.\d+)?)(?:\s*[XxYy]\b)?$',
    );
    final justNumber = RegExp(r'^[+-]?\d{1,12}(?:\.\d+)?$');
    // Exclude Y/X — those are column headers, not beacon letters.
    final justLetter = RegExp(r'^[A-Wa-wZz]$');

    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    bool skip(String line) {
      final lower = line.toLowerCase();
      if (lower.contains('constant')) return true;
      if (_bearingLike.hasMatch(line)) return true;
      return false;
    }

    void addPair(String as, String bs) {
      final a = double.tryParse(as);
      final b = double.tryParse(bs);
      if (a == null || b == null) return;
      if (a.abs() < 1e-6 && b.abs() < 1e-6) return;
      final pair = _pairFromTwo(a, b);
      if (pair != null) pairs.add(pair);
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (skip(line)) continue;

      final labeled = labeledRow.firstMatch(line);
      if (labeled != null) {
        addPair(labeled.group(1)!, labeled.group(2)!);
        continue;
      }

      final one = letterAndOne.firstMatch(line);
      if (one != null && i + 1 < lines.length && !skip(lines[i + 1])) {
        final nxt = justNumber.firstMatch(lines[i + 1]);
        if (nxt != null) {
          addPair(one.group(1)!, nxt.group(0)!);
          i++;
          continue;
        }
      }

      if (justLetter.hasMatch(line) &&
          i + 2 < lines.length &&
          !skip(lines[i + 1]) &&
          !skip(lines[i + 2])) {
        final n1 = justNumber.firstMatch(lines[i + 1]);
        final n2 = justNumber.firstMatch(lines[i + 2]);
        if (n1 != null && n2 != null) {
          addPair(n1.group(0)!, n2.group(0)!);
          i += 2;
        }
      }
    }
    return pairs;
  }

  /// ML Kit sometimes reads a certificate down the columns: every Y, then
  /// every X (or a `Y` header, numbers, an `X` header, numbers).
  /// Westing and southing ranges do not overlap, so a clean W,W,W,S,S,S
  /// run zips in order. Alternating W,S,W,S is left to the bare-pair path.
  static List<ParsedLoPair> _parseColumnMajor(String text) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    bool skip(String line) {
      final lower = line.toLowerCase();
      if (lower.contains('constant')) return true;
      if (_bearingLike.hasMatch(line)) return true;
      return false;
    }

    final taggedY = <double>[];
    final taggedX = <double>[];
    final yLine = RegExp(
      r'^Y\b\s*[:=]?\s*([+-]?\d{1,12}(?:\.\d+)?)$',
      caseSensitive: false,
    );
    final xLine = RegExp(
      r'^X\b\s*[:=]?\s*([+-]?\d{1,12}(?:\.\d+)?)$',
      caseSensitive: false,
    );
    for (final line in lines) {
      if (skip(line)) continue;
      final y = yLine.firstMatch(line);
      if (y != null) {
        final v = double.tryParse(y.group(1)!);
        if (v != null && _isPlausibleWesting(v)) taggedY.add(v);
        continue;
      }
      final x = xLine.firstMatch(line);
      if (x != null) {
        final v = double.tryParse(x.group(1)!);
        if (v != null && _isPlausibleSouthing(v)) taggedX.add(v);
      }
    }
    if (taggedY.length >= 2 && taggedY.length == taggedX.length) {
      return [
        for (var i = 0; i < taggedY.length; i++)
          ParsedLoPair(westing: taggedY[i], southing: taggedX[i]),
      ];
    }

    int? yAt;
    int? xAt;
    for (var i = 0; i < lines.length; i++) {
      if (skip(lines[i])) continue;
      if (RegExp(r'^Y$', caseSensitive: false).hasMatch(lines[i])) yAt = i;
      if (yAt != null &&
          i > yAt &&
          RegExp(r'^X$', caseSensitive: false).hasMatch(lines[i])) {
        xAt = i;
        break;
      }
    }
    if (yAt != null && xAt != null) {
      final ys = _loneNumbers(lines, yAt + 1, xAt, southing: false);
      final xs = _loneNumbers(lines, xAt + 1, lines.length, southing: true);
      if (ys.length >= 2 && ys.length == xs.length) {
        return [
          for (var i = 0; i < ys.length; i++)
            ParsedLoPair(westing: ys[i], southing: xs[i]),
        ];
      }
    }

    // No headers: one run of lone westings, then one run of lone southings.
    final seq = <(bool, double)>[];
    for (final line in lines) {
      if (skip(line)) continue;
      if (!RegExp(r'^[+-]?\d{1,12}(?:\.\d+)?$').hasMatch(line)) continue;
      final v = double.tryParse(line);
      if (v == null) continue;
      if (_isPlausibleSouthing(v)) {
        seq.add((true, v));
      } else if (_isPlausibleWesting(v)) {
        seq.add((false, v));
      }
    }
    if (seq.length < 4) return const [];
    final firstSouth = seq.first.$1;
    final split = seq.indexWhere((e) => e.$1 != firstSouth);
    if (split <= 0) return const [];
    if (seq.skip(split).any((e) => e.$1 == firstSouth)) return const [];
    final head = seq.sublist(0, split);
    final tail = seq.sublist(split);
    if (head.length != tail.length || head.length < 2) return const [];
    return [
      for (var i = 0; i < head.length; i++)
        ParsedLoPair(
          westing: firstSouth ? tail[i].$2 : head[i].$2,
          southing: firstSouth ? head[i].$2 : tail[i].$2,
        ),
    ];
  }

  static List<double> _loneNumbers(
    List<String> lines,
    int from,
    int to, {
    required bool southing,
  }) {
    final out = <double>[];
    for (var i = from; i < to && i < lines.length; i++) {
      final line = lines[i];
      if (!RegExp(r'^[+-]?\d{1,12}(?:\.\d+)?$').hasMatch(line)) continue;
      final v = double.tryParse(line);
      if (v == null) continue;
      final ok = southing ? _isPlausibleSouthing(v) : _isPlausibleWesting(v);
      if (ok) out.add(v);
    }
    return out;
  }


  /// Copy bytes into app temp dir so ML Kit always gets a readable file path.
  Future<File> _materializeLocalImage(String originalPath, Uint8List bytes) async {
    // If the picker path already points at a readable local file with data,
    // reuse it — but still prefer a cache copy when the path looks like a
    // content URI fragment or the file is missing.
    final original = File(originalPath);
    try {
      if (await original.exists() && await original.length() > 0) {
        // Sanity: ensure we can re-read (guards broken content:// style paths).
        final probe = await original.openRead(0, 16).first;
        if (probe.isNotEmpty) return original;
      }
    } catch (_) {
      // Fall through to cache copy.
    }

    final dir = await getTemporaryDirectory();
    final ext = _guessExt(originalPath, bytes);
    final out = File(
      '${dir.path}/ocr_${DateTime.now().millisecondsSinceEpoch}$ext',
    );
    await out.writeAsBytes(bytes, flush: true);
    return out;
  }

  static String _guessExt(String path, Uint8List bytes) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png') || _isPng(bytes)) return '.png';
    if (lower.endsWith('.webp')) return '.webp';
    return '.jpg';
  }

  static bool _isPng(Uint8List b) =>
      b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47;

  static String _friendlyPickerError(PlatformException e, ImageSource source) {
    final msg = (e.message ?? '').toLowerCase();
    if (msg.contains('permission') || e.code.toLowerCase().contains('permission')) {
      return source == ImageSource.camera
          ? 'Camera permission is required to photograph a certificate.'
          : 'Photo library permission is required to upload a certificate.';
    }
    if (msg.contains('camera') && msg.contains('not available')) {
      return 'Camera is not available on this device.';
    }
    return 'Could not open ${source == ImageSource.camera ? 'camera' : 'gallery'}. '
        'Check app permissions and try again.';
  }

  static String _friendlyMlKitError(PlatformException e) {
    final raw = '${e.code} ${e.message} ${e.details}'.toLowerCase();
    if (raw.contains('null') ||
        raw.contains('getclass') ||
        raw.contains('inputimage') ||
        raw.contains('bitmap')) {
      return 'Could not read that image for text recognition. '
          'Try re-taking the photo in good light (avoid HEIC/screenshots if possible).';
    }
    return 'Text recognition failed. Try a clearer photo of the Y/X coordinates.';
  }

  void dispose() {
    _recognizer?.close();
    _recognizer = null;
  }
}
