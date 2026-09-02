import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory repository;
  late List<File> publicSources;

  setUpAll(() {
    repository = _repositoryRoot();
    publicSources = <File>[
      ..._dartFiles(Directory('${repository.path}/packages/restage/lib')),
      ..._dartFiles(
        Directory('${repository.path}/packages/restage_shared/lib'),
      ),
    ];

    expect(publicSources, isNotEmpty);
  });

  test('deleted assignment declarations stay absent from public libraries', () {
    final offenders = <String>[];
    for (final file in publicSources) {
      final source = file.readAsStringSync();
      if (file.path == _surfaceResponseParserPath(repository)) {
        _assertRequiredFence(
          source,
          _surfaceResponseFence,
          file.path,
        );
      } else if (file.path == _analyticsParserPath(repository)) {
        _assertRequiredFence(
          source,
          _analyticsFieldFence,
          file.path,
        );
      } else if (file.path == _analyticsReservedKeysPath(repository)) {
        _assertRequiredFence(
          source,
          _analyticsReservedKeysFence,
          file.path,
        );
      }

      for (final forbidden in _retiredPublicIdentifiers) {
        for (final match
            in RegExp('\\b${RegExp.escape(forbidden)}\\b').allMatches(source)) {
          if (!_isAllowedRefusalFenceOccurrence(
            file.path,
            source,
            match,
            forbidden,
            repository,
          )) {
            offenders.add('${file.path}: $forbidden');
          }
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('the production fences are present and allow only key strings', () {
    final responseSource =
        File(_surfaceResponseParserPath(repository)).readAsStringSync();
    final analyticsSource =
        File(_analyticsParserPath(repository)).readAsStringSync();
    final reservedKeysSource =
        File(_analyticsReservedKeysPath(repository)).readAsStringSync();

    _assertResponseFenceKeys(responseSource);
    _assertAnalyticsFenceKeys(analyticsSource);
    _assertReservedPropertyKeys(reservedKeysSource);
  });

  test('each production key is covered by a source mutation', () {
    final responseSource =
        File(_surfaceResponseParserPath(repository)).readAsStringSync();
    final analyticsSource =
        File(_analyticsParserPath(repository)).readAsStringSync();
    final reservedKeysSource =
        File(_analyticsReservedKeysPath(repository)).readAsStringSync();

    for (final key in _retiredResponseKeys) {
      final mutated = responseSource.replaceFirst(
        "json.containsKey('$key')",
        '',
      );
      expect(mutated, isNot(equals(responseSource)));
      expect(
        () => _assertResponseFenceKeys(mutated),
        throwsA(isA<TestFailure>()),
        reason: 'response fence mutation for $key was not detected',
      );
    }
    for (final key in _retiredAnalyticsKeys) {
      final mutated = analyticsSource.replaceFirst("'$key',", '');
      expect(mutated, isNot(equals(analyticsSource)));
      expect(
        () => _assertAnalyticsFenceKeys(mutated),
        throwsA(isA<TestFailure>()),
        reason: 'analytics fence mutation for $key was not detected',
      );
    }
    for (final key in _retiredAnalyticsKeys) {
      final mutated = reservedKeysSource.replaceFirst("'$key',", '');
      expect(mutated, isNot(equals(reservedKeysSource)));
      expect(
        () => _assertReservedPropertyKeys(mutated),
        throwsA(isA<TestFailure>()),
        reason: 'reserved property mutation for $key was not detected',
      );
    }
  });

  test('the identifier boundary does not reject experimentEpochId', () {
    expect(
      _forbiddenMatches('experimentEpochId'),
      isEmpty,
      reason: 'the current Measurement epoch identifier is not retired',
    );
    expect(_forbiddenMatches('experimentEpoch'), hasLength(1));
  });

  test('the guard rejects an injected retired identifier', () {
    final temporary = Directory.systemTemp.createTempSync(
      'restage-removed-experiment-assignment-wire-fence-',
    );
    try {
      final injected = File('${temporary.path}/injected.dart')
        ..writeAsStringSync('final FlowAssignment value;');
      expect(_scanForRetiredIdentifiers([injected]), isNotEmpty);
    } finally {
      temporary.deleteSync(recursive: true);
    }
  });
}

const _retiredPublicIdentifiers = <String>[
  'SurfaceExperimentAssignment',
  'FlowAssignment',
  'experimentId',
  'variantId',
  'experimentEpoch',
];

const _retiredResponseKeys = <String>[
  'decision',
  'experimentId',
  'variantId',
  'experimentEpoch',
];

const _retiredAnalyticsKeys = <String>[
  'experimentId',
  'variantId',
  'experimentEpoch',
];

const _surfaceResponseFenceLines = <String>{
  "return json.containsKey('decision') ||",
  "json.containsKey('experimentId') ||",
  "json.containsKey('variantId') ||",
  "json.containsKey('experimentEpoch');",
};

final _surfaceResponseFence = RegExp(
  r'''^  bool _containsRetiredSurfaceResponseField\(Map<String, dynamic> json\) \{.*?^  \}\n''',
  multiLine: true,
  dotAll: true,
);

final _analyticsFieldFence = RegExp(
  r'''^const _unsupportedTopLevelFields = <String>\{\n.*?^\};\n''',
  multiLine: true,
  dotAll: true,
);

final _analyticsReservedKeysFence = RegExp(
  r'''^const Set<String> kReservedPropertyKeys = <String>\{\n.*?^\};\n''',
  multiLine: true,
  dotAll: true,
);

String _surfaceResponseParserPath(Directory root) =>
    '${root.path}/packages/restage/lib/src/restage_rpc_client/restage_rpc_client.dart';

String _analyticsParserPath(Directory root) =>
    '${root.path}/packages/restage_shared/lib/src/legacy_analytics/analytics_event.dart';

String _analyticsReservedKeysPath(Directory root) =>
    '${root.path}/packages/restage_shared/lib/src/legacy_analytics/analytics_reserved_keys.dart';

void _assertRequiredFence(String source, RegExp fence, String path) {
  expect(
    fence.allMatches(source).length,
    1,
    reason: 'expected one refusal fence in $path',
  );
}

bool _isAllowedRefusalFenceOccurrence(
  String path,
  String source,
  RegExpMatch match,
  String identifier,
  Directory repository,
) {
  final line = _lineContaining(source, match.start);
  if (path == _surfaceResponseParserPath(repository)) {
    final fence = _surfaceResponseFence.firstMatch(source);
    return fence != null &&
        match.start >= fence.start &&
        match.end <= fence.end &&
        _surfaceResponseFenceLines.contains(line);
  }
  if (path == _analyticsParserPath(repository)) {
    final fence = _analyticsFieldFence.firstMatch(source);
    return fence != null &&
        match.start >= fence.start &&
        match.end <= fence.end &&
        line == "'$identifier'," &&
        _retiredAnalyticsKeys.contains(identifier);
  }
  if (path == _analyticsReservedKeysPath(repository)) {
    final fence = _analyticsReservedKeysFence.firstMatch(source);
    return fence != null &&
        match.start >= fence.start &&
        match.end <= fence.end &&
        line == "'$identifier'," &&
        _retiredAnalyticsKeys.contains(identifier);
  }
  return false;
}

String _lineContaining(String source, int offset) {
  final lineStart = source.lastIndexOf('\n', offset - 1) + 1;
  final nextNewline = source.indexOf('\n', offset);
  final lineEnd = nextNewline == -1 ? source.length : nextNewline;
  return source.substring(lineStart, lineEnd).trim();
}

void _assertResponseFenceKeys(String source) {
  for (final key in _retiredResponseKeys) {
    expect(
      source,
      contains("json.containsKey('$key')"),
      reason: 'surface response fence does not reject $key',
    );
  }
}

void _assertAnalyticsFenceKeys(String source) {
  for (final key in _retiredAnalyticsKeys) {
    expect(
      source,
      contains("'$key'"),
      reason: 'analytics decoder fence does not reject $key',
    );
  }
}

void _assertReservedPropertyKeys(String source) {
  final fence = _analyticsReservedKeysFence.firstMatch(source)?.group(0) ?? '';
  for (final key in _retiredAnalyticsKeys) {
    expect(
      fence,
      contains("'$key',"),
      reason: 'reserved property scrub does not remove $key',
    );
  }
}

List<String> _forbiddenMatches(String source) => [
      for (final identifier in _retiredPublicIdentifiers)
        if (RegExp('\\b${RegExp.escape(identifier)}\\b').hasMatch(source))
          identifier,
    ];

List<String> _scanForRetiredIdentifiers(Iterable<File> files) => [
      for (final file in files)
        for (final identifier in _forbiddenMatches(file.readAsStringSync()))
          '${file.path}: $identifier',
    ];

Iterable<File> _dartFiles(Directory directory) => directory
    .listSync(recursive: true, followLinks: false)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

Directory _repositoryRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    if (File('${directory.path}/packages/restage/pubspec.yaml').existsSync()) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not locate the repository root.');
    }
    directory = parent;
  }
}
