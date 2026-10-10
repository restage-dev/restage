import 'package:meta/meta.dart';

/// Portable generated files that Restage's starter configuration does not
/// track by default. The final negation keeps bundled app assets tracked.
const List<String> restagePortableOutputIgnorePatterns = <String>[
  '.restage/build/',
  '*.rsbundle',
  '*.restage.md',
  'restage.outputs.json',
  'restage.publication.json',
  'restage_a2ui_catalog.a2ui.json',
  '!$restageBundledAssetsPattern',
];

/// Bundled runtime assets, which the app ships and the repository tracks.
const String restageBundledAssetsPattern = 'assets/restage/bundles/**';

// Earlier generated headers, each with the rules it already wrote. Rules added
// since are appended; rules it wrote and the user removed stay removed.
const Map<String, List<String>> _earlierHeaders = <String, List<String>>{
  '# Restage portable generated output. Remove or negate individual rules '
      'to track it.': <String>[
    '*.rsbundle',
    '*.restage.md',
    'restage.outputs.json',
    'restage.publication.json',
    'restage_a2ui_catalog.a2ui.json',
  ],
  '# Restage portable generated output. Build cache and portable artifacts; '
      'remove or negate individual rules to track them.': <String>[
    '.restage/build/',
    '*.rsbundle',
    '*.restage.md',
    'restage.outputs.json',
    'restage.publication.json',
    'restage_a2ui_catalog.a2ui.json',
  ],
};

const String _portableOutputHeader =
    '# Restage build output (bundled surfaces under assets/restage/bundles/ '
    'stay tracked)';
final _lineBreak = RegExp(r'\r?\n');

/// The result of planning an update to a project's `.gitignore`.
@immutable
class PortableOutputIgnorePlan {
  /// Construct a plan.
  const PortableOutputIgnorePlan({
    required this.source,
    required this.addedPatterns,
  });

  /// The original source when no update is needed, or the updated source.
  final String source;

  /// Rules added by the plan. An explicit negation counts as an existing rule.
  final List<String> addedPatterns;

  /// Whether applying this plan leaves the file unchanged.
  bool get isNoOp => addedPatterns.isEmpty;
}

/// Plans the portable-output rules for a project's `.gitignore`.
///
/// Existing content is never rewritten. Positive and explicit negated rules
/// both count as intentional user handling of a pattern. Once the generated
/// Restage section exists, a missing rule is treated as a deliberate deletion,
/// so a later `restage init` cannot undo a team's tracking choice.
PortableOutputIgnorePlan planPortableOutputIgnores(String source) {
  final lines = [for (final line in source.split(_lineBreak)) line.trim()];
  final present = <String>{
    for (final line in lines)
      if (line.isNotEmpty && !line.startsWith('#')) _ruleBody(line),
  };
  final written = <String>{
    if (lines.contains(_portableOutputHeader))
      ...restagePortableOutputIgnorePatterns,
    for (final MapEntry(key: header, value: rules) in _earlierHeaders.entries)
      if (lines.contains(header)) ...rules,
  };

  final missing = <String>[
    for (final pattern in restagePortableOutputIgnorePatterns)
      if (!present.contains(_ruleBody(pattern)) && !written.contains(pattern))
        pattern,
  ];
  if (missing.isEmpty) {
    return PortableOutputIgnorePlan(
      source: source,
      addedPatterns: const <String>[],
    );
  }

  final lineEnding = _lineEndingFor(source);
  final block = <String>[_portableOutputHeader, ...missing].join(lineEnding);
  return PortableOutputIgnorePlan(
    source: '$source${_separatorFor(source, lineEnding)}$block$lineEnding',
    addedPatterns: List<String>.unmodifiable(missing),
  );
}

String _ruleBody(String rule) =>
    rule.startsWith('!') ? rule.substring(1).trim() : rule;

String _lineEndingFor(String source) {
  final crlfCount = '\r\n'.allMatches(source).length;
  final lfCount = RegExp(r'(?<!\r)\n').allMatches(source).length;
  if (crlfCount > lfCount) return '\r\n';
  return '\n';
}

String _separatorFor(String source, String lineEnding) {
  if (source.isEmpty) return '';
  if (source.endsWith('\n\n') || source.endsWith('\r\n\r\n')) return '';
  if (source.endsWith('\n') || source.endsWith('\r')) return lineEnding;
  return '$lineEnding$lineEnding';
}
