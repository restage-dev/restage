import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/dart_import_planner.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('DartImportPlanner', () {
    test('plans dart and public Flutter barrels deterministically', () {
      final planner = DartImportPlanner(
        libraryUris: const {
          'package:flutter/src/material/colors.dart',
          'dart:core',
          'package:flutter/src/cupertino/colors.dart',
          'dart:math',
        },
        prefixStem: 'i',
      );

      expect(
        planner.importDirectives,
        equals([
          "import 'dart:math' as i0;",
          "import 'package:flutter/cupertino.dart' as i1;",
          "import 'package:flutter/material.dart' as i2;",
        ]),
      );
      expect(planner.qualify('dart:core', 'String'), 'String');
      expect(
        planner.qualify(
          'package:flutter/src/material/colors.dart',
          'Colors',
        ),
        'i2.Colors',
      );
      expect(
        planner.qualify(
          'package:flutter/src/cupertino/colors.dart',
          'CupertinoColors',
        ),
        'i1.CupertinoColors',
      );
    });

    test('plans narrow bare type imports beside deterministic prefixes', () {
      final planner = DartImportPlanner(
        libraryUris: const {
          'dart:core',
          'dart:ui',
          'package:fixture/models.dart',
        },
        prefixStem: 'i',
        bareSymbolImports: const [
          DartBareSymbolImport(
            libraryUri: 'dart:core',
            symbol: 'String',
            sourcePath: 'lib/card.dart#Card.title',
          ),
          DartBareSymbolImport(
            libraryUri: 'dart:ui',
            symbol: 'Color',
            sourcePath: 'lib/card.dart#Card.color',
          ),
          DartBareSymbolImport(
            libraryUri: 'package:fixture/models.dart',
            symbol: 'CardData',
            sourcePath: 'lib/card.dart#Card.data',
          ),
          DartBareSymbolImport(
            libraryUri: 'package:fixture/models.dart',
            symbol: 'BadgeData',
            sourcePath: 'lib/card.dart#Card.badge',
          ),
        ],
      );

      expect(
        planner.importDirectives,
        equals([
          "import 'dart:ui' as i0;",
          "import 'package:fixture/models.dart' as i1;",
          "import 'dart:ui' show Color;",
          "import 'package:fixture/models.dart' show BadgeData, CardData;",
        ]),
      );
      expect(planner.qualify('dart:ui', 'Color'), 'i0.Color');
    });

    test('rejects ambiguous bare type imports', () {
      expect(
        () => DartImportPlanner(
          libraryUris: const {'package:first.dart', 'package:second.dart'},
          bareSymbolImports: const [
            DartBareSymbolImport(
              libraryUri: 'package:first.dart',
              symbol: 'Same',
              sourcePath: 'lib/card.dart#Card.first',
            ),
            DartBareSymbolImport(
              libraryUri: 'package:second.dart',
              symbol: 'Same',
              sourcePath: 'lib/card.dart#Card.second',
            ),
          ],
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('cannot be imported bare'),
              contains('lib/card.dart#Card.first'),
              contains('lib/card.dart#Card.second'),
            ),
          ),
        ),
      );
    });

    test('rejects a Widgetbook Meta collision at the property source path', () {
      expect(
        () => DartImportPlanner(
          libraryUris: const {'package:fixture/models.dart'},
          bareSymbolImports: const [
            DartBareSymbolImport(
              libraryUri: 'package:fixture/models.dart',
              symbol: 'Meta',
              sourcePath: 'lib/card.dart#Card.meta',
            ),
          ],
          bareSymbolReservations: const [
            DartBareSymbolReservation(
              libraryUri: 'package:widgetbook/src/core/framework/meta.dart',
              symbol: 'Meta',
              source: 'package:widgetbook/widgetbook.dart export',
            ),
          ],
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('lib/card.dart#Card.meta'),
              contains('package:fixture/models.dart#Meta'),
              contains('package:widgetbook/widgetbook.dart export'),
            ),
          ),
        ),
      );
    });

    test('rejects conflicting existing bare namespace bindings', () {
      expect(
        () => DartImportPlanner(
          libraryUris: const {'package:fixture/config.dart'},
          bareSymbolReservations: const [
            DartBareSymbolReservation(
              libraryUri: 'package:fixture/config.dart',
              symbol: 'Config',
              source: 'source widget import at lib/config.dart#Config',
            ),
            DartBareSymbolReservation(
              libraryUri: 'package:widgetbook/src/config.dart',
              symbol: 'Config',
              source: 'package:widgetbook/widgetbook.dart export',
            ),
          ],
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('conflicting bare namespace bindings'),
              contains('lib/config.dart#Config'),
              contains('package:widgetbook/widgetbook.dart export'),
            ),
          ),
        ),
      );
    });

    test('uses an existing source show binding for the same bare identity', () {
      final planner = DartImportPlanner(
        libraryUris: const {'package:fixture/customer_card.dart'},
        fixedPrefixes: const {
          'package:fixture/customer_card.dart': 'restage_source',
        },
        bareSymbolImports: const [
          DartBareSymbolImport(
            libraryUri: 'package:fixture/customer_card.dart',
            symbol: 'CustomerCard',
            sourcePath: 'lib/customer_card.dart#CustomerCard',
          ),
        ],
        bareSymbolReservations: const [
          DartBareSymbolReservation(
            libraryUri: 'package:fixture/customer_card.dart',
            symbol: 'CustomerCard',
            source:
                'source widget import at lib/customer_card.dart#CustomerCard',
          ),
        ],
      );

      expect(
        planner.importDirectives,
        [
          "import 'package:fixture/customer_card.dart' as restage_source;",
        ],
      );
    });

    test('rejects a bare type that collides with an assigned prefix', () {
      expect(
        () => DartImportPlanner(
          libraryUris: const {
            'package:fixture/models.dart',
            'package:fixture/other.dart',
          },
          prefixStem: 'model',
          bareSymbolImports: const [
            DartBareSymbolImport(
              libraryUri: 'package:fixture/models.dart',
              symbol: 'model0',
              sourcePath: 'lib/card.dart#Card.data',
            ),
          ],
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('lib/card.dart#Card.data'),
              contains('import prefix model0'),
            ),
          ),
        ),
      );
    });

    test('renders every type argument and outer nullability from identity', () {
      const type = DartTypeIdentity(
        libraryUri: 'package:boxes/box.dart',
        symbolName: 'Box',
        nullable: true,
        typeArguments: [
          DartTypeIdentity(
            libraryUri: 'package:first/model.dart',
            symbolName: 'Same',
            nullable: true,
          ),
          DartTypeIdentity(
            libraryUri: 'package:second/model.dart',
            symbolName: 'Same',
          ),
        ],
      );
      final planner = DartImportPlanner(
        libraryUris: dartTypeIdentityLibraryUris(type),
        prefixStem: 'i',
      );

      expect(
        planner.renderType(type),
        'i0.Box<i1.Same?, i2.Same>?',
      );
    });

    test('renders Dart core keyword type identities only from Dart core', () {
      final planner = DartImportPlanner(
        libraryUris: const {'dart:core', 'package:fixture/model.dart'},
      );

      for (final symbolName in ['dynamic', 'Function', 'void']) {
        expect(
          planner.renderType(
            DartTypeIdentity(
              libraryUri: 'dart:core',
              symbolName: symbolName,
            ),
          ),
          symbolName,
        );
      }
      expect(
        () => planner.renderType(
          const DartTypeIdentity(
            libraryUri: 'package:fixture/model.dart',
            symbolName: 'dynamic',
          ),
        ),
        throwsStateError,
      );
    });

    test('contextual identifiers analyze in every emitted position', () async {
      const source = '''
import 'dart:math' as augment;

class base {
  const base.as({int required = 0, this.interface = 0})
      : required = required;

  final int required;
  final int interface;
  static const int dynamic = 1;
}

typedef when = ({int as, int dynamic});

const base value = base.as(required: 1, interface: 2);
const when record = (as: 3, dynamic: 4);
final selected = value.interface + base.dynamic;
final prefixed = augment.pi;
''';
      final parsed = parseString(content: source, throwIfDiagnostics: false);
      expect(parsed.errors, isEmpty, reason: source);

      await resolveSources(
        {'restage_codegen|lib/contextual_identifier_fixture.dart': source},
        (resolver) async {
          final library = await resolver.libraryFor(
            AssetId(
              'restage_codegen',
              'lib/contextual_identifier_fixture.dart',
            ),
          );
          final resolved =
              await library.session.getResolvedLibraryByElement(library);
          if (resolved is! ResolvedLibraryResult) {
            throw StateError('Contextual identifier fixture did not resolve.');
          }
          final errors = [
            for (final unit in resolved.units)
              for (final diagnostic in unit.diagnostics)
                if (diagnostic.severity == Severity.error)
                  diagnostic.problemMessage.messageText(includeUrl: false),
          ];
          expect(errors, isEmpty, reason: source);
        },
        resolverFor: 'restage_codegen|lib/contextual_identifier_fixture.dart',
        rootPackage: 'restage_codegen',
        readAllSourcesFromFilesystem: true,
      );

      for (final name in [
        'required',
        'interface',
        'base',
        'when',
        'as',
        'dynamic',
      ]) {
        for (final position in [
          DartIdentifierPosition.namedParameter,
          DartIdentifierPosition.namedArgument,
          DartIdentifierPosition.recordField,
          DartIdentifierPosition.memberSelector,
          DartIdentifierPosition.constructorSelector,
        ]) {
          expect(
            isPublicDartIdentifier(name, position: position),
            isTrue,
            reason: '$name in $position',
          );
        }
      }
      for (final name in ['augment', 'base', 'when']) {
        expect(
          isPublicDartIdentifier(
            name,
            position: DartIdentifierPosition.importPrefix,
          ),
          isTrue,
          reason: '$name as an import prefix',
        );
      }
      for (final name in ['base', 'when']) {
        expect(
          isPublicDartTypeIdentity(
            'package:restage_codegen/contextual_identifier_fixture.dart',
            name,
          ),
          isTrue,
          reason: '$name as a type identity',
        );
      }
      for (final name in ['dynamic', 'Function', 'void']) {
        expect(isPublicDartTypeIdentity('dart:core', name), isTrue);
        expect(
          isPublicDartTypeIdentity('package:fixture/model.dart', name),
          isFalse,
        );
      }
    });

    test('built-in identifiers stay illegal as import prefixes', () async {
      const source = '''
import 'dart:math' as required;

final value = required.pi;
''';
      final parsed = parseString(content: source, throwIfDiagnostics: false);
      expect(parsed.errors, isEmpty, reason: source);

      await resolveSources(
        {'restage_codegen|lib/builtin_prefix_fixture.dart': source},
        (resolver) async {
          final library = await resolver.libraryFor(
            AssetId(
              'restage_codegen',
              'lib/builtin_prefix_fixture.dart',
            ),
          );
          final resolved =
              await library.session.getResolvedLibraryByElement(library);
          if (resolved is! ResolvedLibraryResult) {
            throw StateError('Built-in prefix fixture did not resolve.');
          }
          final errors = [
            for (final unit in resolved.units)
              for (final diagnostic in unit.diagnostics)
                if (diagnostic.severity == Severity.error)
                  diagnostic.problemMessage.messageText(includeUrl: false),
          ];
          expect(
            errors,
            contains(
              "The built-in identifier 'required' can't be used as a prefix "
              'name.',
            ),
            reason: source,
          );
        },
        resolverFor: 'restage_codegen|lib/builtin_prefix_fixture.dart',
        rootPackage: 'restage_codegen',
        readAllSourcesFromFilesystem: true,
      );

      for (final name in [
        'required',
        'interface',
        'as',
        'dynamic',
        'Function',
      ]) {
        expect(
          isPublicDartIdentifier(
            name,
            position: DartIdentifierPosition.importPrefix,
          ),
          isFalse,
          reason: '$name as an import prefix',
        );
      }
    });

    test('hard keywords fail both parser and emitted-position policy', () {
      for (final word in [
        'class',
        'for',
        'return',
        'true',
        'false',
        'null',
        'this',
        'super',
      ]) {
        final fixtures = <DartIdentifierPosition, String>{
          DartIdentifierPosition.namedParameter: 'void f({int $word = 0}) {}',
          DartIdentifierPosition.namedArgument:
              'void f({int value = 0}) {} void g() { f($word: 1); }',
          DartIdentifierPosition.recordField:
              'typedef R = ({int $word}); R r = ($word: 1);',
          DartIdentifierPosition.memberSelector:
              'class C { int $word = 0; } int g(C c) => c.$word;',
          DartIdentifierPosition.constructorSelector:
              'class C { const C.$word(); } C c = const C.$word();',
          DartIdentifierPosition.importPrefix:
              "import 'dart:math' as $word; final x = $word.pi;",
        };
        for (final entry in fixtures.entries) {
          final parsed = parseString(
            content: entry.value,
            throwIfDiagnostics: false,
          );
          expect(
            parsed.errors,
            isNotEmpty,
            reason: '$word unexpectedly parsed in ${entry.key}',
          );
          expect(
            isPublicDartIdentifier(word, position: entry.key),
            isFalse,
            reason: '$word unexpectedly admitted in ${entry.key}',
          );
        }
        expect(
          isPublicDartTypeIdentity('package:fixture/model.dart', word),
          isFalse,
        );
      }
    });

    test('renders every reconstructed const variant with planned prefixes', () {
      const value = DartConstInvocation(
        type: DartTypeIdentity(
          libraryUri: 'package:second/model.dart',
          symbolName: 'Box',
          nullable: true,
          typeArguments: [
            DartTypeIdentity(
              libraryUri: 'package:first/model.dart',
              symbolName: 'Same',
            ),
          ],
        ),
        constructorName: 'named',
        positional: [
          DartConstReference(
            libraryUri: 'package:first/model.dart',
            member: 'seed',
          ),
        ],
        named: [
          DartConstNamedValue(
            'meta',
            DartConstRecord(
              named: [
                DartConstNamedValue(
                  'labels',
                  DartConstList([
                    DartConstScalar("a\n\r\t\b\f\u0001\$b'\\"),
                  ]),
                ),
                DartConstNamedValue(
                  'ids',
                  DartConstSet([DartConstScalar(1), DartConstScalar(2)]),
                ),
                DartConstNamedValue(
                  'scores',
                  DartConstMap([
                    DartConstMapEntry(
                      DartConstScalar('first'),
                      DartConstReference(
                        libraryUri: 'package:first/model.dart',
                        owner: 'Tokens',
                        member: 'score',
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      );
      final planner = DartImportPlanner(
        libraryUris: dartConstValueLibraryUris(value),
        prefixStem: 'i',
      );

      expect(
        renderDartConstValueFromPrefixes(value, planner.prefixesBySourceUri),
        'const i1.Box<i0.Same>.named(i0.seed, meta: '
        r"(ids: const {1, 2}, labels: const ['a\n\r\t\b\f\u0001\$b\'\\'], "
        "scores: const {'first': i0.Tokens.score},))",
      );
      expect(
        renderDartConstValueFromPrefixes(
          const DartConstList([]),
          const {},
        ),
        'const <Never>[]',
      );
      expect(
        renderDartConstValueFromPrefixes(
          const DartConstSet([]),
          const {},
        ),
        'const <Never>{}',
      );
      expect(
        renderDartConstValueFromPrefixes(
          const DartConstMap([]),
          const {},
        ),
        'const <Never, Never>{}',
      );
      expect(
        renderDartConstValueFromPrefixes(const DartConstNull(), const {}),
        'null',
      );
      expect(
        renderDartConstValueFromPrefixes(
          const DartConstRecord(),
          const {},
        ),
        '()',
      );
    });

    test('canonicalizes named members for import planning and rendering', () {
      const alphaUri = 'package:restage_codegen/import_fixture_alpha.dart';
      const pairUri = 'package:restage_codegen/import_fixture_pair.dart';
      const zetaUri = 'package:restage_codegen/import_fixture_zeta.dart';
      const canonicalType = DartRecordTypeIdentity(
        named: [
          DartRecordTypeNamedField(
            'alpha',
            DartTypeIdentity(libraryUri: alphaUri, symbolName: 'Alpha'),
          ),
          DartRecordTypeNamedField(
            'zeta',
            DartTypeIdentity(libraryUri: zetaUri, symbolName: 'Zeta'),
          ),
        ],
      );
      const reorderedType = DartRecordTypeIdentity(
        named: [
          DartRecordTypeNamedField(
            'zeta',
            DartTypeIdentity(libraryUri: zetaUri, symbolName: 'Zeta'),
          ),
          DartRecordTypeNamedField(
            'alpha',
            DartTypeIdentity(libraryUri: alphaUri, symbolName: 'Alpha'),
          ),
        ],
      );
      const canonicalNamed = [
        DartConstNamedValue(
          'alpha',
          DartConstReference(libraryUri: alphaUri, member: 'alpha'),
        ),
        DartConstNamedValue(
          'zeta',
          DartConstReference(libraryUri: zetaUri, member: 'zeta'),
        ),
      ];
      const reorderedNamed = [
        DartConstNamedValue(
          'zeta',
          DartConstReference(libraryUri: zetaUri, member: 'zeta'),
        ),
        DartConstNamedValue(
          'alpha',
          DartConstReference(libraryUri: alphaUri, member: 'alpha'),
        ),
      ];
      const canonicalRecord = DartConstRecord(named: canonicalNamed);
      const reorderedRecord = DartConstRecord(named: reorderedNamed);
      const canonicalInvocation = DartConstInvocation(
        type: DartTypeIdentity(libraryUri: pairUri, symbolName: 'Pair'),
        named: canonicalNamed,
      );
      const reorderedInvocation = DartConstInvocation(
        type: DartTypeIdentity(libraryUri: pairUri, symbolName: 'Pair'),
        named: reorderedNamed,
      );
      final planner = DartImportPlanner(
        libraryUris: {
          ...dartTypeIdentityLibraryUris(reorderedType),
          ...dartConstValueLibraryUris(reorderedInvocation),
        },
        prefixStem: 'i',
      );

      expect(
        dartTypeIdentityLibraryUris(reorderedType).toList(),
        [alphaUri, zetaUri],
      );
      expect(
        dartConstValueLibraryUris(reorderedRecord).toList(),
        [alphaUri, zetaUri],
      );
      expect(
        dartConstValueLibraryUris(reorderedInvocation).toList(),
        [pairUri, alphaUri, zetaUri],
      );
      expect(
        renderDartTypeFromPrefixes(
          canonicalType,
          planner.prefixesBySourceUri,
        ),
        '({i0.Alpha alpha, i2.Zeta zeta})',
      );
      expect(
        renderDartTypeFromPrefixes(
          reorderedType,
          planner.prefixesBySourceUri,
        ),
        '({i0.Alpha alpha, i2.Zeta zeta})',
      );
      expect(
        renderDartConstValueFromPrefixes(
          canonicalRecord,
          planner.prefixesBySourceUri,
        ),
        '(alpha: i0.alpha, zeta: i2.zeta,)',
      );
      expect(
        renderDartConstValueFromPrefixes(
          reorderedRecord,
          planner.prefixesBySourceUri,
        ),
        '(alpha: i0.alpha, zeta: i2.zeta,)',
      );
      expect(
        renderDartConstValueFromPrefixes(
          canonicalInvocation,
          planner.prefixesBySourceUri,
        ),
        'const i1.Pair(alpha: i0.alpha, zeta: i2.zeta)',
      );
      expect(
        renderDartConstValueFromPrefixes(
          reorderedInvocation,
          planner.prefixesBySourceUri,
        ),
        'const i1.Pair(alpha: i0.alpha, zeta: i2.zeta)',
      );
    });

    test('analyzer sees reordered named constants as canonical duplicates',
        () async {
      const modelUri =
          'package:restage_codegen/import_fixture_named_model.dart';
      const pairType = DartTypeIdentity(
        libraryUri: modelUri,
        symbolName: 'Pair',
      );
      const recordType = DartRecordTypeIdentity(
        named: [
          DartRecordTypeNamedField(
            'a',
            DartTypeIdentity(libraryUri: 'dart:core', symbolName: 'int'),
          ),
          DartRecordTypeNamedField(
            'b',
            DartTypeIdentity(libraryUri: 'dart:core', symbolName: 'int'),
          ),
        ],
      );
      const canonicalNamed = [
        DartConstNamedValue('a', DartConstScalar(1)),
        DartConstNamedValue('b', DartConstScalar(2)),
      ];
      const reorderedNamed = [
        DartConstNamedValue('b', DartConstScalar(2)),
        DartConstNamedValue('a', DartConstScalar(1)),
      ];
      const canonicalRecord = DartConstRecord(named: canonicalNamed);
      const reorderedRecord = DartConstRecord(named: reorderedNamed);
      const canonicalInvocation = DartConstInvocation(
        type: pairType,
        named: canonicalNamed,
      );
      const reorderedInvocation = DartConstInvocation(
        type: pairType,
        named: reorderedNamed,
      );
      const value = DartConstRecord(
        positional: [
          DartConstSet(
            [canonicalRecord, reorderedRecord],
            type: DartTypeIdentity(
              libraryUri: 'dart:core',
              symbolName: 'Set',
              typeArguments: [recordType],
            ),
          ),
          DartConstMap(
            [
              DartConstMapEntry(canonicalRecord, DartConstScalar(1)),
              DartConstMapEntry(reorderedRecord, DartConstScalar(2)),
            ],
            type: DartTypeIdentity(
              libraryUri: 'dart:core',
              symbolName: 'Map',
              typeArguments: [
                recordType,
                DartTypeIdentity(
                  libraryUri: 'dart:core',
                  symbolName: 'int',
                ),
              ],
            ),
          ),
          DartConstSet(
            [canonicalInvocation, reorderedInvocation],
            type: DartTypeIdentity(
              libraryUri: 'dart:core',
              symbolName: 'Set',
              typeArguments: [pairType],
            ),
          ),
          DartConstMap(
            [
              DartConstMapEntry(canonicalInvocation, DartConstScalar(1)),
              DartConstMapEntry(reorderedInvocation, DartConstScalar(2)),
            ],
            type: DartTypeIdentity(
              libraryUri: 'dart:core',
              symbolName: 'Map',
              typeArguments: [
                pairType,
                DartTypeIdentity(
                  libraryUri: 'dart:core',
                  symbolName: 'int',
                ),
              ],
            ),
          ),
        ],
      );
      final planner = DartImportPlanner(
        libraryUris: dartConstValueLibraryUris(value),
        prefixStem: 'i',
      );
      final rendered = renderDartConstValueFromPrefixes(
        value,
        planner.prefixesBySourceUri,
      );
      final generated = '''
${planner.importDirectives.join('\n')}

final duplicates = $rendered;
''';

      expect(
        rendered,
        contains('(a: 1, b: 2,), (a: 1, b: 2,)'),
      );
      expect(
        rendered,
        contains('const i0.Pair(a: 1, b: 2)'),
      );
      await resolveSources(
        {
          'restage_codegen|lib/import_fixture_named_model.dart': '''
class Pair {
  const Pair({required this.a, required this.b});

  final int a;
  final int b;
}
''',
          'restage_codegen|lib/import_fixture_named_duplicates.dart': generated,
        },
        (resolver) async {
          final library = await resolver.libraryFor(
            AssetId(
              'restage_codegen',
              'lib/import_fixture_named_duplicates.dart',
            ),
          );
          final resolved =
              await library.session.getResolvedLibraryByElement(library);
          if (resolved is! ResolvedLibraryResult) {
            throw StateError('Named duplicate fixture did not resolve.');
          }
          final duplicateCodes = [
            for (final unit in resolved.units)
              for (final diagnostic in unit.diagnostics)
                if (diagnostic.severity == Severity.error)
                  diagnostic.diagnosticCode.lowerCaseName,
          ];
          expect(
            duplicateCodes.where(
              (code) => code == 'equal_elements_in_const_set',
            ),
            hasLength(2),
            reason: generated,
          );
          expect(
            duplicateCodes.where(
              (code) => code == 'equal_keys_in_const_map',
            ),
            hasLength(2),
            reason: generated,
          );
        },
        resolverFor: 'restage_codegen|lib/import_fixture_named_duplicates.dart',
        rootPackage: 'restage_codegen',
        readAllSourcesFromFilesystem: true,
      );
    });

    test('analyzer rejects the const shapes blocked by schema validation',
        () async {
      const invalidSet = DartConstSet([
        DartConstRecord(positional: [DartConstScalar(1.0)]),
      ]);
      const invalidMap = DartConstMap([
        DartConstMapEntry(DartConstScalar(-0.0), DartConstScalar('value')),
      ]);
      const invalidArity = DartConstList(
        <DartConstValue>[],
        type: DartTypeIdentity(
          libraryUri: 'dart:core',
          symbolName: 'List',
          typeArguments: [
            DartTypeIdentity(
              libraryUri: 'dart:core',
              symbolName: 'int',
              typeArguments: [
                DartTypeIdentity(
                  libraryUri: 'dart:core',
                  symbolName: 'String',
                ),
              ],
            ),
          ],
        ),
      );
      final generated = '''
final invalidSet = ${renderDartConstValueFromPrefixes(invalidSet, const {})};
final invalidMap = ${renderDartConstValueFromPrefixes(invalidMap, const {})};
final invalidArity = ${renderDartConstValueFromPrefixes(invalidArity, const {})};
''';

      await resolveSources(
        {'restage_codegen|lib/import_fixture_invalid_const.dart': generated},
        (resolver) async {
          final library = await resolver.libraryFor(
            AssetId(
              'restage_codegen',
              'lib/import_fixture_invalid_const.dart',
            ),
          );
          final resolved =
              await library.session.getResolvedLibraryByElement(library);
          if (resolved is! ResolvedLibraryResult) {
            throw StateError('Invalid const fixture did not resolve.');
          }
          final errorCodes = {
            for (final unit in resolved.units)
              for (final diagnostic in unit.diagnostics)
                if (diagnostic.severity == Severity.error)
                  diagnostic.diagnosticCode.lowerCaseName,
          };
          expect(
            errorCodes,
            containsAll(<String>{
              'const_set_element_not_primitive_equality',
              'const_map_key_not_primitive_equality',
              'wrong_number_of_type_arguments',
            }),
            reason: generated,
          );
        },
        resolverFor: 'restage_codegen|lib/import_fixture_invalid_const.dart',
        rootPackage: 'restage_codegen',
        readAllSourcesFromFilesystem: true,
      );
    });

    test('typed collections plan and render cross-library type arguments',
        () async {
      const modelUri =
          'package:restage_codegen/import_fixture_collection_model.dart';
      const sameType = DartTypeIdentity(
        libraryUri: modelUri,
        symbolName: 'Same',
      );
      const value = DartConstRecord(
        positional: [
          DartConstList(
            [],
            type: DartTypeIdentity(
              libraryUri: 'dart:core',
              symbolName: 'List',
              typeArguments: [
                DartRecordTypeIdentity(
                  named: [
                    DartRecordTypeNamedField(
                      'item',
                      DartTypeIdentity(
                        libraryUri: modelUri,
                        symbolName: 'Same',
                        nullable: true,
                      ),
                    ),
                    DartRecordTypeNamedField(
                      'values',
                      DartTypeIdentity(
                        libraryUri: 'dart:core',
                        symbolName: 'List',
                        typeArguments: [
                          DartTypeIdentity(
                            libraryUri: 'dart:core',
                            symbolName: 'int',
                            nullable: true,
                          ),
                        ],
                        nullable: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          DartConstSet(
            [],
            type: DartTypeIdentity(
              libraryUri: 'dart:core',
              symbolName: 'Set',
              typeArguments: [
                DartRecordTypeIdentity(
                  positional: [
                    DartTypeIdentity(
                      libraryUri: modelUri,
                      symbolName: 'Same',
                      nullable: true,
                    ),
                    DartTypeIdentity(
                      libraryUri: 'dart:core',
                      symbolName: 'String',
                    ),
                  ],
                  nullable: true,
                ),
              ],
            ),
          ),
          DartConstMap(
            [],
            type: DartTypeIdentity(
              libraryUri: 'dart:core',
              symbolName: 'Map',
              typeArguments: [
                DartTypeIdentity(
                  libraryUri: 'dart:core',
                  symbolName: 'String',
                ),
                DartRecordTypeIdentity(
                  positional: [sameType],
                  named: [
                    DartRecordTypeNamedField(
                      'count',
                      DartTypeIdentity(
                        libraryUri: 'dart:core',
                        symbolName: 'int',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
      final planner = DartImportPlanner(
        libraryUris: dartConstValueLibraryUris(value),
        prefixStem: 'i',
      );
      final rendered = renderDartConstValueFromPrefixes(
        value,
        planner.prefixesBySourceUri,
      );

      expect(
        rendered,
        '(const <({i0.Same? item, List<int?>? values})>[], '
        'const <(i0.Same?, String)?>{}, '
        'const <String, (i0.Same, {int count})>{},)',
      );
      expect(
        planner.importDirectives,
        ["import '$modelUri' as i0;"],
      );

      final generated = '''
${planner.importDirectives.join('\n')}

final (
  List<({i0.Same? item, List<int?>? values})>,
  Set<(i0.Same?, String)?>,
  Map<String, (i0.Same, {int count})>
) value = $rendered;
''';
      await resolveSources(
        {
          'restage_codegen|lib/import_fixture_collection_model.dart': '''
class Same {
  const Same();
}
''',
          'restage_codegen|lib/import_fixture_typed_collections.dart':
              generated,
        },
        (resolver) async {
          final library = await resolver.libraryFor(
            AssetId(
              'restage_codegen',
              'lib/import_fixture_typed_collections.dart',
            ),
          );
          final resolved =
              await library.session.getResolvedLibraryByElement(library);
          if (resolved is! ResolvedLibraryResult) {
            throw StateError('Typed collection fixture did not resolve.');
          }
          final errors = [
            for (final unit in resolved.units)
              for (final diagnostic in unit.diagnostics)
                if (diagnostic.severity == Severity.error)
                  diagnostic.problemMessage.messageText(includeUrl: false),
          ];
          expect(errors, isEmpty, reason: generated);
        },
        resolverFor:
            'restage_codegen|lib/import_fixture_typed_collections.dart',
        rootPackage: 'restage_codegen',
        readAllSourcesFromFilesystem: true,
      );
    });

    test('rendered nested constructor defaults analyze clean', () async {
      const firstUri = 'package:restage_codegen/import_fixture_first.dart';
      const secondUri = 'package:restage_codegen/import_fixture_second.dart';
      const value = DartConstInvocation(
        type: DartTypeIdentity(
          libraryUri: secondUri,
          symbolName: 'Box',
          typeArguments: [
            DartTypeIdentity(
              libraryUri: firstUri,
              symbolName: 'Same',
              nullable: true,
            ),
          ],
        ),
        constructorName: 'named',
        positional: [
          DartConstReference(libraryUri: firstUri, member: 'absent'),
        ],
        named: [
          DartConstNamedValue(
            'meta',
            DartConstRecord(
              named: [
                DartConstNamedValue(
                  'labels',
                  DartConstList(
                    [
                      DartConstReference(
                        libraryUri: firstUri,
                        member: 'absentLabel',
                      ),
                    ],
                    type: DartTypeIdentity(
                      libraryUri: 'dart:core',
                      symbolName: 'List',
                      typeArguments: [
                        DartTypeIdentity(
                          libraryUri: 'dart:core',
                          symbolName: 'String',
                          nullable: true,
                        ),
                      ],
                    ),
                  ),
                ),
                DartConstNamedValue(
                  'ids',
                  DartConstSet([DartConstScalar(1)]),
                ),
                DartConstNamedValue(
                  'scores',
                  DartConstMap([
                    DartConstMapEntry(
                      DartConstScalar('first'),
                      DartConstReference(
                        libraryUri: firstUri,
                        owner: 'Tokens',
                        member: 'score',
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      );
      final planner = DartImportPlanner(
        libraryUris: dartConstValueLibraryUris(value),
        prefixStem: 'i',
      );
      final rendered = renderDartConstValueFromPrefixes(
        value,
        planner.prefixesBySourceUri,
      );
      final generated = '''
${planner.importDirectives.join('\n')}

final i1.Box<i0.Same?> value = $rendered;
final emptyRecord = ${renderDartConstValueFromPrefixes(const DartConstRecord(), const {})};
final escapedControls = ${renderDartConstValueFromPrefixes(const DartConstScalar("a\n\r\t\b\f\u0001\$b'\\"), const {})};
''';

      expect(
        rendered,
        contains('const i1.Box<i0.Same?>.named(i0.absent,'),
      );
      expect(
        rendered,
        contains('labels: const <String?>[i0.absentLabel]'),
      );

      await resolveSources(
        {
          'restage_codegen|lib/import_fixture_first.dart': '''
class Same {
  const Same();
}

const Same? absent = null;
const String? absentLabel = null;

class Tokens {
  static const score = 7;
}
''',
          'restage_codegen|lib/import_fixture_second.dart': '''
class Box<T> {
  const Box.named(this.value, {required this.meta});

  final T value;
  final ({Set<int> ids, List<String?> labels, Map<String, int> scores}) meta;
}
''',
          'restage_codegen|lib/import_fixture_generated.dart': generated,
        },
        (resolver) async {
          final library = await resolver.libraryFor(
            AssetId(
              'restage_codegen',
              'lib/import_fixture_generated.dart',
            ),
          );
          final resolved =
              await library.session.getResolvedLibraryByElement(library);
          if (resolved is! ResolvedLibraryResult) {
            throw StateError('Rendered const fixture did not resolve.');
          }
          final errors = [
            for (final unit in resolved.units)
              for (final diagnostic in unit.diagnostics)
                if (diagnostic.severity == Severity.error)
                  diagnostic.problemMessage.messageText(includeUrl: false),
          ];
          expect(errors, isEmpty, reason: generated);
        },
        resolverFor: 'restage_codegen|lib/import_fixture_generated.dart',
        rootPackage: 'restage_codegen',
        readAllSourcesFromFilesystem: true,
      );
    });

    test('fails loud on private type, member, owner, and constructor names',
        () {
      final planner = DartImportPlanner(
        libraryUris: const {'package:fixture/private.dart'},
      );

      expect(
        () => planner.renderType(
          const DartTypeIdentity(
            libraryUri: 'package:fixture/private.dart',
            symbolName: '_Private',
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('private Dart identity'),
          ),
        ),
      );
      expect(
        () => planner.qualifyReference(
          libraryUri: 'package:fixture/private.dart',
          owner: '_Owner',
          member: 'value',
        ),
        throwsStateError,
      );
      expect(
        () => planner.qualifyReference(
          libraryUri: 'package:fixture/private.dart',
          member: '_value',
        ),
        throwsStateError,
      );
      expect(
        () => planner.qualifyConstructor(
          const DartTypeIdentity(
            libraryUri: 'package:fixture/private.dart',
            symbolName: 'Public',
          ),
          constructorName: '_named',
        ),
        throwsStateError,
      );
    });

    test('accepts the language-defined unnamed constructor selector', () {
      final planner = DartImportPlanner(
        libraryUris: const {'package:fixture/public.dart'},
      );
      const type = DartTypeIdentity(
        libraryUri: 'package:fixture/public.dart',
        symbolName: 'Public',
      );

      expect(
        planner.qualifyConstructor(type, constructorName: 'new'),
        'restage_import_0.Public.new',
      );
      expect(
        () => planner.qualifyConstructor(type, constructorName: 'class'),
        throwsStateError,
      );
    });

    test('fails loud when fixed and generated prefixes collide', () {
      expect(
        () => DartImportPlanner(
          libraryUris: const {
            'package:a/a.dart',
            'package:b/b.dart',
          },
          prefixStem: 'i',
          fixedPrefixes: const {'package:b/b.dart': 'i0'},
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('collide on prefix i0'),
          ),
        ),
      );
    });

    test('retains a valid file fixture URI exactly', () {
      final planner = DartImportPlanner(
        libraryUris: const {'file:///tmp/restage_fixture.dart'},
      );

      expect(
        planner.importDirectives,
        ["import 'file:///tmp/restage_fixture.dart' as restage_import_0;"],
      );
    });

    test(
      'planned same-name, prefixed const, and constructor source analyzes '
      'clean',
      () async {
        const firstUri = 'package:restage_codegen/import_fixture_first.dart';
        const secondUri = 'package:restage_codegen/import_fixture_second.dart';
        const firstType = DartTypeIdentity(
          libraryUri: firstUri,
          symbolName: 'Same',
        );
        const boxType = DartTypeIdentity(
          libraryUri: secondUri,
          symbolName: 'Box',
          typeArguments: [firstType],
        );
        final planner = DartImportPlanner(
          libraryUris: {
            ...dartTypeIdentityLibraryUris(firstType),
            ...dartTypeIdentityLibraryUris(boxType),
          },
          prefixStem: 'i',
        );
        final first = planner.renderType(firstType);
        final box = planner.renderType(boxType);
        final seed = planner.qualifyReference(
          libraryUri: firstUri,
          member: 'seed',
        );
        final constructor = planner.qualifyConstructor(boxType);
        final generated = '''
${planner.importDirectives.join('\n')}

final $first first = $seed;
final $box nested = const $constructor($seed);
''';

        await resolveSources(
          {
            'restage_codegen|lib/import_fixture_first.dart': '''
class Same {
  const Same();
}

const seed = Same();
''',
            'restage_codegen|lib/import_fixture_second.dart': '''
class Same {
  const Same();
}

class Box<T> {
  const Box(this.value);
  final T value;
}
''',
            'restage_codegen|lib/import_fixture_generated.dart': generated,
          },
          (resolver) async {
            final library = await resolver.libraryFor(
              AssetId(
                'restage_codegen',
                'lib/import_fixture_generated.dart',
              ),
            );
            final resolved =
                await library.session.getResolvedLibraryByElement(library);
            if (resolved is! ResolvedLibraryResult) {
              throw StateError(
                'Generated import-planner fixture did not resolve.',
              );
            }
            final errors = [
              for (final unit in resolved.units)
                for (final diagnostic in unit.diagnostics)
                  if (diagnostic.severity == Severity.error)
                    diagnostic.problemMessage.messageText(includeUrl: false),
            ];
            expect(errors, isEmpty, reason: generated);
          },
          resolverFor: 'restage_codegen|lib/import_fixture_generated.dart',
          rootPackage: 'restage_codegen',
          readAllSourcesFromFilesystem: true,
        );
      },
    );

    test(
      'non-colliding Widgetbook model remains prefixed, bare, and analyzable',
      () async {
        const modelUri =
            'package:restage_codegen/import_fixture_widgetbook_model.dart';
        final planner = DartImportPlanner(
          libraryUris: const {modelUri},
          prefixStem: 'model',
          bareSymbolImports: const [
            DartBareSymbolImport(
              libraryUri: modelUri,
              symbol: 'CardData',
              sourcePath: 'lib/card.dart#Card.data',
            ),
          ],
          bareSymbolReservations: const [
            DartBareSymbolReservation(
              libraryUri: 'package:widgetbook/src/core/framework/meta.dart',
              symbol: 'Meta',
              source: 'package:widgetbook/widgetbook.dart export',
            ),
            DartBareSymbolReservation(
              libraryUri: 'dart:core',
              symbol: 'String',
              source: 'implicit dart:core namespace',
            ),
            DartBareSymbolReservation(
              symbol: 'widgetbook',
              source: 'Widgetbook import prefix',
            ),
          ],
        );
        final generated = '''
${planner.importDirectives.join('\n')}

final model0.CardData prefixed = const model0.CardData('prefixed');
final CardData reproducedByPart = const CardData('bare');
''';

        expect(
          planner.importDirectives,
          equals([
            "import '$modelUri' as model0;",
            "import '$modelUri' show CardData;",
          ]),
        );
        await resolveSources(
          {
            'restage_codegen|lib/import_fixture_widgetbook_model.dart': '''
class CardData {
  const CardData(this.label);
  final String label;
}
''',
            'restage_codegen|lib/import_fixture_widgetbook_generated.dart':
                generated,
          },
          (resolver) async {
            final library = await resolver.libraryFor(
              AssetId(
                'restage_codegen',
                'lib/import_fixture_widgetbook_generated.dart',
              ),
            );
            final resolved =
                await library.session.getResolvedLibraryByElement(library);
            if (resolved is! ResolvedLibraryResult) {
              throw StateError(
                'Generated Widgetbook namespace fixture did not resolve.',
              );
            }
            final errors = [
              for (final unit in resolved.units)
                for (final diagnostic in unit.diagnostics)
                  if (diagnostic.severity == Severity.error)
                    diagnostic.problemMessage.messageText(includeUrl: false),
            ];
            expect(errors, isEmpty, reason: generated);
          },
          resolverFor:
              'restage_codegen|lib/import_fixture_widgetbook_generated.dart',
          rootPackage: 'restage_codegen',
          readAllSourcesFromFilesystem: true,
        );
      },
    );

    test(
      'planned Dart UI, Material, and Cupertino source analyzes clean',
      () async {
        const uiUri = 'dart:ui';
        const materialUri = 'package:flutter/src/material/colors.dart';
        const cupertinoUri = 'package:flutter/src/cupertino/colors.dart';
        final planner = DartImportPlanner(
          libraryUris: const {uiUri, materialUri, cupertinoUri},
          prefixStem: 'i',
        );
        final colorType = planner.qualify(uiUri, 'Color');
        final colorCtor = planner.qualifyConstructor(
          const DartTypeIdentity(libraryUri: uiUri, symbolName: 'Color'),
        );
        final materialRed = planner.qualifyReference(
          libraryUri: materialUri,
          owner: 'Colors',
          member: 'red',
        );
        final cupertinoBlue = planner.qualifyReference(
          libraryUri: cupertinoUri,
          owner: 'CupertinoColors',
          member: 'activeBlue',
        );
        final generated = '''
${planner.importDirectives.join('\n')}

const $colorType direct = $colorCtor(0xFF000000);
final $colorType material = $materialRed;
final Object cupertino = $cupertinoBlue;
''';

        await resolveSources(
          {'apps_examples|lib/import_planner_flutter.dart': generated},
          (resolver) async {
            final library = await resolver.libraryFor(
              AssetId('apps_examples', 'lib/import_planner_flutter.dart'),
            );
            final resolved =
                await library.session.getResolvedLibraryByElement(library);
            if (resolved is! ResolvedLibraryResult) {
              throw StateError(
                'Generated Flutter import fixture did not resolve.',
              );
            }
            final errors = [
              for (final unit in resolved.units)
                for (final diagnostic in unit.diagnostics)
                  if (diagnostic.severity == Severity.error)
                    diagnostic.problemMessage.messageText(includeUrl: false),
            ];
            expect(errors, isEmpty, reason: generated);
          },
          resolverFor: 'apps_examples|lib/import_planner_flutter.dart',
          rootPackage: 'apps_examples',
          readAllSourcesFromFilesystem: true,
        );
      },
    );
  });
}
