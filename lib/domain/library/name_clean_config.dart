import 'dart:convert';

enum BuiltinNoiseRule {
  latinBracketTags,
  resolution,
  codecSource,
  year,
  url,
}

class NameCleanConfig {
  const NameCleanConfig({
    required this.enabledBuiltinRules,
    required this.customSnippets,
  });

  final Set<BuiltinNoiseRule> enabledBuiltinRules;
  final List<String> customSnippets;

  static const NameCleanConfig defaults = NameCleanConfig(
    enabledBuiltinRules: {
      BuiltinNoiseRule.latinBracketTags,
      BuiltinNoiseRule.resolution,
      BuiltinNoiseRule.codecSource,
      BuiltinNoiseRule.year,
      BuiltinNoiseRule.url,
    },
    customSnippets: <String>[],
  );

  NameCleanConfig copyWith({
    Set<BuiltinNoiseRule>? enabledBuiltinRules,
    List<String>? customSnippets,
  }) {
    return NameCleanConfig(
      enabledBuiltinRules: enabledBuiltinRules ?? this.enabledBuiltinRules,
      customSnippets: customSnippets ?? this.customSnippets,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabledBuiltinRules':
            enabledBuiltinRules.map((r) => r.name).toList(),
        'customSnippets': customSnippets,
      };

  factory NameCleanConfig.fromJson(Map<String, dynamic> json) {
    final names = (json['enabledBuiltinRules'] as List?)?.cast<String>() ??
        const <String>[];
    final rules = <BuiltinNoiseRule>{};
    for (final name in names) {
      for (final r in BuiltinNoiseRule.values) {
        if (r.name == name) rules.add(r);
      }
    }
    final snippets =
        (json['customSnippets'] as List?)?.cast<String>() ?? const <String>[];
    return NameCleanConfig(
      enabledBuiltinRules: rules,
      customSnippets: List<String>.from(snippets),
    );
  }

  String encode() => jsonEncode(toJson());

  factory NameCleanConfig.decode(String source) {
    try {
      return NameCleanConfig.fromJson(
          jsonDecode(source) as Map<String, dynamic>);
    } catch (_) {
      return defaults;
    }
  }
}
