import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/a2ui/user_a2ui_catalog_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

/// Classifier-coverage fail-loud guards: a classify-level scope-out must be as
/// loud as the walk / seam gates. Without the coverage gate, a widget the
/// classifier drops silently vanishes from BOTH outputs (the generated Dart
/// catalog and the capability stamp) under a green build, and an omitted field
/// whose constructor parameter is required emits a constructor call missing a
/// required argument — uncompilable generated code, still under a green build.
///
/// Each test drives the real `UserA2uiCatalogBuilder` over a customer package
/// and asserts the build FAILS with a diagnostic naming the widget, the
/// property, and the reason (customer-actionable), mirroring
/// `a2ui_builder_fail_loud_guards_test.dart`. The last test proves the
/// non-fatal leg: an omitted OPTIONAL property builds green with a WARNING.
Future<(bool succeeded, String logs)> _runBuilder(
  Map<String, String> sources,
) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'restage_codegen',
    includeFlutter: true,
  );
  for (final entry in sources.entries) {
    readerWriter.testing.writeString(
      AssetId('apps_examples', entry.key),
      entry.value,
    );
  }
  final logs = <String>[];
  final result = await testBuilder(
    const UserA2uiCatalogBuilder(BuilderOptions.empty),
    {for (final e in sources.entries) 'apps_examples|${e.key}': e.value},
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
    onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
  );
  return (result.succeeded, logs.join('\n'));
}

/// The shared `@RestageLibrary` barrel declaring the custom library.
const _libraryDeclaration = '''
  import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
  @RestageLibrary(
    library: WidgetLibrary.custom('acme.widgets'),
    capabilityVersion: 1,
  )
  const restageLibrary = 0;
''';

