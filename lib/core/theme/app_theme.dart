import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';

/// Builds light/dark [ThemeData] from the user's appearance settings:
/// accent seed or Material You dynamic colors, AMOLED true black, corner
/// radius, density and font scale.
class AppTheme {
  static ThemeData build(
    AppearanceSettings a,
    Brightness brightness, {
    ColorScheme? dynamicScheme,
  }) {
    var scheme = (a.dynamicColor && dynamicScheme != null)
        ? dynamicScheme
        : ColorScheme.fromSeed(
            seedColor: Color(a.accent),
            brightness: brightness,
          );
    final dark = brightness == Brightness.dark;
    if (dark && a.amoled) {
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFF111111),
        surfaceContainerHigh: const Color(0xFF161616),
        surfaceContainerHighest: const Color(0xFF1C1C1C),
      );
    }
    final r = BorderRadius.circular(a.cornerRadius);
    final density = a.density == 'compact'
        ? VisualDensity.compact
        : VisualDensity.standard;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      visualDensity: density,
      scaffoldBackgroundColor: dark && a.amoled ? Colors.black : null,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: r,
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: r),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: r),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: r),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(a.cornerRadius + 4),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(a.cornerRadius + 4),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark && a.amoled ? Colors.black : null,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: r),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(a.cornerRadius),
        ),
      ),
    );
  }

  static ThemeMode mode(String m) => switch (m) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  /// Wraps [builder] with Material You dynamic colors when available.
  static Widget withDynamic(
    bool enabled,
    Widget Function(ColorScheme? light, ColorScheme? dark) builder,
  ) {
    if (!enabled) return builder(null, null);
    return DynamicColorBuilder(
      builder: (light, dark) =>
          builder(light?.harmonized(), dark?.harmonized()),
    );
  }
}

/// Preset accent colors shown in the picker.
const accentPresets = <int>[
  0xFF3B82F6, // blue
  0xFF10B981, // emerald
  0xFF8B5CF6, // violet
  0xFFEF4444, // red
  0xFFF59E0B, // amber
  0xFFEC4899, // pink
  0xFF06B6D4, // cyan
  0xFF64748B, // slate
];
