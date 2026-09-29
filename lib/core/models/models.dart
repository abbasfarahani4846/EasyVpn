import 'dart:convert';

/// Connection mode chosen by the user (FlClash-style).
enum ConnMode {
  tun('tun'),
  systemProxy('system_proxy'),
  both('both'),
  proxyOnly('proxy_only');

  const ConnMode(this.wire);
  final String wire;

  static ConnMode parse(String? v) => ConnMode.values.firstWhere(
    (m) => m.wire == v,
    orElse: () => ConnMode.proxyOnly,
  );

  bool get usesTun => this == tun || this == both;
  bool get usesSystemProxy => this == systemProxy || this == both;
}

enum CoreStatus {
  unavailable,
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
}

CoreStatus parseStatus(String? s) => switch (s) {
  'connecting' => CoreStatus.connecting,
  'connected' => CoreStatus.connected,
  'disconnecting' => CoreStatus.disconnecting,
  'error' => CoreStatus.error,
  _ => CoreStatus.disconnected,
};

class CoreState {
  const CoreState({
    this.status = CoreStatus.disconnected,
    this.mode = ConnMode.proxyOnly,
    this.detail = '',
  });
  final CoreStatus status;
  final ConnMode mode;
  final String detail;

  bool get isConnected => status == CoreStatus.connected;
  bool get isBusy =>
      status == CoreStatus.connecting || status == CoreStatus.disconnecting;

  CoreState copyWith({CoreStatus? status, ConnMode? mode, String? detail}) =>
      CoreState(
        status: status ?? this.status,
        mode: mode ?? this.mode,
        detail: detail ?? this.detail,
      );
}

class TrafficStats {
  const TrafficStats({
    this.upBps = 0,
    this.downBps = 0,
    this.totalUp = 0,
    this.totalDown = 0,
    this.connections = 0,
  });
  final int upBps;
  final int downBps;
  final int totalUp;
  final int totalDown;
  final int connections;

  factory TrafficStats.fromJson(Map<String, dynamic> j) => TrafficStats(
    upBps: (j['upload_speed'] ?? 0) as int,
    downBps: (j['download_speed'] ?? 0) as int,
    totalUp: (j['total_upload'] ?? 0) as int,
    totalDown: (j['total_download'] ?? 0) as int,
    connections: (j['connections'] ?? 0) as int,
  );
}

/// Light row used by lists (secrets stay in the encrypted blob).
class NodeRow {
  const NodeRow({
    required this.id,
    required this.profileId,
    required this.name,
    required this.protocol,
    required this.server,
    required this.port,
    this.latency = -1,
    this.isFavorite = false,
    this.group = '',
    this.requires = const [],
  });

  final String id;
  final String profileId;
  final String name;
  final String protocol;
  final String server;
  final int port;
  final int latency; // -1 = untested/failed
  final bool isFavorite;
  final String group;
  final List<String> requires;

  bool get hasLatency => latency > 0;

  NodeRow copyWith({int? latency, bool? isFavorite, String? name}) => NodeRow(
    id: id,
    profileId: profileId,
    name: name ?? this.name,
    protocol: protocol,
    server: server,
    port: port,
    latency: latency ?? this.latency,
    isFavorite: isFavorite ?? this.isFavorite,
    group: group,
    requires: requires,
  );

  factory NodeRow.fromMap(Map<String, Object?> m) => NodeRow(
    id: m['id'] as String,
    profileId: m['profile_id'] as String,
    name: m['name'] as String,
    protocol: m['protocol'] as String,
    server: m['server'] as String,
    port: m['port'] as int,
    latency: (m['latency'] as int?) ?? -1,
    isFavorite: (m['is_favorite'] as int? ?? 0) == 1,
    group: (m['group_tag'] as String?) ?? '',
    requires: ((m['requires'] as String?) ?? '').isEmpty
        ? const []
        : (m['requires'] as String).split(','),
  );
}

class Profile {
  const Profile({
    required this.id,
    required this.name,
    this.url,
    this.userAgent = '',
    this.autoRefresh = true,
    this.intervalHours = 24,
    this.updatedAt,
    this.nodeCount = 0,
    this.upload = 0,
    this.download = 0,
    this.total = 0,
    this.expire = 0,
    this.lastError = '',
    this.failCount = 0,
  });

  final String id;
  final String name;
  final String? url;
  final String userAgent;
  final bool autoRefresh;
  final int intervalHours;
  final DateTime? updatedAt;
  final int nodeCount;
  final int upload;
  final int download;
  final int total;
  final int expire; // unix seconds, 0 = none
  final String lastError;
  final int failCount;

