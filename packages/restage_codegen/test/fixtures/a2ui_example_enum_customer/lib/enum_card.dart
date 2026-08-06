import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

@RestageLibrary(
  library: WidgetLibrary.custom('acme.enum_fixture'),
  capabilityVersion: 1,
)
const restageLibrary = 0;

enum Tone { quiet, loud }

@RestageA2uiExample(
  name: 'Zulu',
  asset: 'lib/a2ui_examples/enum_card/zulu.json',
)
@RestageA2uiExample(
  name: 'Alpha',
  asset: 'lib/a2ui_examples/enum_card/alpha.json',
)
@RestageWidget(
  name: 'EnumCard',
  library: WidgetLibrary.custom('acme.enum_fixture'),
  category: WidgetCategory.decoration,
  description: 'Synthetic enum example-builder fixture.',
)
class EnumCard {
  const EnumCard({
    required this.tone,
    required this.measurements,
    required this.labels,
  });

  @RestageProperty(description: 'The literal enum member.')
  final Tone tone;

  @RestageProperty(description: 'Numbers retaining integer and double kinds.')
  final List<num> measurements;

  @RestageProperty(description: 'Labels retaining authored array order.')
  final List<String> labels;
}
