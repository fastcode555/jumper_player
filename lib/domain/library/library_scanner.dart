import 'dart:io';

import 'package:jump_player/domain/library/episode_sorter.dart';
import 'package:jump_player/domain/library/library_models.dart';
import 'package:jump_player/domain/library/name_clean_config.dart';
import 'package:jump_player/domain/library/name_cleaner.dart';

class LibraryScanner {
  static const Set<String> videoExtensions = {
    '.mkv', '.mp4', '.avi', '.mov', '.flv', '.ts',
    '.webm', '.m4v', '.wmv', '.rmvb', '.rm', '.mpg', '.mpeg',
  };

  Future<Series> scan(
    String rootPath, [
    NameCleanConfig config = NameCleanConfig.defaults,
  ]) async {
    final root = Directory(rootPath);
    final groupsMap = <String, List<Episode>>{};

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = _baseName(entity.path);
      final ext = _extension(name).toLowerCase();
      if (!videoExtensions.contains(ext)) continue;

      final parentDirPath = _parentPath(entity.path);
      final parentDir = _baseName(parentDirPath);
      final cleaned = NameCleaner.clean(name, parentDir, config);
      final episode = Episode(
        path: entity.path,
        fileName: name,
        displayName: cleaned.displayName,
        season: cleaned.season,
        episodeNumber: cleaned.episodeNumber,
      );
      groupsMap.putIfAbsent(parentDirPath, () => []).add(episode);
    }

    // Build groups: key is parent dir path, title is cleaned dir basename.
    final dirPaths = groupsMap.keys.toList()
      ..sort((a, b) => EpisodeSorter.compareNatural(
            NameCleaner.cleanDir(_baseName(a), config),
            NameCleaner.cleanDir(_baseName(b), config),
          ));
    final groups = [
      for (final dirPath in dirPaths)
        SeriesGroup(
          title: NameCleaner.cleanDir(_baseName(dirPath), config),
          episodes: EpisodeSorter.sort(groupsMap[dirPath]!),
          dirPath: dirPath,
        ),
    ];

    return Series(name: _baseName(rootPath), rootPath: rootPath, groups: groups);
  }

  static String _baseName(String path) {
    final norm = path.endsWith('/') || path.endsWith('\\')
        ? path.substring(0, path.length - 1)
        : path;
    final idxForward = norm.lastIndexOf('/');
    final idxBack = norm.lastIndexOf('\\');
    final idx = idxForward > idxBack ? idxForward : idxBack;
    return idx >= 0 ? norm.substring(idx + 1) : norm;
  }

  static String _parentPath(String path) {
    final norm = path.endsWith('/') || path.endsWith('\\')
        ? path.substring(0, path.length - 1)
        : path;
    final idxForward = norm.lastIndexOf('/');
    final idxBack = norm.lastIndexOf('\\');
    final idx = idxForward > idxBack ? idxForward : idxBack;
    return idx >= 0 ? norm.substring(0, idx) : norm;
  }

  static String _extension(String name) {
    final idx = name.lastIndexOf('.');
    return idx >= 0 ? name.substring(idx) : '';
  }
}
