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

  // Retry the intro seek up to this many position ticks. A seek issued right
  // after open/play is often dropped by media_kit before it is ready to seek,
  // so one attempt is unreliable; this bounds the retry to the episode's
  // startup window so we never fight a user who scrubs into the opening.
  static const int _maxIntroAttempts = 40;

  String? _episodePath;
  bool _introDone = false;
  bool _outroDone = false;
  int _introAttempts = 0;

  void _onPosition(Duration pos) {
    final queue = _ref.read(playbackQueueProvider);
    final path = queue.currentEpisode?.path;
    if (path != _episodePath) {
      _episodePath = path;
      _introDone = false;
      _outroDone = false;
      _introAttempts = 0;
    }
    final dirPath = queue.currentGroupDirPath;
    if (dirPath == null) return;
    final cfg = _ref.read(skipConfigProvider.notifier).configFor(dirPath);
    final d = (_ref.read(durationProvider).value ?? Duration.zero).inSeconds;
    final p = pos.inSeconds;

    // Intro: keep re-issuing the seek until the position actually reaches the
    // intro end, then mark done. This survives the dropped-seek race above.
    if (!_introDone && cfg.introSeconds > 0 && (d == 0 || cfg.introSeconds < d)) {
      if (p >= cfg.introSeconds) {
        _introDone = true;
      } else if (_introAttempts < _maxIntroAttempts) {
        _introAttempts++;
        _ref
            .read(playerEngineProvider)
            .seek(Duration(seconds: cfg.introSeconds));
        return;
      } else {
        _introDone = true;
      }
    }

    // Outro: advance before the credits. This never double-advances with
    // PlaybackQueueController's own completedStream-based auto-next: outro
    // fires strictly before EOF (outroSeconds > 0), and calling next() ->
    // engine.open() on the next file suppresses the old media's `completed`
    // event, so the two advance paths are temporally disjoint per episode.
    // When auto-advance is OFF we intentionally leave _outroDone unset so the
    // skip can still fire once the user turns auto-advance back on mid-outro.
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
