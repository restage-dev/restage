import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// ENCODE side of the customer-structured render: a paywall body that
/// AUTHORS a customer data-class value (`Price(999, currency: 'EUR')`)
/// compiles that value into the field-name-keyed wire map the decoder
/// faithfully reconstructs. Encode<->decode key symmetry is by construction:
/// both derive the map keys from the SAME source — the catalog
/// `StructuredEntry.fields[i].name`.

/// The library URI the synthetic probe source is mounted under, so a customer
/// class declared inline resolves to this URI — which must equal the catalog
/// [StructuredEntry.sourceType] prefix for the encode branch to recognise it.
const String _probe = kSyntheticProbeLibraryUri;

WireIdRef _ref(String library, String wireId) =>
    WireIdRef(library: library, wireId: WireId(wireId));

/// A catalog carrying customer structured entries for `Price` and (optionally)
/// `Plan`, keyed by a source type under the synthetic probe URI so a resolved
/// `Price(...)` / `Plan(...)` construction in the probe source matches.
Catalog _catalog(List<StructuredEntry> structuredTypes) => Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      libraries: {
        WidgetLibrary.material: const LibraryInfo(version: '1.0.0'),
      },
      widgets: const [],
      structuredTypes: structuredTypes,
    );

/// `Price(this.amount, {this.currency = 'USD'})` — a mixed ctor: `amount` is
/// positional (`integer`), `currency` is named (`string`).
StructuredEntry _priceEntry() => StructuredEntry(
      wireId: WireId('s0001'),
      name: 'Price',
      library: WidgetLibrary.material,
      description: '',
      sourceType: '$_probe#Price',
      fields: [
        StructuredField(
          wireId: WireId('p0001'),
          name: 'amount',
          type: PropertyType.integer,
          description: '',
          required: true,
        ),
        StructuredField(
          wireId: WireId('p0002'),
          name: 'currency',
          type: PropertyType.string,
          description: '',
        ),
      ],
      variants: [ConstructorVariant(wireId: WireId('v0001'))],
    );

/// `Plan({required name, required price, badge, tier = ...})` — all named;
/// `price` is a NESTED structured field (→ [_priceEntry]); `badge` is an
/// optional string; `tier` is an optional enum.
StructuredEntry _planEntry() => StructuredEntry(
      wireId: WireId('s0002'),
      name: 'Plan',
      library: WidgetLibrary.material,
      description: '',
      sourceType: '$_probe#Plan',
      fields: [
        StructuredField(
          wireId: WireId('p0003'),
          name: 'name',
          type: PropertyType.string,
          description: '',
          required: true,
        ),
        StructuredField(
          wireId: WireId('p0004'),
          name: 'price',
          type: PropertyType.structured,
          description: '',
          required: true,
          structuredRef: _ref('restage.material', 's0001'),
        ),
        StructuredField(
          wireId: WireId('p0005'),
          name: 'badge',
          type: PropertyType.string,
          description: '',
        ),
        StructuredField(
          wireId: WireId('p0006'),
          name: 'tier',
          type: PropertyType.enumValue,
          description: '',
        ),
      ],
      variants: [ConstructorVariant(wireId: WireId('v0002'))],
    );

/// `Metrics(this.ratio, {this.weight = 1.0})` — `ratio` positional `double`,
/// `weight` named `double`. Exercises the `asLength` (double → length) path
/// PricingCard has no field for (so it lives here, not on the public demo).
StructuredEntry _metricsEntry() => StructuredEntry(
      wireId: WireId('s0003'),
      name: 'Metrics',
      library: WidgetLibrary.material,
      description: '',
      sourceType: '$_probe#Metrics',
      fields: [
        StructuredField(
          wireId: WireId('p0007'),
          name: 'ratio',
          type: PropertyType.real,
          description: '',
          required: true,
        ),
        StructuredField(
          wireId: WireId('p0008'),
          name: 'weight',
          type: PropertyType.real,
          description: '',
        ),
      ],
      variants: [ConstructorVariant(wireId: WireId('v0003'))],
    );

