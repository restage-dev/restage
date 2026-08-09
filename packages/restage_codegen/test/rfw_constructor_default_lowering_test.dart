import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test(
      'production factory builder lowers references, invocations, collections, '
      'children, and structured-default omission', () async {
    const source = '''
      import 'package:flutter/widgets.dart';
      import 'package:apps_examples/defaults.dart';
      import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

      @RestageLibrary(
        library: WidgetLibrary.custom('acme.widgets'),
        capabilityVersion: 1,
      )
      const restageLibrary = 0;

      class Tokens {
        static const retries = 3;
      }

      const defaultTimeout = 5;

      class Tone {
        const Tone({required this.level});

        final int level;
      }

      @RestageWidget(
        name: 'DefaultProbe',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.decoration,
        description: 'a constructor-default probe',
        childrenSlot: ChildrenSlot.list,
      )
      class DefaultProbe extends StatelessWidget {
        const DefaultProbe({
          this.retries = Tokens.retries,
          this.timeout = defaultTimeout,
          this.color = const Color(0xFF123456),
          this.labels = const <String>['first', 'second'],
          this.tone = const Tone(level: Defaults.level),
          this.nullableTone = const Tone(level: Defaults.level),
          this.tones = const <Tone>[Tone(level: Defaults.level)],
          this.nullableTones = const <Tone>[Tone(level: Defaults.level)],
          this.scores = const <String, int>{'first': 1},
          this.summary = (count: 1, label: 'first'),
          this.nullableSummary = (count: 1, label: 'first'),
          this.child = const SizedBox.shrink(),
          this.children = const <Widget>[SizedBox.shrink()],
          super.key,
        });

        /// Retry count.
        final int retries;
        /// Timeout count.
        final int timeout;
        /// Brand color.
        final Color color;
        /// Visible labels.
        final List<String> labels;
        /// Display tone.
        final Tone tone;
        /// Nullable display tone.
        final Tone? nullableTone;
        /// Display tones.
        final List<Tone> tones;
        /// Nullable display tones.
        final List<Tone>? nullableTones;
        /// Scores by label.
        final Map<String, int> scores;
        /// Summary values.
        final ({int count, String label}) summary;
        /// Nullable summary values.
        final ({int count, String label})? nullableSummary;
        /// Default child.
        final Widget child;
        /// Default children.
        final List<Widget> children;

        @override
        Widget build(BuildContext context) => child;
      }

      @RestageWidget(
        name: 'NullableChildrenProbe',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.decoration,
        description: 'a nullable children constructor-default probe',
        childrenSlot: ChildrenSlot.list,
      )
      class NullableChildrenProbe extends StatelessWidget {
        const NullableChildrenProbe({
          this.children = const <Widget>[SizedBox.shrink()],
          super.key,
        });

        /// Nullable default children.
        final List<Widget>? children;

        @override
        Widget build(BuildContext context) => Column(
          children: children ?? const <Widget>[],
        );
      }
    ''';
    final readerWriter = await readerWriterWithFilesystemSources(
      rootPackage: 'restage_codegen',
      includeFlutter: true,
    );
    const defaults = '''
      class Defaults {
        static const level = 2;
      }
    ''';
    readerWriter.testing
      ..writeString(
        AssetId('apps_examples', 'lib/default_probe.dart'),
        source,
      )
      ..writeString(
        AssetId('apps_examples', 'lib/defaults.dart'),
        defaults,
      );

    final result = await testBuilder(
      const UserFactoryBuilder(BuilderOptions.empty),
      const {
        'apps_examples|lib/default_probe.dart': source,
        'apps_examples|lib/defaults.dart': defaults,
      },
      rootPackage: 'apps_examples',
      readerWriter: readerWriter,
      flattenOutput: true,
    );

    expect(result.succeeded, isTrue);
    final dart = String.fromCharCodes(
      result.readerWriter.testing.readBytes(
        AssetId('apps_examples', 'lib/user_factories.g.dart'),
      ),
    );
    final flat = dart.replaceAll(RegExp(r'\s+'), ' ');
    String presenceLocal(String property) =>
        '_restagePresence${property[0].toUpperCase()}'
        '${property.substring(1)}';
    String argumentSource(String property) {
      final start = flat.indexOf('#$property:');
      expect(
        start,
        isNonNegative,
        reason: '$property argument was not emitted',
      );
      final nextArgument = flat.indexOf(', if (', start);
      final end = nextArgument < 0 ? flat.indexOf(', },', start) : nextArgument;
      expect(end, isNonNegative, reason: '$property argument was not closed');
      return flat.substring(start, end);
    }

    String compactArgumentSource(String property) =>
        argumentSource(property).replaceAll(' ', '');

    expect(dart, isNot(contains('Tokens.retries')));
    expect(dart, isNot(contains('defaultTimeout')));
    expect(dart, isNot(contains('Color.new(4279383126)')));
    expect(
      flat,
      contains(
        'if (_restagePresenceRetries.supplied) '
        '#retries: source.v<int>(_restagePresenceRetries.valuePath)',
      ),
      reason: 'Function.apply must include a supplied scalar even when its '
          'decoded value is null or the wrong scalar type',
    );
    expect(
      flat,
      isNot(
        contains(
          'if (_restagePresenceRetries.hasValue) #retries:',
        ),
      ),
    );
    expect(
      flat,
      isNot(contains('_restagePresenceRetries.valuePath) ?? Tokens.retries')),
      reason: 'a supplied malformed scalar must not silently take the Dart '
          'constructor default',
    );
    expect(
      dart,
      isNot(contains('#labels:')),
      reason: 'RFW has no direct scalar-list wire shape, so Dart must apply '
          'the constructor default instead of leaking A2UI vocabulary',
    );
    for (final property in [
      'tone',
      'nullableTone',
      'tones',
      'nullableTones',
      'scores',
      'summary',
      'nullableSummary',
      'children',
    ]) {
      final local = presenceLocal(property);
      expect(
        flat,
        contains('if ($local.supplied) #$property:'),
        reason: '$property must be passed based on supplied, not hasValue',
      );
      expect(
        flat,
        isNot(contains('if ($local.hasValue) #$property:')),
        reason: '$property must not turn supplied null into omission/default',
      );
      expect(
        flat,
        contains('$local.hasValue'),
        reason: '$property must distinguish supplied no-value from wrong '
            'shape',
      );
    }
    for (final property in [
      'tone',
      'nullableTone',
      'summary',
      'nullableSummary',
    ]) {
      final local = presenceLocal(property);
      expect(
        compactArgumentSource(property),
        contains(
          'source.isMap(<Object>[...$local.valuePath])'.replaceAll(' ', ''),
        ),
        reason: '$property must reconstruct only an expected map shape',
      );
    }
    for (final property in [
      'tones',
      'nullableTones',
      'scores',
    ]) {
      final local = presenceLocal(property);
      expect(
        compactArgumentSource(property),
        contains(
          'source.isList(<Object>[...$local.valuePath])'.replaceAll(' ', ''),
        ),
        reason: '$property must reconstruct only an expected list shape',
      );
    }
    expect(
      flat,
      contains('source.isList(_restagePresenceChildren.valuePath)'),
      reason: 'canonical children must validate the nested supplied value',
    );
    for (final property in ['tone', 'tones', 'scores', 'summary', 'children']) {
      final local = presenceLocal(property);
      expect(
        dart,
        contains('DefaultProbe.$property is required.'),
        reason: '$property is nonnullable and supplied no-value must throw',
      );
      final expectedNoValue =
          ": (throw ArgumentError('DefaultProbe.$property is required.'))"
              .replaceAll(' ', '');
      expect(
        compactArgumentSource(property),
        allOf(contains('$local.hasValue?'), endsWith(expectedNoValue)),
        reason: '$property must not route supplied no-value to its default',
      );
    }
    for (final property in [
      'nullableTone',
      'nullableTones',
      'nullableSummary',
    ]) {
      final local = presenceLocal(property);
      expect(
        compactArgumentSource(property),
        allOf(contains('$local.hasValue?'), endsWith(':null')),
        reason: '$property must route supplied no-value to null',
      );
      expect(
        flat,
        contains('DefaultProbe.$property is required.'),
        reason: '$property must still throw when a supplied value has the '
            'wrong shape',
      );
    }
    expect(
      flat,
      contains(
        'source.childList(_restagePresenceChildren.valuePath)',
      ),
    );
    expect(
      dart,
      contains('NullableChildrenProbe.children is required.'),
      reason: 'wrong-shape nullable children must throw even though supplied '
          'no-value becomes null',
    );
    expect(
      flat,
      contains('Widget _buildNullableChildrenProbe'),
    );
    final nullableChildrenFactory = flat.substring(
      flat.indexOf('Widget _buildNullableChildrenProbe'),
    );
    expect(
      nullableChildrenFactory.replaceAll(' ', ''),
      allOf(
        contains('#children:_restagePresenceChildren.hasValue?'),
        contains(':null,'),
      ),
      reason: 'nullable canonical children must preserve supplied null',
    );
    expect(dart, isNot(contains('defaults.dart')));
    expect(dart, isNot(contains('const SizedBox.shrink()')));
    expect(dart, isNot(contains('const [const SizedBox.shrink()]')));
    expect(dart, isNot(contains('CatalogItem(')));
    expect(dart, isNot(contains(r'$RestageExclusions')));
  });
}
