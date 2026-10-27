// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated from lib/registry_curation.dart by the catalog generator.
//
// Edit the curation file and re-run build_runner; do not
// edit this file directly. Runtime and authoring tools
// consume `kRegistry` from here.

library;

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Registry for the `restage.svg` library.
/// Read by codegen, authoring tools, and the runtime SDK.
final Catalog kRegistry = Catalog(
  schemaVersion: 5,
  generatedAt: '1970-01-01T00:00:00Z',
  libraries: {
    WidgetLibrary.custom('restage.svg'):
        const LibraryInfo(version: '0.1.0', capabilityVersion: 2),
  },
  widgets: [
    WidgetEntry(
      wireId: WireId('w0001'),
      name: 'SvgPictureAsset',
      library: WidgetLibrary.custom('restage.svg'),
      category: WidgetCategory.decoration,
      description: 'A widget that will parse SVG data for rendering on screen.',
      flutterType: 'package:flutter_svg/svg.dart#SvgPicture.asset',
      childrenSlot: ChildrenSlot.none,
      properties: [
        PropertyEntry(
          wireId: WireId('p0001'),
          name: 'assetName',
          type: PropertyType.string,
          description: '',
          required: true,
          positional: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0091'),
          name: 'key',
          type: PropertyType.structured,
          description: '',
          sinceVersion: 2,
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0006'))),
        ),
        PropertyEntry(
          wireId: WireId('p0002'),
          name: 'matchTextDirection',
          type: PropertyType.boolean,
          description:
              'If true, will horizontally flip the picture in [TextDirection.rtl] contexts.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0092'),
          name: 'bundle',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0007'))),
        ),
        PropertyEntry(
          wireId: WireId('p0003'),
          name: 'package',
          type: PropertyType.string,
          description: '',
          constructorNullable: true,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0004'),
          name: 'width',
          type: PropertyType.length,
          description:
              'If specified, the width to use for the SVG.  If unspecified, the SVG will take the width of its parent.',
          constructorNullable: true,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0005'),
          name: 'height',
          type: PropertyType.length,
          description:
              'If specified, the height to use for the SVG.  If unspecified, the SVG will take the height of its parent.',
          constructorNullable: true,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0006'),
          name: 'fit',
          type: PropertyType.enumValue,
          description:
              'How to inscribe the picture into the space allocated during layout. The default is [BoxFit.contain].',
          enumType: 'BoxFit',
          defaultSource: LiteralDefault('contain'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/box_fit.dart',
                  symbolName: 'BoxFit')),
        ),
        PropertyEntry(
          wireId: WireId('p0007'),
          name: 'alignment',
          type: PropertyType.alignment,
          description: 'How to align the picture within its parent widget.',
          defaultSource: LiteralDefault('center'),
          constructorDefault: DartConstReference(
              libraryUri: 'package:flutter/src/painting/alignment.dart',
              owner: 'Alignment',
              member: 'center'),
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0008'),
          name: 'allowDrawingOutsideViewBox',
          type: PropertyType.boolean,
          description:
              'If true, will allow the SVG to be drawn outside of the clip boundary of its viewBox.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0086'),
          name: 'placeholderBuilder',
          type: PropertyType.widgetBuilder,
          description:
              'The placeholder to use while fetching, decoding, and parsing the SVG data.',
          builderContract: WidgetBuilderContract(
            parameters: [WidgetBuilderParameter.buildContext],
            nullableResult: false,
          ),
          constructorNullable: true,
          valueShape: ScalarShape(propertyType: PropertyType.widgetBuilder),
        ),
        PropertyEntry(
          wireId: WireId('p0009'),
          name: 'semanticsLabel',
          type: PropertyType.string,
          description: 'The [Semantics.label] for this picture.',
          constructorNullable: true,
          category: PropertyCategory.accessibility,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0010'),
          name: 'excludeFromSemantics',
          type: PropertyType.boolean,
          description: 'Whether to exclude this picture from semantics.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0011'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description:
              'The content will be clipped (or not) according to this option.',
          enumType: 'Clip',
          defaultSource: LiteralDefault('hardEdge'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0093'),
          name: 'errorBuilder',
          type: PropertyType.structured,
          description:
              'Widget displayed while the target image failed loading.',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0008'))),
        ),
        PropertyEntry(
          wireId: WireId('p0094'),
          name: 'imageBuilder',
          type: PropertyType.structured,
          description:
              'A builder that wraps the successfully loaded SVG widget.',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0009'))),
        ),
        PropertyEntry(
          wireId: WireId('p0012'),
          name: 'theme',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0001'))),
        ),
        PropertyEntry(
          wireId: WireId('p0095'),
          name: 'colorMapper',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0010'))),
        ),
        PropertyEntry(
          wireId: WireId('p0013'),
          name: 'colorFilter',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0002'))),
        ),
        PropertyEntry(
          wireId: WireId('p0014'),
          name: 'color',
          type: PropertyType.color,
          description: '',
          constructorNullable: true,
          category: PropertyCategory.style,
          deprecated: DeprecationInfo(
              source:
                  SourceDeprecationInfo(message: 'Use colorFilter instead.')),
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0015'),
          name: 'colorBlendMode',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'BlendMode',
          defaultSource: LiteralDefault('srcIn'),
          deprecated: DeprecationInfo(
              source:
                  SourceDeprecationInfo(message: 'Use colorFilter instead.')),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'BlendMode')),
        ),
        PropertyEntry(
          wireId: WireId('p0016'),
          name: 'cacheColorFilter',
          type: PropertyType.boolean,
          description: '',
          defaultSource: LiteralDefault(false),
          deprecated: DeprecationInfo(
              source: SourceDeprecationInfo(
                  message: 'This no longer does anything.')),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0017'),
          name: 'renderingStrategy',
          type: PropertyType.enumValue,
          description:
              'Widget rendering strategy used to balance flexibility and performance.',
          enumType: 'RenderingStrategy',
          defaultSource: LiteralDefault('picture'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri:
                      'package:vector_graphics/src/vector_graphics.dart',
                  symbolName: 'RenderingStrategy')),
        ),
        PropertyEntry(
          wireId: WireId('p0018'),
          name: 'analyticsId',
          type: PropertyType.string,
          description: 'Optional identifier for this widget occurrence.',
          synthetic: 'analyticsId',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0002'),
      name: 'SvgPictureNetwork',
      library: WidgetLibrary.custom('restage.svg'),
      category: WidgetCategory.decoration,
      description: 'A widget that will parse SVG data for rendering on screen.',
      flutterType: 'package:flutter_svg/svg.dart#SvgPicture.network',
      childrenSlot: ChildrenSlot.none,
      properties: [
        PropertyEntry(
          wireId: WireId('p0019'),
          name: 'url',
          type: PropertyType.string,
          description: '',
          required: true,
          positional: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0096'),
          name: 'key',
          type: PropertyType.structured,
          description: '',
          sinceVersion: 2,
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0006'))),
        ),
        PropertyEntry(
          wireId: WireId('p0020'),
          name: 'headers',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0003'))),
        ),
        PropertyEntry(
          wireId: WireId('p0021'),
          name: 'width',
          type: PropertyType.length,
          description:
              'If specified, the width to use for the SVG.  If unspecified, the SVG will take the width of its parent.',
          constructorNullable: true,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0022'),
          name: 'height',
          type: PropertyType.length,
          description:
              'If specified, the height to use for the SVG.  If unspecified, the SVG will take the height of its parent.',
          constructorNullable: true,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0023'),
          name: 'fit',
          type: PropertyType.enumValue,
          description:
              'How to inscribe the picture into the space allocated during layout. The default is [BoxFit.contain].',
          enumType: 'BoxFit',
          defaultSource: LiteralDefault('contain'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/box_fit.dart',
                  symbolName: 'BoxFit')),
        ),
        PropertyEntry(
          wireId: WireId('p0024'),
          name: 'alignment',
          type: PropertyType.alignment,
          description: 'How to align the picture within its parent widget.',
          defaultSource: LiteralDefault('center'),
          constructorDefault: DartConstReference(
              libraryUri: 'package:flutter/src/painting/alignment.dart',
              owner: 'Alignment',
              member: 'center'),
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0025'),
          name: 'matchTextDirection',
          type: PropertyType.boolean,
          description:
              'If true, will horizontally flip the picture in [TextDirection.rtl] contexts.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0026'),
          name: 'allowDrawingOutsideViewBox',
          type: PropertyType.boolean,
          description:
              'If true, will allow the SVG to be drawn outside of the clip boundary of its viewBox.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0087'),
          name: 'placeholderBuilder',
          type: PropertyType.widgetBuilder,
          description:
              'The placeholder to use while fetching, decoding, and parsing the SVG data.',
          builderContract: WidgetBuilderContract(
            parameters: [WidgetBuilderParameter.buildContext],
            nullableResult: false,
          ),
          constructorNullable: true,
          valueShape: ScalarShape(propertyType: PropertyType.widgetBuilder),
        ),
        PropertyEntry(
          wireId: WireId('p0027'),
          name: 'colorFilter',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0002'))),
        ),
        PropertyEntry(
          wireId: WireId('p0028'),
          name: 'color',
          type: PropertyType.color,
          description: '',
          constructorNullable: true,
          category: PropertyCategory.style,
          deprecated: DeprecationInfo(
              source:
                  SourceDeprecationInfo(message: 'Use colorFilter instead.')),
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0029'),
          name: 'colorBlendMode',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'BlendMode',
          defaultSource: LiteralDefault('srcIn'),
          deprecated: DeprecationInfo(
              source:
                  SourceDeprecationInfo(message: 'Use colorFilter instead.')),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'BlendMode')),
        ),
        PropertyEntry(
          wireId: WireId('p0030'),
          name: 'semanticsLabel',
          type: PropertyType.string,
          description: 'The [Semantics.label] for this picture.',
          constructorNullable: true,
          category: PropertyCategory.accessibility,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0031'),
          name: 'excludeFromSemantics',
          type: PropertyType.boolean,
          description: 'Whether to exclude this picture from semantics.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0032'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description:
              'The content will be clipped (or not) according to this option.',
          enumType: 'Clip',
          defaultSource: LiteralDefault('hardEdge'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0097'),
          name: 'errorBuilder',
          type: PropertyType.structured,
          description:
              'Widget displayed while the target image failed loading.',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0008'))),
        ),
        PropertyEntry(
          wireId: WireId('p0098'),
          name: 'imageBuilder',
          type: PropertyType.structured,
          description:
              'A builder that wraps the successfully loaded SVG widget.',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0009'))),
        ),
        PropertyEntry(
          wireId: WireId('p0033'),
          name: 'cacheColorFilter',
          type: PropertyType.boolean,
          description: '',
          defaultSource: LiteralDefault(false),
          deprecated: DeprecationInfo(
              source: SourceDeprecationInfo(
                  message: 'This no longer does anything.')),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0034'),
          name: 'theme',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0001'))),
        ),
        PropertyEntry(
          wireId: WireId('p0099'),
          name: 'colorMapper',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0010'))),
        ),
        PropertyEntry(
          wireId: WireId('p0100'),
          name: 'httpClient',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0011'))),
        ),
        PropertyEntry(
          wireId: WireId('p0035'),
          name: 'renderingStrategy',
          type: PropertyType.enumValue,
          description:
              'Widget rendering strategy used to balance flexibility and performance.',
          enumType: 'RenderingStrategy',
          defaultSource: LiteralDefault('picture'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri:
                      'package:vector_graphics/src/vector_graphics.dart',
                  symbolName: 'RenderingStrategy')),
        ),
        PropertyEntry(
          wireId: WireId('p0036'),
          name: 'analyticsId',
          type: PropertyType.string,
          description: 'Optional identifier for this widget occurrence.',
          synthetic: 'analyticsId',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0003'),
      name: 'SvgPictureString',
      library: WidgetLibrary.custom('restage.svg'),
      category: WidgetCategory.decoration,
      description: 'A widget that will parse SVG data for rendering on screen.',
      flutterType: 'package:flutter_svg/svg.dart#SvgPicture.string',
      childrenSlot: ChildrenSlot.none,
      properties: [
        PropertyEntry(
          wireId: WireId('p0037'),
          name: 'string',
          type: PropertyType.string,
          description: '',
          required: true,
          positional: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0101'),
          name: 'key',
          type: PropertyType.structured,
          description: '',
          sinceVersion: 2,
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0006'))),
        ),
        PropertyEntry(
          wireId: WireId('p0038'),
          name: 'width',
          type: PropertyType.length,
          description:
              'If specified, the width to use for the SVG.  If unspecified, the SVG will take the width of its parent.',
          constructorNullable: true,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0039'),
          name: 'height',
          type: PropertyType.length,
          description:
              'If specified, the height to use for the SVG.  If unspecified, the SVG will take the height of its parent.',
          constructorNullable: true,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0040'),
          name: 'fit',
          type: PropertyType.enumValue,
          description:
              'How to inscribe the picture into the space allocated during layout. The default is [BoxFit.contain].',
          enumType: 'BoxFit',
          defaultSource: LiteralDefault('contain'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/box_fit.dart',
                  symbolName: 'BoxFit')),
        ),
        PropertyEntry(
          wireId: WireId('p0041'),
          name: 'alignment',
          type: PropertyType.alignment,
          description: 'How to align the picture within its parent widget.',
          defaultSource: LiteralDefault('center'),
          constructorDefault: DartConstReference(
              libraryUri: 'package:flutter/src/painting/alignment.dart',
              owner: 'Alignment',
              member: 'center'),
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0042'),
          name: 'matchTextDirection',
          type: PropertyType.boolean,
          description:
              'If true, will horizontally flip the picture in [TextDirection.rtl] contexts.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0043'),
          name: 'allowDrawingOutsideViewBox',
          type: PropertyType.boolean,
          description:
              'If true, will allow the SVG to be drawn outside of the clip boundary of its viewBox.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0088'),
          name: 'placeholderBuilder',
          type: PropertyType.widgetBuilder,
          description:
              'The placeholder to use while fetching, decoding, and parsing the SVG data.',
          builderContract: WidgetBuilderContract(
            parameters: [WidgetBuilderParameter.buildContext],
            nullableResult: false,
          ),
          constructorNullable: true,
          valueShape: ScalarShape(propertyType: PropertyType.widgetBuilder),
        ),
        PropertyEntry(
          wireId: WireId('p0044'),
          name: 'colorFilter',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0002'))),
        ),
        PropertyEntry(
          wireId: WireId('p0045'),
          name: 'color',
          type: PropertyType.color,
          description: '',
          constructorNullable: true,
          category: PropertyCategory.style,
          deprecated: DeprecationInfo(
              source:
                  SourceDeprecationInfo(message: 'Use colorFilter instead.')),
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0046'),
          name: 'colorBlendMode',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'BlendMode',
          defaultSource: LiteralDefault('srcIn'),
          deprecated: DeprecationInfo(
              source:
                  SourceDeprecationInfo(message: 'Use colorFilter instead.')),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'BlendMode')),
        ),
        PropertyEntry(
          wireId: WireId('p0047'),
          name: 'semanticsLabel',
          type: PropertyType.string,
          description: 'The [Semantics.label] for this picture.',
          constructorNullable: true,
          category: PropertyCategory.accessibility,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0048'),
          name: 'excludeFromSemantics',
          type: PropertyType.boolean,
          description: 'Whether to exclude this picture from semantics.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0049'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description:
              'The content will be clipped (or not) according to this option.',
          enumType: 'Clip',
          defaultSource: LiteralDefault('hardEdge'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0102'),
          name: 'errorBuilder',
          type: PropertyType.structured,
          description:
              'Widget displayed while the target image failed loading.',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0008'))),
        ),
        PropertyEntry(
          wireId: WireId('p0103'),
          name: 'imageBuilder',
          type: PropertyType.structured,
          description:
              'A builder that wraps the successfully loaded SVG widget.',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0009'))),
        ),
        PropertyEntry(
          wireId: WireId('p0050'),
          name: 'theme',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0001'))),
        ),
        PropertyEntry(
          wireId: WireId('p0104'),
          name: 'colorMapper',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0010'))),
        ),
        PropertyEntry(
          wireId: WireId('p0051'),
          name: 'cacheColorFilter',
          type: PropertyType.boolean,
          description: '',
          defaultSource: LiteralDefault(false),
          deprecated: DeprecationInfo(
              source: SourceDeprecationInfo(
                  message: 'This no longer does anything.')),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0052'),
          name: 'renderingStrategy',
          type: PropertyType.enumValue,
          description:
              'Widget rendering strategy used to balance flexibility and performance.',
          enumType: 'RenderingStrategy',
          defaultSource: LiteralDefault('picture'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri:
                      'package:vector_graphics/src/vector_graphics.dart',
                  symbolName: 'RenderingStrategy')),
        ),
        PropertyEntry(
          wireId: WireId('p0053'),
          name: 'analyticsId',
          type: PropertyType.string,
          description: 'Optional identifier for this widget occurrence.',
          synthetic: 'analyticsId',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0004'),
      name: 'SvgPictureMemory',
      library: WidgetLibrary.custom('restage.svg'),
      category: WidgetCategory.decoration,
      description: 'A widget that will parse SVG data for rendering on screen.',
      flutterType: 'package:flutter_svg/svg.dart#SvgPicture.memory',
      childrenSlot: ChildrenSlot.none,
      properties: [
        PropertyEntry(
          wireId: WireId('p0054'),
          name: 'bytes',
          type: PropertyType.structured,
          description: '',
          required: true,
          positional: true,
          priority: PropertyPriority.primary,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0004'))),
        ),
        PropertyEntry(
          wireId: WireId('p0105'),
          name: 'key',
          type: PropertyType.structured,
          description: '',
          sinceVersion: 2,
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0006'))),
        ),
        PropertyEntry(
          wireId: WireId('p0055'),
          name: 'width',
          type: PropertyType.length,
          description:
              'If specified, the width to use for the SVG.  If unspecified, the SVG will take the width of its parent.',
          constructorNullable: true,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0056'),
          name: 'height',
          type: PropertyType.length,
          description:
              'If specified, the height to use for the SVG.  If unspecified, the SVG will take the height of its parent.',
          constructorNullable: true,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0057'),
          name: 'fit',
          type: PropertyType.enumValue,
          description:
              'How to inscribe the picture into the space allocated during layout. The default is [BoxFit.contain].',
          enumType: 'BoxFit',
          defaultSource: LiteralDefault('contain'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/box_fit.dart',
                  symbolName: 'BoxFit')),
        ),
        PropertyEntry(
          wireId: WireId('p0058'),
          name: 'alignment',
          type: PropertyType.alignment,
          description: 'How to align the picture within its parent widget.',
          defaultSource: LiteralDefault('center'),
          constructorDefault: DartConstReference(
              libraryUri: 'package:flutter/src/painting/alignment.dart',
              owner: 'Alignment',
              member: 'center'),
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0059'),
          name: 'matchTextDirection',
          type: PropertyType.boolean,
          description:
              'If true, will horizontally flip the picture in [TextDirection.rtl] contexts.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0060'),
          name: 'allowDrawingOutsideViewBox',
          type: PropertyType.boolean,
          description:
              'If true, will allow the SVG to be drawn outside of the clip boundary of its viewBox.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0089'),
          name: 'placeholderBuilder',
          type: PropertyType.widgetBuilder,
          description:
              'The placeholder to use while fetching, decoding, and parsing the SVG data.',
          builderContract: WidgetBuilderContract(
            parameters: [WidgetBuilderParameter.buildContext],
            nullableResult: false,
          ),
          constructorNullable: true,
          valueShape: ScalarShape(propertyType: PropertyType.widgetBuilder),
        ),
        PropertyEntry(
          wireId: WireId('p0061'),
          name: 'colorFilter',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0002'))),
        ),
        PropertyEntry(
          wireId: WireId('p0062'),
          name: 'color',
          type: PropertyType.color,
          description: '',
          constructorNullable: true,
          category: PropertyCategory.style,
          deprecated: DeprecationInfo(
              source:
                  SourceDeprecationInfo(message: 'Use colorFilter instead.')),
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0063'),
          name: 'colorBlendMode',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'BlendMode',
          defaultSource: LiteralDefault('srcIn'),
          deprecated: DeprecationInfo(
              source:
                  SourceDeprecationInfo(message: 'Use colorFilter instead.')),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'BlendMode')),
        ),
        PropertyEntry(
          wireId: WireId('p0064'),
          name: 'semanticsLabel',
          type: PropertyType.string,
          description: 'The [Semantics.label] for this picture.',
          constructorNullable: true,
          category: PropertyCategory.accessibility,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0065'),
          name: 'excludeFromSemantics',
          type: PropertyType.boolean,
          description: 'Whether to exclude this picture from semantics.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0066'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description:
              'The content will be clipped (or not) according to this option.',
          enumType: 'Clip',
          defaultSource: LiteralDefault('hardEdge'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0106'),
          name: 'errorBuilder',
          type: PropertyType.structured,
          description:
              'Widget displayed while the target image failed loading.',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0008'))),
        ),
        PropertyEntry(
          wireId: WireId('p0107'),
          name: 'imageBuilder',
          type: PropertyType.structured,
          description:
              'A builder that wraps the successfully loaded SVG widget.',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0009'))),
        ),
        PropertyEntry(
          wireId: WireId('p0067'),
          name: 'theme',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0001'))),
        ),
        PropertyEntry(
          wireId: WireId('p0108'),
          name: 'colorMapper',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0010'))),
        ),
        PropertyEntry(
          wireId: WireId('p0068'),
          name: 'cacheColorFilter',
          type: PropertyType.boolean,
          description: '',
          defaultSource: LiteralDefault(false),
          deprecated: DeprecationInfo(
              source: SourceDeprecationInfo(
                  message: 'This no longer does anything.')),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0069'),
          name: 'renderingStrategy',
          type: PropertyType.enumValue,
          description:
              'Widget rendering strategy used to balance flexibility and performance.',
          enumType: 'RenderingStrategy',
          defaultSource: LiteralDefault('picture'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri:
                      'package:vector_graphics/src/vector_graphics.dart',
                  symbolName: 'RenderingStrategy')),
        ),
        PropertyEntry(
          wireId: WireId('p0070'),
          name: 'analyticsId',
          type: PropertyType.string,
          description: 'Optional identifier for this widget occurrence.',
          synthetic: 'analyticsId',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0005'),
      name: 'SvgPicture',
      library: WidgetLibrary.custom('restage.svg'),
      category: WidgetCategory.decoration,
      description: 'A widget that will parse SVG data for rendering on screen.',
      flutterType: 'package:flutter_svg/svg.dart#SvgPicture',
      childrenSlot: ChildrenSlot.none,
      properties: [
        PropertyEntry(
          wireId: WireId('p0071'),
          name: 'bytesLoader',
          type: PropertyType.structured,
          description: 'The [BytesLoader] used to resolve the SVG.',
          required: true,
          positional: true,
          priority: PropertyPriority.primary,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0005'))),
        ),
        PropertyEntry(
          wireId: WireId('p0109'),
          name: 'key',
          type: PropertyType.structured,
          description: '',
          sinceVersion: 2,
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0006'))),
        ),
        PropertyEntry(
          wireId: WireId('p0072'),
          name: 'width',
          type: PropertyType.length,
          description:
              'If specified, the width to use for the SVG.  If unspecified, the SVG will take the width of its parent.',
          constructorNullable: true,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0073'),
          name: 'height',
          type: PropertyType.length,
          description:
              'If specified, the height to use for the SVG.  If unspecified, the SVG will take the height of its parent.',
          constructorNullable: true,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0074'),
          name: 'fit',
          type: PropertyType.enumValue,
          description:
              'How to inscribe the picture into the space allocated during layout. The default is [BoxFit.contain].',
          enumType: 'BoxFit',
          defaultSource: LiteralDefault('contain'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/box_fit.dart',
                  symbolName: 'BoxFit')),
        ),
        PropertyEntry(
          wireId: WireId('p0075'),
          name: 'alignment',
          type: PropertyType.alignment,
          description: 'How to align the picture within its parent widget.',
          defaultSource: LiteralDefault('center'),
          constructorDefault: DartConstReference(
              libraryUri: 'package:flutter/src/painting/alignment.dart',
              owner: 'Alignment',
              member: 'center'),
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0076'),
          name: 'matchTextDirection',
          type: PropertyType.boolean,
          description:
              'If true, will horizontally flip the picture in [TextDirection.rtl] contexts.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0077'),
          name: 'allowDrawingOutsideViewBox',
          type: PropertyType.boolean,
          description:
              'If true, will allow the SVG to be drawn outside of the clip boundary of its viewBox.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0090'),
          name: 'placeholderBuilder',
          type: PropertyType.widgetBuilder,
          description:
              'The placeholder to use while fetching, decoding, and parsing the SVG data.',
          builderContract: WidgetBuilderContract(
            parameters: [WidgetBuilderParameter.buildContext],
            nullableResult: false,
          ),
          constructorNullable: true,
          valueShape: ScalarShape(propertyType: PropertyType.widgetBuilder),
        ),
        PropertyEntry(
          wireId: WireId('p0078'),
          name: 'colorFilter',
          type: PropertyType.structured,
          description: 'The color filter, if any, to apply to this widget.',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0002'))),
        ),
        PropertyEntry(
          wireId: WireId('p0079'),
          name: 'semanticsLabel',
          type: PropertyType.string,
          description: 'The [Semantics.label] for this picture.',
          constructorNullable: true,
          category: PropertyCategory.accessibility,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0080'),
          name: 'excludeFromSemantics',
          type: PropertyType.boolean,
          description: 'Whether to exclude this picture from semantics.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0081'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description:
              'The content will be clipped (or not) according to this option.',
          enumType: 'Clip',
          defaultSource: LiteralDefault('hardEdge'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0110'),
          name: 'errorBuilder',
          type: PropertyType.structured,
          description:
              'Widget displayed while the target image failed loading.',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0008'))),
        ),
        PropertyEntry(
          wireId: WireId('p0111'),
          name: 'imageBuilder',
          type: PropertyType.structured,
          description:
              'A builder that wraps the successfully loaded SVG widget.',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0009'))),
        ),
        PropertyEntry(
          wireId: WireId('p0082'),
          name: 'theme',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          deprecated: DeprecationInfo(
              source: SourceDeprecationInfo(
                  message:
                      'No code should use this parameter. It never was implemented properly. The SVG theme must be set on the bytesLoader.')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0001'))),
        ),
        PropertyEntry(
          wireId: WireId('p0083'),
          name: 'cacheColorFilter',
          type: PropertyType.boolean,
          description: '',
          defaultSource: LiteralDefault(false),
          deprecated: DeprecationInfo(
              source: SourceDeprecationInfo(
                  message: 'This no longer does anything.')),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0084'),
          name: 'renderingStrategy',
          type: PropertyType.enumValue,
          description:
              'Widget rendering strategy used to balance flexibility and performance.',
          enumType: 'RenderingStrategy',
          defaultSource: LiteralDefault('picture'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri:
                      'package:vector_graphics/src/vector_graphics.dart',
                  symbolName: 'RenderingStrategy')),
        ),
        PropertyEntry(
          wireId: WireId('p0085'),
          name: 'analyticsId',
          type: PropertyType.string,
          description: 'Optional identifier for this widget occurrence.',
          synthetic: 'analyticsId',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0006'),
      name: 'SvgPictureFile',
      library: WidgetLibrary.custom('restage.svg'),
      category: WidgetCategory.decoration,
      description: 'A widget that will parse SVG data for rendering on screen.',
      flutterType: 'package:flutter_svg/svg.dart#SvgPicture.file',
      childrenSlot: ChildrenSlot.none,
      properties: [
        PropertyEntry(
          wireId: WireId('p0112'),
          name: 'file',
          type: PropertyType.structured,
          description: '',
          required: true,
          positional: true,
          priority: PropertyPriority.primary,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0012'))),
        ),
        PropertyEntry(
          wireId: WireId('p0113'),
          name: 'key',
          type: PropertyType.structured,
          description: '',
          sinceVersion: 2,
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0006'))),
        ),
        PropertyEntry(
          wireId: WireId('p0114'),
          name: 'width',
          type: PropertyType.length,
          description:
              'If specified, the width to use for the SVG.  If unspecified, the SVG will take the width of its parent.',
          constructorNullable: true,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0115'),
          name: 'height',
          type: PropertyType.length,
          description:
              'If specified, the height to use for the SVG.  If unspecified, the SVG will take the height of its parent.',
          constructorNullable: true,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0116'),
          name: 'fit',
          type: PropertyType.enumValue,
          description:
              'How to inscribe the picture into the space allocated during layout. The default is [BoxFit.contain].',
          enumType: 'BoxFit',
          defaultSource: LiteralDefault('contain'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/box_fit.dart',
                  symbolName: 'BoxFit')),
        ),
        PropertyEntry(
          wireId: WireId('p0117'),
          name: 'alignment',
          type: PropertyType.alignment,
          description: 'How to align the picture within its parent widget.',
          defaultSource: LiteralDefault('center'),
          constructorDefault: DartConstReference(
              libraryUri: 'package:flutter/src/painting/alignment.dart',
              owner: 'Alignment',
              member: 'center'),
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0118'),
          name: 'matchTextDirection',
          type: PropertyType.boolean,
          description:
              'If true, will horizontally flip the picture in [TextDirection.rtl] contexts.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0119'),
          name: 'allowDrawingOutsideViewBox',
          type: PropertyType.boolean,
          description:
              'If true, will allow the SVG to be drawn outside of the clip boundary of its viewBox.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0120'),
          name: 'placeholderBuilder',
          type: PropertyType.widgetBuilder,
          description:
              'The placeholder to use while fetching, decoding, and parsing the SVG data.',
          builderContract: WidgetBuilderContract(
            parameters: [WidgetBuilderParameter.buildContext],
            nullableResult: false,
          ),
          constructorNullable: true,
          valueShape: ScalarShape(propertyType: PropertyType.widgetBuilder),
        ),
        PropertyEntry(
          wireId: WireId('p0121'),
          name: 'colorFilter',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0002'))),
        ),
        PropertyEntry(
          wireId: WireId('p0122'),
          name: 'color',
          type: PropertyType.color,
          description: '',
          constructorNullable: true,
          category: PropertyCategory.style,
          deprecated: DeprecationInfo(
              source:
                  SourceDeprecationInfo(message: 'Use colorFilter instead.')),
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0123'),
          name: 'colorBlendMode',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'BlendMode',
          defaultSource: LiteralDefault('srcIn'),
          deprecated: DeprecationInfo(
              source:
                  SourceDeprecationInfo(message: 'Use colorFilter instead.')),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'BlendMode')),
        ),
        PropertyEntry(
          wireId: WireId('p0124'),
          name: 'semanticsLabel',
          type: PropertyType.string,
          description: 'The [Semantics.label] for this picture.',
          constructorNullable: true,
          category: PropertyCategory.accessibility,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0125'),
          name: 'excludeFromSemantics',
          type: PropertyType.boolean,
          description: 'Whether to exclude this picture from semantics.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0126'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description:
              'The content will be clipped (or not) according to this option.',
          enumType: 'Clip',
          defaultSource: LiteralDefault('hardEdge'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0127'),
          name: 'errorBuilder',
          type: PropertyType.structured,
          description:
              'Widget displayed while the target image failed loading.',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0008'))),
        ),
        PropertyEntry(
          wireId: WireId('p0128'),
          name: 'imageBuilder',
          type: PropertyType.structured,
          description:
              'A builder that wraps the successfully loaded SVG widget.',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0009'))),
        ),
        PropertyEntry(
          wireId: WireId('p0129'),
          name: 'theme',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0001'))),
        ),
        PropertyEntry(
          wireId: WireId('p0130'),
          name: 'colorMapper',
          type: PropertyType.structured,
          description: '',
          constructorNullable: true,
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.svg', wireId: WireId('s0010'))),
        ),
        PropertyEntry(
          wireId: WireId('p0131'),
          name: 'cacheColorFilter',
          type: PropertyType.boolean,
          description: '',
          defaultSource: LiteralDefault(false),
          deprecated: DeprecationInfo(
              source: SourceDeprecationInfo(
                  message: 'This no longer does anything.')),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0132'),
          name: 'renderingStrategy',
          type: PropertyType.enumValue,
          description:
              'Widget rendering strategy used to balance flexibility and performance.',
          enumType: 'RenderingStrategy',
          defaultSource: LiteralDefault('picture'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri:
                      'package:vector_graphics/src/vector_graphics.dart',
                  symbolName: 'RenderingStrategy')),
        ),
        PropertyEntry(
          wireId: WireId('p0133'),
          name: 'analyticsId',
          type: PropertyType.string,
          description: 'Optional identifier for this widget occurrence.',
          synthetic: 'analyticsId',
        ),
      ],
    ),
  ],
  structuredTypes: [
    StructuredEntry(
      wireId: WireId('s0006'),
      name: 'Key',
      library: WidgetLibrary.custom('restage.svg'),
      description: 'Closed native data value.',
      sourceType: 'package:flutter/src/foundation/key.dart#Key',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0007'),
      name: 'AssetBundle',
      library: WidgetLibrary.custom('restage.svg'),
      description: 'Closed native data value.',
      sourceType: 'package:flutter/src/services/asset_bundle.dart#AssetBundle',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0008'),
      name: 'SvgErrorWidgetBuilder',
      library: WidgetLibrary.custom('restage.svg'),
      description: 'Closed native data value.',
      sourceType: 'package:flutter_svg/svg.dart#SvgErrorWidgetBuilder',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0009'),
      name: 'SvgImageWidgetBuilder',
      library: WidgetLibrary.custom('restage.svg'),
      description: 'Closed native data value.',
      sourceType: 'package:flutter_svg/svg.dart#SvgImageWidgetBuilder',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0001'),
      name: 'SvgTheme',
      library: WidgetLibrary.custom('restage.svg'),
      description: 'Closed native data value.',
      sourceType: 'package:flutter_svg/src/loaders.dart#SvgTheme',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0010'),
      name: 'ColorMapper',
      library: WidgetLibrary.custom('restage.svg'),
      description: 'Closed native data value.',
      sourceType: 'package:flutter_svg/src/loaders.dart#ColorMapper',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0002'),
      name: 'ColorFilter',
      library: WidgetLibrary.custom('restage.svg'),
      description: 'Closed native data value.',
      sourceType: 'dart:ui#ColorFilter',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0003'),
      name: 'StringHeaders',
      library: WidgetLibrary.custom('restage.svg'),
      description: 'Closed native data value.',
      sourceType: 'dart:core#Map',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0011'),
      name: 'Client',
      library: WidgetLibrary.custom('restage.svg'),
      description: 'Closed native data value.',
      sourceType: 'package:http/src/client.dart#Client',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0004'),
      name: 'Uint8List',
      library: WidgetLibrary.custom('restage.svg'),
      description: 'Closed native data value.',
      sourceType: 'dart:typed_data#Uint8List',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0005'),
      name: 'BytesLoader',
      library: WidgetLibrary.custom('restage.svg'),
      description: 'Closed native data value.',
      sourceType: 'package:vector_graphics/src/loader.dart#BytesLoader',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0012'),
      name: 'File',
      library: WidgetLibrary.custom('restage.svg'),
      description: 'Closed native data value.',
      sourceType: 'dart:io#File',
      fields: [],
      variants: [],
    ),
  ],
);

/// The content version of the `restage.svg` catalog —
/// the maximum widget `sinceVersion` in this library. Read by
/// the SDK to derive the installed built-in catalog version.
const int kSvgCatalogContentVersion = 2;
