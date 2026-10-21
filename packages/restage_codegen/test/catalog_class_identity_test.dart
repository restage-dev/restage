import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _package = 'apps_examples';

String _surface(
  String id,
  String body, {
  String imports = '',
  String declarations = '',
}) =>
    '''
$imports

class PaywallSource {
  const PaywallSource({required this.id});
  final String id;
}

$declarations

@PaywallSource(id: '$id')
class IdentitySurface extends StatelessWidget {
  const IdentitySurface();
  @override
  Widget build(BuildContext context) => $body;
}
''';

Future<({bool succeeded, String log, String? rfwText})> _compile(
  String id,
  String source, {
  bool includeDesignPackages = false,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: _package,
    includeFlutter: true,
    includeDesignPackages: includeDesignPackages,
  );
  final sourceId = AssetId(_package, 'lib/paywalls/$id.dart');
  readerWriter.testing.writeString(sourceId, source);
  final messages = <String>[];
  final result = await testBuilder(
    restageCodegenBuilder(BuilderOptions.empty),
    {sourceId.toString(): source},
    rootPackage: _package,
    readerWriter: readerWriter,
    onLog: (record) => messages.add(record.message),
    flattenOutput: true,
  );
  final textId = AssetId(_package, 'assets/paywalls/$id.rfwtxt');
  return (
    succeeded: result.succeeded,
    log: messages.join('\n'),
    rfwText: result.readerWriter.testing.exists(textId)
        ? result.readerWriter.testing.readString(textId)
        : null,
  );
}

void main() {
  for (final (name, library, construction) in [
    ('Opacity', 'package:flutter/widgets.dart', 'Opacity(opacity: 0.5)'),
    (
      'Chip',
      'package:flutter/material.dart',
      "Chip(label: const Text('Plan'))"
    ),
  ]) {
    test('an app class named $name never binds the Flutter widget', () async {
      final id = 'app_${name.toLowerCase()}';
      final result = await _compile(
        id,
        _surface(
          id,
          construction,
          imports: "import '$library' hide $name;",
          declarations: '''
            class $name extends StatelessWidget {
              const $name({this.opacity, this.label});
              final double? opacity;
              final Widget? label;
              @override
              Widget build(BuildContext context) => const SizedBox();
            }
          ''',
        ),
      );
      expect(
        result.rfwText ?? '',
        isNot(contains('$name(')),
        reason: result.log,
      );
      if (!result.succeeded) {
        expect(result.log, contains(name));
      }
    });
  }

  test('a resolved named constructor binds its base widget entry', () async {
    const id = 'positioned_fill';
    final result = await _compile(
      id,
      _surface(
        id,
        "Stack(children: [Positioned.fill(child: const Text('Fill'))])",
        imports: "import 'package:flutter/widgets.dart';",
      ),
    );
    expect(result.succeeded, isTrue, reason: result.log);
    expect(
      result.rfwText,
      allOf(
        contains('Positioned('),
        contains('left: 0.0'),
        contains('bottom: 0.0'),
      ),
    );
  });

  test('a design-package class binds its framework catalog entry', () async {
    const id = 'design_package_card';
    final result = await _compile(
      id,
      _surface(
        id,
        "Card(child: const Text('Plan'))",
        imports: "import 'package:material_ui/material_ui.dart';",
      ),
      includeDesignPackages: true,
    );
    expect(result.succeeded, isTrue, reason: result.log);
    expect(result.rfwText, contains('Card('));
  });
}
