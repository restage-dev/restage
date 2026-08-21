import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _reviewedRfwVersion = '1.1.3';
const _reviewedRfwArchiveSha256 =
    '97b3a1d07b21583c7bafa3c848757e07e81a6a10a04871f82557ff4a0252ad86';
const _reviewedRfwRepository =
    'https://github.com/flutter/packages/tree/main/packages/rfw';
const _reviewedRfwEventHandlerPath = 'lib/src/flutter/remote_widget.dart';
const _reviewedRfwPackageName = 'rfw';

void main() {
  late _ResolvedRfwSource resolvedRfw;

  setUpAll(() {
    resolvedRfw = _resolveReviewedRfwSource();
  });

  test('the workspace lock and hosted cache identify the reviewed RFW pin', () {
    final lockEntry = resolvedRfw.lockEntry;
    expect(lockEntry, contains('    source: hosted\n'));
    expect(lockEntry, contains('      name: rfw\n'));
    expect(
      lockEntry,
      contains('      sha256: "$_reviewedRfwArchiveSha256"\n'),
    );
    expect(lockEntry, contains('      url: "https://pub.dev"\n'));
    expect(
      lockEntry,
      contains('    version: "$_reviewedRfwVersion"\n'),
    );
    expect(resolvedRfw.hostedCacheSha256, _reviewedRfwArchiveSha256);
  });

  test(
    'the RFW event-handler source is the resolved hosted package source',
    () {
      expect(
        _topLevelYamlScalar(resolvedRfw.packagePubspec, 'name'),
        _reviewedRfwPackageName,
      );
      expect(
        _topLevelYamlScalar(resolvedRfw.packagePubspec, 'version'),
        _reviewedRfwVersion,
      );
      expect(
        _topLevelYamlScalar(resolvedRfw.packagePubspec, 'repository'),
        _reviewedRfwRepository,
      );
      expect(resolvedRfw.eventHandlerSourcePath, _reviewedRfwEventHandlerPath);
      expect(
        resolvedRfw.eventHandlerFile.existsSync(),
        isTrue,
        reason: 'The source file must be the file resolved from package:rfw.',
      );
    },
  );

  test('RemoteWidget forwards both event values directly before the host', () {
    final source = resolvedRfw.eventHandlerFile.readAsStringSync();
    final tokens = _tokenizeDart(source);
    final signature = <String>[
      'void',
      '_eventHandler',
      '(',
      'String',
      'eventName',
      ',',
      'DynamicMap',
      'eventArguments',
      ')',
      '{',
    ];
    final matches = <int>[];
    for (var index = 0; index <= tokens.length - signature.length; index++) {
      var matchesSignature = true;
      for (var offset = 0; offset < signature.length; offset++) {
        if (tokens[index + offset].text != signature[offset]) {
          matchesSignature = false;
          break;
        }
      }
      if (matchesSignature) matches.add(index);
    }

    expect(
      matches,
      hasLength(1),
      reason: 'The resolved RFW source must retain one recognizable '
          'RemoteWidget._eventHandler declaration.',
    );

    final openingBraceIndex = matches.single + signature.length - 1;
    final closingBraceIndex = _matchingBraceIndex(tokens, openingBraceIndex);
    final methodTokens = tokens
        .sublist(openingBraceIndex, closingBraceIndex + 1)
        .map((token) => token.text)
        .toList(growable: false);

    expect(
      methodTokens,
      orderedEquals(const <String>[
        '{',
        'if',
        '(',
        'widget',
        '.',
        'onEvent',
        '!=',
        'null',
        ')',
        '{',
        'widget',
        '.',
        'onEvent',
        '!',
        '(',
        'eventName',
        ',',
        'eventArguments',
        ')',
        ';',
        '}',
        '}',
      ]),
      reason:
          'The pinned upstream handler must have no logging, serialization, '
          'mutation, retention, or callback before the repository host.',
    );
  });
}

class _ResolvedRfwSource {
  const _ResolvedRfwSource({
    required this.lockEntry,
    required this.hostedCacheSha256,
    required this.packagePubspec,
    required this.eventHandlerFile,
    required this.eventHandlerSourcePath,
  });

  final String lockEntry;
  final String hostedCacheSha256;
  final String packagePubspec;
  final File eventHandlerFile;
  final String eventHandlerSourcePath;
}