  bool get isRemote => url != null && url!.isNotEmpty;
  bool get isDue =>
      isRemote &&
      autoRefresh &&
      (updatedAt == null ||
          DateTime.now().difference(updatedAt!) >=
              Duration(hours: intervalHours));
  double? get usedFraction =>
      total > 0 ? ((upload + download) / total).clamp(0, 1).toDouble() : null;

  Profile copyWith({
    String? name,
    String? url,
    String? userAgent,
    bool? autoRefresh,
    int? intervalHours,
    DateTime? updatedAt,
    int? nodeCount,
    int? upload,
    int? download,
    int? total,
    int? expire,
    String? lastError,
    int? failCount,
  }) => Profile(
    id: id,
    name: name ?? this.name,
    url: url ?? this.url,
    userAgent: userAgent ?? this.userAgent,
    autoRefresh: autoRefresh ?? this.autoRefresh,
    intervalHours: intervalHours ?? this.intervalHours,
    updatedAt: updatedAt ?? this.updatedAt,
    nodeCount: nodeCount ?? this.nodeCount,
    upload: upload ?? this.upload,
    download: download ?? this.download,
    total: total ?? this.total,
    expire: expire ?? this.expire,
    lastError: lastError ?? this.lastError,
    failCount: failCount ?? this.failCount,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'url': url,
    'user_agent': userAgent,
    'auto_refresh': autoRefresh ? 1 : 0,
    'interval_hours': intervalHours,
    'updated_at': updatedAt?.millisecondsSinceEpoch,
    'upload': upload,
    'download': download,
    'total': total,
    'expire': expire,
    'last_error': lastError,
    'fail_count': failCount,
  };

  factory Profile.fromMap(Map<String, Object?> m) => Profile(
    id: m['id'] as String,
    name: m['name'] as String,
    url: m['url'] as String?,
    userAgent: (m['user_agent'] as String?) ?? '',
    autoRefresh: (m['auto_refresh'] as int? ?? 1) == 1,
    intervalHours: (m['interval_hours'] as int?) ?? 24,
    updatedAt: m['updated_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
    nodeCount: (m['node_count'] as int?) ?? 0,
    upload: (m['upload'] as int?) ?? 0,
    download: (m['download'] as int?) ?? 0,
    total: (m['total'] as int?) ?? 0,
    expire: (m['expire'] as int?) ?? 0,
    lastError: (m['last_error'] as String?) ?? '',
    failCount: (m['fail_count'] as int?) ?? 0,
  );
}

/// One row of the custom-rules editor.
class CustomRule {
  const CustomRule({
    required this.kind,
    required this.values,
    required this.outbound,
  });
  final String
  kind; // domain_suffix|domain_keyword|ip_cidr|port|process_name|package_name|rule_set
  final List<String> values;
  final String outbound; // direct|proxy|block

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'values': values,
    'outbound': outbound,
  };
  factory CustomRule.fromJson(Map<String, dynamic> j) => CustomRule(
    kind: j['kind'] as String,
    values: (j['values'] as List).cast<String>(),
    outbound: j['outbound'] as String,
  );
}

/// Routing preferences (mirrors router.Model on the Go side).
class RoutingSettings {
  const RoutingSettings({
    this.country = 'IR',
    this.autoCountry = true,
    this.mode = 'bypass_local_country',
    this.blockAds = true,
    this.blockTrackers = true,
    this.bypassLan = true,
    this.remoteDns = 'https://1.1.1.1/dns-query',
    this.localDns = '',
    this.fakeIp = true,
    this.tlsFragment = true,
    this.customRules = const [],
    this.overrideProxy = const [],
    this.overrideDirect = const [],
    this.autoUpdateRules = true,
  });

  final String country;
  final bool autoCountry;
  final String
  mode; // bypass_local_country|bypass_lan_only|global_proxy|bypass_proxy|custom
  final bool blockAds;
  final bool blockTrackers;
  final bool bypassLan;
  final String remoteDns;
  final String localDns;
  final bool fakeIp;
  final bool tlsFragment;
  final List<CustomRule> customRules;
  final List<String> overrideProxy;
  final List<String> overrideDirect;
  final bool autoUpdateRules;

