import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/domain/library/library_scanner.dart';
import 'package:jump_player/infra/fs/file_system_ops.dart';
import 'package:jump_player/state/name_clean_providers.dart';
import 'package:jump_player/state/playback_queue.dart';

class LibraryActions {
  LibraryActions(this._scanner, this._ref);

  final LibraryScanner _scanner;
  final Ref _ref;
  String? _currentRoot;

  PlaybackQueueController get _queue =>
      _ref.read(playbackQueueProvider.notifier);

  FileSystemOps get _ops => _ref.read(fileSystemOpsProvider);

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
    final series = await _scanner.scan(root, config);
    _queue.remapSeries(series);
  }

  Future<void> revealEpisode(Episode ep) => _ops.reveal(ep.path);

  Future<void> renameEpisode(Episode ep, String newBaseName) async {
    final newPath = await _ops.rename(ep.path, newBaseName);
    final root = _currentRoot;
    if (root == null) return;
    final config = _ref.read(nameCleanConfigProvider);
    final series = await _scanner.scan(root, config);
    _queue.remapSeriesByPath(series, oldPath: ep.path, newPath: newPath);
  }

  Future<void> deleteEpisode(Episode ep) async {
    await _ops.moveToTrash(ep.path);
    final dir = _parentPath(ep.path);
    if (!_dirHasVideo(dir)) {
      await _ops.moveToTrash(dir);
    }
    await _rescan();
  }

  Future<void> revealFolder(SeriesGroup group) => _ops.reveal(group.dirPath);

  Future<void> renameFolder(SeriesGroup group, String newName) async {
    if (isRootGroup(group)) {
      throw StateError('Cannot rename the opened root folder');
    }
    await _ops.renameDirectory(group.dirPath, newName);
    await _rescan();
  }

  Future<void> deleteFolder(SeriesGroup group) async {
    if (isRootGroup(group)) {
      throw StateError('Cannot delete the opened root folder');
    }
    await _ops.moveToTrash(group.dirPath);
    await _rescan();
  }

  bool isRootGroup(SeriesGroup g) => g.dirPath == _currentRoot;

  Future<void> _rescan() async {
    final root = _currentRoot;
    if (root == null) return;
    final config = _ref.read(nameCleanConfigProvider);
    final series = await _scanner.scan(root, config);
    _queue.remapSeries(series);
  }

  bool _dirHasVideo(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) return false;
    for (final e in d.listSync(followLinks: false)) {
      if (e is File) {
        final n = e.path.toLowerCase();
        if (LibraryScanner.videoExtensions.any((ext) => n.endsWith(ext))) {
          return true;
        }
      }
    }
    return false;
  }

  static String _parentPath(String path) {
    final norm = path.endsWith('/') || path.endsWith('\\')
        ? path.substring(0, path.length - 1)
        : path;
    final i = norm.lastIndexOf('/') > norm.lastIndexOf('\\')
        ? norm.lastIndexOf('/')
        : norm.lastIndexOf('\\');
    return i >= 0 ? norm.substring(0, i) : norm;
  }
}

final libraryActionsProvider = Provider<LibraryActions>((ref) {
  return LibraryActions(LibraryScanner(), ref);
});

final fileSystemOpsProvider =
    Provider<FileSystemOps>((ref) => DefaultFileSystemOps());
