import 'package:meta/meta.dart';

/// Portable generated files that Restage's starter configuration does not
/// track by default.
const List<String> restagePortableOutputIgnorePatterns = <String>[
  '*.rsbundle',
  '*.restage.md',
  'restage.outputs.json',
  'restage.publication.json',
  'restage_a2ui_catalog.a2ui.json',
];

const String _portableOutputHeader =
    '# Restage portable generated output. Remove or negate individual rules '
    'to track it.';
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
  final present = <String>{};
  for (final line in source.split(_lineBreak)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    final rule = trimmed.startsWith('!')
        ? trimmed.substring(1).trim()
        : trimmed;
    if (restagePortableOutputIgnorePatterns.contains(rule)) {
      present.add(rule);
    }
  }

  final missing = <String>[
    for (final pattern in restagePortableOutputIgnorePatterns)
      if (!present.contains(pattern)) pattern,
  ];
  if (missing.isEmpty || _hasPortableOutputHeader(source)) {
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

bool _hasPortableOutputHeader(String source) {
  return source
      .split(_lineBreak)
      .any((line) => line.trim() == _portableOutputHeader);
}

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
