import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/restage_widget_walker.dart';
import 'package:restage_codegen/src/user_catalog_builder.dart';
import 'package:restage_codegen/src/user_factory_builder.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The STRUCTURED RENDER LEG: a customer `@RestageWidget` whose
/// structured (data-class) property is RENDERABLE is ADMITTED to the RFW
/// catalog AND the factory emits an inline reconstructor for it (admit + decode
/// land together — no factory skip, no throw). A still-unsupported structured
/// shape stays excluded-loud (a predicate gap), never admitted-but-unrendered.
void main() {
  const source = '''
    import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
    @RestageLibrary(
      library: WidgetLibrary.custom('acme.design_system'),
      capabilityVersion: 1,
    )
    const restageLibrary = 0;

    class Badge {
      const Badge({required this.label});
      final String label;
    }

    @RestageWidget(
      name: 'PlainButton',
      library: WidgetLibrary.custom('acme.design_system'),
      category: WidgetCategory.input,
      description: 'CTA.',
    )
    class PlainButton {
      const PlainButton();
    }

    @RestageWidget(
      name: 'BadgeCard',
      library: WidgetLibrary.custom('acme.design_system'),
      category: WidgetCategory.decoration,
      description: 'A card that renders a badge.',
    )
    class BadgeCard {
      const BadgeCard({required this.badge});
      @RestageProperty(description: 'The badge to render.')
      final Badge badge;
    }
  ''';

  group('customer-structured RFW render leg', () {
    test(
        'UserCatalogBuilder ADMITS the renderable structured widget + the '
        'scalar one, allocates the structured type, and does not throw',
        () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        source,
      );

      await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_catalog.g.dart': decodedMatches(
            allOf(
              contains("name: 'PlainButton'"),
              contains("name: 'BadgeCard'"),
              isNot(contains('WireId.unallocated')),
            ),
          ),
        },
      );
    });

    test(
        'UserFactoryBuilder RECONSTRUCTS the structured widget inline (emits a '
        'Badge reconstruction, imports its type) and does not throw', () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        source,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf(
              contains('PlainButton'),
              // The inline reconstruction of the customer data class — the
              // ctor call, sourced by name from the wire map (a NAMED param).
              contains('Badge('),
              contains('label:'),
              // The import closure names the referenced type so it compiles.
              contains('widgets.dart'),
            ),
          ),
        },
      );
    });

    // Arg-KIND correctness: the reconstruction must emit each arg in its ctor
    // param's kind — Dart positional params CANNOT be passed by name, so a
    // named-arg emission on a positional ctor is a generated-factory COMPILE
    // ERROR (governing-invariant (c)). The positional-hole fix admits
    // all-positional-all-field classes, so they DO reach the reconstructor.
    test(
        'an ALL-POSITIONAL data class reconstructs with POSITIONAL args (in '
        'ctor order), not named args', () async {
      const positionalSource = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        class Badge {
          const Badge(this.label, this.count);
          final String label;
          final int count;
        }
        @RestageWidget(name: 'BadgeCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class BadgeCard {
          const BadgeCard({required this.badge});
          @RestageProperty(description: 'b') final Badge badge;
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        positionalSource,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': positionalSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf(
              contains('Badge('),
              // Positional: NO `label:`/`count:` named args on the Badge ctor.
              isNot(contains('label:')),
              isNot(contains('count:')),
            ),
          ),
        },
      );
    });

    test(
        'a MIXED (positional + named) data class reconstructs '
        'positional-then-named in the correct kind', () async {
      const mixedSource = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        class Badge {
          const Badge(this.a, {required this.b});
          final String a;
          final int b;
        }
        @RestageWidget(name: 'BadgeCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class BadgeCard {
          const BadgeCard({required this.badge});
          @RestageProperty(description: 'x') final Badge badge;
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        mixedSource,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': mixedSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf(
              contains('Badge('),
              // `a` is positional (no `a:`); `b` is named (`b:` present).
              isNot(contains('a:')),
              contains('b:'),
            ),
          ),
        },
      );
    });

    test(
        'a NESTED structured field reconstructs RECURSIVELY (Outer -> Inner) '
        'with the extended wire path', () async {
      const nestedSource = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        class Inner { const Inner({required this.value}); final int value; }
        class Outer {
          const Outer({required this.title, required this.inner});
          final String title;
          final Inner inner;
        }
        @RestageWidget(name: 'OuterCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class OuterCard {
          const OuterCard({required this.config});
          @RestageProperty(description: 'x') final Outer config;
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        nestedSource,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': nestedSource},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf(
              contains('Outer('),
              contains('Inner('),
              // The nested field reads at the extended path
              // config -> inner -> value.
              contains("'config', 'inner', 'value'"),
            ),
          ),
        },
      );
    });

    test(
        'a REQUIRED NESTED structured field FAIL-CLOSES on a missing nested '
        'map (presence-checked; never fabricates an empty nested object)',
        () async {
      // Inner has only an OPTIONAL field, so a scalar-leaf fail-close would not
      // fire. The REQUIRED `inner` must presence-check its map and throw when
      // absent, not fabricate Inner(label: null).
      const nestedReq = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        class Inner { const Inner({this.label}); final String? label; }
        class Outer { const Outer({required this.inner}); final Inner inner; }
        @RestageWidget(name: 'OuterCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class OuterCard {
          const OuterCard({required this.config});
          @RestageProperty(description: 'x') final Outer config;
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        nestedReq,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': nestedReq},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf(
              contains('Inner('),
              // The required nested field presence-checks its map + throws.
              contains('isMap'),
              contains('throw ArgumentError'),
              contains('is required'),
            ),
          ),
        },
      );
    });

    // H2 — an OPTIONAL NON-NULLABLE param decodes a nullable value into a
    // non-null slot, a COMPILE ERROR unless the ctor default is supplied on the
    // absent branch. The reconstruction must emit `<decode> ?? <default>` from
    // the analyzer's const default (type-correct + faithful: present -> value,
    // absent -> the ctor default).
    test(
        'an OPTIONAL NON-NULLABLE field with a literal default reconstructs '
        'with `?? <default>` (type-correct + faithful)', () async {
      const optionalDefault = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        class Badge { const Badge({this.label = 'new'}); final String label; }
        @RestageWidget(name: 'BadgeCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class BadgeCard {
          const BadgeCard({required this.badge});
          @RestageProperty(description: 'x') final Badge badge;
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        optionalDefault,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': optionalDefault},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf(
              contains('Badge('),
              // The nullable decode coalesces to the reproduced ctor default.
              contains("?? 'new'"),
            ),
          ),
        },
      );
    });

    // H2 — an OPTIONAL NULLABLE param needs no fallback: `source.v<T>` already
    // returns `T?`, which assigns to the nullable slot. Emit the bare decode
    // (no spurious `??`).
    test('an OPTIONAL NULLABLE field reconstructs with a BARE decode (no `??`)',
        () async {
      const optionalNullable = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        class Badge { const Badge({this.label}); final String? label; }
        @RestageWidget(name: 'BadgeCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class BadgeCard {
          const BadgeCard({required this.badge});
          @RestageProperty(description: 'x') final Badge badge;
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        optionalNullable,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': optionalNullable},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf(
              contains('label: source.v<String>'),
              // No `??`: the nullable decode assigns to a nullable slot.
              isNot(contains('??')),
            ),
          ),
        },
      );
    });

    // H2 (nested analog) — an OPTIONAL NULLABLE NESTED field must
    // presence-check its map and yield `null` when absent, never fabricate an
    // empty nested object from missing wire values.
    test(
        'an OPTIONAL NULLABLE NESTED field reconstructs `isMap ? recon : null` '
        '(never fabricates from an absent map)', () async {
      const optionalNested = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        class Inner { const Inner({this.value}); final int? value; }
        class Outer { const Outer({this.inner}); final Inner? inner; }
        @RestageWidget(name: 'OuterCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class OuterCard {
          const OuterCard({required this.config});
          @RestageProperty(description: 'x') final Outer config;
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        optionalNested,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': optionalNested},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf(
              contains('Inner('),
              // The optional nullable nested field is presence-checked; an
              // absent map yields null, not a fabricated Inner.
              contains('isMap'),
              contains(': null'),
            ),
          ),
        },
      );
    });

    test(
        'a REQUIRED field reconstructs FAIL-CLOSED (throws on a missing wire '
        'value, never fabricates)', () async {
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        source,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf(
              contains('Badge('),
              // The required `label` fail-closes on a missing wire value.
              contains('throw ArgumentError'),
              contains('is required'),
            ),
          ),
        },
      );
    });

    // H2 (enum-default recovery, once the H5 alias exists) — an OPTIONAL
    // NON-NULLABLE field whose default is a CUSTOMER-enum constant reconstructs
    // `?? s0.Tone.<value>` (the enum qualified through its alias), rather than
    // excluding-loud. Recovers the common data-class enum-default pattern.
    test(
        'an OPTIONAL NON-NULLABLE enum field with an enum-constant default '
        'reconstructs `?? <alias>.Enum.value` (qualified)', () async {
      const enumDefault = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        enum Tone { soft, loud }
        class Badge { const Badge({this.tone = Tone.loud}); final Tone tone; }
        @RestageWidget(name: 'BadgeCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class BadgeCard {
          const BadgeCard({required this.badge});
          @RestageProperty(description: 'x') final Badge badge;
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        enumDefault,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': enumDefault},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf(
              // The nullable enum decode coalesces to the qualified default.
              matches(RegExp(r'\?\?\s*s\d+\.Tone\.loud')),
            ),
          ),
        },
      );
    });

    // Level-0 fail-closed (the H1 invariant at the WIDGET structured PROPERTY,
    // one level up from the nested field): a REQUIRED widget structured prop
    // whose target's fields are all optional would fabricate an empty value
    // from an absent wire map (the leaf fail-closes never fire). Presence-check
    // the prop's map + throw when absent, exactly like the nested-field fix.
    test(
        'a REQUIRED widget structured property presence-checks its map and '
        'FAIL-CLOSES (throws) when absent, never fabricates', () async {
      const allOptional = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        class Badge { const Badge({this.label}); final String? label; }
        @RestageWidget(name: 'BadgeCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class BadgeCard {
          const BadgeCard({required this.badge});
          @RestageProperty(description: 'x') final Badge badge;
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        allOptional,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': allOptional},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf(
              contains('Badge('),
              // The required widget structured prop presence-checks + throws.
              contains('isMap'),
              contains('BadgeCard.badge is required'),
            ),
          ),
        },
      );
    });

    // Pass-3 #F2 — an OPTIONAL-NULLABLE widget structured prop must yield null
    // on an absent map (`isMap ? recon : null`), not reconstruct
    // unconditionally (which throws on an absent nested-required leaf — a valid
    // absent-nullable input). Nullability is a build-time signal (not a wire
    // field). An optional-NON-NULL-with-default prop stays unconditional (the
    // accepted absent-with-default boundary); a REQUIRED prop throws.
    test(
        'an OPTIONAL-NULLABLE widget structured prop yields null on an absent '
        'map (never crashes)', () async {
      const nullableProp = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        class Badge { const Badge({required this.label}); final String label; }
        @RestageWidget(name: 'BadgeCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class BadgeCard {
          const BadgeCard({this.badge});
          @RestageProperty(description: 'x') final Badge? badge;
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        nullableProp,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': nullableProp},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf(
              contains('Badge('),
              // Presence-checked; an absent map yields null (no crash).
              contains('isMap'),
              contains(': null'),
              // The widget prop is optional-nullable, so it does NOT throw
              // "BadgeCard.badge is required".
              isNot(contains('BadgeCard.badge is required')),
            ),
          ),
        },
      );
    });

    // Constructor-first admission cannot reinterpret an initializer-transformed
    // positional parameter as a catalog property. It fails at the exact input,
    // while a canonical positional sibling still projects normally.
    test(
        'an initializer-transformed positional input fails loud; a clean '
        'positional widget still projects', () async {
      const holeAndClean = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        @RestageWidget(name: 'HoleCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class HoleCard {
          const HoleCard(this.title, [Object? ignored, this.count = 0]);
          @RestageProperty(description: 'c', required: true) final int count;
          @RestageProperty(description: 't', required: true) final String title;
        }
        @RestageWidget(name: 'CleanCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class CleanCard {
          const CleanCard(this.title, this.count);
          @RestageProperty(description: 'c', required: true) final int count;
          @RestageProperty(description: 't', required: true) final String title;
        }
      ''';
      final result = await runWidgetVisitorOn(
        {'lib/widgets.dart': holeAndClean},
      );
      expect(
        result.widgets.map((widget) => widget.name),
        contains('CleanCard'),
      );
      final issue = result.issues.singleWhere(
        (candidate) =>
            candidate.code == IssueCode.invalidWidgetConstructorInput &&
            candidate.location == 'lib/widgets.dart#HoleCard.ignored',
      );
      expect(issue.message, contains('initializer-transformed'));
    });

    // Pass-3 #F1 — POSITIONAL args must emit in CONSTRUCTOR order, not field-
    // declaration order. Here the fields are declared `badge` then `title` but
    // the ctor is `(title, badge)`; emitting in field order would transpose the
    // args (`PairCard(Badge(...), <String>)`) — a compile error / wrong render.
    test(
        'POSITIONAL args emit in ctor order even when field-declaration order '
        'differs', () async {
      const reordered = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        class Badge { const Badge({required this.count}); final int count; }
        @RestageWidget(name: 'PairCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class PairCard {
          const PairCard(this.title, this.badge);
          @RestageProperty(description: 'b') final Badge badge;
          @RestageProperty(description: 't') final String title;
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        reordered,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': reordered},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            // Ctor order: `title` (String) BEFORE `badge` (the reconstruction).
            stringContainsInOrder(['source.v<String>', 'Badge(']),
          ),
        },
      );
    });

    // THE PERMANENT ADMIT-THEN-SKIP COHERENCE ANCHOR. Customer source can no
    // longer author the malformed canonical child slot that remains a real
    // historical-catalog factory rejection. Exercise that rejection through
    // the walker's production predicate (including
    // `customerChildProperties: true`), then prove admission excludes it.
    test(
        'walker production factory rejection excludes a structured widget '
        'before catalog emission', () async {
      final visited = await runWidgetVisitorOn({
        'lib/widgets.dart': source,
      });
      final original = visited.widgets.singleWhere(
        (widget) => widget.name == 'BadgeCard',
      );
      final malformedHistorical = WidgetEntry(
        wireId: original.wireId,
        name: original.name,
        library: original.library,
        category: original.category,
        description: original.description,
        flutterType: original.flutterType,
        childrenSlot: ChildrenSlot.single,
        properties: original.properties,
      );
      final context = (
        structuredBySourceType: {
          for (final structured in visited.structuredTypes)
            structured.sourceType: structured,
        },
        plansBySourceType: visited.reconstructionPlans,
        mapPlans: visited.mapPlans,
        recordPlans: visited.recordPlans,
        slotTargets: visited.slotTargets,
        nullableStructuredSlots: visited.nullableStructuredSlots,
        aliases: const <String, String>{},
      );
      final customerListControl = WidgetEntry(
        wireId: original.wireId,
        name: original.name,
        library: original.library,
        category: original.category,
        description: original.description,
        flutterType: original.flutterType,
        childrenSlot: ChildrenSlot.none,
        properties: <PropertyEntry>[
          ...original.properties,
          const PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'regions',
            type: PropertyType.widgetList,
            description: 'Customer child regions.',
            required: true,
          ),
        ],
      );

      expect(
        isFactoryEmittable(customerListControl, customer: context),
        isFalse,
        reason: 'the default predicate retains curated widget-list policy',
      );
      expect(
        isCustomerFactoryEmittableForWalker(
          customerListControl,
          customer: context,
        ),
        isTrue,
        reason: 'the production walker must enable exact customer lists',
      );

      expect(
        isCustomerFactoryEmittableForWalker(
          malformedHistorical,
          customer: context,
        ),
        isFalse,
      );
      final admission = computeAdmission(
        widgets: [malformedHistorical],
        structuredTypes: visited.structuredTypes,
        slotTargets: visited.slotTargets,
        localUnrenderable: visited.localUnrenderable,
        widgetUnrenderable: visited.widgetUnrenderable,
        mapPlans: visited.mapPlans,
        isWholeWidgetEmittable: (widget) => isCustomerFactoryEmittableForWalker(
          widget,
          customer: context,
        ),
      );

      expect(admission.admitted, isEmpty);
      expect(admission.excluded, hasLength(1));
      expect(
        admission.excluded.single.reason,
        contains('admitted-then-skipped incoherence'),
      );
    });

    // Pass-2 #6a — a POSITIONAL customer structured widget property must route
    // through the reconstructor (emitted positionally), not fall into the old
    // structured decoder (which throws "no registered decoder" and crashes the
    // build). It is the positional analog of a named structured prop.
    test(
        'a POSITIONAL customer structured widget property reconstructs '
        'positionally (no crash, no name prefix)', () async {
      const positionalProp = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        class Badge { const Badge({required this.label}); final String label; }
        @RestageWidget(name: 'BadgeCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class BadgeCard {
          const BadgeCard(this.badge);
          @RestageProperty(description: 'x') final Badge badge;
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        positionalProp,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': positionalProp},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf(
              contains('Badge('),
              // Positional: no `badge:` name prefix on the reconstruction.
              isNot(contains('badge:')),
              // A required positional structured prop still presence-checks.
              contains('isMap'),
              contains('BadgeCard.badge is required'),
            ),
          ),
        },
      );
    });

    // An otherwise reconstructable customer object can still use a default
    // whose constructor is private to the source library. Generated code
    // cannot spell that identity, so it must fail source-qualified at
    // authoring time rather than flattening or silently changing the default.
    test('a private customer-object constructor default fails RFW loudly',
        () async {
      const optionalProp = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        class Badge {
          const Badge({required this.label});
          const Badge._secret({required this.label});
          final String label;
        }
        @RestageWidget(name: 'BadgeCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class BadgeCard {
          const BadgeCard({this.badge = const Badge._secret(label: 'x')});
          @RestageProperty(description: 'x') final Badge badge;
        }
      ''';
      final result = await runWidgetVisitorOn(
        {'lib/widgets.dart': optionalProp},
      );
      final issue = result.issues.singleWhere(
        (candidate) =>
            candidate.code == IssueCode.invalidWidgetConstructorInput &&
            candidate.location == 'lib/widgets.dart#BadgeCard.badge',
      );
      expect(issue.message, contains('Badge._secret'));
      expect(issue.message, contains('rfw target cannot reproduce'));
    });

    // Pass-2 #2 — a String default containing `$` must be escaped in the
    // emitted `??` fallback (an unescaped `'$free'` is Dart interpolation of an
    // undefined `free`, a compile error).
    test(
        r'a String default containing `$` is escaped in the reconstruction '
        'fallback (never a stray interpolation)', () async {
      const dollarDefault = r'''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        class Badge { const Badge({this.label = r'$free'}); final String label; }
        @RestageWidget(name: 'BadgeCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class BadgeCard {
          const BadgeCard({required this.badge});
          @RestageProperty(description: 'x') final Badge badge;
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        dollarDefault,
      );

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': dollarDefault},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            // The `$` is backslash-escaped so it is a literal, not interp.
            contains(r"'\$free'"),
          ),
        },
      );
    });

    // Pass-3 #F3 — a customer structured field of a FLUTTER enum is admitted
    // IFF that enum is in `package:flutter/widgets.dart`'s EXPORT NAMESPACE (the
    // only flutter surface the generated factory imports). `Axis` (re-exported)
    // admits; `ThemeMode` (material) and `TextInputAction` (services) are NOT
    // re-exported by widgets.dart, so they exclude-loud (the export namespace
    // is ground truth — the src-path is not: Axis is `src/painting/` yet
    // exported, TextInputAction is `src/services/` yet not).
    test(
        'flutter-enum structured fields are admitted by widgets.dart export '
        'namespace: Axis admits, ThemeMode/TextInputAction exclude', () async {
      const flutterEnums = '''
        import 'package:flutter/material.dart';
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        class ThemeCfg { const ThemeCfg({required this.mode}); final ThemeMode mode; }
        class InputCfg { const InputCfg({required this.action}); final TextInputAction action; }
        class AxisCfg { const AxisCfg({required this.axis}); final Axis axis; }
        @RestageWidget(name: 'PlainButton',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input, description: 'CTA.')
        class PlainButton { const PlainButton(); }
        @RestageWidget(name: 'ThemeCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class ThemeCard {
          const ThemeCard({required this.cfg});
          @RestageProperty(description: 'x') final ThemeCfg cfg;
        }
        @RestageWidget(name: 'InputCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class InputCard {
          const InputCard({required this.cfg});
          @RestageProperty(description: 'x') final InputCfg cfg;
        }
        @RestageWidget(name: 'AxisCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class AxisCard {
          const AxisCard({required this.cfg});
          @RestageProperty(description: 'x') final AxisCfg cfg;
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets.dart'),
        flutterEnums,
      );

      await testBuilder(
        const UserCatalogBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets.dart': flutterEnums},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_catalog.g.dart': decodedMatches(
            allOf(
              contains("name: 'PlainButton'"),
              // Axis is exported by widgets.dart -> admitted.
              contains("name: 'AxisCard'"),
              // ThemeMode (material) + TextInputAction (services) are NOT
              // exported by widgets.dart -> excluded-loud from the catalog.
              isNot(contains("name: 'ThemeCard'")),
              isNot(contains("name: 'InputCard'")),
            ),
          ),
        },
      );
    });

    // A customer structured field of ENUM type whose enum is in a SEPARATE
    // file emits `RestageDecoders.enumByName<Tone>(...)`,
    // so the enum's library must be in the import closure (it imported
    // structured-type libs but missed enum libs) or the factory won't compile.
    test(
        'a NESTED enum field in a SEPARATE file is IMPORTED (aliased) and '
        'referenced QUALIFIED in the reconstruction', () async {
      const tone = 'enum Tone { soft, loud }';
      const widgets = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        import 'tone.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        class Badge { const Badge({required this.tone}); final Tone tone; }
        @RestageWidget(name: 'BadgeCard',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'c')
        class BadgeCard {
          const BadgeCard({required this.badge});
          @RestageProperty(description: 'x') final Badge badge;
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing
        ..writeString(AssetId('apps_examples', 'lib/tone.dart'), tone)
        ..writeString(AssetId('apps_examples', 'lib/widgets.dart'), widgets);

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {
          'apps_examples|lib/tone.dart': tone,
          'apps_examples|lib/widgets.dart': widgets,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf(
              // The enum's library is imported (aliased) so `Tone` resolves.
              contains('tone.dart'),
              // The enum reference is qualified with the import alias.
              matches(RegExp(r's\d+\.Tone\b')),
            ),
          ),
        },
      );
    });

    // H5 — two SAME-NAME customer structured types (`Badge` in a.dart +
    // b.dart), both referenced. The alias scheme admits both (distinct wire
    // ids), but the generated Dart cannot name both `Badge` unambiguously.
    // Uniform-prefix import aliases qualify EVERY customer reference, so a
    // same-name collision is unrepresentable by construction (no bare Badge).
    test(
        'two SAME-NAME structured types reconstruct QUALIFIED (aliased '
        'imports), never an ambiguous bare `Badge(`', () async {
      const a = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        class Badge { const Badge({required this.label}); final String label; }
        @RestageWidget(name: 'CardA',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'a')
        class CardA {
          const CardA({required this.badge});
          @RestageProperty(description: 'b') final Badge badge;
        }
      ''';
      const b = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
        @RestageLibrary(
          library: WidgetLibrary.custom('acme.design_system'),
          capabilityVersion: 1,
        )
        const restageLibrary = 0;
        class Badge { const Badge({required this.count}); final int count; }
        @RestageWidget(name: 'CardB',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.decoration, description: 'b')
        class CardB {
          const CardB({required this.badge});
          @RestageProperty(description: 'b') final Badge badge;
        }
      ''';
      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'restage_codegen',
      );
      readerWriter.testing
        ..writeString(AssetId('apps_examples', 'lib/a.dart'), a)
        ..writeString(AssetId('apps_examples', 'lib/b.dart'), b);

      await testBuilder(
        const UserFactoryBuilder(BuilderOptions.empty),
        {
          'apps_examples|lib/a.dart': a,
          'apps_examples|lib/b.dart': b,
        },
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_factories.g.dart': decodedMatches(
            allOf(
              // Each same-name Badge is reconstructed through a distinct alias.
              // (`\s*` absorbs any dart-format line wrap after the `(`.)
              matches(RegExp(r's\d+\.Badge\(\s*label:')),
              matches(RegExp(r's\d+\.Badge\(\s*count:')),
              // No ambiguous bare `Badge(` (only qualified, alias-prefixed).
              isNot(matches(RegExp(r'(?<![\w.])Badge\('))),
              // The customer libraries are imported with prefix aliases.
              matches(RegExp(r"import '[^']*a\.dart' as s\d+;")),
              matches(RegExp(r"import '[^']*b\.dart' as s\d+;")),
            ),
          ),
        },
      );
    });
  });
}
