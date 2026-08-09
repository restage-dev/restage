import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_catalog_source_index.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_plan.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_source_renderer.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _remediation =
    'Make the Dart default public, importable, and reconstructable; change the '
    'constructor contract (for example, to a safe nullable input without a '
    'non-null default); use a catalog-facing wrapper; or ignore the optional '
    'input where omission is semantically legal.';

const _source = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const _privateLabel = 'private';

@RestageWidget(
  name: 'PrivateDefaultCard',
  library: WidgetLibrary.custom('fixture.widgets'),
  category: WidgetCategory.decoration,
  description: 'Private-default card.',
)
class PrivateDefaultCard extends StatelessWidget {
  const PrivateDefaultCard({this.label = _privateLabel});

  @RestageProperty(description: 'Card label.')
  final String label;

  @override
  Widget build(BuildContext context) => Text(label);
}
''';

void main() {
  test('RFW unsupported defaults recommend only effective remedies', () async {
    final result = await runWidgetVisitorOn({
      'lib/private_default.dart': _source,
    });
    final issue = result.issues.singleWhere(
      (candidate) => candidate.code == IssueCode.invalidWidgetConstructorInput,
    );

    expect(issue.location, 'lib/private_default.dart#PrivateDefaultCard.label');
    expect(
      issue.message,
      'PrivateDefaultCard.label has constructor default _privateLabel, which '
      'the rfw target cannot reproduce. $_remediation',
    );
    expect(issue.message, isNot(contains('RestageProperty default source')));
  });

  test('Widgetbook unsupported defaults recommend only effective remedies',
      () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/private_default.dart'),
      _source,
    );

    await testBuilder(
      const _StoryPlanProbeBuilder(),
      const {'apps_examples|lib/private_default.dart': _source},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      outputs: {
        'apps_examples|lib/customer.stories.dart': decodedMatches(
          'Bad state: Widgetbook seed at /constructorDefaults/label cannot '
          'reproduce constructor default _privateLabel. $_remediation',
        ),
      },
    );
  });
}

final class _StoryPlanProbeBuilder implements Builder {
  const _StoryPlanProbeBuilder();

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$lib$': ['customer.stories.dart'],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    try {
      final index = await loadWidgetbookCatalogSourceIndex(buildStep);
      final widget = index.widgets.single;
      final plan = planWidgetbookStory(index: index, widget: widget);
      await buildStep.writeAsString(
        AssetId(buildStep.inputId.package, 'lib/customer.stories.dart'),
        renderWidgetbookStorySource(
          plan: plan,
          packageName: buildStep.inputId.package,
          sourcePath: widget.sourceAsset.path,
        ),
      );
    } on Object catch (error) {
      await buildStep.writeAsString(
        AssetId(buildStep.inputId.package, 'lib/customer.stories.dart'),
        error.toString(),
      );
    }
  }
}
