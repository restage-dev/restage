import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:restage_codegen/src/user_catalog_builder.dart';
import 'package:restage_codegen/src/user_catalog_json_builder.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_story_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _rfwBuilders = <Builder>[
  UserCatalogBuilder(BuilderOptions.empty),
  UserCatalogJsonBuilder(BuilderOptions.empty),
  UserFactoryBuilder(BuilderOptions.empty),
];
const _a2uiBuilder = UserA2uiCatalogBuilder(BuilderOptions.empty);
const _widgetbookSentinel = 'generated/.restage_widgetbook_story_builder';

void main() {
  test('real builders honor the complete seven-case target matrix', () async {
    final widgetbookOutputs = <String>[
      _widgetbookSentinel,
      for (final name in _matrixNames)
        'generated/${_snakeCase(name)}.stories.dart',
    ];
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final sourceId = AssetId(
      'apps_examples',
      'lib/widgets/target_matrix.dart',
    );
    readerWriter.testing.writeString(sourceId, _targetMatrixSource);

    final result = await testBuilders(
      [
        ..._rfwBuilders,
        _a2uiBuilder,
        WidgetbookStoryBuilder({r'$lib$': widgetbookOutputs}),
      ],
      const {
        'apps_examples|lib/widgets/target_matrix.dart': _targetMatrixSource,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.succeeded, isTrue);

    final rfwJson = jsonDecode(
      readerWriter.testing.readString(
        AssetId(
          'apps_examples',
          'lib/src/widget_catalog/catalog.json',
        ),
      ),
    ) as Map<String, Object?>;
    expect(
      _catalogWidgetNames(rfwJson),
      _rfwMatrixNames,
    );

    final a2uiStamp = jsonDecode(
      readerWriter.testing.readString(
        AssetId(
          'apps_examples',
          'lib/generated/restage_a2ui_catalog.a2ui.json',
        ),
      ),
    ) as Map<String, Object?>;
    final a2uiCatalog = a2uiStamp['a2uiCatalog']! as Map<String, Object?>;
    expect(
      (a2uiCatalog['components']! as Map).keys.toSet(),
      _a2uiMatrixNames,
    );

    for (final name in _matrixNames) {
      final source = readerWriter.testing.readString(
        AssetId(
          'apps_examples',
          'lib/generated/${_snakeCase(name)}.stories.dart',
        ),
      );
      expect(
        source.contains('class ${name}StoryInput'),
        _widgetbookMatrixNames.contains(name),
        reason: name,
      );
      expect(source, startsWith('// GENERATED CODE - DO NOT MODIFY BY HAND'));
    }
  });

  test('RFW last-widget off/on overwrites aggregates and preserves IDs',
      () async {
    const eventLog = '{"kind":"alloc","type":"widget","id":"w0042",'
        '"name":"RoutedCard",'
        '"source":"package:apps_examples/widgets/routed_card.dart#RoutedCard",'
        '"at":"2026-08-10T00:00:00.000Z","by":"test"}\n';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'wire_ids.events.jsonl'),
      eventLog,
    );

    final enabled = await _runRfw(
      readerWriter,
      _routedCardSource(),
      eventLog: eventLog,
    );
    expect(enabled.catalogDart, contains("WireId('w0042')"));
    expect(enabled.factoryDart, contains('RoutedCard'));

    final disabled = await _runRfw(
      readerWriter,
      _routedCardSource(rfwEnabled: false),
      eventLog: eventLog,
    );
    expect(
      _catalogWidgetNames(
        jsonDecode(disabled.catalogJson) as Map<String, Object?>,
      ),
      isEmpty,
    );
    expect(disabled.catalogDart, isNot(contains('RoutedCard')));
    expect(disabled.factoryDart, isNot(contains('RoutedCard')));
    expect(
      disabled.factoryDart,
      contains('void registerRestageCustomerWidgets() {}'),
    );
    expect(
      readerWriter.testing.readString(
        AssetId('apps_examples', 'wire_ids.events.jsonl'),
      ),
      eventLog,
    );

    final reenabled = await _runRfw(
      readerWriter,
      _routedCardSource(),
      eventLog: eventLog,
    );
    expect(reenabled.catalogDart, enabled.catalogDart);
    expect(reenabled.catalogJson, enabled.catalogJson);
    expect(reenabled.factoryDart, enabled.factoryDart);

    final cold = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    cold.testing.writeString(
      AssetId('apps_examples', 'wire_ids.events.jsonl'),
      eventLog,
    );
    final coldDisabled = await _runRfw(
      cold,
      _routedCardSource(rfwEnabled: false),
      eventLog: eventLog,
    );
    expect(
      _catalogWidgetNames(
        jsonDecode(coldDisabled.catalogJson) as Map<String, Object?>,
      ),
      isEmpty,
    );
  });

  test('A2UI last-widget off/on overwrites both aggregate artifacts', () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );

    final enabled = await _runA2ui(readerWriter, _routedCardSource());
    expect(_a2uiComponentNames(enabled.stamp), {'RoutedCard'});

    final disabled = await _runA2ui(
      readerWriter,
      _routedCardSource(a2uiEnabled: false),
    );
    expect(_a2uiComponentNames(disabled.stamp), isEmpty);
    expect(disabled.dart, isNot(contains('RoutedCard')));

    final reenabled = await _runA2ui(readerWriter, _routedCardSource());
    expect(reenabled, enabled);

    final cold = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final coldDisabled = await _runA2ui(
      cold,
      _routedCardSource(a2uiEnabled: false),
    );
    expect(_a2uiComponentNames(coldDisabled.stamp), isEmpty);
  });

  test('Widgetbook last-widget off/on overwrites the reserved story', () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );

    final enabled = await _runWidgetbook(readerWriter, _routedCardSource());
    expect(enabled, contains('class RoutedCardStoryInput'));

    final disabled = await _runWidgetbook(
      readerWriter,
      _routedCardSource(widgetbookEnabled: false),
    );
    expect(disabled, startsWith('// GENERATED CODE - DO NOT MODIFY BY HAND'));
    expect(disabled, contains('No enabled Restage source'));
    expect(disabled, isNot(contains('class RoutedCardStoryInput')));

    final reenabled = await _runWidgetbook(
      readerWriter,
      _routedCardSource(),
    );
    expect(reenabled, enabled);

    final cold = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final coldDisabled = await _runWidgetbook(
      cold,
      _routedCardSource(widgetbookEnabled: false),
    );
    expect(coldDisabled, contains('No enabled Restage source'));
  });

  test('legacy all-target Ignore spellings remain artifact-byte neutral',
      () async {
    final canonical = await _buildIgnoreSpelling('@ignore');
    final constructed = await _buildIgnoreSpelling('@Ignore()');
    final explicitNull = await _buildIgnoreSpelling('@Ignore(null)');

    expect(constructed, canonical);
    expect(explicitNull, canonical);
  });

  test('selective Ignore changes only the selected generated properties',
      () async {
    final baseline = await _buildSiblingBytes(_routedPropertySource());
    final selective = await _buildSiblingBytes(
      _routedPropertySource(selectiveIgnore: true),
    );

    expect(
      _only(selective, _rfwArtifactPaths),
      _only(baseline, _rfwArtifactPaths),
    );
    for (final path in _a2uiAndWidgetbook) {
      expect(baseline[path], contains('debugLabel'), reason: path);
      expect(selective[path], isNot(contains('debugLabel')), reason: path);
    }
  });

  test(
      'A2UI builds when every positional after an authored omission is '
      'automatically omitted', () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final output = await _runA2ui(readerWriter, _positionalFinalSetSource);

    expect(_a2uiComponentNames(output.stamp), {'PositionalCard'});
    final stamp = jsonDecode(output.stamp) as Map<String, Object?>;
    final catalog = stamp['a2uiCatalog']! as Map<String, Object?>;
    final components = catalog['components']! as Map<String, Object?>;
    final component = components['PositionalCard']! as Map<String, Object?>;
    final componentJson = jsonEncode(component);
    expect(componentJson, isNot(contains('"label"')));
    expect(componentJson, isNot(contains('"hostObject"')));
  });

  test('A2UI validates write-back references after selective routing',
      () async {
    final validReader = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    final valid = await _runA2ui(validReader, _callbackRoutingSource);
    expect(valid.dart, contains('onChanged: restageA2uiWriteValue'));

    final invalidSource = _callbackRoutingSource.replaceFirst(
      'EmitTarget.widgetbook',
      'EmitTarget.a2ui',
    );
    final invalidReader = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    const path = 'lib/widgets/routed_card.dart';
    invalidReader.testing.writeString(
      AssetId('apps_examples', path),
      invalidSource,
    );
    final logs = <String>[];
    final result = await testBuilder(
      _a2uiBuilder,
      {'apps_examples|$path': invalidSource},
      rootPackage: 'apps_examples',
      readerWriter: invalidReader,
      flattenOutput: true,
      onLog: (record) => logs.add(record.message),
    );

    expect(result.succeeded, isFalse);
    expect(
      logs.join('\n'),
      allOf(
        contains('invalidTargetConfigReference'),
        contains('"onChanged" is not an input'),
      ),
    );
  });

  test(
      'A2UI builder rejects inherited property placement of class-only '
      'enabled', () async {
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    const path = 'lib/widgets/routed_card.dart';
    readerWriter.testing.writeString(
      AssetId('apps_examples', path),
      _inheritedEnabledSource,
    );
    final logs = <String>[];
    final result = await testBuilder(
      _a2uiBuilder,
      {'apps_examples|$path': _inheritedEnabledSource},
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
      onLog: (record) => logs.add(record.message),
    );

    expect(result.succeeded, isFalse);
    expect(
      logs.join('\n'),
      allOf(
        contains('invalidTargetConfigPlacement'),
        contains('InheritedEnabledCard.label@a2ui.Config[0]'),
      ),
    );
  });

  test('disabling one target leaves every sibling artifact byte-identical',
      () async {
    final baseline = await _buildSiblingBytes(_routedCardSource());
    final noRfw = await _buildSiblingBytes(
      _routedCardSource(rfwEnabled: false),
    );
    final noA2ui = await _buildSiblingBytes(
      _routedCardSource(a2uiEnabled: false),
    );
    final noWidgetbook = await _buildSiblingBytes(
      _routedCardSource(widgetbookEnabled: false),
    );

    expect(
      _only(baseline, _a2uiAndWidgetbook),
      _only(noRfw, _a2uiAndWidgetbook),
    );
    expect(
      _only(baseline, _rfwAndWidgetbook),
      _only(noA2ui, _rfwAndWidgetbook),
    );
    expect(_only(baseline, _rfwAndA2ui), _only(noWidgetbook, _rfwAndA2ui));
  });
}

