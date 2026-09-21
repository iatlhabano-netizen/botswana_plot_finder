import 'package:flutter_test/flutter_test.dart';
import 'package:botswana_plot_finder/services/ocr_service.dart';

void main() {
  group('OcrService.parseLoCoordinates', () {
    test('parses Y/X labeled pairs', () {
      const text = '''
        Corner 1  Y = -74283  X = 2609149
        Corner 2  Y=-74593, X=2609153
        Y : -74589 ; X : 2609473
        Y -74279 X 2609469
      ''';
      final pairs = OcrService.parseLoCoordinates(text);
      expect(pairs.length, greaterThanOrEqualTo(4));
      expect(pairs[0].westing, -74283);
      expect(pairs[0].southing, 2609149);
    });

    test('parses X/Y labeled order', () {
      const text = 'X 2609149 Y -74283';
      final pairs = OcrService.parseLoCoordinates(text);
      expect(pairs, isNotEmpty);
      expect(pairs.first.westing, -74283);
      expect(pairs.first.southing, 2609149);
    });

    test('parses bare number pairs with Lo heuristics', () {
      const text = '-74283 2609149 -74593 2609153';
      final pairs = OcrService.parseLoCoordinates(text);
      expect(pairs.length, 2);
      expect(pairs[0].westing, -74283);
      expect(pairs[0].southing, 2609149);
    });

    test('OCR O→0 cleanup then parse', () {
      // Capital O mistaken for zero before a digit
      final result = OcrService.parseRecognizedText(
        'Y -O74283 X 26O9149',
      );
      expect(result.pairs, isNotEmpty);
      expect(result.pairs.first.westing, -74283);
      expect(result.pairs.first.southing, 2609149);
    });

    test('empty / garbage text returns no pairs (null-guard path)', () {
      expect(OcrService.parseLoCoordinates(''), isEmpty);
      expect(OcrService.parseLoCoordinates('no coords here'), isEmpty);
      expect(OcrService.parseLoCoordinates('123 456'), isEmpty);
    });

    test('extracts declared hectares via parseRecognizedText', () {
      final result = OcrService.parseRecognizedText(
        'Y -74283 X 2609149\nArea (9.6HA)',
      );
      expect(result.declaredHectares, 9.6);
    });
  });

  test('parses decimal Y/X from certificate-style text', () {
      const text = 'Y = -74283.25  X = 2609149.50';
      final pairs = OcrService.parseLoCoordinates(text);
      expect(pairs, isNotEmpty);
      expect(pairs.first.westing, closeTo(-74283.25, 1e-9));
      expect(pairs.first.southing, closeTo(2609149.50, 1e-9));
    });

  group('OcrException', () {
    test('toString is the user message', () {
      const e = OcrException('Image file is missing or empty after save. Please try again.');
      expect(e.toString(), contains('missing or empty'));
      expect(e.message, isNotEmpty);
    });
  });
}
