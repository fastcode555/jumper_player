import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';

class PlaybackQueueState {
  const PlaybackQueueState({this.series, this.currentIndex = -1});

  final Series? series;
  final int currentIndex;

  List<Episode> get episodes => series?.episodes ?? const [];
  Episode? get currentEpisode =>
      (currentIndex >= 0 && currentIndex < episodes.length)
          ? episodes[currentIndex]
          : null;
  bool get hasNext => currentIndex >= 0 && currentIndex < episodes.length - 1;
  bool get hasPrevious => currentIndex > 0;
}

class PlaybackQueueController extends StateNotifier<PlaybackQueueState> {
  PlaybackQueueController(this._engine) : super(const PlaybackQueueState()) {
    _completedSub = _engine.completedStream.listen((_) {
      if (autoNext && state.hasNext) {
        next();
      }
    });
  }

  final PlayerEngine _engine;
  late final StreamSubscription<bool> _completedSub;
  bool autoNext = true;

  Future<void> loadSeries(Series series, {int startAt = 0}) async {
    state = PlaybackQueueState(series: series, currentIndex: -1);
    if (series.episodes.isEmpty) return;
    final idx = startAt.clamp(0, series.episodes.length - 1);
    await playAt(idx);
  }

  Future<void> playAt(int index) async {
    final eps = state.episodes;
    if (index < 0 || index >= eps.length) return;
    state = PlaybackQueueState(series: state.series, currentIndex: index);
    await _engine.open(eps[index].path);
    await _engine.play();
  }

  Future<void> next() async {
    if (state.hasNext) await playAt(state.currentIndex + 1);
  }

  Future<void> previous() async {
    if (state.hasPrevious) await playAt(state.currentIndex - 1);
  }

  @override
  void dispose() {
    _completedSub.cancel();
    super.dispose();
  }
}

final playbackQueueProvider =
    StateNotifierProvider<PlaybackQueueController, PlaybackQueueState>((ref) {
  final engine = ref.watch(playerEngineProvider);
  return PlaybackQueueController(engine);
});
