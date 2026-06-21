class Episode {
  const Episode({
    required this.path,
    required this.fileName,
    this.season,
    this.episodeNumber,
  });

  final String path;
  final String fileName;
  final int? season;
  final int? episodeNumber;

  @override
  bool operator ==(Object other) =>
      other is Episode && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

class Series {
  const Series({
    required this.name,
    required this.rootPath,
    required this.episodes,
  });

  final String name;
  final String rootPath;
  final List<Episode> episodes;
}
