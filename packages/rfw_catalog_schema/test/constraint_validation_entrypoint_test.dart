import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('constraint value validation has one narrow toolchain entrypoint',
      () async {
    final broad = File('lib/rfw_catalog_schema.dart').readAsStringSync();
    final narrow = File('lib/constraint_validation.dart');

    expect(broad, isNot(contains('constraint_value_validation.dart')));
    expect(broad, isNot(contains('validateRestageConstraintValues')));
    expect(narrow.existsSync(), isTrue);
    expect(
      narrow.readAsStringSync(),
      contains('show validateRestageConstraintValues'),
    );

    final narrowCompile = await _compileProbe('''
import 'package:rfw_catalog_schema/constraint_validation.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

void main() {
  validateRestageConstraintValues(const RestageConstraints());
}
''');
    expect(narrowCompile.exitCode, 0, reason: narrowCompile.output);

    for (final barrel in <String>[
      'package:rfw_catalog_schema/rfw_catalog_schema.dart',
      'package:restage_shared/restage_shared.dart',
    ]) {
      final broadCompile = await _compileProbe('''
import '$barrel';

void main() {
  validateRestageConstraintValues(const RestageConstraints());
}
''');
      expect(broadCompile.exitCode, isNot(0), reason: barrel);
      expect(
        broadCompile.output,
        contains("Method not found: 'validateRestageConstraintValues'"),
        reason: barrel,
      );
    }
  });
}

Future<({int exitCode, String output})> _compileProbe(String source) async {
  final temporary = Directory.systemTemp.createTempSync(
    'restage_constraint_entrypoint_',
  );
  try {
    final probe = File('${temporary.path}/probe.dart')
      ..writeAsStringSync(source);
    final packageConfig =
        '${Directory.current.parent.parent.path}/.dart_tool/package_config.json';
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        '--packages=$packageConfig',
        probe.path,
      ],
    );
    return (
      exitCode: result.exitCode,
      output: '${result.stdout}${result.stderr}',
    );
  } finally {
    temporary.deleteSync(recursive: true);
  }
}
