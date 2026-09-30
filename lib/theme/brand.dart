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
  static ThemeData theme(ThemeData base) => base.copyWith(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: night,
    colorScheme: base.colorScheme.copyWith(
      brightness: Brightness.dark,
      primary: on,
      secondary: on2,
      surface: night2,
      onSurface: text,
      error: bad,
    ),
    textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
    iconTheme: const IconThemeData(color: text),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: panel,
      selectedColor: on.withValues(alpha: 0.22),
      checkmarkColor: on,
      labelStyle: const TextStyle(color: text),
      side: const BorderSide(color: panelBorder),
    ),
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