  RoutingSettings copyWith({
    String? country,
    bool? autoCountry,
    String? mode,
    bool? blockAds,
    bool? blockTrackers,
    bool? bypassLan,
    String? remoteDns,
    String? localDns,
    bool? fakeIp,
    bool? tlsFragment,
    List<CustomRule>? customRules,
    List<String>? overrideProxy,
    List<String>? overrideDirect,
    bool? autoUpdateRules,
  }) => RoutingSettings(
    country: country ?? this.country,
    autoCountry: autoCountry ?? this.autoCountry,
    mode: mode ?? this.mode,
    blockAds: blockAds ?? this.blockAds,
    blockTrackers: blockTrackers ?? this.blockTrackers,
    bypassLan: bypassLan ?? this.bypassLan,
    remoteDns: remoteDns ?? this.remoteDns,
    localDns: localDns ?? this.localDns,
    fakeIp: fakeIp ?? this.fakeIp,
    tlsFragment: tlsFragment ?? this.tlsFragment,
    customRules: customRules ?? this.customRules,
    overrideProxy: overrideProxy ?? this.overrideProxy,
    overrideDirect: overrideDirect ?? this.overrideDirect,
    autoUpdateRules: autoUpdateRules ?? this.autoUpdateRules,
  );

  /// Payload for the Go `SetRouting` method (router.Model).
  Map<String, dynamic> toCoreModel() => {
    'mode': mode,
    'country': country,
    'block_ads': blockAds,
    'block_trackers': blockTrackers,
    'bypass_lan': bypassLan,
    'remote_dns': remoteDns,
    'local_dns': localDns,
    'fakeip_enabled': fakeIp,
    'custom_rules': customRules.map((r) => r.toJson()).toList(),
    'service_overrides': {'proxy': overrideProxy, 'direct': overrideDirect},
  };

  Map<String, dynamic> toJson() => {
    'country': country,
    'autoCountry': autoCountry,
    'mode': mode,
    'blockAds': blockAds,
    'blockTrackers': blockTrackers,
    'bypassLan': bypassLan,
    'remoteDns': remoteDns,
    'localDns': localDns,
    'fakeIp': fakeIp,
    'tlsFragment': tlsFragment,
    'customRules': customRules.map((r) => r.toJson()).toList(),
    'overrideProxy': overrideProxy,
    'overrideDirect': overrideDirect,
    'autoUpdateRules': autoUpdateRules,
  };

  factory RoutingSettings.fromJson(Map<String, dynamic> j) {
    const d = RoutingSettings();
    return RoutingSettings(
      country: (j['country'] as String?) ?? d.country,
      autoCountry: (j['autoCountry'] as bool?) ?? d.autoCountry,
      mode: (j['mode'] as String?) ?? d.mode,
      blockAds: (j['blockAds'] as bool?) ?? d.blockAds,
      blockTrackers: (j['blockTrackers'] as bool?) ?? d.blockTrackers,
      bypassLan: (j['bypassLan'] as bool?) ?? d.bypassLan,
      remoteDns: (j['remoteDns'] as String?) ?? d.remoteDns,
      localDns: (j['localDns'] as String?) ?? d.localDns,
      fakeIp: (j['fakeIp'] as bool?) ?? d.fakeIp,
      tlsFragment: (j['tlsFragment'] as bool?) ?? d.tlsFragment,
      customRules: ((j['customRules'] as List?) ?? const [])
          .map((e) => CustomRule.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      overrideProxy: ((j['overrideProxy'] as List?) ?? d.overrideProxy)
          .cast<String>(),
      overrideDirect: ((j['overrideDirect'] as List?) ?? d.overrideDirect)
          .cast<String>(),
      autoUpdateRules: (j['autoUpdateRules'] as bool?) ?? d.autoUpdateRules,
    );
  }
}

/// Theme / UI customization.
class AppearanceSettings {
  const AppearanceSettings({
    this.themeMode = 'system', // system|light|dark
    this.amoled = false,
    this.dynamicColor = true,
    this.accent = 0xFF3B82F6,
    this.fontScale = 1.0,
    this.density = 'comfortable', // comfortable|compact
    this.cornerRadius = 16,
    this.locale = 'system', // system|en|fa
    this.navStyle = 'auto', // auto|bottom|rail
    this.showSpeedChart = true,
  });

  final String themeMode;
  final bool amoled;
  final bool dynamicColor;
  final int accent;
  final double fontScale;
  final String density;
  final double cornerRadius;
  final String locale;
  final String navStyle;
  final bool showSpeedChart;

