import 'default_profile_config.dart';
import 'share_link_parser.dart';

/// Panels answer an unknown User-Agent with base64 share links, not a Clash config.
class SubscriptionConverter {
  const SubscriptionConverter._();

  static final _clashKeys = RegExp(
    r'^(proxies|proxy-providers|proxy-groups|rules|mixed-port|port|socks-port)\s*:',
    multiLine: true,
  );

  static bool looksLikeClash(String text) => _clashKeys.hasMatch(text);

  static String? toClashYaml(String text) {
    if (looksLikeClash(text)) return null;
    final parsed = ShareLinkParser.parse(text);
    if (parsed.proxies.isEmpty) return null;
    return DefaultProfileConfig.build(parsed.proxies);
  }
}
