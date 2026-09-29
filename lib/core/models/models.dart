class ProxyNodeModel {
  final String id;
  final String name;
  final String type;
  final String server;
  final int port;
  final int latencyMs;
  final bool isFavorite;
  final String group;
  final String rawConfig;

  ProxyNodeModel({
    required this.id,
    required this.name,
    required this.type,
    required this.server,
    required this.port,
    this.latencyMs = -1,
    this.isFavorite = false,
    this.group = 'Default',
    required this.rawConfig,
  });

  ProxyNodeModel copyWith({
    String? id,
    String? name,
    String? type,
    String? server,
    int? port,
    int? latencyMs,
    bool? isFavorite,
    String? group,
    String? rawConfig,
  }) {
    return ProxyNodeModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      server: server ?? this.server,
      port: port ?? this.port,
      latencyMs: latencyMs ?? this.latencyMs,
      isFavorite: isFavorite ?? this.isFavorite,
      group: group ?? this.group,
      rawConfig: rawConfig ?? this.rawConfig,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'server': server,
      'port': port,
      'latency_ms': latencyMs,
      'is_favorite': isFavorite,
      'group': group,
      'raw_config': rawConfig,
    };
  }

  factory ProxyNodeModel.fromMap(Map<String, dynamic> map) {
    return ProxyNodeModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      type: map['type'] ?? '',
      server: map['server'] ?? '',
      port: map['port'] is int ? map['port'] : int.tryParse(map['port']?.toString() ?? '443') ?? 443,
      latencyMs: map['latency_ms'] ?? -1,
      isFavorite: map['is_favorite'] ?? false,
      group: map['group'] ?? 'Default',
      rawConfig: map['raw_config'] ?? '',
    );
  }
}

class ProfileModel {
  final String id;
  final String name;
  final String url;
  final int autoUpdateMinutes;
  final DateTime lastUpdated;
  final int nodeCount;
  final int uploadBytes;
  final int downloadBytes;
  final int totalBytes;
  final DateTime? expireDate;

  ProfileModel({
    required this.id,
    required this.name,
    required this.url,
    this.autoUpdateMinutes = 1440,
    required this.lastUpdated,
    this.nodeCount = 0,
    this.uploadBytes = 0,
    this.downloadBytes = 0,
    this.totalBytes = 0,
    this.expireDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'auto_update_minutes': autoUpdateMinutes,
      'last_updated': lastUpdated.toIso8601String(),
      'node_count': nodeCount,
      'upload_bytes': uploadBytes,
      'download_bytes': downloadBytes,
      'total_bytes': totalBytes,
      'expire_date': expireDate?.toIso8601String(),
    };
  }

  factory ProfileModel.fromMap(Map<String, dynamic> map) {
    return ProfileModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      url: map['url'] ?? '',
      autoUpdateMinutes: map['auto_update_minutes'] ?? 1440,
      lastUpdated: DateTime.tryParse(map['last_updated'] ?? '') ?? DateTime.now(),
      nodeCount: map['node_count'] ?? 0,
      uploadBytes: map['upload_bytes'] ?? 0,
      downloadBytes: map['download_bytes'] ?? 0,
      totalBytes: map['total_bytes'] ?? 0,
      expireDate: map['expire_date'] != null ? DateTime.tryParse(map['expire_date']) : null,
    );
  }
}

class IPInfo {
  final String ip;
  final String country;
  final String countryCode;
  final String city;
  final String isp;

  const IPInfo({
    required this.ip,
    required this.country,
    required this.countryCode,
    required this.city,
    required this.isp,
  });

  static const IPInfo disconnected = IPInfo(
    ip: 'Direct Connection',
    country: 'Local',
    countryCode: 'LOC',
    city: 'Direct',
    isp: 'Standard ISP',
  );
}

class AppSettingsModel {
  final String country;
  final String routingMode;
  final bool tunEnabled;
  final bool isDarkMode;
  final int accentColorValue;
  final bool autoConnect;
  final bool startMinimized;

  AppSettingsModel({
    this.country = 'IR',
    this.routingMode = 'bypass_local_lan',
    this.tunEnabled = true,
    this.isDarkMode = true,
    this.accentColorValue = 0xFF3B82F6, // Sleek Modern Blue default
    this.autoConnect = false,
    this.startMinimized = false,
  });

  AppSettingsModel copyWith({
    String? country,
    String? routingMode,
    bool? tunEnabled,
    bool? isDarkMode,
    int? accentColorValue,
    bool? autoConnect,
    bool? startMinimized,
  }) {
    return AppSettingsModel(
      country: country ?? this.country,
      routingMode: routingMode ?? this.routingMode,
      tunEnabled: tunEnabled ?? this.tunEnabled,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      accentColorValue: accentColorValue ?? this.accentColorValue,
      autoConnect: autoConnect ?? this.autoConnect,
      startMinimized: startMinimized ?? this.startMinimized,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'country': country,
      'routing_mode': routingMode,
      'tun_enabled': tunEnabled,
      'is_dark_mode': isDarkMode,
      'accent_color_value': accentColorValue,
      'auto_connect': autoConnect,
      'start_minimized': startMinimized,
    };
  }

  factory AppSettingsModel.fromMap(Map<String, dynamic> map) {
    return AppSettingsModel(
      country: map['country'] ?? 'IR',
      routingMode: map['routing_mode'] ?? 'bypass_local_lan',
      tunEnabled: map['tun_enabled'] ?? true,
      isDarkMode: map['is_dark_mode'] ?? true,
      accentColorValue: map['accent_color_value'] ?? 0xFF3B82F6,
      autoConnect: map['auto_connect'] ?? false,
      startMinimized: map['start_minimized'] ?? false,
    );
  }
}