  AppearanceSettings copyWith({
    String? themeMode,
    bool? amoled,
    bool? dynamicColor,
    int? accent,
    double? fontScale,
    String? density,
    double? cornerRadius,
    String? locale,
    String? navStyle,
    bool? showSpeedChart,
  }) => AppearanceSettings(
    themeMode: themeMode ?? this.themeMode,
    amoled: amoled ?? this.amoled,
    dynamicColor: dynamicColor ?? this.dynamicColor,
    accent: accent ?? this.accent,
    fontScale: fontScale ?? this.fontScale,
    density: density ?? this.density,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    locale: locale ?? this.locale,
    navStyle: navStyle ?? this.navStyle,
    showSpeedChart: showSpeedChart ?? this.showSpeedChart,
  );

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode,
    'amoled': amoled,
    'dynamicColor': dynamicColor,
    'accent': accent,
    'fontScale': fontScale,
    'density': density,
    'cornerRadius': cornerRadius,
    'locale': locale,
    'navStyle': navStyle,
    'showSpeedChart': showSpeedChart,
  };

  factory AppearanceSettings.fromJson(Map<String, dynamic> j) {
    const d = AppearanceSettings();
    return AppearanceSettings(
      themeMode: (j['themeMode'] as String?) ?? d.themeMode,
      amoled: (j['amoled'] as bool?) ?? d.amoled,
      dynamicColor: (j['dynamicColor'] as bool?) ?? d.dynamicColor,
      accent: (j['accent'] as int?) ?? d.accent,
      fontScale: ((j['fontScale'] as num?) ?? d.fontScale).toDouble(),
      density: (j['density'] as String?) ?? d.density,
      cornerRadius: ((j['cornerRadius'] as num?) ?? d.cornerRadius).toDouble(),
      locale: (j['locale'] as String?) ?? d.locale,
      navStyle: (j['navStyle'] as String?) ?? d.navStyle,
      showSpeedChart: (j['showSpeedChart'] as bool?) ?? d.showSpeedChart,
    );
  }
}

/// Connection / core preferences.
class AppSettings {
  const AppSettings({
    this.appearance = const AppearanceSettings(),
    this.routing = const RoutingSettings(),
    this.mode = ConnMode.proxyOnly,
    this.localPort = 2080,
    this.allowLan = false,
    this.localAuth = true,
    this.tunMtu = 9000,
    this.tunStrictRoute = false,
    this.tunIpv6 = false,
    this.perAppMode = 'off', // off|include|exclude (Android)
    this.perAppPackages = const [],
    this.autoConnect = false,
    this.startMinimized = false,
    this.closeToTray = true,
    this.autoLaunch = false,
    this.autoFailover = false,
    this.testUrl = 'https://www.gstatic.com/generate_204',
    this.activeNodeId,
    this.activeProfileId,
    this.onboarded = false,
    this.logLevel = 'info',
    this.autoBackup = false,
  });

  final AppearanceSettings appearance;
  final RoutingSettings routing;
  final ConnMode mode;
  final int localPort;
  final bool allowLan;
  final bool localAuth;
  final int tunMtu;
  final bool tunStrictRoute;
  final bool tunIpv6;
  final String perAppMode;
  final List<String> perAppPackages;
  final bool autoConnect;
  final bool startMinimized;
  final bool closeToTray;
  final bool autoLaunch;
  final bool autoFailover;
  final String testUrl;
  final String? activeNodeId;
  final String? activeProfileId;
  final bool onboarded;
  final String logLevel;
  final bool autoBackup;

  AppSettings copyWith({
    AppearanceSettings? appearance,
    RoutingSettings? routing,
    ConnMode? mode,
    int? localPort,
    bool? allowLan,
    bool? localAuth,
    int? tunMtu,
    bool? tunStrictRoute,
    bool? tunIpv6,
    String? perAppMode,
    List<String>? perAppPackages,
    bool? autoConnect,
    bool? startMinimized,
    bool? closeToTray,
    bool? autoLaunch,
    bool? autoFailover,
    String? testUrl,
    Object? activeNodeId = _keep,
    Object? activeProfileId = _keep,
    bool? onboarded,
    String? logLevel,
    bool? autoBackup,
  }) => AppSettings(
    appearance: appearance ?? this.appearance,
    routing: routing ?? this.routing,
    mode: mode ?? this.mode,
    localPort: localPort ?? this.localPort,
    allowLan: allowLan ?? this.allowLan,
    localAuth: localAuth ?? this.localAuth,
    tunMtu: tunMtu ?? this.tunMtu,
    tunStrictRoute: tunStrictRoute ?? this.tunStrictRoute,
    tunIpv6: tunIpv6 ?? this.tunIpv6,
    perAppMode: perAppMode ?? this.perAppMode,
    perAppPackages: perAppPackages ?? this.perAppPackages,
    autoConnect: autoConnect ?? this.autoConnect,
    startMinimized: startMinimized ?? this.startMinimized,
    closeToTray: closeToTray ?? this.closeToTray,
    autoLaunch: autoLaunch ?? this.autoLaunch,
    autoFailover: autoFailover ?? this.autoFailover,
    testUrl: testUrl ?? this.testUrl,
    activeNodeId: identical(activeNodeId, _keep)
        ? this.activeNodeId
        : activeNodeId as String?,
    activeProfileId: identical(activeProfileId, _keep)
        ? this.activeProfileId
        : activeProfileId as String?,
    onboarded: onboarded ?? this.onboarded,
    logLevel: logLevel ?? this.logLevel,
    autoBackup: autoBackup ?? this.autoBackup,
  );

