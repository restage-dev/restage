import 'dart:typed_data';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:collection/collection.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('RestageCodegenBuilder end-to-end', () {
    test('valid @PaywallSource emits paywall artifacts and adapter', () async {
      const source = '''
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'hello')
        class HelloPaywall extends StatelessWidget {
          const HelloPaywall();
          Widget build(BuildContext context) => Center(child: SizedBox());
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: false,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/hello.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/hello.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/hello.capability.json': anything,
          'apps_examples|assets/paywalls/hello.rfwtxt': decodedMatches(
            allOf(
              contains('import restage.core;'),
              contains('widget Paywall ='),
              contains('Center'),
              contains('SizedBox'),
            ),
          ),
          'apps_examples|assets/paywalls/hello.rfw': isNotEmpty,
          'apps_examples|assets/onboarding/screens/paywall_hello.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test('emits a capability-manifest sidecar for a built-in-only paywall',
        () async {
      const source = '''
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'cap')
        class CapPaywall extends StatelessWidget {
          const CapPaywall();
          Widget build(BuildContext context) => Center(child: SizedBox());
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: false,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/cap.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/cap.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/cap.rfwtxt': anything,
          'apps_examples|assets/paywalls/cap.rfw': isNotEmpty,
          'apps_examples|assets/onboarding/screens/paywall_cap.rfw': anything,
          // A built-in-only paywall derives a baseline floor and no required
          // custom libraries; the sidecar carries the manifest to the publisher.
          'apps_examples|assets/paywalls/cap.capability.json': decodedMatches(
            allOf(
              contains('"builtInFloor": 1'),
              contains('"requiredLibraries": []'),
            ),
          ),
        },
      );
    });

    test(
        'a custom-library paywall emits a capability manifest carrying the '
        'required library (real build through the merged customer catalog)',
        () async {
      // The hand-authored DSL references a custom widget (AcmeBanner). The
      // customer's generated catalog — merged into the build-time catalog by
      // loadMergedCatalog — declares it in library "acme.widgets" at
      // capabilityVersion 2, so the derivation emits a populated
      // requiredLibraries. This exercises the requiredLibraries path in a real
      // build, not just the unit derivation.
      const source = '''
import acme.widgets;
widget Paywall = AcmeBanner();
''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: false,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/promo.rfwtxt'),
        source,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/src/widget_catalog/catalog.json'),
        encodeCatalog(_acmeCustomerCatalog()),
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/promo.rfwtxt': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/promo.rfw': isNotEmpty,
          'apps_examples|assets/paywalls/promo.capability.json': decodedMatches(
            allOf(
              contains('"namespace": "acme.widgets"'),
              contains('"minVersion": 2'),
            ),
          ),
        },
      );
    });

    test(
        'Container(clipBehavior: Clip.antiAlias) lowers the clip slot against '
        'the real catalog — no translator change', () async {
      // Depth-coverage proof for the `Container` clip slot: the `clipBehavior`
      // parameter, formerly stripped from reflector inference, is now surfaced
      // as a `Clip` enum slot reusing the existing enum decoder. A vanilla
      // `Container(clipBehavior: Clip.antiAlias, ...)` lowers the enum member
      // to its wire string against the REAL merged catalog, with no change to
      // the expression translator — the generic enum-slot lowering already in
      // place (the same path that lowers `ClipRect` / `Stack` clip behavior).
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'clipped_box')
        class ClippedBox extends StatelessWidget {
          const ClippedBox();
          Widget build(BuildContext context) => Container(
            clipBehavior: Clip.antiAlias,
            child: const SizedBox(width: 24.0, height: 24.0),
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/clipped_box.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/clipped_box.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/clipped_box.rfwtxt': decodedMatches(
            allOf(
              contains('Container('),
              contains('clipBehavior: "antiAlias"'),
            ),
          ),
          'apps_examples|assets/paywalls/clipped_box.rfw': isNotEmpty,
          'apps_examples|assets/paywalls/clipped_box.capability.json': anything,
          'apps_examples|assets/onboarding/screens/paywall_clipped_box.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test(
        'Container(constraints: BoxConstraints(...)) lowers to flat min/max '
        'slots against the real catalog — no translator change', () async {
      // Depth-coverage proof for the `Container` constraints slot: the
      // `constraints` parameter (a `BoxConstraints`) is surfaced through the
      // flat-scalar decompose pattern (the same pattern that hoists
      // `BoxDecoration`'s inner ctor args onto flat properties). A vanilla
      // `Container(constraints: BoxConstraints(minWidth: 100, maxWidth: 300))`
      // decomposes to FLAT real slots (`minWidth` / `maxWidth`) against the
      // REAL merged catalog, with no change to the expression translator —
      // only the explicitly-set fields emit, so an absent `maxHeight` never
      // leaks a literal `double.infinity` onto the wire.
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'constrained_box')
        class ConstrainedBoxPaywall extends StatelessWidget {
          const ConstrainedBoxPaywall();
          Widget build(BuildContext context) => Container(
            constraints: const BoxConstraints(minWidth: 100, maxWidth: 300),
            child: const SizedBox(width: 24.0, height: 24.0),
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/constrained_box.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/constrained_box.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/constrained_box.rfwtxt':
              decodedMatches(
            allOf(
              contains('Container('),
              // FLAT keys — the decompose hoists the set fields onto flat
              // real slots, never a `constraints: {...}` map.
              contains('minWidth: 100.0'),
              contains('maxWidth: 300.0'),
              isNot(contains('constraints:')),
              // The unset fields stay off the wire — no infinity default leaks.
              isNot(contains('Infinity')),
              isNot(contains('minHeight:')),
              isNot(contains('maxHeight:')),
            ),
          ),
          'apps_examples|assets/paywalls/constrained_box.rfw': isNotEmpty,
          'apps_examples|assets/paywalls/constrained_box.capability.json':
              anything,
          'apps_examples|assets/onboarding/screens/paywall_constrained_box.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test(
        'FilledButton(style: styleFrom(minimumSize: Size(...))) lowers the '
        'size slot to a {width, height} map against the real catalog',
        () async {
      // Depth-coverage proof for the registered structured `Size` value slot:
      // a button's `minimumSize` (a `ButtonStyle` field hoisted via
      // `<Button>.styleFrom`) is a `structured` slot whose `Size(width,
      // height)` source lowers to a `{width, height}` MAP on the wire (unlike
      // the BoxConstraints flat-scalar pattern) and decodes through the
      // registered `Size` runtime decoder. The translator emits the map from
      // the `Size` recipe; the factory reads it through the structured-ref
      // decoder.
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'sized_button')
        class SizedButtonPaywall extends StatelessWidget {
          const SizedButtonPaywall();
          Widget build(BuildContext context) => FilledButton(
            style: FilledButton.styleFrom(minimumSize: Size(200, 48)),
            onPressed: null,
            child: const Text('Go'),
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/sized_button.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/sized_button.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/sized_button.rfwtxt': decodedMatches(
            allOf(
              contains('FilledButton('),
              // The Size value is a {width, height} MAP — the structured-slot
              // shape, distinct from BoxConstraints' flat keys.
              contains('minimumSize: {width: 200.0, height: 48.0}'),
            ),
          ),
          'apps_examples|assets/paywalls/sized_button.rfw': isNotEmpty,
          'apps_examples|assets/paywalls/sized_button.capability.json':
              anything,
          'apps_examples|assets/onboarding/screens/paywall_sized_button.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test(
        'OutlinedButton(style: styleFrom(side: BorderSide(...))) lowers the '
        'side slot to a {color, width} map against the real catalog', () async {
      // Depth-coverage proof for the registered structured `BorderSide` value
      // slot: a button's `side` (a `ButtonStyle` field hoisted via
      // `<Button>.styleFrom`) is a `structured` slot whose `BorderSide(color:,
      // width:)` source lowers to a `{color, width}` MAP on the wire and
      // decodes through the registered `BorderSide` runtime decoder. The
      // source-lowering reuses the existing `BorderSide(...)` recognizer (the
      // same one used by `shape.side`); the factory reads it through the
      // structured-ref decoder.
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'sided_button')
        class SidedButtonPaywall extends StatelessWidget {
          const SidedButtonPaywall();
          Widget build(BuildContext context) => OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF112233), width: 2),
            ),
            onPressed: null,
            child: const Text('Go'),
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/sided_button.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/sided_button.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/sided_button.rfwtxt': decodedMatches(
            allOf(
              contains('OutlinedButton('),
              // The BorderSide value is a {color, width} MAP — the
              // structured-slot shape decoded by the registered BorderSide
              // decoder. The color is the rfw packed-int shape.
              contains('side: {color: 0x'),
              contains('width: 2.0'),
            ),
          ),
          'apps_examples|assets/paywalls/sided_button.rfw': isNotEmpty,
          'apps_examples|assets/paywalls/sided_button.capability.json':
              anything,
          'apps_examples|assets/onboarding/screens/paywall_sided_button.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test(
        'FilledButton(style: styleFrom(textStyle: TextStyle(...))) lowers the '
        'textStyle slot to a map against the real catalog', () async {
      // Depth-coverage proof for the registered structured `TextStyle` value
      // slot: a button's `textStyle` (a `ButtonStyle` field hoisted via
      // `<Button>.styleFrom`) is a `structured` slot whose `TextStyle(...)`
      // source lowers to a map on the wire and decodes through the registered
      // `TextStyle` runtime decoder. Distinct from the FLAT TextStyle
      // decompose on Text / DefaultTextStyle (which coexists by context).
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'styled_button')
        class StyledButtonPaywall extends StatelessWidget {
          const StyledButtonPaywall();
          Widget build(BuildContext context) => FilledButton(
            style: FilledButton.styleFrom(
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF112233),
                letterSpacing: 1,
              ),
            ),
            onPressed: null,
            child: const Text('Go'),
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/styled_button.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/styled_button.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/styled_button.rfwtxt': decodedMatches(
            allOf(
              contains('FilledButton('),
              // The TextStyle value lowers to a map with the set fields —
              // the structured-slot shape decoded by the registered TextStyle
              // decoder. `FontWeight.bold` canonicalizes to its `wN` decoder
              // name (`"w700"`), the exact name `enumValue<FontWeight>` reads;
              // `Color(...)` -> packed int; an int `letterSpacing` coerces to
              // a double (asLength) so the strict `v<double>` read doesn't null
              // it.
              contains('textStyle: {'),
              contains('fontSize: 18.0'),
              contains('fontWeight: "w700"'),
              contains('color: 0xFF112233'),
              contains('letterSpacing: 1.0'),
            ),
          ),
          'apps_examples|assets/paywalls/styled_button.rfw': isNotEmpty,
          'apps_examples|assets/paywalls/styled_button.capability.json':
              anything,
          'apps_examples|assets/onboarding/screens/paywall_styled_button.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test(
        'Column/Row(spacing:) lowers the spacing slot against the real catalog '
        '— no translator change', () async {
      // Depth seed D#2: `spacing` (the dominant modern Flutter layout idiom,
      // Flex.spacing) was stripped from `kFlexExcludes`; it is now surfaced as
      // a `length`/`real` slot reusing the existing decoder (`Wrap` already
      // proved the path). Layout-critical: absent spacing renders children
      // cramped, so this slot's fidelity matters most.
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'spaced_stack')
        class SpacedStack extends StatelessWidget {
          const SpacedStack();
          Widget build(BuildContext context) => Column(
            spacing: 12.0,
            children: const [
              SizedBox(width: 8.0, height: 8.0),
              SizedBox(width: 8.0, height: 8.0),
            ],
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/spaced_stack.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/spaced_stack.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/spaced_stack.rfwtxt': decodedMatches(
            allOf(contains('Column('), contains('spacing: 12.0')),
          ),
          'apps_examples|assets/paywalls/spaced_stack.rfw': isNotEmpty,
          'apps_examples|assets/paywalls/spaced_stack.capability.json':
              anything,
          'apps_examples|assets/onboarding/screens/paywall_spaced_stack.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test(
        'Image.network(color/colorBlendMode/repeat/filterQuality/alignment) '
        'lowers the visual slots against the real catalog — no translator '
        'change', () async {
      // Depth seed D#1: the visual modifiers (`color`, `colorBlendMode`,
      // `alignment`, `repeat`, `filterQuality`) were stripped from
      // `kImageVisualExcludes`; they are now surfaced reusing the existing
      // color / enum / alignment decoders. The async-loader knobs (scale,
      // cache*, gaplessPlayback, …) stay excluded by design.
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'tinted_hero')
        class TintedHero extends StatelessWidget {
          const TintedHero();
          Widget build(BuildContext context) => Image.network(
            'https://example.com/hero.png',
            color: const Color(0xFF112233),
            colorBlendMode: BlendMode.modulate,
            alignment: Alignment.topLeft,
            repeat: ImageRepeat.repeat,
            filterQuality: FilterQuality.high,
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/tinted_hero.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/tinted_hero.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/tinted_hero.rfwtxt': decodedMatches(
            allOf(
              contains('color:'),
              contains('colorBlendMode: "modulate"'),
              contains('repeat: "repeat"'),
              contains('filterQuality: "high"'),
              contains('alignment:'),
            ),
          ),
          'apps_examples|assets/paywalls/tinted_hero.rfw': isNotEmpty,
          'apps_examples|assets/paywalls/tinted_hero.capability.json': anything,
          'apps_examples|assets/onboarding/screens/paywall_tinted_hero.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test(
        'Text(softWrap/overflow/textWidthBasis/semanticsLabel) lowers the '
        'layout slots against the real catalog — no translator change',
        () async {
      // Depth seed D#6: the widget-level text-layout knobs (`softWrap`,
      // `overflow`, `textWidthBasis`, `semanticsLabel`) were stripped from the
      // `Text` `excludeParams`; they are now surfaced reusing the boolean /
      // enum / string decoders, matching what RestagePrice / RestageFormattedNumber
      // already expose.
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'clipped_text')
        class ClippedText extends StatelessWidget {
          const ClippedText();
          Widget build(BuildContext context) => Text(
            'Unlock everything',
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textWidthBasis: TextWidthBasis.longestLine,
            semanticsLabel: 'Unlock all features',
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/clipped_text.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/clipped_text.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/clipped_text.rfwtxt': decodedMatches(
            allOf(
              contains('softWrap: false'),
              contains('overflow: "ellipsis"'),
              contains('textWidthBasis: "longestLine"'),
              contains('semanticsLabel: "Unlock all features"'),
            ),
          ),
          'apps_examples|assets/paywalls/clipped_text.rfw': isNotEmpty,
          'apps_examples|assets/paywalls/clipped_text.capability.json':
              anything,
          'apps_examples|assets/onboarding/screens/paywall_clipped_text.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test(
        'Card(clipBehavior:) lowers — the clip slot is surfaced library-wide '
        '(Material), reusing the enum decoder', () async {
      // Representative proof that the `clipBehavior` drain generalizes across
      // libraries: the same `enumValue<Clip>` slot is now surfaced on every
      // clip-capable widget (here a Material `Card`), not just the core
      // Container seed — curation-only, no translator change.
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'clipped_card')
        class ClippedCard extends StatelessWidget {
          const ClippedCard();
          Widget build(BuildContext context) => Card(
            clipBehavior: Clip.antiAliasWithSaveLayer,
            child: const SizedBox(width: 32.0, height: 32.0),
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/clipped_card.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/clipped_card.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/clipped_card.rfwtxt': decodedMatches(
            allOf(
              contains('Card('),
              contains('clipBehavior: "antiAliasWithSaveLayer"'),
            ),
          ),
          'apps_examples|assets/paywalls/clipped_card.rfw': isNotEmpty,
          'apps_examples|assets/paywalls/clipped_card.capability.json':
              anything,
          'apps_examples|assets/onboarding/screens/paywall_clipped_card.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test('filename / id mismatch emits filenameMismatch and no outputs',
        () async {
      const source = '''
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'pro_upgrade')
        class ProUpgradePaywall extends StatelessWidget {
          const ProUpgradePaywall();
          Widget build(BuildContext context) => Center();
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: false,
      );
      // Filename is `wrong.dart`, not `pro_upgrade.dart` — the
      // generator must reject before writing artifacts.
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/wrong.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/wrong.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: const {},
      );
    });

    test('emitted .rfw round-trips cleanly via the shared decoder', () async {
      // The runtime mounts paywalls by calling decodeLibraryBlob on
      // the .rfw bytes; this round-trip confirms the full codegen
      // pipeline emits a byte sequence the decoder accepts and the
      // resulting widget tree matches the source shape.
      const source = '''
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'round_trip')
        class RoundTripPaywall extends StatelessWidget {
          const RoundTripPaywall();
          Widget build(BuildContext context) => Center(
            child: SizedBox(width: 64.0, height: 64.0),
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: false,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/round_trip.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/round_trip.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/round_trip.capability.json': anything,
          'apps_examples|assets/paywalls/round_trip.rfwtxt':
              decodedMatches(contains('widget Paywall =')),
          'apps_examples|assets/paywalls/round_trip.rfw':
              const _RoundTripMatcher(),
          'apps_examples|assets/onboarding/screens/paywall_round_trip.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test(
        'Text(NumberFormat.currency(...).format(v), style, textAlign) '
        'auto-substitutes to a RestagePrice node, style carried, byte-stable',
        () async {
      // The faithful end-to-end: the real merged catalog (RestagePrice
      // present), the real Flutter Text + TextStyle/TextAlign, and the real
      // intl NumberFormat. The recognised idiom rewrites to a RestagePrice node
      // whose `style` decomposes to the same flat props a hand-authored
      // RestagePrice would, and the emitted .rfw round-trips via the decoder.
      const source = '''
        import 'package:flutter/material.dart';
        import 'package:intl/intl.dart' show NumberFormat;
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'price_tag')
        class PriceTag extends StatelessWidget {
          const PriceTag();
          Widget build(BuildContext context) => Text(
            NumberFormat.currency(locale: 'en_US', symbol: r'\$', decimalDigits: 2)
                .format(9.99),
            style: TextStyle(fontSize: 24.0, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
        includeIntl: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/price_tag.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/price_tag.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/price_tag.capability.json': anything,
          'apps_examples|assets/paywalls/price_tag.rfwtxt': decodedMatches(
            allOf(
              contains('RestagePrice('),
              contains('value: 9.99'),
              contains('decimalDigits: 2'),
              // `style` decomposed onto the widget, exactly as a hand-authored
              // RestagePrice would (the shared TextStyle recipe).
              contains('fontSize: 24'),
              contains('textAlign:'),
              // The imperative formatting call is gone from the blob.
              isNot(contains('NumberFormat')),
              isNot(contains('.format(')),
            ),
          ),
          // L3 byte proof: the emitted BINARY blob decodes to a Paywall whose
          // body root is a RestagePrice carrying the statically-extracted
          // config — the substitution survives the encode/decode round-trip.
          'apps_examples|assets/paywalls/price_tag.rfw':
              const _SubstitutedPriceMatcher(),
          'apps_examples|assets/onboarding/screens/paywall_price_tag.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test('interpolated price string emits TextRich spans, style byte-stable',
        () async {
      const source = '''
        import 'package:flutter/material.dart';
        import 'package:restage/restage.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'price_string')
        class PriceStringPaywall extends StatelessWidget {
          const PriceStringPaywall();
          Widget build(BuildContext context) => Text(
            'Only \${paywallPriceFor(slot: 'pro')}/month',
            style: const TextStyle(
              color: Color(0xFF111111),
              fontSize: 18.0,
              fontWeight: FontWeight.w700,
            ),
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/price_string.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/price_string.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/price_string.capability.json':
              anything,
          'apps_examples|assets/paywalls/price_string.rfwtxt': decodedMatches(
            allOf(
              contains('TextRich('),
              contains('textSpan:'),
              contains('data.products.pro.localizedPrice'),
              contains('fontSize: 18.0'),
              contains('fontWeight: "w700"'),
              isNot(contains('RichText(')),
              isNot(contains('__rfw_interp')),
            ),
          ),
          'apps_examples|assets/paywalls/price_string.rfw':
              const _TextRichPriceStringMatcher(),
          'apps_examples|assets/onboarding/screens/paywall_price_string.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test(
        'PageView(children:) aliases to a RestagePager node, byte-stable + '
        'round-trips', () async {
      // The Mojo testimonial-carousel idiom: a dev writes vanilla-Flutter
      // PageView; the transpiler aliases it to the declarative RestagePager
      // catalog widget. The .rfwtxt carries RestagePager; the binary .rfw
      // decodes to a RestagePager root with the three child pages (the
      // alias→wire mapping survives encode/decode — the render proof).
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'carousel')
        class CarouselPaywall extends StatelessWidget {
          const CarouselPaywall();
          Widget build(BuildContext context) => PageView(
            children: const [SizedBox(), SizedBox(), SizedBox()],
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/carousel.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/carousel.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/carousel.capability.json': anything,
          'apps_examples|assets/paywalls/carousel.rfwtxt': decodedMatches(
            allOf(
              contains('RestagePager('),
              contains('children:'),
              isNot(contains('PageView')),
            ),
          ),
          'apps_examples|assets/paywalls/carousel.rfw':
              const _PagerMatcher(childCount: 3),
          'apps_examples|assets/onboarding/screens/paywall_carousel.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test(
        'PageView controller PageController(initialPage:, viewportFraction:) '
        'flattens onto RestagePager props', () async {
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'carousel_ctrl')
        class CarouselCtrlPaywall extends StatelessWidget {
          const CarouselCtrlPaywall();
          Widget build(BuildContext context) => PageView(
            controller: PageController(initialPage: 1, viewportFraction: 0.85),
            children: const [SizedBox(), SizedBox()],
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/carousel_ctrl.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/carousel_ctrl.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/carousel_ctrl.capability.json':
              anything,
          'apps_examples|assets/paywalls/carousel_ctrl.rfwtxt': decodedMatches(
            allOf(
              contains('RestagePager('),
              contains('initialPage: 1'),
              contains('viewportFraction: 0.85'),
            ),
          ),
          'apps_examples|assets/paywalls/carousel_ctrl.rfw':
              const _PagerMatcher(
            childCount: 2,
            initialPage: 1,
            viewportFraction: 0.85,
          ),
          'apps_examples|assets/onboarding/screens/paywall_carousel_ctrl.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test('PageView with an unmapped argument defers — no artifacts', () async {
      // The whole-widget defer is fatal at the production builder: an
      // unexpressible PageView form emits NO paywall artifacts rather than a
      // degraded RestagePager that drops the `physics` behaviour.
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'carousel_defer')
        class CarouselDeferPaywall extends StatelessWidget {
          const CarouselDeferPaywall();
          Widget build(BuildContext context) => PageView(
            physics: const NeverScrollableScrollPhysics(),
            children: const [SizedBox(), SizedBox()],
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/carousel_defer.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/carousel_defer.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: const {},
      );
    });

    test(
        'a vanilla RadioGroup aliases to a RestageRadioGroup node, '
        'byte-stable + round-trips with its option list', () async {
      // A dev writes a vanilla-Flutter RadioGroup of RadioListTile rows (a
      // remote surface tier/choice picker); the transpiler aliases it to the
      // declarative RestageRadioGroup catalog widget against the REAL merged
      // catalog. The .rfwtxt carries RestageRadioGroup (the source forms are
      // gone); the binary .rfw decodes to a RestageRadioGroup root carrying the
      // {value, label} option list in source order — the proof a remote radio
      // renders the same options the dev authored, none silently dropped.
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'plan_radio')
        class PlanRadioPaywall extends StatelessWidget {
          const PlanRadioPaywall();
          Widget build(BuildContext context) => RadioGroup<String>(
            groupValue: 'annual',
            child: Column(children: const [
              RadioListTile<String>(value: 'monthly', title: Text('Monthly')),
              RadioListTile<String>(value: 'annual', title: Text('Annual')),
            ]),
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/plan_radio.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/plan_radio.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/plan_radio.capability.json': anything,
          'apps_examples|assets/paywalls/plan_radio.rfwtxt': decodedMatches(
            allOf([
              contains('RestageRadioGroupString('),
              contains('items:'),
              contains('"monthly"'),
              contains('"Monthly"'),
              contains('"annual"'),
              contains('"Annual"'),
              isNot(contains('RadioGroup<')),
              isNot(contains('RadioListTile')),
            ]),
          ),
          'apps_examples|assets/paywalls/plan_radio.rfw':
              const _SingleSelectMatcher(
            rootName: 'RestageRadioGroupString',
            options: [
              ('monthly', 'Monthly'),
              ('annual', 'Annual'),
            ],
            selected: 'annual',
          ),
          'apps_examples|assets/onboarding/screens/paywall_plan_radio.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test(
        'a vanilla DropdownButton aliases to a RestageDropdown node, '
        'byte-stable + round-trips with its option list', () async {
      // A dev writes a vanilla-Flutter DropdownButton of DropdownMenuItem
      // entries; the transpiler aliases it to the declarative RestageDropdown
      // catalog widget. The .rfw decodes to a RestageDropdown root carrying the
      // {value, label} option list — the overlay/route DropdownButton owns is
      // hidden behind the compiled widget.
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'currency_dropdown')
        class CurrencyDropdownPaywall extends StatelessWidget {
          const CurrencyDropdownPaywall();
          Widget build(BuildContext context) => DropdownButton<String>(
            value: 'usd',
            items: const [
              DropdownMenuItem<String>(value: 'usd', child: Text('US Dollar')),
              DropdownMenuItem<String>(value: 'eur', child: Text('Euro')),
            ],
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/currency_dropdown.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/currency_dropdown.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/currency_dropdown.capability.json':
              anything,
          'apps_examples|assets/paywalls/currency_dropdown.rfwtxt':
              decodedMatches(
            allOf([
              contains('RestageDropdownString('),
              contains('items:'),
              contains('"usd"'),
              contains('"US Dollar"'),
              contains('"eur"'),
              contains('"Euro"'),
              isNot(contains('DropdownButton<')),
              isNot(contains('DropdownMenuItem')),
            ]),
          ),
          'apps_examples|assets/paywalls/currency_dropdown.rfw':
              const _SingleSelectMatcher(
            rootName: 'RestageDropdownString',
            options: [
              ('usd', 'US Dollar'),
              ('eur', 'Euro'),
            ],
            selected: 'usd',
          ),
          'apps_examples|'
                  'assets/onboarding/screens/paywall_currency_dropdown.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test(
        'a RadioGroup with an unparseable group (a non-carrier leaf) defers — '
        'no artifacts, never a partial group', () async {
      // The all-or-defer-loud contract at the production builder: a single
      // non-RadioListTile leaf defers the WHOLE widget, emitting NO paywall
      // artifacts rather than a RestageRadioGroup that silently drops the
      // un-extractable option. A silently-wrong remote radio is the failure we
      // must not ship.
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'radio_defer')
        class RadioDeferPaywall extends StatelessWidget {
          const RadioDeferPaywall();
          Widget build(BuildContext context) => RadioGroup<String>(
            groupValue: 'a',
            child: Column(children: const [
              RadioListTile<String>(value: 'a', title: Text('A')),
              Radio<String>(value: 'b'),
            ]),
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/radio_defer.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/radio_defer.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: const {},
      );
    });

    test(
        'a vanilla SegmentedButton aliases to a RestageSegmentedButton node '
        'against the REAL catalog, with its segments + selected list',
        () async {
      // A dev writes a vanilla-Flutter SegmentedButton (a remote surface
      // segmented selector); the transpiler aliases it to the declarative
      // RestageSegmentedButton catalog widget against the REAL merged catalog.
      // The .rfwtxt carries RestageSegmentedButtonString (the source forms are
      // gone); it carries the {value, label} segments in source order + the
      // selected value list — the proof a remote segmented button renders the
      // same segments the dev authored, none silently dropped or reordered.
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'view_segments')
        class ViewSegmentsPaywall extends StatelessWidget {
          const ViewSegmentsPaywall();
          Widget build(BuildContext context) => SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(value: 'day', label: Text('Day')),
              ButtonSegment<String>(value: 'week', label: Text('Week')),
            ],
            selected: const {'week'},
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/view_segments.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/view_segments.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/view_segments.capability.json':
              anything,
          'apps_examples|assets/paywalls/view_segments.rfwtxt': decodedMatches(
            allOf([
              contains('RestageSegmentedButtonString('),
              contains('items:'),
              contains('"day"'),
              contains('"Day"'),
              contains('"week"'),
              contains('"Week"'),
              isNot(contains('SegmentedButton<')),
              isNot(contains('ButtonSegment')),
            ]),
          ),
          'apps_examples|assets/paywalls/view_segments.rfw': anything,
          'apps_examples|assets/onboarding/screens/paywall_view_segments.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test(
        'a SegmentedButton with an icon-only segment defers — no artifacts, '
        'never a partial set', () async {
      // The all-or-defer-loud contract at the production builder: a single
      // icon-only segment (no flat string label) defers the WHOLE widget,
      // emitting NO paywall artifacts rather than a RestageSegmentedButton that
      // silently drops the un-extractable segment.
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'segments_defer')
        class SegmentsDeferPaywall extends StatelessWidget {
          const SegmentsDeferPaywall();
          Widget build(BuildContext context) => SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(value: 'a', label: Text('A')),
              ButtonSegment<String>(value: 'b', icon: Icon(Icons.ac_unit)),
            ],
            selected: const {'a'},
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/segments_defer.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/segments_defer.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: const {},
      );
    });

    test(
        'a canonical DraggableScrollableSheet aliases to a '
        'RestageDraggableSheet node, byte-stable + round-trips', () async {
      // A dev writes vanilla-Flutter DraggableScrollableSheet with the
      // canonical builder; the transpiler aliases it to the declarative
      // RestageDraggableSheet catalog widget against the REAL merged catalog.
      // The .rfwtxt carries RestageDraggableSheet (the source forms are gone);
      // the binary .rfw decodes to a RestageDraggableSheet root.
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'drag_sheet')
        class DragSheetPaywall extends StatelessWidget {
          const DragSheetPaywall();
          Widget build(BuildContext context) => DraggableScrollableSheet(
            initialChildSize: 0.4,
            builder: (context, scrollController) => SingleChildScrollView(
              controller: scrollController,
              child: const SizedBox(),
            ),
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/drag_sheet.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/drag_sheet.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/drag_sheet.capability.json': anything,
          'apps_examples|assets/paywalls/drag_sheet.rfwtxt': decodedMatches(
            allOf(
              contains('RestageDraggableSheet('),
              contains('child:'),
              contains('initialChildSize: 0.4'),
              contains('SizedBox'),
              isNot(contains('DraggableScrollableSheet(builder')),
              isNot(contains('SingleChildScrollView')),
            ),
          ),
          // The binary blob round-trips: it decodes to the single `Paywall`
          // widget (the root construct is asserted as RestageDraggableSheet via
          // the .rfwtxt above).
          'apps_examples|assets/paywalls/drag_sheet.rfw':
              const _RootWidgetMatcher('Paywall'),
          'apps_examples|assets/onboarding/screens/paywall_drag_sheet.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test(
        'a DraggableScrollableSheet with an author controller defers — no '
        'artifacts', () async {
      // The whole-widget defer is fatal at the production builder: an
      // author-supplied controller (an imperative escape hatch) emits NO
      // paywall artifacts rather than a surface that silently drops it.
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'drag_defer')
        class DragDeferPaywall extends StatelessWidget {
          const DragDeferPaywall();
          Widget build(BuildContext context) => DraggableScrollableSheet(
            controller: DraggableScrollableController(),
            builder: (context, scrollController) => SingleChildScrollView(
              controller: scrollController,
              child: const SizedBox(),
            ),
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/drag_defer.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/drag_defer.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: const {},
      );
    });

    test('Icons.X reference resolves to integer codepoint in the emitted .rfw',
        () async {
      // End-to-end: `Icon(iconCodepoint: Icons.favorite)` emits a bare integer
      // codepoint, not `"favorite"` (string). `Icons` is gated to the real
      // package:flutter namespace (no name-only path), so the fixture imports
      // the real `Icons`/`IconData` (showing only those to avoid colliding
      // with the local `Icon` catalog-widget stub).
      const source = '''
        import 'package:flutter/material.dart' show Icons, IconData;
        $kStubAnnotationsAndBases

        class Icon extends StatelessWidget {
          const Icon({this.iconCodepoint});
          final IconData? iconCodepoint;
          Widget build(BuildContext context) => Widget();
        }

        @PaywallSource(id: 'icon_canary')
        class IconCanary extends StatelessWidget {
          const IconCanary();
          Widget build(BuildContext context) =>
              Icon(iconCodepoint: Icons.favorite);
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/icon_canary.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/icon_canary.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/icon_canary.capability.json': anything,
          'apps_examples|assets/paywalls/icon_canary.rfwtxt': decodedMatches(
            allOf(
              contains('Icon('),
              matches(RegExp(r'iconCodepoint: \d+')),
              isNot(contains('"favorite"')),
            ),
          ),
          'apps_examples|assets/paywalls/icon_canary.rfw': isNotEmpty,
          'apps_examples|assets/onboarding/screens/paywall_icon_canary.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test('previously-working shapes still translate through resolved AST',
        () async {
      // Regression for the AST-substrate switch: factory ctors and
      // alignment members already had per-shape handling under
      // parsed AST. They must continue to land on the same DSL
      // fragments when the build pipeline runs against the resolved
      // AST. Exercises a single fixture covering Color literal +
      // EdgeInsets factory + Alignment member (via LinearGradient
      // begin/end) + a second Icons reference to guard against any
      // per-element caching surprise.
      const source = '''
        // The value types (Color / EdgeInsets / Alignment / LinearGradient)
        // resolve to REAL Flutter so the value-substitution gate recognises
        // them — a customer-stub look-alike would (correctly) defer. Container /
        // Icon stay catalog-widget stubs (matched by name against the catalog).
        import 'package:flutter/material.dart'
            show
                Icons,
                IconData,
                Color,
                EdgeInsets,
                Alignment,
                LinearGradient;
        $kStubAnnotationsAndBases

        class Container extends StatelessWidget {
          const Container({this.padding, this.color, this.gradient, this.child});
          final EdgeInsets? padding;
          final Color? color;
          final LinearGradient? gradient;
          final Widget? child;
          Widget build(BuildContext context) => Widget();
        }
        class Icon extends StatelessWidget {
          const Icon({this.iconCodepoint});
          final IconData? iconCodepoint;
          Widget build(BuildContext context) => Widget();
        }

        @PaywallSource(id: 'mixed_shapes')
        class MixedShapes extends StatelessWidget {
          const MixedShapes();
          Widget build(BuildContext context) => Container(
                padding: const EdgeInsets.all(12),
                color: const Color(0xFF112233),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFAA0000), Color(0xFF00AA00)],
                ),
                child: Icon(iconCodepoint: Icons.favorite),
              );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/mixed_shapes.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/mixed_shapes.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/mixed_shapes.capability.json':
              anything,
          'apps_examples|assets/paywalls/mixed_shapes.rfwtxt': decodedMatches(
            allOf(
              // EdgeInsets factory emits the array shape with double
              // literals (rfw's edge-insets decoder strict-casts the
              // values via source.v<double>).
              contains('padding: [12.0, 12.0, 12.0, 12.0]'),
              // Color literal still emits 0xAARRGGBB.
              contains('color: 0xFF112233'),
              // Alignment members still resolve to {x, y} maps inside
              // LinearGradient's begin/end.
              contains('begin: {x: -1.0, y: -1.0}'),
              contains('end: {x: 1.0, y: 1.0}'),
              // Second Icons reference resolves independently to a bare integer
              // codepoint — guards against per-element caching.
              matches(RegExp(r'iconCodepoint: \d+')),
            ),
          ),
          'apps_examples|assets/paywalls/mixed_shapes.rfw': isNotEmpty,
          'apps_examples|assets/onboarding/screens/paywall_mixed_shapes.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test('a const local in build() folds at its reference site', () async {
      // End-to-end: a `const` local before the single return is permitted by
      // the body-shape rule, and a reference to it folds to its literal value
      // (`SizedBox(width: w)` → `width: 320.0`), not a deferral.
      const source = '''
        $kStubAnnotationsAndBases

        class SizedBox extends StatelessWidget {
          const SizedBox({this.width});
          final double? width;
          Widget build(BuildContext context) => Widget();
        }

        @PaywallSource(id: 'const_local')
        class ConstLocal extends StatelessWidget {
          const ConstLocal();
          Widget build(BuildContext context) {
            const w = 320.0;
            return SizedBox(width: w);
          }
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: false,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/const_local.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/const_local.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/const_local.capability.json': anything,
          'apps_examples|assets/paywalls/const_local.rfwtxt': decodedMatches(
            allOf(
              contains('SizedBox('),
              contains('width: 320.0'),
            ),
          ),
          'apps_examples|assets/paywalls/const_local.rfw': isNotEmpty,
          'apps_examples|assets/onboarding/screens/paywall_const_local.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test('stateful @PaywallSource emits root state and handlers', () async {
      const source = '''
        $kStubAnnotationsAndBases

        abstract class StatefulWidget extends Widget {
          const StatefulWidget();
        }

        abstract class State<T extends StatefulWidget> {
          late T widget;
          Widget build(BuildContext context);
          void setState(void Function() fn) {}
        }

        class Text extends StatelessWidget {
          const Text(this.text);
          final String text;
          Widget build(BuildContext context) => Widget();
        }

        class GestureDetector extends StatelessWidget {
          const GestureDetector({this.onTap, this.child});
          final void Function()? onTap;
          final Widget? child;
          Widget build(BuildContext context) => Widget();
        }

        @PaywallSource(id: 'stateful_toggle')
        class StatefulToggle extends StatefulWidget {
          const StatefulToggle();
          _StatefulToggleState createState() => _StatefulToggleState();
        }

        class _StatefulToggleState extends State<StatefulToggle> {
          bool annual = false;

          void toggle() {
            setState(() {
              annual = !annual;
            });
          }

          Widget build(BuildContext context) => GestureDetector(
                onTap: toggle,
                child: Text(annual ? 'Annual' : 'Monthly'),
              );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: false,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/stateful_toggle.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/stateful_toggle.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/stateful_toggle.capability.json':
              anything,
          'apps_examples|assets/paywalls/stateful_toggle.rfwtxt':
              decodedMatches(
            allOf(
              contains('widget Paywall { annual: false } ='),
              contains(
                'onTap: set state.annual = switch state.annual '
                '{ true: false, false: true }',
              ),
              contains(
                'text: switch state.annual '
                '{ true: "Annual", false: "Monthly" }',
              ),
            ),
          ),
          'apps_examples|assets/paywalls/stateful_toggle.rfw':
              const _StatefulRootMatcher('Paywall', {'annual': false}),
          'apps_examples|assets/onboarding/screens/paywall_stateful_toggle.rfw':
              const _StatefulRootMatcher('OnboardingScreen', {
            'annual': false,
          }),
        },
      );
    });

    test('state string interpolation emits TextRich span state reference',
        () async {
      const source = '''
        $kStubAnnotationsAndBases

        abstract class StatefulWidget extends Widget {
          const StatefulWidget();
        }

        abstract class State<T extends StatefulWidget> {
          late T widget;
          Widget build(BuildContext context);
        }

        class Text extends StatelessWidget {
          const Text(this.text);
          final String text;
          Widget build(BuildContext context) => Widget();
        }

        @PaywallSource(id: 'state_price_string')
        class StatePriceStringPaywall extends StatefulWidget {
          const StatePriceStringPaywall();
          _StatePriceStringPaywallState createState() =>
              _StatePriceStringPaywallState();
        }

        class _StatePriceStringPaywallState
            extends State<StatePriceStringPaywall> {
          String trialLabel = '7 days free';

          Widget build(BuildContext context) =>
              Text('\${trialLabel} remaining');
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: false,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/state_price_string.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/state_price_string.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/state_price_string.capability.json':
              anything,
          'apps_examples|assets/paywalls/state_price_string.rfwtxt':
              decodedMatches(
            allOf(
              contains('widget Paywall { trialLabel: "7 days free" } ='),
              contains('TextRich('),
              contains('text: state.trialLabel'),
              contains('text: " remaining"'),
            ),
          ),
          'apps_examples|assets/paywalls/state_price_string.rfw':
              const _TextRichStateStringMatcher(),
          'apps_examples|assets/onboarding/screens/paywall_state_price_string.rfw':
              const _StatefulRootMatcher('OnboardingScreen', {
            'trialLabel': '7 days free',
          }),
        },
      );
    });

    test('unsupported stateful @PaywallSource emits no outputs', () async {
      const source = '''
        $kStubAnnotationsAndBases

        abstract class StatefulWidget extends Widget {
          const StatefulWidget();
        }

        abstract class State<T extends StatefulWidget> {
          late T widget;
          Widget build(BuildContext context);
          void setState(void Function() fn) {}
        }

        @PaywallSource(id: 'unsupported_state')
        class UnsupportedStatePaywall extends StatefulWidget {
          const UnsupportedStatePaywall();
          _UnsupportedStatePaywallState createState() =>
              _UnsupportedStatePaywallState();
        }

        class _UnsupportedStatePaywallState
            extends State<UnsupportedStatePaywall> {
          List<String> labels = const ['Monthly', 'Annual'];

          Widget build(BuildContext context) => Center();
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: false,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/unsupported_state.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/unsupported_state.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: const {},
      );
    });

    test(
        'Container(decoration: BoxDecoration(image: DecorationImage(...))) '
        'drives the full production path: field mapping -> decorationImage '
        'flat slot -> self-describing image map', () async {
      // End-to-end production-path proof for DecorationImage on Container: the
      // `BoxDecoration.image` ctor arg hoists through the `image` ->
      // `decorationImage` field-mapping curation onto the flat synthetic slot
      // against the REAL merged catalog, and the value lowers to the
      // self-describing image map (provider + fit + alignment) — never a
      // `decoration: {...}` map.
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'hero_image')
        class HeroImagePaywall extends StatelessWidget {
          const HeroImagePaywall();
          Widget build(BuildContext context) => Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: NetworkImage('https://x/hero.jpg'),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
            child: const SizedBox(width: 24.0, height: 24.0),
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/hero_image.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/hero_image.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/hero_image.rfwtxt': decodedMatches(
            allOf(
              contains('Container('),
              // The flat synthetic slot key (the field-mapping wiring), never a
              // `decoration: {...}` map.
              contains('decorationImage:'),
              isNot(contains('decoration:')),
              // The self-describing image map: recursed provider, fit, and the
              // alignment {x, y} pair.
              contains('image: {kind: "network", src: "https://x/hero.jpg"}'),
              contains('fit: "cover"'),
              contains('alignment: {x: 0.0, y: -1.0}'),
            ),
          ),
          'apps_examples|assets/paywalls/hero_image.rfw': isNotEmpty,
          'apps_examples|assets/paywalls/hero_image.capability.json': anything,
          'apps_examples|assets/onboarding/screens/paywall_hero_image.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test(
        'AnimatedContainer(decoration: BoxDecoration(image: DecorationImage)) '
        'drives the same production path on the implicit-animation widget',
        () async {
      // The `decorationImage` synthetic is shared by Container AND
      // AnimatedContainer (both consume the shared BoxDecoration synthetics);
      // this proves the field-mapping wiring on the second consumer through the
      // real catalog.
      const source = '''
        import 'package:flutter/material.dart';
        $kStubAnnotationsAndBases

        @PaywallSource(id: 'anim_hero')
        class AnimHeroPaywall extends StatelessWidget {
          const AnimHeroPaywall();
          Widget build(BuildContext context) => AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/bg.png'),
                fit: BoxFit.fill,
              ),
            ),
            child: const SizedBox(width: 24.0, height: 24.0),
          );
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: true,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/anim_hero.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/anim_hero.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|assets/paywalls/anim_hero.rfwtxt': decodedMatches(
            allOf(
              contains('AnimatedContainer('),
              contains('decorationImage:'),
              isNot(contains('decoration:')),
              contains('kind: "asset"'),
              contains('src: "assets/bg.png"'),
              contains('fit: "fill"'),
            ),
          ),
          'apps_examples|assets/paywalls/anim_hero.rfw': isNotEmpty,
          'apps_examples|assets/paywalls/anim_hero.capability.json': anything,
          'apps_examples|assets/onboarding/screens/paywall_anim_hero.rfw':
              const _RootWidgetMatcher('OnboardingScreen'),
        },
      );
    });

    test('source with no @PaywallSource silently skips', () async {
      const source = '''
        class NotAPaywall {
          const NotAPaywall();
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: false,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/paywalls/empty.dart'),
        source,
      );

      await testBuilder(
        restageCodegenBuilder(BuilderOptions.empty),
        {'apps_examples|lib/paywalls/empty.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: const {},
      );
    });
  });

  group('UserCatalogBuilder end-to-end', () {
    test('emits wire IDs in user_catalog.g.dart', () async {
      const source = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'AcmeButton',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'CTA.',
        )
        class AcmeButton {
          const AcmeButton(this.label);

          @RestageProperty(description: 'Label.', required: true)
          final String label;
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: false,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets/acme_button.dart'),
        source,
      );

      await testBuilder(
        userCatalogBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets/acme_button.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        outputs: {
          'apps_examples|lib/user_catalog.g.dart': decodedMatches(
            allOf(
              contains("wireId: WireId('w0001')"),
              contains("wireId: WireId('p0001')"),
              isNot(contains('WireId.unallocated')),
              contains("name: 'AcmeButton'"),
            ),
          ),
        },
      );
    });

    test(
        'a malformed token in a customer widget source fails the build instead '
        'of emitting a silently-recovered catalog entry', () async {
      // The walker resolves customer sources with `allowSyntaxErrors: true`.
      // An incomplete hex literal `0x` is a scanner error whose parser
      // recovery would otherwise yield a structurally-valid declaration and
      // emit a catalog entry with the bad token silently dropped. The
      // syntactic-error pass surfaces it so the build fails.
      const source = '''
        import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

        @RestageWidget(
          name: 'AcmeButton',
          library: WidgetLibrary.custom('acme.design_system'),
          category: WidgetCategory.input,
          description: 'CTA.',
        )
        class AcmeButton {
          const AcmeButton(this.label, this.elevation);

          @RestageProperty(description: 'Label.', required: true)
          final String label;

          @RestageProperty(description: 'Elevation.', required: true)
          final int elevation = 0x;
        }
      ''';

      final readerWriter = await readerWriterWithFilesystemSources(
        rootPackage: 'apps_examples',
        includeFlutter: false,
      );
      readerWriter.testing.writeString(
        AssetId('apps_examples', 'lib/widgets/acme_button.dart'),
        source,
      );

      final logs = <String>[];
      final result = await testBuilder(
        userCatalogBuilder(BuilderOptions.empty),
        {'apps_examples|lib/widgets/acme_button.dart': source},
        rootPackage: 'apps_examples',
        readerWriter: readerWriter,
        onLog: (record) => logs.add(record.message),
      );

      expect(result.succeeded, isFalse);
      expect(logs.join('\n'), contains('[malformedSourceInput]'));
    });
  });
}

/// A customer's generated catalog declaring one custom library widget at a
/// capability version — the shape `loadMergedCatalog` merges from the package
/// being built so a surface referencing the widget derives a required library.
Catalog _acmeCustomerCatalog() => Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '2026-06-19T00:00:00Z',
      libraries: {
        const WidgetLibrary.custom('acme.widgets'):
            const LibraryInfo(version: '0.0.0', capabilityVersion: 2),
      },
      widgets: [
        WidgetEntry(
          wireId: WireId('w0001'),
          name: 'AcmeBanner',
          library: const WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.layout,
          description: 'A custom banner.',
          flutterType: 'package:acme/banner.dart#AcmeBanner',
          childrenSlot: ChildrenSlot.none,
          fires: const [],
          properties: const [],
        ),
      ],
    );

/// Matcher that decodes the emitted `.rfw` blob via the shared decoder
/// and asserts the round-tripped library shape: one widget named
/// `Paywall` whose root is a `Center(child: SizedBox(width: 64, height: 64))`.
class _RoundTripMatcher extends Matcher {
  const _RoundTripMatcher();

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! List<int>) return false;
    final fmt.RemoteWidgetLibrary decoded;
    try {
      decoded = fmt.decodeLibraryBlob(Uint8List.fromList(item));
    } on fmt.ParserException catch (e) {
      matchState['decodeError'] = e;
      return false;
    }
    if (decoded.widgets.length != 1) {
      matchState['shape'] = 'expected 1 widget, got ${decoded.widgets.length}';
      return false;
    }
    final paywall = decoded.widgets.single;
    if (paywall.name != 'Paywall') {
      matchState['shape'] = "expected widget name 'Paywall', got "
          "'${paywall.name}'";
      return false;
    }
    final root = paywall.root;
    if (root is! fmt.ConstructorCall || root.name != 'Center') {
      matchState['shape'] = 'expected root to be Center, got $root';
      return false;
    }
    final child = root.arguments['child'];
    if (child is! fmt.ConstructorCall || child.name != 'SizedBox') {
      matchState['shape'] = 'expected Center.child to be SizedBox, got $child';
      return false;
    }
    if (child.arguments['width'] != 64.0 || child.arguments['height'] != 64.0) {
      matchState['shape'] = 'expected SizedBox 64x64, got '
          'width=${child.arguments['width']}, '
          'height=${child.arguments['height']}';
      return false;
    }
    return true;
  }

  @override
  Description describe(Description description) => description.add(
        'a .rfw blob that round-trips to '
        'Center(child: SizedBox(width: 64, height: 64))',
      );

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    if (matchState.containsKey('decodeError')) {
      return mismatchDescription
          .add('failed to decode blob: ')
          .addDescriptionOf(matchState['decodeError']);
    }
    if (matchState.containsKey('shape')) {
      return mismatchDescription.add(matchState['shape'] as String);
    }
    return mismatchDescription.add('did not round-trip cleanly');
  }
}

class _StatefulRootMatcher extends Matcher {
  const _StatefulRootMatcher(this.name, this.expectedState);

  final String name;
  final Map<String, Object?> expectedState;

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! List<int>) return false;
    final fmt.RemoteWidgetLibrary decoded;
    try {
      decoded = fmt.decodeLibraryBlob(Uint8List.fromList(item));
    } on fmt.ParserException catch (e) {
      matchState['decodeError'] = e;
      return false;
    }
    if (decoded.widgets.length != 1) {
      matchState['shape'] = 'expected 1 widget, got ${decoded.widgets.length}';
      return false;
    }
    final root = decoded.widgets.single;
    if (root.name != name) {
      matchState['shape'] = "expected widget name '$name', got '${root.name}'";
      return false;
    }
    final initialState = root.initialState ?? const <String, Object?>{};
    if (initialState.length != expectedState.length) {
      matchState['shape'] = 'expected state $expectedState, got '
          '$initialState';
      return false;
    }
    for (final entry in expectedState.entries) {
      if (initialState[entry.key] != entry.value) {
        matchState['shape'] = 'expected state ${entry.key}=${entry.value}, '
            'got ${initialState[entry.key]}';
        return false;
      }
    }
    return true;
  }

  @override
  Description describe(Description description) =>
      description.add("a .rfw blob with stateful root widget '$name'");

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    if (matchState.containsKey('decodeError')) {
      return mismatchDescription
          .add('failed to decode blob: ')
          .addDescriptionOf(matchState['decodeError']);
    }
    if (matchState.containsKey('shape')) {
      return mismatchDescription.add(matchState['shape'] as String);
    }
    return mismatchDescription.add('did not decode to the expected root');
  }
}

/// Asserts the emitted paywall binary decodes to a `Paywall` whose body root is
/// a `RestagePrice` carrying the config statically extracted from the original
/// `NumberFormat.currency('en_US', r'$', 2).format(9.99)` idiom — the L3 proof
/// that the #2 auto-substitution survives the encode/decode round-trip.
class _SubstitutedPriceMatcher extends Matcher {
  const _SubstitutedPriceMatcher();

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! List<int>) return false;
    final fmt.RemoteWidgetLibrary decoded;
    try {
      decoded = fmt.decodeLibraryBlob(Uint8List.fromList(item));
    } on fmt.ParserException catch (e) {
      matchState['decodeError'] = e;
      return false;
    }
    if (decoded.widgets.length != 1) {
      matchState['shape'] = 'expected 1 widget, got ${decoded.widgets.length}';
      return false;
    }
    final root = decoded.widgets.single.root;
    if (root is! fmt.ConstructorCall || root.name != 'RestagePrice') {
      matchState['shape'] = 'expected body root RestagePrice, got $root';
      return false;
    }
    final expected = <String, Object?>{
      'value': 9.99,
      'numberLocale': 'en_US',
      'symbol': r'$',
      'decimalDigits': 2,
    };
    for (final e in expected.entries) {
      if (root.arguments[e.key] != e.value) {
        matchState['shape'] = 'expected RestagePrice.${e.key} == ${e.value}, '
            'got ${root.arguments[e.key]}';
        return false;
      }
    }
    return true;
  }

  @override
  Description describe(Description description) => description.add(
        'a .rfw blob whose body root is a RestagePrice with the extracted '
        'currency config',
      );

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    if (matchState.containsKey('decodeError')) {
      return mismatchDescription
          .add('failed to decode blob: ')
          .addDescriptionOf(matchState['decodeError']);
    }
    if (matchState.containsKey('shape')) {
      return mismatchDescription.add(matchState['shape'] as String);
    }
    return mismatchDescription
        .add('did not carry the substituted RestagePrice');
  }
}

/// Asserts the decoded `.rfw` body root is a `RestagePager` carrying
/// [childCount] child pages and, when supplied, the flattened
/// [initialPage] / [viewportFraction] props — the PageView→RestagePager
/// alias→wire mapping surviving encode/decode.
class _PagerMatcher extends Matcher {
  const _PagerMatcher({
    required this.childCount,
    this.initialPage,
    this.viewportFraction,
  });

  final int childCount;
  final int? initialPage;
  final double? viewportFraction;

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! List<int>) return false;
    final fmt.RemoteWidgetLibrary decoded;
    try {
      decoded = fmt.decodeLibraryBlob(Uint8List.fromList(item));
    } on fmt.ParserException catch (e) {
      matchState['decodeError'] = e;
      return false;
    }
    if (decoded.widgets.length != 1) {
      matchState['shape'] = 'expected 1 widget, got ${decoded.widgets.length}';
      return false;
    }
    final root = decoded.widgets.single.root;
    if (root is! fmt.ConstructorCall || root.name != 'RestagePager') {
      matchState['shape'] = 'expected body root RestagePager, got $root';
      return false;
    }
    final children = root.arguments['children'];
    if (children is! List || children.length != childCount) {
      matchState['shape'] = 'expected $childCount children, got $children';
      return false;
    }
    if (initialPage != null && root.arguments['initialPage'] != initialPage) {
      matchState['shape'] = 'expected initialPage $initialPage, got '
          '${root.arguments['initialPage']}';
      return false;
    }
    if (viewportFraction != null &&
        root.arguments['viewportFraction'] != viewportFraction) {
      matchState['shape'] = 'expected viewportFraction $viewportFraction, got '
          '${root.arguments['viewportFraction']}';
      return false;
    }
    return true;
  }

  @override
  Description describe(Description description) => description.add(
        'a .rfw blob whose body root is a RestagePager with $childCount pages',
      );

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) =>
      _describeBlobMismatch(
        mismatchDescription,
        matchState,
        fallback: 'did not decode to the expected RestagePager',
      );
}

class _TextRichPriceStringMatcher extends Matcher {
  const _TextRichPriceStringMatcher();

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! List<int>) return false;
    final fmt.RemoteWidgetLibrary decoded;
    try {
      decoded = fmt.decodeLibraryBlob(Uint8List.fromList(item));
    } on fmt.ParserException catch (e) {
      matchState['decodeError'] = e;
      return false;
    }
    final root = decoded.widgets.single.root;
    if (root is! fmt.ConstructorCall || root.name != 'TextRich') {
      matchState['shape'] = 'expected body root TextRich, got $root';
      return false;
    }
    if (root.arguments['fontSize'] != 18.0 ||
        root.arguments['fontWeight'] != 'w700' ||
        root.arguments['color'] != 0xFF111111) {
      matchState['shape'] = 'expected carried Text style props, got '
          '${root.arguments}';
      return false;
    }
    final children = _textSpanChildren(root, matchState);
    if (children == null || children.length != 3) return false;
    if (_spanText(children[0]) != 'Only ') {
      matchState['shape'] = 'expected first literal span, got ${children[0]}';
      return false;
    }
    final price = _spanText(children[1]);
    if (price is! fmt.DataReference ||
        !const ListEquality<Object>().equals(
          price.parts,
          ['products', 'pro', 'localizedPrice'],
        )) {
      matchState['shape'] = 'expected product price data ref, got $price';
      return false;
    }
    if (_spanText(children[2]) != '/month') {
      matchState['shape'] = 'expected trailing literal span, got '
          '${children[2]}';
      return false;
    }
    return true;
  }

  @override
  Description describe(Description description) => description.add(
        'a .rfw blob whose body root is TextRich with price data-ref spans',
      );

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) =>
      _describeBlobMismatch(
        mismatchDescription,
        matchState,
        fallback: 'did not decode to the expected TextRich',
      );
}

class _TextRichStateStringMatcher extends Matcher {
  const _TextRichStateStringMatcher();

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! List<int>) return false;
    final fmt.RemoteWidgetLibrary decoded;
    try {
      decoded = fmt.decodeLibraryBlob(Uint8List.fromList(item));
    } on fmt.ParserException catch (e) {
      matchState['decodeError'] = e;
      return false;
    }
    final paywall = decoded.widgets.single;
    if (paywall.initialState?['trialLabel'] != '7 days free') {
      matchState['shape'] = 'expected trialLabel initial state, got '
          '${paywall.initialState}';
      return false;
    }
    final root = paywall.root;
    if (root is! fmt.ConstructorCall || root.name != 'TextRich') {
      matchState['shape'] = 'expected body root TextRich, got $root';
      return false;
    }
    final children = _textSpanChildren(root, matchState);
    if (children == null || children.length != 2) return false;
    final label = _spanText(children[0]);
    if (label is! fmt.StateReference ||
        !const ListEquality<Object>().equals(label.parts, ['trialLabel'])) {
      matchState['shape'] = 'expected trialLabel state ref, got $label';
      return false;
    }
    if (_spanText(children[1]) != ' remaining') {
      matchState['shape'] = 'expected trailing literal span, got '
          '${children[1]}';
      return false;
    }
    return true;
  }

  @override
  Description describe(Description description) => description.add(
        'a stateful .rfw blob whose TextRich span reads state.trialLabel',
      );

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) =>
      _describeBlobMismatch(
        mismatchDescription,
        matchState,
        fallback: 'did not decode to the expected TextRich',
      );
}

List<Object?>? _textSpanChildren(
  fmt.ConstructorCall root,
  Map<dynamic, dynamic> matchState,
) {
  final span = root.arguments['textSpan'];
  if (span is! Map) {
    matchState['shape'] = 'expected textSpan map, got $span';
    return null;
  }
  final children = span['children'];
  if (children is! List<Object?>) {
    matchState['shape'] = 'expected textSpan.children list, got $children';
    return null;
  }
  return children;
}

Object? _spanText(Object? span) {
  if (span is! Map) return null;
  return span['text'];
}

Description _describeBlobMismatch(
  Description mismatchDescription,
  Map<dynamic, dynamic> matchState, {
  String fallback = 'did not decode to the expected structure',
}) {
  if (matchState.containsKey('decodeError')) {
    return mismatchDescription
        .add('failed to decode blob: ')
        .addDescriptionOf(matchState['decodeError']);
  }
  if (matchState.containsKey('shape')) {
    return mismatchDescription.add(matchState['shape'] as String);
  }
  return mismatchDescription.add(fallback);
}

/// Asserts the decoded `.rfw` body root is a single-select catalog widget
/// ([rootName] — `RestageRadioGroup` / `RestageDropdown`) carrying the expected
/// `{value, label}` [options] in order and the flattened [selected] value — the
/// vanilla-idiom → compiled-widget alias→wire mapping surviving encode/decode,
/// with every authored option present (none silently dropped or reordered).
class _SingleSelectMatcher extends Matcher {
  const _SingleSelectMatcher({
    required this.rootName,
    required this.options,
    this.selected,
  });

  final String rootName;
  final List<(String value, String label)> options;
  final String? selected;

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! List<int>) return false;
    final fmt.RemoteWidgetLibrary decoded;
    try {
      decoded = fmt.decodeLibraryBlob(Uint8List.fromList(item));
    } on fmt.ParserException catch (e) {
      matchState['decodeError'] = e;
      return false;
    }
    if (decoded.widgets.length != 1) {
      matchState['shape'] = 'expected 1 widget, got ${decoded.widgets.length}';
      return false;
    }
    final root = decoded.widgets.single.root;
    if (root is! fmt.ConstructorCall || root.name != rootName) {
      matchState['shape'] = 'expected body root $rootName, got $root';
      return false;
    }
    final items = root.arguments['items'];
    if (items is! List || items.length != options.length) {
      matchState['shape'] = 'expected ${options.length} items, got $items';
      return false;
    }
    for (var i = 0; i < options.length; i++) {
      final entry = items[i];
      if (entry is! Map) {
        matchState['shape'] = 'item $i is not a map: $entry';
        return false;
      }
      if (entry['value'] != options[i].$1 || entry['label'] != options[i].$2) {
        matchState['shape'] = 'item $i expected ${options[i]}, got '
            '(${entry['value']}, ${entry['label']})';
        return false;
      }
    }
    if (selected != null && root.arguments['selected'] != selected) {
      matchState['shape'] = 'expected selected $selected, got '
          '${root.arguments['selected']}';
      return false;
    }
    return true;
  }

  @override
  Description describe(Description description) => description.add(
        'a .rfw blob whose body root is a $rootName with '
        '${options.length} options',
      );

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) =>
      _describeBlobMismatch(
        mismatchDescription,
        matchState,
        fallback: 'did not decode to the expected $rootName',
      );
}

class _RootWidgetMatcher extends Matcher {
  const _RootWidgetMatcher(this.name);

  final String name;

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! List<int>) return false;
    final fmt.RemoteWidgetLibrary decoded;
    try {
      decoded = fmt.decodeLibraryBlob(Uint8List.fromList(item));
    } on fmt.ParserException catch (e) {
      matchState['decodeError'] = e;
      return false;
    }
    if (decoded.widgets.length != 1) {
      matchState['shape'] = 'expected 1 widget, got ${decoded.widgets.length}';
      return false;
    }
    final root = decoded.widgets.single;
    if (root.name != name) {
      matchState['shape'] = "expected widget name '$name', got '${root.name}'";
      return false;
    }
    return true;
  }

  @override
  Description describe(Description description) =>
      description.add("a .rfw blob with root widget '$name'");

  @override
  Description describeMismatch(
    dynamic item,
    Description mismatchDescription,
    Map<dynamic, dynamic> matchState,
    bool verbose,
  ) {
    if (matchState.containsKey('decodeError')) {
      return mismatchDescription
          .add('failed to decode blob: ')
          .addDescriptionOf(matchState['decodeError']);
    }
    if (matchState.containsKey('shape')) {
      return mismatchDescription.add(matchState['shape'] as String);
    }
    return mismatchDescription.add('did not decode to the expected root');
  }
}
