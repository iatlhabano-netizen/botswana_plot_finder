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

  group('OcrService cleanup / zone / paste parse', () {
    test('cleanupOcrDigitConfusions fixes l/I→1 and S→5 in numbers', () {
      final cleaned = OcrService.cleanupOcrDigitConfusions('Y -74l283 X 2609I49');
      expect(cleaned.contains('741283'), isTrue);
      expect(cleaned.contains('2609149'), isTrue);
      expect(OcrService.cleanupOcrDigitConfusions('2551S4'), '255154');
    });

    test('detectSuggestedZone from LO 25 / System LO25 / LO. 27 headers', () {
      expect(OcrService.detectSuggestedZone('Plot NN-48   LO 25'), 25);
      expect(OcrService.detectSuggestedZone('System LO25 Cape'), 25);
      expect(OcrService.detectSuggestedZone('CO-ORDINATES System LO. 27'), 27);
      expect(OcrService.detectSuggestedZone('CO-ORDINATES System LO. 27\u00b0'), 27);
      expect(OcrService.detectSuggestedZone('no zone here'), isNull);
    });

    test('parseRecognizedText suggests zone and keeps NN-48 6 corners', () {
      const text = '''
        DEPARTMENT OF LANDS
        Plot NN-48   LO 25
        Beacon     Y                X
        A  - 255 124.38   -7 604 978.00
        B  - 254 977.64   -7 698 730.00
        C  - 249 093.48   -7 698 467.50
        D  - 249 103.50   -7 698 493.00
        E  - 249 102.66   -7 604 846.50
        F  - 255 109.17   -7 604 973.00
      ''';
      final result = OcrService.parseRecognizedText(text);
      expect(result.pairs.length, 6);
      expect(result.suggestedZone, 25);
    });


    test('normalizes European comma decimals (LO27 Land Board)', () {
      expect(
        OcrService.normalizeLoNumberText('+103 208,35   + 2 702 523,47'),
        '+103208.35   +2702523.47',
      );
      expect(
        OcrService.normalizeLoNumberText('+102825,87'),
        '+102825.87',
      );
    });

    test('parses Bokaa LO27 beacon table with 4 corners + zone 27', () {
      // Photo-of-monitor PDF: space thousands, comma decimals, leading +.
      final text = [
        'CO-ORDINATES System LO. 27\u00b0',
        'Beacon     Y                X',
        '+ 0,00            + 0,00',
        'A  +103 208,35   + 2 702 523,47',
        'B  +102 825,87   + 2 702 748,44',
        'C  +103 190,55   + 2 702 993,47',
        'D  +103 510,96   + 2 702 809,52',
        'BAKGATLA TRIBAL TERRITORY',
        '16.1541 hectares',
        '6911 BOKAA',
      ].join('\n');
      final result = OcrService.parseRecognizedText(text);
      expect(result.pairs.length, 4);
      expect(result.suggestedZone, 27);
      expect(result.pairs[0].westing, closeTo(103208.35, 0.01));
      expect(result.pairs[0].southing, closeTo(2702523.47, 0.01));
      expect(result.pairs[1].westing, closeTo(102825.87, 0.01));
      expect(result.pairs[1].southing, closeTo(2702748.44, 0.01));
      expect(result.pairs[2].westing, closeTo(103190.55, 0.01));
      expect(result.pairs[2].southing, closeTo(2702993.47, 0.01));
      expect(result.pairs[3].westing, closeTo(103510.96, 0.01));
      expect(result.pairs[3].southing, closeTo(2702809.52, 0.01));
      expect(result.declaredHectares, closeTo(16.1541, 0.001));
    });

    test('LO27 table keeps all 4 corners even if one Y/X label matches', () {
      // Regression: a single Y…X hit used to short-circuit and drop B/C/D.
      final text = [
        'CO-ORDINATES System LO. 27\u00b0',
        'Y = +103 208,35  X = + 2 702 523,47',
        'B  +102 825,87   + 2 702 748,44',
        'C  +103 190,55   + 2 702 993,47',
        'D  +103 510,96   + 2 702 809,52',
      ].join('\n');
      final result = OcrService.parseRecognizedText(text);
      expect(result.pairs.length, 4);
      expect(result.suggestedZone, 27);
      expect(result.pairs[0].westing, closeTo(103208.35, 0.01));
      expect(result.pairs[3].westing, closeTo(103510.96, 0.01));
    });

    test('LO27 rows with inline Y/X tags after beacon letters', () {
      final text = [
        'System LO. 27\u00b0',
        'A Y +103 208,35 X + 2 702 523,47',
        'B Y +102 825,87 X + 2 702 748,44',
        'C Y +103 190,55 X + 2 702 993,47',
        'D Y +103 510,96 X + 2 702 809,52',
      ].join('\n');
      final pairs = OcrService.parseLoCoordinates(text);
      expect(pairs.length, 4);
      expect(pairs[2].southing, closeTo(2702993.47, 0.01));
    });

    test('negative X pairs survive parse for converter normalize', () {
      final result = OcrService.parseRecognizedText(
        'Y = -74283  X = -2609149\nY = -74593  X = -2609153',
      );
      expect(result.pairs.length, 2);
      expect(result.pairs[0].southing, -2609149);
      expect(result.pairs[1].southing, -2609153);
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
