import 'package:a2ui_core/a2ui_core.dart' show A2uiMessage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:logging/logging.dart';
import 'package:restage_a2ui/restage_a2ui.dart';
import 'package:restage_a2ui_example/generated/restage_a2ui_catalog.g.dart';
import 'package:restage_shared/restage_shared.dart'
    show CapabilityManifest, LibraryRequirement;

import 'a2ui_proof_support.dart';

/// The load-bearing fail-closed proof. A payload whose root references a
/// component the customer catalog does NOT contain must be rejected by the
/// pre-render check BEFORE genui is handed it — and the negative control proves
/// the rejection pre-empts a real failure (genui degrades a raw render of the
/// same payload to a `FallbackWidget` + a SEVERE not-found log, never the
/// ghost). The stamped-but-unverifiable path fails closed too.

/// A payload whose root references a component absent from the catalog.
List<Object?> _ghostMessages(String surfaceId, String catalogId) =>
    sidecarMessages(surfaceId, catalogId, const [
      {
        'id': 'root',
        'component': 'GhostWidget',
        'props': {'title': 'nope'},
      },
    ]);

/// A valid single-component payload (every referenced type EXISTS), so only the
/// capability axis can reject it.
List<Object?> _validMessages(String surfaceId, String catalogId) =>
    sidecarMessages(surfaceId, catalogId, const [
      {
        'id': 'root',
        'component': 'SectionHeader',
        'props': {'title': 'ok'},
      },
    ]);

/// A MIXED payload: a valid root with a valid child AND a missing-type child —
/// the shape that would SILENTLY RENDER PARTIAL (valid siblings + a fallback for
/// the ghost) without the whole-payload reject.
List<Object?> _mixedMessages(String surfaceId, String catalogId) =>
    sidecarMessages(surfaceId, catalogId, const [
      {
        'id': 'root',
        'component': 'ComparisonPanel',
        'props': {
          'heading': 'Mixed',
          'examples': ['ok', 'ghost'],
        },
      },
      {
        'id': 'ok',
        'component': 'SectionHeader',
        'props': {'title': 'I render'},
      },
      {
        'id': 'ghost',
        'component': 'GhostWidget',
        'props': {'title': 'I do not exist'},
      },
    ]);

void main() {
  late final Catalog catalog;
  late final A2uiInstalledCapability installed;

  setUpAll(() {
    catalog = Catalog(buildRestageCatalogItems(), catalogId: 'test_catalog');
    installed = A2uiInstalledCapability.fromStampJson(
      readStamp()['restageCapability'] as Map<String, Object?>,
    );
  });

  test('the pre-render check REJECTS a missing component, naming it', () {
    final sidecar = RestageA2uiSidecar(
      capability: CapabilityManifest(
        builtInFloor: 1,
        requiredLibraries: const [],
      ),
      perItemSinceVersion: const {},
      a2ui: _ghostMessages('s', 'test_catalog'),
    );
    final check = RestageA2uiPreRenderCheck(
      catalog: catalog,
      installed: installed,
    );
    final result = check.check(sidecar.toJson());
    expect(result, isA<A2uiRejected>());
    expect((result as A2uiRejected).diagnostic, contains('GhostWidget'));
  });

  testWidgets('NEGATIVE CONTROL — the same payload rendered RAW (no check) '
      'hits genui\'s not-found path (FallbackWidget + SEVERE log), never the '
      'ghost component', (tester) async {
    const surfaceId = 's';
    final logs = <LogRecord>[];
    final sub = genUiLogger.onRecord.listen(logs.add);
    addTearDown(sub.cancel);

    final controller = SurfaceController(catalogs: [catalog]);
    addTearDown(controller.dispose);
    for (final raw in _ghostMessages(surfaceId, 'test_catalog')) {
      controller.handleMessage(
        A2uiMessage.fromJson(raw! as Map<String, Object?>),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Surface(surfaceContext: controller.contextFor(surfaceId)),
      ),
    );
    await tester.pumpAndSettle();

    // genui degrades to a FallbackWidget and never renders the ghost. This is
    // the broken render the pre-render check pre-empts.
    expect(find.byType(FallbackWidget), findsWidgets);
    // A SEVERE log records the not-found component (the type is on the error).
    expect(
      logs.any(
        (r) =>
            r.level == Level.SEVERE &&
            (r.error?.toString() ?? '').contains('GhostWidget'),
      ),
      isTrue,
      reason:
          'genui should log the not-found component at SEVERE; '
          'errors seen: ${logs.map((r) => r.error).toList()}',
    );
  });

  testWidgets('a MIXED valid+missing payload is rejected WHOLE — the check '
      'pre-empts the silent PARTIAL render (valid siblings + a ghost fallback) '
      'genui would otherwise produce', (tester) async {
    const surfaceId = 's';
    // Check side: the whole payload is rejected even though 2 of 3 components
    // are valid — one missing type fails the entire payload closed.
    final sidecar = RestageA2uiSidecar(
      capability: CapabilityManifest(
        builtInFloor: 1,
        requiredLibraries: const [],
      ),
      perItemSinceVersion: const {},
      a2ui: _mixedMessages(surfaceId, 'test_catalog'),
    );
    final check = RestageA2uiPreRenderCheck(
      catalog: catalog,
      installed: installed,
    );
    final result = check.check(sidecar.toJson());
    expect(result, isA<A2uiRejected>());
    expect((result as A2uiRejected).diagnostic, contains('GhostWidget'));

    // Negative control: WITHOUT the check, the raw render is a genuine PARTIAL
    // render — the valid SectionHeader renders while the ghost degrades to a
    // FallbackWidget. That partial surface is exactly what the whole-payload
    // reject pre-empts.
    final controller = SurfaceController(catalogs: [catalog]);
    addTearDown(controller.dispose);
    for (final raw in _mixedMessages(surfaceId, 'test_catalog')) {
      controller.handleMessage(
        A2uiMessage.fromJson(raw! as Map<String, Object?>),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Surface(surfaceContext: controller.contextFor(surfaceId)),
      ),
    );
    await tester.pumpAndSettle();

    // The valid sibling rendered...
    expect(find.text('I render'), findsOneWidget);
    // ...AND the ghost degraded to a fallback — a partial render.
    expect(find.byType(FallbackWidget), findsWidgets);
  });

  test('a stamped payload with NO installed descriptor fails closed', () {
    final sidecar = RestageA2uiSidecar(
      capability: CapabilityManifest(
        builtInFloor: 1,
        requiredLibraries: const [
          LibraryRequirement(namespace: 'acme.lessons', minVersion: 1),
        ],
      ),
      perItemSinceVersion: const {},
      a2ui: _validMessages('s', 'test_catalog'),
    );
    // No `installed:` supplied → a stamped requirement cannot be verified.
    final check = RestageA2uiPreRenderCheck(catalog: catalog);
    final result = check.check(sidecar.toJson());
    expect(result, isA<A2uiRejected>());
    expect((result as A2uiRejected).diagnostic, contains('cannot be verified'));
  });
}
