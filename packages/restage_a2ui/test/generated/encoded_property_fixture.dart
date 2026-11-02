import 'package:flutter/material.dart';
import 'package:rfw_catalog_schema/a2ui.dart' as a2ui;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('encoded.proof'),
  capabilityVersion: 1,
)
const restageLibrary = 0;

final class EncodedDetails {
  const EncodedDetails({required this.$value});

  final String $value;
}

@a2ui.Config.writeBackValues({'onChanged': r'$value'})
@RestageWidget(
  name: 'EncodedPropertyProbe',
  library: WidgetLibrary.custom('encoded.proof'),
  category: WidgetCategory.input,
  description: 'Proves exact Dart names and valid component property names.',
)
final class EncodedPropertyProbe extends StatelessWidget {
  const EncodedPropertyProbe({
    required this.$value,
    required this.encoded_002400760061006c00750065,
    required this.value,
    required this.details,
    required this.onChanged,
    super.key,
  });

  @RestageProperty(description: 'The controlled dollar-named value.')
  final int $value;

  @RestageProperty(description: 'A source name resembling an encoded suffix.')
  final String encoded_002400760061006c00750065;

  @RestageProperty(description: 'An ordinary unencoded constructor input.')
  final String value;

  @RestageProperty(description: 'Nested business data keeps its dollar key.')
  final EncodedDetails details;

  @RestageProperty(description: 'Writes the controlled dollar-named input.')
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('dollar:${$value}'),
      Text('collision:$encoded_002400760061006c00750065'),
      Text('ordinary:$value'),
      Text('nested:${details.$value}'),
      TextButton(
        key: const ValueKey('encoded-write'),
        onPressed: () => onChanged(41),
        child: const Text('Write'),
      ),
    ],
  );
}
