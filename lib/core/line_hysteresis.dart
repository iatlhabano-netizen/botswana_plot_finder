/// ON LINE / LEFT / RIGHT Schmitt-trigger hysteresis.
///
/// Enter ON LINE at ~0.85×corridor; leave only past ~1.12×corridor.
/// Optional [confirmSamples] delays side flips / state changes.
enum LineSide { onLine, left, right }

class LineHysteresis {
  LineSide state = LineSide.onLine;
  LineSide? _pending;
  int _pendingCount = 0;

  final double enterFactor;
  final double exitFactor;
  final int confirmSamples;

  LineHysteresis({
    this.enterFactor = 0.85,
    this.exitFactor = 1.12,
    this.confirmSamples = 2,
  });

  void reset() {
    state = LineSide.onLine;
    _pending = null;
    _pendingCount = 0;
  }

  /// Feed signed XTE (+RIGHT / −LEFT) and corridor half-width (m).
  LineSide update(double xteM, double corridorM) {
    final abs = xteM.abs();
    final enter = corridorM * enterFactor;
    final exit = corridorM * exitFactor;

    late LineSide raw;
    if (state == LineSide.onLine) {
      if (abs <= exit) {
        raw = LineSide.onLine;
      } else {
        raw = xteM > 0 ? LineSide.right : LineSide.left;
      }
    } else if (abs <= enter) {
      raw = LineSide.onLine;
    } else if (state == LineSide.left) {
      raw = xteM > exit ? LineSide.right : LineSide.left;
    } else {
      raw = xteM < -exit ? LineSide.left : LineSide.right;
    }

    if (raw == state) {
      _pending = null;
      _pendingCount = 0;
    } else if (raw == _pending) {
      _pendingCount++;
      if (_pendingCount >= confirmSamples) {
        state = raw;
        _pending = null;
        _pendingCount = 0;
      }
    } else {
      _pending = raw;
      _pendingCount = 1;
    }
    return state;
  }

  /// Boolean ON-LINE Schmitt used by Qwen (enter/leave thresholds).
  static bool schmittOnLine(bool? wasOn, double absXt, double inThr, double outThr) {
    if (wasOn == null) return absXt <= inThr;
    if (wasOn) return absXt <= outThr;
    return absXt <= inThr;
  }
}
