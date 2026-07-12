import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/widgets/tier_board.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

/// Decode-side faithfulness for a NESTED list-of-objects (a `List<Tier>` whose
/// item carries a `List<Feature>`) and for the list CONTAINER contract (a
/// required list absent must fail closed; a nullable list absent must be null —
/// never a silently-empty list).
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

  TierBoard readBoard(WidgetTester tester) =>
      tester.widget<TierBoard>(find.byType(TierBoard));

  testWidgets(
    'a NESTED list (List<Tier> whose item carries List<Feature>) reconstructs '
    'each level at its OWN index, with differing inner counts',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = TierBoard(tiers: [
          { name: "Pro", features: [ { label: "a" }, { label: "b" } ] },
          { name: "Starter", features: [ { label: "c" } ] },
        ]);
      ''');

      final tiers = readBoard(tester).tiers;
      expect(tiers.map((t) => t.name), ['Pro', 'Starter']);
      // Pro has TWO features; Starter has ONE — each tier's feature list is read
      // at the tier's OWN index (a shared loop variable would mis-associate).
      expect(tiers[0].features.map((f) => f.label), ['a', 'b']);
      expect(tiers[1].features.map((f) => f.label), ['c']);
    },
  );

  testWidgets(
    'a REQUIRED list absent from the wire FAILS CLOSED (never a silently-empty '
    'list)',
    (tester) async {
      // `tiers` (required) is omitted — the generated factory must throw rather
      // than reconstruct an empty list.
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = TierBoard();
      ''');

      tester.takeException();
      expect(find.byType(TierBoard), findsNothing);
    },
  );

  testWidgets(
    'a NULLABLE list absent from the wire reconstructs as null (never a '
    'silently-empty list)',
    (tester) async {
      // `bonusTiers` (nullable) is omitted.
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = TierBoard(tiers: [
          { name: "Pro", features: [] },
        ]);
      ''');

      expect(readBoard(tester).bonusTiers, isNull);
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
