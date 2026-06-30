class SkipConfig {
  const SkipConfig({this.introSeconds = 0, this.outroSeconds = 0});

  final int introSeconds;
  final int outroSeconds;

  SkipConfig copyWith({int? introSeconds, int? outroSeconds}) => SkipConfig(
        introSeconds: introSeconds ?? this.introSeconds,
        outroSeconds: outroSeconds ?? this.outroSeconds,
      );

  Map<String, dynamic> toJson() =>
      {'intro': introSeconds, 'outro': outroSeconds};

  factory SkipConfig.fromJson(Map<String, dynamic> json) => SkipConfig(
        introSeconds: (json['intro'] as num?)?.toInt() ?? 0,
        outroSeconds: (json['outro'] as num?)?.toInt() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is SkipConfig &&
      other.introSeconds == introSeconds &&
      other.outroSeconds == outroSeconds;

  @override
  int get hashCode => Object.hash(introSeconds, outroSeconds);
}
