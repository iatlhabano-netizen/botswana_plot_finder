import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'theme/tokens.dart';

export 'theme/app_theme.dart';
export 'theme/tokens.dart';
export 'theme/typography.dart';

/// Back-compat facade used across screens.
/// Brand palette: deep forest + sand gold (logo-aligned).
class PathfinderTheme {
  static const seed = PfColors.forest;
  static const accent = PfColors.sandGold;
  static const sky = PfColors.sky;

  /// Legacy alias kept for any older references.
  static const forest = PfColors.forest;
  static const sandGold = PfColors.sandGold;

  static ThemeData light() => AppTheme.light();
  static ThemeData dark() => AppTheme.dark();
}
