import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:crypto/crypto.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:restage_codegen/src/native_screen_source_index.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('no-screen builder path freezes the customer props Dart and JSON bytes',
      () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.widgets'),
  capabilityVersion: 1,
)
const restageLibrary = 0;

@RestageWidget(
  name: 'LegacyGauge',
  library: WidgetLibrary.custom('acme.widgets'),
  description: 'A legacy no-screen byte probe.',
)
class LegacyGauge extends StatelessWidget {
  const LegacyGauge({super.key, required this.value});

  /// Visible gauge value.
  final double value;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    readerWriter.testing.writeString(
      AssetId('apps_examples', 'lib/legacy_gauge.dart'),
      source,
    );

    final result = await testBuilder(
      UserA2uiCatalogBuilder(BuilderOptions.empty),
      const <String, String>{
        'apps_examples|lib/legacy_gauge.dart': source,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue);
    final dartBytes = result.readerWriter.testing.readBytes(
      AssetId(
        'apps_examples',
        'lib/generated/restage_a2ui_catalog.g.dart',
      ),
    );
    final jsonBytes = result.readerWriter.testing.readBytes(
      AssetId(
        'apps_examples',
        'lib/generated/restage_a2ui_catalog.a2ui.json',
      ),
    );
    expect(
      sha256.convert(dartBytes).toString(),
      'dd907d669936317a09240ef4e1f494f894f51d9df0beae4e7356b1bdb3147d0a',
      reason: 'the customer props Dart artifact must match the emitter',
    );
    expect(
      sha256.convert(jsonBytes).toString(),
      'be804d484063b9ef0fc6ce87ae442fee78941aefcf2dd4e70491a96601cda507',
      reason: 'the customer props JSON artifact must remain byte-identical',
    );
  });

  test(
    'ordinary A2UI build emits one exact-ID opaque native screen component',
    () async {
      const source = '''
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' as wb;

part 'restage.generated/opaque_screen.restage.g.dart';

@ScreenSource(id: 'opaque_screen', version: 2)
@wb.Config.values([true])
class OpaqueScreen extends StatelessWidget {
  const OpaqueScreen({
    super.key,
    required this.title,
    this.enabled = true,
  });

  static const continued = SurfaceEvent<String>('continue');

  /// Visible screen title.
  final String title;

  /// Whether continuing is enabled.
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Text(title),
          ElevatedButton(
            onPressed: surfaceEvent(continued, 'preview'),
            child: const Text('Continue'),
          ),
        ],
      );
}
''';
      const pubspec = '''
name: apps_examples
dependencies:
  flutter: any
  restage: any
  rfw_catalog_schema: any
''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      readerWriter.testing
        ..writeString(
          AssetId(
            'apps_examples',
            'lib/onboarding/screens/opaque_screen.dart',
          ),
          source,
        )
        ..writeString(AssetId('apps_examples', 'pubspec.yaml'), pubspec);
      final logs = <String>[];

      final result = await runWithNativeScreenPackageGraphForTesting(
        packageGraphSource: _screenSourcePackageGraph,
        body: () => testBuilder(
          UserA2uiCatalogBuilder(BuilderOptions.empty),
          const <String, String>{
            'apps_examples|lib/onboarding/screens/opaque_screen.dart': source,
            'apps_examples|pubspec.yaml': pubspec,
          },
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          flattenOutput: true,
          onLog: (record) => logs.add(record.message),
        ),
      );

      expect(result.succeeded, isTrue, reason: logs.join('\n'));
      final dartId = AssetId(
        'apps_examples',
        'lib/generated/restage_a2ui_catalog.g.dart',
      );
      final stampId = AssetId(
        'apps_examples',
        'lib/generated/restage_a2ui_catalog.a2ui.json',
      );
      expect(result.readerWriter.testing.exists(dartId), isTrue);
      expect(result.readerWriter.testing.exists(stampId), isTrue);
      final dart = result.readerWriter.testing.exists(dartId)
          ? utf8.decode(result.readerWriter.testing.readBytes(dartId))
          : '';
      final stampJson = result.readerWriter.testing.exists(stampId)
          ? utf8.decode(result.readerWriter.testing.readBytes(stampId))
          : '';
      final stamp = stampJson.isNotEmpty
          ? jsonDecode(stampJson) as Map<String, Object?>
          : const <String, Object?>{};

      expect(dart, contains("name: 'opaque_screen'"));
      expect(dart, contains("'props': S.object("));
      expect(dart, contains("'title': S.string("));
      expect(dart, contains("'enabled': S.boolean("));
      expect(dart, contains("required: <String>['title']"));
      expect(dart, contains("required: <String>['props']"));
      expect(
        dart,
        contains(
          "final props = (data['props']! as Map).cast<String, Object?>();",
        ),
      );
      expect(dart, contains("value: props['title']"));
      expect(dart, contains("value: props['enabled']"));
      expect(dart, contains('OpaqueScreen('));
      expect(dart, contains('RestageSurfaceEventDispatcher('));
      expect(dart, contains('UserActionEvent('));
      expect(dart, contains('sourceComponentId: itemContext.id'));
      expect(dart, contains("'value': value"));
      expect(dart, isNot(contains('Column(')));
      expect(dart, isNot(contains('Text(')));
      expect(dart, isNot(contains('restage.native_screen_source')));
      expect(dart, isNot(contains('WidgetCategory.layout')));
      expect(stampJson, isNot(contains('restage.native_screen_source')));
      expect(stampJson, isNot(contains('"category"')));

      final a2uiCatalog = stamp['a2uiCatalog'] as Map<String, Object?>?;
      expect(
        (a2uiCatalog?['components'] as Map<String, Object?>?)?.keys,
        <String>['opaque_screen'],
      );
      final components = a2uiCatalog?['components'] as Map<String, Object?>?;
      final screenSchema =
          components?['opaque_screen'] as Map<String, Object?>?;
      final screenProperties =
          screenSchema?['properties'] as Map<String, Object?>?;
      final propsSchema = screenProperties?['props'] as Map<String, Object?>?;
      expect(screenSchema?['required'], <Object?>['component', 'props']);
      expect(
        (propsSchema?['properties'] as Map<String, Object?>?)?.keys,
        <String>['title', 'enabled'],
      );
      expect(propsSchema?['required'], <Object?>['title']);
      final capability = stamp['restageCapability'] as Map<String, Object?>?;
      expect(capability?['availableLibraries'], isEmpty);
      expect(
        capability?['perItemSinceVersion'],
        <String, Object?>{'opaque_screen': 2},
      );

      expect(
        result.readerWriter.testing.exists(
          AssetId(
            'apps_examples',
            'lib/generated/opaque_screen.a2ui.dart',
          ),
        ),
        isFalse,
      );
    },
  );

  test(
    'A2UI catalogs package-wide canonical screens with implicit and '
    'colocated explicit IDs alongside a legacy screen',
    () async {
      const sources = <String, String>{
        'apps_examples|lib/features/implicit_notice.dart':
            _canonicalImplicitNotice,
        'apps_examples|lib/features/message_bundle.dart':
            _canonicalMessageBundle,
        'apps_examples|lib/onboarding/screens/legacy_notice.dart':
            _legacyNotice,
        'apps_examples|pubspec.yaml': _screenSourcePubspec,
      };
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
      );
      for (final source in sources.entries) {
        readerWriter.testing.writeString(
          AssetId.parse(source.key),
          source.value,
        );
      }
      final logs = <String>[];

      final result = await runWithNativeScreenPackageGraphForTesting(
        packageGraphSource: _screenSourcePackageGraph,
        body: () => testBuilder(
          UserA2uiCatalogBuilder(BuilderOptions.empty),
          sources,
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          flattenOutput: true,
          onLog: (record) => logs.add(record.message),
        ),
      );

      expect(result.succeeded, isTrue, reason: logs.join('\n'));
      final stamp = jsonDecode(
        utf8.decode(
          result.readerWriter.testing.readBytes(
            AssetId(
              'apps_examples',
              'lib/generated/restage_a2ui_catalog.a2ui.json',
            ),
          ),
        ),
      ) as Map<String, Object?>;
      final catalog = stamp['a2uiCatalog']! as Map<String, Object?>;
      final components = catalog['components']! as Map<String, Object?>;
      expect(
        components.keys,
        containsAll(<String>[
          'implicit_notice',
          'stable-first',
          'stable-second',
          'legacy_notice',
        ]),
      );
      final capability = stamp['restageCapability']! as Map<String, Object?>;
      expect(
        capability['perItemSinceVersion'],
        containsPair('implicit_notice', 2),
      );
    },
  );

  test('ScreenSource order migration is logged exactly once', () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

part 'restage.generated/order_screen.restage.g.dart';

@ScreenSource(id: 'order_screen')
class OrderScreen extends StatelessWidget {
  const OrderScreen({
    super.key,
    @Ignore({EmitTarget.a2ui, EmitTarget.widgetbook}) this.hidden = '',
    this.first = '',
    this.second = '',
  });

  final String hidden;

  @RestageProperty(description: 'Second field.')
  final String second;

  @RestageProperty(description: 'First field.')
  final String first;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    readerWriter.testing
      ..writeString(
        AssetId(
          'apps_examples',
          'lib/onboarding/screens/order_screen.dart',
        ),
        source,
      )
      ..writeString(
        AssetId('apps_examples', 'pubspec.yaml'),
        _screenSourcePubspec,
      );
    final logs = <String>[];

    final result = await runWithNativeScreenPackageGraphForTesting(
      packageGraphSource: _screenSourcePackageGraph,
      body: () => testBuilder(
        UserA2uiCatalogBuilder(BuilderOptions.empty),
        const <String, String>{
          'apps_examples|lib/onboarding/screens/order_screen.dart': source,
          'apps_examples|pubspec.yaml': _screenSourcePubspec,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
        onLog: (record) => logs.add(record.message),
      ),
    );

    expect(result.succeeded, isTrue, reason: logs.join('\n'));
    expect(
      logs.where((message) => message.contains('catalog properties move')),
      hasLength(1),
    );
  });

  for (final decoy in _partDirectiveDecoys.entries) {
    test(
      'A2UI rejects a ${decoy.key} part-directive decoy before empty-index '
      'writes',
      () async {
        final source = _screenWithPartDirectiveDecoy(decoy.value);
        final input = AssetId(
          'apps_examples',
          'lib/onboarding/screens/part_decoy.dart',
        );
        final readerWriter = await readerWriterWithFilesystemSources(
          rootPackage: 'apps_examples',
        );
        readerWriter.testing
          ..writeString(input, source)
          ..writeString(
            AssetId('apps_examples', 'pubspec.yaml'),
            _screenSourcePubspec,
          )
          ..writeString(
            AssetId('apps_examples', '.dart_tool/package_graph.json'),
            _screenSourcePackageGraph,
          );
        final logs = <String>[];

        final result = await runWithNativeScreenPackageGraphForTesting(
          packageGraphSource: _screenSourcePackageGraph,
          body: () => testBuilder(
            UserA2uiCatalogBuilder(BuilderOptions.empty),
            {
              'apps_examples|${input.path}': source,
              'apps_examples|pubspec.yaml': _screenSourcePubspec,
            },
            rootPackage: 'apps_examples',
            readerWriter: readerWriter,
            flattenOutput: true,
            onLog: (record) => logs.add(record.message),
            outputs: const {},
          ),
        );

        expect(result.succeeded, isFalse);
        expect(logs.join('\n'), contains('missingPartDirective'));
        for (final path in const <String>[
          'lib/generated/restage_a2ui_catalog.g.dart',
          'lib/generated/restage_a2ui_catalog.a2ui.json',
        ]) {
          expect(
            result.readerWriter.testing.exists(
              AssetId('apps_examples', path),
            ),
            isFalse,
            reason: '$path must not be emitted from an invalid empty index',
          );
        }
      },
    );
  }

  test('A2UI rejects an abstract ScreenSource before generated construction',
      () async {
    const source = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart' as restage;

part 'restage.generated/abstract_screen.restage.g.dart';

@restage.ScreenSource(id: 'abstract_screen')
abstract class AbstractScreen extends StatelessWidget {
  const AbstractScreen({super.key});
}
''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'apps_examples',
    );
    readerWriter.testing
      ..writeString(
        AssetId(
          'apps_examples',
          'lib/onboarding/screens/abstract_screen.dart',
        ),
        source,
      )
      ..writeString(
        AssetId('apps_examples', 'pubspec.yaml'),
        _screenSourcePubspec,
      )
      ..writeString(
        AssetId('apps_examples', '.dart_tool/package_graph.json'),
        _screenSourcePackageGraph,
      );
    final logs = <String>[];

    final result = await runWithNativeScreenPackageGraphForTesting(
      packageGraphSource: _screenSourcePackageGraph,
      body: () => testBuilder(
        UserA2uiCatalogBuilder(BuilderOptions.empty),
        const <String, String>{
          'apps_examples|lib/onboarding/screens/abstract_screen.dart': source,
          'apps_examples|pubspec.yaml': _screenSourcePubspec,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        flattenOutput: true,
        onLog: (record) => logs.add(record.message),
      ),
    );

    expect(result.succeeded, isFalse);
    expect(
      logs.join('\n'),
      allOf(
        contains('has no build() method'),
        contains('lib/onboarding/screens/abstract_screen.dart#AbstractScreen'),
      ),
    );
    expect(
      result.readerWriter.testing.exists(
        AssetId(
          'apps_examples',
          'lib/generated/restage_a2ui_catalog.g.dart',
        ),
      ),
      isFalse,
    );
  });
}

String _screenWithPartDirectiveDecoy(String decoy) => '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

$decoy

@ScreenSource(id: 'part_decoy')
final class PartDecoyScreen extends StatelessWidget {
  const PartDecoyScreen({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _partDirectiveDecoys = <String, String>{
  'comment': "// part 'restage.generated/part_decoy.restage.g.dart';",
  'string':
      "const partDirectiveText = \"part 'restage.generated/part_decoy.restage.g.dart';\";",
};

const _canonicalImplicitNotice = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/implicit_notice.restage.g.dart';

@Screen(surface: Surface.general, version: 2)
final class ImplicitNotice extends StatelessWidget {
  const ImplicitNotice({super.key});

  static const continued = SurfaceEvent<String>('continue');

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _canonicalMessageBundle = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/message_bundle.restage.g.dart';

@Screen(id: 'stable-first', surface: Surface.message)
final class StableFirst extends StatelessWidget {
  const StableFirst({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

@Screen(id: 'stable-second', surface: Surface.message)
final class StableSecond extends StatelessWidget {
  const StableSecond({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _legacyNotice = '''
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

part 'restage.generated/legacy_notice.restage.g.dart';

@ScreenSource(id: 'legacy_notice')
final class LegacyNotice extends StatelessWidget {
  const LegacyNotice({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
''';

const _screenSourcePubspec = '''
name: apps_examples
dependencies:
  flutter: any
  restage: any
  rfw_catalog_schema: any
''';

const _screenSourcePackageGraph = '''
{"roots":["apps_examples"],"packages":[{"name":"apps_examples","version":"0.0.0","dependencies":["flutter","restage","rfw_catalog_schema"],"devDependencies":[]}]}
''';