  static const Object _keep = Object();

  Map<String, dynamic> toJson() => {
    'appearance': appearance.toJson(),
    'routing': routing.toJson(),
    'mode': mode.wire,
    'localPort': localPort,
    'allowLan': allowLan,
    'localAuth': localAuth,
    'tunMtu': tunMtu,
    'tunStrictRoute': tunStrictRoute,
    'tunIpv6': tunIpv6,
    'perAppMode': perAppMode,
    'perAppPackages': perAppPackages,
    'autoConnect': autoConnect,
    'startMinimized': startMinimized,
    'closeToTray': closeToTray,
    'autoLaunch': autoLaunch,
    'autoFailover': autoFailover,
    'testUrl': testUrl,
    'activeNodeId': activeNodeId,
    'activeProfileId': activeProfileId,
    'onboarded': onboarded,
    'logLevel': logLevel,
    'autoBackup': autoBackup,
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    return AppSettings(
      appearance: AppearanceSettings.fromJson(
        ((j['appearance'] as Map?) ?? {}).cast<String, dynamic>(),
      ),
      routing: RoutingSettings.fromJson(
        ((j['routing'] as Map?) ?? {}).cast<String, dynamic>(),
      ),
      mode: ConnMode.parse(j['mode'] as String?),
      localPort: (j['localPort'] as int?) ?? d.localPort,
      allowLan: (j['allowLan'] as bool?) ?? d.allowLan,
      localAuth: (j['localAuth'] as bool?) ?? d.localAuth,
      tunMtu: (j['tunMtu'] as int?) ?? d.tunMtu,
      tunStrictRoute: (j['tunStrictRoute'] as bool?) ?? d.tunStrictRoute,
      tunIpv6: (j['tunIpv6'] as bool?) ?? d.tunIpv6,
      perAppMode: (j['perAppMode'] as String?) ?? d.perAppMode,
      perAppPackages: ((j['perAppPackages'] as List?) ?? const [])
          .cast<String>(),
      autoConnect: (j['autoConnect'] as bool?) ?? d.autoConnect,
      startMinimized: (j['startMinimized'] as bool?) ?? d.startMinimized,
      closeToTray: (j['closeToTray'] as bool?) ?? d.closeToTray,
      autoLaunch: (j['autoLaunch'] as bool?) ?? d.autoLaunch,
      autoFailover: (j['autoFailover'] as bool?) ?? d.autoFailover,
      testUrl: (j['testUrl'] as String?) ?? d.testUrl,
      activeNodeId: j['activeNodeId'] as String?,
      activeProfileId: j['activeProfileId'] as String?,
      onboarded: (j['onboarded'] as bool?) ?? d.onboarded,
      logLevel: (j['logLevel'] as String?) ?? d.logLevel,
      autoBackup: (j['autoBackup'] as bool?) ?? d.autoBackup,
    );
  }

  String encode() => jsonEncode(toJson());
  factory AppSettings.decode(String s) =>
      AppSettings.fromJson((jsonDecode(s) as Map).cast<String, dynamic>());
}

class LogLine {
  const LogLine(this.time, this.level, this.message);
  final DateTime time;
  final String level;
  final String message;
}

class RuleSetStatus {
  const RuleSetStatus({
    required this.tag,
    required this.present,
    this.bytes = 0,
    this.fetchedAt,
    this.source,
    this.nextRefresh,
  });
  final String tag;
  final bool present;
  final int bytes;
  final DateTime? fetchedAt;
  final String? source;
  final DateTime? nextRefresh;

  factory RuleSetStatus.fromJson(Map<String, dynamic> j) {
    DateTime? t(String k) {
      final v = j[k] as String?;
      if (v == null || v.startsWith('0001')) return null;
      return DateTime.tryParse(v);
    }

    return RuleSetStatus(
      tag: j['tag'] as String,
      present: (j['present'] as bool?) ?? false,
      bytes: (j['bytes'] as int?) ?? 0,
      fetchedAt: t('fetched_at'),
      source: j['source'] as String?,
      nextRefresh: t('next_refresh'),
    );
  }
}