_ResolvedRfwSource _resolveReviewedRfwSource() {
  final workspaceRoot = _findWorkspaceRoot();
  final lockFile = File('${workspaceRoot.path}/pubspec.lock');
  if (!lockFile.existsSync()) {
    throw StateError(
      'The RFW leakage gate could not find the workspace pubspec.lock at '
      '${lockFile.path}. Run melos bootstrap or flutter pub get from '
      'the workspace root before running this gate.',
    );
  }
  final lockEntry = _findLockEntry(
    lockFile.readAsStringSync(),
    packageName: _reviewedRfwPackageName,
  );

  final packageConfigFile = File(
    '${workspaceRoot.path}/.dart_tool/package_config.json',
  );
  final sourceUri = _resolveRfwSourceUri(packageConfigFile);

  final eventHandlerFile = File.fromUri(sourceUri);
  if (!eventHandlerFile.existsSync()) {
    throw StateError(
      'The RFW leakage gate resolved '
      'package:rfw/src/flutter/remote_widget.dart to '
      '${eventHandlerFile.path}, but that file is missing. Restore the '
      'resolved hosted package with melos bootstrap or flutter pub get; do '
      'not skip this gate.',
    );
  }

  final packageRoot = _findPackageRoot(eventHandlerFile);
  if (packageRoot == null) {
    throw StateError(
      'The RFW leakage gate could not find the rfw package root above '
      '${eventHandlerFile.path}. The package source must be available '
      'from the active package config; run melos bootstrap or flutter pub '
      'get.',
    );
  }

  final canonicalPackageRoot = Directory(
    packageRoot.resolveSymbolicLinksSync(),
  );
  final canonicalEventHandlerFile = File(
    eventHandlerFile.resolveSymbolicLinksSync(),
  );
  final expectedEventHandlerFile = File(
    '${canonicalPackageRoot.path}/$_reviewedRfwEventHandlerPath',
  );
  if (!expectedEventHandlerFile.existsSync() ||
      canonicalEventHandlerFile.path !=
          expectedEventHandlerFile.resolveSymbolicLinksSync()) {
    throw StateError(
      'The RFW leakage gate resolved an unexpected source location: '
      '${canonicalEventHandlerFile.path}. Expected the reviewed hosted '
      'package file at ${expectedEventHandlerFile.path}. This gate '
      'does not accept copied fixtures or alternate package sources.',
    );
  }

  final rootSegments = canonicalPackageRoot.uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  if (rootSegments.length < 3 ||
      rootSegments[rootSegments.length - 1] !=
          '$_reviewedRfwPackageName-$_reviewedRfwVersion' ||
      rootSegments[rootSegments.length - 2] != 'pub.dev' ||
      rootSegments[rootSegments.length - 3] != 'hosted') {
    throw StateError(
      'The RFW leakage gate resolved source outside the deterministic hosted '
      'cache identity hosted/pub.dev/$_reviewedRfwPackageName-'
      '$_reviewedRfwVersion: ${canonicalPackageRoot.path}. Ensure '
      'CI runs melos bootstrap or flutter pub get with the locked hosted '
      'package.',
    );
  }

  final cacheRoot = canonicalPackageRoot.parent.parent.parent;
  final hostedHashFile = File(
    '${cacheRoot.path}/hosted-hashes/pub.dev/'
    '$_reviewedRfwPackageName-$_reviewedRfwVersion.sha256',
  );
  if (!hostedHashFile.existsSync()) {
    throw StateError(
      'The RFW leakage gate could not find Pub provenance metadata at '
      '${hostedHashFile.path}. Restore the hosted package with flutter '
      'pub get or melos bootstrap so CI can verify the locked archive hash.',
    );
  }

  return _ResolvedRfwSource(
    lockEntry: lockEntry,
    hostedCacheSha256: hostedHashFile.readAsStringSync().trim(),
    packagePubspec: File(
      '${canonicalPackageRoot.path}/pubspec.yaml',
    ).readAsStringSync(),
    eventHandlerFile: canonicalEventHandlerFile,
    eventHandlerSourcePath: _reviewedRfwEventHandlerPath,
  );
}

