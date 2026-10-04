import 'country_bypass/country_bypass_store.dart';
import 'entry_server/entry_server_store.dart';

/// Single seam for every config tweak the easy features make. The generated
/// profile calls this once, so a new feature adds no hook to upstream files.
class EasyConfig {
  const EasyConfig._();

  static Future<Map<String, dynamic>> apply(
    Map<String, dynamic> rawConfig,
  ) async {
    var config = rawConfig;
    config = await EntryServerStore.applyStored(config);
    config = await CountryBypassStore.applyStored(config);
    return config;
  }
}