const _rfwArtifactPaths = <String>{
  'lib/user_catalog.g.dart',
  'lib/src/widget_catalog/catalog.json',
  'lib/user_factories.g.dart',
};
const _a2uiArtifactPaths = <String>{
  'lib/generated/restage_a2ui_catalog.g.dart',
  'lib/generated/restage_a2ui_catalog.a2ui.json',
};
const _widgetbookArtifactPaths = <String>{
  'lib/generated/routed_card.stories.dart',
};
const _rfwAndA2ui = <String>{..._rfwArtifactPaths, ..._a2uiArtifactPaths};
const _rfwAndWidgetbook = <String>{
  ..._rfwArtifactPaths,
  ..._widgetbookArtifactPaths,
};
const _a2uiAndWidgetbook = <String>{
  ..._a2uiArtifactPaths,
  ..._widgetbookArtifactPaths,
};

Future<Map<String, String>> _buildSiblingBytes(String source) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  const path = 'lib/widgets/routed_card.dart';
  readerWriter.testing
    ..writeString(AssetId('apps_examples', path), source)
    ..writeString(AssetId('apps_examples', 'wire_ids.events.jsonl'), '');
  final result = await testBuilders(
    [
      const UserCatalogBuilder(BuilderOptions.empty),
      const UserCatalogJsonBuilder(BuilderOptions.empty),
      const UserFactoryBuilder(BuilderOptions.empty),
      _a2uiBuilder,
      const WidgetbookStoryBuilder({
        r'$lib$': [
          _widgetbookSentinel,
          'generated/routed_card.stories.dart',
        ],
      }),
    ],
    {
      'apps_examples|$path': source,
      'apps_examples|wire_ids.events.jsonl': '',
    },
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.succeeded, isTrue);
  return {
    for (final output in {
      ..._rfwArtifactPaths,
      ..._a2uiArtifactPaths,
      ..._widgetbookArtifactPaths,
    })
      output: readerWriter.testing.readString(
        AssetId('apps_examples', output),
      ),
  };
}