Uri _resolveRfwSourceUri(File packageConfigFile) {
  if (!packageConfigFile.existsSync()) {
    throw StateError(
      'The RFW leakage gate could not find the active package config at '
      '${packageConfigFile.path}. Run melos bootstrap or flutter pub '
      'get in this checkout; do not add a copied RFW fixture.',
    );
  }

  late final dynamic decoded;
  try {
    decoded = jsonDecode(packageConfigFile.readAsStringSync());
  } on Object catch (error) {
    throw StateError(
      'The RFW leakage gate could not parse the active package config at '
      '${packageConfigFile.path}: ${error.toString()}. Regenerate it with '
      'melos bootstrap or flutter pub get.',
    );
  }
  if (decoded is! Map<String, dynamic> || decoded['packages'] is! List) {
    throw StateError(
      'The RFW leakage gate found an invalid package config at '
      '${packageConfigFile.path}. Regenerate it with melos bootstrap '
      'or flutter pub get.',
    );
  }

  final matches = (decoded['packages'] as List)
      .whereType<Map<String, dynamic>>()
      .where((entry) => entry['name'] == _reviewedRfwPackageName)
      .toList(growable: false);
  if (matches.length != 1) {
    throw StateError(
      'The RFW leakage gate expected exactly one rfw package in '
      '${packageConfigFile.path}, found ${matches.length}. '
      'Regenerate the package config with melos bootstrap or flutter pub '
      'get.',
    );
  }

  final entry = matches.single;
  final rootUriText = entry['rootUri'];
  final packageUriText = entry['packageUri'];
  if (rootUriText is! String || packageUriText is! String) {
    throw StateError(
      'The rfw package entry in ${packageConfigFile.path} has no usable '
      'rootUri/packageUri. Regenerate it with melos bootstrap or flutter '
      'pub get.',
    );
  }

  final rootUri = packageConfigFile.uri.resolve(rootUriText);
  final packageUri = _directoryUri(rootUri).resolve(packageUriText);
  final sourceUri = _directoryUri(packageUri).resolve(
    'src/flutter/remote_widget.dart',
  );
  if (sourceUri.scheme != 'file') {
    throw StateError(
      'The RFW package config resolves the event-handler source to a non-file '
      'URI: ${sourceUri.toString()}. Restore a hosted package resolution with '
      'melos bootstrap or flutter pub get.',
    );
  }
  return sourceUri;
}

Uri _directoryUri(Uri uri) {
  if (uri.path.endsWith('/')) return uri;
  return uri.replace(path: '${uri.path}/');
}

Directory _findWorkspaceRoot() {
  var directory = Directory.current.absolute;
  while (true) {
    final pubspec = File('${directory.path}/pubspec.yaml');
    final lockFile = File('${directory.path}/pubspec.lock');
    if (pubspec.existsSync() &&
        lockFile.existsSync() &&
        _topLevelYamlScalar(pubspec.readAsStringSync(), 'name') ==
            'restage_workspace') {
      return directory;
    }

    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }

  throw StateError(
    'The RFW leakage gate could not locate the Restage workspace root from '
    '${Directory.current.path}. Run this test from a workspace package '
    'after melos bootstrap or flutter pub get.',
  );
}

String _findLockEntry(String lockfile, {required String packageName}) {
  final matches = RegExp(
    '^  $packageName:\\n(?:(?!^  \\S).)*',
    multiLine: true,
    dotAll: true,
  ).allMatches(lockfile).toList(growable: false);
  if (matches.length != 1) {
    throw StateError(
      'The RFW leakage gate expected exactly one $packageName entry in '
      'the workspace pubspec.lock, found $matches.length. Regenerate '
      'the workspace resolution with melos bootstrap and inspect the '
      'lockfile.',
    );
  }
  return matches.single.group(0)!;
}

Directory? _findPackageRoot(File sourceFile) {
  var directory = sourceFile.parent;
  while (true) {
    final pubspec = File('${directory.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        _topLevelYamlScalar(pubspec.readAsStringSync(), 'name') ==
            _reviewedRfwPackageName) {
      return directory;
    }

    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}

String? _topLevelYamlScalar(String source, String key) {
  for (final line in source.split('\n')) {
    if (!line.startsWith('$key:')) continue;
    var value = line.substring(key.length + 1).trim();
    if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
      value = value.substring(1, value.length - 1);
    } else if (value.startsWith("'") &&
        value.endsWith("'") &&
        value.length >= 2) {
      value = value.substring(1, value.length - 1);
    }
    return value;
  }
  return null;
}

