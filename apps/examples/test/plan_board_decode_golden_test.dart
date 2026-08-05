import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/widgets/plan_board.dart';
import 'package:restage_example/widgets/pricing_card.dart' show PlanTier;
import 'package:rfw/formats.dart' hide WidgetLibrary;

/// Decode-side faithfulness for string-keyed and enum-keyed maps.
///
/// A map travels as an ordered list of `key`/`value` entry objects, so its
/// reconstruction carries guards a list does not need: a list rebuilt into a
/// list cannot lose an element, but a list rebuilt into a *map* can, because a
/// repeated key resolves last-wins. Complete entry lists reconstruct in the
/// authored order; a non-list container, a malformed entry, a half-formed
/// entry, a duplicate key and an unknown enum key each fail closed.
void main() {
  setUp(() {
    Restage.debugReset();
    registerRestageCustomerWidgets();
  });

  Future<void> pumpBlob(WidgetTester tester, String blob) async {
    final bytes = Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(blob)));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RestagePaywall(id: 'b', resolver: _StaticResolver(bytes)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  PlanBoard readBoard(WidgetTester tester) =>
      tester.widget<PlanBoard>(find.byType(PlanBoard));

  testWidgets(
    'a complete entry list reconstructs every key and value in wire order',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PlanBoard(
          plans: [
            { key: "team", value: { name: "Team", price: { amount: 4900 } } },
            { key: "pro", value: { name: "Pro", price: { amount: 1900 } } },
          ],
          highlights: [
            { key: "pro", value: { name: "Pro", price: { amount: 1900 } } },
          ],
        );
      ''');

      final board = readBoard(tester);
      expect(board.plans.keys.toList(), ['team', 'pro']);
      expect(board.plans['team']!.name, 'Team');
      expect(board.plans['team']!.price.amount, 4900);
      expect(board.plans['pro']!.name, 'Pro');
      expect(board.highlights.keys.toList(), [PlanTier.pro]);
      expect(board.highlights[PlanTier.pro]!.name, 'Pro');
    },
  );

  testWidgets(
    'wire order is preserved rather than sorted',
    (tester) async {
      // Authored in reverse-alphabetical order. A reconstruction that
      // canonicalised keys would yield ['alpha', 'zeta'] and fail here.
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PlanBoard(
          plans: [
            { key: "zeta", value: { name: "Zeta", price: { amount: 1 } } },
            { key: "alpha", value: { name: "Alpha", price: { amount: 2 } } },
          ],
          highlights: [],
        );
      ''');

      expect(readBoard(tester).plans.keys.toList(), ['zeta', 'alpha']);
    },
  );

  testWidgets(
    'an empty entry list reconstructs an empty map rather than failing',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PlanBoard(plans: [], highlights: []);
      ''');

      final board = readBoard(tester);
      expect(board.plans, isEmpty);
      expect(board.highlights, isEmpty);
    },
  );

  testWidgets(
    'an absent map fails closed',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PlanBoard(
          highlights: [
            { key: "pro", value: { name: "Pro", price: { amount: 1900 } } },
          ],
        );
      ''');

      tester.takeException();
      // Reconstruction throws, but its message is not observable through this
      // render harness. This pins fail-closure, not the reason for the failure.
      expect(find.byType(PlanBoard), findsNothing);
    },
  );

  testWidgets(
    'a map sent as a key-keyed object rather than an entry list fails closed',
    (tester) async {
      // The natural spelling the contract does NOT use. It must not be
      // silently accepted, and it must not silently reconstruct an empty map:
      // `length` returns 0 for a non-list, so only the container guard stands
      // between this and a plausible, wrong, empty result.
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PlanBoard(
          plans: { team: { name: "Team", price: { amount: 4900 } } },
          highlights: [],
        );
      ''');

      tester.takeException();
      // Reconstruction throws, but its message is not observable through this
      // render harness. This pins fail-closure, not the reason for the failure.
      expect(find.byType(PlanBoard), findsNothing);
    },
  );

  testWidgets(
    'a malformed entry fails closed',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PlanBoard(
          plans: ["team"],
          highlights: [],
        );
      ''');

      tester.takeException();
      // Reconstruction throws, but its message is not observable through this
      // render harness. This pins fail-closure, not the reason for the failure.
      expect(find.byType(PlanBoard), findsNothing);
    },
  );

  testWidgets(
    'an entry missing its key fails closed',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PlanBoard(
          plans: [
            { value: { name: "Team", price: { amount: 4900 } } },
          ],
          highlights: [],
        );
      ''');

      tester.takeException();
      // Reconstruction throws, but its message is not observable through this
      // render harness. This pins fail-closure, not the reason for the failure.
      expect(find.byType(PlanBoard), findsNothing);
    },
  );

  testWidgets(
    'an entry missing its value fails closed',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PlanBoard(
          plans: [
            { key: "team" },
          ],
          highlights: [],
        );
      ''');

      tester.takeException();
      // Reconstruction throws, but its message is not observable through this
      // render harness. This pins fail-closure, not the reason for the failure.
      expect(find.byType(PlanBoard), findsNothing);
    },
  );

  testWidgets(
    'a duplicate key fails closed instead of silently collapsing to one entry',
    (tester) async {
      // Without the duplicate-key guard a Dart map literal resolves the
      // repeated key last-wins, so the author's first entry would vanish and
      // the render would succeed with two entries silently become one.
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PlanBoard(
          plans: [
            { key: "team", value: { name: "First", price: { amount: 1 } } },
            { key: "team", value: { name: "Second", price: { amount: 2 } } },
          ],
          highlights: [],
        );
      ''');

      tester.takeException();
      // Reconstruction throws, but its message is not observable through this
      // render harness. This pins fail-closure, not the reason for the failure.
      expect(find.byType(PlanBoard), findsNothing);
    },
  );

  testWidgets(
    'an unknown enum key fails closed instead of defaulting to another entry',
    (tester) async {
      // The enum KEY read must throw where an enum FIELD read defaults. A
      // defaulted key would move the author's entry to a key they never sent:
      // the entry sent disappears and an entry never sent appears, with the
      // render succeeding either way.
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PlanBoard(
          plans: [],
          highlights: [
            { key: "bogus", value: { name: "Pro", price: { amount: 1900 } } },
          ],
        );
      ''');

      tester.takeException();
      // Reconstruction throws, but its message is not observable through this
      // render harness. This pins fail-closure, not the reason for the failure.
      expect(find.byType(PlanBoard), findsNothing);
    },
  );

  testWidgets(
    'an unknown enum VALUE field still defaults, unlike the key',
    (tester) async {
      // The counterpart of the test above, and the reason it cannot be
      // "simplified" for consistency: within one generated factory the enum
      // key throws while the enum field defaults. Asserting both pins the
      // asymmetry, so a change that unifies them fails one of the pair.
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PlanBoard(
          plans: [
            {
              key: "team",
              value: { name: "Team", price: { amount: 1 }, tier: "bogus" },
            },
          ],
          highlights: [],
        );
      ''');

      final board = readBoard(tester);
      expect(board.plans.keys.toList(), ['team']);
      expect(board.plans['team']!.tier, PlanTier.starter);
    },
  );

  testWidgets(
    'a stale extra entry key is ignored without displacing the real ones',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PlanBoard(
          plans: [
            {
              retired: "old",
              key: "team",
              value: { name: "Team", price: { amount: 4900 } },
            },
          ],
          highlights: [],
        );
      ''');

      final board = readBoard(tester);
      expect(board.plans.keys.toList(), ['team']);
      expect(board.plans['team']!.name, 'Team');
      expect(board.plans['team']!.price.amount, 4900);
    },
  );

  testWidgets(
    'a value missing a required field fails closed',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PlanBoard(
          plans: [
            { key: "team", value: { price: { amount: 4900 } } },
          ],
          highlights: [],
        );
      ''');

      tester.takeException();
      // Reconstruction throws, but its message is not observable through this
      // render harness. This pins fail-closure, not the reason for the failure.
      expect(find.byType(PlanBoard), findsNothing);
    },
  );

  testWidgets(
    'a nested value record reconstructs at its own path inside the entry',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PlanBoard(
          plans: [
            {
              key: "starter",
              value: {
                name: "Starter",
                price: { amount: 250, currency: "GBP" },
                badge: "New",
              },
            },
          ],
          highlights: [],
        );
      ''');

      final board = readBoard(tester);
      expect(board.plans['starter']!.price.amount, 250);
      expect(board.plans['starter']!.price.currency, 'GBP');
      expect(board.plans['starter']!.badge, 'New');
    },
  );
}

class _StaticResolver implements VariantResolver {
  _StaticResolver(this.bytes);

  final Uint8List bytes;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(bytes: bytes, paywallId: id);
}
