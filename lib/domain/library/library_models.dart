class Episode {
  Episode({
    required this.path,
    required this.fileName,
    String? displayName,
    this.season,
    this.episodeNumber,
  }) : displayName = displayName ?? fileName;

  final String path;
  final String fileName;
  final String displayName;
  final int? season;
  final int? episodeNumber;

  @override
  bool operator ==(Object other) => other is Episode && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

class SeriesGroup {
  const SeriesGroup({required this.title, required this.episodes});

  final String title;
  final List<Episode> episodes;
}

class Series {
  const Series({
    required this.name,
    required this.rootPath,
    required this.groups,
  });

  final String name;
  final String rootPath;
  final List<SeriesGroup> groups;

  List<Episode> get episodes => [for (final g in groups) ...g.episodes];
}
