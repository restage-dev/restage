import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:restage_a2ui/restage_a2ui.dart';
import 'package:restage_a2ui_example/lessons.dart';
import 'package:restage_a2ui_example/restage_a2ui_catalog.g.dart';
import 'package:restage_a2ui_example/restage_imports.dart';
import 'package:restage_shared/restage_shared.dart'
    show CapabilityManifest, LibraryRequirement;

import 'a2ui_proof_support.dart';

/// The full-chain proof: a golden `updateComponents` + `createSurface` payload
/// referencing the generated DOMAIN components → wrapped in a Restage sidecar →
/// passed through `RestageA2uiPreRenderCheck` (expected renderable) → rendered
/// through genui's REAL `SurfaceController`/`Surface` runtime (0.9.2). The
/// customer lesson widgets render through the real surface — compile-and-run,
/// not a static source assertion.
///
/// The golden payload ([goldenLessonComponents]): a `ComparisonPanel` root whose
/// `children` are a `SectionHeader`, a `Callout` wrapping another `SectionHeader`
/// in its single `child` slot, and a `QuizCheck` — all customer components, all
/// referenced by string id in one flat `updateComponents` list.
void main() {
  test('the generated catalog exposes both libraries\' widgets', () {
    final items = buildRestageCatalogItems();
    final names = items.map((i) => i.name).toSet();
    // The EXACT customer set — acme.widgets + acme.lessons, nothing else — so
    // a built-in leaking into the committed artifact fails this proof directly.
    expect(
      names,
      equals(<String>{
        'CtaButton',
        'IntegerListPicker',
        'ProductCard',
        'RatingPicker',
        'ScalarListPanel', // acme.widgets
        'SectionHeader', 'Callout', 'ComparisonPanel', 'QuizCheck', // lessons
      }),
    );
    // Reference the lessons barrel so its @RestageLibrary source is exercised.
    expect(restageLessonsLibrary, 0);
  });

  test('the stamp carries both custom libraries with capability versions', () {
    final stamp = readStamp();
    final libs = {
      for (final l
          in ((stamp['restageCapability'] as Map)['availableLibraries']
              as List))
        (l as Map)['namespace'] as String: l['version'],
    };
    expect(libs, containsPair('acme.widgets', 3));
    expect(libs, containsPair('acme.lessons', 1));
    final components = ((stamp['a2uiCatalog'] as Map)['components'] as Map).keys
        .toSet();
    // The EXACT customer component set, mirroring the catalog assertion above:
    // a built-in leaking into the committed stamp fails this proof directly.
    expect(
      components,
      equals(<String>{
        'CtaButton',
        'IntegerListPicker',
        'ProductCard',
        'RatingPicker',
        'ScalarListPanel',
        'SectionHeader',
        'Callout',
        'ComparisonPanel',
        'QuizCheck',
      }),
    );
  });

  testWidgets('a golden payload renders the customer lesson components through '
      'the REAL genui SurfaceController/Surface after passing the pre-render '
      'check', (tester) async {
    const surfaceId = 'lesson-surface';
    const catalogId = 'test_catalog';

    final catalog = Catalog(buildRestageCatalogItems(), catalogId: catalogId);

    // The installed capability = the committed stamp's restageCapability block.
    final installed = A2uiInstalledCapability.fromStampJson(
      readStamp()['restageCapability'] as Map<String, Object?>,
    );

    // Wrap the golden payload in a Restage sidecar carrying a satisfiable
    // capability requirement (the lessons library, at the installed version).
    final messages = sidecarMessages(
      surfaceId,
      catalogId,
      goldenLessonComponents,
    );
    final sidecar = RestageA2uiSidecar(
      capability: CapabilityManifest(
        builtInFloor: 1,
        requiredLibraries: const [
          LibraryRequirement(namespace: 'acme.lessons', minVersion: 1),
        ],
      ),
      perItemSinceVersion: const {},
      a2ui: messages,
    );

    // Pre-render check MUST accept: every referenced component exists and the
    // capability is satisfied by the installed catalog.
    final check = RestageA2uiPreRenderCheck(
      catalog: catalog,
      installed: installed,
    );
    final verdict = check.check(sidecar.toJson());
    expect(
      verdict,
      isA<A2uiRenderable>(),
      reason: 'golden payload should be renderable, got: $verdict',
    );

    // Drive genui's REAL surface runtime with the decoded messages.
    final controller = SurfaceController(catalogs: [catalog]);
    addTearDown(controller.dispose);
    for (final raw in messages) {
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

    // A CLEAN render — no component fell back to a genui error widget.
    expect(find.byType(FallbackWidget), findsNothing);
    // The customer lesson components rendered through the real surface.
    expect(find.byType(ComparisonPanel), findsOneWidget); // children slot
    expect(find.byType(Callout), findsOneWidget); // single child slot
    expect(
      find.byType(QuizCheck),
      findsOneWidget,
    ); // explicit write-back widget
    expect(
      find.byType(SectionHeader),
      findsNWidgets(2),
    ); // header + callout body
    expect(find.text('Grammar showcase'), findsOneWidget);
    expect(find.text('Present tense'), findsOneWidget);
    expect(find.textContaining('Watch the ending'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.textContaining('Is this right?'), findsOneWidget);
  });

  testWidgets('real Surface retains an IntegerListPicker literal override for '
      'the same component identity', (tester) async {
    const surfaceId = 'integer-list-surface';
    final controller = SurfaceController(catalogs: [buildRestageCatalog()]);
    addTearDown(controller.dispose);
    controller
      ..handleMessage(
        const CreateSurface(
          surfaceId: surfaceId,
          catalogId: restageA2uiCatalogId,
        ),
      )
      ..handleMessage(
        const UpdateComponents(
          surfaceId: surfaceId,
          components: [
            Component(
              id: 'root',
              type: 'IntegerListPicker',
              properties: {
                'selected': <int>[1, 2],
              },
            ),
          ],
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: Surface(surfaceContext: controller.contextFor(surfaceId)),
      ),
    );
    await tester.pump();
    expect(find.byType(IntegerListPicker), findsOneWidget);
    expect(find.text('selected:1,2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('integer-list-add')));
    await tester.pump();
    expect(find.text('selected:1,2,3'), findsOneWidget);

    controller.handleMessage(
      const UpdateComponents(
        surfaceId: surfaceId,
        components: [
          Component(
            id: 'root',
            type: 'IntegerListPicker',
            properties: {
              'selected': <int>[9],
            },
          ),
        ],
      ),
    );
    await tester.pump();
    expect(find.text('selected:1,2,3'), findsOneWidget);
    expect(find.byType(FallbackWidget), findsNothing);
  });
}
