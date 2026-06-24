// End-to-end render proofs for the `Text.rich` (TextRich) catalog entry.
//
// The translator (a separate build-time package) lowers a Dart-authored
// `Text.rich(TextSpan(...))` into the wire DSL asserted here; these tests
// take that emitted DSL, build the real core widget library, decode it
// through the generated `_buildTextRich` factory (which calls
// `RestageDecoders.inlineSpan`), and assert the reconstructed `InlineSpan`
// tree. This closes the emission↔decoder loop empirically: the DSL strings
// below are byte-for-byte the translator's asserted output for the same
// sources (the Notion price row and the mixed-style legal paragraph in the
// translator suite), so a real factory rebuilding them into a real
// `TextSpan` tree proves the two halves agree.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'paywall']);

Runtime _buildRuntime(String paywallSource) => Runtime()
  ..update(_coreLibrary, buildCoreWidgetLibrary())
  ..update(_rootLibrary, parseLibraryFile(paywallSource));

/// Pumps [paywallSource] and returns the single rendered `Text` widget's
/// reconstructed root span. `Text.rich` constructs a `Text` whose
/// `textSpan` carries the decoded `InlineSpan` tree.
Future<TextSpan> _pumpAndReadSpan(
  WidgetTester tester,
  String paywallSource, {
  DynamicContent? data,
}) async {
  final runtime = _buildRuntime(paywallSource);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RemoteWidget(
        runtime: runtime,
        data: data ?? DynamicContent(),
        widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
        onEvent: (_, __) {},
      ),
    ),
  );
  await tester.pump();
  final text = tester.widget<Text>(find.byType(Text));
  return text.textSpan! as TextSpan;
}

void main() {
  group('Text.rich (TextRich) render proof', () {
    testWidgets(
      'mixed-style legal paragraph decodes into a nested TextSpan tree',
      (tester) async {
        // Byte-for-byte the translator suite's asserted DSL for the
        // mixed-style legal paragraph source.
        const blob = '''
import restage.core;
widget Paywall = TextRich(textSpan: { text: "By continuing, you agree to ", children: [{ text: "Purchaser Terms", style: { fontWeight: "w600", decoration: "underline" } }, { text: " and " }, { text: "Privacy Policy", style: { fontStyle: "italic" } }] });
''';
        final root = await _pumpAndReadSpan(tester, blob);

        expect(root.text, 'By continuing, you agree to ');
        expect(root.children, hasLength(3));

        final terms = root.children![0] as TextSpan;
        expect(terms.text, 'Purchaser Terms');
        expect(terms.style!.fontWeight, FontWeight.w600);
        expect(terms.style!.decoration, TextDecoration.underline);

        final conjunction = root.children![1] as TextSpan;
        expect(conjunction.text, ' and ');
        expect(conjunction.style, isNull);

        final privacy = root.children![2] as TextSpan;
        expect(privacy.text, 'Privacy Policy');
        expect(privacy.style!.fontStyle, FontStyle.italic);
      },
    );

    testWidgets(
      'Notion price row decodes a two-child styled span',
      (tester) async {
        // The translator's Notion price-row shape with the conditional price
        // resolved to a literal (the conditional itself is proven separately
        // below + in the translator suite).
        const blob = '''
import restage.core;
widget Paywall = TextRich(textSpan: { children: [{ text: "\$10", style: { color: 0xFF191918, fontSize: 24.0, fontWeight: "w700" } }, { text: "  per member / month", style: { color: 0xFF787774, fontSize: 13.0 } }] });
''';
        final root = await _pumpAndReadSpan(tester, blob);

        expect(root.text, isNull);
        expect(root.children, hasLength(2));

        final price = root.children![0] as TextSpan;
        expect(price.text, r'$10');
        expect(price.style!.color, const Color(0xFF191918));
        expect(price.style!.fontSize, 24.0);
        expect(price.style!.fontWeight, FontWeight.w700);

        final suffix = root.children![1] as TextSpan;
        expect(suffix.text, '  per member / month');
        expect(suffix.style!.color, const Color(0xFF787774));
        expect(suffix.style!.fontSize, 13.0);
      },
    );

    testWidgets(
      'a data-bound conditional inside a span text slot resolves through '
      'the inlineSpan decoder',
      (tester) async {
        // Proves the inlineSpan decoder reads `text` through rfw's lazy data
        // resolution (via `source.v`), so a per-value conditional / data
        // binding inside a span node — the Notion `paywallPriceFor` shape —
        // resolves correctly and reacts to the bound value. (The translator
        // emits `switch state.annualBilling { true: data..., false: data... }`;
        // the data-keyed form here exercises the same reference-resolution
        // path without the interactive state toggle.)
        const blob = '''
import restage.core;
widget Paywall = TextRich(textSpan: { children: [{ text: switch data.annual { true: data.priceAnnual, false: data.priceMonthly } }] });
''';
        final data = DynamicContent()
          ..update('annual', true)
          ..update('priceAnnual', r'$96/yr')
          ..update('priceMonthly', r'$10/mo');

        final annual = await _pumpAndReadSpan(tester, blob, data: data);
        expect((annual.children!.single as TextSpan).text, r'$96/yr');

        data.update('annual', false);
        await tester.pump();
        final text = tester.widget<Text>(find.byType(Text));
        final monthly = text.textSpan! as TextSpan;
        expect((monthly.children!.single as TextSpan).text, r'$10/mo');
      },
    );
  });
}