/// `Plan({required name, badge})` plus a convenience `Plan.pro` named ctor —
/// two variants (the unnamed canonical + `pro`). Exercises the
/// canonical-vs-non-canonical constructor gate.
StructuredEntry _planWithNamedCtorEntry() => StructuredEntry(
      wireId: WireId('s0006'),
      name: 'Plan',
      library: WidgetLibrary.material,
      description: '',
      sourceType: '$_probe#Plan',
      fields: [
        StructuredField(
          wireId: WireId('p0011'),
          name: 'name',
          type: PropertyType.string,
          description: '',
          required: true,
        ),
        StructuredField(
          wireId: WireId('p0012'),
          name: 'badge',
          type: PropertyType.string,
          description: '',
        ),
      ],
      variants: [
        ConstructorVariant(wireId: WireId('v0006')),
        ConstructorVariant(wireId: WireId('v0007'), namedConstructor: 'pro'),
      ],
    );

void main() {
  group('customer structured value encode', () {
    test('a MIXED-ctor customer data class encodes to a field-name-keyed map',
        () async {
      final expr = await parseExpressionFromSourceForTest('''
        class Price {
          const Price(this.amount, {this.currency = 'USD'});
          final int amount;
          final String currency;
        }
        Object x() => const Price(999, currency: 'EUR');
      ''');
      final translator = ExpressionTranslator(
        catalog: _catalog([_priceEntry()]),
        helpers: HelperRegistry(),
      );

      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, '{amount: 999, currency: "EUR"}');
    });

    test('a NESTED (two-level) data class recurses into the inner map',
        () async {
      final expr = await parseExpressionFromSourceForTest('''
        class Price {
          const Price(this.amount, {this.currency = 'USD'});
          final int amount;
          final String currency;
        }
        class Plan {
          const Plan({required this.name, required this.price, this.badge});
          final String name;
          final Price price;
          final String? badge;
        }
        Object x() => const Plan(
          name: 'Pro',
          price: Price(1999, currency: 'EUR'),
          badge: 'Best value',
        );
      ''');
      final translator = ExpressionTranslator(
        catalog: _catalog([_priceEntry(), _planEntry()]),
        helpers: HelperRegistry(),
      );

      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(
        result.dsl,
        '{name: "Pro", price: {amount: 1999, currency: "EUR"}, '
        'badge: "Best value"}',
      );
    });

    test(
        'an OPTIONAL field the author omits is OMITTED from the wire map '
        '(the decoder reads the absent key as null / the constructor default)',
        () async {
      final expr = await parseExpressionFromSourceForTest('''
        class Price {
          const Price(this.amount, {this.currency = 'USD'});
          final int amount;
          final String currency;
        }
        class Plan {
          const Plan({required this.name, required this.price, this.badge});
          final String name;
          final Price price;
          final String? badge;
        }
        Object x() => const Plan(name: 'Basic', price: Price(0));
      ''');
      final translator = ExpressionTranslator(
        catalog: _catalog([_priceEntry(), _planEntry()]),
        helpers: HelperRegistry(),
      );

      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      // `currency` (Price) and `badge`/`tier` (Plan) are omitted — never
      // emitted as an explicit null.
      expect(result.dsl, '{name: "Basic", price: {amount: 0}}');
    });

    test(
        'a DOUBLE field is coerced to a double literal (asLength) so the '
        "decoder's source.v<double> does not null an author-written int",
        () async {
      final expr = await parseExpressionFromSourceForTest('''
        class Metrics {
          const Metrics(this.ratio, {this.weight = 1.0});
          final double ratio;
          final double weight;
        }
        Object x() => const Metrics(2, weight: 3);
      ''');
      final translator = ExpressionTranslator(
        catalog: _catalog([_metricsEntry()]),
        helpers: HelperRegistry(),
      );

      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, '{ratio: 2.0, weight: 3.0}');
    });

    test(
        'a customer ENUM field encodes to its member-name string (the wire '
        'representation the decoder reads back to the enum value)', () async {
      final expr = await parseExpressionFromSourceForTest('''
        enum PlanTier { starter, pro, team }
        class Price {
          const Price(this.amount, {this.currency = 'USD'});
          final int amount;
          final String currency;
        }
        class Plan {
          const Plan({
            required this.name,
            required this.price,
            this.tier = PlanTier.starter,
          });
          final String name;
          final Price price;
          final PlanTier tier;
        }
        Object x() => const Plan(
          name: 'Pro',
          price: Price(0),
          tier: PlanTier.pro,
        );
      ''');
      final translator = ExpressionTranslator(
        catalog: _catalog([_priceEntry(), _planEntry()]),
        helpers: HelperRegistry(),
      );

      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, '{name: "Pro", price: {amount: 0}, tier: "pro"}');
    });

    // === The transforming-field case ===
    //
    // The encode captures the author's CONSTRUCTOR ARGUMENT under each field's
    // name (not the materialized field value), and the decode re-applies the
    // SAME constructor. So a field that is a non-identity function of its
    // same-named ctor parameter round-trips FAITHFULLY by construction (the
    // transform is applied identically at author time and reconstruction time);
    // and a field with NO same-named parameter is excluded-loud. There is no
    // admitted-but-mis-decoded case.

    test(
        'a SAME-NAMED transforming field encodes the author ARGUMENT (not the '
        'materialized value) — so the decoder re-applies the transform and the '
        'round-trip is faithful by construction', () async {
      // `Bumped(count: 5)` materialises `count == 10`, but the wire must carry
      // the ARGUMENT `5`: the decoder reconstructs `Bumped(count: 5)` → `10`,
      // matching the original. Emitting the materialized `10` would double it
      // on decode (`Bumped(count: 10)` → `20`) — the unfaithful outcome this
      // capture-the-argument mechanism structurally avoids.
      final expr = await parseExpressionFromSourceForTest('''
        class Bumped {
          const Bumped({required int count}) : count = count * 2;
          final int count;
        }
        Object x() => const Bumped(count: 5);
      ''');
      final structured = StructuredEntry(
        wireId: WireId('s0004'),
        name: 'Bumped',
        library: WidgetLibrary.material,
        description: '',
        sourceType: '$_probe#Bumped',
        fields: [
          StructuredField(
            wireId: WireId('p0009'),
            name: 'count',
            type: PropertyType.integer,
            description: '',
            required: true,
          ),
        ],
        variants: [ConstructorVariant(wireId: WireId('v0004'))],
      );
      final translator = ExpressionTranslator(
        catalog: _catalog([structured]),
        helpers: HelperRegistry(),
      );

      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, '{count: 5}'); // the argument, NOT the materialized 10
    });

    test(
        'a value AUTHORED VIA A NON-CANONICAL CONSTRUCTOR is DEFERRED LOUD — '
        'never silently encoded against a ctor the decoder does not '
        'reconstruct through', () async {
      // The decoder always rebuilds via the reconstruction variant (the
      // canonical unnamed constructor, or the first constructor variant when
      // there is no unnamed one) — never the constructor the author actually
      // invoked. `Plan.pro` is a convenience named constructor that
      // materialises `badge` to `'PRO'` without taking a `badge` parameter;
      // encoding from it would omit `badge` from the wire map, and the
      // decoder — reconstructing via the canonical `Plan(...)` — would then
      // read `badge` back as its default, not `'PRO'`: a silent wrong value.
      // The encode must recognise this mismatch and defer rather than emit a
      // map keyed to a constructor the decoder never uses.
      final expr = await parseExpressionFromSourceForTest('''
        class Plan {
          const Plan({required this.name, this.badge});
          const Plan.pro({required this.name}) : badge = 'PRO';
          final String name;
          final String? badge;
        }
        Object x() => const Plan.pro(name: 'X');
      ''');
      final translator = ExpressionTranslator(
        catalog: _catalog([_planWithNamedCtorEntry()]),
        helpers: HelperRegistry(),
      );

      final result = translator.translate(expr);

      expect(result.dsl, ''); // deferred, never a map keyed to the wrong ctor
      expect(
        result.issues.map((i) => i.message).join('\n'),
        contains('canonical constructor'),
      );
    });

    test(
        'authoring via the CANONICAL constructor (the one the decoder '
        'reconstructs through) still encodes normally', () async {
      final expr = await parseExpressionFromSourceForTest('''
        class Plan {
          const Plan({required this.name, this.badge});
          const Plan.pro({required this.name}) : badge = 'PRO';
          final String name;
          final String? badge;
        }
        Object x() => const Plan(name: 'X', badge: 'set');
      ''');
      final translator = ExpressionTranslator(
        catalog: _catalog([_planWithNamedCtorEntry()]),
        helpers: HelperRegistry(),
      );

      final result = translator.translate(expr);

      expect(result.issues, isEmpty);
      expect(result.dsl, '{name: "X", badge: "set"}');
    });

    test(
        'a NESTED value authored via a non-canonical constructor defers the '
        'WHOLE OUTER value — never a partial map with an empty inner entry',
        () async {
      // `price` is authored via `Price.eur(...)`, a non-canonical ctor (the
      // same class as the top-level negative fixture above, just nested one
      // level in). The inner `tryEmit` for `Price.eur(...)` correctly defers
      // to '' and raises its own issue — but the OUTER map must not simply
      // splice that '' in as `price: `, which would emit a syntactically
      // broken partial map. The whole `Plan(...)` value must defer too.
      final expr = await parseExpressionFromSourceForTest('''
        class Price {
          const Price(this.amount);
          const Price.eur(int value) : amount = value;
          final int amount;
        }
        class Plan {
          const Plan({required this.name, required this.price});
          final String name;
          final Price price;
        }
        Object x() => const Plan(name: 'Pro', price: Price.eur(1999));
      ''');
      final priceEntryWithNamedCtor = StructuredEntry(
        wireId: WireId('s0007'),
        name: 'Price',
        library: WidgetLibrary.material,
        description: '',
        sourceType: '$_probe#Price',
        fields: [
          StructuredField(
            wireId: WireId('p0013'),
            name: 'amount',
            type: PropertyType.integer,
            description: '',
            required: true,
          ),
        ],
        variants: [
          ConstructorVariant(wireId: WireId('v0008')),
          ConstructorVariant(wireId: WireId('v0009'), namedConstructor: 'eur'),
        ],
      );
      final planEntryNestingPrice = StructuredEntry(
        wireId: WireId('s0008'),
        name: 'Plan',
        library: WidgetLibrary.material,
        description: '',
        sourceType: '$_probe#Plan',
        fields: [
          StructuredField(
            wireId: WireId('p0014'),
            name: 'name',
            type: PropertyType.string,
            description: '',
            required: true,
          ),
          StructuredField(
            wireId: WireId('p0015'),
            name: 'price',
            type: PropertyType.structured,
            description: '',
            required: true,
            structuredRef: _ref('restage.material', 's0007'),
          ),
        ],
        variants: [ConstructorVariant(wireId: WireId('v0010'))],
      );
      final translator = ExpressionTranslator(
        catalog: _catalog([priceEntryWithNamedCtor, planEntryNestingPrice]),
        helpers: HelperRegistry(),
      );

      final result = translator.translate(expr);

      // Deferred as a whole — never `{name: "Pro", price: }`.
      expect(result.dsl, '');
      expect(
        result.issues.map((i) => i.message).join('\n'),
        contains('canonical constructor'),
      );
    });

    test(
        'a REQUIRED field with NO same-named constructor parameter is '
        'DEFERRED LOUD (fail-closed) — never a partial or mis-sourced map',
        () async {
      // `Doubler(int n) : value = n * 2` — the field `value` has no ctor
      // parameter named `value`, so the encode cannot faithfully source it.
      // (the decode-side admission gate already excludes this shape as
      // required-param-no-field; this asserts the encode's own fail-closed
      // defense-in-depth.)
      final expr = await parseExpressionFromSourceForTest('''
        class Doubler {
          const Doubler(int n) : value = n * 2;
          final int value;
        }
        Object x() => const Doubler(5);
      ''');
      final structured = StructuredEntry(
        wireId: WireId('s0005'),
        name: 'Doubler',
        library: WidgetLibrary.material,
        description: '',
        sourceType: '$_probe#Doubler',
        fields: [
          StructuredField(
            wireId: WireId('p0010'),
            name: 'value',
            type: PropertyType.integer,
            description: '',
            required: true,
          ),
        ],
        variants: [ConstructorVariant(wireId: WireId('v0005'))],
      );
      final translator = ExpressionTranslator(
        catalog: _catalog([structured]),
        helpers: HelperRegistry(),
      );

      final result = translator.translate(expr);

      expect(result.dsl, ''); // deferred, never a partial map
      expect(
        result.issues.map((i) => i.message).join('\n'),
        contains('cannot be encoded'),
      );
    });

    test(
        'a customer type that is NOT a discovered structured value falls '
        'through (the branch never swallows a non-structured construction)',
        () async {
      // `Gadget` is not in the catalog's structuredTypes, so tryEmit returns
      // null and the construction routes to widget construction — which, with
      // no matching catalog widget, surfaces the unchanged unknownWidget
      // diagnostic (proving the encode branch did not intercept it).
      final expr = await parseExpressionFromSourceForTest('''
        class Gadget { const Gadget(this.label); final String label; }
        Object x() => const Gadget('x');
      ''');
      final translator = ExpressionTranslator(
        catalog: _catalog([_priceEntry()]),
        helpers: HelperRegistry(),
      );

      final result = translator.translate(expr);

      expect(
        result.issues.map((i) => i.code),
        contains(IssueCode.unknownWidget),
      );
    });
  });
}
