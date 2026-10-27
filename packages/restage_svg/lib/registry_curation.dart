import 'package:flutter_svg/flutter_svg.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const _svgPropertyOverrides = <String, PropertyOverride>{
  'alignment': PropertyOverride(preserveConstructorDefault: true),
  'placeholderBuilder': PropertyOverride(
    type: PropertyType.widgetBuilder,
    builderContract: WidgetBuilderContract(
      parameters: [WidgetBuilderParameter.buildContext],
    ),
  ),
  'width': PropertyOverride(type: PropertyType.length),
  'height': PropertyOverride(type: PropertyType.length),
};

/// Native SVG constructors available to generated surfaces.
@RestageBuiltinLibrary(
  library: WidgetLibrary.custom('restage.svg'),
  version: '0.1.0',
  capabilityVersion: 2,
)
const List<BuiltinWidgetCuration> kCuration = [
  BuiltinWidgetCuration<SvgPicture>(
    category: WidgetCategory.decoration,
    constructorName: 'asset',
    propertyOverrides: _svgPropertyOverrides,
  ),
  BuiltinWidgetCuration<SvgPicture>(
    category: WidgetCategory.decoration,
    constructorName: 'network',
    propertyOverrides: _svgPropertyOverrides,
  ),
  BuiltinWidgetCuration<SvgPicture>(
    category: WidgetCategory.decoration,
    constructorName: 'string',
    propertyOverrides: _svgPropertyOverrides,
  ),
  BuiltinWidgetCuration<SvgPicture>(
    category: WidgetCategory.decoration,
    constructorName: 'memory',
    propertyOverrides: _svgPropertyOverrides,
  ),
  BuiltinWidgetCuration<SvgPicture>(
    category: WidgetCategory.decoration,
    propertyOverrides: _svgPropertyOverrides,
  ),
  BuiltinWidgetCuration<SvgPicture>(
    category: WidgetCategory.decoration,
    constructorName: 'file',
    propertyOverrides: _svgPropertyOverrides,
  ),
];
