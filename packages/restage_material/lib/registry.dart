// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated from lib/registry_curation.dart by restage_catalog_gen.
//
// Edit the curation file and re-run build_runner; do not
// edit this file directly. The runtime, codegen, and editor
// all consume `kRegistry` from here.

library;

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Registry for the `restage.material` library.
/// Read by codegen, the editor, and the runtime SDK.
final Catalog kRegistry = Catalog(
  schemaVersion: 4,
  generatedAt: '1970-01-01T00:00:00Z',
  libraries: {
    WidgetLibrary.material: const LibraryInfo(version: '0.1.0'),
  },
  widgets: [
    WidgetEntry(
      wireId: WireId('w0001'),
      name: 'ActionChip',
      library: WidgetLibrary.material,
      category: WidgetCategory.input,
      description: 'A Material Design action chip.',
      flutterType: 'package:flutter/src/material/action_chip.dart#ActionChip',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onPressed],
      properties: [
        PropertyEntry(
          wireId: WireId('p0001'),
          name: 'avatar',
          type: PropertyType.widget,
          description: '',
        ),
        PropertyEntry(
          wireId: WireId('p0002'),
          name: 'label',
          type: PropertyType.widget,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0003'),
          name: 'onPressed',
          type: PropertyType.event,
          description: '',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0349'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'Clip',
          defaultSource: LiteralDefault('none'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0004'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: '',
          defaultBrandToken: 'surface',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0005'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description: '',
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0002'),
      name: 'AppBar',
      library: WidgetLibrary.material,
      category: WidgetCategory.layout,
      description: 'A Material Design app bar.',
      flutterType: 'package:flutter/src/material/app_bar.dart#AppBar',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0006'),
          name: 'title',
          type: PropertyType.widget,
          description:
              '{@template flutter.material.appbar.title} The primary widget displayed in the app bar.',
        ),
        PropertyEntry(
          wireId: WireId('p0007'),
          name: 'elevation',
          type: PropertyType.length,
          description:
              '{@template flutter.material.appbar.elevation} The z-coordinate at which to place this app bar relative to its parent.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0260'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description:
              '{@template flutter.material.appbar.shape} The shape of the app bar\'s [Material] as well as its shadow.',
        ),
        PropertyEntry(
          wireId: WireId('p0008'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description:
              '{@template flutter.material.appbar.backgroundColor} The fill color to use for an app bar\'s [Material].',
          defaultBrandToken: 'primary',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0009'),
          name: 'foregroundColor',
          type: PropertyType.color,
          description:
              '{@template flutter.material.appbar.foregroundColor} The default color for [Text] and [Icon]s within the app bar.',
          defaultBrandToken: 'onPrimary',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0010'),
          name: 'centerTitle',
          type: PropertyType.boolean,
          description:
              '{@template flutter.material.appbar.centerTitle} Whether the title should be centered.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0350'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '{@macro flutter.material.Material.clipBehavior}',
          enumType: 'Clip',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0003'),
      name: 'Badge',
      library: WidgetLibrary.material,
      category: WidgetCategory.decoration,
      description: 'A Material Design "badge".',
      flutterType: 'package:flutter/src/material/badge.dart#Badge',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0011'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'The badge\'s fill color.',
          defaultBrandToken: 'error',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0012'),
          name: 'textColor',
          type: PropertyType.color,
          description: 'The color of the badge\'s [label] text.',
          defaultBrandToken: 'onError',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0013'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description: 'The padding added to the badge\'s label.',
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0014'),
          name: 'alignment',
          type: PropertyType.alignment,
          description:
              'Combined with [offset] to determine the location of the [label] relative to the [child].',
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0314'),
          name: 'offset',
          type: PropertyType.offset,
          description:
              'Combined with [alignment] to determine the location of the [label] relative to the [child].',
          valueShape: ScalarShape(
              propertyType: PropertyType.offset,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Offset')),
        ),
        PropertyEntry(
          wireId: WireId('p0015'),
          name: 'label',
          type: PropertyType.widget,
          description:
              'The badge\'s content, typically a [Text] widget that contains 1 to 4 characters.',
        ),
        PropertyEntry(
          wireId: WireId('p0016'),
          name: 'isLabelVisible',
          type: PropertyType.boolean,
          description: 'If false, the badge\'s [label] is not included.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0017'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget that the badge is stacked on top of.',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0004'),
      name: 'Card',
      library: WidgetLibrary.material,
      category: WidgetCategory.decoration,
      description:
          'A Material Design card: a panel with slightly rounded corners and an elevation shadow.',
      flutterType: 'package:flutter/src/material/card.dart#Card',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0018'),
          name: 'color',
          type: PropertyType.color,
          description: 'The card\'s background color.',
          defaultBrandToken: 'surface',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0019'),
          name: 'elevation',
          type: PropertyType.length,
          description:
              'The z-coordinate at which to place this card. This controls the size of the shadow below the card.',
          defaultSource: LiteralDefault(1.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0261'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description: 'The shape of the card\'s [Material].',
        ),
        PropertyEntry(
          wireId: WireId('p0020'),
          name: 'margin',
          type: PropertyType.edgeInsets,
          description: 'The empty space that surrounds the card.',
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0351'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '{@macro flutter.material.Material.clipBehavior}',
          enumType: 'Clip',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0021'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0005'),
      name: 'CardFilled',
      library: WidgetLibrary.material,
      category: WidgetCategory.decoration,
      description: 'An M3 filled card — flat surface tinted from the palette.',
      flutterType: 'package:flutter/src/material/card.dart#Card.filled',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0022'),
          name: 'color',
          type: PropertyType.color,
          description: 'The card\'s background color.',
          defaultBrandToken: 'surfaceContainerHighest',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0023'),
          name: 'elevation',
          type: PropertyType.length,
          description:
              'The z-coordinate at which to place this card. This controls the size of the shadow below the card.',
          defaultSource: LiteralDefault(0.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0262'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description: 'The shape of the card\'s [Material].',
        ),
        PropertyEntry(
          wireId: WireId('p0024'),
          name: 'margin',
          type: PropertyType.edgeInsets,
          description: 'The empty space that surrounds the card.',
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0352'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '{@macro flutter.material.Material.clipBehavior}',
          enumType: 'Clip',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0025'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0006'),
      name: 'CardOutlined',
      library: WidgetLibrary.material,
      category: WidgetCategory.decoration,
      description: 'An M3 outlined card — transparent surface with a border.',
      flutterType: 'package:flutter/src/material/card.dart#Card.outlined',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0026'),
          name: 'color',
          type: PropertyType.color,
          description: 'The card\'s background color.',
          defaultBrandToken: 'surface',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0027'),
          name: 'elevation',
          type: PropertyType.length,
          description:
              'The z-coordinate at which to place this card. This controls the size of the shadow below the card.',
          defaultSource: LiteralDefault(0.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0263'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description: 'The shape of the card\'s [Material].',
        ),
        PropertyEntry(
          wireId: WireId('p0028'),
          name: 'margin',
          type: PropertyType.edgeInsets,
          description: 'The empty space that surrounds the card.',
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0353'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '{@macro flutter.material.Material.clipBehavior}',
          enumType: 'Clip',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0029'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0007'),
      name: 'Checkbox',
      library: WidgetLibrary.material,
      category: WidgetCategory.input,
      description: 'A Material Design checkbox.',
      flutterType: 'package:flutter/src/material/checkbox.dart#Checkbox',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onChanged],
      properties: [
        PropertyEntry(
          wireId: WireId('p0030'),
          name: 'value',
          type: PropertyType.boolean,
          description: 'Whether this checkbox is checked.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0031'),
          name: 'onChanged',
          type: PropertyType.event,
          description: 'Called when the value of the checkbox should change.',
          required: true,
          callbackSignature: 'ValueChanged<bool?>',
          category: PropertyCategory.behavior,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0032'),
          name: 'activeColor',
          type: PropertyType.color,
          description: 'The color to use when this checkbox is checked.',
          defaultBrandToken: 'primary',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0008'),
      name: 'CheckboxListTile',
      library: WidgetLibrary.material,
      category: WidgetCategory.input,
      description:
          'A [ListTile] with a [Checkbox]. In other words, a checkbox with a label.',
      flutterType:
          'package:flutter/src/material/checkbox_list_tile.dart#CheckboxListTile',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onChanged],
      properties: [
        PropertyEntry(
          wireId: WireId('p0033'),
          name: 'value',
          type: PropertyType.boolean,
          description: 'Whether this checkbox is checked.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0034'),
          name: 'onChanged',
          type: PropertyType.event,
          description: 'Called when the value of the checkbox should change.',
          required: true,
          callbackSignature: 'ValueChanged<bool?>',
          category: PropertyCategory.behavior,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0035'),
          name: 'activeColor',
          type: PropertyType.color,
          description: 'The color to use when this checkbox is checked.',
          defaultBrandToken: 'primary',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0264'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description: '{@macro flutter.material.ListTile.shape}',
        ),
        PropertyEntry(
          wireId: WireId('p0036'),
          name: 'title',
          type: PropertyType.widget,
          description: 'The primary content of the list tile.',
        ),
        PropertyEntry(
          wireId: WireId('p0037'),
          name: 'subtitle',
          type: PropertyType.widget,
          description: 'Additional content displayed below the title.',
        ),
        PropertyEntry(
          wireId: WireId('p0038'),
          name: 'secondary',
          type: PropertyType.widget,
          description:
              'A widget to display on the opposite side of the tile from the checkbox.',
        ),
        PropertyEntry(
          wireId: WireId('p0039'),
          name: 'selected',
          type: PropertyType.boolean,
          description: 'Whether to render icons and text in the [activeColor].',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0009'),
      name: 'Chip',
      library: WidgetLibrary.material,
      category: WidgetCategory.decoration,
      description: 'A Material Design chip.',
      flutterType: 'package:flutter/src/material/chip.dart#Chip',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0040'),
          name: 'avatar',
          type: PropertyType.widget,
          description: '',
        ),
        PropertyEntry(
          wireId: WireId('p0041'),
          name: 'label',
          type: PropertyType.widget,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0354'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'Clip',
          defaultSource: LiteralDefault('none'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0042'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: '',
          defaultBrandToken: 'surface',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0043'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description: '',
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0010'),
      name: 'ChoiceChip',
      library: WidgetLibrary.material,
      category: WidgetCategory.input,
      description: 'A Material Design choice chip.',
      flutterType: 'package:flutter/src/material/choice_chip.dart#ChoiceChip',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onSelected],
      properties: [
        PropertyEntry(
          wireId: WireId('p0044'),
          name: 'avatar',
          type: PropertyType.widget,
          description: '',
        ),
        PropertyEntry(
          wireId: WireId('p0045'),
          name: 'label',
          type: PropertyType.widget,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0046'),
          name: 'onSelected',
          type: PropertyType.event,
          description: '',
          callbackSignature: 'ValueChanged<bool>',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0047'),
          name: 'selected',
          type: PropertyType.boolean,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0355'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'Clip',
          defaultSource: LiteralDefault('none'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0048'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: '',
          defaultBrandToken: 'surface',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0049'),
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
          wireId: WireId('p0265'),
          name: 'avatarBorder',
          type: PropertyType.shapeBorder,
          description: '',
          defaultSource: LiteralDefault('circle'),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0011'),
      name: 'CircularProgressIndicator',
      library: WidgetLibrary.material,
      category: WidgetCategory.decoration,
      description:
          'A Material Design circular progress indicator, which spins to indicate that the application is busy.',
      flutterType:
          'package:flutter/src/material/progress_indicator.dart#CircularProgressIndicator',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0050'),
          name: 'value',
          type: PropertyType.real,
          description: '',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0051'),
          name: 'color',
          type: PropertyType.color,
          description: '',
          defaultBrandToken: 'primary',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0052'),
          name: 'strokeWidth',
          type: PropertyType.length,
          description: 'The width of the line used to draw the circle.',
          defaultSource: LiteralDefault(4.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0012'),
      name: 'Divider',
      library: WidgetLibrary.material,
      category: WidgetCategory.decoration,
      description: 'A thin horizontal line, with padding on either side.',
      flutterType: 'package:flutter/src/material/divider.dart#Divider',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0053'),
          name: 'height',
          type: PropertyType.length,
          description: 'The divider\'s height extent.',
          defaultSource: LiteralDefault(16.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0054'),
          name: 'thickness',
          type: PropertyType.length,
          description: 'The thickness of the line drawn within the divider.',
          defaultSource: LiteralDefault(1.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0055'),
          name: 'color',
          type: PropertyType.color,
          description:
              '{@template flutter.material.Divider.color} The color to use when painting the line.',
          defaultBrandToken: 'onBackground',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0013'),
      name: 'ElevatedButton',
      library: WidgetLibrary.material,
      category: WidgetCategory.action,
      description: 'A Material Design "elevated button".',
      flutterType:
          'package:flutter/src/material/elevated_button.dart#ElevatedButton',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onPressed],
      properties: [
        PropertyEntry(
          wireId: WireId('p0056'),
          name: 'onPressed',
          type: PropertyType.event,
          description: '',
          required: true,
          category: PropertyCategory.behavior,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0356'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'Clip',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0057'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0058'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'Background color.',
          defaultBrandToken: 'primary',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0059'),
          name: 'foregroundColor',
          type: PropertyType.color,
          description: 'Foreground color (text + icons).',
          defaultBrandToken: 'onPrimary',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0060'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description: 'Padding inside the button.',
          defaultSource: LiteralDefault([24.0, 12.0, 24.0, 12.0]),
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0061'),
          name: 'elevation',
          type: PropertyType.length,
          description: 'Material elevation in logical pixels.',
          defaultSource: LiteralDefault(1.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0266'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description: 'Button outline shape.',
          valueShape: UnionShape(
              propertyType: PropertyType.shapeBorder,
              unionRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('u0005')),
              wireCodec: CatalogWireCodec.rfwShapeBorder),
        ),
        PropertyEntry(
          wireId: WireId('p0367'),
          name: 'minimumSize',
          type: PropertyType.structured,
          description: 'Minimum button size (width, height).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0025'))),
        ),
        PropertyEntry(
          wireId: WireId('p0368'),
          name: 'fixedSize',
          type: PropertyType.structured,
          description: 'Fixed button size (width, height).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0025'))),
        ),
        PropertyEntry(
          wireId: WireId('p0369'),
          name: 'side',
          type: PropertyType.structured,
          description: 'Button border side (color, width, style).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0003'))),
        ),
        PropertyEntry(
          wireId: WireId('p0370'),
          name: 'textStyle',
          type: PropertyType.structured,
          description: 'Button label text style.',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0002'))),
        ),
        PropertyEntry(
          wireId: WireId('p0062'),
          name: 'disabled',
          type: PropertyType.boolean,
          description: 'Whether the button is disabled.',
          synthetic: 'gateOnPressed',
          defaultSource: LiteralDefault(false),
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0001')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'style',
          construction: FactoryInvocation(
              variantRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('v0001')),
              receiver: OwningWidgetTypeReceiver(),
              memberName: 'styleFrom'),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0187'),
              propertyRef: WireId('p0058'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0188'),
              propertyRef: WireId('p0059'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0189'),
              propertyRef: WireId('p0060'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0190'),
              propertyRef: WireId('p0061'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0259'),
              propertyRef: WireId('p0266'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0395'),
              propertyRef: WireId('p0367'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0396'),
              propertyRef: WireId('p0368'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0397'),
              propertyRef: WireId('p0369'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0398'),
              propertyRef: WireId('p0370'),
              transform: IdentityTransform(),
            ),
          ],
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0014'),
      name: 'ExpansionTile',
      library: WidgetLibrary.material,
      category: WidgetCategory.layout,
      description:
          'A single-line [ListTile] with an expansion arrow icon that expands or collapses the tile to reveal or hide the [children].',
      flutterType:
          'package:flutter/src/material/expansion_tile.dart#ExpansionTile',
      childrenSlot: ChildrenSlot.list,
      fires: [WidgetEventName.onExpansionChanged],
      properties: [
        PropertyEntry(
          wireId: WireId('p0063'),
          name: 'leading',
          type: PropertyType.widget,
          description: 'A widget to display before the title.',
        ),
        PropertyEntry(
          wireId: WireId('p0064'),
          name: 'title',
          type: PropertyType.widget,
          description: 'The primary content of the list item.',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0065'),
          name: 'subtitle',
          type: PropertyType.widget,
          description: 'Additional content displayed below the title.',
        ),
        PropertyEntry(
          wireId: WireId('p0066'),
          name: 'onExpansionChanged',
          type: PropertyType.event,
          description: 'Called when the tile expands or collapses.',
          callbackSignature: 'ValueChanged<bool>',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0067'),
          name: 'children',
          type: PropertyType.widgetList,
          description: 'The widgets that are displayed when the tile expands.',
        ),
        PropertyEntry(
          wireId: WireId('p0068'),
          name: 'trailing',
          type: PropertyType.widget,
          description: 'A widget to display after the title.',
        ),
        PropertyEntry(
          wireId: WireId('p0069'),
          name: 'initiallyExpanded',
          type: PropertyType.boolean,
          description:
              'Specifies if the list tile is initially expanded (true) or collapsed (false).',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0267'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description: 'The tile\'s border shape when the sublist is expanded.',
        ),
        PropertyEntry(
          wireId: WireId('p0268'),
          name: 'collapsedShape',
          type: PropertyType.shapeBorder,
          description:
              'The tile\'s border shape when the sublist is collapsed.',
        ),
        PropertyEntry(
          wireId: WireId('p0357'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '{@macro flutter.material.Material.clipBehavior}',
          enumType: 'Clip',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0015'),
      name: 'ExpressCheckoutButton',
      library: WidgetLibrary.material,
      category: WidgetCategory.action,
      description:
          'Conversion-CTA button for platform-native express-checkout flows.',
      flutterType:
          'package:restage_material/src/widgets/express_checkout_button.dart#ExpressCheckoutButton',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onPressed],
      properties: [
        PropertyEntry(
          wireId: WireId('p0070'),
          name: 'onPressed',
          type: PropertyType.event,
          description:
              'Fires when the user taps the button. Pass `null` (the default) to render the button in its disabled state.',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0071'),
          name: 'paymentMethod',
          type: PropertyType.enumValue,
          description:
              'Which platform\'s express-checkout variant to render. Defaults to [ExpressPaymentMethod.auto].',
          enumType: 'ExpressPaymentMethod',
          defaultSource: LiteralDefault('auto'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri:
                      'package:restage_material/src/widgets/express_checkout_button.dart',
                  symbolName: 'ExpressPaymentMethod')),
        ),
        PropertyEntry(
          wireId: WireId('p0072'),
          name: 'label',
          type: PropertyType.string,
          description:
              'Overrides the platform-default label (for example `\'Subscribe with Apple Pay\'`). When `null`, a sensible default is chosen based on the resolved payment method.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0016'),
      name: 'FilledButton',
      library: WidgetLibrary.material,
      category: WidgetCategory.action,
      description: 'A Material Design filled button.',
      flutterType:
          'package:flutter/src/material/filled_button.dart#FilledButton',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onPressed],
      properties: [
        PropertyEntry(
          wireId: WireId('p0073'),
          name: 'onPressed',
          type: PropertyType.event,
          description: '',
          required: true,
          category: PropertyCategory.behavior,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0358'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'Clip',
          defaultSource: LiteralDefault('none'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0074'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0075'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'Background color.',
          defaultBrandToken: 'primary',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0076'),
          name: 'foregroundColor',
          type: PropertyType.color,
          description: 'Foreground color (text + icons).',
          defaultBrandToken: 'onPrimary',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0077'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description: 'Padding inside the button.',
          defaultSource: LiteralDefault([24.0, 12.0, 24.0, 12.0]),
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0078'),
          name: 'elevation',
          type: PropertyType.length,
          description: 'Material elevation in logical pixels.',
          defaultSource: LiteralDefault(0.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0269'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description: 'Button outline shape.',
          valueShape: UnionShape(
              propertyType: PropertyType.shapeBorder,
              unionRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('u0005')),
              wireCodec: CatalogWireCodec.rfwShapeBorder),
        ),
        PropertyEntry(
          wireId: WireId('p0371'),
          name: 'minimumSize',
          type: PropertyType.structured,
          description: 'Minimum button size (width, height).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0025'))),
        ),
        PropertyEntry(
          wireId: WireId('p0372'),
          name: 'fixedSize',
          type: PropertyType.structured,
          description: 'Fixed button size (width, height).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0025'))),
        ),
        PropertyEntry(
          wireId: WireId('p0373'),
          name: 'side',
          type: PropertyType.structured,
          description: 'Button border side (color, width, style).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0003'))),
        ),
        PropertyEntry(
          wireId: WireId('p0374'),
          name: 'textStyle',
          type: PropertyType.structured,
          description: 'Button label text style.',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0002'))),
        ),
        PropertyEntry(
          wireId: WireId('p0079'),
          name: 'disabled',
          type: PropertyType.boolean,
          description: 'Whether the button is disabled.',
          synthetic: 'gateOnPressed',
          defaultSource: LiteralDefault(false),
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0001')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'style',
          construction: FactoryInvocation(
              variantRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('v0001')),
              receiver: OwningWidgetTypeReceiver(),
              memberName: 'styleFrom'),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0187'),
              propertyRef: WireId('p0075'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0188'),
              propertyRef: WireId('p0076'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0189'),
              propertyRef: WireId('p0077'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0190'),
              propertyRef: WireId('p0078'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0259'),
              propertyRef: WireId('p0269'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0395'),
              propertyRef: WireId('p0371'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0396'),
              propertyRef: WireId('p0372'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0397'),
              propertyRef: WireId('p0373'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0398'),
              propertyRef: WireId('p0374'),
              transform: IdentityTransform(),
            ),
          ],
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0017'),
      name: 'FilledButtonTonal',
      library: WidgetLibrary.material,
      category: WidgetCategory.action,
      description: 'An M3 secondary call-to-action button (tonal variant).',
      flutterType:
          'package:flutter/src/material/filled_button.dart#FilledButton.tonal',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onPressed],
      properties: [
        PropertyEntry(
          wireId: WireId('p0080'),
          name: 'onPressed',
          type: PropertyType.event,
          description: '',
          required: true,
          category: PropertyCategory.behavior,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0359'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'Clip',
          defaultSource: LiteralDefault('none'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0081'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0082'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'Background (tonal) color.',
          defaultBrandToken: 'secondaryContainer',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0083'),
          name: 'foregroundColor',
          type: PropertyType.color,
          description: 'Foreground color (text + icons).',
          defaultBrandToken: 'onSecondaryContainer',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0084'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description: 'Padding inside the button.',
          defaultSource: LiteralDefault([24.0, 12.0, 24.0, 12.0]),
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0270'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description: 'Button outline shape.',
          valueShape: UnionShape(
              propertyType: PropertyType.shapeBorder,
              unionRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('u0005')),
              wireCodec: CatalogWireCodec.rfwShapeBorder),
        ),
        PropertyEntry(
          wireId: WireId('p0375'),
          name: 'minimumSize',
          type: PropertyType.structured,
          description: 'Minimum button size (width, height).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0025'))),
        ),
        PropertyEntry(
          wireId: WireId('p0376'),
          name: 'fixedSize',
          type: PropertyType.structured,
          description: 'Fixed button size (width, height).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0025'))),
        ),
        PropertyEntry(
          wireId: WireId('p0377'),
          name: 'side',
          type: PropertyType.structured,
          description: 'Button border side (color, width, style).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0003'))),
        ),
        PropertyEntry(
          wireId: WireId('p0378'),
          name: 'textStyle',
          type: PropertyType.structured,
          description: 'Button label text style.',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0002'))),
        ),
        PropertyEntry(
          wireId: WireId('p0085'),
          name: 'disabled',
          type: PropertyType.boolean,
          description: 'Whether the button is disabled.',
          synthetic: 'gateOnPressed',
          defaultSource: LiteralDefault(false),
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0001')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'style',
          construction: FactoryInvocation(
              variantRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('v0001')),
              receiver: OwningWidgetTypeReceiver(),
              memberName: 'styleFrom'),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0187'),
              propertyRef: WireId('p0082'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0188'),
              propertyRef: WireId('p0083'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0189'),
              propertyRef: WireId('p0084'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0259'),
              propertyRef: WireId('p0270'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0395'),
              propertyRef: WireId('p0375'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0396'),
              propertyRef: WireId('p0376'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0397'),
              propertyRef: WireId('p0377'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0398'),
              propertyRef: WireId('p0378'),
              transform: IdentityTransform(),
            ),
          ],
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0018'),
      name: 'FilterChip',
      library: WidgetLibrary.material,
      category: WidgetCategory.input,
      description: 'A Material Design filter chip.',
      flutterType: 'package:flutter/src/material/filter_chip.dart#FilterChip',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onSelected],
      properties: [
        PropertyEntry(
          wireId: WireId('p0086'),
          name: 'avatar',
          type: PropertyType.widget,
          description: '',
        ),
        PropertyEntry(
          wireId: WireId('p0087'),
          name: 'label',
          type: PropertyType.widget,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0088'),
          name: 'selected',
          type: PropertyType.boolean,
          description: '',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0089'),
          name: 'onSelected',
          type: PropertyType.event,
          description: '',
          callbackSignature: 'ValueChanged<bool>',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0360'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'Clip',
          defaultSource: LiteralDefault('none'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0090'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: '',
          defaultBrandToken: 'surface',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0091'),
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
          wireId: WireId('p0271'),
          name: 'avatarBorder',
          type: PropertyType.shapeBorder,
          description: '',
          defaultSource: LiteralDefault('circle'),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0019'),
      name: 'FloatingActionButton',
      library: WidgetLibrary.material,
      category: WidgetCategory.input,
      description: 'A Material Design floating action button.',
      flutterType:
          'package:flutter/src/material/floating_action_button.dart#FloatingActionButton',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onPressed],
      properties: [
        PropertyEntry(
          wireId: WireId('p0092'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
        ),
        PropertyEntry(
          wireId: WireId('p0093'),
          name: 'tooltip',
          type: PropertyType.string,
          description:
              'Text that describes the action that will occur when the button is pressed.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0094'),
          name: 'foregroundColor',
          type: PropertyType.color,
          description:
              'The default foreground color for icons and text within the button.',
          defaultBrandToken: 'onPrimaryContainer',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0095'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'The button\'s background color.',
          defaultBrandToken: 'primaryContainer',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0096'),
          name: 'elevation',
          type: PropertyType.length,
          description:
              'The z-coordinate at which to place this button relative to its parent.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0097'),
          name: 'onPressed',
          type: PropertyType.event,
          description:
              'The callback that is called when the button is tapped or otherwise activated.',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0098'),
          name: 'mini',
          type: PropertyType.boolean,
          description: 'Controls the size of this button.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0272'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description: 'The shape of the button\'s [Material].',
        ),
        PropertyEntry(
          wireId: WireId('p0361'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '{@macro flutter.material.Material.clipBehavior}',
          enumType: 'Clip',
          defaultSource: LiteralDefault('none'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0020'),
      name: 'Icon',
      library: WidgetLibrary.material,
      category: WidgetCategory.decoration,
      description:
          'A graphical icon widget drawn with a glyph from a font described in an [IconData] such as material\'s predefined [IconData]s in [Icons].',
      flutterType: 'package:flutter/src/widgets/icon.dart#Icon',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0099'),
          name: 'size',
          type: PropertyType.length,
          description: 'The size of the icon in logical pixels.',
          defaultSource:
              ThemeBindingDefault(ThemeBindingPath.path('iconTheme.size')),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0100'),
          name: 'color',
          type: PropertyType.color,
          description: 'The color to use when drawing the icon.',
          defaultSource:
              ThemeBindingDefault(ThemeBindingPath.path('iconTheme.color')),
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0101'),
          name: 'iconCodepoint',
          type: PropertyType.integer,
          description: 'Material icon codepoint, e.g. 0xe145 for Icons.add.',
          required: true,
          synthetic: 'iconData',
          positional: true,
          priority: PropertyPriority.primary,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0021'),
      name: 'IconButton',
      library: WidgetLibrary.material,
      category: WidgetCategory.input,
      description: 'A Material Design icon button.',
      flutterType: 'package:flutter/src/material/icon_button.dart#IconButton',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onPressed],
      properties: [
        PropertyEntry(
          wireId: WireId('p0102'),
          name: 'iconSize',
          type: PropertyType.length,
          description: 'The size of the icon inside the button.',
          defaultSource: LiteralDefault(24.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0103'),
          name: 'color',
          type: PropertyType.color,
          description:
              'The color to use for the icon inside the button, if the icon is enabled. Defaults to leaving this up to the [icon] widget.',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0104'),
          name: 'onPressed',
          type: PropertyType.event,
          description:
              'The callback that is called when the button is tapped or otherwise activated.',
          required: true,
          category: PropertyCategory.behavior,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0105'),
          name: 'tooltip',
          type: PropertyType.string,
          description:
              'Text that describes the action that will occur when the button is pressed.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0106'),
          name: 'icon',
          type: PropertyType.widget,
          description: 'The icon to display inside the button.',
          required: true,
          priority: PropertyPriority.primary,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0022'),
      name: 'InkWell',
      library: WidgetLibrary.material,
      category: WidgetCategory.input,
      description: 'A rectangular area of a [Material] that responds to touch.',
      flutterType: 'package:flutter/src/material/ink_well.dart#InkWell',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onTap],
      properties: [
        PropertyEntry(
          wireId: WireId('p0107'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
        ),
        PropertyEntry(
          wireId: WireId('p0108'),
          name: 'onTap',
          type: PropertyType.event,
          description: '',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0273'),
          name: 'customBorder',
          type: PropertyType.shapeBorder,
          description: '',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0023'),
      name: 'LinearProgressIndicator',
      library: WidgetLibrary.material,
      category: WidgetCategory.decoration,
      description:
          'A Material Design linear progress indicator, also known as a progress bar.',
      flutterType:
          'package:flutter/src/material/progress_indicator.dart#LinearProgressIndicator',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0109'),
          name: 'value',
          type: PropertyType.real,
          description: '',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0315'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: '',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0110'),
          name: 'color',
          type: PropertyType.color,
          description: '',
          defaultBrandToken: 'primary',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0111'),
          name: 'minHeight',
          type: PropertyType.length,
          description:
              '{@template flutter.material.LinearProgressIndicator.minHeight} The minimum height of the line used to draw the linear indicator.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0024'),
      name: 'ListTile',
      library: WidgetLibrary.material,
      category: WidgetCategory.layout,
      description:
          'A single fixed-height row that typically contains some text as well as a leading or trailing icon.',
      flutterType: 'package:flutter/src/material/list_tile.dart#ListTile',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onTap],
      properties: [
        PropertyEntry(
          wireId: WireId('p0112'),
          name: 'leading',
          type: PropertyType.widget,
          description: 'A widget to display before the title.',
        ),
        PropertyEntry(
          wireId: WireId('p0113'),
          name: 'title',
          type: PropertyType.widget,
          description: 'The primary content of the list tile.',
        ),
        PropertyEntry(
          wireId: WireId('p0114'),
          name: 'subtitle',
          type: PropertyType.widget,
          description: 'Additional content displayed below the title.',
        ),
        PropertyEntry(
          wireId: WireId('p0115'),
          name: 'trailing',
          type: PropertyType.widget,
          description: 'A widget to display after the title.',
        ),
        PropertyEntry(
          wireId: WireId('p0274'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description:
              '{@template flutter.material.ListTile.shape} Defines the tile\'s [InkWell.customBorder] and [Ink.decoration] shape. {@endtemplate}',
        ),
        PropertyEntry(
          wireId: WireId('p0116'),
          name: 'onTap',
          type: PropertyType.event,
          description: 'Called when the user taps this list tile.',
          category: PropertyCategory.behavior,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0025'),
      name: 'MaterialApp',
      library: WidgetLibrary.material,
      category: WidgetCategory.layout,
      description: 'An application that uses Material Design.',
      flutterType: 'package:flutter/src/material/app.dart#MaterialApp',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0117'),
          name: 'home',
          type: PropertyType.widget,
          description: '{@macro flutter.widgets.widgetsApp.home}',
        ),
        PropertyEntry(
          wireId: WireId('p0118'),
          name: 'title',
          type: PropertyType.string,
          description: '{@macro flutter.widgets.widgetsApp.title}',
          defaultSource: LiteralDefault(''),
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0040'),
      name: 'RestageModalSheet',
      library: WidgetLibrary.material,
      category: WidgetCategory.action,
      description:
          'A modal bottom sheet that slides up over a scrim and can be dismissed by dragging it down or tapping the scrim — expressed as a purely declarative surface.',
      flutterType:
          'package:restage_material/src/widgets/restage_modal_sheet.dart#RestageModalSheet',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onSheetDismissed],
      properties: [
        PropertyEntry(
          wireId: WireId('p0316'),
          name: 'open',
          type: PropertyType.boolean,
          description:
              'Whether the sheet is shown. `true` slides it in; `false` slides it out (and, once the close animation finishes, removes it from the tree). The sole driver of visibility.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0317'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The sheet body.',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0318'),
          name: 'isDismissible',
          type: PropertyType.boolean,
          description:
              'When `true` (the default), tapping the scrim dismisses the sheet (fires [onSheetDismissed]).',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0319'),
          name: 'enableDrag',
          type: PropertyType.boolean,
          description:
              'When `true` (the default), the sheet can be dragged down and dismissed by swiping downward.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0320'),
          name: 'showDragHandle',
          type: PropertyType.boolean,
          description:
              'Whether a grab handle is shown at the top of the sheet. Null defers to the ambient bottom-sheet theme.',
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0321'),
          name: 'dragHandleColor',
          type: PropertyType.color,
          description:
              'The grab handle\'s color. Null defers to the theme default.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0322'),
          name: 'isScrollControlled',
          type: PropertyType.boolean,
          description:
              'When `true`, the sheet may grow past half the available height to fit its content (e.g. a scrollable body). When `false` (the default), the sheet is capped at [scrollControlDisabledMaxHeightRatio] of the available height.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0323'),
          name: 'scrollControlDisabledMaxHeightRatio',
          type: PropertyType.real,
          description:
              'The fraction of the available height the sheet may occupy when [isScrollControlled] is `false`. Defaults to `9/16`.',
          defaultSource: LiteralDefault(0.5625),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0324'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description:
              'The sheet\'s background color. Null defers to the theme default.',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0325'),
          name: 'elevation',
          type: PropertyType.real,
          description:
              'The sheet\'s elevation. Null defers to the theme default.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0326'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description:
              'The sheet\'s shape. Null defers to the theme default (rounded top corners under Material 3).',
        ),
        PropertyEntry(
          wireId: WireId('p0327'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description:
              'How to clip the sheet\'s content. Null defers to the theme default.',
          enumType: 'Clip',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0328'),
          name: 'useSafeArea',
          type: PropertyType.boolean,
          description:
              'When `true`, the sheet avoids system intrusions on the top, left, and right. Defaults to `false` (edge-to-edge, flush to the bottom).',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0329'),
          name: 'barrierColor',
          type: PropertyType.color,
          description: 'The scrim color. Null defaults to a translucent black.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0330'),
          name: 'barrierLabel',
          type: PropertyType.string,
          description:
              'Semantic label for the scrim, announced by assistive technology.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0331'),
          name: 'anchorPoint',
          type: PropertyType.offset,
          description:
              'The point used to disambiguate the sheet\'s placement on a display with hinges or folds. Null lets the framework choose.',
          valueShape: ScalarShape(
              propertyType: PropertyType.offset,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Offset')),
        ),
        PropertyEntry(
          wireId: WireId('p0333'),
          name: 'enterDuration',
          type: PropertyType.duration,
          description:
              'How long the slide-in takes on a programmatic open. Null uses the framework default (250ms).',
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0334'),
          name: 'exitDuration',
          type: PropertyType.duration,
          description:
              'How long the slide-out takes on a programmatic close. Null uses the framework default (200ms).',
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0335'),
          name: 'enterCurve',
          type: PropertyType.curve,
          description:
              'The easing curve for a programmatic open. Null uses the platform default (an eased curve); a drag always tracks the finger 1:1 regardless. Set it to tune the open feel.',
          valueShape: ScalarShape(
              propertyType: PropertyType.curve,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/animation/curves.dart',
                  symbolName: 'Curve')),
        ),
        PropertyEntry(
          wireId: WireId('p0336'),
          name: 'exitCurve',
          type: PropertyType.curve,
          description:
              'The easing curve for a programmatic close. Null uses the platform default. A drag always tracks the finger 1:1 regardless.',
          valueShape: ScalarShape(
              propertyType: PropertyType.curve,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/animation/curves.dart',
                  symbolName: 'Curve')),
        ),
        PropertyEntry(
          wireId: WireId('p0338'),
          name: 'presentation',
          type: PropertyType.enumValue,
          description:
              'How the sheet chooses its platform presentation. Defaults to [RestageSheetPresentation.adaptive] (the Material bottom sheet on Android, the Cupertino card sheet on iOS/macOS). Set [RestageSheetPresentation.material] or [RestageSheetPresentation.cupertino] to pin the sheet to that library on every platform.',
          enumType: 'RestageSheetPresentation',
          defaultSource: LiteralDefault('adaptive'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri:
                      'package:restage_material/src/widgets/restage_modal_sheet.dart',
                  symbolName: 'RestageSheetPresentation')),
        ),
        PropertyEntry(
          wireId: WireId('p0337'),
          name: 'underlay',
          type: PropertyType.widget,
          description:
              'The surface shown *beneath* the sheet, owned by this widget. When non-null and the platform is iOS/macOS, it scales down and rounds as the sheet rises (the iOS card-sheet look); on other platforms it renders plain behind the sheet. Null (the default) is a pure overlay — the sheet floats over whatever is already behind it, with no owned surface and no scale-down.',
        ),
        PropertyEntry(
          wireId: WireId('p0332'),
          name: 'onSheetDismissed',
          type: PropertyType.event,
          description:
              'Fires when the sheet is dismissed by a downward drag or a scrim tap. Distinct from the paywall-level dismiss: this is the *sheet* closing, not the surface that hosts it. Wire it back to `open = false`.',
          category: PropertyCategory.behavior,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0026'),
      name: 'RestagePager',
      library: WidgetLibrary.material,
      category: WidgetCategory.action,
      description:
          'Multi-page surface that hosts a swipeable sequence of child widgets.',
      flutterType:
          'package:restage_material/src/widgets/restage_pager.dart#RestagePager',
      childrenSlot: ChildrenSlot.list,
      fires: [WidgetEventName.onPageChanged],
      properties: [
        PropertyEntry(
          wireId: WireId('p0119'),
          name: 'children',
          type: PropertyType.widgetList,
          description: 'Pages displayed in order. Must be non-empty.',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0120'),
          name: 'initialPage',
          type: PropertyType.integer,
          description:
              'Index of the page shown when the pager first mounts. Defaults to `0`.',
          defaultSource: LiteralDefault(0),
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0121'),
          name: 'viewportFraction',
          type: PropertyType.real,
          description:
              'Fraction of the viewport occupied by each page. `1.0` (the default) shows one full page at a time; smaller values reveal adjacent pages at the edges of the viewport.',
          defaultSource: LiteralDefault(1.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0122'),
          name: 'scrollDirection',
          type: PropertyType.enumValue,
          description:
              'Direction users swipe to move between pages. Defaults to horizontal.',
          enumType: 'Axis',
          defaultSource: LiteralDefault('horizontal'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/basic_types.dart',
                  symbolName: 'Axis')),
        ),
        PropertyEntry(
          wireId: WireId('p0123'),
          name: 'pageSnapping',
          type: PropertyType.boolean,
          description:
              'When `true` (the default), the pager snaps to whole-page boundaries instead of allowing partial offsets.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0124'),
          name: 'onPageChanged',
          type: PropertyType.event,
          description:
              'Fires with the new page index when the visible page changes.',
          callbackSignature: 'ValueChanged<int>',
          category: PropertyCategory.behavior,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0042'),
      name: 'RestageRadioGroupString',
      library: WidgetLibrary.material,
      category: WidgetCategory.input,
      description:
          'A single-select radio group expressed as a purely declarative surface.',
      flutterType:
          'package:restage_material/src/widgets/restage_radio_group.dart#RestageRadioGroup<String>',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onChanged],
      properties: [
        PropertyEntry(
          wireId: WireId('p0399'),
          name: 'items',
          type: PropertyType.selectionOptionList,
          description:
              'The selectable options, in display order. Each becomes one radio row. An empty list renders nothing.',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0400'),
          name: 'selected',
          type: PropertyType.string,
          description:
              'The currently-selected option value. The row whose value equals this is checked; `null` (or a value matching no row) leaves the group unselected.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0401'),
          name: 'onChanged',
          type: PropertyType.event,
          description:
              'Fires with the newly-selected value when the user taps a row. `null` disables selection (the rows render but do not respond).',
          callbackSignature: 'ValueChanged<String?>',
          category: PropertyCategory.behavior,
        ),
      ],
      sinceVersion: 2,
    ),
    WidgetEntry(
      wireId: WireId('w0043'),
      name: 'RestageDropdownString',
      library: WidgetLibrary.material,
      category: WidgetCategory.input,
      description:
          'A single-select dropdown expressed as a purely declarative surface.',
      flutterType:
          'package:restage_material/src/widgets/restage_dropdown.dart#RestageDropdown<String>',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onChanged],
      properties: [
        PropertyEntry(
          wireId: WireId('p0402'),
          name: 'items',
          type: PropertyType.selectionOptionList,
          description:
              'The selectable options, in menu order. Each becomes one menu item. An empty list renders nothing.',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0403'),
          name: 'selected',
          type: PropertyType.string,
          description:
              'The currently-selected option value, shown as the field\'s current value. `null` (or a value matching no option) shows the [hint].',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0404'),
          name: 'onChanged',
          type: PropertyType.event,
          description:
              'Fires with the newly-selected value when the user picks an option. `null` disables the dropdown (it renders but does not open).',
          callbackSignature: 'ValueChanged<String?>',
          category: PropertyCategory.behavior,
        ),
      ],
      sinceVersion: 2,
    ),
    WidgetEntry(
      wireId: WireId('w0044'),
      name: 'RestageToggleButtons',
      library: WidgetLibrary.material,
      category: WidgetCategory.input,
      description:
          'A horizontal set of mutually-independent toggle buttons expressed as a purely declarative surface.',
      flutterType:
          'package:restage_material/src/widgets/restage_toggle_buttons.dart#RestageToggleButtons',
      childrenSlot: ChildrenSlot.list,
      fires: [WidgetEventName.onPressed],
      properties: [
        PropertyEntry(
          wireId: WireId('p0405'),
          name: 'children',
          type: PropertyType.widgetList,
          description:
              'The per-button labels, in display order. Each becomes one toggle button. An empty list renders nothing.',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0406'),
          name: 'isSelected',
          type: PropertyType.booleanList,
          description:
              'Each button\'s pressed state, by index, parallel to [children]. Reconciled to [children]\'s length when the two differ (pad-with-false / truncate), so a mismatched wire never trips the framework\'s length assert.',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0407'),
          name: 'onPressed',
          type: PropertyType.event,
          description:
              'Fires with the pressed button\'s index when the user presses a button. `null` disables the set (the buttons render but do not respond).',
          callbackSignature: 'ValueChanged<int>',
          category: PropertyCategory.behavior,
        ),
      ],
      sinceVersion: 3,
    ),
    WidgetEntry(
      wireId: WireId('w0045'),
      name: 'RestageSegmentedButtonString',
      library: WidgetLibrary.material,
      category: WidgetCategory.input,
      description:
          'A segmented button (single- or multi-select) expressed as a purely declarative surface.',
      flutterType:
          'package:restage_material/src/widgets/restage_segmented_button.dart#RestageSegmentedButton<String>',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onChanged],
      properties: [
        PropertyEntry(
          wireId: WireId('p0408'),
          name: 'items',
          type: PropertyType.selectionOptionList,
          description:
              'The selectable segments, in display order. Each becomes one segment. An empty list renders nothing.',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0409'),
          name: 'selected',
          type: PropertyType.stringList,
          description:
              'The currently-selected segment values. Segments whose value is in this list are shown selected; values absent from [items] are ignored. In single-select mode (the default) only the first (in segment order) is honored. `null` (or an empty list) is no initial selection.',
          valueShape: ListShape(
              propertyType: PropertyType.stringList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.string,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'String'))),
        ),
        PropertyEntry(
          wireId: WireId('p0410'),
          name: 'onChanged',
          type: PropertyType.event,
          description:
              'Fires with the whole settled selection — a `List<T>` in **segment order** — when the user changes the selection. `null` leaves the button non-interactive (it renders the initial selection but does not respond).',
          callbackSignature: 'ValueChanged<List<String>>',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0411'),
          name: 'multiSelectionEnabled',
          type: PropertyType.boolean,
          description:
              'Whether more than one segment may be selected at once. Defaults to `false` (single-select — the dominant case).',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0412'),
          name: 'emptySelectionAllowed',
          type: PropertyType.boolean,
          description:
              'Whether the user may deselect down to an empty selection. Defaults to `false`. (A degenerate wire whose effective selection is already empty is always tolerated regardless of this flag — see the class docs.)',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0413'),
          name: 'showSelectedIcon',
          type: PropertyType.boolean,
          description:
              'Whether a checkmark icon is shown on selected segments. Defaults to `true` (the framework default).',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
      ],
      sinceVersion: 4,
    ),
    WidgetEntry(
      wireId: WireId('w0041'),
      name: 'RestageDraggableSheet',
      library: WidgetLibrary.material,
      category: WidgetCategory.action,
      description:
          'A persistent, resizable bottom sheet the user drags between a peek size and a fully-expanded size — expressed as a purely declarative surface. Unlike [RestageModalSheet] it never dismisses: it bottoms out at [minChildSize] and stays in the layout.',
      flutterType:
          'package:restage_material/src/widgets/restage_draggable_sheet.dart#RestageDraggableSheet',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0339'),
          name: 'child',
          type: PropertyType.widget,
          description:
              'The sheet body. Wrapped in a [SingleChildScrollView] bound to the sheet\'s drag controller, so the whole sheet is draggable and the body scrolls once the sheet is fully expanded.',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0340'),
          name: 'initialChildSize',
          type: PropertyType.real,
          description:
              'The fraction of the parent\'s height the sheet occupies at rest (the peek). Defaults to `0.5`.',
          defaultSource: LiteralDefault(0.5),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0341'),
          name: 'minChildSize',
          type: PropertyType.real,
          description:
              'The minimum fraction the sheet can be dragged to — the persistent floor. The sheet never dismisses below it. Defaults to `0.25`.',
          defaultSource: LiteralDefault(0.25),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0342'),
          name: 'maxChildSize',
          type: PropertyType.real,
          description:
              'The maximum fraction the sheet expands to. Defaults to `1.0`.',
          defaultSource: LiteralDefault(1.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0343'),
          name: 'expand',
          type: PropertyType.boolean,
          description:
              'Whether the sheet expands to fill the available space in its parent. Defaults to `true`.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0344'),
          name: 'snap',
          type: PropertyType.boolean,
          description:
              'Whether the sheet snaps between [snapSizes] when the user lifts their finger during a drag. Defaults to `false`.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0345'),
          name: 'snapAnimationDuration',
          type: PropertyType.duration,
          description:
              'The duration of a snap animation. Null lets the framework derive it from the fling velocity.',
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0346'),
          name: 'expanded',
          type: PropertyType.boolean,
          description:
              'Whether the sheet is expanded. Flip to `true` to animate the sheet to [maxChildSize]; flip to `false` to animate back to [initialChildSize] (the peek). This is the sole programmatic driver; a manual drag is independent. `true` at initial mount shows the sheet expanded instantly, with no animation.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0347'),
          name: 'expandDuration',
          type: PropertyType.duration,
          description:
              'How long the [expanded]-driven expand/collapse takes. Null uses the framework default (250ms).',
          valueShape: ScalarShape(
              propertyType: PropertyType.duration,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'Duration')),
        ),
        PropertyEntry(
          wireId: WireId('p0348'),
          name: 'expandCurve',
          type: PropertyType.curve,
          description:
              'The easing curve for the [expanded]-driven expand/collapse. Null uses the framework default (an eased curve). A manual drag is unaffected.',
          valueShape: ScalarShape(
              propertyType: PropertyType.curve,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/animation/curves.dart',
                  symbolName: 'Curve')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0027'),
      name: 'OutlinedButton',
      library: WidgetLibrary.material,
      category: WidgetCategory.action,
      description:
          'A Material Design "Outlined Button"; essentially a [TextButton] with an outlined border.',
      flutterType:
          'package:flutter/src/material/outlined_button.dart#OutlinedButton',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onPressed],
      properties: [
        PropertyEntry(
          wireId: WireId('p0125'),
          name: 'onPressed',
          type: PropertyType.event,
          description: '',
          required: true,
          category: PropertyCategory.behavior,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0362'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'Clip',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0126'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0127'),
          name: 'foregroundColor',
          type: PropertyType.color,
          description: 'Foreground color (text + icons).',
          defaultBrandToken: 'primary',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0128'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description: 'Padding inside the button.',
          defaultSource: LiteralDefault([24.0, 12.0, 24.0, 12.0]),
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0275'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description: 'Button outline shape.',
          valueShape: UnionShape(
              propertyType: PropertyType.shapeBorder,
              unionRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('u0005')),
              wireCodec: CatalogWireCodec.rfwShapeBorder),
        ),
        PropertyEntry(
          wireId: WireId('p0379'),
          name: 'minimumSize',
          type: PropertyType.structured,
          description: 'Minimum button size (width, height).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0025'))),
        ),
        PropertyEntry(
          wireId: WireId('p0380'),
          name: 'fixedSize',
          type: PropertyType.structured,
          description: 'Fixed button size (width, height).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0025'))),
        ),
        PropertyEntry(
          wireId: WireId('p0381'),
          name: 'side',
          type: PropertyType.structured,
          description: 'Button border side (color, width, style).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0003'))),
        ),
        PropertyEntry(
          wireId: WireId('p0382'),
          name: 'textStyle',
          type: PropertyType.structured,
          description: 'Button label text style.',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0002'))),
        ),
        PropertyEntry(
          wireId: WireId('p0129'),
          name: 'disabled',
          type: PropertyType.boolean,
          description: 'Whether the button is disabled.',
          synthetic: 'gateOnPressed',
          defaultSource: LiteralDefault(false),
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0001')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'style',
          construction: FactoryInvocation(
              variantRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('v0001')),
              receiver: OwningWidgetTypeReceiver(),
              memberName: 'styleFrom'),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0188'),
              propertyRef: WireId('p0127'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0189'),
              propertyRef: WireId('p0128'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0259'),
              propertyRef: WireId('p0275'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0395'),
              propertyRef: WireId('p0379'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0396'),
              propertyRef: WireId('p0380'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0397'),
              propertyRef: WireId('p0381'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0398'),
              propertyRef: WireId('p0382'),
              transform: IdentityTransform(),
            ),
          ],
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0028'),
      name: 'OutlinedButtonIcon',
      library: WidgetLibrary.material,
      category: WidgetCategory.action,
      description: 'A secondary call-to-action button with a leading icon.',
      flutterType:
          'package:flutter/src/material/outlined_button.dart#OutlinedButton.icon',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onPressed],
      properties: [
        PropertyEntry(
          wireId: WireId('p0130'),
          name: 'onPressed',
          type: PropertyType.event,
          description: '',
          required: true,
          category: PropertyCategory.behavior,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0363'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'Clip',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0131'),
          name: 'icon',
          type: PropertyType.widget,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0132'),
          name: 'label',
          type: PropertyType.widget,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0133'),
          name: 'foregroundColor',
          type: PropertyType.color,
          description: 'Foreground color (text + icons).',
          defaultBrandToken: 'primary',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0134'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description: 'Padding inside the button.',
          defaultSource: LiteralDefault([24.0, 12.0, 24.0, 12.0]),
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0276'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description: 'Button outline shape.',
          valueShape: UnionShape(
              propertyType: PropertyType.shapeBorder,
              unionRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('u0005')),
              wireCodec: CatalogWireCodec.rfwShapeBorder),
        ),
        PropertyEntry(
          wireId: WireId('p0383'),
          name: 'minimumSize',
          type: PropertyType.structured,
          description: 'Minimum button size (width, height).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0025'))),
        ),
        PropertyEntry(
          wireId: WireId('p0384'),
          name: 'fixedSize',
          type: PropertyType.structured,
          description: 'Fixed button size (width, height).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0025'))),
        ),
        PropertyEntry(
          wireId: WireId('p0385'),
          name: 'side',
          type: PropertyType.structured,
          description: 'Button border side (color, width, style).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0003'))),
        ),
        PropertyEntry(
          wireId: WireId('p0386'),
          name: 'textStyle',
          type: PropertyType.structured,
          description: 'Button label text style.',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0002'))),
        ),
        PropertyEntry(
          wireId: WireId('p0135'),
          name: 'disabled',
          type: PropertyType.boolean,
          description: 'Whether the button is disabled.',
          synthetic: 'gateOnPressed',
          defaultSource: LiteralDefault(false),
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0001')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'style',
          construction: FactoryInvocation(
              variantRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('v0001')),
              receiver: OwningWidgetTypeReceiver(),
              memberName: 'styleFrom'),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0188'),
              propertyRef: WireId('p0133'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0189'),
              propertyRef: WireId('p0134'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0259'),
              propertyRef: WireId('p0276'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0395'),
              propertyRef: WireId('p0383'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0396'),
              propertyRef: WireId('p0384'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0397'),
              propertyRef: WireId('p0385'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0398'),
              propertyRef: WireId('p0386'),
              transform: IdentityTransform(),
            ),
          ],
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0029'),
      name: 'Package',
      library: WidgetLibrary.material,
      category: WidgetCategory.action,
      description: 'Binds a child widget tree to a configured product slot.',
      flutterType: 'package:restage_material/src/widgets/package.dart#Package',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0136'),
          name: 'slot',
          type: PropertyType.string,
          description:
              'Identifier matched against the host app\'s product configuration (for example `\'primary\'`, `\'secondary\'`, `\'tertiary\'`).',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0137'),
          name: 'child',
          type: PropertyType.widget,
          description:
              'UI bound to the resolved product. Descendants may read price and metadata via the standard product-resolution helpers.',
          required: true,
          priority: PropertyPriority.primary,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0030'),
      name: 'Scaffold',
      library: WidgetLibrary.material,
      category: WidgetCategory.layout,
      description:
          'Implements the basic Material Design visual layout structure.',
      flutterType: 'package:flutter/src/material/scaffold.dart#Scaffold',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0138'),
          name: 'body',
          type: PropertyType.widget,
          description: 'The primary content of the scaffold.',
        ),
        PropertyEntry(
          wireId: WireId('p0139'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description:
              'The color of the [Material] widget that underlies the entire Scaffold.',
          defaultBrandToken: 'background',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0031'),
      name: 'Scrollbar',
      library: WidgetLibrary.material,
      category: WidgetCategory.layout,
      description: 'A Material Design scrollbar.',
      flutterType: 'package:flutter/src/material/scrollbar.dart#Scrollbar',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0140'),
          name: 'child',
          type: PropertyType.widget,
          description: '{@macro flutter.widgets.Scrollbar.child}',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0141'),
          name: 'thumbVisibility',
          type: PropertyType.boolean,
          description: '{@macro flutter.widgets.Scrollbar.thumbVisibility}',
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0142'),
          name: 'trackVisibility',
          type: PropertyType.boolean,
          description: '{@macro flutter.widgets.Scrollbar.trackVisibility}',
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0143'),
          name: 'thickness',
          type: PropertyType.length,
          description:
              'The thickness of the scrollbar in the cross axis of the scrollable.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0144'),
          name: 'interactive',
          type: PropertyType.boolean,
          description: '{@macro flutter.widgets.Scrollbar.interactive}',
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0032'),
      name: 'Slider',
      library: WidgetLibrary.material,
      category: WidgetCategory.input,
      description: 'A Material Design slider.',
      flutterType: 'package:flutter/src/material/slider.dart#Slider',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onChanged],
      properties: [
        PropertyEntry(
          wireId: WireId('p0145'),
          name: 'value',
          type: PropertyType.real,
          description: 'The currently selected value for this slider.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0146'),
          name: 'secondaryTrackValue',
          type: PropertyType.real,
          description: 'The secondary track value for this slider.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0147'),
          name: 'onChanged',
          type: PropertyType.event,
          description:
              'Called during a drag when the user is selecting a new value for the slider by dragging.',
          callbackSignature: 'ValueChanged<double>',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0148'),
          name: 'min',
          type: PropertyType.real,
          description: 'The minimum value the user can select.',
          defaultSource: LiteralDefault(0.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0149'),
          name: 'max',
          type: PropertyType.real,
          description: 'The maximum value the user can select.',
          defaultSource: LiteralDefault(1.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0150'),
          name: 'divisions',
          type: PropertyType.integer,
          description: 'The number of discrete divisions.',
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0151'),
          name: 'label',
          type: PropertyType.string,
          description:
              'A label to show above the slider when the slider is active and [SliderThemeData.showValueIndicator] is satisfied.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0033'),
      name: 'Switch',
      library: WidgetLibrary.material,
      category: WidgetCategory.input,
      description: 'A Material Design switch.',
      flutterType: 'package:flutter/src/material/switch.dart#Switch',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onChanged],
      properties: [
        PropertyEntry(
          wireId: WireId('p0152'),
          name: 'value',
          type: PropertyType.boolean,
          description: 'Whether this switch is on or off.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0153'),
          name: 'onChanged',
          type: PropertyType.event,
          description: 'Called when the user toggles the switch on or off.',
          required: true,
          callbackSignature: 'ValueChanged<bool>',
          category: PropertyCategory.behavior,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0154'),
          name: 'activeThumbColor',
          type: PropertyType.color,
          description:
              '{@template flutter.material.switch.activeThumbColor} The color to use when this switch is on. {@endtemplate}',
          defaultBrandToken: 'primary',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0034'),
      name: 'SwitchListTile',
      library: WidgetLibrary.material,
      category: WidgetCategory.input,
      description:
          'A [ListTile] with a [Switch]. In other words, a switch with a label.',
      flutterType:
          'package:flutter/src/material/switch_list_tile.dart#SwitchListTile',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onChanged],
      properties: [
        PropertyEntry(
          wireId: WireId('p0155'),
          name: 'value',
          type: PropertyType.boolean,
          description: 'Whether this switch is checked.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0156'),
          name: 'onChanged',
          type: PropertyType.event,
          description: 'Called when the user toggles the switch on or off.',
          required: true,
          callbackSignature: 'ValueChanged<bool>',
          category: PropertyCategory.behavior,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0157'),
          name: 'activeThumbColor',
          type: PropertyType.color,
          description: '{@macro flutter.material.switch.activeThumbColor}',
          defaultBrandToken: 'primary',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0158'),
          name: 'title',
          type: PropertyType.widget,
          description: 'The primary content of the list tile.',
        ),
        PropertyEntry(
          wireId: WireId('p0159'),
          name: 'subtitle',
          type: PropertyType.widget,
          description: 'Additional content displayed below the title.',
        ),
        PropertyEntry(
          wireId: WireId('p0160'),
          name: 'secondary',
          type: PropertyType.widget,
          description:
              'A widget to display on the opposite side of the tile from the switch.',
        ),
        PropertyEntry(
          wireId: WireId('p0277'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description: '{@macro flutter.material.ListTile.shape}',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0035'),
      name: 'TextButton',
      library: WidgetLibrary.material,
      category: WidgetCategory.action,
      description: 'A Material Design "Text Button".',
      flutterType: 'package:flutter/src/material/text_button.dart#TextButton',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onPressed],
      properties: [
        PropertyEntry(
          wireId: WireId('p0161'),
          name: 'onPressed',
          type: PropertyType.event,
          description: '',
          required: true,
          category: PropertyCategory.behavior,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0364'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'Clip',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0162'),
          name: 'child',
          type: PropertyType.widget,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0163'),
          name: 'foregroundColor',
          type: PropertyType.color,
          description: 'Foreground color (text + icons).',
          defaultBrandToken: 'primary',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0164'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description: 'Padding inside the button.',
          defaultSource: LiteralDefault([24.0, 12.0, 24.0, 12.0]),
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0278'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description: 'Button outline shape.',
          valueShape: UnionShape(
              propertyType: PropertyType.shapeBorder,
              unionRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('u0005')),
              wireCodec: CatalogWireCodec.rfwShapeBorder),
        ),
        PropertyEntry(
          wireId: WireId('p0387'),
          name: 'minimumSize',
          type: PropertyType.structured,
          description: 'Minimum button size (width, height).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0025'))),
        ),
        PropertyEntry(
          wireId: WireId('p0388'),
          name: 'fixedSize',
          type: PropertyType.structured,
          description: 'Fixed button size (width, height).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0025'))),
        ),
        PropertyEntry(
          wireId: WireId('p0389'),
          name: 'side',
          type: PropertyType.structured,
          description: 'Button border side (color, width, style).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0003'))),
        ),
        PropertyEntry(
          wireId: WireId('p0390'),
          name: 'textStyle',
          type: PropertyType.structured,
          description: 'Button label text style.',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0002'))),
        ),
        PropertyEntry(
          wireId: WireId('p0165'),
          name: 'disabled',
          type: PropertyType.boolean,
          description: 'Whether the button is disabled.',
          synthetic: 'gateOnPressed',
          defaultSource: LiteralDefault(false),
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0001')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'style',
          construction: FactoryInvocation(
              variantRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('v0001')),
              receiver: OwningWidgetTypeReceiver(),
              memberName: 'styleFrom'),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0188'),
              propertyRef: WireId('p0163'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0189'),
              propertyRef: WireId('p0164'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0259'),
              propertyRef: WireId('p0278'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0395'),
              propertyRef: WireId('p0387'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0396'),
              propertyRef: WireId('p0388'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0397'),
              propertyRef: WireId('p0389'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0398'),
              propertyRef: WireId('p0390'),
              transform: IdentityTransform(),
            ),
          ],
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0036'),
      name: 'TextButtonIcon',
      library: WidgetLibrary.material,
      category: WidgetCategory.action,
      description: 'A low-emphasis text-only button with a leading icon.',
      flutterType:
          'package:flutter/src/material/text_button.dart#TextButton.icon',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onPressed],
      properties: [
        PropertyEntry(
          wireId: WireId('p0166'),
          name: 'onPressed',
          type: PropertyType.event,
          description: '',
          required: true,
          category: PropertyCategory.behavior,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0365'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '',
          enumType: 'Clip',
          defaultSource: LiteralDefault('none'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
        PropertyEntry(
          wireId: WireId('p0167'),
          name: 'icon',
          type: PropertyType.widget,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0168'),
          name: 'label',
          type: PropertyType.widget,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0169'),
          name: 'foregroundColor',
          type: PropertyType.color,
          description: 'Foreground color (text + icons).',
          defaultBrandToken: 'primary',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0170'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description: 'Padding inside the button.',
          defaultSource: LiteralDefault([24.0, 12.0, 24.0, 12.0]),
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0279'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description: 'Button outline shape.',
          valueShape: UnionShape(
              propertyType: PropertyType.shapeBorder,
              unionRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('u0005')),
              wireCodec: CatalogWireCodec.rfwShapeBorder),
        ),
        PropertyEntry(
          wireId: WireId('p0391'),
          name: 'minimumSize',
          type: PropertyType.structured,
          description: 'Minimum button size (width, height).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0025'))),
        ),
        PropertyEntry(
          wireId: WireId('p0392'),
          name: 'fixedSize',
          type: PropertyType.structured,
          description: 'Fixed button size (width, height).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0025'))),
        ),
        PropertyEntry(
          wireId: WireId('p0393'),
          name: 'side',
          type: PropertyType.structured,
          description: 'Button border side (color, width, style).',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0003'))),
        ),
        PropertyEntry(
          wireId: WireId('p0394'),
          name: 'textStyle',
          type: PropertyType.structured,
          description: 'Button label text style.',
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0002'))),
        ),
        PropertyEntry(
          wireId: WireId('p0171'),
          name: 'disabled',
          type: PropertyType.boolean,
          description: 'Whether the button is disabled.',
          synthetic: 'gateOnPressed',
          defaultSource: LiteralDefault(false),
        ),
      ],
      decomposes: [
        DecompositionRecipe(
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0001')),
          flatProperties: <WireId, WireId>{},
          targetArg: 'style',
          construction: FactoryInvocation(
              variantRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('v0001')),
              receiver: OwningWidgetTypeReceiver(),
              memberName: 'styleFrom'),
          fieldMappings: [
            DecompositionFieldMapping(
              fieldRef: WireId('p0188'),
              propertyRef: WireId('p0169'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0189'),
              propertyRef: WireId('p0170'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0259'),
              propertyRef: WireId('p0279'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0395'),
              propertyRef: WireId('p0391'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0396'),
              propertyRef: WireId('p0392'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0397'),
              propertyRef: WireId('p0393'),
              transform: IdentityTransform(),
            ),
            DecompositionFieldMapping(
              fieldRef: WireId('p0398'),
              propertyRef: WireId('p0394'),
              transform: IdentityTransform(),
            ),
          ],
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0037'),
      name: 'Tab',
      library: WidgetLibrary.material,
      category: WidgetCategory.layout,
      description: 'A Material Design [TabBar] tab.',
      flutterType: 'package:flutter/src/material/tabs.dart#Tab',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0172'),
          name: 'text',
          type: PropertyType.string,
          description: 'The text to display as the tab\'s label.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0173'),
          name: 'icon',
          type: PropertyType.widget,
          description: 'An icon to display as the tab\'s label.',
        ),
        PropertyEntry(
          wireId: WireId('p0174'),
          name: 'iconMargin',
          type: PropertyType.edgeInsets,
          description: 'The margin added around the tab\'s icon.',
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0175'),
          name: 'height',
          type: PropertyType.length,
          description: 'The height of the [Tab].',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0176'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget to be used as the tab\'s label.',
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0038'),
      name: 'TextField',
      library: WidgetLibrary.material,
      category: WidgetCategory.input,
      description: 'A Material Design text field.',
      flutterType: 'package:flutter/src/material/text_field.dart#TextField',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onChanged, WidgetEventName.onSubmitted],
      properties: [
        PropertyEntry(
          wireId: WireId('p0177'),
          name: 'obscureText',
          type: PropertyType.boolean,
          description: '{@macro flutter.widgets.editableText.obscureText}',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0178'),
          name: 'maxLines',
          type: PropertyType.integer,
          description:
              '{@macro flutter.widgets.editableText.maxLines} * [expands], which determines whether the field should fill the height of its parent.',
          defaultSource: LiteralDefault(1),
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0179'),
          name: 'maxLength',
          type: PropertyType.integer,
          description:
              'The maximum number of characters (Unicode grapheme clusters) to allow in the text field.',
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0180'),
          name: 'onChanged',
          type: PropertyType.event,
          description: '{@macro flutter.widgets.editableText.onChanged}',
          callbackSignature: 'ValueChanged<String>',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0181'),
          name: 'onSubmitted',
          type: PropertyType.event,
          description: '{@macro flutter.widgets.editableText.onSubmitted}',
          callbackSignature: 'ValueChanged<String>',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0366'),
          name: 'clipBehavior',
          type: PropertyType.enumValue,
          description: '{@macro flutter.material.Material.clipBehavior}',
          enumType: 'Clip',
          defaultSource: LiteralDefault('hardEdge'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Clip')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0039'),
      name: 'Tooltip',
      library: WidgetLibrary.material,
      category: WidgetCategory.decoration,
      description: 'A Material Design tooltip.',
      flutterType: 'package:flutter/src/material/tooltip.dart#Tooltip',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0182'),
          name: 'message',
          type: PropertyType.string,
          description: 'The text to display in the tooltip.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0183'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description:
              'The amount of space by which to inset the [Tooltip]\'s message.',
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0184'),
          name: 'margin',
          type: PropertyType.edgeInsets,
          description: 'The empty space that surrounds the tooltip.',
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0185'),
          name: 'preferBelow',
          type: PropertyType.boolean,
          description:
              'Whether the tooltip defaults to being displayed below the widget.',
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0186'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
        ),
      ],
    ),
  ],
  structuredTypes: [
    StructuredEntry(
      wireId: WireId('s0002'),
      name: 'TextStyle',
      library: WidgetLibrary.material,
      description:
          'An immutable style describing how to format and paint text.',
      sourceType: 'package:flutter/src/painting/text_style.dart#TextStyle',
      fields: [
        StructuredField(
          wireId: WireId('p0191'),
          name: 'inherit',
          type: PropertyType.boolean,
          description:
              'Whether null values in this [TextStyle] can be replaced with their value in another [TextStyle] using [merge].',
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        StructuredField(
          wireId: WireId('p0192'),
          name: 'color',
          type: PropertyType.color,
          description: 'The color to use when painting the text.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        StructuredField(
          wireId: WireId('p0193'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'The color to use as the background for the text.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        StructuredField(
          wireId: WireId('p0194'),
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
          wireId: WireId('p0291'),
          name: 'fontFamilyFallback',
          type: PropertyType.stringList,
          description: '',
          valueShape: ListShape(
              propertyType: PropertyType.stringList,
              itemShape: ScalarShape(
                  propertyType: PropertyType.string,
                  dartTypeRef: DartTypeRef(
                      libraryUri: 'dart:core', symbolName: 'String'))),
        ),
        StructuredField(
          wireId: WireId('p0195'),
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
          wireId: WireId('p0292'),
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
          wireId: WireId('p0293'),
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
          wireId: WireId('p0196'),
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
          wireId: WireId('p0197'),
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
          wireId: WireId('p0198'),
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
          wireId: WireId('p0294'),
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
          wireId: WireId('p0295'),
          name: 'foreground',
          type: PropertyType.paint,
          description: 'The paint drawn as a foreground for the text.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        StructuredField(
          wireId: WireId('p0296'),
          name: 'background',
          type: PropertyType.paint,
          description: 'The paint drawn as a background for the text.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        StructuredField(
          wireId: WireId('p0297'),
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
          wireId: WireId('p0199'),
          name: 'decorationColor',
          type: PropertyType.color,
          description: 'The color in which to paint the text decorations.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        StructuredField(
          wireId: WireId('p0298'),
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
          wireId: WireId('p0200'),
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
          wireId: WireId('p0201'),
          name: 'debugLabel',
          type: PropertyType.string,
          description: 'A human-readable description of this text style.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        StructuredField(
          wireId: WireId('p0299'),
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
          wireId: WireId('p0300'),
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
          wireId: WireId('p0301'),
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
          wireId: WireId('p0302'),
          name: 'overflow',
          type: PropertyType.enumValue,
          description: 'How visual text overflow should be handled.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/text_painter.dart',
                  symbolName: 'TextOverflow')),
        ),
      ],
      variants: [
        StaticMethodVariant(
          wireId: WireId('v0002'),
          staticAccessor: 'lerp',
          description:
              'Interpolate between two text styles for animated transitions.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0003'),
      name: 'BorderSide',
      library: WidgetLibrary.material,
      description: 'A side of a border of a box.',
      sourceType: 'package:flutter/src/painting/borders.dart#BorderSide',
      fields: [
        StructuredField(
          wireId: WireId('p0203'),
          name: 'color',
          type: PropertyType.color,
          description: 'The color of this side of the border.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        StructuredField(
          wireId: WireId('p0204'),
          name: 'width',
          type: PropertyType.real,
          description:
              'The width of this side of the border, in logical pixels.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0303'),
          name: 'style',
          type: PropertyType.enumValue,
          description: 'The style of this side of the border.',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/borders.dart',
                  symbolName: 'BorderStyle')),
        ),
        StructuredField(
          wireId: WireId('p0205'),
          name: 'strokeAlign',
          type: PropertyType.real,
          description:
              'The relative position of the stroke on a [BorderSide] in an [OutlinedBorder] or [Border].',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0003'),
          argMappings: {
            'color': ArgMapping(targetFields: [WireId('p0203')]),
            'strokeAlign': ArgMapping(targetFields: [WireId('p0205')]),
            'style': ArgMapping(targetFields: [WireId('p0303')]),
            'width': ArgMapping(targetFields: [WireId('p0204')]),
          },
          description: 'Creates the side of a border.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0004'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two border sides.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0005'),
          staticAccessor: 'merge',
          description:
              'Creates a [BorderSide] that represents the addition of the two given [BorderSide]s.',
        ),
        ConstValueVariant(
          wireId: WireId('v0007'),
          staticAccessor: 'none',
          description: 'A hairline black border that is not rendered.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0001'),
      name: 'ButtonStyle',
      library: WidgetLibrary.material,
      description: 'ButtonStyle value.',
      sourceType: 'package:flutter/src/material/button_style.dart#ButtonStyle',
      fields: [
        StructuredField(
          wireId: WireId('p0187'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'Background color.',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        StructuredField(
          wireId: WireId('p0188'),
          name: 'foregroundColor',
          type: PropertyType.color,
          description: 'Foreground color (text + icons).',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        StructuredField(
          wireId: WireId('p0189'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description: 'Padding inside the button.',
          defaultSource: LiteralDefault([24.0, 12.0, 24.0, 12.0]),
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        StructuredField(
          wireId: WireId('p0190'),
          name: 'elevation',
          type: PropertyType.length,
          description: 'Material elevation in logical pixels.',
          defaultSource: LiteralDefault(1.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.length,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0259'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description: 'Button outline shape.',
          unionRef:
              WireIdRef(library: 'restage.material', wireId: WireId('u0005')),
          valueShape: UnionShape(
              propertyType: PropertyType.shapeBorder,
              unionRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('u0005')),
              wireCodec: CatalogWireCodec.rfwShapeBorder),
        ),
        StructuredField(
          wireId: WireId('p0395'),
          name: 'minimumSize',
          type: PropertyType.structured,
          description: 'Minimum button size (width, height).',
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0025')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0025'))),
        ),
        StructuredField(
          wireId: WireId('p0396'),
          name: 'fixedSize',
          type: PropertyType.structured,
          description: 'Fixed button size (width, height).',
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0025')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0025'))),
        ),
        StructuredField(
          wireId: WireId('p0397'),
          name: 'side',
          type: PropertyType.structured,
          description: 'Button border side (color, width, style).',
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0003'))),
        ),
        StructuredField(
          wireId: WireId('p0398'),
          name: 'textStyle',
          type: PropertyType.structured,
          description: 'Button label text style.',
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0002')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0002'))),
        ),
      ],
      variants: [
        StaticMethodVariant(
          wireId: WireId('v0001'),
          staticAccessor: 'styleFrom',
          argMappings: {
            'backgroundColor': ArgMapping(targetFields: [WireId('p0187')]),
            'elevation': ArgMapping(targetFields: [WireId('p0190')]),
            'fixedSize': ArgMapping(targetFields: [WireId('p0396')]),
            'foregroundColor': ArgMapping(targetFields: [WireId('p0188')]),
            'minimumSize': ArgMapping(targetFields: [WireId('p0395')]),
            'padding': ArgMapping(targetFields: [WireId('p0189')]),
            'shape': ArgMapping(targetFields: [WireId('p0259')]),
            'side': ArgMapping(targetFields: [WireId('p0397')]),
            'textStyle': ArgMapping(targetFields: [WireId('p0398')]),
          },
          parameters: [
            FactoryParameter(
              wireId: WireId('a0001'),
              name: 'foregroundColor',
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
              wireId: WireId('a0002'),
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
              wireId: WireId('a0003'),
              name: 'elevation',
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
              wireId: WireId('a0008'),
              name: 'textStyle',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: StructuredShape(
                  propertyType: PropertyType.structured,
                  structuredRef: WireIdRef(
                      library: 'restage.material', wireId: WireId('s0002'))),
            ),
            FactoryParameter(
              wireId: WireId('a0004'),
              name: 'padding',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: ScalarShape(
                  propertyType: PropertyType.edgeInsets,
                  dartTypeRef: DartTypeRef(
                      libraryUri:
                          'package:flutter/src/painting/edge_insets.dart',
                      symbolName: 'EdgeInsetsGeometry')),
            ),
            FactoryParameter(
              wireId: WireId('a0009'),
              name: 'minimumSize',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: StructuredShape(
                  propertyType: PropertyType.structured,
                  structuredRef: WireIdRef(
                      library: 'restage.material', wireId: WireId('s0025'))),
            ),
            FactoryParameter(
              wireId: WireId('a0010'),
              name: 'fixedSize',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: StructuredShape(
                  propertyType: PropertyType.structured,
                  structuredRef: WireIdRef(
                      library: 'restage.material', wireId: WireId('s0025'))),
            ),
            FactoryParameter(
              wireId: WireId('a0011'),
              name: 'side',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: StructuredShape(
                  propertyType: PropertyType.structured,
                  structuredRef: WireIdRef(
                      library: 'restage.material', wireId: WireId('s0003'))),
            ),
            FactoryParameter(
              wireId: WireId('a0005'),
              name: 'shape',
              kind: FactoryParameterKind.named,
              required: false,
              nullable: true,
              defaultPolicy: FactoryParameterDefaultPolicy.omitWhenNull,
              valueShape: UnionShape(
                  propertyType: PropertyType.shapeBorder,
                  unionRef: WireIdRef(
                      library: 'restage.material', wireId: WireId('u0005')),
                  wireCodec: CatalogWireCodec.rfwShapeBorder),
            ),
          ],
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0025'),
      name: 'Size',
      library: WidgetLibrary.material,
      description: 'Size value.',
      sourceType: 'dart:ui#Size',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0006'),
      name: 'BoxDecoration',
      library: WidgetLibrary.material,
      description: 'An immutable description of how to paint a box.',
      sourceType:
          'package:flutter/src/painting/box_decoration.dart#BoxDecoration',
      fields: [
        StructuredField(
          wireId: WireId('p0216'),
          name: 'color',
          type: PropertyType.color,
          description: 'The color to fill in the background of the box.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        StructuredField(
          wireId: WireId('p0217'),
          name: 'border',
          type: PropertyType.border,
          description:
              'A border to draw above the background [color], [gradient], or [image].',
          unionRef:
              WireIdRef(library: 'restage.material', wireId: WireId('u0004')),
          valueShape: UnionShape(
              propertyType: PropertyType.border,
              unionRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('u0004')),
              wireCodec: CatalogWireCodec.rfwBorder),
        ),
        StructuredField(
          wireId: WireId('p0218'),
          name: 'gradient',
          type: PropertyType.gradient,
          description: 'A gradient to use when filling the box.',
          unionRef:
              WireIdRef(library: 'restage.material', wireId: WireId('u0003')),
          valueShape: UnionShape(
              propertyType: PropertyType.gradient,
              unionRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('u0003')),
              wireCodec: CatalogWireCodec.rfwGradient),
        ),
        StructuredField(
          wireId: WireId('p0304'),
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
          wireId: WireId('p0305'),
          name: 'shape',
          type: PropertyType.enumValue,
          description:
              'The shape to fill the background [color], [gradient], and [image] into and to cast as the [boxShadow].',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/box_border.dart',
                  symbolName: 'BoxShape')),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0015'),
          argMappings: {
            'backgroundBlendMode': ArgMapping(targetFields: [WireId('p0304')]),
            'border': ArgMapping(targetFields: [WireId('p0217')]),
            'color': ArgMapping(targetFields: [WireId('p0216')]),
            'gradient': ArgMapping(targetFields: [WireId('p0218')]),
            'shape': ArgMapping(targetFields: [WireId('p0305')]),
          },
          description: 'Creates a box decoration.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0016'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two box decorations.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0007'),
      name: 'Radius',
      library: WidgetLibrary.material,
      description: 'A radius for either circular or elliptical shapes.',
      sourceType: 'dart:ui#Radius',
      fields: [
        StructuredField(
          wireId: WireId('p0221'),
          name: 'x',
          type: PropertyType.real,
          description: 'The radius value on the horizontal axis.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0222'),
          name: 'y',
          type: PropertyType.real,
          description: 'The radius value on the vertical axis.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0017'),
          namedConstructor: 'elliptical',
          argMappings: {
            'x': ArgMapping(targetFields: [WireId('p0221')]),
            'y': ArgMapping(targetFields: [WireId('p0222')]),
          },
          description: 'Constructs an elliptical radius with the given radii.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0018'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two radii.',
        ),
        ConstValueVariant(
          wireId: WireId('v0020'),
          staticAccessor: 'zero',
          description: 'A radius with [x] and [y] values set to zero.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0008'),
      name: 'Decoration',
      library: WidgetLibrary.material,
      description:
          'A description of a box decoration (a decoration applied to a [Rect]).',
      sourceType: 'package:flutter/src/painting/decoration.dart#Decoration',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0009'),
      name: 'ShapeDecoration',
      library: WidgetLibrary.material,
      description:
          'An immutable description of how to paint an arbitrary shape.',
      sourceType:
          'package:flutter/src/painting/shape_decoration.dart#ShapeDecoration',
      fields: [
        StructuredField(
          wireId: WireId('p0224'),
          name: 'color',
          type: PropertyType.color,
          description: 'The color to fill in the background of the shape.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        StructuredField(
          wireId: WireId('p0225'),
          name: 'gradient',
          type: PropertyType.gradient,
          description: 'A gradient to use when filling the shape.',
          unionRef:
              WireIdRef(library: 'restage.material', wireId: WireId('u0003')),
          valueShape: UnionShape(
              propertyType: PropertyType.gradient,
              unionRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('u0003')),
              wireCodec: CatalogWireCodec.rfwGradient),
        ),
        StructuredField(
          wireId: WireId('p0226'),
          name: 'shape',
          type: PropertyType.shapeBorder,
          description:
              'The shape to fill the [color], [gradient], and [image] into and to cast as the [shadows].',
          unionRef:
              WireIdRef(library: 'restage.material', wireId: WireId('u0002')),
          valueShape: UnionShape(
              propertyType: PropertyType.shapeBorder,
              unionRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('u0002')),
              wireCodec: CatalogWireCodec.rfwShapeBorder),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0021'),
          argMappings: {
            'color': ArgMapping(targetFields: [WireId('p0224')]),
            'gradient': ArgMapping(targetFields: [WireId('p0225')]),
            'shape': ArgMapping(targetFields: [WireId('p0226')]),
          },
          description: 'Creates a shape decoration.',
        ),
        ConstructorVariant(
          wireId: WireId('v0022'),
          namedConstructor: 'fromBoxDecoration',
          description:
              'Creates a shape decoration configured to match a [BoxDecoration].',
        ),
        StaticMethodVariant(
          wireId: WireId('v0023'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two shapes.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0010'),
      name: 'RoundedRectangleBorder',
      library: WidgetLibrary.material,
      description: 'A rectangular border with rounded corners.',
      sourceType:
          'package:flutter/src/painting/rounded_rectangle_border.dart#RoundedRectangleBorder',
      fields: [],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0024'),
          description: 'Creates a rounded rectangle border.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0021'),
      name: 'RoundedSuperellipseBorder',
      library: WidgetLibrary.material,
      description:
          'A rectangular border with rounded corners following the shape of an [RSuperellipse].',
      sourceType:
          'package:flutter/src/painting/rounded_rectangle_border.dart#RoundedSuperellipseBorder',
      fields: [],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0045'),
          description: 'Creates a rounded rectangle border.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0011'),
      name: 'CircleBorder',
      library: WidgetLibrary.material,
      description: 'A border that fits a circle within the available space.',
      sourceType:
          'package:flutter/src/painting/circle_border.dart#CircleBorder',
      fields: [
        StructuredField(
          wireId: WireId('p0231'),
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
          wireId: WireId('v0025'),
          argMappings: {
            'eccentricity': ArgMapping(targetFields: [WireId('p0231')]),
          },
          description: 'Create a circle border.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0012'),
      name: 'StadiumBorder',
      library: WidgetLibrary.material,
      description:
          'A border that fits a stadium-shaped border (a box with semicircles on the ends) within the rectangle of the widget it is applied to.',
      sourceType:
          'package:flutter/src/painting/stadium_border.dart#StadiumBorder',
      fields: [],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0026'),
          description: 'Create a stadium border.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0013'),
      name: 'ContinuousRectangleBorder',
      library: WidgetLibrary.material,
      description:
          'A rectangular border with smooth continuous transitions between the straight sides and the rounded corners.',
      sourceType:
          'package:flutter/src/painting/continuous_rectangle_border.dart#ContinuousRectangleBorder',
      fields: [],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0027'),
          description: 'Creates a [ContinuousRectangleBorder].',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0014'),
      name: 'BeveledRectangleBorder',
      library: WidgetLibrary.material,
      description: 'A rectangular border with flattened or "beveled" corners.',
      sourceType:
          'package:flutter/src/painting/beveled_rectangle_border.dart#BeveledRectangleBorder',
      fields: [],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0028'),
          description:
              'Creates a border like a [RoundedRectangleBorder] except that the corners are joined by straight lines instead of arcs.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0022'),
      name: 'LinearBorder',
      library: WidgetLibrary.material,
      description:
          'An [OutlinedBorder] like [BoxBorder] that allows one to define a rectangular (box) border in terms of zero to four [LinearBorderEdge]s, each of which is rendered as a single line.',
      sourceType:
          'package:flutter/src/painting/linear_border.dart#LinearBorder',
      fields: [
        StructuredField(
          wireId: WireId('p0281'),
          name: 'start',
          type: PropertyType.structured,
          description:
              'Defines the left edge for [TextDirection.ltr] or the right for [TextDirection.rtl].',
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0024')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0024'))),
        ),
        StructuredField(
          wireId: WireId('p0282'),
          name: 'end',
          type: PropertyType.structured,
          description:
              'Defines the right edge for [TextDirection.ltr] or the left for [TextDirection.rtl].',
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0024')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0024'))),
        ),
        StructuredField(
          wireId: WireId('p0283'),
          name: 'top',
          type: PropertyType.structured,
          description: 'Defines the top edge.',
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0024')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0024'))),
        ),
        StructuredField(
          wireId: WireId('p0284'),
          name: 'bottom',
          type: PropertyType.structured,
          description: 'Defines the bottom edge.',
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0024')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0024'))),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0046'),
          argMappings: {
            'bottom': ArgMapping(targetFields: [WireId('p0284')]),
            'end': ArgMapping(targetFields: [WireId('p0282')]),
            'start': ArgMapping(targetFields: [WireId('p0281')]),
            'top': ArgMapping(targetFields: [WireId('p0283')]),
          },
          description:
              'Creates a rectangular box border that\'s rendered as zero to four lines.',
        ),
        ConstructorVariant(
          wireId: WireId('v0047'),
          namedConstructor: 'bottom',
          description:
              'Creates a rectangular box border with an edge on the bottom.',
        ),
        ConstructorVariant(
          wireId: WireId('v0048'),
          namedConstructor: 'end',
          description:
              'Creates a rectangular box border with an edge on the right for [TextDirection.ltr] or on the left for [TextDirection.rtl].',
        ),
        ConstructorVariant(
          wireId: WireId('v0049'),
          namedConstructor: 'start',
          description:
              'Creates a rectangular box border with an edge on the left for [TextDirection.ltr] or on the right for [TextDirection.rtl].',
        ),
        ConstructorVariant(
          wireId: WireId('v0050'),
          namedConstructor: 'top',
          description:
              'Creates a rectangular box border with an edge on the top.',
        ),
        ConstValueVariant(
          wireId: WireId('v0052'),
          staticAccessor: 'none',
          description: 'No border.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0023'),
      name: 'StarBorder',
      library: WidgetLibrary.material,
      description:
          'A border that fits a star or polygon-shaped border within the rectangle of the widget it is applied to.',
      sourceType: 'package:flutter/src/painting/star_border.dart#StarBorder',
      fields: [
        StructuredField(
          wireId: WireId('p0285'),
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
          wireId: WireId('p0286'),
          name: 'innerRadiusRatio',
          type: PropertyType.real,
          description: '',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0287'),
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
          wireId: WireId('p0288'),
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
          wireId: WireId('p0289'),
          name: 'rotation',
          type: PropertyType.real,
          description: '',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0290'),
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
          wireId: WireId('v0053'),
          argMappings: {
            'innerRadiusRatio': ArgMapping(targetFields: [WireId('p0286')]),
            'pointRounding': ArgMapping(targetFields: [WireId('p0287')]),
            'points': ArgMapping(targetFields: [WireId('p0285')]),
            'rotation': ArgMapping(targetFields: [WireId('p0289')]),
            'squash': ArgMapping(targetFields: [WireId('p0290')]),
            'valleyRounding': ArgMapping(targetFields: [WireId('p0288')]),
          },
          description:
              'Create a const star-shaped border with the given number [points] on the star.',
        ),
        ConstructorVariant(
          wireId: WireId('v0054'),
          namedConstructor: 'polygon',
          argMappings: {
            'pointRounding': ArgMapping(targetFields: [WireId('p0287')]),
            'rotation': ArgMapping(targetFields: [WireId('p0289')]),
            'squash': ArgMapping(targetFields: [WireId('p0290')]),
          },
          description:
              'Create a const polygon border with the given number of [sides].',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0024'),
      name: 'LinearBorderEdge',
      library: WidgetLibrary.material,
      description:
          'Defines the relative size and alignment of one [LinearBorder] edge.',
      sourceType:
          'package:flutter/src/painting/linear_border.dart#LinearBorderEdge',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0015'),
      name: 'LinearGradient',
      library: WidgetLibrary.material,
      description: 'A 2D linear gradient.',
      sourceType: 'package:flutter/src/painting/gradient.dart#LinearGradient',
      fields: [
        StructuredField(
          wireId: WireId('p0306'),
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
          wireId: WireId('p0307'),
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
          wireId: WireId('p0308'),
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
          wireId: WireId('v0029'),
          argMappings: {
            'begin': ArgMapping(targetFields: [WireId('p0306')]),
            'end': ArgMapping(targetFields: [WireId('p0307')]),
            'tileMode': ArgMapping(targetFields: [WireId('p0308')]),
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
      wireId: WireId('s0016'),
      name: 'RadialGradient',
      library: WidgetLibrary.material,
      description: 'A 2D radial gradient.',
      sourceType: 'package:flutter/src/painting/gradient.dart#RadialGradient',
      fields: [
        StructuredField(
          wireId: WireId('p0309'),
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
          wireId: WireId('p0239'),
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
          wireId: WireId('p0310'),
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
          wireId: WireId('p0311'),
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
          wireId: WireId('p0240'),
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
            'center': ArgMapping(targetFields: [WireId('p0309')]),
            'focal': ArgMapping(targetFields: [WireId('p0311')]),
            'focalRadius': ArgMapping(targetFields: [WireId('p0240')]),
            'radius': ArgMapping(targetFields: [WireId('p0239')]),
            'tileMode': ArgMapping(targetFields: [WireId('p0310')]),
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
      wireId: WireId('s0017'),
      name: 'SweepGradient',
      library: WidgetLibrary.material,
      description: 'A 2D sweep gradient.',
      sourceType: 'package:flutter/src/painting/gradient.dart#SweepGradient',
      fields: [
        StructuredField(
          wireId: WireId('p0312'),
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
          wireId: WireId('p0242'),
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
          wireId: WireId('p0243'),
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
          wireId: WireId('p0313'),
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
            'center': ArgMapping(targetFields: [WireId('p0312')]),
            'endAngle': ArgMapping(targetFields: [WireId('p0243')]),
            'startAngle': ArgMapping(targetFields: [WireId('p0242')]),
            'tileMode': ArgMapping(targetFields: [WireId('p0313')]),
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
      wireId: WireId('s0018'),
      name: 'Border',
      library: WidgetLibrary.material,
      description:
          'A border of a box, comprised of four sides: top, right, bottom, left.',
      sourceType: 'package:flutter/src/painting/box_border.dart#Border',
      fields: [
        StructuredField(
          wireId: WireId('p0245'),
          name: 'top',
          type: PropertyType.structured,
          description: '',
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0003'))),
        ),
        StructuredField(
          wireId: WireId('p0246'),
          name: 'right',
          type: PropertyType.structured,
          description: 'The right side of this border.',
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0003'))),
        ),
        StructuredField(
          wireId: WireId('p0247'),
          name: 'bottom',
          type: PropertyType.structured,
          description: '',
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0003'))),
        ),
        StructuredField(
          wireId: WireId('p0248'),
          name: 'left',
          type: PropertyType.structured,
          description: 'The left side of this border.',
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0003'))),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0035'),
          argMappings: {
            'bottom': ArgMapping(targetFields: [WireId('p0247')]),
            'left': ArgMapping(targetFields: [WireId('p0248')]),
            'right': ArgMapping(targetFields: [WireId('p0246')]),
            'top': ArgMapping(targetFields: [WireId('p0245')]),
          },
          description: 'Creates a border.',
        ),
        ConstructorVariant(
          wireId: WireId('v0036'),
          namedConstructor: 'all',
          description:
              'A uniform border with all sides the same color and width.',
        ),
        ConstructorVariant(
          wireId: WireId('v0037'),
          namedConstructor: 'fromBorderSide',
          argMappings: {
            'side': ArgMapping(targetFields: [
              WireId('p0245'),
              WireId('p0246'),
              WireId('p0247'),
              WireId('p0248')
            ]),
          },
          description: 'Creates a border whose sides are all the same.',
        ),
        ConstructorVariant(
          wireId: WireId('v0038'),
          namedConstructor: 'symmetric',
          description:
              'Creates a border with symmetrical vertical and horizontal sides.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0039'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two borders.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0040'),
          staticAccessor: 'merge',
          description:
              'Creates a [Border] that represents the addition of the two given [Border]s.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0019'),
      name: 'BorderDirectional',
      library: WidgetLibrary.material,
      description:
          'A border of a box, comprised of four sides, the lateral sides of which flip over based on the reading direction.',
      sourceType:
          'package:flutter/src/painting/box_border.dart#BorderDirectional',
      fields: [
        StructuredField(
          wireId: WireId('p0251'),
          name: 'top',
          type: PropertyType.structured,
          description: '',
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0003'))),
        ),
        StructuredField(
          wireId: WireId('p0252'),
          name: 'start',
          type: PropertyType.structured,
          description: 'The start side of this border.',
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0003'))),
        ),
        StructuredField(
          wireId: WireId('p0253'),
          name: 'end',
          type: PropertyType.structured,
          description: 'The end side of this border.',
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0003'))),
        ),
        StructuredField(
          wireId: WireId('p0254'),
          name: 'bottom',
          type: PropertyType.structured,
          description: '',
          structuredRef:
              WireIdRef(library: 'restage.material', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.material', wireId: WireId('s0003'))),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0041'),
          argMappings: {
            'bottom': ArgMapping(targetFields: [WireId('p0254')]),
            'end': ArgMapping(targetFields: [WireId('p0253')]),
            'start': ArgMapping(targetFields: [WireId('p0252')]),
            'top': ArgMapping(targetFields: [WireId('p0251')]),
          },
          description: 'Creates a border.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0042'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two borders.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0043'),
          staticAccessor: 'merge',
          description:
              'Creates a [BorderDirectional] that represents the addition of the two given [BorderDirectional]s.',
        ),
      ],
    ),
  ],
  unions: [
    UnionEntry(
      wireId: WireId('u0001'),
      name: 'Decoration',
      library: WidgetLibrary.material,
      description: 'A box decoration: BoxDecoration or ShapeDecoration.',
      sourceType: 'package:flutter/src/painting/decoration.dart#Decoration',
      memberSourceTypes: [
        'package:flutter/src/painting/box_decoration.dart#BoxDecoration',
        'package:flutter/src/painting/shape_decoration.dart#ShapeDecoration'
      ],
      discriminator: DiscriminatorSpec(field: '_s', values: [
        WireIdRef(library: 'restage.material', wireId: WireId('s0006')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0009'))
      ]),
      members: [
        WireIdRef(library: 'restage.material', wireId: WireId('s0006')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0009'))
      ],
    ),
    UnionEntry(
      wireId: WireId('u0002'),
      name: 'ShapeBorder',
      library: WidgetLibrary.material,
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
        WireIdRef(library: 'restage.material', wireId: WireId('s0010')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0021')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0011')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0012')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0013')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0014')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0022')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0023'))
      ]),
      members: [
        WireIdRef(library: 'restage.material', wireId: WireId('s0010')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0021')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0011')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0012')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0013')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0014')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0022')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0023'))
      ],
    ),
    UnionEntry(
      wireId: WireId('u0003'),
      name: 'Gradient',
      library: WidgetLibrary.material,
      description: 'A color gradient: linear, radial, or sweep.',
      sourceType: 'package:flutter/src/painting/gradient.dart#Gradient',
      memberSourceTypes: [
        'package:flutter/src/painting/gradient.dart#LinearGradient',
        'package:flutter/src/painting/gradient.dart#RadialGradient',
        'package:flutter/src/painting/gradient.dart#SweepGradient'
      ],
      discriminator: DiscriminatorSpec(field: '_s', values: [
        WireIdRef(library: 'restage.material', wireId: WireId('s0015')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0016')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0017'))
      ]),
      members: [
        WireIdRef(library: 'restage.material', wireId: WireId('s0015')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0016')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0017'))
      ],
    ),
    UnionEntry(
      wireId: WireId('u0004'),
      name: 'BoxBorder',
      library: WidgetLibrary.material,
      description:
          'A box border: uniform or per-side Border, or text-direction-aware BorderDirectional.',
      sourceType: 'package:flutter/src/painting/box_border.dart#BoxBorder',
      memberSourceTypes: [
        'package:flutter/src/painting/box_border.dart#Border',
        'package:flutter/src/painting/box_border.dart#BorderDirectional'
      ],
      discriminator: DiscriminatorSpec(field: '_s', values: [
        WireIdRef(library: 'restage.material', wireId: WireId('s0018')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0019'))
      ]),
      members: [
        WireIdRef(library: 'restage.material', wireId: WireId('s0018')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0019'))
      ],
    ),
    UnionEntry(
      wireId: WireId('u0005'),
      name: 'OutlinedBorder',
      library: WidgetLibrary.material,
      description:
          'An outlined shape border: rounded, superellipse, circle, stadium, continuous, beveled, linear, or star.',
      sourceType: 'package:flutter/src/painting/borders.dart#OutlinedBorder',
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
        WireIdRef(library: 'restage.material', wireId: WireId('s0010')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0021')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0011')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0012')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0013')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0014')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0022')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0023'))
      ]),
      members: [
        WireIdRef(library: 'restage.material', wireId: WireId('s0010')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0021')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0011')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0012')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0013')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0014')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0022')),
        WireIdRef(library: 'restage.material', wireId: WireId('s0023'))
      ],
    ),
  ],
);

/// The content version of the `restage.material` catalog —
/// the maximum widget `sinceVersion` in this library. Read by
/// the SDK to derive the installed built-in catalog version.
const int kMaterialCatalogContentVersion = 4;
