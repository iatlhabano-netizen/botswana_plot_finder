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

  /// Extract Y/X (westing/southing) Lo pairs from cleaned OCR text.
  static List<ParsedLoPair> parseLoCoordinates(String cleaned) {
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

    for (final m in reYX.allMatches(cleaned)) {
      if (spans.any((sp) => m.start < sp.$2 && m.end > sp.$1)) continue;
      final w = double.tryParse(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
      final s = double.tryParse(m.group(2)!.replaceAll(RegExp(r'\s'), ''));
      if (w != null && s != null) {
        parsed.add(ParsedLoPair(westing: w, southing: s));
        spans.add((m.start, m.end));
      }
    }
    for (final m in reXY.allMatches(cleaned)) {
      if (spans.any((sp) => m.start < sp.$2 && m.end > sp.$1)) continue;
      final s = double.tryParse(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
      final w = double.tryParse(m.group(2)!.replaceAll(RegExp(r'\s'), ''));
      if (w != null && s != null) {
        parsed.add(ParsedLoPair(westing: w, southing: s));
        spans.add((m.start, m.end));
      }
    }

    // Bare number pairs (handwritten lists): large X (~7 digits) + Y
    if (parsed.isEmpty) {
      final nums = RegExp(r'[+-]?\d{4,10}(?:\.\d+)?')
          .allMatches(cleaned)
          .map((m) => double.tryParse(m.group(0)!))
          .whereType<double>()
          .toList();
      // Heuristic: southing typically 1.5e6–3.2e6, westing |y|<2e5
      for (var i = 0; i + 1 < nums.length; i++) {
        final a = nums[i];
        final b = nums[i + 1];
        if (b.abs() >= 1500000 && b.abs() <= 3200000 && a.abs() <= 200000) {
          parsed.add(ParsedLoPair(westing: a, southing: b));
          i++;
        } else if (a.abs() >= 1500000 &&
            a.abs() <= 3200000 &&
            b.abs() <= 200000) {
          parsed.add(ParsedLoPair(westing: b, southing: a));
          i++;
        }
      }
    }

    return parsed;
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
