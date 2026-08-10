import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _libraryDeclaration = '''
@RestageLibrary(
  library: WidgetLibrary.custom('acme.widgets'),
  capabilityVersion: 1,
)
const restageLibrary = 0;
''';

void main() {
  test(
      'nullable named exact customer list preserves null and authored list '
      'values and analyze clean', () async {
    const source = '''
      import 'package:flutter/widgets.dart';
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      $_libraryDeclaration

      @RestageWidget(
        name: 'NullableChildrenProbe',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.layout,
        description: 'A nullable children probe.',
      )
      class NullableChildrenProbe extends StatelessWidget {
        const NullableChildrenProbe({this.regions});

        /// Optional child widgets.
        final List<Widget>? regions;

        @override
        Widget build(BuildContext context) => Column(
          children: regions ?? const <Widget>[],
        );
      }

      @RestageWidget(
        name: 'NullableDefaultChildrenProbe',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.layout,
        description: 'A nullable default children probe.',
      )
      class NullableDefaultChildrenProbe extends StatelessWidget {
        const NullableDefaultChildrenProbe({
          this.regions = const <Widget>[SizedBox.shrink()],
        });

        /// Optional child widgets with a non-null default.
        final List<Widget>? regions;

        @override
        Widget build(BuildContext context) => Column(
          children: regions ?? const <Widget>[],
        );
      }

      @RestageWidget(
        name: 'NonNullableDefaultChildrenProbe',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.layout,
        description: 'A non-nullable default children probe.',
      )
      class NonNullableDefaultChildrenProbe extends StatelessWidget {
        const NonNullableDefaultChildrenProbe({
          this.regions = const <Widget>[SizedBox.shrink()],
        });

        /// Child widgets with a non-null default.
        final List<Widget> regions;

        @override
        Widget build(BuildContext context) => Column(children: regions);
      }
    ''';
    final sources = {
      'apps_examples|lib/nullable_children_probe.dart': source,
    };
    final dart = await _buildFactories(sources);
    final nullable = _factorySource(dart, 'NullableChildrenProbe');
    final nullableDefault =
        _factorySource(dart, 'NullableDefaultChildrenProbe');
    final nonNullableDefault =
        _factorySource(dart, 'NonNullableDefaultChildrenProbe');
    final nullableFlat = nullable.replaceAll(RegExp(r'\s+'), ' ');

    expect(
      nullableFlat,
      contains(
        "regions: source.isList(<Object>['regions']) ? "
        "source.childList(<Object>['regions']) : null,",
      ),
      reason: 'missing and explicit-null inputs must remain null, while both '
          'empty and non-empty authored lists must retain childList lowering',
    );
    expect(
      nullable,
      isNot(contains("regions: source.childList(<Object>['regions'])")),
      reason: 'the direct childList read collapses missing/null to an empty '
          'list',
    );
    expect(
      nullable,
      isNot(contains('const <Widget>[]')),
      reason: 'an empty-list literal must not stand in for constructor null',
    );

    for (final factory in [nullableDefault, nonNullableDefault]) {
      final flat = factory.replaceAll(RegExp(r'\s+'), ' ');
      expect(flat, contains('if (_restagePresenceRegions.supplied)'));
      expect(
        flat,
        contains('source.isList(_restagePresenceRegions.valuePath)'),
        reason: 'authored empty and non-empty lists must stay on the list '
            'decoder path',
      );
    }
    expect(
      nullableDefault.replaceAll(RegExp(r'\s+'), ''),
      contains(':null,'),
      reason: 'an explicit null must not select the non-null constructor '
          'default',
    );
    expect(
      nonNullableDefault,
      contains('NonNullableDefaultChildrenProbe.regions is required.'),
      reason: 'the non-nullable default control must still reject a supplied '
          'null instead of replacing it with an empty list',
    );
    await _expectGeneratedAnalyzesClean(sources, dart);
  });

  test(
      'optional positional exact customer list emits once with its real '
      'binding and analyze clean', () async {
    const source = '''
      import 'package:flutter/widgets.dart';
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      $_libraryDeclaration

      @RestageWidget(
        name: 'PositionalChildrenProbe',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.layout,
        description: 'A positional children probe.',
      )
      class PositionalChildrenProbe extends StatelessWidget {
        const PositionalChildrenProbe([
          this.regions = const <Widget>[],
        ]);

        /// Child widgets.
        final List<Widget> regions;

        @override
        Widget build(BuildContext context) => Column(children: regions);
      }

      @RestageWidget(
        name: 'NullablePositionalChildrenProbe',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.layout,
        description: 'A nullable positional children probe.',
      )
      class NullablePositionalChildrenProbe extends StatelessWidget {
        const NullablePositionalChildrenProbe([
          this.regions = const <Widget>[],
        ]);

        /// Nullable child widgets.
        final List<Widget>? regions;

        @override
        Widget build(BuildContext context) => Column(
          children: regions ?? const <Widget>[],
        );
      }
    ''';
    final sources = {
      'apps_examples|lib/positional_children_probe.dart': source,
    };
    final dart = await _buildFactories(sources);
    final nonNullable = _factorySource(dart, 'PositionalChildrenProbe');
    final nullable = _factorySource(dart, 'NullablePositionalChildrenProbe');

    for (final factory in [nonNullable, nullable]) {
      final flat = factory.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        RegExp('#regions:').allMatches(factory),
        isEmpty,
        reason: 'a positional customer child must never be re-emitted named',
      );
      expect(
        RegExp(r'source\.childList\(').allMatches(factory),
        hasLength(1),
        reason: 'the exact customer list value must be emitted exactly once',
      );
      expect(
        flat,
        contains('if (_restagePresenceRegions.supplied)'),
        reason: 'absence must omit the trailing optional positional slot',
      );
      expect(
        flat,
        contains('source.isList(_restagePresenceRegions.valuePath)'),
        reason: 'a supplied value must retain list-shape validation',
      );
      expect(
        flat,
        isNot(contains('if (_restagePresenceRegions.hasValue)')),
        reason: 'supplied null/missing must not become constructor omission',
      );
      expect(
        factory,
        contains('regions is required.'),
        reason: 'a supplied wrong shape must remain a loud failure',
      );
    }
    expect(
      nonNullable.replaceAll(RegExp(r'\s+'), ''),
      contains(
        ":(throwArgumentError('PositionalChildrenProbe.regionsisrequired.'))",
      ),
      reason: 'supplied null/missing is invalid for a non-nullable slot',
    );
    expect(
      nullable.replaceAll(RegExp(r'\s+'), ''),
      contains(':null,'),
      reason: 'supplied null/missing must remain null for a nullable slot',
    );
    await _expectGeneratedAnalyzesClean(sources, dart);
  });

  test(
      'optional positional gaps use exact defaults without shifting later '
      'values or blocking trailing omission', () async {
    const source = '''
      import 'package:flutter/widgets.dart';
      import 'package:apps_examples/defaults.dart';
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      $_libraryDeclaration

      class Tone {
        const Tone({required this.level});

        final int level;
      }

      @RestageWidget(
        name: 'PositionalGapProbe',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.decoration,
        description: 'A positional default gap probe.',
      )
      class PositionalGapProbe extends StatelessWidget {
        const PositionalGapProbe([
          this.tones = const <Tone>[Tone(level: Defaults.level)],
          this.label = 'fallback',
        ]);

        /// Display tones.
        final List<Tone> tones;

        /// Display label.
        final String label;

        @override
        Widget build(BuildContext context) => Text(label);
      }

      @RestageWidget(
        name: 'ForcedPositionalGapProbe',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.decoration,
        description: 'A forced positional default gap probe.',
      )
      class ForcedPositionalGapProbe extends StatelessWidget {
        const ForcedPositionalGapProbe([
          this.tones = const <Tone>[Tone(level: Defaults.level)],
          this.tail,
        ]);

        /// Display tones.
        final List<Tone> tones;

        /// Optional tail label.
        final String? tail;

        @override
        Widget build(BuildContext context) => Text(tail ?? 'none');
      }
    ''';
    const defaults = '''
      class Defaults {
        static const level = 2;
      }
    ''';
    final sources = {
      'apps_examples|lib/positional_gap_probe.dart': source,
      'apps_examples|lib/defaults.dart': defaults,
    };
    final dart = await _buildFactories(sources);
    final gap = _factorySource(dart, 'PositionalGapProbe');
    final forced = _factorySource(dart, 'ForcedPositionalGapProbe');
    final gapFlat = gap.replaceAll(RegExp(r'\s+'), ' ');
    final forcedFlat = forced.replaceAll(RegExp(r'\s+'), ' ');

    expect(
      dart,
      contains("import 'package:apps_examples/defaults.dart' as"),
      reason: 'the exact default used to fill a positional gap needs its '
          'public nested identity import',
    );
    expect(gap, isNot(contains('#tones:')));
    expect(gap, isNot(contains('#label:')));
    expect(
      gapFlat,
      contains(
        'if (_restagePresenceTones.supplied || '
        '_restagePresenceLabel.supplied)',
      ),
      reason: 'a later supplied slot must extend the contiguous prefix',
    );
    expect(
      gapFlat,
      contains('_restagePresenceTones.supplied ?'),
      reason: 'a supplied first slot must retain its supplied value semantics',
    );
    expect(
      gapFlat,
      contains('Defaults.level'),
      reason: 'an absent gap before a supplied value needs the exact default',
    );
    expect(
      gapFlat,
      contains('if (_restagePresenceLabel.supplied)'),
      reason: 'the final absent optional slot must remain a trailing omission',
    );
    expect(
      gapFlat,
      isNot(contains('_restagePresenceTones.hasValue ? const')),
      reason: 'supplied null/wrong shape must not select the gap default',
    );

    expect(
      forcedFlat,
      contains('_restagePresenceTones.supplied ?'),
      reason: 'an unconditionally emitted later slot must force the earlier '
          'slot into the prefix',
    );
    expect(
      forcedFlat,
      isNot(contains('if (_restagePresenceTones.supplied)')),
      reason: 'the forced prefix must not conditionally omit its first slot',
    );
    expect(forcedFlat, contains('Defaults.level'));
    expect(forced, isNot(contains('#tones:')));
    expect(forced, isNot(contains('#tail:')));
    await _expectGeneratedAnalyzesClean(sources, dart);
  });

  test(
      'trailing structured-list omission prunes an unused nested default '
      'identity import', () async {
    const source = '''
      import 'package:flutter/widgets.dart';
      import 'package:apps_examples/defaults.dart';
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      $_libraryDeclaration

      class Tone {
        const Tone({required this.level});

        final int level;
      }

      @RestageWidget(
        name: 'StructuredListDefaultProbe',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.decoration,
        description: 'A structured list default probe.',
      )
      class StructuredListDefaultProbe extends StatelessWidget {
        const StructuredListDefaultProbe({
          this.tones = const <Tone>[Tone(level: Defaults.level)],
        });

        /// Display tones.
        final List<Tone> tones;

        @override
        Widget build(BuildContext context) => const SizedBox.shrink();
      }
    ''';
    const defaults = '''
      class Defaults {
        static const level = 2;
      }
    ''';
    final sources = {
      'apps_examples|lib/structured_list_default_probe.dart': source,
      'apps_examples|lib/defaults.dart': defaults,
    };
    final dart = await _buildFactories(sources);

    expect(
      dart,
      isNot(contains("import 'package:apps_examples/defaults.dart'")),
      reason: 'Dart applies the trailing structured-list constructor default, '
          'so its nested identity must not leave a stale import',
    );
    expect(
      dart,
      isNot(contains('Defaults.level')),
      reason: 'the omitted default must not be reconstructed in the factory',
    );
    expect(
      dart.replaceAll(RegExp(r'\s+'), ' '),
      contains('if (_restagePresenceTones.supplied) #tones:'),
      reason: 'the import is pruned only because the default is truly omitted',
    );
    await _expectGeneratedAnalyzesClean(sources, dart);
  });
}

