import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/core_bridge.dart';
import '../models/models.dart';
import 'core_provider.dart';
import 'env.dart';
import 'settings_provider.dart';

class ImportResult {
  const ImportResult({
    this.profileId,
    this.added = 0,
    this.removed = 0,
    this.total = 0,
    this.warnings = const [],
    this.error,
  });
  final String? profileId;
  final int added;
  final int removed;
  final int total;
  final List<String> warnings;
  final String? error;
  bool get ok => error == null;
}

String newId(String prefix) =>
    '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

class ProfilesNotifier extends AsyncNotifier<List<Profile>> {
  @override
  Future<List<Profile>> build() => ref.read(envProvider).repo.profiles();

  Future<void> reload() async {
    state = AsyncData(await ref.read(envProvider).repo.profiles());
  }

  Profile? byId(String id) => state.value?.where((p) => p.id == id).firstOrNull;

  /// Imports pasted/file content (URI list, base64, Clash/sing-box/Xray JSON, .ovpn, wg-quick).
  Future<ImportResult> importText(
    String content, {
    String? name,
    String? intoProfile,
  }) async {
    final env = ref.read(envProvider);
    try {
      final parsed = await env.core.parseContent(content);
      final id = intoProfile ?? newId('p');
      final existing = intoProfile == null ? null : byId(intoProfile);
      await env.repo.saveProfile(
        existing ??
            Profile(
              id: id,
              name: (name == null || name.isEmpty)
                  ? _autoName(parsed.nodes)
                  : name,
              updatedAt: DateTime.now(),
            ),
      );
      final r = await env.repo.importNodes(
        id,
        parsed.nodes,
        replace: intoProfile == null,
      );
      await _adoptActive(id);
      await reload();
      return ImportResult(
        profileId: id,
        added: r.added,
        removed: r.removed,
        total: r.total,
        warnings: parsed.warnings,
      );
    } on CoreException catch (e) {
      return ImportResult(error: e.message);
    } catch (e) {
      return ImportResult(error: '$e');
    }
  }

  String _autoName(List<Map<String, dynamic>> nodes) => nodes.length == 1
      ? (nodes.first['name'] as String? ?? 'Imported')
      : 'Imported (${nodes.length})';

  Future<ImportResult> addSubscription(
    String url, {
    String? name,
    String ua = '',
  }) async {
    final id = newId('p');
    final env = ref.read(envProvider);
    await env.repo.saveProfile(
      Profile(
        id: id,
        name: (name == null || name.isEmpty)
            ? Uri.tryParse(url)?.host ?? 'Subscription'
            : name,
        url: url,
        userAgent: ua,
      ),
    );
    final r = await refresh(id);
    if (!r.ok) {
      // keep the profile so the user can retry, but surface the error
      await reload();
    }
    return r;
  }

  Future<ImportResult> refresh(String id) async {
    final env = ref.read(envProvider);
    final p =
        byId(id) ?? (await env.repo.profiles()).firstWhere((e) => e.id == id);
    if (!p.isRemote) return const ImportResult(error: 'not a remote profile');
    final connected = ref.read(coreControllerProvider).isConnected;
    try {
      final j = await env.core.fetchSubscription(
        p.url!,
        ua: p.userAgent,
        viaProxy: connected,
      );
      final nodes = (j['nodes'] as List)
          .cast<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      final ui = (j['userinfo'] as Map?)?.cast<String, dynamic>();
      final r = await env.repo.importNodes(id, nodes);
      var updated = p.copyWith(
        updatedAt: DateTime.now(),
        lastError: '',
        failCount: 0,
        upload: (ui?['upload'] as int?) ?? p.upload,
        download: (ui?['download'] as int?) ?? p.download,
        total: (ui?['total'] as int?) ?? p.total,
        expire: (ui?['expire'] as int?) ?? p.expire,
      );
      final title = (j['title'] as String?) ?? '';
      if (title.isNotEmpty &&
          (p.name.isEmpty || p.name == Uri.tryParse(p.url!)?.host))
        updated = updated.copyWith(name: title);
      final hours = (j['update_interval_hours'] as int?) ?? 0;
      if (hours > 0) updated = updated.copyWith(intervalHours: hours);
      await env.repo.saveProfile(updated);
      await _adoptActive(id);
      await reload();
      return ImportResult(
        profileId: id,
        added: r.added,
        removed: r.removed,
        total: r.total,
        warnings: ((j['warnings'] as List?) ?? const []).cast<String>(),
      );
    } on CoreException catch (e) {
      await env.repo.saveProfile(
        p.copyWith(lastError: e.message, failCount: p.failCount + 1),
      );
      await reload();
      return ImportResult(profileId: id, error: e.message);
    }
  }

  /// Refreshes every remote profile whose interval elapsed.
  Future<void> refreshDue() async {
    for (final p in state.value ?? const <Profile>[]) {
      if (p.isDue) await refresh(p.id);
    }
  }

  Future<void> saveProfile(Profile p) async {
    await ref.read(envProvider).repo.saveProfile(p);
    await reload();
  }

  Future<void> delete(String id) async {
    await ref.read(envProvider).repo.deleteProfile(id);
    final s = ref.read(settingsProvider);
    if (s.activeProfileId == id) {
      ref
          .read(settingsProvider.notifier)
          .update((x) => x.copyWith(activeProfileId: null, activeNodeId: null));
    }
    await reload();
  }

  /// If nothing is selected yet, select the first node of [profileId].
  Future<void> _adoptActive(String profileId) async {
    final s = ref.read(settingsProvider);
    if (s.activeNodeId != null &&
        await ref.read(envProvider).repo.nodeRow(s.activeNodeId!) != null)
      return;
    final page = await ref
        .read(envProvider)
        .repo
        .query(profileId: profileId, limit: 1);
    if (page.rows.isNotEmpty) {
      ref
          .read(settingsProvider.notifier)
          .update(
            (x) => x.copyWith(
              activeNodeId: page.rows.first.id,
              activeProfileId: profileId,
            ),
          );
    }
  }
}

final profilesProvider = AsyncNotifierProvider<ProfilesNotifier, List<Profile>>(
  ProfilesNotifier.new,
);

/// Keeps subscriptions fresh: at startup and every 30 minutes.
final subscriptionSchedulerProvider = Provider<void>((ref) {
  Future<void> tick() async {
    try {
      await ref.read(profilesProvider.notifier).refreshDue();
    } catch (_) {}
  }

  final first = Timer(const Duration(seconds: 5), tick);
  final periodic = Timer.periodic(const Duration(minutes: 30), (_) => tick());
  ref.onDispose(() {
    first.cancel();
    periodic.cancel();
  });
});