int _matchingBraceIndex(List<_DartToken> tokens, int openingBraceIndex) {
  var depth = 0;
  for (var index = openingBraceIndex; index < tokens.length; index++) {
    final token = tokens[index].text;
    if (token == '{') depth++;
    if (token != '}') continue;
    depth--;
    if (depth == 0) return index;
  }
  throw StateError(
    'The RFW leakage gate found an event-handler opening brace without a '
    'matching closing brace in the resolved source.',
  );
}

List<_DartToken> _tokenizeDart(String source) {
  final tokens = <_DartToken>[];
  var index = 0;
  while (index < source.length) {
    final codeUnit = source.codeUnitAt(index);
    if (_isWhitespace(codeUnit)) {
      index++;
      continue;
    }

    if (codeUnit == 0x2f && index + 1 < source.length) {
      final next = source.codeUnitAt(index + 1);
      if (next == 0x2f) {
        index += 2;
        while (index < source.length && source.codeUnitAt(index) != 0x0a) {
          index++;
        }
        continue;
      }
      if (next == 0x2a) {
        final end = source.indexOf('*/', index + 2);
        if (end < 0) {
          throw StateError(
            'The RFW leakage gate found an unterminated block comment in '
            'the resolved source.',
          );
        }
        index = end + 2;
        continue;
      }
    }

    if (codeUnit == 0x22 || codeUnit == 0x27) {
      final end = _quotedStringEnd(source, index);
      tokens.add(_DartToken('<string>'));
      index = end;
      continue;
    }

    if (_isIdentifierStart(codeUnit)) {
      var end = index + 1;
      while (end < source.length && _isIdentifierPart(source.codeUnitAt(end))) {
        end++;
      }
      tokens.add(_DartToken(source.substring(index, end)));
      index = end;
      continue;
    }

    if (_isDigit(codeUnit)) {
      var end = index + 1;
      while (end < source.length &&
          (_isIdentifierPart(source.codeUnitAt(end)) ||
              source.codeUnitAt(end) == 0x2e)) {
        end++;
      }
      tokens.add(_DartToken(source.substring(index, end)));
      index = end;
      continue;
    }

    final operator = _operatorAt(source, index);
    tokens.add(_DartToken(operator));
    index += operator.length;
  }
  return tokens;
}

String _operatorAt(String source, int index) {
  for (final operator in const <String>[
    '>>>=',
    '??=',
    '>>>',
    '...',
    '?.',
    '..',
    '=>',
    '!=',
    '==',
    '<=',
    '>=',
    '&&',
    '||',
    '++',
    '--',
    '+=',
    '-=',
    '*=',
    '/=',
    '%=',
    '<<',
    '>>',
  ]) {
    if (source.startsWith(operator, index)) return operator;
  }
  return source[index];
}

int _quotedStringEnd(String source, int openingIndex) {
  final quote = source.codeUnitAt(openingIndex);
  final raw = openingIndex > 0 &&
      (source.codeUnitAt(openingIndex - 1) == 0x72 ||
          source.codeUnitAt(openingIndex - 1) == 0x52);
  final triple = openingIndex + 2 < source.length &&
      source.codeUnitAt(openingIndex + 1) == quote &&
      source.codeUnitAt(openingIndex + 2) == quote;
  var index = openingIndex + (triple ? 3 : 1);
  while (index < source.length) {
    if (!raw && source.codeUnitAt(index) == 0x5c) {
      index += 2;
      continue;
    }
    if (source.codeUnitAt(index) != quote) {
      index++;
      continue;
    }
    if (triple) {
      if (index + 2 < source.length &&
          source.codeUnitAt(index + 1) == quote &&
          source.codeUnitAt(index + 2) == quote) {
        return index + 3;
      }
      index++;
      continue;
    }
    return index + 1;
  }
  throw StateError(
    'The RFW leakage gate found an unterminated string in the resolved '
    'source.',
  );
}

bool _isWhitespace(int codeUnit) =>
    codeUnit == 0x09 ||
    codeUnit == 0x0a ||
    codeUnit == 0x0d ||
    codeUnit == 0x20;

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

bool _isIdentifierStart(int codeUnit) =>
    codeUnit == 0x24 ||
    codeUnit == 0x5f ||
    (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
    (codeUnit >= 0x61 && codeUnit <= 0x7a);

bool _isIdentifierPart(int codeUnit) =>
    _isIdentifierStart(codeUnit) || _isDigit(codeUnit);

class _DartToken {
  const _DartToken(this.text);

  final String text;
}