Future<String> _buildFactories(Map<String, String> sources) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }
  final result = await testBuilders(
    [const UserFactoryBuilder(BuilderOptions.empty)],
    sources,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  return result.readerWriter.testing.readString(
    AssetId('apps_examples', 'lib/user_factories.g.dart'),
  );
}

String _factorySource(
  String dart,
  String widgetName,
) {
  final start = dart.indexOf('Widget _build$widgetName');
  expect(start, isNonNegative, reason: '$widgetName factory was not emitted');
  final nextFactory = dart.indexOf('\nWidget _build', start + 1);
  final end = nextFactory < 0 ? dart.length : nextFactory;
  return dart.substring(start, end);
}

Future<void> _expectGeneratedAnalyzesClean(
  Map<String, String> sources,
  String generated,
) async {
  const generatedId = 'apps_examples|lib/user_factories.g.dart';
  await resolveSources(
    {...sources, generatedId: generated},
    (resolver) async {
      final library = await resolver.libraryFor(AssetId.parse(generatedId));
      final resolved =
          await library.session.getResolvedLibraryByElement(library);
      if (resolved is! ResolvedLibraryResult) {
        throw StateError('Generated user_factories.g.dart did not resolve.');
      }
      final diagnostics = [
        for (final unit in resolved.units)
          for (final diagnostic in unit.diagnostics)
            if (diagnostic.severity == Severity.error ||
                diagnostic.severity == Severity.warning)
              _diagnosticText(diagnostic),
      ];
      expect(
        diagnostics,
        isEmpty,
        reason: 'generated factories must have no errors or warnings:\n'
            '$generated',
      );
    },
    resolverFor: generatedId,
    rootPackage: 'apps_examples',
    readAllSourcesFromFilesystem: true,
  );
}

String _diagnosticText(Diagnostic diagnostic) {
  final code = diagnostic.diagnosticCode.lowerCaseName;
  final message = diagnostic.problemMessage.messageText(includeUrl: false);
  return '$code: $message';
}
