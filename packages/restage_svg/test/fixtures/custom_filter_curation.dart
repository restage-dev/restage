import 'package:flutter/widgets.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

class FilterLeaf extends StatelessWidget {
  const FilterLeaf({super.key, this.filter, this.findChildIndexCallback});
  final ColorFilter? filter;
  final int? Function(Key)? findChildIndexCallback;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@RestageBuiltinLibrary(
  library: WidgetLibrary.custom('example.filters'),
  version: '0.1.0',
  capabilityVersion: 1,
)
const kCuration = [
  BuiltinWidgetCuration<FilterLeaf>(category: WidgetCategory.decoration),
];