Map<String, String> _only(
  Map<String, String> source,
  Set<String> paths,
) =>
    {for (final path in paths) path: source[path]!};

Future<Map<String, String>> _buildIgnoreSpelling(String spelling) async {
  final source = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('routing.widgets'),
  capabilityVersion: 1,
)
const restageLibrary = 0;

/// Ignore spelling byte-neutrality probe.
@RestageWidget(library: WidgetLibrary.custom('routing.widgets'))
class IgnoreProbe extends StatelessWidget {
  const IgnoreProbe({
    $spelling this.internal = 0,
    this.label = 'visible',
    super.key,
  });

  final int internal;

  @RestageProperty(description: 'Visible label.')
  final String label;

  @override
  Widget build(BuildContext context) => Text(label);
}
''';
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  const path = 'lib/widgets/ignore_probe.dart';
  readerWriter.testing
    ..writeString(AssetId('apps_examples', path), source)
    ..writeString(AssetId('apps_examples', 'wire_ids.events.jsonl'), '');
  final result = await testBuilders(
    [
      const UserCatalogBuilder(BuilderOptions.empty),
      const UserCatalogJsonBuilder(BuilderOptions.empty),
      const UserFactoryBuilder(BuilderOptions.empty),
      _a2uiBuilder,
      const WidgetbookStoryBuilder({
        r'$lib$': [
          _widgetbookSentinel,
          'generated/ignore_probe.stories.dart',
        ],
      }),
    ],
    {
      'apps_examples|$path': source,
      'apps_examples|wire_ids.events.jsonl': '',
    },
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.succeeded, isTrue);
  const outputs = <String>[
    'lib/user_catalog.g.dart',
    'lib/src/widget_catalog/catalog.json',
    'lib/user_factories.g.dart',
    'lib/generated/restage_a2ui_catalog.g.dart',
    'lib/generated/restage_a2ui_catalog.a2ui.json',
    'lib/generated/ignore_probe.stories.dart',
  ];
  return {
    for (final output in outputs)
      output: readerWriter.testing.readString(
        AssetId('apps_examples', output),
      ),
  };
}

Future<({String catalogDart, String catalogJson, String factoryDart})> _runRfw(
  TestReaderWriter readerWriter,
  String source, {
  required String eventLog,
}) async {
  final sourceId = AssetId(
    'apps_examples',
    'lib/widgets/routed_card.dart',
  );
  readerWriter.testing.writeString(sourceId, source);
  final result = await testBuilders(
    _rfwBuilders,
    {
      'apps_examples|lib/widgets/routed_card.dart': source,
      'apps_examples|wire_ids.events.jsonl': eventLog,
    },
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.succeeded, isTrue);
  return (
    catalogDart: readerWriter.testing.readString(
      AssetId('apps_examples', 'lib/user_catalog.g.dart'),
    ),
    catalogJson: readerWriter.testing.readString(
      AssetId(
        'apps_examples',
        'lib/src/widget_catalog/catalog.json',
      ),
    ),
    factoryDart: readerWriter.testing.readString(
      AssetId('apps_examples', 'lib/user_factories.g.dart'),
    ),
  );
}

Future<({String dart, String stamp})> _runA2ui(
  TestReaderWriter readerWriter,
  String source,
) async {
  final sourceId = AssetId(
    'apps_examples',
    'lib/widgets/routed_card.dart',
  );
  readerWriter.testing.writeString(sourceId, source);
  final result = await testBuilder(
    _a2uiBuilder,
    {'apps_examples|lib/widgets/routed_card.dart': source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.succeeded, isTrue);
  return (
    dart: readerWriter.testing.readString(
      AssetId(
        'apps_examples',
        'lib/generated/restage_a2ui_catalog.g.dart',
      ),
    ),
    stamp: readerWriter.testing.readString(
      AssetId(
        'apps_examples',
        'lib/generated/restage_a2ui_catalog.a2ui.json',
      ),
    ),
  );
}

Future<String> _runWidgetbook(
  TestReaderWriter readerWriter,
  String source,
) async {
  final sourceId = AssetId(
    'apps_examples',
    'lib/widgets/routed_card.dart',
  );
  readerWriter.testing.writeString(sourceId, source);
  final result = await testBuilder(
    const WidgetbookStoryBuilder({
      r'$lib$': [
        _widgetbookSentinel,
        'generated/routed_card.stories.dart',
      ],
    }),
    {'apps_examples|lib/widgets/routed_card.dart': source},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.succeeded, isTrue);
  return readerWriter.testing.readString(
    AssetId(
      'apps_examples',
      'lib/generated/routed_card.stories.dart',
    ),
  );
}

Set<String> _catalogWidgetNames(Map<String, Object?> catalog) => {
      for (final widget in catalog['widgets']! as List<Object?>)
        (widget! as Map<String, Object?>)['name']! as String,
    };

Set<String> _a2uiComponentNames(String stamp) {
  final decoded = jsonDecode(stamp) as Map<String, Object?>;
  final catalog = decoded['a2uiCatalog']! as Map<String, Object?>;
  return (catalog['components']! as Map<String, Object?>).keys.toSet();
}

String _snakeCase(String value) => value
    .replaceAllMapped(
      RegExp('([a-z0-9])([A-Z])'),
      (match) => '${match[1]}_${match[2]}',
    )
    .toLowerCase();

String _routedCardSource({
  bool rfwEnabled = true,
  bool a2uiEnabled = true,
  bool widgetbookEnabled = true,
}) =>
    '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw.dart' as rfw;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

@RestageLibrary(
  library: WidgetLibrary.custom('routing.widgets'),
  capabilityVersion: 1,
)
const restageLibrary = 0;

/// A widget used to prove aggregate target toggling.
${rfwEnabled ? '' : '@rfw.Config.enabled(false)'}
${a2uiEnabled ? '' : '@a2ui.Config.enabled(false)'}
${widgetbookEnabled ? '' : '@wb.Config.enabled(false)'}
@RestageWidget(library: WidgetLibrary.custom('routing.widgets'))
class RoutedCard extends StatelessWidget {
  const RoutedCard({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

String _routedPropertySource({bool selectiveIgnore = false}) => '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('routing.widgets'),
  capabilityVersion: 1,
)
const restageLibrary = 0;

/// A widget used to prove generated selective-property routing.
@RestageWidget(library: WidgetLibrary.custom('routing.widgets'))
class RoutedCard extends StatelessWidget {
  const RoutedCard({
    super.key,
    ${selectiveIgnore ? '@Ignore({EmitTarget.a2ui, EmitTarget.widgetbook})' : ''}
    this.debugLabel = '',
  });

  /// App-owned diagnostic text.
  final String debugLabel;

  @override
  Widget build(BuildContext context) => Text(debugLabel);
}
''';

