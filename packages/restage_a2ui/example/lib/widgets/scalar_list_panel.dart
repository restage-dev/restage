import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Renders every A2UI scalar-list family from direct widget properties.
@RestageWidget(
  name: 'ScalarListPanel',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.layout,
  description: 'Renders string, integer, number, and boolean lists.',
)
class ScalarListPanel extends StatelessWidget {
  /// Creates a scalar-list panel.
  const ScalarListPanel({
    required this.labels,
    required this.counts,
    required this.weights,
    required this.measurements,
    required this.flags,
    this.maybeCounts,
    this.fallbackCounts = const <int>[7, 8],
    super.key,
  });

  /// Labels to display.
  @RestageProperty(description: 'String list values.')
  final List<String> labels;

  /// Integer values to display.
  @RestageProperty(description: 'Integer list values.')
  final List<int> counts;

  /// Floating-point values to display.
  @RestageProperty(description: 'Number list values.')
  final List<double> weights;

  /// Numeric values that preserve delivered integer and fractional types.
  @RestageProperty(description: 'Dart num list values.')
  final List<num> measurements;

  /// Boolean values to display.
  @RestageProperty(description: 'Boolean list values.')
  final List<bool> flags;

  /// Optional integer values used to prove nullable-list construction.
  @RestageProperty(description: 'Optional integer list values.')
  final List<int>? maybeCounts;

  /// Integer values with a declared constructor fallback.
  @RestageProperty(
    description: 'Integer list values with a fallback.',
    defaultSource: LiteralDefault(<int>[7, 8]),
  )
  final List<int>? fallbackCounts;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('scalar-list-panel'),
      children: [
        Text('labels:${labels.join(',')}'),
        Text('counts:${counts.join(',')}'),
        Text('weights:${weights.join(',')}'),
        Text('measurements:${measurements.join(',')}'),
        Text(
          'measurement-types:'
          '${measurements.map((value) => value.runtimeType).join(',')}',
        ),
        Text('flags:${flags.join(',')}'),
        Text('maybe-counts:${maybeCounts?.join(',') ?? 'none'}'),
        Text('fallback-counts:${fallbackCounts?.join(',') ?? 'none'}'),
      ],
    );
  }
}

/// A controlled integer-list component proving list path write-back.
@RestageWidget(
  name: 'IntegerListPicker',
  library: WidgetLibrary.custom('acme.widgets'),
  category: WidgetCategory.input,
  description: 'Adds values to a bound integer list.',
  fires: [WidgetEventName.onChanged],
)
class IntegerListPicker extends StatelessWidget {
  /// Creates an integer-list picker.
  const IntegerListPicker({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// The currently selected integer values.
  @RestageProperty(description: 'The selected integer values.')
  final List<int> selected;

  /// Reports the settled integer list.
  @RestageProperty(description: 'Reports the selected integer values.')
  final ValueChanged<List<int>> onSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('integer-list-add'),
      onTap: () => onSelected([...selected, selected.length + 1]),
      child: Text('selected:${selected.join(',')}'),
    );
  }
}
