import 'package:flutter_test/flutter_test.dart';
import 'package:botswana_plot_finder/core/corridor.dart';
import 'package:botswana_plot_finder/core/gps_smoother.dart';
import 'package:botswana_plot_finder/core/guided_path.dart';
import 'package:botswana_plot_finder/core/line_geo.dart';
import 'package:botswana_plot_finder/core/line_hysteresis.dart';
import 'package:botswana_plot_finder/core/line_projector.dart';
import 'package:botswana_plot_finder/core/path_guidance.dart';
import 'package:latlong2/latlong.dart' as ll;

void main() {
  // Eastbound segment near Gaborone-ish.
  final a = const ll.LatLng(-24.0, 25.0);
  final b = const ll.LatLng(-24.0, 25.01); // ~1 km east
  final c = const ll.LatLng(-23.99, 25.01); // then north

  group('XTE sign convention (+ = RIGHT)', () {
    test('eastbound: south = positive (RIGHT)', () {
      final south = const ll.LatLng(-24.001, 25.005);
      final xt = LineGeo.crossTrackM(south, a, b);
      expect(xt, greaterThan(50));
      expect(PathGuidance.crossTrackM(south, a, b), greaterThan(50));
    });

    test('eastbound: north = negative (LEFT)', () {
      final north = const ll.LatLng(-23.999, 25.005);
      final xt = LineGeo.crossTrackM(north, a, b);
      expect(xt, lessThan(-50));
    });

    test('ENU projSeg RIGHT-positive matches geodesic', () {
      final south = const ll.LatLng(-24.001, 25.005);
      final pr = projectSegmentEnu(origin: a, p: south, a: a, b: b);
      expect(pr.lateralM, greaterThan(50));
      expect(pr.interior, isTrue);
    });
  });

  group('along-track / multi-leg', () {
    test('midpoint along ≈ half segment', () {
      final mid = const ll.LatLng(-24.0, 25.005);
      final along = PathGuidance.alongTrackM(mid, a, b);
      final full = LineGeo.distanceM(a, b);
      expect(along, closeTo(full / 2, 30));
    });

    test('projectOntoPath picks second leg interior', () {
      final mid2 = const ll.LatLng(-23.995, 25.01);
      final proj = LineProjector.projectOnce(mid2, [a, b, c]);
      expect(proj, isNotNull);
      expect(proj!.legIndex, 1);
      expect(proj.crossTrackM.abs(), lessThan(5));
      expect(proj.alongPathM, greaterThan(LineGeo.distanceM(a, b) * 0.85));
      expect(proj.remainingM + proj.alongPathM, closeTo(proj.totalM, 1));
    });

    test('switchCost keeps hint leg near bend', () {
      // Just past bend on second leg, but close to vertex b.
      final nearBend = const ll.LatLng(-23.99999, 25.01);
      final stay0 = LineProjector.projectOnce(
        nearBend,
        [a, b, c],
        hintLeg: 0,
        switchCostM: 2.5,
      );
      final stay1 = LineProjector.projectOnce(
        nearBend,
        [a, b, c],
        hintLeg: 1,
        switchCostM: 2.5,
      );
      expect(stay0!.legIndex, 0);
      expect(stay1!.legIndex, 1);
    });

    test('decisive move onto the next leg commits immediately', () {
      final projector = LineProjector()..reset(leg: 0);
      // Clearly on leg 1 (~500 m north of the bend). Waiting out dwell here
      // reports cross-track against the finished east leg — the wrong side.
      final onLeg1 = const ll.LatLng(-23.995, 25.01);
      final r1 = projector.project(onLeg1, [a, b, c]);
      expect(r1!.legIndex, 1);
    });

    test('ambiguous bend still dwells for 2 fixes', () {
      final projector = LineProjector()..reset(leg: 0);
      // 1 m before the bend and 10 m north: leg 0 is still interior, so the
      // switch is not "decisive", but leg 1 is the better score.
      final before = LineGeo.destination(b, (LineGeo.bearingDeg(a, b) + 180) % 360, 1);
      final p = LineGeo.destination(before, 0, 10);
      final r1 = projector.project(p, [a, b, c]);
      expect(r1!.legIndex, 0);
      final r2 = projector.project(p, [a, b, c]);
      expect(r2!.legIndex, 1);
    });

    test('past-end uses metres, not 98% of a long leg', () {
      final len = LineGeo.distanceM(a, b);
      final brg = LineGeo.bearingDeg(a, b);
      final short = LineGeo.destination(a, brg, len - 15);
      final early = LineProjector.projectOnce(short, [a, b]);
      expect(early!.pastEnd, isFalse);
      final beyond = LineGeo.destination(a, brg, len + 20);
      final late = LineProjector.projectOnce(beyond, [a, b]);
      expect(late!.pastEnd, isTrue);
    });
  });

  group('Schmitt / corridor', () {
    test('Schmitt enter 0.85 / exit 1.12', () {
      expect(LineHysteresis.schmittOnLine(null, 1.0, 1.7, 2.24), isTrue);
      expect(LineHysteresis.schmittOnLine(true, 2.0, 1.7, 2.24), isTrue);
      expect(LineHysteresis.schmittOnLine(true, 2.5, 1.7, 2.24), isFalse);
      expect(LineHysteresis.schmittOnLine(false, 1.5, 1.7, 2.24), isTrue);
    });

    test('LineHysteresis confirms side flip', () {
      final h = LineHysteresis(confirmSamples: 2);
      // Leave ON LINE to the right
      expect(h.update(0.2, 2.0), LineSide.onLine);
      h.update(3.0, 2.0); // pending RIGHT
      expect(h.update(3.0, 2.0), LineSide.right);
    });

    test('crossed to the other side is not latched on the old side', () {
      final h = LineHysteresis(confirmSamples: 2);
      expect(h.update(0.2, 2.0), LineSide.onLine);
      h.update(3.0, 2.0);
      expect(h.update(3.0, 2.0), LineSide.right);
      // -2.0 m is left of the line, outside the enter band (1.7 m) but inside
      // the old exit threshold (2.24 m). Must not keep saying RIGHT.
      expect(h.update(-2.0, 2.0), LineSide.right); // first confirm sample
      expect(h.update(-2.0, 2.0), LineSide.left);
    });

    test('corridor vs accuracy', () {
      expect(
        Corridor.halfWidthM(baseTolM: 1.8, accuracyM: 2.0),
        closeTo(1.8, 0.01),
      );
      expect(
        Corridor.halfWidthM(baseTolM: 1.8, accuracyM: 10.0),
        closeTo(6.0, 0.01), // 0.6 * 10
      );
      expect(
        Corridor.halfWidthM(baseTolM: 1.8, accuracyM: 50.0),
        closeTo(12.0, 0.01), // clamped
      );
      expect(
        Corridor.halfWidthM(baseTolM: 0.2, accuracyM: 0),
        closeTo(0.5, 0.01), // floor
      );
    });

    test('corridor polygon non-empty', () {
      final poly = Corridor.polygon([a, b, c], 2.0);
      expect(poly.length, greaterThanOrEqualTo(6));
      // Closed-ish ring: first and last distinct (left[0] vs right[0])
      expect(poly.first.latitude, isNot(closeTo(poly.last.latitude, 1e-9)));
    });

    test('corridor width eases a spike instead of snapping', () {
      final f = CorridorWidthFilter();
      expect(f.update(1.8), closeTo(1.8, 1e-9));
      // One bad accuracy sample wants 12 m. Do not jump there in one fix.
      final stepped = f.update(12);
      expect(stepped, lessThan(4));
      expect(stepped, greaterThan(1.8));
      // Shrinking back is slower than widening.
      final back = f.update(1.8);
      expect(f.width! - back, closeTo(0, 1e-9));
      expect((stepped - back).abs(), closeTo(CorridorWidthFilter.shrinkStepM, 1e-9));
      f.snap(2.5);
      expect(f.width, closeTo(2.5, 1e-9));
    });
  });

  group('smoothing EMA', () {
    test('DualEma blends cross/along', () {
      final e = DualEma();
      final r1 = e.update(10, 100);
      expect(r1.cross, 10);
      final r2 = e.update(0, 200);
      expect(r2.cross, lessThan(10));
      expect(r2.cross, greaterThan(0));
      expect(r2.along, greaterThan(100));
      expect(r2.along, lessThan(200));
    });

    test('GpsSmoother accepts first fix', () {
      final s = GpsSmoother();
      final f = s.update(a, 5, 1000);
      expect(f, isNotNull);
      expect(f!.position.latitude, closeTo(a.latitude, 1e-9));
    });

    test('grace hold does not integrate velocity through a spike', () {
      final s = GpsSmoother();
      var t = 0;
      s.update(a, 5, t);
      var pos = a;
      SmoothedFix? before;
      for (var i = 0; i < 6; i++) {
        t += 1000;
        pos = LineGeo.destination(pos, 90, 6);
        before = s.update(pos, 5, t);
      }
      final spike = LineGeo.destination(pos, 0, 40);
      final held = s.update(spike, 5, t + 1000);
      expect(
        LineGeo.distanceM(held!.position, before!.position),
        lessThan(0.5),
      );
    });

    test('inferred speed is clamped', () {
      final s = GpsSmoother();
      s.update(a, 1, 0);
      final jumped = LineGeo.destination(a, 90, 20);
      final f = s.update(jumped, 1, 50);
      expect(f!.speedMps, lessThanOrEqualTo(GpsSmoother.maxSpeedMps + 1e-6));
    });
  });

  group('GuidedPath + messages', () {
    test('evaluate returns projected + RIGHT XT', () {
      final path = GuidedPath([
        PathVertex(a, label: 'Start'),
        PathVertex(b, label: 'Via 1'),
        PathVertex(c, label: 'End'),
      ]);
      final south = const ll.LatLng(-24.001, 25.005);
      final fix = path.evaluate(south);
      expect(fix.segmentIndex, 0);
      expect(fix.crossTrackM, greaterThan(50));
      expect(fix.projected.latitude, isNotNull);
    });

    test('stayOnLine action copy', () {
      expect(PathGuidance.stayOnLineAction(0.2), contains('corridor'));
      expect(PathGuidance.stayOnLineAction(3), contains('left'));
      expect(PathGuidance.stayOnLineAction(-3), contains('right'));
    });
  });
}
