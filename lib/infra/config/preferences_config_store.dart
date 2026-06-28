import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';

class PreferencesConfigStore {
  static const String _key = 'name_clean_config_v3';

  Future<NameCleanConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return NameCleanConfig.defaults;
    return NameCleanConfig.decode(raw);
  }

  Future<void> save(NameCleanConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, config.encode());
  }
}
