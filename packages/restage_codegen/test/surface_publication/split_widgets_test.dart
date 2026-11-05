import 'package:restage_codegen/src/surface_publication/split_widgets.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

const _entry = WidgetEntry(
  wireId: WireId.unallocatedWidget,
  name: 'PlanCard',
  library: WidgetLibrary.custom('acme.ui'),
  category: null,
  description: 'A plan card.',
  flutterType: 'package:acme/plan_card.dart#PlanCard',
  childrenSlot: ChildrenSlot.none,
  properties: [
    PropertyEntry(
      wireId: WireId.unallocatedWidget,
      name: 'key',
      type: PropertyType.structured,
      description: 'The key.',
    ),
    PropertyEntry(
      wireId: WireId.unallocatedWidget,
      name: kAnalyticsIdPropertyName,
      type: PropertyType.string,
      description: 'The occurrence label.',
    ),
    PropertyEntry(
      wireId: WireId.unallocatedWidget,
      name: 'title',
      type: PropertyType.string,
      description: 'The title.',
    ),
  ],
  sinceVersion: 1,
);

void main() {
  group('a split widget', () {
    test('places its wrapper with its build as the builder body', () {
      final definition = splitDefinition(
        'Column(children: [Text(text: data.context.title), '
        'Text(text: data.context._h12), Text(text: "data.context.title"), '
        'PlanCard_GestureDetector_0(child: Text(text: data.context.title))])',
        _entry,
        {'title'},
      );
      // The key goes to the wrapper; the occurrence label stays on the
      // placement.
      expect(
        definition,
        startsWith('PlanCard__split(key: args.key, title: args.title, '),
      );
      expect(definition, isNot(contains(kAnalyticsIdPropertyName)));
      expect(
        definition,
        contains('restageWidget: __RestageBuilderContinuation('),
      );
      expect(
        definition,
        contains(
          '(restageWidget) => Column(children: '
          '[Text(text: args.title), Text(text: restageWidget.values._h12), '
          'Text(text: "data.context.title"), '
          'PlanCard_GestureDetector_0(child: Text(text: args.title))])',
        ),
      );
    });
  });
}
