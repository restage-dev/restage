import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/resolver/placement_fallback_log.dart';
import 'package:restage/src/runtime/generated_surface_need.dart';
import 'package:restage/src/runtime/library_runtime_registry.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

// A design that reads a value only the generated widget computes.
final Uint8List _computed =
    Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
  import restage.core;
  widget Paywall = Text(text: data.context._h0123456789);
''')));

final class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);
  final Map<String, Uint8List> files;
  @override
  Future<ByteData> load(String key) async {
    final bytes = files[key];
    if (bytes == null) throw FlutterError('missing $key');
    return ByteData.sublistView(bytes);
  }
}

class _Delivered implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(String id,
          {String? placementId, Locale? locale}) async =>
      ResolvedVariant(bytes: _computed, surfaceVersion: 'r3', paywallId: id);
}

void _configure(List<RestageSurfaceRef> surfaces) => Restage.configure(
    analyticsEnabled: false,
    measurementEnabled: false,
    deliveryReceiptsEnabled: false,
    surfaces: surfaces);

Future<List<String>> _shown(
    WidgetTester tester, VariantResolver resolver) async {
  final lines = <String>[];
  final print = debugPrint;
  debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
  try {
    await tester.pumpWidget(MaterialApp(
        home: RestagePaywall(
            id: 'offer',
            resolver: resolver,
            fallbackBuilder: (_) => const Text('Original'))));
    await tester.pumpAndSettle();
  } finally {
    debugPrint = print;
  }
  expect(find.text('Original'), findsOneWidget);
  return lines;
}

const _named = "[restage] `RestagePaywall(id: 'offer')` shows a design that "
    'needs values from the generated `OfferSurface`. Try showing '
    '`OfferSurface` instead.';

void main() {
  setUp(() {
    Restage.debugReset();
    resetGeneratedSurfaceLog();
    resetPlacementFallbackLog();
  });
  tearDown(Restage.debugReset);

  testWidgets(
      'a bundled design that needs the generated widget shows the fallback '
      'and names the widget', (tester) async {
    _configure(const [PaywallRef('offer', surfaceWidget: 'OfferSurface')]);
    final lines = await _shown(
        tester,
        AssetVariantResolver(
            bundle: _Bundle({'assets/paywalls/offer.rfw': _computed})));
    expect(lines, contains(_named));
  });

  testWidgets(
      'a delivered design that needs the generated widget shows the fallback '
      'and names the widget', (tester) async {
    _configure(const [PaywallRef('offer', surfaceWidget: 'OfferSurface')]);
    expect(await _shown(tester, _Delivered()), contains(_named));
  });

  testWidgets('without the generated surface list the refusal names no widget',
      (tester) async {
    _configure(const []);
    final lines = await _shown(tester, _Delivered());
    expect(
        lines,
        contains("[restage] `RestagePaywall(id: 'offer')` shows a design that "
            'needs values from its generated widget. Try showing that widget '
            'instead of `RestagePaywall`.'));
  });

  test('an explicit placement refused for computed values names the widget',
      () {
    _configure(const [PaywallRef('offer', surfaceWidget: 'OfferSurface')]);
    expect(
        fitTokenNeedsGeneratedSurface('missingHostField:_h0123456789'), isTrue);
    expect(fitTokenNeedsGeneratedSurface('missingHostField:title'), isFalse);
    expect(fitTokenNeedsGeneratedSurface('missingIsland:app.islands:Badge'),
        isTrue);
    final lines = <String>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
    try {
      debugLogPlacementNoAnswer(PlacementKeyV1.named(slug: 'offer_slot'),
          'unsupported', const PlacementNoAnswerNeedsGeneratedSurface('offer'));
    } finally {
      debugPrint = print;
    }
    expect(lines, [_named]);
  });

  group("a split widget's islands", () {
    Widget none(BuildContext context, DataSource source) =>
        const SizedBox.shrink();
    // [design] as the paywall root, beside a split `Card` whose body places
    // the island `Card_Paint_0`; [wrapper] when its wrapper is registered.
    bool needs(String design, {bool wrapper = true}) {
      LibraryRuntimeRegistry.install(RestageWidgetLibraryRegistration(
          library: const WidgetLibrary.custom('app.islands'),
          widgets: [RestageWidgetFactory(name: 'Card_Paint_0', builder: none)],
          islands: true));
      if (wrapper) {
        LibraryRuntimeRegistry.install(RestageWidgetLibraryRegistration(
            library: const WidgetLibrary.custom('app.ui'),
            widgets: [
              RestageWidgetFactory(name: 'Card__split', builder: none)
            ]));
      }
      final blob = encodeLibraryBlob(parseLibraryFile('''
        import restage.core;
        import app.islands;
        import app.ui;
        widget Card = Card__split(restageWidget: Continuation(bodies: [
            (restageWidget) => Column(children: [Card_Paint_0()])]));
        widget Paywall = $design;
      '''));
      return needsGeneratedSurface(decodeLibraryBlob(blob), blob,
          root: 'Paywall', provided: const {}, islandsHosted: false);
    }

    test('placed only in its body need no generated widget', () {
      expect(needs('Card()'), isFalse);
    });

    test('placed outside its body need the generated widget', () {
      expect(needs('Column(children: [Card(), Card_Paint_0()])'), isTrue);
    });

    test('need the generated widget without its wrapper', () {
      expect(needs('Card()', wrapper: false), isTrue);
    });

    test('a measurement wrapper the host installs is not an island', () {
      expect(needs('MeasurementPresented(child: Card())'), isFalse);
      expect(needs('MeasurementSourcePresented(child: Card())'), isFalse);
    });
  });
}
