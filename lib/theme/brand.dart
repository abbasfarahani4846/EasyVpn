import 'package:flutter/material.dart';

import '../core/models/models.dart';

/// EasyVPN brand tokens for the simple (one-button) experience. Deliberately
/// not Material defaults: deep night background, state-driven glow colors,
/// glass panels and large rounded geometry.
class Brand {
  static const night = Color(0xFF070B16);
  static const night2 = Color(0xFF0E1426);
  static const panel = Color(0x1AFFFFFF); // glass
  static const panelBorder = Color(0x26FFFFFF);
  static const text = Color(0xFFF4F7FF);
  static const textDim = Color(0x99F4F7FF);

  static const off = Color(0xFF6B7AA6);
  static const busy = Color(0xFFF5A524);
  static const on = Color(0xFF16E0A8);
  static const on2 = Color(0xFF0EA5E9);
  static const bad = Color(0xFFFF5C7A);

  static const radius = 28.0;

  /// Primary glow color for a connection status.
  static Color forStatus(CoreStatus s) => switch (s) {
    CoreStatus.connected => on,
    CoreStatus.connecting || CoreStatus.disconnecting => busy,
    CoreStatus.error => bad,
    _ => off,
  };

  static LinearGradient orbGradient(CoreStatus s) => switch (s) {
    CoreStatus.connected => const LinearGradient(
      colors: [on, on2],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    CoreStatus.connecting || CoreStatus.disconnecting => const LinearGradient(
      colors: [busy, Color(0xFFFF7A45)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    CoreStatus.error => const LinearGradient(
      colors: [bad, Color(0xFFB0356A)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    _ => const LinearGradient(
      colors: [Color(0xFF2A3354), Color(0xFF1A2038)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  };

  static BoxDecoration glass({double radius = Brand.radius}) => BoxDecoration(
    color: panel,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: panelBorder),
  );

  /// Theme used inside the simple experience (always dark, brand colors).
  static ThemeData theme(ThemeData base) => glassTheme(base);

  /// The app-wide "liquid glass" theme: night background (painted once by
  /// [GlassBackground]), translucent surfaces with hairline borders, large
  /// radii, teal accent. Used for every page in simple AND advanced layout.
  static ThemeData glassTheme(ThemeData base) {
    final scheme = base.colorScheme.copyWith(
      brightness: Brightness.dark,
      primary: on,
      onPrimary: night,
      secondary: on2,
      onSecondary: night,
      surface: night2,
      onSurface: text,
      onSurfaceVariant: textDim,
      surfaceContainerLowest: const Color(0xFF0B1020),
      surfaceContainerLow: const Color(0xFF111831),
      surfaceContainer: const Color(0xFF141C38),
      surfaceContainerHigh: const Color(0xFF18213F),
      surfaceContainerHighest: const Color(0xFF1C2647),
      outline: const Color(0x40F4F7FF),
      outlineVariant: panelBorder,
      error: bad,
      primaryContainer: on.withValues(alpha: 0.18),
      onPrimaryContainer: text,
      secondaryContainer: on2.withValues(alpha: 0.18),
      onSecondaryContainer: text,
      errorContainer: bad.withValues(alpha: 0.18),
      onErrorContainer: text,
    );
    final r16 = BorderRadius.circular(16);
    final r22 = BorderRadius.circular(22);
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: night2,
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      iconTheme: const IconThemeData(color: text),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: text,
        ),
      ),
      cardTheme: CardThemeData(
        color: panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: r22,
          side: const BorderSide(color: panelBorder),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: textDim,
        textColor: text,
        selectedColor: on,
      ),
      dividerTheme: const DividerThemeData(color: panelBorder, space: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: night2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: r22,
          side: const BorderSide(color: panelBorder),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: night2,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: textDim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: night2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: r16,
          side: const BorderSide(color: panelBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        border: OutlineInputBorder(
          borderRadius: r16,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: r16,
          borderSide: const BorderSide(color: panelBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: r16,
          borderSide: const BorderSide(color: on),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: on,
          foregroundColor: night,
          shape: RoundedRectangleBorder(borderRadius: r16),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: const BorderSide(color: panelBorder),
          shape: RoundedRectangleBorder(borderRadius: r16),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: night2.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        indicatorColor: on.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? on : textDim,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: s.contains(WidgetState.selected) ? text : textDim,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: on.withValues(alpha: 0.18),
        selectedIconTheme: const IconThemeData(color: on),
        unselectedIconTheme: const IconThemeData(color: textDim),
        selectedLabelTextStyle: const TextStyle(
          color: text,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: const TextStyle(color: textDim, fontSize: 12),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? night : textDim,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? on : panel,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? on.withValues(alpha: 0.2)
                : Colors.transparent,
          ),
          foregroundColor: const WidgetStatePropertyAll(text),
          side: const WidgetStatePropertyAll(BorderSide(color: panelBorder)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: panel,
        selectedColor: on.withValues(alpha: 0.22),
        checkmarkColor: on,
        labelStyle: const TextStyle(color: text),
        side: const BorderSide(color: panelBorder),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1C2647),
        contentTextStyle: const TextStyle(color: text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: r16),
      ),
    );
  }
}

/// Paints the brand night background behind every route, once, so glass
/// surfaces (translucent cards, bars) look the same on every page.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0C1330), Brand.night, Color(0xFF071A1F)],
        stops: [0, 0.55, 1],
      ),
    ),
    child: child,
  );
}

/// Extracts a leading flag emoji (two regional-indicator symbols) from a name.
String? leadingFlag(String name) {
  final runes = name.runes.toList();
  for (var i = 0; i + 1 < runes.length && i < 6; i++) {
    bool ri(int r) => r >= 0x1F1E6 && r <= 0x1F1FF;
    if (ri(runes[i]) && ri(runes[i + 1])) {
      return String.fromCharCodes([runes[i], runes[i + 1]]);
    }
  }
  return null;
}

/// Name without decorative leading flag/emoji noise.
String cleanName(String name) {
  final f = leadingFlag(name);
  var n = f == null ? name : name.replaceFirst(f, '');
  return n.trim().isEmpty ? name : n.trim();
}

/// 0..4 signal bars from latency (ms); -1 / 0 = unknown.
int signalBars(int ms) {
  if (ms <= 0) return 0;
  if (ms < 150) return 4;
  if (ms < 300) return 3;
  if (ms < 600) return 2;
  return 1;
}

class SignalBars extends StatelessWidget {
  const SignalBars(this.ms, {super.key, this.color});
  final int ms;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final n = signalBars(ms);
    final c = color ?? (n >= 3 ? Brand.on : (n == 2 ? Brand.busy : Brand.bad));
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            width: 4,
            height: 6.0 + i * 4,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: i < n ? c : Brand.textDim.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}