const _positionalFinalSetSource = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('routing.widgets'),
  capabilityVersion: 1,
)
const restageLibrary = 0;

/// A widget used to prove final positional-set validation.
@RestageWidget(library: WidgetLibrary.custom('routing.widgets'))
class PositionalCard extends StatelessWidget {
  const PositionalCard([
    @Ignore({EmitTarget.a2ui}) this.label = '',
    this.hostObject,
  ]);

  @RestageProperty(description: 'Visible label.')
  final String label;

  @RestageProperty(description: 'Host-only object.')
  final Object? hostObject;

  @override
  Widget build(BuildContext context) => Text(label);
}
''';

const _callbackRoutingSource = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('routing.widgets'),
  capabilityVersion: 1,
)
const restageLibrary = 0;

/// Callback routing builder probe.
@a2ui.Config.writeBackValues({'onChanged': 'value'})
@RestageWidget(library: WidgetLibrary.custom('routing.widgets'))
class CallbackCard extends StatelessWidget {
  const CallbackCard({
    super.key,
    this.value = '',
    @Ignore({EmitTarget.widgetbook}) this.onChanged,
  });

  /// Current value.
  final String value;

  /// Reports a changed value.
  final void Function(String)? onChanged;

  @override
  Widget build(BuildContext context) => Text(value);
}
''';

