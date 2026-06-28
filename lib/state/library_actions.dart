import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/domain/library/library_scanner.dart';
import 'package:jump_player/state/name_clean_providers.dart';
import 'package:jump_player/state/playback_queue.dart';

class LibraryActions {
  LibraryActions(this._scanner, this._ref);

  final LibraryScanner _scanner;
  final Ref _ref;
  String? _currentRoot;

  PlaybackQueueController get _queue =>
      _ref.read(playbackQueueProvider.notifier);

  Future<void> openFolder(String path) async {
    final config = _ref.read(nameCleanConfigProvider);
    final series = await _scanner.scan(path, config);
    _currentRoot = path;
    await _queue.loadSeries(series);
  }

  Future<void> reapplyCurrent() async {
    final root = _currentRoot;
    if (root == null) return;
    final config = _ref.read(nameCleanConfigProvider);
    final currentPath =
        _ref.read(playbackQueueProvider).currentEpisode?.path;
    final series = await _scanner.scan(root, config);
    final startAt = _flatIndexOfPath(series, currentPath);
    await _queue.loadSeries(series, startAt: startAt);
  }

  int _flatIndexOfPath(Series series, String? path) {
    if (path == null) return 0;
    final eps = series.episodes;
    final i = eps.indexWhere((e) => e.path == path);
    return i < 0 ? 0 : i;
  }
}

final libraryActionsProvider = Provider<LibraryActions>((ref) {
  return LibraryActions(LibraryScanner(), ref);
});
