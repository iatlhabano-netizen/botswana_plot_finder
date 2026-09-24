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

    test('parses decimal Y/X from certificate-style text', () {
      const text = 'Y = -74283.25  X = 2609149.50';
      final pairs = OcrService.parseLoCoordinates(text);
      expect(pairs, isNotEmpty);
      expect(pairs.first.westing, closeTo(-74283.25, 1e-9));
      expect(pairs.first.southing, closeTo(2609149.50, 1e-9));
    });

    test('normalizes spaced thousands and spaced signs', () {
      expect(
        OcrService.normalizeLoNumberText('- 255 124.38   -7 604 978.00'),
        '-255124.38   -7604978.00',
      );
      expect(
        OcrService.normalizeLoNumberText('255,124.38'),
        '255124.38',
      );
    });

    test('parses LO25 Land Board beacon table (NN-48 fixture)', () {
      // Mimics a monitor photo OCR of a cadastral beacon table: header once,
      // then bare Y/X pairs with spaced thousands and spaced minus signs.
      const text = '''
        DEPARTMENT OF LANDS
        Plot NN-48   LO 25
        Co-ordinates of Beacons
        Beacon     Y                X
        A  - 255 124.38   -7 604 978.00
        B  - 254 977.64   -7 698 730.00
        C  - 249 093.48   -7 698 467.50
        D  - 249 103.50   -7 698 493.00
        E  - 249 102.66   -7 604 846.50
        F  - 255 109.17   -7 604 973.00
        Constants  0.00   0.00
        A to B   1.20.43   245.12
      ''';
      final pairs = OcrService.parseLoCoordinates(text);
      expect(pairs.length, 6);
      expect(pairs[0].westing, closeTo(-255124.38, 0.01));
      expect(pairs[0].southing, closeTo(-7604978.00, 0.01));
      expect(pairs[1].westing, closeTo(-254977.64, 0.01));
      expect(pairs[1].southing, closeTo(-7698730.00, 0.01));
      expect(pairs[2].westing, closeTo(-249093.48, 0.01));
      expect(pairs[2].southing, closeTo(-7698467.50, 0.01));
      expect(pairs[3].westing, closeTo(-249103.50, 0.01));
      expect(pairs[3].southing, closeTo(-7698493.00, 0.01));
      expect(pairs[4].westing, closeTo(-249102.66, 0.01));
      expect(pairs[4].southing, closeTo(-7604846.50, 0.01));
      expect(pairs[5].westing, closeTo(-255109.17, 0.01));
      expect(pairs[5].southing, closeTo(-7604973.00, 0.01));
    });

    test('LO25 beacon table with OCR garble O→0 still yields corners', () {
      // O→0 already applied in parseRecognizedText (O before a digit).
      final result = OcrService.parseRecognizedText('''
        LO 25  Co-ordinates
        A  - 255 124.38   -7 6O4 978.00
        B  - 254 977.64   -7 6O4 973.00
      ''');
      expect(result.pairs.length, 2);
      expect(result.pairs[0].westing, closeTo(-255124.38, 0.01));
      expect(result.pairs[0].southing, closeTo(-7604978.00, 0.01));
      expect(result.pairs[1].westing, closeTo(-254977.64, 0.01));
      expect(result.pairs[1].southing, closeTo(-7604973.00, 0.01));
    });

    test('accepts LO25-magnitude bare pairs outside old 3.2e6 southing cap', () {
      const text = '-255124.38 -7604978.00 -254977.64 -7698730.00';
      final pairs = OcrService.parseLoCoordinates(text);
      expect(pairs.length, 2);
      expect(pairs[0].westing, closeTo(-255124.38, 0.01));
      expect(pairs[0].southing, closeTo(-7604978.00, 0.01));
    });
  });

  group('OcrException', () {
    test('toString is the user message', () {
      const e = OcrException(
          'Image file is missing or empty after save. Please try again.');
      expect(e.toString(), contains('missing or empty'));
      expect(e.message, isNotEmpty);
    });
  });
}
