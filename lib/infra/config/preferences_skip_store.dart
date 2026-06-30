import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jump_player/domain/playback/skip_config.dart';

class PreferencesSkipStore {
  static const String _key = 'skip_config_v1';

  Future<Map<String, SkipConfig>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) =>
          MapEntry(k, SkipConfig.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Map<String, SkipConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    final map = configs.map((k, v) => MapEntry(k, v.toJson()));
    await prefs.setString(_key, jsonEncode(map));
  }
}