const _inheritedEnabledSource = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('routing.widgets'),
  capabilityVersion: 1,
)
const restageLibrary = 0;

abstract class BaseCard extends StatelessWidget {
  const BaseCard({super.key, this.label = ''});

  @a2ui.Config.enabled(false)
  @RestageProperty(description: 'Visible label.')
  final String label;
}

/// A widget used to prove inherited routing placement validation.
@RestageWidget(library: WidgetLibrary.custom('routing.widgets'))
class InheritedEnabledCard extends BaseCard {
  const InheritedEnabledCard({super.key, super.label});

  @override
  Widget build(BuildContext context) => Text(label);
}
''';

const _matrixNames = <String>{
  'DefaultCard',
  'RfwOnlyCard',
  'A2uiOnlyCard',
  'WidgetbookOnlyCard',
  'RfwA2uiCard',
  'RfwWidgetbookCard',
  'A2uiWidgetbookCard',
};
const _rfwMatrixNames = <String>{
  'DefaultCard',
  'RfwOnlyCard',
  'RfwA2uiCard',
  'RfwWidgetbookCard',
};
const _a2uiMatrixNames = <String>{
  'DefaultCard',
  'A2uiOnlyCard',
  'RfwA2uiCard',
  'A2uiWidgetbookCard',
};
const _widgetbookMatrixNames = <String>{
  'DefaultCard',
  'WidgetbookOnlyCard',
  'RfwWidgetbookCard',
  'A2uiWidgetbookCard',
};

const _targetMatrixSource = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw.dart' as rfw;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

@RestageLibrary(
  library: WidgetLibrary.custom('routing.widgets'),
  capabilityVersion: 1,
)
const restageLibrary = 0;

/// Default target card.
@RestageWidget(library: WidgetLibrary.custom('routing.widgets'))
class DefaultCard extends StatelessWidget {
  const DefaultCard({super.key});
  @override Widget build(BuildContext context) => const SizedBox.shrink();
}

/// RFW-only card.
@a2ui.Config.enabled(false)
@wb.Config.enabled(false)
@RestageWidget(library: WidgetLibrary.custom('routing.widgets'))
class RfwOnlyCard extends StatelessWidget {
  const RfwOnlyCard({super.key});
  @override Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A2UI-only card.
@rfw.Config.enabled(false)
@wb.Config.enabled(false)
@RestageWidget(library: WidgetLibrary.custom('routing.widgets'))
class A2uiOnlyCard extends StatelessWidget {
  const A2uiOnlyCard({super.key});
  @override Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Widgetbook-only card.
@rfw.Config.enabled(false)
@a2ui.Config.enabled(false)
@RestageWidget(library: WidgetLibrary.custom('routing.widgets'))
class WidgetbookOnlyCard extends StatelessWidget {
  const WidgetbookOnlyCard({super.key});
  @override Widget build(BuildContext context) => const SizedBox.shrink();
}

/// RFW and A2UI card.
@wb.Config.enabled(false)
@RestageWidget(library: WidgetLibrary.custom('routing.widgets'))
class RfwA2uiCard extends StatelessWidget {
  const RfwA2uiCard({super.key});
  @override Widget build(BuildContext context) => const SizedBox.shrink();
}

/// RFW and Widgetbook card.
@a2ui.Config.enabled(false)
@RestageWidget(library: WidgetLibrary.custom('routing.widgets'))
class RfwWidgetbookCard extends StatelessWidget {
  const RfwWidgetbookCard({super.key});
  @override Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A2UI and Widgetbook card.
@rfw.Config.enabled(false)
@RestageWidget(library: WidgetLibrary.custom('routing.widgets'))
class A2uiWidgetbookCard extends StatelessWidget {
  const A2uiWidgetbookCard({super.key});
  @override Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
