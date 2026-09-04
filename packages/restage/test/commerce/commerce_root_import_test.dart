import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _facadeSymbol = 'RestageCommerce';
const _commerceDataSymbols = <String>{
  'CommerceActionResult',
  'CommerceActionStatusCode',
  'CommerceAvailability',
  'CommerceAvailabilityRequest',
  'CommerceCapabilityCode',
  'CommercePurchaserState',
  'CommercePurchaserStateStatusCode',
  'CommerceFailureCode',
  'CommerceOfferId',
  'CommercePurchaseRequest',
  'CommerceRefreshRequest',
  'CommerceRequest',
  'CommerceResponse',
  'CommerceRestoreRequest',
};
const _probedSymbols = <String>{_facadeSymbol, ..._commerceDataSymbols};
const _expectedRootSymbols = <String>{_facadeSymbol};

void main() {
  test(
    'root exports the commerce facade and no commerce data types',
    () async {
      final probe = await _compileNamespaceProbe(
        entrypoint: 'package:restage/restage.dart',
        fixtureStem: 'restage_root',
      );

      expect(probe.exitCode, isNot(0), reason: probe.rawOutcome);
      expect(
        probe.visibleSymbols,
        _expectedRootSymbols,
        reason: probe.rawOutcome,
      );
      expect(_matchesRootContract(probe.visibleSymbols), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'namespace fence rejects a known commerce data-type leak',
    () async {
      const leakedSymbol = 'CommerceActionResult';
      final probe = await _compileNamespaceProbe(
        entrypoint: 'root_with_leak.fixture.dart',
        fixtureStem: 'known_leak',
        supportingSources: const <String, String>{
          'root_with_leak.fixture.dart': '''
export 'package:restage/restage.dart';
export 'package:restage/commerce.dart' show CommerceActionResult;
''',
        },
      );

      expect(probe.exitCode, isNot(0), reason: probe.rawOutcome);
      expect(
        probe.visibleSymbols,
        <String>{_facadeSymbol, leakedSymbol},
        reason: probe.rawOutcome,
      );
      expect(_matchesRootContract(probe.visibleSymbols), isFalse);
      expect(
        probe.visibleSymbols.difference(_expectedRootSymbols),
        const <String>{leakedSymbol},
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

bool _matchesRootContract(Set<String> visibleSymbols) =>
    visibleSymbols.length == _expectedRootSymbols.length &&
    visibleSymbols.containsAll(_expectedRootSymbols);

Future<_NamespaceProbe> _compileNamespaceProbe({
  required String entrypoint,
  required String fixtureStem,
  Map<String, String> supportingSources = const <String, String>{},
}) async {
  final packageRoot = Directory(
    Directory.current.absolute.resolveSymbolicLinksSync(),
  );
  final packageConfig = _findPackageConfig(packageRoot);
  final fixtureDirectory = Directory(
    '${packageRoot.path}/test/commerce/generated_namespace_probe_${pid}_'
    '${DateTime.now().microsecondsSinceEpoch}',
  )..createSync(recursive: true);

  try {
    for (final source in supportingSources.entries) {
      File('${fixtureDirectory.path}/${source.key}').writeAsStringSync(
        source.value,
      );
    }
    final fixture = File(
      '${fixtureDirectory.path}/$fixtureStem.fixture.dart',
    )..writeAsStringSync(_probeSource(entrypoint));
    final outputPath = '${fixtureDirectory.path}/$fixtureStem.dill';

    final result = await Process.run(
      'dart',
      <String>[
        'compile',
        'kernel',
        '--verbosity=error',
        '--packages=${packageConfig.path}',
        '--output=$outputPath',
        fixture.path,
      ],
      workingDirectory: packageRoot.path,
    );
    final output = '${result.stdout}\n${result.stderr}';
    final missingSymbols = <String>{
      for (final symbol in _probedSymbols)
        if (_missingTypePattern(symbol).hasMatch(output)) symbol,
    };

    return _NamespaceProbe(
      visibleSymbols: _probedSymbols.difference(missingSymbols),
      exitCode: result.exitCode,
      rawOutcome: 'exitCode=${result.exitCode}\n$output',
    );
  } finally {
    if (fixtureDirectory.existsSync()) {
      fixtureDirectory.deleteSync(recursive: true);
    }
  }
}

File _findPackageConfig(Directory start) {
  var directory = start;
  while (true) {
    final candidate = File(
      '${directory.path}/.dart_tool/package_config.json',
    );
    if (candidate.existsSync()) return candidate;

    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not find .dart_tool/package_config.json');
    }
    directory = parent;
  }
}

RegExp _missingTypePattern(String symbol) => RegExp(
      "Type '(?:root\\.)?${RegExp.escape(symbol)}' not found",
    );

String _probeSource(String entrypoint) {
  final source = StringBuffer("import '$entrypoint' as root;\n\n");
  for (final symbol in _probedSymbols) {
    source.writeln('typedef Probe$symbol = root.$symbol;');
  }
  source.writeln('\nvoid main() {}');
  return source.toString();
}

final class _NamespaceProbe {
  const _NamespaceProbe({
    required this.visibleSymbols,
    required this.exitCode,
    required this.rawOutcome,
  });

  final Set<String> visibleSymbols;
  final int exitCode;
  final String rawOutcome;
}
