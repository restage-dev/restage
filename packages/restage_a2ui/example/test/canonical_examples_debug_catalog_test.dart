import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:restage_a2ui_example/restage_a2ui_catalog.g.dart';
import 'package:restage_a2ui_example/widgets/cta_button.dart';
import 'package:restage_a2ui_example/widgets/lessons/callout.dart';
import 'package:restage_a2ui_example/widgets/lessons/comparison_panel.dart';
import 'package:restage_a2ui_example/widgets/lessons/quiz_check.dart';
import 'package:restage_a2ui_example/widgets/lessons/section_header.dart';
import 'package:restage_a2ui_example/widgets/product_card.dart';
import 'package:restage_a2ui_example/widgets/rating_picker.dart';
import 'package:restage_a2ui_example/widgets/scalar_list_panel.dart';

void main() {
  testWidgets('stock DebugCatalogView renders every canonical example', (
    tester,
  ) async {
    final catalog = buildRestageCatalog();
    expect(catalog.catalogId, restageA2uiCatalogId);
    expect(catalog.catalogId, isNotNull);
    expect(restageA2uiExampleRegistry, isNotEmpty);
    expect(
      () => restageA2uiExampleRegistry['Injected'] = const {},
      throwsUnsupportedError,
    );
    expect(
      () => restageA2uiExampleRegistry.values.first['Injected'] = '[]',
      throwsUnsupportedError,
    );

    final expectedSurfaceIds = <String>[];
    for (final item in catalog.items) {
      final examples = restageA2uiExampleRegistry[item.name];
      if (examples == null) {
        expect(item.exampleData, isEmpty);
        continue;
      }
      expect(
        item.exampleData.map((buildExample) => buildExample()),
        examples.values,
      );
      for (var index = 0; index < examples.length; index++) {
        expectedSurfaceIds.add(
          examples.length > 1 ? '${item.name}-$index' : item.name,
        );
      }
    }

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(1400, expectedSurfaceIds.length * 360);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: DebugCatalogView(catalog: catalog, itemHeight: 280)),
    );
    await tester.pump();

    for (final surfaceId in expectedSurfaceIds) {
      expect(find.text(surfaceId), findsOneWidget);
    }
    expect(find.byType(FallbackWidget), findsNothing);

    // These exact counts account for all ten authored roots plus the three
    // authored child nodes in the Callout and ComparisonPanel graphs.
    final authoredWidgetCounts = <Type, int>{
      ProductCard: 1,
      RatingPicker: 1,
      ScalarListPanel: 2,
      IntegerListPicker: 1,
      CtaButton: 2,
      Callout: 1,
      ComparisonPanel: 1,
      QuizCheck: 1,
      SectionHeader: 3,
    };
    for (final MapEntry(key: widgetType, value: count)
        in authoredWidgetCounts.entries) {
      expect(find.byType(widgetType), findsNWidgets(count));
    }
    expect(tester.takeException(), isNull);
  });
}
