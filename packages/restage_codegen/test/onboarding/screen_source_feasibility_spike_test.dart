import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('ScreenSource can reuse normalized constructor facts', () async {
    final facts = await runWidgetConstructorFactsOn({
      'lib/onboarding/screens/probe.dart': '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'probe')
class Probe extends StatelessWidget {
  const Probe({super.key, required this.title, this.enabled = true});

  final String title;
  final bool enabled;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''',
    });

    expect(facts.issues, hasLength(2));
    expect(
      facts.issues.map((issue) => issue.code),
      everyElement(IssueCode.constructorCatalogMigration),
    );
    expect(
      facts.inputs.map((input) => input.name),
      <String>['title', 'enabled'],
    );
    expect(facts.inputs.first.required, isTrue);
    expect(facts.inputs.last.required, isFalse);
    expect(
      facts.inputs.last.constructorDefault,
      isA<LiteralWidgetConstructorDefault>().having(
        (fact) => fact.value,
        'value',
        isTrue,
      ),
    );
  });

  test('dual source annotations are currently admitted independently',
      () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@ScreenSource(id: 'dual')
@RestageWidget(
  name: 'dual',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.layout,
  description: 'A dual-annotation probe.',
)
class DualScreen extends StatelessWidget {
  const DualScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final screens = await runOnboardingVisitorOn({'lib/dual.dart': source});
    final widgets = await runWidgetVisitorOn({'lib/dual.dart': source});

    expect(screens.issues, isEmpty);
    expect(widgets.issues, isEmpty);
    expect(screens.sources.single.id, 'dual');
    expect(widgets.widgets.single.name, 'dual');
  });

  test('duplicate screen IDs in separate libraries escape visitor diagnostics',
      () async {
    String source(String className) => '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

@ScreenSource(id: 'duplicate')
class $className extends StatelessWidget {
  const $className({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

    final result = await runOnboardingVisitorOn({
      'lib/first.dart': source('FirstScreen'),
      'lib/second.dart': source('SecondScreen'),
    });

    expect(result.issues, isEmpty);
    expect(result.sources.map((screen) => screen.id), <String>[
      'duplicate',
      'duplicate',
    ]);
  });
}
