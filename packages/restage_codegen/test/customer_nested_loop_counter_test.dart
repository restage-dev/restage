// Nested customer collection loops must not reuse a counter name.
//
// Every emitted collection loop declares `iN` and every path segment BELOW it
// references that `iN` by IDENTIFIER (`_pathLiteral` emits an index segment as
// a bare expression). So an inner loop that reuses an enclosing loop's counter
// name does not fail to compile and does not throw — it silently re-points the
// enclosing index at the inner counter, and the factory reads a DIFFERENT
// entry than the wire holds. That is a wrong VALUE on a device with no signal
// anywhere in the build: the emitted source compiles and `dart analyze` reports
// no issues on it.
//
// The map emitter and the list emitter each number their own loops, so the
// counter must be threaded as ONE shared depth across both — a map inside a
// list, or a list inside a map, is the shape a per-emitter counter gets wrong.
//
// The companion VALUE proof (the same shape reconstructed from a real
// `DataSource`, asserting the rebuilt map rather than merely that nothing
// threw) lives in `packages/restage_core/test/`.
import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/user_factory_emitter.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const String _header =
    "import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';";

/// Emits the factory library for a single `@RestageWidget` whose `rows`
/// property has type [propertyType], through the production composition:
/// the real visitor, the ONE admission point, and the real emitter.
Future<String?> _emit(String declarations, String propertyType) async {
  final result = await runWidgetVisitorOn({
    'lib/board.dart': '''
$_header
$declarations
@RestageWidget(name: 'Board', library: WidgetLibrary.custom('acme.ds'),
  category: WidgetCategory.decoration, description: 'b')
class Board {
  const Board({required this.rows});
  @RestageProperty(description: 'r') final $propertyType rows;
}
''',
  });
  final context = (
    structuredBySourceType: {
      for (final structured in result.structuredTypes)
        structured.sourceType: structured,
    },
    plansBySourceType: result.reconstructionPlans,
    mapPlans: result.mapPlans,
    recordPlans: result.recordPlans,
    slotTargets: result.slotTargets,
    nullableStructuredSlots: result.nullableStructuredSlots,
    aliases: const <String, String>{},
  );
  final admission = computeAdmission(
    widgets: result.widgets,
    structuredTypes: result.structuredTypes,
    slotTargets: result.slotTargets,
    localUnrenderable: result.localUnrenderable,
    widgetUnrenderable: result.widgetUnrenderable,
    mapPlans: result.mapPlans,
    isWholeWidgetEmittable: (widget) =>
        isFactoryEmittable(widget, customer: context),
  );
  if (admission.admitted.isEmpty) return null;
  return emitUserFactoriesDart(
    admission.admitted,
    structuredTypes: result.structuredTypes,
    slotTargets: result.slotTargets,
    nullableStructuredSlots: result.nullableStructuredSlots,
    reconstructionPlans: result.reconstructionPlans,
    mapPlans: result.mapPlans,
    recordPlans: result.recordPlans,
  );
}

/// Every loop counter DECLARED in [source], in emission order. A repeat means
/// one loop shadows an enclosing one.
List<String> _declaredCounters(String source) => RegExp(r'for \(var (\w+) =')
    .allMatches(source)
    .map((m) => m.group(1)!)
    .toList();

/// A list of structured elements, each carrying a list of structured elements.
const String _listInList = '''
class Cell {
  const Cell({required this.label});
  final String label;
}
class Line {
  const Line({required this.cells});
  final List<Cell> cells;
}
''';

/// A structured type carrying a map field — the map emitter reached from BELOW
/// a list loop.
const String _mapInStructured = '''
class Line {
  const Line({required this.cells});
  final Map<String, String> cells;
}
''';

void main() {
  Future<void> expectDistinctCounters(
    String declarations,
    String propertyType,
  ) async {
    final source = await _emit(declarations, propertyType);
    expect(
      source,
      isNotNull,
      reason: '$propertyType must be admitted for this shape to be covered',
    );
    final counters = _declaredCounters(source!);
    expect(
      counters.length,
      greaterThan(1),
      reason: 'the shape must emit nested loops, or it proves nothing',
    );
    expect(
      counters.toSet().length,
      counters.length,
      reason: 'a repeated counter shadows an enclosing loop: $counters\n'
          '$source',
    );
  }

  test('a list inside a MAP value does not reuse the map counter', () async {
    await expectDistinctCounters(_listInList, 'Map<String, Line>');
  });

  test('a map inside a LIST element does not reuse the list counter', () async {
    await expectDistinctCounters(_mapInStructured, 'List<Line>');
  });

  test('a list below a TWO-LEVEL map does not reuse either map counter',
      () async {
    // The deepest reachable form: the map layers consume TWO counters before
    // the list layer opens its own. It proves the counter is monotonic ACROSS
    // the layers rather than merely "one more than the map's key depth" — a
    // fix that derived the list counter from the key depth alone would pass
    // the single-level case and collide here.
    //
    // Only reachable once nested maps over a customer data class emit at all;
    // before that they failed the build in the emitter.
    await expectDistinctCounters(_listInList, 'Map<String, Map<String, Line>>');
  });

  test('a map inside a MAP value does not reuse the outer map counter',
      () async {
    await expectDistinctCounters(_mapInStructured, 'Map<String, Line>');
  });

  test('the plain nested-list shape keeps its distinct counters', () async {
    // The control: this path already threads its depth, so it must stay green
    // through any change to the shared counter.
    await expectDistinctCounters(_listInList, 'List<Line>');
  });
}
