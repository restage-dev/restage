import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('RFW callback constructor nullability', () {
    for (final required in const [false, true]) {
      for (final constructorNullable in const [false, true]) {
        for (final signature in const <String?>[
          null,
          'ValueChanged<int>',
        ]) {
          final callbackKind = signature == null ? 'zero-argument' : 'typed';
          test(
            '$callbackKind fallback follows constructor nullability '
            '(required: $required, nullable: $constructorNullable)',
            () {
              final entry = WidgetEntry(
                wireId: WireId.unallocatedWidget,
                name: 'CallbackNullabilityProbe',
                library: WidgetLibrary.core,
                category: WidgetCategory.input,
                description: '',
                flutterType: 'package:test_pkg/w.dart#CallbackNullabilityProbe',
                childrenSlot: ChildrenSlot.none,
                properties: [
                  PropertyEntry(
                    wireId: WireId.unallocatedProperty,
                    name: 'onChanged',
                    type: PropertyType.event,
                    description: '',
                    required: required,
                    constructorNullable: constructorNullable,
                    callbackSignature: signature,
                  ),
                ],
              );

              final source = emitFactoryFunction(entry);
              expect(source, isNotNull);
              final fallback = signature == null ? '?? () {}' : '?? (int _) {}';
              expect(
                source,
                constructorNullable || !required
                    ? isNot(contains(fallback))
                    : contains(fallback),
                reason: 'an optional callback without a recorded default is '
                    'necessarily nullable in Dart; legacy built-in catalog '
                    'entries must preserve that omission even before they '
                    'carry constructorNullable.',
              );
            },
          );
        }
      }
    }

    test('representable event constructor default precedes the no-op', () {
      const callbackLibrary = 'package:test_pkg/callbacks.dart';
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'CallbackDefaultProbe',
        library: WidgetLibrary.core,
        category: WidgetCategory.input,
        description: '',
        flutterType: 'package:test_pkg/w.dart#CallbackDefaultProbe',
        childrenSlot: ChildrenSlot.none,
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'onRetry',
            type: PropertyType.event,
            description: '',
            required: true,
            constructorDefault: DartConstReference(
              libraryUri: callbackLibrary,
              member: 'retryDefault',
            ),
          ),
        ],
      );

      final source = emitFactoryFunction(
        entry,
        aliases: const {callbackLibrary: 'c0'},
      );
      expect(
        source,
        contains(
          "source.voidHandler(<Object>['onRetry']) ?? c0.retryDefault",
        ),
      );
      expect(source, isNot(contains('?? () {}')));
    });

    test(
      'presence callback default distinguishes omission, handler, and null',
      () {
        const callbackLibrary = 'package:test_pkg/callbacks.dart';
        const entry = WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'CallbackDefaultProbe',
          library: WidgetLibrary.core,
          category: WidgetCategory.input,
          description: '',
          flutterType: 'package:test_pkg/w.dart#CallbackDefaultProbe',
          childrenSlot: ChildrenSlot.none,
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: r'on$Retry',
              type: PropertyType.event,
              description: '',
              constructorDefault: DartConstReference(
                libraryUri: callbackLibrary,
                member: 'retryDefault',
              ),
            ),
          ],
        );

        final source = emitFactoryFunction(
          entry,
          aliases: const {callbackLibrary: 'c0'},
        )!;

        expect(
          source,
          contains(r'if (_restagePresenceOn$Retry.supplied) #on$Retry:'),
          reason: 'omission must leave the named argument out so Dart applies '
              'the public constructor default',
        );
        expect(
          source,
          contains(
            r'source.voidHandler(_restagePresenceOn$Retry.valuePath)',
          ),
          reason: 'a supplied event envelope must decode its handler',
        );
        expect(
          source,
          contains(
            r"throw ArgumentError('CallbackDefaultProbe.on\$Retry is required.')",
          ),
          reason: 'a supplied null must fail instead of becoming a no-op',
        );
        expect(source, isNot(contains('?? () {}')));
        expect(source, isNot(contains('c0.retryDefault')));
        expect(source, contains(r"<Object>['on\$Retry']"));
      },
    );

    test(
      'generated customer factory analyzes required callback targets',
      () async {
        const widgetSource = r'''
          import 'package:flutter/widgets.dart';
          import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

          void retryDefault() {}
          const VoidCallback defaultRetry = retryDefault;

          @RestageWidget(
            name: 'CallbackNullabilityProbe',
            library: WidgetLibrary.custom('acme.design_system'),
            category: WidgetCategory.input,
            description: 'RFW callback nullability probe.',
          )
          class CallbackNullabilityProbe extends StatelessWidget {
            const CallbackNullabilityProbe({
              this.$source = 'constructor default',
              this.on$Retry = defaultRetry,
              this.onDefault = defaultRetry,
              required this.onRetry,
              required this.onValue,
              super.key,
            });

            /// A Dart-only identifier with an ordinary constructor default.
            final String $source;

            /// Uses the public callback default only when omitted.
            final VoidCallback on$Retry;

            @RestageProperty(
              description: 'Uses the public callback constructor default.',
              required: true,
            )
            final VoidCallback onDefault;

            /// Retries the operation.
            final VoidCallback onRetry;

            /// Reports a changed value when a listener is available.
            final ValueChanged<int>? onValue;

            @override
            Widget build(BuildContext context) => GestureDetector(
                  onTap: on$Retry,
                  child: Text('$source:${onValue == null ? 'absent' : 'bound'}'),
                );
          }
        ''';
        const widgetPath =
            'apps_examples|lib/widgets/callback_nullability_probe.dart';
        const generatedPath = 'apps_examples|lib/user_factories.g.dart';
        final readerWriter = await readerWriterWithFilesystemSources(
          rootPackage: 'apps_examples',
        );
        readerWriter.testing.writeString(
          AssetId.parse(widgetPath),
          widgetSource,
        );

        final result = await testBuilders(
          [const UserFactoryBuilder(BuilderOptions.empty)],
          {widgetPath: widgetSource},
          rootPackage: 'apps_examples',
          readerWriter: readerWriter,
          flattenOutput: true,
        );
        final generated = result.readerWriter.testing.readString(
          AssetId.parse(generatedPath),
        );

        expect(
          generated,
          allOf(
            contains(
              'onDefault: '
              "source.voidHandler(<Object>['onDefault'])",
            ),
            contains('s0.defaultRetry'),
          ),
          reason: '$widgetPath#CallbackNullabilityProbe.onDefault targets a '
              'required catalog input with a public function default.',
        );
        expect(
          generated,
          allOf(
            contains(r"<Object>['\$source']"),
            contains(r"<Object>['on\$Retry']"),
            contains(r'if (_restagePresenceOn$Retry.supplied)'),
            contains(r'#$source:'),
            contains(r'#on$Retry:'),
            contains('throw ArgumentError('),
            contains(
              r"'CallbackNullabilityProbe.on\$Retry is required.'",
            ),
          ),
          reason: 'ordinary, event, and constructor-presence paths must escape '
              r'Dart-only $ names without changing their identity',
        );
        expect(
          generated,
          contains(
            'onRetry: '
            "source.voidHandler(<Object>['onRetry']) ?? () {}",
          ),
          reason: '$widgetPath#CallbackNullabilityProbe.onRetry targets a '
              'required non-nullable VoidCallback.',
        );
        expect(
          generated,
          allOf(
            contains('onValue: source.handler<ValueChanged<int>>('),
            isNot(contains('?? (int _) {}')),
          ),
          reason: '$widgetPath#CallbackNullabilityProbe.onValue targets a '
              'required nullable ValueChanged<int>?.',
        );

        await resolveSources(
          {
            widgetPath: widgetSource,
            generatedPath: generated,
          },
          (resolver) async {
            final library = await resolver.libraryFor(
              AssetId.parse(generatedPath),
            );
            final resolved =
                await library.session.getResolvedLibraryByElement(library);
            if (resolved is! ResolvedLibraryResult) {
              throw StateError('$generatedPath did not resolve.');
            }
            final errors = [
              for (final unit in resolved.units)
                for (final diagnostic in unit.diagnostics)
                  if (diagnostic.severity == Severity.error)
                    diagnostic.problemMessage.messageText(includeUrl: false),
            ];
            expect(
              errors,
              isEmpty,
              reason: '$generatedPath must analyze both callback targets '
                  'without changing required-nullable absence into a no-op.',
            );
          },
          resolverFor: generatedPath,
          rootPackage: 'apps_examples',
          readAllSourcesFromFilesystem: true,
        );
      },
    );
  });
}
