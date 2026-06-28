import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/infra/config/preferences_config_store.dart';

final configStoreProvider =
    Provider<PreferencesConfigStore>((ref) => PreferencesConfigStore());

class NameCleanConfigController extends StateNotifier<NameCleanConfig> {
  NameCleanConfigController(this._store) : super(NameCleanConfig.defaults) {
    _load();
  }

  final PreferencesConfigStore _store;

  Future<void> _load() async {
    state = await _store.load();
  }

  Future<void> save(NameCleanConfig config) async {
    state = config;
    await _store.save(config);
  }
}

final nameCleanConfigProvider =
    StateNotifierProvider<NameCleanConfigController, NameCleanConfig>((ref) {
  return NameCleanConfigController(ref.watch(configStoreProvider));
});