void main() {
  group('UserA2uiCatalogBuilder — classifier coverage fails loud', () {
    test(
        'a required callback with an unsupported signature fails loud naming '
        'the widget, the callback, and the reason — never a silent drop from '
        'both outputs', () async {
      // A three-argument callback has no declarative lowering. Marked required
      // on the catalog AND the constructor, the widget cannot be emitted — the
      // build must fail loud, not quietly emit a catalog without the widget.
      const source = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageWidget(
          name: 'Scrubber',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.input,
          description: 'a widget with an unlowerable callback',
        )
        class Scrubber {
          const Scrubber({required this.label, required this.onScrub});
          @RestageProperty(description: 'the label')
          final String label;
          @RestageProperty(description: 'scrub callback', required: true)
          final void Function(String, int, double) onScrub;
        }
      ''';

      final (succeeded, logs) = await _runBuilder({
        'lib/lib.dart': _libraryDeclaration,
        'lib/scrubber.dart': source,
      });

      expect(succeeded, isFalse);
      expect(logs, contains('Scrubber'));
      expect(logs, contains('onScrub'));
      expect(logs, contains('callback signature has no declarative lowering'));
    });

    test(
        'a required property whose name collides with a reserved generated '
        'identifier fails loud (the emitted constructor call would miss a '
        'required argument)', () async {
      // `data` is a reserved identifier in the generated widget builders, so
      // the field is scoped out of the emit — but the constructor requires it,
      // so the generated code would not compile. Fail loud with the rename fix.
      const source = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageWidget(
          name: 'Ticker',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.decoration,
          description: 'a widget with a reserved-name property',
        )
        class Ticker {
          const Ticker({required this.data});
          @RestageProperty(description: 'the text')
          final String data;
        }
      ''';

      final (succeeded, logs) = await _runBuilder({
        'lib/lib.dart': _libraryDeclaration,
        'lib/ticker.dart': source,
      });

      expect(succeeded, isFalse);
      expect(logs, contains('Ticker'));
      expect(logs, contains("'data'"));
      expect(logs, contains('reserved identifier'));
    });

    for (final fieldName in const ['id', 'component']) {
      final sourceShapes = <String, ({String declarations, String type})>{
        'scalar': (declarations: '', type: 'String'),
        'rich-data': (
          declarations: '''
          class Details {
            const Details({required this.label});
            final String label;
          }
        ''',
          type: 'Details',
        ),
        'child': (
          declarations: '''
          import 'package:flutter/widgets.dart';
        ''',
          type: 'Widget',
        ),
      };

      for (final sourceShape in sourceShapes.entries) {
        test(
            "top-level envelope field '$fieldName' fails loud before "
            '${sourceShape.key} admission', () async {
          final source = '''
            import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
            ${sourceShape.value.declarations}
            @RestageWidget(
              name: 'EnvelopeCollision',
              library: WidgetLibrary.custom('acme.widgets'),
              category: WidgetCategory.decoration,
              description: 'a widget with an envelope-name collision',
            )
            class EnvelopeCollision {
              const EnvelopeCollision({required this.$fieldName});
              @RestageProperty(description: 'an envelope-name collision')
              final ${sourceShape.value.type} $fieldName;
            }
          ''';

          final (succeeded, logs) = await _runBuilder({
            'lib/lib.dart': _libraryDeclaration,
            'lib/envelope_collision.dart': source,
          });

          expect(succeeded, isFalse);
          expect(logs, contains('EnvelopeCollision'));
          expect(logs, contains("'$fieldName'"));
          expect(logs, contains('GenUI component envelope'));
          expect(logs, contains('rename the property'));
        });
      }

      test(
          "optional top-level envelope field '$fieldName' is fatal, not a "
          'coverage warning', () async {
        final source = '''
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
          @RestageWidget(
            name: 'OptionalEnvelopeCollision',
            library: WidgetLibrary.custom('acme.widgets'),
            category: WidgetCategory.decoration,
            description: 'a widget with an optional envelope collision',
          )
          class OptionalEnvelopeCollision {
            const OptionalEnvelopeCollision({this.$fieldName});
            @RestageProperty(description: 'an optional collision')
            final String? $fieldName;
          }
        ''';

        final (succeeded, logs) = await _runBuilder({
          'lib/lib.dart': _libraryDeclaration,
          'lib/optional_envelope_collision.dart': source,
        });

        expect(succeeded, isFalse);
        expect(logs, contains('OptionalEnvelopeCollision'));
        expect(logs, contains("'$fieldName'"));
        expect(logs, contains('GenUI component envelope'));
        expect(logs, isNot(contains('WARNING')));
      });
    }

    test('nested rich-data id and component members remain legal', () async {
      const source = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        class Details {
          const Details({required this.id, required this.component});
          final String id;
          final String component;
        }
        @RestageWidget(
          name: 'NestedEnvelopeNames',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.decoration,
          description: 'a widget with legal nested envelope names',
        )
        class NestedEnvelopeNames {
          const NestedEnvelopeNames({required this.details});
          @RestageProperty(description: 'the nested details')
          final Details details;
        }
      ''';

      final (succeeded, logs) = await _runBuilder({
        'lib/lib.dart': _libraryDeclaration,
        'lib/nested_envelope_names.dart': source,
      });

      expect(succeeded, isTrue, reason: logs);
      expect(logs, isNot(contains('GenUI component envelope')));
    });

    test(
        'two unannotated write-back callbacks the constructor requires fail '
        'loud as an ambiguous pairing (never an emit missing required '
        'constructor arguments)', () async {
      // Two value-callbacks over the same value type cannot be auto-paired to
      // the single `value` property. Both are constructor-required, so the
      // scoped-out fields would leave the generated constructor call
      // uncompilable. Fail loud pointing at the explicit-pairing annotation.
      const source = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageWidget(
          name: 'DualKnob',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.input,
          description: 'a widget with an ambiguous write-back pairing',
        )
        class DualKnob {
          const DualKnob({
            required this.value,
            required this.onCoarse,
            required this.onFine,
          });
          @RestageProperty(description: 'the value')
          final double value;
          @RestageProperty(description: 'coarse change')
          final void Function(double) onCoarse;
          @RestageProperty(description: 'fine change')
          final void Function(double) onFine;
        }
      ''';

      final (succeeded, logs) = await _runBuilder({
        'lib/lib.dart': _libraryDeclaration,
        'lib/dual_knob.dart': source,
      });

      expect(succeeded, isFalse);
      expect(logs, contains('DualKnob'));
      expect(logs, contains('onCoarse'));
      expect(logs, contains('onFine'));
      expect(logs, contains('writeBackValue'));
    });

    test(
        'the A2UI target derives a required non-nullable child from its '
        'constructor even without annotation duplication', () async {
      // The named A2UI visitor target marks this constructor-required child as
      // schema-required and the emitter therefore null-asserts the child
      // lookup. The old annotation-only gap must no longer trip the coverage
      // guard or emit an uncompilable nullable argument.
      const source = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        import 'package:flutter/widgets.dart';
        @RestageWidget(
          name: 'Framed',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.layout,
          description: 'a widget with a non-nullable child slot',
        )
        class Framed {
          const Framed({required this.child});
          @RestageProperty(description: 'the framed child')
          final Widget child;
        }
      ''';

      final (succeeded, logs) = await _runBuilder({
        'lib/lib.dart': _libraryDeclaration,
        'lib/framed.dart': source,
      });

      expect(succeeded, isTrue, reason: logs);
      expect(logs, isNot(contains("Declare the parameter 'Widget?'")));
    });

    test(
        'an omitted OPTIONAL property builds green with a WARNING naming the '
        'widget, the field, and the reason (contract-narrowing, not fatal)',
        () async {
      // `Curve` is a catalog property type with no A2UI data lowering. The
      // constructor parameter is optional, so the widget still compiles and
      // renders without it — the build stays green but must say what was
      // narrowed out of the advertised contract.
      const source = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        import 'package:flutter/widgets.dart';
        @RestageWidget(
          name: 'Fader',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.decoration,
          description: 'a widget with an optional unlowerable property',
        )
        class Fader {
          const Fader({required this.label, this.easing});
          @RestageProperty(description: 'the label')
          final String label;
          @RestageProperty(description: 'the easing curve')
          final Curve? easing;
        }
      ''';

      final (succeeded, logs) = await _runBuilder({
        'lib/lib.dart': _libraryDeclaration,
        'lib/fader.dart': source,
      });

      expect(succeeded, isTrue);
      expect(logs, contains('WARNING'));
      expect(logs, contains('Fader'));
      expect(logs, contains("'easing'"));
      expect(logs, contains('omitted from the A2UI catalog'));
    });
  });
}
