import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/main_section_header_demo.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/widgets/section_header.dart';

/// The RECORD ENCODE-SIDE SOUND NET (source → encode → wire → decode → pixels).
///
/// The `section_header_showcase` screen AUTHORS record literals in ordinary
/// Flutter (`lib/onboarding/screens/section_header_showcase.dart`). Build-time
/// codegen ENCODES both records into the committed blob as
/// field-name-keyed maps. The heading labels are deliberately authored in
/// non-canonical order. This test loads the COMMITTED `.rfw` binary — the exact
/// artifact that ships — renders it through the REAL RFW runtime and generated
/// `SectionHeader` factory (not a mock), and asserts each reconstructed label's
/// value and runtime type.
///
/// Together with `section_header_decode_golden_test.dart`, which pins the
/// decode half against hand-authored wire maps, this closes the round trip for
/// record-shaped properties.
void main() {
  setUp(() {
    Restage.debugReset();
    registerRestageCustomerWidgets();
    Restage.configure(
      apiKey: 'rs_pk_test',
      resolver: const AssetVariantResolver(),
    );
  });

  SectionHeader renderedHeader(WidgetTester tester) =>
      tester.widget<SectionHeader>(find.byType(SectionHeader));

  testWidgets(
    'the built section_header_showcase blob round-trips every authored record '
    'label through the real generated factory',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(home: SectionHeaderDemo()),
      );
      await tester.pumpAndSettle();

      final header = renderedHeader(tester);

      expect(header.heading.title, 'Choose a plan');
      expect(header.heading.title.runtimeType, String);
      expect(header.heading.step, 2);
      expect(header.heading.step.runtimeType, int);
      expect(header.heading.tone, HeaderTone.emphasis);
      expect(header.heading.tone.runtimeType, HeaderTone);

      expect(header.entry.label, 'Billing');
      expect(header.entry.label.runtimeType, String);
      expect(header.entry.meta.order, 1);
      expect(header.entry.meta.order.runtimeType, int);
      expect(header.entry.meta.pinned, isTrue);
      expect(header.entry.meta.pinned.runtimeType, bool);
    },
  );
}
