import 'psiphon_manager.dart';

/// Keeps the Psiphon core out of the app's own tunnel. With TUN on, the
/// core's connections to Psiphon servers would be captured and fed back into
/// the Psiphon profile, which is not up yet: a loop. Matching the process and
/// sending it DIRECT breaks the loop. Needs `find-process-mode: always`.
class PsiphonBypass {
  const PsiphonBypass._();

  static String get rule => 'PROCESS-NAME,${PsiphonBinary.fileName},DIRECT';

  static Map<String, dynamic> apply(Map<String, dynamic> config) {
    final rules = [for (final r in (config['rules'] as List? ?? const [])) r];
    if (rules.contains(rule)) return config;
    return {
      ...config,
      'rules': [rule, ...rules],
    };
  }
}
