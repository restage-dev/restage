import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/delivered_fonts.dart';
import 'package:restage/src/delivery/surface_sections_carrier.dart';
import 'package:restage_core/restage_core.dart' show RestageDeliveredIcon;
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/restage_runtime_test_support.dart';
import '../surface_screen/surface_screen_test_support.dart';

void main() {
  installRestageRuntimeTestSupport();
  final font = DeliveredIconFont(
    family: 'MaterialIcons',
    bytes: File(
      '../restage_shared/test/fonts/fixtures/material_icons_subset.otf',
    ).readAsBytesSync(),
  );
  final codePoint =
      (readSfntCoveredCodePoints(font.bytes).toList()..sort()).first;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
    DeliveredIconFontLoader.reset();
  });
  tearDown(() {
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
    DeliveredIconFontLoader.reset();
  });

  for (final mount in ['paywall', 'screen', 'flow', 'screenView']) {
    testWidgets('$mount renders a delivered glyph with the default empty table',
        (tester) async {
      final root = mount == 'paywall' ? 'Paywall' : 'OnboardingScreen';
      final blob = rfwSourceBlob('''
import restage.material;
widget $root = Icon(iconCodepoint: $codePoint);
''');
      final flow =
          mount == 'flow' || mount == 'screenView' ? _flow(blob) : null;
      final payload = flow == null
          ? BlobSurfacePayload(
              minClient: kSurfaceFeatureClientFloor,
              blob: blob,
              iconFonts: [font],
            )
          : FlowSurfacePayload(
              flowDocument: flow.document,
              screenBlobs: flow.screenBlobs,
              iconFonts: [font],
            );
      // Cross the serialized payload boundary and load the real font engine.
      final decoded = SurfacePayload.decode(payload.canonicalBytes);
      await tester.runAsync(() async {
        Restage.configure(analyticsEnabled: false, measurementEnabled: false);
        expect(
            await DeliveredIconFontLoader.loadAll(decoded.iconFonts), isTrue);
      });
      expect(InstalledIconTable.current.isEmpty, isTrue);

      final Widget child;
      if (mount == 'paywall') {
        child = RestagePaywall(
          id: 'new-icon',
          resolver: _PaywallResolver(attachSurfacePayload(
            ResolvedVariant(
              bytes: blob,
              paywallId: 'new-icon',
              surfaceVersion: 'delivered-v1',
            ),
            decoded,
          )),
          errorBuilder: (_, error) => Text('unavailable: ${error.message}'),
        );
      } else if (mount == 'screen') {
        final fixture = stringScreenFixture(
          blob: blob,
          capabilities: CapabilityManifest(
            builtInFloor: kSurfaceFeatureClientFloor,
            requiredLibraries: const [],
          ),
        );
        child = RestageScreen<String>(
          screen: fixture.ref,
          resolver: FixedScreenResolver(
            attachSurfacePayload(
              fixture.hosted(sections: surfaceSectionsOf(decoded)),
              decoded,
            ),
          ),
          unavailable: SurfaceScreenUnavailablePolicy.fallback(
            builder: (_, error) => Text('unavailable: ${error.reason.name}'),
          ),
        );
      } else if (mount == 'screenView') {
        final controller = RestageFlowController<void>(
          flow: _flowRef,
          resolver: _FlowResolver(attachSurfacePayload(flow!, decoded)),
          actions: null,
          onEvent: (_) {},
          onComplete: (_) {},
          onUnavailable: (_) {},
        );
        addTearDown(controller.dispose);
        unawaited(controller.load());
        child = RestageScreenView(controller: controller);
      } else {
        child = RestageFlowGraph<void>(
          flow: _flowRef,
          resolver: _FlowResolver(attachSurfacePayload(flow!, decoded)),
          unavailable: const FlowUnavailablePolicy.hide(),
        );
      }

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('unavailable:'), findsNothing);
      expect(find.byType(RestageDeliveredIcon), findsOneWidget);
      final text = tester
          .widget<RichText>(find.descendant(
            of: find.byType(RestageDeliveredIcon),
            matching: find.byType(RichText),
          ))
          .text as TextSpan;
      expect(text.text, String.fromCharCode(codePoint));
      expect(text.style!.fontFamily,
          DeliveredIconFontLoader.familyFor(font.bytes));
      expect(InstalledIconTable.current.isEmpty, isTrue);
    });
  }
}

void _decodeResult(Map<String, Object?> result) {}

const _flowRef = SurfaceFlowRef<void>(
  id: 'new-icon',
  version: 1,
  minClient: kSurfaceFeatureClientFloor,
  surface: Surface.onboarding,
  decodeResult: _decodeResult,
);

ResolvedFlow _flow(Uint8List blob) => ResolvedFlow(
      document: FlowDocument(
        flow: 'new-icon',
        version: 1,
        schemaVersion: 1,
        minClient: kSurfaceFeatureClientFloor,
        initial: 'welcome',
        actions: const {},
        legacyTerminalResultPassthrough: true,
        screenArtifacts: {
          'welcome': ScreenArtifact(
            path: 'welcome.rfw',
            version: 1,
            schemaVersion: 1,
            minClient: kSurfaceFeatureClientFloor,
            contentHash: FlowContentHash.compute(blob),
          ),
        },
        states: const {
          'welcome': ScreenFlowState(
            screen: 'welcome',
            on: {'finish': FlowTransition.goto('done')},
          ),
          'done': EndFlowState(result: {}),
        },
      ),
      screenBlobs: {'welcome': blob},
      cacheHit: false,
    );

final class _PaywallResolver implements VariantResolver {
  _PaywallResolver(this.variant);
  final ResolvedVariant variant;

  @override
  Future<ResolvedVariant> resolve(String id,
          {String? placementId, Locale? locale}) async =>
      variant;
}

final class _FlowResolver implements FlowResolver {
  _FlowResolver(this.resolved);
  final ResolvedFlow resolved;

  @override
  Future<ResolvedFlow> resolve<R>(SurfaceFlowRef<R> flow) async => resolved;
}
