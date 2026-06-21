import 'dart:io';

import 'package:jump_player/domain/library/episode_sorter.dart';
import 'package:jump_player/domain/library/library_models.dart';

class LibraryScanner {
  static const Set<String> videoExtensions = {
    '.mkv', '.mp4', '.avi', '.mov', '.flv', '.ts',
    '.webm', '.m4v', '.wmv', '.rmvb', '.rm', '.mpg', '.mpeg',
  };

  Future<Series> scan(String rootPath) async {
    final root = Directory(rootPath);
    final episodes = <Episode>[];

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = _baseName(entity.path);
      final ext = _extension(name).toLowerCase();
      if (!videoExtensions.contains(ext)) continue;
      final parsed = EpisodeSorter.parse(name);
      episodes.add(Episode(
        path: entity.path,
        fileName: name,
        season: parsed?.season,
        episodeNumber: parsed?.episode,
      ));
    }

    return Series(
      name: _baseName(rootPath),
      rootPath: rootPath,
      episodes: EpisodeSorter.sort(episodes),
    );
  }

  // Cross-platform: handles both '/' (POSIX) and '\\' (Windows) separators.
  // The brief's original only split on '/'; we find the last occurrence of
  // either separator so that paths returned by Directory.list on Windows
  // (which use '\\') are handled correctly without adding any package dep.
  static String _baseName(String path) {
    final norm = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final idxForward = norm.lastIndexOf('/');
    final idxBack = norm.lastIndexOf('\\');
    final idx = idxForward > idxBack ? idxForward : idxBack;
    return idx >= 0 ? norm.substring(idx + 1) : norm;
  }

  static String _extension(String name) {
    final idx = name.lastIndexOf('.');
    return idx >= 0 ? name.substring(idx) : '';
  }
}
