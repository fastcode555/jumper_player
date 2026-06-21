import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_scanner.dart';
import 'package:jump_player/state/playback_queue.dart';

class LibraryActions {
  LibraryActions(this._scanner, this._queue);

  final LibraryScanner _scanner;
  final PlaybackQueueController _queue;

  Future<void> openFolder(String path) async {
    final series = await _scanner.scan(path);
    await _queue.loadSeries(series);
  }
}

final libraryActionsProvider = Provider<LibraryActions>((ref) {
  return LibraryActions(
    LibraryScanner(),
    ref.watch(playbackQueueProvider.notifier),
  );
});
