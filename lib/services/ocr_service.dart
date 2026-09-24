import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../core/models.dart';
import 'area_audit.dart';

class OcrScanResult {
  final List<ParsedLoPair> pairs;
  final double? declaredHectares;
  final String rawText;
  const OcrScanResult({
    required this.pairs,
    required this.rawText,
    this.declaredHectares,
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
        maxWidth: 2600,
        maxHeight: 2600,
        // Force JPEG recompression on Android — avoids HEIC/null-bitmap NPEs
        // inside ML Kit InputImage.fromFilePath.
        imageQuality: 90,
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
    final cleaned = text.replaceAll(RegExp(r'[oO](?=\d)'), '0');
    final pairs = parseLoCoordinates(cleaned);
    return OcrScanResult(
      pairs: pairs,
      rawText: cleaned,
      declaredHectares: AreaAuditor.extractStatedArea(cleaned),
    );
  }

  /// Botswana Lo plausible southing |X| (metres from equator, Capricorn belt).
  static const double _minSouthingAbs = 1000000;
  static const double _maxSouthingAbs = 9500000;

  /// Botswana Lo plausible westing |Y| (metres from zone central meridian).
  static const double _maxWestingAbs = 600000;

  /// Reject tiny OCR junk (e.g. 123 / 456) while allowing real |Y| ~ tens of km.
  static const double _minWestingAbs = 1000;

  /// Collapse OCR artifacts in Lo numbers: spaced signs, spaced/comma thousands.
  ///
  /// Examples: `- 255 124.38` → `-255124.38`, `-7 604 978.00` → `-7604978.00`,
  /// `255,124.38` → `255124.38`. Leaves decimal points alone; does not touch
  /// bearings like `1.20.43` (multiple dots).
  static String normalizeLoNumberText(String text) {
    var s = text;
    // Spaced sign before a digit: "- 255" / "+ 7" → "-255" / "+7"
    s = s.replaceAllMapped(RegExp(r'([+-])\s+(?=\d)'), (m) => m.group(1)!);

    // US/OCR thousands commas: 255,124.38 or 2,609,149
    s = s.replaceAllMapped(
      RegExp(r'(?<![\d.])\d{1,3}(?:,\d{3})+(?:\.\d+)?'),
      (m) => m.group(0)!.replaceAll(',', ''),
    );

    // Spaced thousands groups: 255 124.38 / 7 604 978.00
    s = s.replaceAllMapped(
      RegExp(r'(?<![\d.])\d{1,3}(?:\s\d{3})+(?:\.\d+)?'),
      (m) => m.group(0)!.replaceAll(RegExp(r'\s'), ''),
    );

    return s;
  }

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
      r'Y\s*[:=]?\s*([+-]?\d[\d\s]{2,9}\d(?:\.\d+)?)\s*[,;:\s]+\s*X\s*[:=]?\s*([+-]?\d[\d\s]{4,9}\d(?:\.\d+)?)',
      caseSensitive: false,
    );
    final reXY = RegExp(
      r'X\s*[:=]?\s*([+-]?\d[\d\s]{4,9}\d(?:\.\d+)?)\s*[,;:\s]+\s*Y\s*[:=]?\s*([+-]?\d[\d\s]{2,9}\d(?:\.\d+)?)',
      caseSensitive: false,
    );

    final parsed = <ParsedLoPair>[];
    final spans = <(int, int)>[];

    for (final m in reYX.allMatches(text)) {
      if (spans.any((sp) => m.start < sp.$2 && m.end > sp.$1)) continue;
      final w = double.tryParse(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
      final s = double.tryParse(m.group(2)!.replaceAll(RegExp(r'\s'), ''));
      if (w != null && s != null) {
        parsed.add(ParsedLoPair(westing: w, southing: s));
        spans.add((m.start, m.end));
      }
    }
    for (final m in reXY.allMatches(text)) {
      if (spans.any((sp) => m.start < sp.$2 && m.end > sp.$1)) continue;
      final s = double.tryParse(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
      final w = double.tryParse(m.group(2)!.replaceAll(RegExp(r'\s'), ''));
      if (w != null && s != null) {
        parsed.add(ParsedLoPair(westing: w, southing: s));
        spans.add((m.start, m.end));
      }
    }

    if (parsed.isNotEmpty) return parsed;

    // Beacon / Land Board table rows (header optional):
    //   A  -255124.38   -7604978.00
    // Prefer Y then X column order. Skip Constants 0/0 and bearings.
    final beaconPairs = _parseBeaconTablePairs(text);
    if (beaconPairs.isNotEmpty) return beaconPairs;

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

  /// Parse Land Board beacon / co-ordinate table rows into Lo pairs.
  ///
  /// Only letter-labeled rows (A/B/C…) are accepted here so handwritten
  /// bare lists still flow through the sequential bare-pair path.
  static List<ParsedLoPair> _parseBeaconTablePairs(String text) {
    final pairs = <ParsedLoPair>[];
    final labeledRow = RegExp(
      r'^\s*[A-Za-z]\b\s*([+-]?\d{4,10}(?:\.\d+)?)\s+([+-]?\d{4,10}(?:\.\d+)?)',
    );

    for (final rawLine in text.split(RegExp(r'[\r\n]+'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final lower = line.toLowerCase();
      if (lower.contains('constant')) continue;
      if (_bearingLike.hasMatch(line)) continue;

      final labeled = labeledRow.firstMatch(line);
      if (labeled == null) continue;
      final a = double.tryParse(labeled.group(1)!);
      final b = double.tryParse(labeled.group(2)!);
      if (a == null || b == null) continue;
      if (a.abs() < 1e-6 && b.abs() < 1e-6) continue;
      final pair = _pairFromTwo(a, b);
      if (pair != null) pairs.add(pair);
    }
    return pairs;
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
