// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated from lib/registry_curation.dart by restage_catalog_gen.
//
// Edit the curation file and re-run build_runner; do not
// edit this file directly. The runtime, codegen, and editor
// all consume `kRegistry` from here.

library;

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Registry for the `restage.core` library.
/// Read by codegen, the editor, and the runtime SDK.
final Catalog kRegistry = Catalog(
  schemaVersion: 4,
  generatedAt: '1970-01-01T00:00:00Z',
  libraries: {
    WidgetLibrary.core: const LibraryInfo(version: '0.1.0'),
  },
  widgets: [
    WidgetEntry(
      wireId: WireId('w0001'),
      name: 'Align',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'A widget that aligns its child within itself and optionally sizes itself based on the child\'s size.',
      flutterType: 'package:flutter/src/widgets/basic.dart#Align',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0001'),
          name: 'alignment',
          type: PropertyType.alignment,
          description: 'How to align the child.',
          defaultSource: LiteralDefault('center'),
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0002'),
          name: 'widthFactor',
          type: PropertyType.length,
          description:
              'If non-null, sets its width to the child\'s width multiplied by this factor.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0003'),
          name: 'heightFactor',
          type: PropertyType.length,
          description:
              'If non-null, sets its height to the child\'s height multiplied by this factor.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0004'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0036'),
      name: 'AnimatedAlign',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'Animated version of [Align] which automatically transitions the child\'s position over a given duration whenever the given [alignment] changes.',
      flutterType:
          'package:flutter/src/widgets/implicit_animations.dart#AnimatedAlign',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onEnd],
      properties: [
        PropertyEntry(
          wireId: WireId('p0313'),
          name: 'alignment',
          type: PropertyType.alignment,
          description: 'How to align the child.',
          required: true,
          defaultSource: LiteralDefault('center'),
          category: PropertyCategory.layout,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0314'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
        ),
        PropertyEntry(
          wireId: WireId('p0315'),
          name: 'heightFactor',
          type: PropertyType.length,
          description:
              'If non-null, sets its height to the child\'s height multiplied by this factor.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0316'),
          name: 'widthFactor',
          type: PropertyType.length,
          description:
              'If non-null, sets its width to the child\'s width multiplied by this factor.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0385'),
          name: 'curve',
          type: PropertyType.curve,
          description: '',
          defaultSource: LiteralDefault('linear'),
          valueShape: ScalarShape(
              propertyType: PropertyType.curve,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/animation/curves.dart',
                  symbolName: 'Curve')),
        ),
        PropertyEntry(
          wireId: WireId('p0317'),
          name: 'duration',
          type: PropertyType.duration,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0386'),
          name: 'onEnd',
          type: PropertyType.event,
          description: '',
          category: PropertyCategory.behavior,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0002'),
      name: 'AnimatedContainer',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'Animated version of [Container] that gradually changes its values over a period of time.',
      flutterType:
          'package:flutter/src/widgets/implicit_animations.dart#AnimatedContainer',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onEnd],
      properties: [
        PropertyEntry(
          wireId: WireId('p0005'),
          name: 'alignment',
          type: PropertyType.alignment,
          description: 'Align the [child] within the container.',
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0006'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description:
              'Empty space to inscribe inside the [decoration]. The [child], if any, is placed inside this padding.',
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0007'),
          name: 'color',
          type: PropertyType.color,
          description: '',
          defaultBrandToken: 'background',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0008'),
          name: 'width',
          type: PropertyType.length,
          description: '',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0009'),
          name: 'height',
          type: PropertyType.length,
          description: '',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0010'),
          name: 'margin',
          type: PropertyType.edgeInsets,
          description: 'Empty space to surround the [decoration] and [child].',
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0011'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The [child] contained by the container.',
        ),
        PropertyEntry(
          wireId: WireId('p0529'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description:
              'The clip behavior when [AnimatedContainer.decoration] is not null.',
          enumType: 'Clip',
          defaultSource: LiteralDefault('none'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0387'),
          name: 'curve',
          type: PropertyType.curve,
          description: '',
          defaultSource: LiteralDefault('linear'),
          valueShape: ScalarShape(
              propertyType: PropertyType.curve,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/animation/curves.dart',
                  symbolName: 'Curve')),
        ),
        PropertyEntry(
          wireId: WireId('p0012'),
          name: 'duration',
          type: PropertyType.duration,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0388'),
          name: 'onEnd',
          type: PropertyType.event,
          description: '',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0013'),
          name: 'borderRadius',
          type: PropertyType.real,
          description: 'Uniform corner radius applied to all four corners.',
          synthetic: 'borderRadiusCircular',
        ),
        PropertyEntry(
          wireId: WireId('p0565'),
          name: 'borderRadiusTopLeft',
          type: PropertyType.real,
          description: 'Top-left corner radius (Radius.circular).',
          synthetic: 'borderRadiusCorner',
        ),
        PropertyEntry(
          wireId: WireId('p0566'),
          name: 'borderRadiusTopRight',
          type: PropertyType.real,
          description: 'Top-right corner radius (Radius.circular).',
          synthetic: 'borderRadiusCorner',
        ),
        PropertyEntry(
          wireId: WireId('p0567'),
          name: 'borderRadiusBottomLeft',
          type: PropertyType.real,
          description: 'Bottom-left corner radius (Radius.circular).',
          synthetic: 'borderRadiusCorner',
        ),
        PropertyEntry(
          wireId: WireId('p0568'),
          name: 'borderRadiusBottomRight',
          type: PropertyType.real,
          description: 'Bottom-right corner radius (Radius.circular).',
          synthetic: 'borderRadiusCorner',
        ),
        PropertyEntry(
          wireId: WireId('p0014'),
          name: 'gradient',
          type: PropertyType.gradient,
          description:
              'Gradient painted behind the child (LinearGradient supported; other shapes deferred).',
          valueShape: UnionShape(
              propertyType: PropertyType.gradient,
              unionRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('u0003')),
              wireCodec: CatalogWireCodec.rfwGradient),
        ),
        PropertyEntry(
          wireId: WireId('p0015'),
          name: 'border',
          type: PropertyType.border,
          description:
              'Box border, uniform via Border.all or per-side via the default Border ctor.',
          valueShape: UnionShape(
              propertyType: PropertyType.border,
              unionRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('u0004')),
              wireCodec: CatalogWireCodec.rfwBorder),
        ),
        PropertyEntry(
          wireId: WireId('p0016'),
          name: 'boxShadow',
          type: PropertyType.boxShadowList,
          description: 'List of shadows painted behind the box.',
          valueShape: ListShape(
              propertyType: PropertyType.boxShadowList,
              itemShape: StructuredShape(
                  propertyType: PropertyType.structured,
                  structuredRef: WireIdRef(
                      library: 'restage.core', wireId: WireId('s0007'))),
              wireCodec: CatalogWireCodec.rfwBoxShadowList),
        ),
        PropertyEntry(
          wireId: WireId('p0017'),
          name: 'shape',
          type: PropertyType.enumValue,
          description: 'BoxDecoration shape (rectangle or circle).',
          enumType: 'BoxShape',
          defaultSource: LiteralDefault('rectangle'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/box_border.dart',
                  symbolName: 'BoxShape')),
        ),
        PropertyEntry(
          wireId: WireId('p0577'),
          name: 'decorationImage',
          type: PropertyType.decorationImage,
          description:
              'Background image painted behind the child (NetworkImage / AssetImage supported).',
          valueShape: ScalarShape(
              propertyType: PropertyType.decorationImage,
              dartTypeRef: DartTypeRef(
                  libraryUri:
                      'package:flutter/src/painting/decoration_image.dart',
                  symbolName: 'DecorationImage')),
        ),
        PropertyEntry(
          wireId: WireId('p0553'),
          name: 'minWidth',
          type: PropertyType.real,
          description: 'Minimum width the box may have.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0554'),
          name: 'maxWidth',
          type: PropertyType.real,
          description: 'Maximum width the box may have.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0555'),
          name: 'minHeight',
          type: PropertyType.real,
          description: 'Minimum height the box may have.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0556'),
          name: 'maxHeight',
          type: PropertyType.real,
          description: 'Maximum height the box may have.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0001')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'decoration',
          construction: FactoryInvocation(
              variantRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('v0002')),
              receiver: ResultStructuredTypeReceiver()),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0161'),
              propertyRef: WireId('p0007'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0163'),
              propertyRef: WireId('p0014'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0579'),
              propertyRef: WireId('p0577'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0164'),
              propertyRef: WireId('p0015'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0162'),
              propertyRef: WireId('p0013'),
              transform: ConstructVariantTransform(
                  resultStructuredRef: WireIdRef(
                      library: 'restage.core', wireId: WireId('s0003')),
                  invocation: FactoryInvocation(
                      variantRef: WireIdRef(
                          library: 'restage.core', wireId: WireId('v0003')),
                      receiver: ResultStructuredTypeReceiver(),
                      memberName: 'circular'),
                  argumentBindings: [
                    PropertyValueArgumentBinding(
                        parameterRef: WireId('a0003'),
                        nullPolicy: TransformNullPolicy.nullResult,
                        missingPolicy: TransformMissingPolicy.nullResult)
                  ]),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0165'),
              propertyRef: WireId('p0016'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0166'),
              propertyRef: WireId('p0017'),
              transform: IdentityTransform(),
            ),
          ],
        ),
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0028')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'constraints',
          construction: FactoryInvocation(
              variantRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('v0052')),
              receiver: ResultStructuredTypeReceiver()),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0561'),
              propertyRef: WireId('p0553'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0562'),
              propertyRef: WireId('p0554'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0563'),
              propertyRef: WireId('p0555'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0564'),
              propertyRef: WireId('p0556'),
              transform: IdentityTransform(),
            ),
          ],
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0037'),
      name: 'AnimatedDefaultTextStyle',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description:
          'Animated version of [DefaultTextStyle] which automatically transitions the default text style (the text style to apply to descendant [Text] widgets without explicit style) over a given duration whenever the given style changes.',
      flutterType:
          'package:flutter/src/widgets/implicit_animations.dart#AnimatedDefaultTextStyle',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onEnd],
      properties: [
        PropertyEntry(
          wireId: WireId('p0318'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0319'),
          name: 'textAlign',
          type: PropertyType.enumValue,
          description: 'How the text should be aligned horizontally.',
          enumType: 'TextAlign',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'TextAlign')),
        ),
        PropertyEntry(
          wireId: WireId('p0320'),
          name: 'softWrap',
          type: PropertyType.boolean,
          description: 'Whether the text should break at soft line breaks.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0321'),
          name: 'overflow',
          type: PropertyType.enumValue,
          description: 'How visual overflow should be handled.',
          enumType: 'TextOverflow',
          defaultSource: LiteralDefault('clip'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/text_painter.dart',
                  symbolName: 'TextOverflow')),
        ),
        PropertyEntry(
          wireId: WireId('p0322'),
          name: 'maxLines',
          type: PropertyType.integer,
          description:
              'An optional maximum number of lines for the text to span, wrapping if necessary.',
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0323'),
          name: 'textWidthBasis',
          type: PropertyType.enumValue,
          description:
              'The strategy to use when calculating the width of the Text.',
          enumType: 'TextWidthBasis',
          defaultSource: LiteralDefault('parent'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/text_painter.dart',
                  symbolName: 'TextWidthBasis')),
        ),
        PropertyEntry(
          wireId: WireId('p0389'),
          name: 'curve',
          type: PropertyType.curve,
          description: '',
          defaultSource: LiteralDefault('linear'),
          valueShape: ScalarShape(
              propertyType: PropertyType.curve,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/animation/curves.dart',
                  symbolName: 'Curve')),
        ),
        PropertyEntry(
          wireId: WireId('p0324'),
          name: 'duration',
          type: PropertyType.duration,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0390'),
          name: 'onEnd',
          type: PropertyType.event,
          description: '',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0325'),
          name: 'inherit',
          type: PropertyType.boolean,
          description:
              'Whether unset text style values inherit from the parent.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0326'),
          name: 'color',
          type: PropertyType.color,
          description: 'Text color.',
          defaultBrandToken: 'onBackground',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0327'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'Text background color.',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0328'),
          name: 'fontFamily',
          type: PropertyType.string,
          description: 'Primary font family.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0329'),
          name: 'fontSize',
          type: PropertyType.length,
          description: 'Font size in logical pixels.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0330'),
          name: 'fontWeight',
          type: PropertyType.fontWeight,
          description: 'Font weight.',
          valueShape: ScalarShape(
              propertyType: PropertyType.fontWeight,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'FontWeight')),
        ),
        PropertyEntry(
          wireId: WireId('p0331'),
          name: 'fontStyle',
          type: PropertyType.enumValue,
          description: 'Font posture.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'FontStyle')),
        ),
        PropertyEntry(
          wireId: WireId('p0332'),
          name: 'letterSpacing',
          type: PropertyType.length,
          description: 'Horizontal spacing between text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0333'),
          name: 'wordSpacing',
          type: PropertyType.length,
          description: 'Horizontal spacing between words.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0334'),
          name: 'textBaseline',
          type: PropertyType.enumValue,
          description: 'Baseline used to align text.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextBaseline')),
        ),
        PropertyEntry(
          wireId: WireId('p0335'),
          name: 'height',
          type: PropertyType.length,
          description: 'Text line height multiplier.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0336'),
          name: 'leadingDistribution',
          type: PropertyType.enumValue,
          description: 'How leading is distributed above and below text.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui',
                  symbolName: 'TextLeadingDistribution')),
        ),
        PropertyEntry(
          wireId: WireId('p0337'),
          name: 'locale',
          type: PropertyType.locale,
          description: 'Locale used for font selection.',
          valueShape: ScalarShape(
              propertyType: PropertyType.locale,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Locale')),
        ),
        PropertyEntry(
          wireId: WireId('p0338'),
          name: 'foreground',
          type: PropertyType.paint,
          description: 'Paint used to draw text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        PropertyEntry(
          wireId: WireId('p0339'),
          name: 'background',
          type: PropertyType.paint,
          description: 'Paint used behind text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        PropertyEntry(
          wireId: WireId('p0340'),
          name: 'shadows',
          type: PropertyType.shadowList,
          description: 'Shadows painted beneath text glyphs.',
          valueShape: ListShape(
              propertyType: PropertyType.shadowList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.shadowList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'Shadow'))),
        ),
        PropertyEntry(
          wireId: WireId('p0341'),
          name: 'fontFeatures',
          type: PropertyType.fontFeatureList,
          description: 'OpenType font features.',
          valueShape: ListShape(
              propertyType: PropertyType.fontFeatureList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.fontFeatureList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'FontFeature'))),
        ),
        PropertyEntry(
          wireId: WireId('p0342'),
          name: 'fontVariations',
          type: PropertyType.fontVariationList,
          description: 'OpenType font variation axis values.',
          valueShape: ListShape(
              propertyType: PropertyType.fontVariationList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.fontVariationList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'FontVariation'))),
        ),
        PropertyEntry(
          wireId: WireId('p0343'),
          name: 'decoration',
          type: PropertyType.textDecoration,
          description: 'Text decoration lines.',
          valueShape: ScalarShape(
              propertyType: PropertyType.textDecoration,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextDecoration')),
        ),
        PropertyEntry(
          wireId: WireId('p0344'),
          name: 'decorationColor',
          type: PropertyType.color,
          description: 'Text decoration color.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0345'),
          name: 'decorationStyle',
          type: PropertyType.enumValue,
          description: 'Text decoration stroke style.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextDecorationStyle')),
        ),
        PropertyEntry(
          wireId: WireId('p0346'),
          name: 'decorationThickness',
          type: PropertyType.length,
          description: 'Text decoration stroke thickness.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0347'),
          name: 'debugLabel',
          type: PropertyType.string,
          description: 'Debug label for this text style.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0348'),
          name: 'fontFamilyFallback',
          type: PropertyType.stringList,
          description: 'Fallback font families.',
          valueShape: ListShape(
              propertyType: PropertyType.stringList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.string,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'String'))),
        ),
        PropertyEntry(
          wireId: WireId('p0349'),
          name: 'fontPackage',
          type: PropertyType.string,
          description: 'Package that contains the custom font family.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0002')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'style',
          construction: FactoryInvocation(
              variantRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('v0001')),
              receiver: ResultStructuredTypeReceiver()),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0190'),
              propertyRef: WireId('p0325'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0169'),
              propertyRef: WireId('p0326'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0191'),
              propertyRef: WireId('p0327'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0192'),
              propertyRef: WireId('p0328'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0167'),
              propertyRef: WireId('p0329'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0168'),
              propertyRef: WireId('p0330'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0282'),
              propertyRef: WireId('p0331'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0193'),
              propertyRef: WireId('p0332'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0194'),
              propertyRef: WireId('p0333'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0283'),
              propertyRef: WireId('p0334'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0195'),
              propertyRef: WireId('p0335'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0284'),
              propertyRef: WireId('p0336'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0285'),
              propertyRef: WireId('p0337'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0286'),
              propertyRef: WireId('p0338'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0287'),
              propertyRef: WireId('p0339'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0288'),
              propertyRef: WireId('p0340'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0289'),
              propertyRef: WireId('p0341'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0290'),
              propertyRef: WireId('p0342'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0291'),
              propertyRef: WireId('p0343'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0196'),
              propertyRef: WireId('p0344'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0292'),
              propertyRef: WireId('p0345'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0197'),
              propertyRef: WireId('p0346'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0198'),
              propertyRef: WireId('p0347'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0293'),
              propertyRef: WireId('p0348'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0294'),
              propertyRef: WireId('p0321'),
              transform: IdentityTransform(),
            ),
          ],
          parameterMappings: [
            DecompositionParameterMapping(
              parameterRef: WireId('a0033'),
              propertyRef: WireId('p0349'),
              transform: IdentityTransform(),
            ),
          ],
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0038'),
      name: 'AnimatedOpacity',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description:
          'Animated version of [Opacity] which automatically transitions the child\'s opacity over a given duration whenever the given opacity changes.',
      flutterType:
          'package:flutter/src/widgets/implicit_animations.dart#AnimatedOpacity',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onEnd],
      properties: [
        PropertyEntry(
          wireId: WireId('p0350'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
        ),
        PropertyEntry(
          wireId: WireId('p0351'),
          name: 'opacity',
          type: PropertyType.real,
          description: 'The target opacity.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0391'),
          name: 'curve',
          type: PropertyType.curve,
          description: '',
          defaultSource: LiteralDefault('linear'),
          valueShape: ScalarShape(
              propertyType: PropertyType.curve,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/animation/curves.dart',
                  symbolName: 'Curve')),
        ),
        PropertyEntry(
          wireId: WireId('p0352'),
          name: 'duration',
          type: PropertyType.duration,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0392'),
          name: 'onEnd',
          type: PropertyType.event,
          description: '',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0353'),
          name: 'alwaysIncludeSemantics',
          type: PropertyType.boolean,
          description:
              'Whether the semantic information of the children is always included.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0039'),
      name: 'AnimatedPadding',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'Animated version of [Padding] which automatically transitions the indentation over a given duration whenever the given inset changes.',
      flutterType:
          'package:flutter/src/widgets/implicit_animations.dart#AnimatedPadding',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onEnd],
      properties: [
        PropertyEntry(
          wireId: WireId('p0354'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description: 'The amount of space by which to inset the child.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0355'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
        ),
        PropertyEntry(
          wireId: WireId('p0393'),
          name: 'curve',
          type: PropertyType.curve,
          description: '',
          defaultSource: LiteralDefault('linear'),
          valueShape: ScalarShape(
              propertyType: PropertyType.curve,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/animation/curves.dart',
                  symbolName: 'Curve')),
        ),
        PropertyEntry(
          wireId: WireId('p0356'),
          name: 'duration',
          type: PropertyType.duration,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0394'),
          name: 'onEnd',
          type: PropertyType.event,
          description: '',
          category: PropertyCategory.behavior,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0040'),
      name: 'AnimatedPositioned',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'Animated version of [Positioned] which automatically transitions the child\'s position over a given duration whenever the given position changes.',
      flutterType:
          'package:flutter/src/widgets/implicit_animations.dart#AnimatedPositioned',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onEnd],
      properties: [
        PropertyEntry(
          wireId: WireId('p0357'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0358'),
          name: 'left',
          type: PropertyType.length,
          description:
              'The offset of the child\'s left edge from the left of the stack.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0359'),
          name: 'top',
          type: PropertyType.length,
          description:
              'The offset of the child\'s top edge from the top of the stack.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0360'),
          name: 'right',
          type: PropertyType.length,
          description:
              'The offset of the child\'s right edge from the right of the stack.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0361'),
          name: 'bottom',
          type: PropertyType.length,
          description:
              'The offset of the child\'s bottom edge from the bottom of the stack.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0362'),
          name: 'width',
          type: PropertyType.length,
          description: 'The child\'s width.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0363'),
          name: 'height',
          type: PropertyType.length,
          description: 'The child\'s height.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0395'),
          name: 'curve',
          type: PropertyType.curve,
          description: '',
          defaultSource: LiteralDefault('linear'),
          valueShape: ScalarShape(
              propertyType: PropertyType.curve,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/animation/curves.dart',
                  symbolName: 'Curve')),
        ),
        PropertyEntry(
          wireId: WireId('p0364'),
          name: 'duration',
          type: PropertyType.duration,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0396'),
          name: 'onEnd',
          type: PropertyType.event,
          description: '',
          category: PropertyCategory.behavior,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0041'),
      name: 'AnimatedRotation',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description:
          'Animated version of [Transform.rotate] which automatically transitions the child\'s rotation over a given duration whenever the given rotation changes.',
      flutterType:
          'package:flutter/src/widgets/implicit_animations.dart#AnimatedRotation',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onEnd],
      properties: [
        PropertyEntry(
          wireId: WireId('p0365'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
        ),
        PropertyEntry(
          wireId: WireId('p0366'),
          name: 'turns',
          type: PropertyType.real,
          description: 'The animation that controls the rotation of the child.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0371'),
          name: 'alignment',
          type: PropertyType.alignmentXY,
          description:
              'The alignment of the origin of the coordinate system in which the rotation takes place, relative to the size of the box.',
          defaultSource: LiteralDefault('center'),
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignmentXY,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'Alignment')),
        ),
        PropertyEntry(
          wireId: WireId('p0397'),
          name: 'curve',
          type: PropertyType.curve,
          description: '',
          defaultSource: LiteralDefault('linear'),
          valueShape: ScalarShape(
              propertyType: PropertyType.curve,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/animation/curves.dart',
                  symbolName: 'Curve')),
        ),
        PropertyEntry(
          wireId: WireId('p0367'),
          name: 'duration',
          type: PropertyType.duration,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0398'),
          name: 'onEnd',
          type: PropertyType.event,
          description: '',
          category: PropertyCategory.behavior,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0042'),
      name: 'AnimatedScale',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description:
          'Animated version of [Transform.scale] which automatically transitions the child\'s scale over a given duration whenever the given scale changes.',
      flutterType:
          'package:flutter/src/widgets/implicit_animations.dart#AnimatedScale',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onEnd],
      properties: [
        PropertyEntry(
          wireId: WireId('p0368'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
        ),
        PropertyEntry(
          wireId: WireId('p0369'),
          name: 'scale',
          type: PropertyType.real,
          description: 'The target scale.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0372'),
          name: 'alignment',
          type: PropertyType.alignmentXY,
          description:
              'The alignment of the origin of the coordinate system in which the scale takes place, relative to the size of the box.',
          defaultSource: LiteralDefault('center'),
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignmentXY,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'Alignment')),
        ),
        PropertyEntry(
          wireId: WireId('p0399'),
          name: 'curve',
          type: PropertyType.curve,
          description: '',
          defaultSource: LiteralDefault('linear'),
          valueShape: ScalarShape(
              propertyType: PropertyType.curve,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/animation/curves.dart',
                  symbolName: 'Curve')),
        ),
        PropertyEntry(
          wireId: WireId('p0370'),
          name: 'duration',
          type: PropertyType.duration,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0400'),
          name: 'onEnd',
          type: PropertyType.event,
          description: '',
          category: PropertyCategory.behavior,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0043'),
      name: 'AnimatedSize',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description:
          'Animated widget that automatically transitions its size over a given duration whenever the given child\'s size changes.',
      flutterType:
          'package:flutter/src/widgets/animated_size.dart#AnimatedSize',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onEnd],
      properties: [
        PropertyEntry(
          wireId: WireId('p0373'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
        ),
        PropertyEntry(
          wireId: WireId('p0374'),
          name: 'alignment',
          type: PropertyType.alignment,
          description:
              'The alignment of the child within the parent when the parent is not yet the same size as the child.',
          defaultSource: LiteralDefault('center'),
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0401'),
          name: 'curve',
          type: PropertyType.curve,
          description:
              'The animation curve when transitioning this widget\'s size to match the child\'s size.',
          defaultSource: LiteralDefault('linear'),
          valueShape: ScalarShape(
              propertyType: PropertyType.curve,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/animation/curves.dart',
                  symbolName: 'Curve')),
        ),
        PropertyEntry(
          wireId: WireId('p0375'),
          name: 'duration',
          type: PropertyType.duration,
          description:
              'The duration when transitioning this widget\'s size to match the child\'s size.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0376'),
          name: 'reverseDuration',
          type: PropertyType.duration,
          description:
              'The duration when transitioning this widget\'s size to match the child\'s size when going in reverse.',
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0549'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '{@macro flutter.material.Material.clipBehavior}',
          enumType: 'Clip',
          defaultSource: LiteralDefault('hardEdge'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0402'),
          name: 'onEnd',
          type: PropertyType.event,
          description: 'Called every time an animation completes.',
          category: PropertyCategory.behavior,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0047'),
      name: 'AnimatedSlide',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description:
          'Widget which automatically transitions the child\'s offset relative to its normal position whenever the given offset changes.',
      flutterType:
          'package:flutter/src/widgets/implicit_animations.dart#AnimatedSlide',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onEnd],
      properties: [
        PropertyEntry(
          wireId: WireId('p0403'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
        ),
        PropertyEntry(
          wireId: WireId('p0404'),
          name: 'offset',
          type: PropertyType.offset,
          description:
              'The target offset. The child will be translated horizontally by `width * dx` and vertically by `height * dy`',
          required: true,
          defaultSource: LiteralDefault('zero'),
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.offset,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Offset')),
        ),
        PropertyEntry(
          wireId: WireId('p0405'),
          name: 'curve',
          type: PropertyType.curve,
          description: '',
          defaultSource: LiteralDefault('linear'),
          valueShape: ScalarShape(
              propertyType: PropertyType.curve,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/animation/curves.dart',
                  symbolName: 'Curve')),
        ),
        PropertyEntry(
          wireId: WireId('p0406'),
          name: 'duration',
          type: PropertyType.duration,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0407'),
          name: 'onEnd',
          type: PropertyType.event,
          description: '',
          category: PropertyCategory.behavior,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0003'),
      name: 'AspectRatio',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'A widget that attempts to size the child to a specific aspect ratio.',
      flutterType: 'package:flutter/src/widgets/basic.dart#AspectRatio',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0018'),
          name: 'aspectRatio',
          type: PropertyType.real,
          description: 'The aspect ratio to attempt to use.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0019'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0004'),
      name: 'BackdropFilter',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description:
          'A widget that applies a filter to the existing painted content and then paints [child].',
      flutterType: 'package:flutter/src/widgets/basic.dart#BackdropFilter',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0020'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
        PropertyEntry(
          wireId: WireId('p0021'),
          name: 'blendMode',
          type: PropertyType.enumValue,
          description:
              'The blend mode to use to apply the filtered background content onto the background surface.',
          enumType: 'BlendMode',
          defaultSource: LiteralDefault('srcOver'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'BlendMode')),
        ),
        PropertyEntry(
          wireId: WireId('p0022'),
          name: 'enabled',
          type: PropertyType.boolean,
          description:
              'Whether or not to apply the backdrop filter operation to the child of this widget.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0023'),
          name: 'blurSigmaX',
          type: PropertyType.real,
          description: 'Gaussian blur sigma along the X axis.',
          synthetic: 'imageFilterBlur',
        ),
        PropertyEntry(
          wireId: WireId('p0024'),
          name: 'blurSigmaY',
          type: PropertyType.real,
          description: 'Gaussian blur sigma along the Y axis.',
          synthetic: 'imageFilterBlur',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0005'),
      name: 'Center',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description: 'A widget that centers its child within itself.',
      flutterType: 'package:flutter/src/widgets/basic.dart#Center',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0025'),
          name: 'widthFactor',
          type: PropertyType.real,
          description: '',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0026'),
          name: 'heightFactor',
          type: PropertyType.real,
          description: '',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0027'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0006'),
      name: 'ClipOval',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description: 'A widget that clips its child using an oval.',
      flutterType: 'package:flutter/src/widgets/basic.dart#ClipOval',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0028'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '{@macro flutter.rendering.ClipRectLayer.clipBehavior}',
          enumType: 'Clip',
          defaultSource: LiteralDefault('antiAlias'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0029'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0007'),
      name: 'ClipRRect',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description: 'A widget that clips its child using a rounded rectangle.',
      flutterType: 'package:flutter/src/widgets/basic.dart#ClipRRect',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0030'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '{@macro flutter.rendering.ClipRectLayer.clipBehavior}',
          enumType: 'Clip',
          defaultSource: LiteralDefault('antiAlias'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0031'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
        PropertyEntry(
          wireId: WireId('p0032'),
          name: 'borderRadius',
          type: PropertyType.real,
          description: 'Uniform corner radius applied to all four corners.',
          synthetic: 'borderRadiusCircular',
        ),
        PropertyEntry(
          wireId: WireId('p0569'),
          name: 'borderRadiusTopLeft',
          type: PropertyType.real,
          description: 'Top-left corner radius (Radius.circular).',
          synthetic: 'borderRadiusCorner',
        ),
        PropertyEntry(
          wireId: WireId('p0570'),
          name: 'borderRadiusTopRight',
          type: PropertyType.real,
          description: 'Top-right corner radius (Radius.circular).',
          synthetic: 'borderRadiusCorner',
        ),
        PropertyEntry(
          wireId: WireId('p0571'),
          name: 'borderRadiusBottomLeft',
          type: PropertyType.real,
          description: 'Bottom-left corner radius (Radius.circular).',
          synthetic: 'borderRadiusCorner',
        ),
        PropertyEntry(
          wireId: WireId('p0572'),
          name: 'borderRadiusBottomRight',
          type: PropertyType.real,
          description: 'Bottom-right corner radius (Radius.circular).',
          synthetic: 'borderRadiusCorner',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0008'),
      name: 'ClipRect',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description: 'A widget that clips its child using a rectangle.',
      flutterType: 'package:flutter/src/widgets/basic.dart#ClipRect',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0033'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '{@macro flutter.rendering.ClipRectLayer.clipBehavior}',
          enumType: 'Clip',
          defaultSource: LiteralDefault('hardEdge'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0034'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0009'),
      name: 'Column',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description: 'A widget that displays its children in a vertical array.',
      flutterType: 'package:flutter/src/widgets/basic.dart#Column',
      childrenSlot: ChildrenSlot.list,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0035'),
          name: 'mainAxisAlignment',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'MainAxisAlignment',
          defaultSource: LiteralDefault('start'),
          category: PropertyCategory.layout,
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/rendering/flex.dart',
                  symbolName: 'MainAxisAlignment')),
        ),
        PropertyEntry(
          wireId: WireId('p0036'),
          name: 'mainAxisSize',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'MainAxisSize',
          defaultSource: LiteralDefault('max'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/rendering/flex.dart',
                  symbolName: 'MainAxisSize')),
        ),
        PropertyEntry(
          wireId: WireId('p0037'),
          name: 'crossAxisAlignment',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'CrossAxisAlignment',
          defaultSource: LiteralDefault('center'),
          category: PropertyCategory.layout,
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/rendering/flex.dart',
                  symbolName: 'CrossAxisAlignment')),
        ),
        PropertyEntry(
          wireId: WireId('p0531'),
          name: 'spacing',
          type: PropertyType.real,
          description: '',
          defaultSource: LiteralDefault(0.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0038'),
          name: 'children',
          type: PropertyType.widgetList,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0010'),
      name: 'Container',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'A convenience widget that combines common painting, positioning, and sizing widgets.',
      flutterType: 'package:flutter/src/widgets/container.dart#Container',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0039'),
          name: 'alignment',
          type: PropertyType.alignment,
          description: 'Align the [child] within the container.',
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0040'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description:
              'Empty space to inscribe inside the [decoration]. The [child], if any, is placed inside this padding.',
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0041'),
          name: 'color',
          type: PropertyType.color,
          description: 'The color to paint behind the [child].',
          defaultBrandToken: 'background',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0042'),
          name: 'width',
          type: PropertyType.length,
          description: '',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0043'),
          name: 'height',
          type: PropertyType.length,
          description: '',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0044'),
          name: 'margin',
          type: PropertyType.edgeInsets,
          description: 'Empty space to surround the [decoration] and [child].',
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0045'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The [child] contained by the container.',
        ),
        PropertyEntry(
          wireId: WireId('p0530'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description:
              'The clip behavior when [Container.decoration] is not null.',
          enumType: 'Clip',
          defaultSource: LiteralDefault('none'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0046'),
          name: 'borderRadius',
          type: PropertyType.real,
          description: 'Uniform corner radius applied to all four corners.',
          synthetic: 'borderRadiusCircular',
        ),
        PropertyEntry(
          wireId: WireId('p0573'),
          name: 'borderRadiusTopLeft',
          type: PropertyType.real,
          description: 'Top-left corner radius (Radius.circular).',
          synthetic: 'borderRadiusCorner',
        ),
        PropertyEntry(
          wireId: WireId('p0574'),
          name: 'borderRadiusTopRight',
          type: PropertyType.real,
          description: 'Top-right corner radius (Radius.circular).',
          synthetic: 'borderRadiusCorner',
        ),
        PropertyEntry(
          wireId: WireId('p0575'),
          name: 'borderRadiusBottomLeft',
          type: PropertyType.real,
          description: 'Bottom-left corner radius (Radius.circular).',
          synthetic: 'borderRadiusCorner',
        ),
        PropertyEntry(
          wireId: WireId('p0576'),
          name: 'borderRadiusBottomRight',
          type: PropertyType.real,
          description: 'Bottom-right corner radius (Radius.circular).',
          synthetic: 'borderRadiusCorner',
        ),
        PropertyEntry(
          wireId: WireId('p0047'),
          name: 'gradient',
          type: PropertyType.gradient,
          description:
              'Gradient painted behind the child (LinearGradient supported; other shapes deferred).',
          valueShape: UnionShape(
              propertyType: PropertyType.gradient,
              unionRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('u0003')),
              wireCodec: CatalogWireCodec.rfwGradient),
        ),
        PropertyEntry(
          wireId: WireId('p0048'),
          name: 'border',
          type: PropertyType.border,
          description:
              'Box border, uniform via Border.all or per-side via the default Border ctor.',
          valueShape: UnionShape(
              propertyType: PropertyType.border,
              unionRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('u0004')),
              wireCodec: CatalogWireCodec.rfwBorder),
        ),
        PropertyEntry(
          wireId: WireId('p0049'),
          name: 'boxShadow',
          type: PropertyType.boxShadowList,
          description: 'List of shadows painted behind the box.',
          valueShape: ListShape(
              propertyType: PropertyType.boxShadowList,
              itemShape: StructuredShape(
                  propertyType: PropertyType.structured,
                  structuredRef: WireIdRef(
                      library: 'restage.core', wireId: WireId('s0007'))),
              wireCodec: CatalogWireCodec.rfwBoxShadowList),
        ),
        PropertyEntry(
          wireId: WireId('p0050'),
          name: 'shape',
          type: PropertyType.enumValue,
          description: 'BoxDecoration shape (rectangle or circle).',
          enumType: 'BoxShape',
          defaultSource: LiteralDefault('rectangle'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/box_border.dart',
                  symbolName: 'BoxShape')),
        ),
        PropertyEntry(
          wireId: WireId('p0578'),
          name: 'decorationImage',
          type: PropertyType.decorationImage,
          description:
              'Background image painted behind the child (NetworkImage / AssetImage supported).',
          valueShape: ScalarShape(
              propertyType: PropertyType.decorationImage,
              dartTypeRef: DartTypeRef(
                  libraryUri:
                      'package:flutter/src/painting/decoration_image.dart',
                  symbolName: 'DecorationImage')),
        ),
        PropertyEntry(
          wireId: WireId('p0557'),
          name: 'minWidth',
          type: PropertyType.real,
          description: 'Minimum width the box may have.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0558'),
          name: 'maxWidth',
          type: PropertyType.real,
          description: 'Maximum width the box may have.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0559'),
          name: 'minHeight',
          type: PropertyType.real,
          description: 'Minimum height the box may have.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0560'),
          name: 'maxHeight',
          type: PropertyType.real,
          description: 'Maximum height the box may have.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0001')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'decoration',
          construction: FactoryInvocation(
              variantRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('v0002')),
              receiver: ResultStructuredTypeReceiver()),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0161'),
              propertyRef: WireId('p0041'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0163'),
              propertyRef: WireId('p0047'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0579'),
              propertyRef: WireId('p0578'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0164'),
              propertyRef: WireId('p0048'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0162'),
              propertyRef: WireId('p0046'),
              transform: ConstructVariantTransform(
                  resultStructuredRef: WireIdRef(
                      library: 'restage.core', wireId: WireId('s0003')),
                  invocation: FactoryInvocation(
                      variantRef: WireIdRef(
                          library: 'restage.core', wireId: WireId('v0003')),
                      receiver: ResultStructuredTypeReceiver(),
                      memberName: 'circular'),
                  argumentBindings: [
                    PropertyValueArgumentBinding(
                        parameterRef: WireId('a0003'),
                        nullPolicy: TransformNullPolicy.nullResult,
                        missingPolicy: TransformMissingPolicy.nullResult)
                  ]),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0165'),
              propertyRef: WireId('p0049'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0166'),
              propertyRef: WireId('p0050'),
              transform: IdentityTransform(),
            ),
          ],
        ),
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0028')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'constraints',
          construction: FactoryInvocation(
              variantRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('v0052')),
              receiver: ResultStructuredTypeReceiver()),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0561'),
              propertyRef: WireId('p0557'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0562'),
              propertyRef: WireId('p0558'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0563'),
              propertyRef: WireId('p0559'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0564'),
              propertyRef: WireId('p0560'),
              transform: IdentityTransform(),
            ),
          ],
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0011'),
      name: 'DecoratedBox',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description:
          'A widget that paints a [Decoration] either before or after its child paints.',
      flutterType: 'package:flutter/src/widgets/container.dart#DecoratedBox',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0051'),
          name: 'position',
          type: PropertyType.enumValue,
          description:
              'Whether to paint the box decoration behind or in front of the child.',
          enumType: 'DecorationPosition',
          defaultSource: LiteralDefault('background'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/rendering/proxy_box.dart',
                  symbolName: 'DecorationPosition')),
        ),
        PropertyEntry(
          wireId: WireId('p0052'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
        PropertyEntry(
          wireId: WireId('p0053'),
          name: 'color',
          type: PropertyType.color,
          description: 'Background color of the decoration.',
          defaultBrandToken: 'background',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0001')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'decoration',
          construction: FactoryInvocation(
              variantRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('v0002')),
              receiver: ResultStructuredTypeReceiver()),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0161'),
              propertyRef: WireId('p0053'),
              transform: IdentityTransform(),
            ),
          ],
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0012'),
      name: 'DefaultTextStyle',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description:
          'The text style to apply to descendant [Text] widgets which don\'t have an explicit style.',
      flutterType: 'package:flutter/src/widgets/text.dart#DefaultTextStyle',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0054'),
          name: 'textAlign',
          type: PropertyType.enumValue,
          description:
              'How each line of text in the Text widget should be aligned horizontally.',
          enumType: 'TextAlign',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'TextAlign')),
        ),
        PropertyEntry(
          wireId: WireId('p0055'),
          name: 'softWrap',
          type: PropertyType.boolean,
          description: 'Whether the text should break at soft line breaks.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0056'),
          name: 'overflow',
          type: PropertyType.enumValue,
          description: 'How visual overflow should be handled.',
          enumType: 'TextOverflow',
          defaultSource: LiteralDefault('clip'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/text_painter.dart',
                  symbolName: 'TextOverflow')),
        ),
        PropertyEntry(
          wireId: WireId('p0057'),
          name: 'maxLines',
          type: PropertyType.integer,
          description:
              'An optional maximum number of lines for the text to span, wrapping if necessary. If the text exceeds the given number of lines, it will be truncated according to [overflow].',
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0058'),
          name: 'textWidthBasis',
          type: PropertyType.enumValue,
          description:
              'The strategy to use when calculating the width of the Text.',
          enumType: 'TextWidthBasis',
          defaultSource: LiteralDefault('parent'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/text_painter.dart',
                  symbolName: 'TextWidthBasis')),
        ),
        PropertyEntry(
          wireId: WireId('p0059'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0241'),
          name: 'inherit',
          type: PropertyType.boolean,
          description:
              'Whether unset text style values inherit from the parent.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0062'),
          name: 'color',
          type: PropertyType.color,
          description: 'Text color.',
          defaultBrandToken: 'onBackground',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0242'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'Text background color.',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0243'),
          name: 'fontFamily',
          type: PropertyType.string,
          description: 'Primary font family.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0060'),
          name: 'fontSize',
          type: PropertyType.length,
          description: 'Font size in logical pixels.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0061'),
          name: 'fontWeight',
          type: PropertyType.fontWeight,
          description: 'Font weight.',
          valueShape: ScalarShape(
              propertyType: PropertyType.fontWeight,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'FontWeight')),
        ),
        PropertyEntry(
          wireId: WireId('p0244'),
          name: 'fontStyle',
          type: PropertyType.enumValue,
          description: 'Font posture.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'FontStyle')),
        ),
        PropertyEntry(
          wireId: WireId('p0237'),
          name: 'letterSpacing',
          type: PropertyType.length,
          description: 'Horizontal spacing between text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0245'),
          name: 'wordSpacing',
          type: PropertyType.length,
          description: 'Horizontal spacing between words.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0246'),
          name: 'textBaseline',
          type: PropertyType.enumValue,
          description: 'Baseline used to align text.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextBaseline')),
        ),
        PropertyEntry(
          wireId: WireId('p0238'),
          name: 'height',
          type: PropertyType.length,
          description: 'Text line height multiplier.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0247'),
          name: 'leadingDistribution',
          type: PropertyType.enumValue,
          description: 'How leading is distributed above and below text.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui',
                  symbolName: 'TextLeadingDistribution')),
        ),
        PropertyEntry(
          wireId: WireId('p0248'),
          name: 'locale',
          type: PropertyType.locale,
          description: 'Locale used for font selection.',
          valueShape: ScalarShape(
              propertyType: PropertyType.locale,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Locale')),
        ),
        PropertyEntry(
          wireId: WireId('p0249'),
          name: 'foreground',
          type: PropertyType.paint,
          description: 'Paint used to draw text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        PropertyEntry(
          wireId: WireId('p0250'),
          name: 'background',
          type: PropertyType.paint,
          description: 'Paint used behind text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        PropertyEntry(
          wireId: WireId('p0251'),
          name: 'shadows',
          type: PropertyType.shadowList,
          description: 'Shadows painted beneath text glyphs.',
          valueShape: ListShape(
              propertyType: PropertyType.shadowList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.shadowList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'Shadow'))),
        ),
        PropertyEntry(
          wireId: WireId('p0252'),
          name: 'fontFeatures',
          type: PropertyType.fontFeatureList,
          description: 'OpenType font features.',
          valueShape: ListShape(
              propertyType: PropertyType.fontFeatureList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.fontFeatureList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'FontFeature'))),
        ),
        PropertyEntry(
          wireId: WireId('p0253'),
          name: 'fontVariations',
          type: PropertyType.fontVariationList,
          description: 'OpenType font variation axis values.',
          valueShape: ListShape(
              propertyType: PropertyType.fontVariationList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.fontVariationList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'FontVariation'))),
        ),
        PropertyEntry(
          wireId: WireId('p0254'),
          name: 'decoration',
          type: PropertyType.textDecoration,
          description: 'Text decoration lines.',
          valueShape: ScalarShape(
              propertyType: PropertyType.textDecoration,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextDecoration')),
        ),
        PropertyEntry(
          wireId: WireId('p0255'),
          name: 'decorationColor',
          type: PropertyType.color,
          description: 'Text decoration color.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0256'),
          name: 'decorationStyle',
          type: PropertyType.enumValue,
          description: 'Text decoration stroke style.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextDecorationStyle')),
        ),
        PropertyEntry(
          wireId: WireId('p0257'),
          name: 'decorationThickness',
          type: PropertyType.length,
          description: 'Text decoration stroke thickness.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0258'),
          name: 'debugLabel',
          type: PropertyType.string,
          description: 'Debug label for this text style.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0259'),
          name: 'fontFamilyFallback',
          type: PropertyType.stringList,
          description: 'Fallback font families.',
          valueShape: ListShape(
              propertyType: PropertyType.stringList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.string,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'String'))),
        ),
        PropertyEntry(
          wireId: WireId('p0260'),
          name: 'fontPackage',
          type: PropertyType.string,
          description: 'Package that contains the custom font family.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0002')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'style',
          construction: FactoryInvocation(
              variantRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('v0001')),
              receiver: ResultStructuredTypeReceiver()),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0190'),
              propertyRef: WireId('p0241'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0169'),
              propertyRef: WireId('p0062'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0191'),
              propertyRef: WireId('p0242'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0192'),
              propertyRef: WireId('p0243'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0167'),
              propertyRef: WireId('p0060'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0168'),
              propertyRef: WireId('p0061'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0282'),
              propertyRef: WireId('p0244'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0193'),
              propertyRef: WireId('p0237'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0194'),
              propertyRef: WireId('p0245'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0283'),
              propertyRef: WireId('p0246'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0195'),
              propertyRef: WireId('p0238'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0284'),
              propertyRef: WireId('p0247'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0285'),
              propertyRef: WireId('p0248'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0286'),
              propertyRef: WireId('p0249'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0287'),
              propertyRef: WireId('p0250'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0288'),
              propertyRef: WireId('p0251'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0289'),
              propertyRef: WireId('p0252'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0290'),
              propertyRef: WireId('p0253'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0291'),
              propertyRef: WireId('p0254'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0196'),
              propertyRef: WireId('p0255'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0292'),
              propertyRef: WireId('p0256'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0197'),
              propertyRef: WireId('p0257'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0198'),
              propertyRef: WireId('p0258'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0293'),
              propertyRef: WireId('p0259'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0294'),
              propertyRef: WireId('p0056'),
              transform: IdentityTransform(),
            ),
          ],
          parameterMappings: [
            DecompositionParameterMapping(
              parameterRef: WireId('a0033'),
              propertyRef: WireId('p0260'),
              transform: IdentityTransform(),
            ),
          ],
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0013'),
      name: 'Expanded',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'A widget that expands a child of a [Row], [Column], or [Flex] so that the child fills the available space.',
      flutterType: 'package:flutter/src/widgets/basic.dart#Expanded',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0063'),
          name: 'flex',
          type: PropertyType.integer,
          description: '',
          defaultSource: LiteralDefault(1),
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0064'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0014'),
      name: 'FadeInImageAssetNetwork',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description:
          'An image that shows a [placeholder] image while the target [image] is loading, then fades in the new image when it loads.',
      flutterType:
          'package:flutter/src/widgets/fade_in_image.dart#FadeInImage.assetNetwork',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0065'),
          name: 'placeholder',
          type: PropertyType.string,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0066'),
          name: 'image',
          type: PropertyType.string,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0067'),
          name: 'imageScale',
          type: PropertyType.real,
          description: '',
          defaultSource: LiteralDefault(1.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0068'),
          name: 'width',
          type: PropertyType.length,
          description: 'If non-null, require the image to have this width.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0069'),
          name: 'height',
          type: PropertyType.length,
          description: 'If non-null, require the image to have this height.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0070'),
          name: 'fit',
          type: PropertyType.enumValue,
          description:
              'How to inscribe the image into the space allocated during layout.',
          enumType: 'BoxFit',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/box_fit.dart',
                  symbolName: 'BoxFit')),
        ),
        PropertyEntry(
          wireId: WireId('p0071'),
          name: 'placeholderFit',
          type: PropertyType.enumValue,
          description:
              'How to inscribe the placeholder image into the space allocated during layout.',
          enumType: 'BoxFit',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/box_fit.dart',
                  symbolName: 'BoxFit')),
        ),
        PropertyEntry(
          wireId: WireId('p0072'),
          name: 'placeholderFilterQuality',
          type: PropertyType.enumValue,
          description: 'The rendering quality of the placeholder image.',
          enumType: 'FilterQuality',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'FilterQuality')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0015'),
      name: 'FittedBox',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'Scales and positions its child within itself according to [fit].',
      flutterType: 'package:flutter/src/widgets/basic.dart#FittedBox',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0073'),
          name: 'fit',
          type: PropertyType.enumValue,
          description:
              'How to inscribe the child into the space allocated during layout.',
          enumType: 'BoxFit',
          defaultSource: LiteralDefault('contain'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/box_fit.dart',
                  symbolName: 'BoxFit')),
        ),
        PropertyEntry(
          wireId: WireId('p0074'),
          name: 'alignment',
          type: PropertyType.alignment,
          description: 'How to align the child within its parent\'s bounds.',
          defaultSource: LiteralDefault('center'),
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0075'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '{@macro flutter.material.Material.clipBehavior}',
          enumType: 'Clip',
          defaultSource: LiteralDefault('none'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0076'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0016'),
      name: 'Flexible',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'A widget that controls how a child of a [Row], [Column], or [Flex] flexes.',
      flutterType: 'package:flutter/src/widgets/basic.dart#Flexible',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0077'),
          name: 'flex',
          type: PropertyType.integer,
          description: 'The flex factor to use for this child.',
          defaultSource: LiteralDefault(1),
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0078'),
          name: 'fit',
          type: PropertyType.enumValue,
          description:
              'How a flexible child is inscribed into the available space.',
          enumType: 'FlexFit',
          defaultSource: LiteralDefault('loose'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/rendering/flex.dart',
                  symbolName: 'FlexFit')),
        ),
        PropertyEntry(
          wireId: WireId('p0079'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0044'),
      name: 'FractionallySizedBox',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'A widget that sizes its child to a fraction of the total available space. For more details about the layout algorithm, see [RenderFractionallySizedOverflowBox].',
      flutterType:
          'package:flutter/src/widgets/basic.dart#FractionallySizedBox',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0377'),
          name: 'alignment',
          type: PropertyType.alignment,
          description:
              '{@template flutter.widgets.basic.fractionallySizedBox.alignment} How to align the child.',
          defaultSource: LiteralDefault('center'),
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0378'),
          name: 'widthFactor',
          type: PropertyType.real,
          description:
              '{@template flutter.widgets.basic.fractionallySizedBox.widthFactor} If non-null, the fraction of the incoming width given to the child.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0379'),
          name: 'heightFactor',
          type: PropertyType.real,
          description:
              '{@template flutter.widgets.basic.fractionallySizedBox.heightFactor} If non-null, the fraction of the incoming height given to the child.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0380'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0017'),
      name: 'GestureDetector',
      library: WidgetLibrary.core,
      category: WidgetCategory.input,
      description: 'A widget that detects gestures.',
      flutterType:
          'package:flutter/src/widgets/gesture_detector.dart#GestureDetector',
      childrenSlot: ChildrenSlot.single,
      fires: [
        WidgetEventName.onTap,
        WidgetEventName.onLongPress,
        WidgetEventName.onDoubleTap
      ],
      properties: [
        PropertyEntry(
          wireId: WireId('p0080'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
        ),
        PropertyEntry(
          wireId: WireId('p0081'),
          name: 'onTap',
          type: PropertyType.event,
          description: 'A tap with a primary button has occurred.',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0082'),
          name: 'onDoubleTap',
          type: PropertyType.event,
          description:
              'The user has tapped the screen with a primary button at the same location twice in quick succession.',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0083'),
          name: 'onLongPress',
          type: PropertyType.event,
          description:
              'Called when a long press gesture with a primary button has been recognized.',
          category: PropertyCategory.behavior,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0018'),
      name: 'Image',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description: 'A network image.',
      flutterType: 'package:flutter/src/widgets/image.dart#Image.network',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0084'),
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
          wireId: WireId('p0085'),
          name: 'semanticLabel',
          type: PropertyType.string,
          description: 'A Semantic description of the image.',
          category: PropertyCategory.accessibility,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0086'),
          name: 'width',
          type: PropertyType.length,
          description:
              'If non-null, require the image to have this width (in logical pixels).',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0087'),
          name: 'height',
          type: PropertyType.length,
          description:
              'If non-null, require the image to have this height (in logical pixels).',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0532'),
          name: 'color',
          type: PropertyType.color,
          description:
              'If non-null, this color is blended with each image pixel using [colorBlendMode].',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0533'),
          name: 'colorBlendMode',
          type: PropertyType.enumValue,
          description: 'Used to combine [color] with this image.',
          enumType: 'BlendMode',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'BlendMode')),
        ),
        PropertyEntry(
          wireId: WireId('p0088'),
          name: 'fit',
          type: PropertyType.enumValue,
          description:
              'How to inscribe the image into the space allocated during layout.',
          enumType: 'BoxFit',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/box_fit.dart',
                  symbolName: 'BoxFit')),
        ),
        PropertyEntry(
          wireId: WireId('p0534'),
          name: 'alignment',
          type: PropertyType.alignmentXY,
          description: 'How to align the image within its bounds.',
          defaultSource: LiteralDefault('center'),
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignmentXY,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0535'),
          name: 'repeat',
          type: PropertyType.enumValue,
          description:
              'How to paint any portions of the layout bounds not covered by the image.',
          enumType: 'ImageRepeat',
          defaultSource: LiteralDefault('noRepeat'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri:
                      'package:flutter/src/painting/decoration_image.dart',
                  symbolName: 'ImageRepeat')),
        ),
        PropertyEntry(
          wireId: WireId('p0536'),
          name: 'filterQuality',
          type: PropertyType.enumValue,
          description: 'The rendering quality of the image.',
          enumType: 'FilterQuality',
          defaultSource: LiteralDefault('medium'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'FilterQuality')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0019'),
      name: 'ImageAsset',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description: 'A widget that displays an image.',
      flutterType: 'package:flutter/src/widgets/image.dart#Image.asset',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0089'),
          name: 'name',
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
          wireId: WireId('p0090'),
          name: 'semanticLabel',
          type: PropertyType.string,
          description: 'A Semantic description of the image.',
          category: PropertyCategory.accessibility,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0091'),
          name: 'width',
          type: PropertyType.length,
          description:
              'If non-null, require the image to have this width (in logical pixels).',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0092'),
          name: 'height',
          type: PropertyType.length,
          description:
              'If non-null, require the image to have this height (in logical pixels).',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0537'),
          name: 'color',
          type: PropertyType.color,
          description:
              'If non-null, this color is blended with each image pixel using [colorBlendMode].',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0538'),
          name: 'colorBlendMode',
          type: PropertyType.enumValue,
          description: 'Used to combine [color] with this image.',
          enumType: 'BlendMode',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'BlendMode')),
        ),
        PropertyEntry(
          wireId: WireId('p0093'),
          name: 'fit',
          type: PropertyType.enumValue,
          description:
              'How to inscribe the image into the space allocated during layout.',
          enumType: 'BoxFit',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/box_fit.dart',
                  symbolName: 'BoxFit')),
        ),
        PropertyEntry(
          wireId: WireId('p0539'),
          name: 'alignment',
          type: PropertyType.alignmentXY,
          description: 'How to align the image within its bounds.',
          defaultSource: LiteralDefault('center'),
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignmentXY,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0540'),
          name: 'repeat',
          type: PropertyType.enumValue,
          description:
              'How to paint any portions of the layout bounds not covered by the image.',
          enumType: 'ImageRepeat',
          defaultSource: LiteralDefault('noRepeat'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri:
                      'package:flutter/src/painting/decoration_image.dart',
                  symbolName: 'ImageRepeat')),
        ),
        PropertyEntry(
          wireId: WireId('p0541'),
          name: 'filterQuality',
          type: PropertyType.enumValue,
          description: 'The rendering quality of the image.',
          enumType: 'FilterQuality',
          defaultSource: LiteralDefault('medium'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'FilterQuality')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0045'),
      name: 'IntrinsicHeight',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'A widget that sizes its child to the child\'s intrinsic height.',
      flutterType: 'package:flutter/src/widgets/basic.dart#IntrinsicHeight',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0381'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0046'),
      name: 'IntrinsicWidth',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'A widget that sizes its child to the child\'s maximum intrinsic width.',
      flutterType: 'package:flutter/src/widgets/basic.dart#IntrinsicWidth',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0382'),
          name: 'stepWidth',
          type: PropertyType.real,
          description:
              'If non-null, force the child\'s width to be a multiple of this value.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0383'),
          name: 'stepHeight',
          type: PropertyType.real,
          description:
              'If non-null, force the child\'s height to be a multiple of this value.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0384'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0020'),
      name: 'LimitedBox',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description: 'A box that limits its size only when it\'s unconstrained.',
      flutterType: 'package:flutter/src/widgets/basic.dart#LimitedBox',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0094'),
          name: 'maxWidth',
          type: PropertyType.length,
          description:
              'The maximum width limit to apply in the absence of a [BoxConstraints.maxWidth] constraint.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0095'),
          name: 'maxHeight',
          type: PropertyType.length,
          description:
              'The maximum height limit to apply in the absence of a [BoxConstraints.maxHeight] constraint.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0096'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0021'),
      name: 'ListView',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description: 'A scrollable list of widgets arranged linearly.',
      flutterType: 'package:flutter/src/widgets/scroll_view.dart#ListView',
      childrenSlot: ChildrenSlot.list,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0097'),
          name: 'scrollDirection',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'Axis',
          defaultSource: LiteralDefault('vertical'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/basic_types.dart',
                  symbolName: 'Axis')),
        ),
        PropertyEntry(
          wireId: WireId('p0098'),
          name: 'reverse',
          type: PropertyType.boolean,
          description: '',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0099'),
          name: 'shrinkWrap',
          type: PropertyType.boolean,
          description: '',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0100'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description: '',
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0101'),
          name: 'children',
          type: PropertyType.widgetList,
          description: '',
        ),
        PropertyEntry(
          wireId: WireId('p0498'),
          name: 'keyboardDismissBehavior',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'ScrollViewKeyboardDismissBehavior',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/widgets/scroll_view.dart',
                  symbolName: 'ScrollViewKeyboardDismissBehavior')),
        ),
        PropertyEntry(
          wireId: WireId('p0550'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'Clip',
          defaultSource: LiteralDefault('hardEdge'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0050'),
      name: 'RestageFadeIn',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description:
          'Fades [child] in (optionally rising into place) when it first appears.',
      flutterType:
          'package:restage_core/src/widgets/restage_fade_in.dart#RestageFadeIn',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onEnd],
      properties: [
        PropertyEntry(
          wireId: WireId('p0471'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget that fades in.',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0472'),
          name: 'duration',
          type: PropertyType.duration,
          description:
              'How long the fade takes. Null uses [defaultDuration] (300ms).',
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0473'),
          name: 'curve',
          type: PropertyType.curve,
          description: 'The easing of the fade. Defaults to [Curves.easeOut].',
          defaultSource: LiteralDefault('easeOut'),
          valueShape: ScalarShape(
              propertyType: PropertyType.curve,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/animation/curves.dart',
                  symbolName: 'Curve')),
        ),
        PropertyEntry(
          wireId: WireId('p0474'),
          name: 'fromOpacity',
          type: PropertyType.real,
          description:
              'The opacity the child fades from. Defaults to `0.0` (fully transparent).',
          defaultSource: LiteralDefault(0.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0475'),
          name: 'fromOffset',
          type: PropertyType.offset,
          description:
              'The translation (in logical pixels) the child rises from. `Offset.zero` (the default) means a pure fade; e.g. `Offset(0, 16)` fades + rises.',
          defaultSource: LiteralDefault('zero'),
          valueShape: ScalarShape(
              propertyType: PropertyType.offset,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Offset')),
        ),
        PropertyEntry(
          wireId: WireId('p0476'),
          name: 'delay',
          type: PropertyType.duration,
          description:
              'How long to wait after mount before the fade starts. Null means no delay.',
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0477'),
          name: 'onEnd',
          type: PropertyType.event,
          description:
              'Fires once when the fade settles. Never fires if the widget is disposed before settling.',
          category: PropertyCategory.behavior,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0048'),
      name: 'RestageFormattedNumber',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description: 'Locale-aware decimal number formatting, rendered as text.',
      flutterType:
          'package:restage_core/src/widgets/restage_formatted_number.dart#RestageFormattedNumber',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0409'),
          name: 'value',
          type: PropertyType.real,
          description: 'The number to format. Null renders the empty string.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0410'),
          name: 'numberLocale',
          type: PropertyType.string,
          description:
              'The locale whose conventions govern number formatting — grouping and the decimal mark (e.g. `en_US`, `de_DE`). Null uses the ambient default locale.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0411'),
          name: 'textAlign',
          type: PropertyType.enumValue,
          description: 'Horizontal alignment of the rendered value.',
          enumType: 'TextAlign',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'TextAlign')),
        ),
        PropertyEntry(
          wireId: WireId('p0412'),
          name: 'maxLines',
          type: PropertyType.integer,
          description: 'Maximum number of lines for the rendered value.',
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0413'),
          name: 'inherit',
          type: PropertyType.boolean,
          description:
              'Whether unset text style values inherit from the parent.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0414'),
          name: 'color',
          type: PropertyType.color,
          description: 'Text color.',
          defaultBrandToken: 'onBackground',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0415'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'Text background color.',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0416'),
          name: 'fontFamily',
          type: PropertyType.string,
          description: 'Primary font family.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0417'),
          name: 'fontSize',
          type: PropertyType.length,
          description: 'Font size in logical pixels.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0418'),
          name: 'fontWeight',
          type: PropertyType.fontWeight,
          description: 'Font weight.',
          valueShape: ScalarShape(
              propertyType: PropertyType.fontWeight,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'FontWeight')),
        ),
        PropertyEntry(
          wireId: WireId('p0419'),
          name: 'fontStyle',
          type: PropertyType.enumValue,
          description: 'Font posture.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'FontStyle')),
        ),
        PropertyEntry(
          wireId: WireId('p0420'),
          name: 'letterSpacing',
          type: PropertyType.length,
          description: 'Horizontal spacing between text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0421'),
          name: 'wordSpacing',
          type: PropertyType.length,
          description: 'Horizontal spacing between words.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0422'),
          name: 'textBaseline',
          type: PropertyType.enumValue,
          description: 'Baseline used to align text.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextBaseline')),
        ),
        PropertyEntry(
          wireId: WireId('p0423'),
          name: 'height',
          type: PropertyType.length,
          description: 'Text line height multiplier.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0424'),
          name: 'leadingDistribution',
          type: PropertyType.enumValue,
          description: 'How leading is distributed above and below text.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui',
                  symbolName: 'TextLeadingDistribution')),
        ),
        PropertyEntry(
          wireId: WireId('p0425'),
          name: 'locale',
          type: PropertyType.locale,
          description: 'Locale used for font selection.',
          valueShape: ScalarShape(
              propertyType: PropertyType.locale,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Locale')),
        ),
        PropertyEntry(
          wireId: WireId('p0426'),
          name: 'foreground',
          type: PropertyType.paint,
          description: 'Paint used to draw text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        PropertyEntry(
          wireId: WireId('p0427'),
          name: 'background',
          type: PropertyType.paint,
          description: 'Paint used behind text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        PropertyEntry(
          wireId: WireId('p0428'),
          name: 'shadows',
          type: PropertyType.shadowList,
          description: 'Shadows painted beneath text glyphs.',
          valueShape: ListShape(
              propertyType: PropertyType.shadowList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.shadowList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'Shadow'))),
        ),
        PropertyEntry(
          wireId: WireId('p0429'),
          name: 'fontFeatures',
          type: PropertyType.fontFeatureList,
          description: 'OpenType font features.',
          valueShape: ListShape(
              propertyType: PropertyType.fontFeatureList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.fontFeatureList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'FontFeature'))),
        ),
        PropertyEntry(
          wireId: WireId('p0430'),
          name: 'fontVariations',
          type: PropertyType.fontVariationList,
          description: 'OpenType font variation axis values.',
          valueShape: ListShape(
              propertyType: PropertyType.fontVariationList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.fontVariationList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'FontVariation'))),
        ),
        PropertyEntry(
          wireId: WireId('p0431'),
          name: 'decoration',
          type: PropertyType.textDecoration,
          description: 'Text decoration lines.',
          valueShape: ScalarShape(
              propertyType: PropertyType.textDecoration,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextDecoration')),
        ),
        PropertyEntry(
          wireId: WireId('p0432'),
          name: 'decorationColor',
          type: PropertyType.color,
          description: 'Text decoration color.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0433'),
          name: 'decorationStyle',
          type: PropertyType.enumValue,
          description: 'Text decoration stroke style.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextDecorationStyle')),
        ),
        PropertyEntry(
          wireId: WireId('p0434'),
          name: 'decorationThickness',
          type: PropertyType.length,
          description: 'Text decoration stroke thickness.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0435'),
          name: 'debugLabel',
          type: PropertyType.string,
          description: 'Debug label for this text style.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0436'),
          name: 'fontFamilyFallback',
          type: PropertyType.stringList,
          description: 'Fallback font families.',
          valueShape: ListShape(
              propertyType: PropertyType.stringList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.string,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'String'))),
        ),
        PropertyEntry(
          wireId: WireId('p0437'),
          name: 'fontPackage',
          type: PropertyType.string,
          description: 'Package that contains the custom font family.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0438'),
          name: 'overflow',
          type: PropertyType.enumValue,
          description: 'Text overflow behavior.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/text_painter.dart',
                  symbolName: 'TextOverflow')),
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0002')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'style',
          construction: FactoryInvocation(
              variantRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('v0001')),
              receiver: ResultStructuredTypeReceiver()),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0190'),
              propertyRef: WireId('p0413'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0169'),
              propertyRef: WireId('p0414'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0191'),
              propertyRef: WireId('p0415'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0192'),
              propertyRef: WireId('p0416'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0167'),
              propertyRef: WireId('p0417'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0168'),
              propertyRef: WireId('p0418'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0282'),
              propertyRef: WireId('p0419'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0193'),
              propertyRef: WireId('p0420'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0194'),
              propertyRef: WireId('p0421'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0283'),
              propertyRef: WireId('p0422'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0195'),
              propertyRef: WireId('p0423'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0284'),
              propertyRef: WireId('p0424'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0285'),
              propertyRef: WireId('p0425'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0286'),
              propertyRef: WireId('p0426'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0287'),
              propertyRef: WireId('p0427'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0288'),
              propertyRef: WireId('p0428'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0289'),
              propertyRef: WireId('p0429'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0290'),
              propertyRef: WireId('p0430'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0291'),
              propertyRef: WireId('p0431'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0196'),
              propertyRef: WireId('p0432'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0292'),
              propertyRef: WireId('p0433'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0197'),
              propertyRef: WireId('p0434'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0198'),
              propertyRef: WireId('p0435'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0293'),
              propertyRef: WireId('p0436'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0294'),
              propertyRef: WireId('p0438'),
              transform: IdentityTransform(),
            ),
          ],
          parameterMappings: [
            DecompositionParameterMapping(
              parameterRef: WireId('a0033'),
              propertyRef: WireId('p0437'),
              transform: IdentityTransform(),
            ),
          ],
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0051'),
      name: 'RestageMotion',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description: 'Springs [child] into place when it first appears.',
      flutterType:
          'package:restage_core/src/widgets/restage_motion.dart#RestageMotion',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onEnd],
      properties: [
        PropertyEntry(
          wireId: WireId('p0478'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget that springs into place.',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0479'),
          name: 'spring',
          type: PropertyType.enumValue,
          description:
              'The named spring feel. Defaults to [RestageSpring.smooth].',
          enumType: 'RestageSpring',
          defaultSource: LiteralDefault('smooth'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri:
                      'package:restage_core/src/widgets/restage_spring.dart',
                  symbolName: 'RestageSpring')),
        ),
        PropertyEntry(
          wireId: WireId('p0480'),
          name: 'duration',
          type: PropertyType.duration,
          description:
              'Optional override for the preset\'s settle duration. Null keeps the preset\'s duration. Independent of [bounce] — overriding one leaves the other at the preset\'s value.',
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0481'),
          name: 'bounce',
          type: PropertyType.real,
          description:
              'Optional override for the preset\'s bounce (overshoot). Null keeps the preset\'s bounce. Independent of [duration]. Clamped internally so no value can produce a non-settling spring.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0482'),
          name: 'fromScale',
          type: PropertyType.real,
          description:
              'The scale the child animates from. `1.0` (the default) means no scale animation; `< 1.0` pops in, `> 1.0` shrinks in.',
          defaultSource: LiteralDefault(1.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0483'),
          name: 'fromOpacity',
          type: PropertyType.real,
          description:
              'The opacity the child animates from. `1.0` (the default) means no fade; `0.0` fades in.',
          defaultSource: LiteralDefault(1.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0484'),
          name: 'fromOffset',
          type: PropertyType.offset,
          description:
              'The translation (in logical pixels) the child animates from. `Offset.zero` (the default) means no slide; e.g. `Offset(0, 24)` rises into place.',
          defaultSource: LiteralDefault('zero'),
          valueShape: ScalarShape(
              propertyType: PropertyType.offset,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Offset')),
        ),
        PropertyEntry(
          wireId: WireId('p0485'),
          name: 'delay',
          type: PropertyType.duration,
          description:
              'How long to wait after mount before the entrance starts. Null means no delay (start immediately).',
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0486'),
          name: 'onEnd',
          type: PropertyType.event,
          description:
              'Fires once when the entrance settles. Never fires if the widget is disposed before settling.',
          category: PropertyCategory.behavior,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0049'),
      name: 'RestagePrice',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description: 'Locale-aware currency formatting, rendered as text.',
      flutterType:
          'package:restage_core/src/widgets/restage_formatted_number.dart#RestagePrice',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0439'),
          name: 'value',
          type: PropertyType.real,
          description: 'The amount to format. Null renders the empty string.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0440'),
          name: 'numberLocale',
          type: PropertyType.string,
          description:
              'The locale whose conventions govern number formatting — grouping, the decimal mark, digit shaping, and symbol placement (e.g. `en_US`, `de_DE`, `ja_JP`). Null uses the ambient default locale.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0441'),
          name: 'symbol',
          type: PropertyType.string,
          description:
              'The currency symbol or sign to show (e.g. `\$`, `€`, `¥`). Null uses the locale\'s default currency symbol.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0442'),
          name: 'decimalDigits',
          type: PropertyType.integer,
          description:
              'The number of fraction digits (e.g. `2` for most currencies, `0` for JPY, `3` for KWD). Null uses the locale\'s default for the currency.',
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0443'),
          name: 'textAlign',
          type: PropertyType.enumValue,
          description: 'Horizontal alignment of the rendered value.',
          enumType: 'TextAlign',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'TextAlign')),
        ),
        PropertyEntry(
          wireId: WireId('p0444'),
          name: 'maxLines',
          type: PropertyType.integer,
          description: 'Maximum number of lines for the rendered value.',
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0445'),
          name: 'inherit',
          type: PropertyType.boolean,
          description:
              'Whether unset text style values inherit from the parent.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0446'),
          name: 'color',
          type: PropertyType.color,
          description: 'Text color.',
          defaultBrandToken: 'onBackground',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0447'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'Text background color.',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0448'),
          name: 'fontFamily',
          type: PropertyType.string,
          description: 'Primary font family.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0449'),
          name: 'fontSize',
          type: PropertyType.length,
          description: 'Font size in logical pixels.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0450'),
          name: 'fontWeight',
          type: PropertyType.fontWeight,
          description: 'Font weight.',
          valueShape: ScalarShape(
              propertyType: PropertyType.fontWeight,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'FontWeight')),
        ),
        PropertyEntry(
          wireId: WireId('p0451'),
          name: 'fontStyle',
          type: PropertyType.enumValue,
          description: 'Font posture.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'FontStyle')),
        ),
        PropertyEntry(
          wireId: WireId('p0452'),
          name: 'letterSpacing',
          type: PropertyType.length,
          description: 'Horizontal spacing between text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0453'),
          name: 'wordSpacing',
          type: PropertyType.length,
          description: 'Horizontal spacing between words.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0454'),
          name: 'textBaseline',
          type: PropertyType.enumValue,
          description: 'Baseline used to align text.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextBaseline')),
        ),
        PropertyEntry(
          wireId: WireId('p0455'),
          name: 'height',
          type: PropertyType.length,
          description: 'Text line height multiplier.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0456'),
          name: 'leadingDistribution',
          type: PropertyType.enumValue,
          description: 'How leading is distributed above and below text.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui',
                  symbolName: 'TextLeadingDistribution')),
        ),
        PropertyEntry(
          wireId: WireId('p0457'),
          name: 'locale',
          type: PropertyType.locale,
          description: 'Locale used for font selection.',
          valueShape: ScalarShape(
              propertyType: PropertyType.locale,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Locale')),
        ),
        PropertyEntry(
          wireId: WireId('p0458'),
          name: 'foreground',
          type: PropertyType.paint,
          description: 'Paint used to draw text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        PropertyEntry(
          wireId: WireId('p0459'),
          name: 'background',
          type: PropertyType.paint,
          description: 'Paint used behind text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        PropertyEntry(
          wireId: WireId('p0460'),
          name: 'shadows',
          type: PropertyType.shadowList,
          description: 'Shadows painted beneath text glyphs.',
          valueShape: ListShape(
              propertyType: PropertyType.shadowList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.shadowList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'Shadow'))),
        ),
        PropertyEntry(
          wireId: WireId('p0461'),
          name: 'fontFeatures',
          type: PropertyType.fontFeatureList,
          description: 'OpenType font features.',
          valueShape: ListShape(
              propertyType: PropertyType.fontFeatureList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.fontFeatureList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'FontFeature'))),
        ),
        PropertyEntry(
          wireId: WireId('p0462'),
          name: 'fontVariations',
          type: PropertyType.fontVariationList,
          description: 'OpenType font variation axis values.',
          valueShape: ListShape(
              propertyType: PropertyType.fontVariationList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.fontVariationList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'FontVariation'))),
        ),
        PropertyEntry(
          wireId: WireId('p0463'),
          name: 'decoration',
          type: PropertyType.textDecoration,
          description: 'Text decoration lines.',
          valueShape: ScalarShape(
              propertyType: PropertyType.textDecoration,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextDecoration')),
        ),
        PropertyEntry(
          wireId: WireId('p0464'),
          name: 'decorationColor',
          type: PropertyType.color,
          description: 'Text decoration color.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0465'),
          name: 'decorationStyle',
          type: PropertyType.enumValue,
          description: 'Text decoration stroke style.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextDecorationStyle')),
        ),
        PropertyEntry(
          wireId: WireId('p0466'),
          name: 'decorationThickness',
          type: PropertyType.length,
          description: 'Text decoration stroke thickness.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0467'),
          name: 'debugLabel',
          type: PropertyType.string,
          description: 'Debug label for this text style.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0468'),
          name: 'fontFamilyFallback',
          type: PropertyType.stringList,
          description: 'Fallback font families.',
          valueShape: ListShape(
              propertyType: PropertyType.stringList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.string,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'String'))),
        ),
        PropertyEntry(
          wireId: WireId('p0469'),
          name: 'fontPackage',
          type: PropertyType.string,
          description: 'Package that contains the custom font family.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0470'),
          name: 'overflow',
          type: PropertyType.enumValue,
          description: 'Text overflow behavior.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/text_painter.dart',
                  symbolName: 'TextOverflow')),
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0002')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'style',
          construction: FactoryInvocation(
              variantRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('v0001')),
              receiver: ResultStructuredTypeReceiver()),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0190'),
              propertyRef: WireId('p0445'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0169'),
              propertyRef: WireId('p0446'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0191'),
              propertyRef: WireId('p0447'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0192'),
              propertyRef: WireId('p0448'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0167'),
              propertyRef: WireId('p0449'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0168'),
              propertyRef: WireId('p0450'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0282'),
              propertyRef: WireId('p0451'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0193'),
              propertyRef: WireId('p0452'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0194'),
              propertyRef: WireId('p0453'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0283'),
              propertyRef: WireId('p0454'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0195'),
              propertyRef: WireId('p0455'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0284'),
              propertyRef: WireId('p0456'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0285'),
              propertyRef: WireId('p0457'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0286'),
              propertyRef: WireId('p0458'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0287'),
              propertyRef: WireId('p0459'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0288'),
              propertyRef: WireId('p0460'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0289'),
              propertyRef: WireId('p0461'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0290'),
              propertyRef: WireId('p0462'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0291'),
              propertyRef: WireId('p0463'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0196'),
              propertyRef: WireId('p0464'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0292'),
              propertyRef: WireId('p0465'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0197'),
              propertyRef: WireId('p0466'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0198'),
              propertyRef: WireId('p0467'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0293'),
              propertyRef: WireId('p0468'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0294'),
              propertyRef: WireId('p0470'),
              transform: IdentityTransform(),
            ),
          ],
          parameterMappings: [
            DecompositionParameterMapping(
              parameterRef: WireId('a0033'),
              propertyRef: WireId('p0469'),
              transform: IdentityTransform(),
            ),
          ],
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0052'),
      name: 'RestagePulse',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description:
          'Continuously pulses [child] between [minScale] and [maxScale] to draw attention — a subtle "breathing" effect for a call-to-action.',
      flutterType:
          'package:restage_core/src/widgets/restage_pulse.dart#RestagePulse',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0487'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget that pulses.',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0488'),
          name: 'minScale',
          type: PropertyType.real,
          description:
              'The smallest scale in the pulse. Defaults to a subtle `0.97`.',
          defaultSource: LiteralDefault(0.97),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0489'),
          name: 'maxScale',
          type: PropertyType.real,
          description:
              'The largest scale in the pulse. Defaults to a subtle `1.03`.',
          defaultSource: LiteralDefault(1.03),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0490'),
          name: 'period',
          type: PropertyType.duration,
          description:
              'The duration of a single sweep between [minScale] and [maxScale]; a full pulse (out and back) takes two sweeps. Null uses [defaultPeriod] (1200ms).',
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0491'),
          name: 'curve',
          type: PropertyType.curve,
          description:
              'The easing of each sweep. Defaults to [Curves.easeInOut].',
          defaultSource: LiteralDefault('easeInOut'),
          valueShape: ScalarShape(
              propertyType: PropertyType.curve,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/animation/curves.dart',
                  symbolName: 'Curve')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0053'),
      name: 'RestageStagger',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'Reveals a vertical list of [children] with a cascading entrance — each child springs into place ([RestageMotion]\'s entrance), delayed by [delayBetween] times its index, so the list flows in rather than appearing at once.',
      flutterType:
          'package:restage_core/src/widgets/restage_stagger.dart#RestageStagger',
      childrenSlot: ChildrenSlot.list,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0492'),
          name: 'children',
          type: PropertyType.widgetList,
          description: 'The children revealed in order, top to bottom.',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0493'),
          name: 'delayBetween',
          type: PropertyType.duration,
          description:
              'The delay added per child — child `i` starts after `delayBetween * i`. Null uses [defaultDelayBetween] (60ms). Clamped to a safe range so a pathological value cannot overflow the per-child delay.',
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0494'),
          name: 'spring',
          type: PropertyType.enumValue,
          description:
              'The spring feel each child enters with. Defaults to [RestageSpring.smooth].',
          enumType: 'RestageSpring',
          defaultSource: LiteralDefault('smooth'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri:
                      'package:restage_core/src/widgets/restage_spring.dart',
                  symbolName: 'RestageSpring')),
        ),
        PropertyEntry(
          wireId: WireId('p0495'),
          name: 'fromOffset',
          type: PropertyType.offset,
          description:
              'The translation (in logical pixels) each child enters from. Defaults to `Offset.zero` (a pure fade stagger).',
          defaultSource: LiteralDefault('zero'),
          valueShape: ScalarShape(
              propertyType: PropertyType.offset,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Offset')),
        ),
        PropertyEntry(
          wireId: WireId('p0496'),
          name: 'fromOpacity',
          type: PropertyType.real,
          description:
              'The opacity each child enters from. Defaults to `0.0` (fade in).',
          defaultSource: LiteralDefault(0.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0497'),
          name: 'fromScale',
          type: PropertyType.real,
          description:
              'The scale each child enters from. Defaults to `1.0` (no scale).',
          defaultSource: LiteralDefault(1.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0022'),
      name: 'Opacity',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description: 'A widget that makes its child partially transparent.',
      flutterType: 'package:flutter/src/widgets/basic.dart#Opacity',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0102'),
          name: 'opacity',
          type: PropertyType.real,
          description: 'The fraction to scale the child\'s alpha value.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0103'),
          name: 'alwaysIncludeSemantics',
          type: PropertyType.boolean,
          description:
              'Whether the semantic information of the children is always included.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0104'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0023'),
      name: 'Padding',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description: 'A widget that insets its child by the given padding.',
      flutterType: 'package:flutter/src/widgets/basic.dart#Padding',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0105'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description: 'The amount of space by which to inset the child.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0106'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0024'),
      name: 'Positioned',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'A widget that controls where a child of a [Stack] is positioned.',
      flutterType: 'package:flutter/src/widgets/basic.dart#Positioned',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0107'),
          name: 'left',
          type: PropertyType.length,
          description:
              'The distance that the child\'s left edge is inset from the left of the stack.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0108'),
          name: 'top',
          type: PropertyType.length,
          description:
              'The distance that the child\'s top edge is inset from the top of the stack.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0109'),
          name: 'right',
          type: PropertyType.length,
          description:
              'The distance that the child\'s right edge is inset from the right of the stack.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0110'),
          name: 'bottom',
          type: PropertyType.length,
          description:
              'The distance that the child\'s bottom edge is inset from the bottom of the stack.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0111'),
          name: 'width',
          type: PropertyType.length,
          description: 'The child\'s width.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0112'),
          name: 'height',
          type: PropertyType.length,
          description: 'The child\'s height.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0113'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0025'),
      name: 'Row',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description: 'A widget that displays its children in a horizontal array.',
      flutterType: 'package:flutter/src/widgets/basic.dart#Row',
      childrenSlot: ChildrenSlot.list,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0114'),
          name: 'mainAxisAlignment',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'MainAxisAlignment',
          defaultSource: LiteralDefault('start'),
          category: PropertyCategory.layout,
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/rendering/flex.dart',
                  symbolName: 'MainAxisAlignment')),
        ),
        PropertyEntry(
          wireId: WireId('p0115'),
          name: 'mainAxisSize',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'MainAxisSize',
          defaultSource: LiteralDefault('max'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/rendering/flex.dart',
                  symbolName: 'MainAxisSize')),
        ),
        PropertyEntry(
          wireId: WireId('p0116'),
          name: 'crossAxisAlignment',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'CrossAxisAlignment',
          defaultSource: LiteralDefault('center'),
          category: PropertyCategory.layout,
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/rendering/flex.dart',
                  symbolName: 'CrossAxisAlignment')),
        ),
        PropertyEntry(
          wireId: WireId('p0542'),
          name: 'spacing',
          type: PropertyType.real,
          description: '',
          defaultSource: LiteralDefault(0.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0117'),
          name: 'children',
          type: PropertyType.widgetList,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0026'),
      name: 'RotatedBox',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description:
          'A widget that rotates its child by a integral number of quarter turns.',
      flutterType: 'package:flutter/src/widgets/basic.dart#RotatedBox',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0118'),
          name: 'quarterTurns',
          type: PropertyType.integer,
          description:
              'The number of clockwise quarter turns the child should be rotated.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0119'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0027'),
      name: 'SafeArea',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'A widget that insets its child with sufficient padding to avoid intrusions by the operating system.',
      flutterType: 'package:flutter/src/widgets/safe_area.dart#SafeArea',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0120'),
          name: 'left',
          type: PropertyType.boolean,
          description: 'Whether to avoid system intrusions on the left.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0121'),
          name: 'top',
          type: PropertyType.boolean,
          description:
              'Whether to avoid system intrusions at the top of the screen, typically the system status bar.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0122'),
          name: 'right',
          type: PropertyType.boolean,
          description: 'Whether to avoid system intrusions on the right.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0123'),
          name: 'bottom',
          type: PropertyType.boolean,
          description:
              'Whether to avoid system intrusions on the bottom side of the screen.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0124'),
          name: 'maintainBottomViewPadding',
          type: PropertyType.boolean,
          description:
              'Specifies whether the [SafeArea] should maintain the bottom [MediaQueryData.viewPadding] instead of the bottom [MediaQueryData.padding], defaults to false.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0125'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
          required: true,
          priority: PropertyPriority.primary,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0028'),
      name: 'SingleChildScrollView',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description: 'A box in which a single widget can be scrolled.',
      flutterType:
          'package:flutter/src/widgets/single_child_scroll_view.dart#SingleChildScrollView',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0126'),
          name: 'scrollDirection',
          type: PropertyType.enumValue,
          description: '{@macro flutter.widgets.scroll_view.scrollDirection}',
          enumType: 'Axis',
          defaultSource: LiteralDefault('vertical'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/basic_types.dart',
                  symbolName: 'Axis')),
        ),
        PropertyEntry(
          wireId: WireId('p0127'),
          name: 'reverse',
          type: PropertyType.boolean,
          description:
              'Whether the scroll view scrolls in the reading direction.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0128'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description: 'The amount of space by which to inset the child.',
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0129'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget that scrolls.',
        ),
        PropertyEntry(
          wireId: WireId('p0551'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '{@macro flutter.material.Material.clipBehavior}',
          enumType: 'Clip',
          defaultSource: LiteralDefault('hardEdge'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0499'),
          name: 'keyboardDismissBehavior',
          type: PropertyType.enumValue,
          description:
              '{@macro flutter.widgets.scroll_view.keyboardDismissBehavior}',
          enumType: 'ScrollViewKeyboardDismissBehavior',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/widgets/scroll_view.dart',
                  symbolName: 'ScrollViewKeyboardDismissBehavior')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0029'),
      name: 'SizedBox',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description: 'A box with a specified size.',
      flutterType: 'package:flutter/src/widgets/basic.dart#SizedBox',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0130'),
          name: 'width',
          type: PropertyType.length,
          description:
              'If non-null, requires the child to have exactly this width.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0131'),
          name: 'height',
          type: PropertyType.length,
          description:
              'If non-null, requires the child to have exactly this height.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0132'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0030'),
      name: 'Spacer',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'Spacer creates an adjustable, empty spacer that can be used to tune the spacing between widgets in a [Flex] container, like [Row] or [Column].',
      flutterType: 'package:flutter/src/widgets/spacer.dart#Spacer',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0133'),
          name: 'flex',
          type: PropertyType.integer,
          description:
              'The flex factor to use in determining how much space to take up.',
          defaultSource: LiteralDefault(1),
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0031'),
      name: 'Stack',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'A widget that positions its children relative to the edges of its box.',
      flutterType: 'package:flutter/src/widgets/basic.dart#Stack',
      childrenSlot: ChildrenSlot.list,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0134'),
          name: 'alignment',
          type: PropertyType.alignment,
          description:
              'How to align the non-positioned and partially-positioned children in the stack.',
          defaultSource: LiteralDefault('topStart'),
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0135'),
          name: 'fit',
          type: PropertyType.enumValue,
          description: 'How to size the non-positioned children in the stack.',
          enumType: 'StackFit',
          defaultSource: LiteralDefault('loose'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/rendering/stack.dart',
                  symbolName: 'StackFit')),
        ),
        PropertyEntry(
          wireId: WireId('p0552'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '{@macro flutter.material.Material.clipBehavior}',
          enumType: 'Clip',
          defaultSource: LiteralDefault('hardEdge'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0136'),
          name: 'children',
          type: PropertyType.widgetList,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0032'),
      name: 'Text',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description: 'Static text with optional styling.',
      flutterType: 'package:flutter/src/widgets/text.dart#Text',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0137'),
          name: 'text',
          type: PropertyType.string,
          description: 'The text to display.',
          required: true,
          positional: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0138'),
          name: 'textAlign',
          type: PropertyType.enumValue,
          description: 'How the text should be aligned horizontally.',
          enumType: 'TextAlign',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'TextAlign')),
        ),
        PropertyEntry(
          wireId: WireId('p0543'),
          name: 'softWrap',
          type: PropertyType.boolean,
          description: 'Whether the text should break at soft line breaks.',
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0139'),
          name: 'maxLines',
          type: PropertyType.integer,
          description:
              'An optional maximum number of lines for the text to span, wrapping if necessary. If the text exceeds the given number of lines, it will be truncated according to [overflow].',
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0544'),
          name: 'semanticsLabel',
          type: PropertyType.string,
          description:
              '{@template flutter.widgets.Text.semanticsLabel} An alternative semantics label for this text.',
          category: PropertyCategory.accessibility,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0545'),
          name: 'textWidthBasis',
          type: PropertyType.enumValue,
          description: '{@macro flutter.painting.textPainter.textWidthBasis}',
          enumType: 'TextWidthBasis',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/text_painter.dart',
                  symbolName: 'TextWidthBasis')),
        ),
        PropertyEntry(
          wireId: WireId('p0261'),
          name: 'inherit',
          type: PropertyType.boolean,
          description:
              'Whether unset text style values inherit from the parent.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0142'),
          name: 'color',
          type: PropertyType.color,
          description: 'Text color.',
          defaultBrandToken: 'onBackground',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0262'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'Text background color.',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0263'),
          name: 'fontFamily',
          type: PropertyType.string,
          description: 'Primary font family.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0140'),
          name: 'fontSize',
          type: PropertyType.length,
          description: 'Font size in logical pixels.',
          defaultSource: ThemeBindingDefault(
              ThemeBindingPath.path('defaultTextStyle.fontSize')),
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0141'),
          name: 'fontWeight',
          type: PropertyType.fontWeight,
          description: 'Font weight.',
          defaultSource: ThemeBindingDefault(
              ThemeBindingPath.path('defaultTextStyle.fontWeight')),
          valueShape: ScalarShape(
              propertyType: PropertyType.fontWeight,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'FontWeight')),
        ),
        PropertyEntry(
          wireId: WireId('p0264'),
          name: 'fontStyle',
          type: PropertyType.enumValue,
          description: 'Font posture.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'FontStyle')),
        ),
        PropertyEntry(
          wireId: WireId('p0239'),
          name: 'letterSpacing',
          type: PropertyType.length,
          description: 'Horizontal spacing between text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0265'),
          name: 'wordSpacing',
          type: PropertyType.length,
          description: 'Horizontal spacing between words.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0266'),
          name: 'textBaseline',
          type: PropertyType.enumValue,
          description: 'Baseline used to align text.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextBaseline')),
        ),
        PropertyEntry(
          wireId: WireId('p0240'),
          name: 'height',
          type: PropertyType.length,
          description: 'Text line height multiplier.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0267'),
          name: 'leadingDistribution',
          type: PropertyType.enumValue,
          description: 'How leading is distributed above and below text.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui',
                  symbolName: 'TextLeadingDistribution')),
        ),
        PropertyEntry(
          wireId: WireId('p0268'),
          name: 'locale',
          type: PropertyType.locale,
          description: 'Locale used for font selection.',
          valueShape: ScalarShape(
              propertyType: PropertyType.locale,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Locale')),
        ),
        PropertyEntry(
          wireId: WireId('p0269'),
          name: 'foreground',
          type: PropertyType.paint,
          description: 'Paint used to draw text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        PropertyEntry(
          wireId: WireId('p0270'),
          name: 'background',
          type: PropertyType.paint,
          description: 'Paint used behind text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        PropertyEntry(
          wireId: WireId('p0271'),
          name: 'shadows',
          type: PropertyType.shadowList,
          description: 'Shadows painted beneath text glyphs.',
          valueShape: ListShape(
              propertyType: PropertyType.shadowList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.shadowList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'Shadow'))),
        ),
        PropertyEntry(
          wireId: WireId('p0272'),
          name: 'fontFeatures',
          type: PropertyType.fontFeatureList,
          description: 'OpenType font features.',
          valueShape: ListShape(
              propertyType: PropertyType.fontFeatureList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.fontFeatureList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'FontFeature'))),
        ),
        PropertyEntry(
          wireId: WireId('p0273'),
          name: 'fontVariations',
          type: PropertyType.fontVariationList,
          description: 'OpenType font variation axis values.',
          valueShape: ListShape(
              propertyType: PropertyType.fontVariationList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.fontVariationList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'FontVariation'))),
        ),
        PropertyEntry(
          wireId: WireId('p0274'),
          name: 'decoration',
          type: PropertyType.textDecoration,
          description: 'Text decoration lines.',
          valueShape: ScalarShape(
              propertyType: PropertyType.textDecoration,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextDecoration')),
        ),
        PropertyEntry(
          wireId: WireId('p0275'),
          name: 'decorationColor',
          type: PropertyType.color,
          description: 'Text decoration color.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0276'),
          name: 'decorationStyle',
          type: PropertyType.enumValue,
          description: 'Text decoration stroke style.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextDecorationStyle')),
        ),
        PropertyEntry(
          wireId: WireId('p0277'),
          name: 'decorationThickness',
          type: PropertyType.length,
          description: 'Text decoration stroke thickness.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0278'),
          name: 'debugLabel',
          type: PropertyType.string,
          description: 'Debug label for this text style.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0279'),
          name: 'fontFamilyFallback',
          type: PropertyType.stringList,
          description: 'Fallback font families.',
          valueShape: ListShape(
              propertyType: PropertyType.stringList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.string,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'String'))),
        ),
        PropertyEntry(
          wireId: WireId('p0280'),
          name: 'fontPackage',
          type: PropertyType.string,
          description: 'Package that contains the custom font family.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0281'),
          name: 'overflow',
          type: PropertyType.enumValue,
          description: 'Text overflow behavior.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/text_painter.dart',
                  symbolName: 'TextOverflow')),
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0002')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'style',
          construction: FactoryInvocation(
              variantRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('v0001')),
              receiver: ResultStructuredTypeReceiver()),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0190'),
              propertyRef: WireId('p0261'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0169'),
              propertyRef: WireId('p0142'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0191'),
              propertyRef: WireId('p0262'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0192'),
              propertyRef: WireId('p0263'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0167'),
              propertyRef: WireId('p0140'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0168'),
              propertyRef: WireId('p0141'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0282'),
              propertyRef: WireId('p0264'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0193'),
              propertyRef: WireId('p0239'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0194'),
              propertyRef: WireId('p0265'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0283'),
              propertyRef: WireId('p0266'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0195'),
              propertyRef: WireId('p0240'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0284'),
              propertyRef: WireId('p0267'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0285'),
              propertyRef: WireId('p0268'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0286'),
              propertyRef: WireId('p0269'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0287'),
              propertyRef: WireId('p0270'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0288'),
              propertyRef: WireId('p0271'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0289'),
              propertyRef: WireId('p0272'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0290'),
              propertyRef: WireId('p0273'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0291'),
              propertyRef: WireId('p0274'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0196'),
              propertyRef: WireId('p0275'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0292'),
              propertyRef: WireId('p0276'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0197'),
              propertyRef: WireId('p0277'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0198'),
              propertyRef: WireId('p0278'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0293'),
              propertyRef: WireId('p0279'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0294'),
              propertyRef: WireId('p0281'),
              transform: IdentityTransform(),
            ),
          ],
          parameterMappings: [
            DecompositionParameterMapping(
              parameterRef: WireId('a0033'),
              propertyRef: WireId('p0280'),
              transform: IdentityTransform(),
            ),
          ],
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0054'),
      name: 'TextRich',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description:
          'Rich text — a styled inline-span tree with optional styling.',
      flutterType: 'package:flutter/src/widgets/text.dart#Text.rich',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0500'),
          name: 'textSpan',
          type: PropertyType.inlineSpan,
          description: 'The text to display as a [InlineSpan].',
          required: true,
          positional: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0501'),
          name: 'textAlign',
          type: PropertyType.enumValue,
          description: 'How the text should be aligned horizontally.',
          enumType: 'TextAlign',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'TextAlign')),
        ),
        PropertyEntry(
          wireId: WireId('p0546'),
          name: 'softWrap',
          type: PropertyType.boolean,
          description: 'Whether the text should break at soft line breaks.',
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0502'),
          name: 'maxLines',
          type: PropertyType.integer,
          description:
              'An optional maximum number of lines for the text to span, wrapping if necessary. If the text exceeds the given number of lines, it will be truncated according to [overflow].',
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0547'),
          name: 'semanticsLabel',
          type: PropertyType.string,
          description:
              '{@template flutter.widgets.Text.semanticsLabel} An alternative semantics label for this text.',
          category: PropertyCategory.accessibility,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0548'),
          name: 'textWidthBasis',
          type: PropertyType.enumValue,
          description: '{@macro flutter.painting.textPainter.textWidthBasis}',
          enumType: 'TextWidthBasis',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/text_painter.dart',
                  symbolName: 'TextWidthBasis')),
        ),
        PropertyEntry(
          wireId: WireId('p0503'),
          name: 'inherit',
          type: PropertyType.boolean,
          description:
              'Whether unset text style values inherit from the parent.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0504'),
          name: 'color',
          type: PropertyType.color,
          description: 'Text color.',
          defaultBrandToken: 'onBackground',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0505'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'Text background color.',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0506'),
          name: 'fontFamily',
          type: PropertyType.string,
          description: 'Primary font family.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0507'),
          name: 'fontSize',
          type: PropertyType.length,
          description: 'Font size in logical pixels.',
          defaultSource: ThemeBindingDefault(
              ThemeBindingPath.path('defaultTextStyle.fontSize')),
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0508'),
          name: 'fontWeight',
          type: PropertyType.fontWeight,
          description: 'Font weight.',
          defaultSource: ThemeBindingDefault(
              ThemeBindingPath.path('defaultTextStyle.fontWeight')),
          valueShape: ScalarShape(
              propertyType: PropertyType.fontWeight,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'FontWeight')),
        ),
        PropertyEntry(
          wireId: WireId('p0509'),
          name: 'fontStyle',
          type: PropertyType.enumValue,
          description: 'Font posture.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'FontStyle')),
        ),
        PropertyEntry(
          wireId: WireId('p0510'),
          name: 'letterSpacing',
          type: PropertyType.length,
          description: 'Horizontal spacing between text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0511'),
          name: 'wordSpacing',
          type: PropertyType.length,
          description: 'Horizontal spacing between words.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0512'),
          name: 'textBaseline',
          type: PropertyType.enumValue,
          description: 'Baseline used to align text.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextBaseline')),
        ),
        PropertyEntry(
          wireId: WireId('p0513'),
          name: 'height',
          type: PropertyType.length,
          description: 'Text line height multiplier.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0514'),
          name: 'leadingDistribution',
          type: PropertyType.enumValue,
          description: 'How leading is distributed above and below text.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui',
                  symbolName: 'TextLeadingDistribution')),
        ),
        PropertyEntry(
          wireId: WireId('p0515'),
          name: 'locale',
          type: PropertyType.locale,
          description: 'Locale used for font selection.',
          valueShape: ScalarShape(
              propertyType: PropertyType.locale,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Locale')),
        ),
        PropertyEntry(
          wireId: WireId('p0516'),
          name: 'foreground',
          type: PropertyType.paint,
          description: 'Paint used to draw text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        PropertyEntry(
          wireId: WireId('p0517'),
          name: 'background',
          type: PropertyType.paint,
          description: 'Paint used behind text glyphs.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        PropertyEntry(
          wireId: WireId('p0518'),
          name: 'shadows',
          type: PropertyType.shadowList,
          description: 'Shadows painted beneath text glyphs.',
          valueShape: ListShape(
              propertyType: PropertyType.shadowList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.shadowList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'Shadow'))),
        ),
        PropertyEntry(
          wireId: WireId('p0519'),
          name: 'fontFeatures',
          type: PropertyType.fontFeatureList,
          description: 'OpenType font features.',
          valueShape: ListShape(
              propertyType: PropertyType.fontFeatureList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.fontFeatureList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'FontFeature'))),
        ),
        PropertyEntry(
          wireId: WireId('p0520'),
          name: 'fontVariations',
          type: PropertyType.fontVariationList,
          description: 'OpenType font variation axis values.',
          valueShape: ListShape(
              propertyType: PropertyType.fontVariationList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.fontVariationList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'FontVariation'))),
        ),
        PropertyEntry(
          wireId: WireId('p0521'),
          name: 'decoration',
          type: PropertyType.textDecoration,
          description: 'Text decoration lines.',
          valueShape: ScalarShape(
              propertyType: PropertyType.textDecoration,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextDecoration')),
        ),
        PropertyEntry(
          wireId: WireId('p0522'),
          name: 'decorationColor',
          type: PropertyType.color,
          description: 'Text decoration color.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0523'),
          name: 'decorationStyle',
          type: PropertyType.enumValue,
          description: 'Text decoration stroke style.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextDecorationStyle')),
        ),
        PropertyEntry(
          wireId: WireId('p0524'),
          name: 'decorationThickness',
          type: PropertyType.length,
          description: 'Text decoration stroke thickness.',
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0525'),
          name: 'debugLabel',
          type: PropertyType.string,
          description: 'Debug label for this text style.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0526'),
          name: 'fontFamilyFallback',
          type: PropertyType.stringList,
          description: 'Fallback font families.',
          valueShape: ListShape(
              propertyType: PropertyType.stringList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.string,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'String'))),
        ),
        PropertyEntry(
          wireId: WireId('p0527'),
          name: 'fontPackage',
          type: PropertyType.string,
          description: 'Package that contains the custom font family.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0528'),
          name: 'overflow',
          type: PropertyType.enumValue,
          description: 'Text overflow behavior.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/text_painter.dart',
                  symbolName: 'TextOverflow')),
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0002')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'style',
          construction: FactoryInvocation(
              variantRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('v0001')),
              receiver: ResultStructuredTypeReceiver()),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0190'),
              propertyRef: WireId('p0503'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0169'),
              propertyRef: WireId('p0504'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0191'),
              propertyRef: WireId('p0505'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0192'),
              propertyRef: WireId('p0506'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0167'),
              propertyRef: WireId('p0507'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0168'),
              propertyRef: WireId('p0508'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0282'),
              propertyRef: WireId('p0509'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0193'),
              propertyRef: WireId('p0510'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0194'),
              propertyRef: WireId('p0511'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0283'),
              propertyRef: WireId('p0512'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0195'),
              propertyRef: WireId('p0513'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0284'),
              propertyRef: WireId('p0514'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0285'),
              propertyRef: WireId('p0515'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0286'),
              propertyRef: WireId('p0516'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0287'),
              propertyRef: WireId('p0517'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0288'),
              propertyRef: WireId('p0518'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0289'),
              propertyRef: WireId('p0519'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0290'),
              propertyRef: WireId('p0520'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0291'),
              propertyRef: WireId('p0521'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0196'),
              propertyRef: WireId('p0522'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0292'),
              propertyRef: WireId('p0523'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0197'),
              propertyRef: WireId('p0524'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0198'),
              propertyRef: WireId('p0525'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0293'),
              propertyRef: WireId('p0526'),
              transform:
                  ProjectListTransform(itemTransform: IdentityTransform()),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0294'),
              propertyRef: WireId('p0528'),
              transform: IdentityTransform(),
            ),
          ],
          parameterMappings: [
            DecompositionParameterMapping(
              parameterRef: WireId('a0033'),
              propertyRef: WireId('p0527'),
              transform: IdentityTransform(),
            ),
          ],
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0033'),
      name: 'TransformRotate',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description:
          'A widget that applies a transformation before painting its child.',
      flutterType: 'package:flutter/src/widgets/basic.dart#Transform.rotate',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0143'),
          name: 'angle',
          type: PropertyType.real,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0408'),
          name: 'origin',
          type: PropertyType.offset,
          description:
              'The origin of the coordinate system in which to apply the matrix, described relative to the point given by [alignment].',
          valueShape: ScalarShape(
              propertyType: PropertyType.offset,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Offset')),
        ),
        PropertyEntry(
          wireId: WireId('p0144'),
          name: 'alignment',
          type: PropertyType.alignment,
          description:
              'The alignment of the origin, relative to the size of the box.',
          defaultSource: LiteralDefault('center'),
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0145'),
          name: 'transformHitTests',
          type: PropertyType.boolean,
          description:
              'Whether to transform registered hits into the child\'s resulting coordinate system.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0146'),
          name: 'filterQuality',
          type: PropertyType.enumValue,
          description:
              'The filter quality with which to apply the transform as a bitmap operation.',
          enumType: 'FilterQuality',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'FilterQuality')),
        ),
        PropertyEntry(
          wireId: WireId('p0147'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0034'),
      name: 'Visibility',
      library: WidgetLibrary.core,
      category: WidgetCategory.decoration,
      description: 'Whether to show or hide a child.',
      flutterType: 'package:flutter/src/widgets/visibility.dart#Visibility',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0148'),
          name: 'child',
          type: PropertyType.widget,
          description:
              'The widget to show or hide, as controlled by [visible].',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0149'),
          name: 'visible',
          type: PropertyType.boolean,
          description: 'Switches between showing the [child] or hiding it.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0150'),
          name: 'maintainFocusability',
          type: PropertyType.boolean,
          description:
              'Whether to allow the widget to receive focus when hidden. Only in effect if [visible] is false.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0035'),
      name: 'Wrap',
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description:
          'A widget that displays its children in multiple horizontal or vertical runs.',
      flutterType: 'package:flutter/src/widgets/basic.dart#Wrap',
      childrenSlot: ChildrenSlot.list,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0151'),
          name: 'direction',
          type: PropertyType.enumValue,
          description: 'The direction to use as the main axis.',
          enumType: 'Axis',
          defaultSource: LiteralDefault('horizontal'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/basic_types.dart',
                  symbolName: 'Axis')),
        ),
        PropertyEntry(
          wireId: WireId('p0152'),
          name: 'alignment',
          type: PropertyType.enumValue,
          description:
              'How the children within a run should be placed in the main axis.',
          enumType: 'WrapAlignment',
          defaultSource: LiteralDefault('start'),
          category: PropertyCategory.layout,
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/rendering/wrap.dart',
                  symbolName: 'WrapAlignment')),
        ),
        PropertyEntry(
          wireId: WireId('p0153'),
          name: 'spacing',
          type: PropertyType.length,
          description:
              'How much space to place between children in a run in the main axis.',
          defaultSource: LiteralDefault(0.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0154'),
          name: 'runAlignment',
          type: PropertyType.enumValue,
          description:
              'How the runs themselves should be placed in the cross axis.',
          enumType: 'WrapAlignment',
          defaultSource: LiteralDefault('start'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/rendering/wrap.dart',
                  symbolName: 'WrapAlignment')),
        ),
        PropertyEntry(
          wireId: WireId('p0155'),
          name: 'runSpacing',
          type: PropertyType.length,
          description:
              'How much space to place between the runs themselves in the cross axis.',
          defaultSource: LiteralDefault(0.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0156'),
          name: 'crossAxisAlignment',
          type: PropertyType.enumValue,
          description:
              'How the children within a run should be aligned relative to each other in the cross axis.',
          enumType: 'WrapCrossAlignment',
          defaultSource: LiteralDefault('start'),
          category: PropertyCategory.layout,
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/rendering/wrap.dart',
                  symbolName: 'WrapCrossAlignment')),
        ),
        PropertyEntry(
          wireId: WireId('p0157'),
          name: 'textDirection',
          type: PropertyType.enumValue,
          description:
              'Determines the order to lay children out horizontally and how to interpret `start` and `end` in the horizontal direction.',
          enumType: 'TextDirection',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextDirection')),
        ),
        PropertyEntry(
          wireId: WireId('p0158'),
          name: 'verticalDirection',
          type: PropertyType.enumValue,
          description:
              'Determines the order to lay children out vertically and how to interpret `start` and `end` in the vertical direction.',
          enumType: 'VerticalDirection',
          defaultSource: LiteralDefault('down'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/basic_types.dart',
                  symbolName: 'VerticalDirection')),
        ),
        PropertyEntry(
          wireId: WireId('p0159'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '{@macro flutter.material.Material.clipBehavior}',
          enumType: 'Clip',
          defaultSource: LiteralDefault('none'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0160'),
          name: 'children',
          type: PropertyType.widgetList,
          description: '',
        ),
      ],
    ),
  ],
  structuredTypes: [
    StructuredEntry(
      wireId: WireId('s0009'),
      name: 'Decoration',
      library: WidgetLibrary.core,
      description:
          'A description of a box decoration (a decoration applied to a [Rect]).',
      sourceType: 'package:flutter/src/painting/decoration.dart#Decoration',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0001'),
      name: 'BoxDecoration',
      library: WidgetLibrary.core,
      description: 'An immutable description of how to paint a box.',
      sourceType:
          'package:flutter/src/painting/box_decoration.dart#BoxDecoration',
      fields: [
        StructuredField(
          wireId: WireId('p0161'),
          name: 'color',
          type: PropertyType.color,
          description: 'The color to fill in the background of the box.',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        StructuredField(
          wireId: WireId('p0164'),
          name: 'border',
          type: PropertyType.border,
          description:
              'A border to draw above the background [color], [gradient], or [image].',
          unionRef: WireIdRef(library: 'restage.core', wireId: WireId('u0004')),
          valueShape: UnionShape(
              propertyType: PropertyType.border,
              unionRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('u0004')),
              wireCodec: CatalogWireCodec.rfwBorder),
        ),
        StructuredField(
          wireId: WireId('p0163'),
          name: 'gradient',
          type: PropertyType.gradient,
          description: 'A gradient to use when filling the box.',
          unionRef: WireIdRef(library: 'restage.core', wireId: WireId('u0003')),
          valueShape: UnionShape(
              propertyType: PropertyType.gradient,
              unionRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('u0003')),
              wireCodec: CatalogWireCodec.rfwGradient),
        ),
        StructuredField(
          wireId: WireId('p0306'),
          name: 'backgroundBlendMode',
          type: PropertyType.enumValue,
          description:
              'The blend mode applied to the [color] or [gradient] background of the box.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'BlendMode')),
        ),
        StructuredField(
          wireId: WireId('p0166'),
          name: 'shape',
          type: PropertyType.enumValue,
          description:
              'The shape to fill the background [color], [gradient], and [image] into and to cast as the [boxShadow].',
          defaultSource: LiteralDefault('rectangle'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/box_border.dart',
                  symbolName: 'BoxShape')),
        ),
        StructuredField(
          wireId: WireId('p0579'),
          name: 'image',
          type: PropertyType.decorationImage,
          description:
              'Background image painted behind the child (NetworkImage / AssetImage supported).',
          valueShape: ScalarShape(
              propertyType: PropertyType.decorationImage,
              dartTypeRef: DartTypeRef(
                  libraryUri:
                      'package:flutter/src/painting/decoration_image.dart',
                  symbolName: 'DecorationImage')),
        ),
        StructuredField(
          wireId: WireId('p0162'),
          name: 'borderRadius',
          type: PropertyType.structured,
          description: 'Uniform corner radius applied to all four corners.',
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('s0003'))),
        ),
        StructuredField(
          wireId: WireId('p0165'),
          name: 'boxShadow',
          type: PropertyType.boxShadowList,
          description: 'List of shadows painted behind the box.',
          valueShape: ListShape(
              propertyType: PropertyType.boxShadowList,
              itemShape: StructuredShape(
                  propertyType: PropertyType.structured,
                  structuredRef: WireIdRef(
                      library: 'restage.core', wireId: WireId('s0007'))),
              wireCodec: CatalogWireCodec.rfwBoxShadowList),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0002'),
          argMappings: {
            'backgroundBlendMode': ArgMapping(targetFields: [WireId('p0306')]),
            'border': ArgMapping(targetFields: [WireId('p0164')]),
            'borderRadius': ArgMapping(targetFields: [WireId('p0162')]),
            'boxShadow': ArgMapping(targetFields: [WireId('p0165')]),
            'color': ArgMapping(targetFields: [WireId('p0161')]),
            'gradient': ArgMapping(targetFields: [WireId('p0163')]),
            'image': ArgMapping(targetFields: [WireId('p0579')]),
            'shape': ArgMapping(targetFields: [WireId('p0166')]),
          },
          parameters: [
            FactoryParameter(
              wireId: WireId('a0001'),
              name: 'color',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.color,
                  dartTypeRef:
                      DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
            ),
            FactoryParameter(
              wireId: WireId('a0038'),
              name: 'image',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.decorationImage,
                  dartTypeRef: DartTypeRef(
                      libraryUri:
                          'package:flutter/src/painting/decoration_image.dart',
                      symbolName: 'DecorationImage')),
            ),
            FactoryParameter(
              wireId: WireId('a0008'),
              name: 'border',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: UnionShape(
                  propertyType: PropertyType.border,
                  unionRef: WireIdRef(
                      library: 'restage.core', wireId: WireId('u0004')),
                  wireCodec: CatalogWireCodec.rfwBorder),
            ),
            FactoryParameter(
              wireId: WireId('a0009'),
              name: 'borderRadius',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: StructuredShape(
                  propertyType: PropertyType.structured,
                  structuredRef: WireIdRef(
                      library: 'restage.core', wireId: WireId('s0003'))),
            ),
            FactoryParameter(
              wireId: WireId('a0010'),
              name: 'boxShadow',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ListShape(
                  propertyType: PropertyType.boxShadowList,
                  itemShape: StructuredShape(
                      propertyType: PropertyType.structured,
                      structuredRef: WireIdRef(
                          library: 'restage.core', wireId: WireId('s0007'))),
                  wireCodec: CatalogWireCodec.rfwBoxShadowList),
            ),
            FactoryParameter(
              wireId: WireId('a0007'),
              name: 'gradient',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: UnionShape(
                  propertyType: PropertyType.gradient,
                  unionRef: WireIdRef(
                      library: 'restage.core', wireId: WireId('u0003')),
                  wireCodec: CatalogWireCodec.rfwGradient),
            ),
            FactoryParameter(
              wireId: WireId('a0002'),
              name: 'shape',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: false,
              defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
              defaultValue: LiteralParameterDefault('rectangle'),
              valueShape: EnumShape(
                  propertyType: PropertyType.enumValue,
                  enumRef: DartTypeRef(
                      libraryUri:
                          'package:flutter/src/painting/box_border.dart',
                      symbolName: 'BoxShape')),
            ),
          ],
          description: 'Creates a box decoration.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0021'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two box decorations.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0007'),
      name: 'BoxShadow',
      library: WidgetLibrary.core,
      description: 'BoxShadow value.',
      sourceType: 'package:flutter/src/painting/box_shadow.dart#BoxShadow',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0003'),
      name: 'BorderRadius',
      library: WidgetLibrary.core,
      description: 'BorderRadius value.',
      sourceType:
          'package:flutter/src/painting/border_radius.dart#BorderRadius',
      fields: [],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0003'),
          namedConstructor: 'circular',
          parameters: [
            FactoryParameter(
              wireId: WireId('a0003'),
              position: 0,
              kind: FactoryParameterKind.positional,
              required: true,
              nullable: false,
              defaultPolicy: FactoryParameterDefaultPolicy.requiredValue,
              valueShape: ScalarShape(
                  propertyType: PropertyType.real,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'double')),
            ),
          ],
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0028'),
      name: 'BoxConstraints',
      library: WidgetLibrary.core,
      description: 'BoxConstraints value.',
      sourceType: 'package:flutter/src/rendering/box.dart#BoxConstraints',
      fields: [
        StructuredField(
          wireId: WireId('p0561'),
          name: 'minWidth',
          type: PropertyType.real,
          description: 'Minimum width the box may have.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0562'),
          name: 'maxWidth',
          type: PropertyType.real,
          description: 'Maximum width the box may have.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0563'),
          name: 'minHeight',
          type: PropertyType.real,
          description: 'Minimum height the box may have.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0564'),
          name: 'maxHeight',
          type: PropertyType.real,
          description: 'Maximum height the box may have.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0052'),
          argMappings: {
            'maxHeight': ArgMapping(targetFields: [WireId('p0564')]),
            'maxWidth': ArgMapping(targetFields: [WireId('p0562')]),
            'minHeight': ArgMapping(targetFields: [WireId('p0563')]),
            'minWidth': ArgMapping(targetFields: [WireId('p0561')]),
          },
          parameters: [
            FactoryParameter(
              wireId: WireId('a0034'),
              name: 'minWidth',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: false,
              defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
              defaultValue: LiteralParameterDefault(0.0),
              valueShape: ScalarShape(
                  propertyType: PropertyType.real,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'double')),
            ),
            FactoryParameter(
              wireId: WireId('a0035'),
              name: 'maxWidth',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: false,
              defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
              defaultValue: StaticMemberParameterDefault(
                  staticType: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'double'),
                  memberName: 'infinity'),
              valueShape: ScalarShape(
                  propertyType: PropertyType.real,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'double')),
            ),
            FactoryParameter(
              wireId: WireId('a0036'),
              name: 'minHeight',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: false,
              defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
              defaultValue: LiteralParameterDefault(0.0),
              valueShape: ScalarShape(
                  propertyType: PropertyType.real,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'double')),
            ),
            FactoryParameter(
              wireId: WireId('a0037'),
              name: 'maxHeight',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: false,
              defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
              defaultValue: StaticMemberParameterDefault(
                  staticType: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'double'),
                  memberName: 'infinity'),
              valueShape: ScalarShape(
                  propertyType: PropertyType.real,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'double')),
            ),
          ],
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0002'),
      name: 'TextStyle',
      library: WidgetLibrary.core,
      description:
          'An immutable style describing how to format and paint text.',
      sourceType: 'package:flutter/src/painting/text_style.dart#TextStyle',
      fields: [
        StructuredField(
          wireId: WireId('p0190'),
          name: 'inherit',
          type: PropertyType.boolean,
          description:
              'Whether null values in this [TextStyle] can be replaced with their value in another [TextStyle] using [merge].',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        StructuredField(
          wireId: WireId('p0169'),
          name: 'color',
          type: PropertyType.color,
          description: 'The color to use when painting the text.',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        StructuredField(
          wireId: WireId('p0191'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'The color to use as the background for the text.',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        StructuredField(
          wireId: WireId('p0192'),
          name: 'fontFamily',
          type: PropertyType.string,
          description:
              'The name of the font to use when painting the text (e.g., Roboto).',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        StructuredField(
          wireId: WireId('p0293'),
          name: 'fontFamilyFallback',
          type: PropertyType.stringList,
          description: 'Fallback font families.',
          valueShape: ListShape(
              propertyType: PropertyType.stringList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.string,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'String'))),
        ),
        StructuredField(
          wireId: WireId('p0167'),
          name: 'fontSize',
          type: PropertyType.real,
          description:
              'The size of fonts (in logical pixels) to use when painting the text.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0168'),
          name: 'fontWeight',
          type: PropertyType.fontWeight,
          description:
              'The typeface thickness to use when painting the text (e.g., bold).',
          valueShape: ScalarShape(
              propertyType: PropertyType.fontWeight,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'FontWeight')),
        ),
        StructuredField(
          wireId: WireId('p0282'),
          name: 'fontStyle',
          type: PropertyType.enumValue,
          description:
              'The typeface variant to use when drawing the letters (e.g., italics).',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'FontStyle')),
        ),
        StructuredField(
          wireId: WireId('p0193'),
          name: 'letterSpacing',
          type: PropertyType.real,
          description:
              'The amount of space (in logical pixels) to add between each letter. A negative value can be used to bring the letters closer.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0194'),
          name: 'wordSpacing',
          type: PropertyType.real,
          description:
              'The amount of space (in logical pixels) to add at each sequence of white-space (i.e. between each word). A negative value can be used to bring the words closer.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0195'),
          name: 'height',
          type: PropertyType.real,
          description:
              'The height of this text span, as a multiple of the font size.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0284'),
          name: 'leadingDistribution',
          type: PropertyType.enumValue,
          description:
              'How the vertical space added by the [height] multiplier should be distributed over and under the text.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui',
                  symbolName: 'TextLeadingDistribution')),
        ),
        StructuredField(
          wireId: WireId('p0286'),
          name: 'foreground',
          type: PropertyType.paint,
          description: 'The paint drawn as a foreground for the text.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        StructuredField(
          wireId: WireId('p0287'),
          name: 'background',
          type: PropertyType.paint,
          description: 'The paint drawn as a background for the text.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        StructuredField(
          wireId: WireId('p0291'),
          name: 'decoration',
          type: PropertyType.textDecoration,
          description:
              'The decorations to paint near the text (e.g., an underline).',
          valueShape: ScalarShape(
              propertyType: PropertyType.textDecoration,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextDecoration')),
        ),
        StructuredField(
          wireId: WireId('p0196'),
          name: 'decorationColor',
          type: PropertyType.color,
          description: 'The color in which to paint the text decorations.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        StructuredField(
          wireId: WireId('p0292'),
          name: 'decorationStyle',
          type: PropertyType.enumValue,
          description:
              'The style in which to paint the text decorations (e.g., dashed).',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextDecorationStyle')),
        ),
        StructuredField(
          wireId: WireId('p0197'),
          name: 'decorationThickness',
          type: PropertyType.real,
          description:
              'The thickness of the decoration stroke as a multiplier of the thickness defined by the font.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0198'),
          name: 'debugLabel',
          type: PropertyType.string,
          description: 'A human-readable description of this text style.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        StructuredField(
          wireId: WireId('p0288'),
          name: 'shadows',
          type: PropertyType.shadowList,
          description:
              'A list of [Shadow]s that will be painted underneath the text.',
          valueShape: ListShape(
              propertyType: PropertyType.shadowList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.shadowList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'Shadow'))),
        ),
        StructuredField(
          wireId: WireId('p0289'),
          name: 'fontFeatures',
          type: PropertyType.fontFeatureList,
          description:
              'A list of [FontFeature]s that affect how the font selects glyphs.',
          valueShape: ListShape(
              propertyType: PropertyType.fontFeatureList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.fontFeatureList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'FontFeature'))),
        ),
        StructuredField(
          wireId: WireId('p0290'),
          name: 'fontVariations',
          type: PropertyType.fontVariationList,
          description:
              'A list of [FontVariation]s that affect how a variable font is rendered.',
          valueShape: ListShape(
              propertyType: PropertyType.fontVariationList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.fontVariationList,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'FontVariation'))),
        ),
        StructuredField(
          wireId: WireId('p0294'),
          name: 'overflow',
          type: PropertyType.enumValue,
          description: 'How visual text overflow should be handled.',
          defaultSource: LiteralDefault('clip'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/text_painter.dart',
                  symbolName: 'TextOverflow')),
        ),
        StructuredField(
          wireId: WireId('p0283'),
          name: 'textBaseline',
          type: PropertyType.enumValue,
          description: 'Baseline used to align text.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'dart:ui', symbolName: 'TextBaseline')),
        ),
        StructuredField(
          wireId: WireId('p0285'),
          name: 'locale',
          type: PropertyType.locale,
          description: 'Locale used for font selection.',
          valueShape: ScalarShape(
              propertyType: PropertyType.locale,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Locale')),
        ),
      ],
      variants: [
        StaticMethodVariant(
          wireId: WireId('v0013'),
          staticAccessor: 'lerp',
          description:
              'Interpolate between two text styles for animated transitions.',
        ),
        ConstructorVariant(
          wireId: WireId('v0001'),
          argMappings: {
            'background': ArgMapping(targetFields: [WireId('p0287')]),
            'backgroundColor': ArgMapping(targetFields: [WireId('p0191')]),
            'color': ArgMapping(targetFields: [WireId('p0169')]),
            'debugLabel': ArgMapping(targetFields: [WireId('p0198')]),
            'decoration': ArgMapping(targetFields: [WireId('p0291')]),
            'decorationColor': ArgMapping(targetFields: [WireId('p0196')]),
            'decorationStyle': ArgMapping(targetFields: [WireId('p0292')]),
            'decorationThickness': ArgMapping(targetFields: [WireId('p0197')]),
            'fontFamily': ArgMapping(targetFields: [WireId('p0192')]),
            'fontFamilyFallback': ArgMapping(targetFields: [WireId('p0293')]),
            'fontFeatures': ArgMapping(targetFields: [WireId('p0289')]),
            'fontSize': ArgMapping(targetFields: [WireId('p0167')]),
            'fontStyle': ArgMapping(targetFields: [WireId('p0282')]),
            'fontVariations': ArgMapping(targetFields: [WireId('p0290')]),
            'fontWeight': ArgMapping(targetFields: [WireId('p0168')]),
            'foreground': ArgMapping(targetFields: [WireId('p0286')]),
            'height': ArgMapping(targetFields: [WireId('p0195')]),
            'inherit': ArgMapping(targetFields: [WireId('p0190')]),
            'leadingDistribution': ArgMapping(targetFields: [WireId('p0284')]),
            'letterSpacing': ArgMapping(targetFields: [WireId('p0193')]),
            'locale': ArgMapping(targetFields: [WireId('p0285')]),
            'overflow': ArgMapping(targetFields: [WireId('p0294')]),
            'shadows': ArgMapping(targetFields: [WireId('p0288')]),
            'textBaseline': ArgMapping(targetFields: [WireId('p0283')]),
            'wordSpacing': ArgMapping(targetFields: [WireId('p0194')]),
          },
          parameters: [
            FactoryParameter(
              wireId: WireId('a0013'),
              name: 'inherit',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: false,
              defaultPolicy: FactoryParameterDefaultPolicy.useFlutterDefault,
              defaultValue: LiteralParameterDefault(true),
              valueShape: ScalarShape(
                  propertyType: PropertyType.boolean,
                  dartTypeRef:
                      DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
            ),
            FactoryParameter(
              wireId: WireId('a0004'),
              name: 'color',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.color,
                  dartTypeRef:
                      DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
            ),
            FactoryParameter(
              wireId: WireId('a0014'),
              name: 'backgroundColor',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.color,
                  dartTypeRef:
                      DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
            ),
            FactoryParameter(
              wireId: WireId('a0005'),
              name: 'fontSize',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.real,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'double')),
            ),
            FactoryParameter(
              wireId: WireId('a0006'),
              name: 'fontWeight',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.fontWeight,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'FontWeight')),
            ),
            FactoryParameter(
              wireId: WireId('a0015'),
              name: 'fontStyle',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: EnumShape(
                  propertyType: PropertyType.enumValue,
                  enumRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'FontStyle')),
            ),
            FactoryParameter(
              wireId: WireId('a0011'),
              name: 'letterSpacing',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.real,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'double')),
            ),
            FactoryParameter(
              wireId: WireId('a0016'),
              name: 'wordSpacing',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.real,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'double')),
            ),
            FactoryParameter(
              wireId: WireId('a0017'),
              name: 'textBaseline',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: EnumShape(
                  propertyType: PropertyType.enumValue,
                  enumRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'TextBaseline')),
            ),
            FactoryParameter(
              wireId: WireId('a0012'),
              name: 'height',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.real,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'double')),
            ),
            FactoryParameter(
              wireId: WireId('a0018'),
              name: 'leadingDistribution',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: EnumShape(
                  propertyType: PropertyType.enumValue,
                  enumRef: DartTypeRef(
                      libraryUri: 'dart:ui',
                      symbolName: 'TextLeadingDistribution')),
            ),
            FactoryParameter(
              wireId: WireId('a0019'),
              name: 'locale',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.locale,
                  dartTypeRef:
                      DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Locale')),
            ),
            FactoryParameter(
              wireId: WireId('a0020'),
              name: 'foreground',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.paint,
                  dartTypeRef:
                      DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
            ),
            FactoryParameter(
              wireId: WireId('a0021'),
              name: 'background',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.paint,
                  dartTypeRef:
                      DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
            ),
            FactoryParameter(
              wireId: WireId('a0022'),
              name: 'shadows',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ListShape(
                  propertyType: PropertyType.shadowList,
                  itemShape: ScalarShape(
                      propertyType: PropertyType.shadowList,
                      dartTypeRef: DartTypeRef(
                          libraryUri: 'dart:ui', symbolName: 'Shadow'))),
            ),
            FactoryParameter(
              wireId: WireId('a0023'),
              name: 'fontFeatures',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ListShape(
                  propertyType: PropertyType.fontFeatureList,
                  itemShape: ScalarShape(
                      propertyType: PropertyType.fontFeatureList,
                      dartTypeRef: DartTypeRef(
                          libraryUri: 'dart:ui', symbolName: 'FontFeature'))),
            ),
            FactoryParameter(
              wireId: WireId('a0024'),
              name: 'fontVariations',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ListShape(
                  propertyType: PropertyType.fontVariationList,
                  itemShape: ScalarShape(
                      propertyType: PropertyType.fontVariationList,
                      dartTypeRef: DartTypeRef(
                          libraryUri: 'dart:ui', symbolName: 'FontVariation'))),
            ),
            FactoryParameter(
              wireId: WireId('a0025'),
              name: 'decoration',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.textDecoration,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:ui', symbolName: 'TextDecoration')),
            ),
            FactoryParameter(
              wireId: WireId('a0026'),
              name: 'decorationColor',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.color,
                  dartTypeRef:
                      DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
            ),
            FactoryParameter(
              wireId: WireId('a0027'),
              name: 'decorationStyle',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: EnumShape(
                  propertyType: PropertyType.enumValue,
                  enumRef: DartTypeRef(
                      libraryUri: 'dart:ui',
                      symbolName: 'TextDecorationStyle')),
            ),
            FactoryParameter(
              wireId: WireId('a0028'),
              name: 'decorationThickness',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.real,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'double')),
            ),
            FactoryParameter(
              wireId: WireId('a0029'),
              name: 'debugLabel',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.string,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'String')),
            ),
            FactoryParameter(
              wireId: WireId('a0030'),
              name: 'fontFamily',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.string,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'String')),
            ),
            FactoryParameter(
              wireId: WireId('a0031'),
              name: 'fontFamilyFallback',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ListShape(
                  propertyType: PropertyType.stringList,
                  itemShape: ScalarShape(
                      propertyType: PropertyType.string,
                      dartTypeRef: DartTypeRef(
                          libraryUri: 'dart:core', symbolName: 'String'))),
            ),
            FactoryParameter(
              wireId: WireId('a0033'),
              name: 'package',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.string,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'String')),
            ),
            FactoryParameter(
              wireId: WireId('a0032'),
              name: 'overflow',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: EnumShape(
                  propertyType: PropertyType.enumValue,
                  enumRef: DartTypeRef(
                      libraryUri:
                          'package:flutter/src/painting/text_painter.dart',
                      symbolName: 'TextOverflow')),
            ),
          ],
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0020'),
      name: 'Shadow',
      library: WidgetLibrary.core,
      description: 'Shadow value.',
      sourceType: 'dart:ui#Shadow',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0021'),
      name: 'FontFeature',
      library: WidgetLibrary.core,
      description: 'FontFeature value.',
      sourceType: 'dart:ui#FontFeature',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0022'),
      name: 'FontVariation',
      library: WidgetLibrary.core,
      description: 'FontVariation value.',
      sourceType: 'dart:ui#FontVariation',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0023'),
      name: 'String',
      library: WidgetLibrary.core,
      description: 'String value.',
      sourceType: 'dart:core#String',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0005'),
      name: 'Border',
      library: WidgetLibrary.core,
      description:
          'A border of a box, comprised of four sides: top, right, bottom, left.',
      sourceType: 'package:flutter/src/painting/box_border.dart#Border',
      fields: [
        StructuredField(
          wireId: WireId('p0175'),
          name: 'top',
          type: PropertyType.structured,
          description: '',
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0006')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('s0006'))),
        ),
        StructuredField(
          wireId: WireId('p0176'),
          name: 'right',
          type: PropertyType.structured,
          description: 'The right side of this border.',
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0006')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('s0006'))),
        ),
        StructuredField(
          wireId: WireId('p0177'),
          name: 'bottom',
          type: PropertyType.structured,
          description: '',
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0006')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('s0006'))),
        ),
        StructuredField(
          wireId: WireId('p0178'),
          name: 'left',
          type: PropertyType.structured,
          description: 'The left side of this border.',
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0006')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('s0006'))),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0008'),
          argMappings: {
            'bottom': ArgMapping(targetFields: [WireId('p0177')]),
            'left': ArgMapping(targetFields: [WireId('p0178')]),
            'right': ArgMapping(targetFields: [WireId('p0176')]),
            'top': ArgMapping(targetFields: [WireId('p0175')]),
          },
          description: 'Creates a border.',
        ),
        ConstructorVariant(
          wireId: WireId('v0009'),
          namedConstructor: 'all',
          description:
              'A uniform border with all sides the same color and width.',
        ),
        ConstructorVariant(
          wireId: WireId('v0035'),
          namedConstructor: 'fromBorderSide',
          argMappings: {
            'side': ArgMapping(targetFields: [
              WireId('p0175'),
              WireId('p0176'),
              WireId('p0177'),
              WireId('p0178')
            ]),
          },
          description: 'Creates a border whose sides are all the same.',
        ),
        ConstructorVariant(
          wireId: WireId('v0036'),
          namedConstructor: 'symmetric',
          description:
              'Creates a border with symmetrical vertical and horizontal sides.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0037'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two borders.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0038'),
          staticAccessor: 'merge',
          description:
              'Creates a [Border] that represents the addition of the two given [Border]s.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0019'),
      name: 'BorderDirectional',
      library: WidgetLibrary.core,
      description:
          'A border of a box, comprised of four sides, the lateral sides of which flip over based on the reading direction.',
      sourceType:
          'package:flutter/src/painting/box_border.dart#BorderDirectional',
      fields: [
        StructuredField(
          wireId: WireId('p0231'),
          name: 'top',
          type: PropertyType.structured,
          description: '',
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0006')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('s0006'))),
        ),
        StructuredField(
          wireId: WireId('p0232'),
          name: 'start',
          type: PropertyType.structured,
          description: 'The start side of this border.',
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0006')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('s0006'))),
        ),
        StructuredField(
          wireId: WireId('p0233'),
          name: 'end',
          type: PropertyType.structured,
          description: 'The end side of this border.',
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0006')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('s0006'))),
        ),
        StructuredField(
          wireId: WireId('p0234'),
          name: 'bottom',
          type: PropertyType.structured,
          description: '',
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0006')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('s0006'))),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0039'),
          argMappings: {
            'bottom': ArgMapping(targetFields: [WireId('p0234')]),
            'end': ArgMapping(targetFields: [WireId('p0233')]),
            'start': ArgMapping(targetFields: [WireId('p0232')]),
            'top': ArgMapping(targetFields: [WireId('p0231')]),
          },
          description: 'Creates a border.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0040'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two borders.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0041'),
          staticAccessor: 'merge',
          description:
              'Creates a [BorderDirectional] that represents the addition of the two given [BorderDirectional]s.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0006'),
      name: 'BorderSide',
      library: WidgetLibrary.core,
      description: 'A side of a border of a box.',
      sourceType: 'package:flutter/src/painting/borders.dart#BorderSide',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0008'),
      name: 'LinearGradient',
      library: WidgetLibrary.core,
      description: 'A 2D linear gradient.',
      sourceType: 'package:flutter/src/painting/gradient.dart#LinearGradient',
      fields: [
        StructuredField(
          wireId: WireId('p0186'),
          name: 'begin',
          type: PropertyType.alignment,
          description:
              'The offset at which stop 0.0 of the gradient is placed.',
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        StructuredField(
          wireId: WireId('p0187'),
          name: 'end',
          type: PropertyType.alignment,
          description:
              'The offset at which stop 1.0 of the gradient is placed.',
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        StructuredField(
          wireId: WireId('p0307'),
          name: 'tileMode',
          type: PropertyType.enumValue,
          description:
              'How this gradient should tile the plane beyond in the region before [begin] and after [end].',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'TileMode')),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0012'),
          argMappings: {
            'begin': ArgMapping(targetFields: [WireId('p0186')]),
            'end': ArgMapping(targetFields: [WireId('p0187')]),
            'tileMode': ArgMapping(targetFields: [WireId('p0307')]),
          },
          description: 'Creates a linear gradient.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0030'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two [LinearGradient]s.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0017'),
      name: 'RadialGradient',
      library: WidgetLibrary.core,
      description: 'A 2D radial gradient.',
      sourceType: 'package:flutter/src/painting/gradient.dart#RadialGradient',
      fields: [
        StructuredField(
          wireId: WireId('p0308'),
          name: 'center',
          type: PropertyType.alignment,
          description:
              'The center of the gradient, as an offset into the (-1.0, -1.0) x (1.0, 1.0) square describing the gradient which will be mapped onto the paint box.',
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        StructuredField(
          wireId: WireId('p0223'),
          name: 'radius',
          type: PropertyType.real,
          description:
              'The radius of the gradient, as a fraction of the shortest side of the paint box.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0309'),
          name: 'tileMode',
          type: PropertyType.enumValue,
          description:
              'How this gradient should tile the plane beyond the outer ring at [radius] pixels from the [center].',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'TileMode')),
        ),
        StructuredField(
          wireId: WireId('p0310'),
          name: 'focal',
          type: PropertyType.alignment,
          description:
              'The focal point of the gradient. If specified, the gradient will appear to be focused along the vector from [center] to focal.',
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        StructuredField(
          wireId: WireId('p0224'),
          name: 'focalRadius',
          type: PropertyType.real,
          description:
              'The radius of the focal point of gradient, as a fraction of the shortest side of the paint box.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0031'),
          argMappings: {
            'center': ArgMapping(targetFields: [WireId('p0308')]),
            'focal': ArgMapping(targetFields: [WireId('p0310')]),
            'focalRadius': ArgMapping(targetFields: [WireId('p0224')]),
            'radius': ArgMapping(targetFields: [WireId('p0223')]),
            'tileMode': ArgMapping(targetFields: [WireId('p0309')]),
          },
          description: 'Creates a radial gradient.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0032'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two [RadialGradient]s.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0018'),
      name: 'SweepGradient',
      library: WidgetLibrary.core,
      description: 'A 2D sweep gradient.',
      sourceType: 'package:flutter/src/painting/gradient.dart#SweepGradient',
      fields: [
        StructuredField(
          wireId: WireId('p0311'),
          name: 'center',
          type: PropertyType.alignment,
          description:
              'The center of the gradient, as an offset into the (-1.0, -1.0) x (1.0, 1.0) square describing the gradient which will be mapped onto the paint box.',
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        StructuredField(
          wireId: WireId('p0226'),
          name: 'startAngle',
          type: PropertyType.real,
          description:
              'The angle in radians at which stop 0.0 of the gradient is placed.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0227'),
          name: 'endAngle',
          type: PropertyType.real,
          description:
              'The angle in radians at which stop 1.0 of the gradient is placed.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0312'),
          name: 'tileMode',
          type: PropertyType.enumValue,
          description:
              'How this gradient should tile the plane in the region before [startAngle] and after [endAngle].',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'TileMode')),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0033'),
          argMappings: {
            'center': ArgMapping(targetFields: [WireId('p0311')]),
            'endAngle': ArgMapping(targetFields: [WireId('p0227')]),
            'startAngle': ArgMapping(targetFields: [WireId('p0226')]),
            'tileMode': ArgMapping(targetFields: [WireId('p0312')]),
          },
          description: 'Creates a sweep gradient.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0034'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two [SweepGradient]s.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0011'),
      name: 'ShapeDecoration',
      library: WidgetLibrary.core,
      description:
          'An immutable description of how to paint an arbitrary shape.',
      sourceType:
          'package:flutter/src/painting/shape_decoration.dart#ShapeDecoration',
      fields: [
        StructuredField(
          wireId: WireId('p0208'),
          name: 'color',
          type: PropertyType.color,
          description: 'The color to fill in the background of the shape.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        StructuredField(
          wireId: WireId('p0209'),
          name: 'gradient',
          type: PropertyType.gradient,
          description: 'A gradient to use when filling the shape.',
          unionRef: WireIdRef(library: 'restage.core', wireId: WireId('u0003')),
          valueShape: UnionShape(
              propertyType: PropertyType.gradient,
              unionRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('u0003')),
              wireCodec: CatalogWireCodec.rfwGradient),
        ),
        StructuredField(
          wireId: WireId('p0210'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description:
              'The shape to fill the [color], [gradient], and [image] into and to cast as the [shadows].',
          unionRef: WireIdRef(library: 'restage.core', wireId: WireId('u0002')),
          valueShape: UnionShape(
              propertyType: PropertyType.shapeBorder,
              unionRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('u0002')),
              wireCodec: CatalogWireCodec.rfwShapeBorder),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0022'),
          argMappings: {
            'color': ArgMapping(targetFields: [WireId('p0208')]),
            'gradient': ArgMapping(targetFields: [WireId('p0209')]),
            'shape': ArgMapping(targetFields: [WireId('p0210')]),
          },
          description: 'Creates a shape decoration.',
        ),
        ConstructorVariant(
          wireId: WireId('v0023'),
          namedConstructor: 'fromBoxDecoration',
          description:
              'Creates a shape decoration configured to match a [BoxDecoration].',
        ),
        StaticMethodVariant(
          wireId: WireId('v0024'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two shapes.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0012'),
      name: 'RoundedRectangleBorder',
      library: WidgetLibrary.core,
      description: 'A rectangular border with rounded corners.',
      sourceType:
          'package:flutter/src/painting/rounded_rectangle_border.dart#RoundedRectangleBorder',
      fields: [],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0025'),
          description: 'Creates a rounded rectangle border.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0024'),
      name: 'RoundedSuperellipseBorder',
      library: WidgetLibrary.core,
      description:
          'A rectangular border with rounded corners following the shape of an [RSuperellipse].',
      sourceType:
          'package:flutter/src/painting/rounded_rectangle_border.dart#RoundedSuperellipseBorder',
      fields: [],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0042'),
          description: 'Creates a rounded rectangle border.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0013'),
      name: 'CircleBorder',
      library: WidgetLibrary.core,
      description: 'A border that fits a circle within the available space.',
      sourceType:
          'package:flutter/src/painting/circle_border.dart#CircleBorder',
      fields: [
        StructuredField(
          wireId: WireId('p0215'),
          name: 'eccentricity',
          type: PropertyType.real,
          description:
              'Defines the ratio (0.0-1.0) from which the border will deform to fit a rectangle. When 0.0, it draws a circle touching at least two sides of the rectangle. When 1.0, it draws an oval touching all sides of the rectangle.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0026'),
          argMappings: {
            'eccentricity': ArgMapping(targetFields: [WireId('p0215')]),
          },
          description: 'Create a circle border.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0014'),
      name: 'StadiumBorder',
      library: WidgetLibrary.core,
      description:
          'A border that fits a stadium-shaped border (a box with semicircles on the ends) within the rectangle of the widget it is applied to.',
      sourceType:
          'package:flutter/src/painting/stadium_border.dart#StadiumBorder',
      fields: [],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0027'),
          description: 'Create a stadium border.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0015'),
      name: 'ContinuousRectangleBorder',
      library: WidgetLibrary.core,
      description:
          'A rectangular border with smooth continuous transitions between the straight sides and the rounded corners.',
      sourceType:
          'package:flutter/src/painting/continuous_rectangle_border.dart#ContinuousRectangleBorder',
      fields: [],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0028'),
          description: 'Creates a [ContinuousRectangleBorder].',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0016'),
      name: 'BeveledRectangleBorder',
      library: WidgetLibrary.core,
      description: 'A rectangular border with flattened or "beveled" corners.',
      sourceType:
          'package:flutter/src/painting/beveled_rectangle_border.dart#BeveledRectangleBorder',
      fields: [],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0029'),
          description:
              'Creates a border like a [RoundedRectangleBorder] except that the corners are joined by straight lines instead of arcs.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0025'),
      name: 'LinearBorder',
      library: WidgetLibrary.core,
      description:
          'An [OutlinedBorder] like [BoxBorder] that allows one to define a rectangular (box) border in terms of zero to four [LinearBorderEdge]s, each of which is rendered as a single line.',
      sourceType:
          'package:flutter/src/painting/linear_border.dart#LinearBorder',
      fields: [
        StructuredField(
          wireId: WireId('p0296'),
          name: 'start',
          type: PropertyType.structured,
          description:
              'Defines the left edge for [TextDirection.ltr] or the right for [TextDirection.rtl].',
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0027')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('s0027'))),
        ),
        StructuredField(
          wireId: WireId('p0297'),
          name: 'end',
          type: PropertyType.structured,
          description:
              'Defines the right edge for [TextDirection.ltr] or the left for [TextDirection.rtl].',
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0027')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('s0027'))),
        ),
        StructuredField(
          wireId: WireId('p0298'),
          name: 'top',
          type: PropertyType.structured,
          description: 'Defines the top edge.',
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0027')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('s0027'))),
        ),
        StructuredField(
          wireId: WireId('p0299'),
          name: 'bottom',
          type: PropertyType.structured,
          description: 'Defines the bottom edge.',
          structuredRef:
              WireIdRef(library: 'restage.core', wireId: WireId('s0027')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef:
                  WireIdRef(library: 'restage.core', wireId: WireId('s0027'))),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0043'),
          argMappings: {
            'bottom': ArgMapping(targetFields: [WireId('p0299')]),
            'end': ArgMapping(targetFields: [WireId('p0297')]),
            'start': ArgMapping(targetFields: [WireId('p0296')]),
            'top': ArgMapping(targetFields: [WireId('p0298')]),
          },
          description:
              'Creates a rectangular box border that\'s rendered as zero to four lines.',
        ),
        ConstructorVariant(
          wireId: WireId('v0044'),
          namedConstructor: 'bottom',
          description:
              'Creates a rectangular box border with an edge on the bottom.',
        ),
        ConstructorVariant(
          wireId: WireId('v0045'),
          namedConstructor: 'end',
          description:
              'Creates a rectangular box border with an edge on the right for [TextDirection.ltr] or on the left for [TextDirection.rtl].',
        ),
        ConstructorVariant(
          wireId: WireId('v0046'),
          namedConstructor: 'start',
          description:
              'Creates a rectangular box border with an edge on the left for [TextDirection.ltr] or on the right for [TextDirection.rtl].',
        ),
        ConstructorVariant(
          wireId: WireId('v0047'),
          namedConstructor: 'top',
          description:
              'Creates a rectangular box border with an edge on the top.',
        ),
        ConstValueVariant(
          wireId: WireId('v0049'),
          staticAccessor: 'none',
          description: 'No border.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0026'),
      name: 'StarBorder',
      library: WidgetLibrary.core,
      description:
          'A border that fits a star or polygon-shaped border within the rectangle of the widget it is applied to.',
      sourceType: 'package:flutter/src/painting/star_border.dart#StarBorder',
      fields: [
        StructuredField(
          wireId: WireId('p0300'),
          name: 'points',
          type: PropertyType.real,
          description:
              'The number of points in this star, or sides on a polygon.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0301'),
          name: 'innerRadiusRatio',
          type: PropertyType.real,
          description: '',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0302'),
          name: 'pointRounding',
          type: PropertyType.real,
          description:
              'The amount of rounding on the points of stars, or the corners of polygons.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0303'),
          name: 'valleyRounding',
          type: PropertyType.real,
          description:
              'The amount of rounding of the interior corners of stars.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0304'),
          name: 'rotation',
          type: PropertyType.real,
          description: '',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0305'),
          name: 'squash',
          type: PropertyType.real,
          description:
              'How much of the aspect ratio of the attached widget to take on.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0050'),
          argMappings: {
            'innerRadiusRatio': ArgMapping(targetFields: [WireId('p0301')]),
            'pointRounding': ArgMapping(targetFields: [WireId('p0302')]),
            'points': ArgMapping(targetFields: [WireId('p0300')]),
            'rotation': ArgMapping(targetFields: [WireId('p0304')]),
            'squash': ArgMapping(targetFields: [WireId('p0305')]),
            'valleyRounding': ArgMapping(targetFields: [WireId('p0303')]),
          },
          description:
              'Create a const star-shaped border with the given number [points] on the star.',
        ),
        ConstructorVariant(
          wireId: WireId('v0051'),
          namedConstructor: 'polygon',
          argMappings: {
            'pointRounding': ArgMapping(targetFields: [WireId('p0302')]),
            'rotation': ArgMapping(targetFields: [WireId('p0304')]),
            'squash': ArgMapping(targetFields: [WireId('p0305')]),
          },
          description:
              'Create a const polygon border with the given number of [sides].',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0027'),
      name: 'LinearBorderEdge',
      library: WidgetLibrary.core,
      description:
          'Defines the relative size and alignment of one [LinearBorder] edge.',
      sourceType:
          'package:flutter/src/painting/linear_border.dart#LinearBorderEdge',
      fields: [],
      variants: [],
    ),
  ],
  unions: [
    UnionEntry(
      wireId: WireId('u0004'),
      name: 'BoxBorder',
      library: WidgetLibrary.core,
      description:
          'A box border: uniform or per-side Border, or text-direction-aware BorderDirectional.',
      sourceType: 'package:flutter/src/painting/box_border.dart#BoxBorder',
      memberSourceTypes: [
        'package:flutter/src/painting/box_border.dart#Border',
        'package:flutter/src/painting/box_border.dart#BorderDirectional'
      ],
      discriminator: DiscriminatorSpec(field: '_s', values: [
        WireIdRef(library: 'restage.core', wireId: WireId('s0005')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0019'))
      ]),
      members: [
        WireIdRef(library: 'restage.core', wireId: WireId('s0005')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0019'))
      ],
    ),
    UnionEntry(
      wireId: WireId('u0003'),
      name: 'Gradient',
      library: WidgetLibrary.core,
      description: 'A color gradient: linear, radial, or sweep.',
      sourceType: 'package:flutter/src/painting/gradient.dart#Gradient',
      memberSourceTypes: [
        'package:flutter/src/painting/gradient.dart#LinearGradient',
        'package:flutter/src/painting/gradient.dart#RadialGradient',
        'package:flutter/src/painting/gradient.dart#SweepGradient'
      ],
      discriminator: DiscriminatorSpec(field: '_s', values: [
        WireIdRef(library: 'restage.core', wireId: WireId('s0008')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0017')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0018'))
      ]),
      members: [
        WireIdRef(library: 'restage.core', wireId: WireId('s0008')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0017')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0018'))
      ],
    ),
    UnionEntry(
      wireId: WireId('u0001'),
      name: 'Decoration',
      library: WidgetLibrary.core,
      description: 'A box decoration: BoxDecoration or ShapeDecoration.',
      sourceType: 'package:flutter/src/painting/decoration.dart#Decoration',
      memberSourceTypes: [
        'package:flutter/src/painting/box_decoration.dart#BoxDecoration',
        'package:flutter/src/painting/shape_decoration.dart#ShapeDecoration'
      ],
      discriminator: DiscriminatorSpec(field: '_s', values: [
        WireIdRef(library: 'restage.core', wireId: WireId('s0001')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0011'))
      ]),
      members: [
        WireIdRef(library: 'restage.core', wireId: WireId('s0001')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0011'))
      ],
    ),
    UnionEntry(
      wireId: WireId('u0002'),
      name: 'ShapeBorder',
      library: WidgetLibrary.core,
      description:
          'A shape border: rounded, superellipse, circle, stadium, continuous, beveled, linear, or star.',
      sourceType: 'package:flutter/src/painting/borders.dart#ShapeBorder',
      memberSourceTypes: [
        'package:flutter/src/painting/rounded_rectangle_border.dart#RoundedRectangleBorder',
        'package:flutter/src/painting/rounded_rectangle_border.dart#RoundedSuperellipseBorder',
        'package:flutter/src/painting/circle_border.dart#CircleBorder',
        'package:flutter/src/painting/stadium_border.dart#StadiumBorder',
        'package:flutter/src/painting/continuous_rectangle_border.dart#ContinuousRectangleBorder',
        'package:flutter/src/painting/beveled_rectangle_border.dart#BeveledRectangleBorder',
        'package:flutter/src/painting/linear_border.dart#LinearBorder',
        'package:flutter/src/painting/star_border.dart#StarBorder'
      ],
      discriminator: DiscriminatorSpec(field: '_s', values: [
        WireIdRef(library: 'restage.core', wireId: WireId('s0012')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0024')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0013')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0014')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0015')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0016')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0025')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0026'))
      ]),
      members: [
        WireIdRef(library: 'restage.core', wireId: WireId('s0012')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0024')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0013')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0014')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0015')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0016')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0025')),
        WireIdRef(library: 'restage.core', wireId: WireId('s0026'))
      ],
    ),
  ],
);

/// The content version of the `restage.core` catalog —
/// the maximum widget `sinceVersion` in this library. Read by
/// the SDK to derive the installed built-in catalog version.
const int kCoreCatalogContentVersion = 1;
