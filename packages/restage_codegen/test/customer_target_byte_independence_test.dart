import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:restage_codegen/src/user_catalog_builder.dart';
import 'package:restage_codegen/src/user_catalog_json_builder.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _sourceAsset = 'apps_examples|lib/widgets/target_probe.dart';

const _rfwOutputs = <String>[
  'lib/user_catalog.g.dart',
  'lib/src/widget_catalog/catalog.json',
  'lib/user_factories.g.dart',
];
const _a2uiOutputs = <String>[
  'lib/generated/restage_a2ui_catalog.g.dart',
  'lib/generated/restage_a2ui_catalog.a2ui.json',
];
const _widgetbookOutputs = <String>[
  'lib/generated/target_probe.stories.dart',
];

const _rfwBuilders = <Builder>[
  UserCatalogBuilder(BuilderOptions.empty),
  UserCatalogJsonBuilder(BuilderOptions.empty),
  UserFactoryBuilder(BuilderOptions.empty),
];
const _a2uiBuilders = <Builder>[
  UserA2uiCatalogBuilder(BuilderOptions.empty),
];
const _widgetbookBuilders = <Builder>[
  WidgetbookStoryBuilder({
    'lib/widgets/target_probe.dart': _widgetbookOutputs,
  }),
];

void main() {
  test('solo and mixed target configurations emit identical sibling bytes',
      () async {
    final rfwOnly = await _build(
      builders: _rfwBuilders,
      outputs: _rfwOutputs,
    );
    final a2uiOnly = await _build(
      builders: _a2uiBuilders,
      outputs: _a2uiOutputs,
    );
    final widgetbookOnly = await _build(
      builders: _widgetbookBuilders,
      outputs: _widgetbookOutputs,
    );
    final mixed = await _build(
      builders: const [
        ..._rfwBuilders,
        ..._a2uiBuilders,
        ..._widgetbookBuilders,
      ],
      outputs: const [
        ..._rfwOutputs,
        ..._a2uiOutputs,
        ..._widgetbookOutputs,
      ],
    );

    expect(_family(mixed, _rfwOutputs), rfwOnly);
    expect(_family(mixed, _a2uiOutputs), a2uiOnly);
    expect(_family(mixed, _widgetbookOutputs), widgetbookOnly);
  });

  test('an A2UI-only pairing mutation changes no sibling output family',
      () async {
    final primary = await _build(
      builders: const [
        ..._rfwBuilders,
        ..._a2uiBuilders,
        ..._widgetbookBuilders,
      ],
      outputs: const [
        ..._rfwOutputs,
        ..._a2uiOutputs,
        ..._widgetbookOutputs,
      ],
    );
    final secondary = await _build(
      builders: const [
        ..._rfwBuilders,
        ..._a2uiBuilders,
        ..._widgetbookBuilders,
      ],
      outputs: const [
        ..._rfwOutputs,
        ..._a2uiOutputs,
        ..._widgetbookOutputs,
      ],
      writeBackTarget: 'secondary',
    );

    expect(_family(primary, _rfwOutputs), _family(secondary, _rfwOutputs));
    expect(
      _family(primary, _widgetbookOutputs),
      _family(secondary, _widgetbookOutputs),
    );
    expect(
      primary['lib/generated/restage_a2ui_catalog.g.dart'],
      isNot(secondary['lib/generated/restage_a2ui_catalog.g.dart']),
    );
  });
}

Future<Map<String, String>> _build({
  required List<Builder> builders,
  required List<String> outputs,
  String writeBackTarget = 'primary',
}) async {
  final source = _targetProbe(writeBackTarget);
  final sources = <String, String>{_sourceAsset: source};
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  readerWriter.testing.writeString(AssetId.parse(_sourceAsset), source);
  final result = await testBuilders(
    builders,
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  return {
    for (final path in outputs)
      path: result.readerWriter.testing.readString(
        AssetId('apps_examples', path),
      ),
  };
}

Map<String, String> _family(
  Map<String, String> outputs,
  List<String> paths,
) =>
    {for (final path in paths) path: outputs[path]!};

String _targetProbe(String writeBackTarget) => '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;

@RestageLibrary(
  library: WidgetLibrary.custom('target.probe'),
  capabilityVersion: 1,
)
const restageLibrary = 0;

/// Customer widget used to compare independent target outputs.
@a2ui.Config(
  writeBackValues: <String, String>{'onChanged': '$writeBackTarget'},
)
@RestageWidget(
  name: 'TargetProbe',
  library: WidgetLibrary.custom('target.probe'),
  category: WidgetCategory.input,
)
class TargetProbe extends StatelessWidget {
  /// Creates the target-independence probe.
  const TargetProbe({
    super.key,
    required this.primary,
    required this.secondary,
    required this.onChanged,
  });

  /// First write-back-compatible value.
  final String primary;

  /// Second write-back-compatible value.
  final String secondary;

  /// Reports a changed value.
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
