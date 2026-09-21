import 'package:flutter/material.dart';

/// Pathfinder design tokens — forest / sand-gold system.
abstract final class PfColors {
  // Brand
  static const forest = Color(0xFF0F3D2E);
  static const forestDeep = Color(0xFF0A2E22);
  static const forestMid = Color(0xFF1A5C45);
  static const sandGold = Color(0xFFC6A75E);
  static const sandGoldDeep = Color(0xFFA88B3F);
  static const sandGoldSoft = Color(0xFFE8D9A8);

  // Neutrals (warm-tinted for outdoor calm)
  static const ivory = Color(0xFFF7F4EE);
  static const sand = Color(0xFFEDE6D9);
  static const mist = Color(0xFFD9D2C5);
  static const stone = Color(0xFF8A8478);
  static const charcoal = Color(0xFF2C2A26);
  static const ink = Color(0xFF1A1916);

  // Semantic / tool accents
  static const sky = Color(0xFF3D6B7A); // Area Calculator
  static const success = Color(0xFF2E7D4F);
  static const warning = Color(0xFFB8860B);
  static const danger = Color(0xFFA33B2B);

  // Surfaces
  static const surfaceLight = Color(0xFFFBF9F5);
  static const surfaceDark = Color(0xFF121A16);
  static const cardDark = Color(0xFF1A2620);
}

abstract final class PfSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;
  static const double section = 28;
}

abstract final class PfRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;

  static final BorderRadius smAll = BorderRadius.circular(sm);
  static final BorderRadius mdAll = BorderRadius.circular(md);
  static final BorderRadius lgAll = BorderRadius.circular(lg);
  static final BorderRadius xlAll = BorderRadius.circular(xl);
}

abstract final class PfElevation {
  static List<BoxShadow> card(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.35 : 0.06),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.2 : 0.03),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  static List<BoxShadow> soft(Brightness brightness) => [
        BoxShadow(
          color: Colors.black.withValues(
              alpha: brightness == Brightness.dark ? 0.28 : 0.04),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];
}

abstract final class PfTap {
  /// Outdoor-friendly minimum control height.
  static const double min = 48;
  static const Size button = Size.fromHeight(min);
}
