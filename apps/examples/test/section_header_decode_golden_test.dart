import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/widgets/section_header.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

/// Decode-side faithfulness for widget-level and nested named records.
///
/// Complete maps reconstruct label by label. Missing slots, missing labels,
/// retyped labels, and unknown enum members fail closed, while stale extra keys
/// cannot displace any admitted label.
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

  SectionHeader readHeader(WidgetTester tester) =>
      tester.widget<SectionHeader>(find.byType(SectionHeader));

  testWidgets(
    'a complete record map reconstructs every heading and entry label',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = SectionHeader(
          heading: { step: 2, title: "Choose a plan", tone: "emphasis" },
          entry: {
            label: "Billing",
            meta: { order: 1, pinned: true },
          },
        );
      ''');

      final header = readHeader(tester);
      expect(header.heading.title, 'Choose a plan');
      expect(header.heading.step, 2);
      expect(header.heading.tone, HeaderTone.emphasis);
      expect(header.entry.label, 'Billing');
      expect(header.entry.meta.order, 1);
      expect(header.entry.meta.pinned, isTrue);
    },
  );

  testWidgets(
    'an absent heading map fails closed',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = SectionHeader(
          entry: {
            label: "Billing",
            meta: { order: 1, pinned: true },
          },
        );
      ''');

      tester.takeException();
      // Reconstruction throws, but its message is not observable through this
      // render harness. This pins fail-closure, not the reason for the failure.
      expect(find.byType(SectionHeader), findsNothing);
    },
  );

  testWidgets(
    'a missing heading label fails closed',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = SectionHeader(
          heading: { title: "Choose a plan", tone: "emphasis" },
          entry: {
            label: "Billing",
            meta: { order: 1, pinned: true },
          },
        );
      ''');

      tester.takeException();
      // Reconstruction throws, but its message is not observable through this
      // render harness. This pins fail-closure, not the reason for the failure.
      expect(find.byType(SectionHeader), findsNothing);
    },
  );

  testWidgets(
    'a retyped heading label fails closed',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = SectionHeader(
          heading: {
            step: "two",
            title: "Choose a plan",
            tone: "emphasis",
          },
          entry: {
            label: "Billing",
            meta: { order: 1, pinned: true },
          },
        );
      ''');

      tester.takeException();
      // Reconstruction throws, but its message is not observable through this
      // render harness. This pins fail-closure, not the reason for the failure.
      expect(find.byType(SectionHeader), findsNothing);
    },
  );

  testWidgets(
    'an unknown heading enum member fails closed instead of defaulting',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = SectionHeader(
          heading: { step: 2, title: "Choose a plan", tone: "bogus" },
          entry: {
            label: "Billing",
            meta: { order: 1, pinned: true },
          },
        );
      ''');

      tester.takeException();
      // Reconstruction throws, but its message is not observable through this
      // render harness. This pins fail-closure, not the reason for the failure.
      expect(find.byType(SectionHeader), findsNothing);
    },
  );

  testWidgets(
    'a stale extra record key is ignored without displacing real labels',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = SectionHeader(
          heading: {
            retired: "old",
            step: 2,
            title: "Choose a plan",
            tone: "emphasis",
          },
          entry: {
            label: "Billing",
            meta: { order: 1, pinned: true },
          },
        );
      ''');

      final header = readHeader(tester);
      expect(header.heading.title, 'Choose a plan');
      expect(header.heading.step, 2);
      expect(header.heading.tone, HeaderTone.emphasis);
      expect(header.entry.label, 'Billing');
      expect(header.entry.meta.order, 1);
      expect(header.entry.meta.pinned, isTrue);
    },
  );

  testWidgets(
    'entry.meta reconstructs at its own nested path',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = SectionHeader(
          heading: { step: 3, title: "Confirm details", tone: "neutral" },
          entry: {
            label: "Profile",
            meta: { order: 7, pinned: false },
          },
        );
      ''');

      final header = readHeader(tester);
      expect(header.heading.title, 'Confirm details');
      expect(header.heading.step, 3);
      expect(header.heading.tone, HeaderTone.neutral);
      expect(header.entry.label, 'Profile');
      expect(header.entry.meta.order, 7);
      expect(header.entry.meta.pinned, isFalse);
    },
  );

  testWidgets(
    'an absent entry.meta record fails closed',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = SectionHeader(
          heading: { step: 2, title: "Choose a plan", tone: "emphasis" },
          entry: { label: "Billing" },
        );
      ''');

      tester.takeException();
      // Reconstruction throws, but its message is not observable through this
      // render harness. This pins fail-closure, not the reason for the failure.
      expect(find.byType(SectionHeader), findsNothing);
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
