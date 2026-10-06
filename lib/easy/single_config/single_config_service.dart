import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_vpn/common/common.dart';
import 'package:easy_vpn/models/models.dart';
import 'package:easy_vpn/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'default_profile_config.dart';
import 'share_link_parser.dart';

class SingleConfigResult {
  final int added;
  final int skipped;
  final List<String> errors;

  const SingleConfigResult({
    required this.added,
    required this.skipped,
    required this.errors,
  });
}

/// Adds pasted configs to the "Default" profile, creating it on first use, so
/// a single link never needs a profile of its own.
class SingleConfigService {
  const SingleConfigService._();

  static Profile? findByLabel(List<Profile> profiles, String label) {
    for (final profile in profiles) {
      if (profile.url.isEmpty && profile.label == label) return profile;
    }
    return null;
  }

  static Profile? findDefault(List<Profile> profiles) =>
      findByLabel(profiles, DefaultProfileConfig.label);

  static Future<SingleConfigResult> add(WidgetRef ref, String text) async {
    return addParsed(ref, ShareLinkParser.parse(text));
  }

  /// [label] picks the profile the configs go into (created on first use);
  /// [select] makes it the active profile so one tap on connect is enough.
  static Future<SingleConfigResult> addParsed(
    WidgetRef ref,
    ShareLinkParseResult parsed, {
    String label = DefaultProfileConfig.label,
    bool select = false,
    bool replace = false,
    bool urlTest = true,
  }) async {
    if (parsed.proxies.isEmpty) {
      throw MessageException(
        parsed.errors.isEmpty ? 'No config found' : parsed.errors.join('\n'),
      );
    }

    final core = ref.read(coreHandlerProvider);
    final problems = await core.validateProxies(parsed.proxies);
    final valid = <Map<String, Object?>>[];
    final errors = [...parsed.errors];
    for (var i = 0; i < parsed.proxies.length; i++) {
      final problem = i < problems.length ? problems[i] : '';
      if (problem.isEmpty) {
        valid.add(parsed.proxies[i]);
      } else {
        errors.add('${parsed.proxies[i]['name']}: $problem');
      }
    }
    if (valid.isEmpty) throw MessageException(errors.join('\n'));

    final existing = findByLabel(ref.read(profilesProvider), label);
    var current = <Map<String, Object?>>[];
    if (existing != null) {
      final file = await existing.file;
      if (await file.exists()) {
        current = DefaultProfileConfig.readProxies(await file.readAsString());
      }
    }

    final merged = replace
        ? (proxies: valid, added: valid.length, skipped: 0)
        : DefaultProfileConfig.merge(current, valid);
    if (merged.added > 0 || existing == null) {
      final bytes = Uint8List.fromList(
        utf8.encode(
          DefaultProfileConfig.build(merged.proxies, urlTest: urlTest),
        ),
      );
      final base = existing ?? Profile.normal(label: label);
      final saved = await base.saveFile(
        bytes,
        validate: (path) => core.validateConfig(path),
      );
      final actions = ref.read(profilesActionProvider.notifier);
      if (existing == null) {
        actions.putProfile(saved);
      } else {
        actions.setProfileAndAutoApply(saved);
      }
      if (select) {
        ref.read(currentProfileIdProvider.notifier).value = saved.id;
      }
    }
    return SingleConfigResult(
      added: merged.added,
      skipped: merged.skipped,
      errors: errors,
    );
  }
}
