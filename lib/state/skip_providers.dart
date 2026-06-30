import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/playback/skip_config.dart';
import 'package:jump_player/infra/config/preferences_skip_store.dart';

final skipStoreProvider =
    Provider<PreferencesSkipStore>((ref) => PreferencesSkipStore());

class SkipConfigController extends StateNotifier<Map<String, SkipConfig>> {
  SkipConfigController(this._store) : super(const {}) {
    _load();
  }
  final PreferencesSkipStore _store;
  bool _dirty = false;

  Future<void> _load() async {
    final loaded = await _store.load();
    // A write (setIntro/setOutro/clear) may have landed while the initial
    // load was in flight; don't clobber it with the stale snapshot.
    if (mounted && !_dirty) state = loaded;
  }

  SkipConfig configFor(String dirPath) => state[dirPath] ?? const SkipConfig();

  Future<void> setIntro(String dirPath, int seconds) => _update(
      dirPath, configFor(dirPath).copyWith(introSeconds: seconds < 0 ? 0 : seconds));

  Future<void> setOutro(String dirPath, int seconds) => _update(
      dirPath, configFor(dirPath).copyWith(outroSeconds: seconds < 0 ? 0 : seconds));

  Future<void> clear(String dirPath) async {
    _dirty = true;
    final copy = Map<String, SkipConfig>.from(state)..remove(dirPath);
    state = copy;
    await _store.save(copy);
  }

  Future<void> _update(String dirPath, SkipConfig cfg) async {
    _dirty = true;
    final copy = Map<String, SkipConfig>.from(state)..[dirPath] = cfg;
    state = copy;
    await _store.save(copy);
  }
}

final skipConfigProvider =
    StateNotifierProvider<SkipConfigController, Map<String, SkipConfig>>(
        (ref) => SkipConfigController(ref.watch(skipStoreProvider)));
