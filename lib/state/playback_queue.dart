import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/domain/playback/player_engine.dart';
import 'package:jump_player/state/playback_providers.dart';
import 'package:jump_player/state/playback_settings.dart';

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

  String? get currentGroupDirPath {
    final s = series;
    if (s == null || currentIndex < 0) return null;
    var idx = currentIndex;
    for (final g in s.groups) {
      if (idx < g.episodes.length) return g.dirPath;
      idx -= g.episodes.length;
    }
    return null;
  }
}

class PlaybackQueueController extends StateNotifier<PlaybackQueueState> {
  PlaybackQueueController(this._engine) : super(const PlaybackQueueState()) {
    _completedSub = _engine.completedStream.listen((completed) {
      if (!completed) return;
      if (_advancing) return;
      if (autoNext && state.hasNext) {
        _advancing = true;
        next().whenComplete(() => _advancing = false);
      }
    });
  }

  final PlayerEngine _engine;
  late final StreamSubscription<bool> _completedSub;
  bool autoNext = true;
  bool _advancing = false;

  Future<void> loadSeries(Series series, {int startAt = 0}) async {
    state = PlaybackQueueState(series: series, currentIndex: -1);
    if (series.episodes.isEmpty) return;
    final idx = startAt.clamp(0, series.episodes.length - 1);
    await playAt(idx);
  }

  /// Swap in a re-scanned series (e.g. after a name-clean config change)
  /// without interrupting playback: keeps the same episode by path and only
  /// updates grouping/displayNames + currentIndex. Does NOT touch the engine.
  void remapSeries(Series series) {
    final currentPath = state.currentEpisode?.path;
    final eps = series.episodes;
    final idx = currentPath == null
        ? state.currentIndex
        : eps.indexWhere((e) => e.path == currentPath);
    state = PlaybackQueueState(series: series, currentIndex: idx < 0 ? -1 : idx);
  }

  /// Swap in a re-scanned series after a rename. If [oldPath] was the current
  /// episode, point currentIndex at [newPath]; otherwise preserve by current path.
  void remapSeriesByPath(Series series,
      {required String oldPath, required String newPath}) {
    final currentPath = state.currentEpisode?.path;
    final targetPath = currentPath == oldPath ? newPath : currentPath;
    final eps = series.episodes;
    final idx =
        targetPath == null ? -1 : eps.indexWhere((e) => e.path == targetPath);
    state = PlaybackQueueState(series: series, currentIndex: idx < 0 ? -1 : idx);
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
  final controller = PlaybackQueueController(engine);
  controller.autoNext = ref.read(autoAdvanceProvider);
  ref.listen<bool>(autoAdvanceProvider, (_, value) => controller.autoNext = value);
  return controller;
});
