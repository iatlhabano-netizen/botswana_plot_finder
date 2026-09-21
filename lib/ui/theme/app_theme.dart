import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'typography.dart';

/// Material 3 ThemeData seeded from Pathfinder brand tokens.
abstract final class AppTheme {
  static ColorScheme _lightScheme() {
    final seeded = ColorScheme.fromSeed(
      seedColor: PfColors.forest,
      brightness: Brightness.light,
    );
    return seeded.copyWith(
      primary: PfColors.forest,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFD5E8DE),
      onPrimaryContainer: PfColors.forestDeep,
      secondary: PfColors.sandGold,
      onSecondary: PfColors.ink,
      secondaryContainer: PfColors.sandGoldSoft,
      onSecondaryContainer: PfColors.forestDeep,
      tertiary: PfColors.sky,
      onTertiary: Colors.white,
      tertiaryContainer: const Color(0xFFD5E4EA),
      onTertiaryContainer: const Color(0xFF1A3340),
      surface: PfColors.surfaceLight,
      onSurface: PfColors.ink,
      onSurfaceVariant: PfColors.stone,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: PfColors.ivory,
      surfaceContainer: PfColors.sand,
      surfaceContainerHigh: PfColors.mist,
      outline: PfColors.mist,
      outlineVariant: const Color(0xFFE2DCCF),
      error: PfColors.danger,
    );
  }

  static ColorScheme _darkScheme() {
    final seeded = ColorScheme.fromSeed(
      seedColor: PfColors.forest,
      brightness: Brightness.dark,
    );
    return seeded.copyWith(
      primary: const Color(0xFF8FCBB0),
      onPrimary: PfColors.forestDeep,
      primaryContainer: PfColors.forestMid,
      onPrimaryContainer: const Color(0xFFD5E8DE),
      secondary: PfColors.sandGoldSoft,
      onSecondary: PfColors.ink,
      secondaryContainer: PfColors.sandGoldDeep,
      onSecondaryContainer: PfColors.ivory,
      tertiary: const Color(0xFF9BBDC9),
      onTertiary: const Color(0xFF0E2430),
      surface: PfColors.surfaceDark,
      onSurface: PfColors.ivory,
      onSurfaceVariant: const Color(0xFFB8B2A6),
      surfaceContainerLowest: const Color(0xFF0C1210),
      surfaceContainerLow: PfColors.cardDark,
      surfaceContainer: const Color(0xFF223029),
      surfaceContainerHigh: const Color(0xFF2A3A32),
      outline: const Color(0xFF4A564F),
      outlineVariant: const Color(0xFF2F3B35),
      error: const Color(0xFFE08A7A),
    );
  }

  static ThemeData light() => _build(_lightScheme(), Brightness.light);
  static ThemeData dark() => _build(_darkScheme(), Brightness.dark);

  static ThemeData _build(ColorScheme cs, Brightness brightness) {
    final text = PfTypography.textTheme(cs);
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? PfColors.forestDeep : PfColors.forest,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 1,
        titleTextStyle: text.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: Colors.white, size: 24),
        actionsIconTheme: const IconThemeData(color: Colors.white, size: 24),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: isDark ? PfColors.cardDark : Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: PfRadius.lgAll,
          side: BorderSide(
            color: cs.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.8),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: PfTap.button,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: PfRadius.mdAll),
          textStyle: text.labelLarge,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: PfTap.button,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: PfRadius.mdAll),
          side: BorderSide(color: cs.outline),
          textStyle: text.labelLarge,
          foregroundColor: cs.primary,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: text.labelLarge,
          foregroundColor: cs.primary,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: PfColors.sandGold,
        foregroundColor: PfColors.ink,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: PfRadius.lgAll),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? cs.surfaceContainerLow
            : PfColors.ivory.withValues(alpha: 0.7),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: PfRadius.mdAll),
        enabledBorder: OutlineInputBorder(
          borderRadius: PfRadius.mdAll,
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: PfRadius.mdAll,
          borderSide: const BorderSide(color: PfColors.forest, width: 1.6),
        ),
        labelStyle: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: PfRadius.mdAll),
        minVerticalPadding: 10,
        iconColor: cs.primary,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: PfRadius.smAll),
        side: BorderSide(color: cs.outlineVariant),
        labelStyle: text.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: PfRadius.mdAll),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: PfRadius.xlAll),
        backgroundColor: isDark ? PfColors.cardDark : Colors.white,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? PfColors.cardDark : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        showDragHandle: true,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: isDark ? cs.primary : PfColors.forest,
      ),
    );
  }
}
