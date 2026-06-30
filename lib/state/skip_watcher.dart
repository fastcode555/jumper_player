import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_queue.dart';
import 'package:jump_player/state/playback_settings.dart';
import 'package:jump_player/state/skip_providers.dart';

class SkipWatcher {
  SkipWatcher(this._ref) {
    // Keep durationProvider's underlying stream subscription alive so its
    // value is up to date by the time a position update is handled (a
    // StreamProvider only starts listening to its stream once it is
    // watched/listened to at least once).
    _durationSub = _ref.listen<AsyncValue<Duration>>(
        durationProvider, (_, __) {});
    _sub = _ref.listen<AsyncValue<Duration>>(positionProvider, (_, next) {
      final pos = next.value;
      if (pos != null) _onPosition(pos);
    });
  }

  final Ref _ref;
  late final ProviderSubscription<AsyncValue<Duration>> _sub;
  late final ProviderSubscription<AsyncValue<Duration>> _durationSub;

  String? _episodePath;
  bool _introDone = false;
  bool _outroDone = false;

  void _onPosition(Duration pos) {
    final queue = _ref.read(playbackQueueProvider);
    final path = queue.currentEpisode?.path;
    if (path != _episodePath) {
      _episodePath = path;
      _introDone = false;
      _outroDone = false;
    }
    final dirPath = queue.currentGroupDirPath;
    if (dirPath == null) return;
    final cfg = _ref.read(skipConfigProvider.notifier).configFor(dirPath);
    final d = (_ref.read(durationProvider).value ?? Duration.zero).inSeconds;
    final p = pos.inSeconds;

    if (!_introDone &&
        cfg.introSeconds > 0 &&
        (d == 0 || cfg.introSeconds < d) &&
        p < cfg.introSeconds) {
      _introDone = true;
      _ref.read(playerEngineProvider).seek(Duration(seconds: cfg.introSeconds));
      return;
    }

    if (!_outroDone &&
        cfg.outroSeconds > 0 &&
        d > 0 &&
        p >= d - cfg.outroSeconds) {
      if (_ref.read(autoAdvanceProvider)) {
        _outroDone = true;
        _ref.read(playbackQueueProvider.notifier).next();
      }
    }
  }

  void dispose() {
    _sub.close();
    _durationSub.close();
  }
}

final skipWatcherProvider = Provider<SkipWatcher>((ref) {
  final w = SkipWatcher(ref);
  ref.onDispose(w.dispose);
  return w;
});
