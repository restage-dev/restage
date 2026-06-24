import 'dart:io';

import 'package:test/test.dart';

/// Packages the A2UI emit adapter must never import — the code generator
/// projects the A2UI catalog as plain maps, so the genui SDK dependency never
/// enters `restage_codegen` (the zero-leakage invariant). The genui dependency
/// lives only in the separate app-side runtime package.
const _forbiddenPackages = [
  'package:genui/',
  'package:genui_a2a/',
  'package:json_schema_builder/',
];

bool _isForbiddenImport(String line) {
  final trimmed = line.trimLeft();
  if (!trimmed.startsWith('import') && !trimmed.startsWith('export')) {
    return false;
  }
  return _forbiddenPackages.any(line.contains);
}

void main() {
  test('the forbidden-import matcher detects a genui import', () {
    // Proves the scan below is not a no-op.
    expect(_isForbiddenImport("import 'package:genui/genui.dart';"), isTrue);
    expect(
      _isForbiddenImport("import 'package:genui_a2a/genui_a2a.dart';"),
      isTrue,
    );
    expect(
      _isForbiddenImport(
        "export 'package:json_schema_builder/json_schema_builder.dart';",
      ),
      isTrue,
    );
    expect(
      _isForbiddenImport(
        "import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';",
      ),
      isFalse,
    );
    // A comment mentioning a package is not an import.
    expect(_isForbiddenImport('// see package:genui/ for the shape'), isFalse);
  });

  test('the A2UI emit adapter stays genui-import-free', () {
    final dir = Directory('lib/src/a2ui');
    expect(
      dir.existsSync(),
      isTrue,
      reason: 'the A2UI adapter directory must exist',
    );

    final offenders = <String>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final line in entity.readAsLinesSync()) {
        if (_isForbiddenImport(line)) {
          offenders.add('${entity.path}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'the emit adapter must not import the genui SDK — it emits the '
          'A2UI catalog as plain maps (zero-leakage invariant). Offenders: '
          '$offenders',
    );
  });

  test('restage_codegen declares no genui dependency in its pubspec', () {
    // The by-construction guard, stronger than the file-level scan: if the dep
    // is not declared, NO import — direct, transitive, or conditional — can
    // resolve, so the genui SDK cannot leak into the build-time toolchain at
    // all. The subtree line-scan above is a secondary defence against an
    // accidental relative reach into a genui-using file.
    final pubspec = File('pubspec.yaml');
    expect(pubspec.existsSync(), isTrue, reason: 'pubspec.yaml must exist');

    final forbiddenDep = RegExp(
      r'^\s*(genui|genui_a2a|json_schema_builder)\s*:',
      multiLine: true,
    );
    final declared = forbiddenDep
        .allMatches(pubspec.readAsStringSync())
        .map((m) => m.group(1))
        .toList();

    expect(
      declared,
      isEmpty,
      reason: 'restage_codegen (the build-time toolchain) must declare no '
          'genui/genui_a2a/json_schema_builder dependency. The emit adapter '
          'produces the A2UI catalog as plain maps; a declared dep would let '
          'an import resolve and leak the genui SDK into the toolchain. '
          'Found: $declared',
    );
  });
}
