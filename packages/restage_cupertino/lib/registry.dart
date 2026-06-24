// GENERATED CODE - DO NOT MODIFY BY HAND
// Generated from lib/registry_curation.dart by restage_catalog_gen.
//
// Edit the curation file and re-run build_runner; do not
// edit this file directly. The runtime, codegen, and editor
// all consume `kRegistry` from here.

library;

import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Registry for the `restage.cupertino` library.
/// Read by codegen, the editor, and the runtime SDK.
final Catalog kRegistry = Catalog(
  schemaVersion: 4,
  generatedAt: '1970-01-01T00:00:00Z',
  libraries: {
    WidgetLibrary.cupertino: const LibraryInfo(version: '0.1.0'),
  },
  widgets: [
    WidgetEntry(
      wireId: WireId('w0001'),
      name: 'CupertinoActivityIndicator',
      library: WidgetLibrary.cupertino,
      category: WidgetCategory.decoration,
      description: 'An iOS-style activity indicator that spins clockwise.',
      flutterType:
          'package:flutter/src/cupertino/activity_indicator.dart#CupertinoActivityIndicator',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0001'),
          name: 'color',
          type: PropertyType.color,
          description: 'Color of the activity indicator.',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0002'),
          name: 'animating',
          type: PropertyType.boolean,
          description:
              'Whether the activity indicator is running its animation.',
          defaultSource: LiteralDefault(true),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0003'),
          name: 'radius',
          type: PropertyType.length,
          description: 'Radius of the spinner widget.',
          defaultSource: LiteralDefault(10.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0002'),
      name: 'CupertinoButton',
      library: WidgetLibrary.cupertino,
      category: WidgetCategory.action,
      description: 'An iOS-style button.',
      flutterType: 'package:flutter/src/cupertino/button.dart#CupertinoButton',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onPressed],
      properties: [
        PropertyEntry(
          wireId: WireId('p0004'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0005'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description:
              'The amount of space to surround the child inside the bounds of the button.',
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0006'),
          name: 'color',
          type: PropertyType.color,
          description: 'The color of the button\'s background.',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0007'),
          name: 'onPressed',
          type: PropertyType.event,
          description:
              'The callback that is called when the button is tapped or otherwise activated.',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0008'),
          name: 'disabled',
          type: PropertyType.boolean,
          description: 'Whether the button is disabled.',
          synthetic: 'gateOnPressed',
          defaultSource: LiteralDefault(false),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0003'),
      name: 'CupertinoButtonFilled',
      library: WidgetLibrary.cupertino,
      category: WidgetCategory.action,
      description: 'A filled Cupertino call-to-action button.',
      flutterType:
          'package:flutter/src/cupertino/button.dart#CupertinoButton.filled',
      childrenSlot: ChildrenSlot.single,
      fires: [WidgetEventName.onPressed],
      properties: [
        PropertyEntry(
          wireId: WireId('p0009'),
          name: 'child',
          type: PropertyType.widget,
          description: 'The widget below this widget in the tree.',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0010'),
          name: 'padding',
          type: PropertyType.edgeInsets,
          description:
              'The amount of space to surround the child inside the bounds of the button.',
          valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                  symbolName: 'EdgeInsetsGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0011'),
          name: 'color',
          type: PropertyType.color,
          description: 'The color of the button\'s background.',
          defaultBrandToken: 'primary',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0012'),
          name: 'onPressed',
          type: PropertyType.event,
          description:
              'The callback that is called when the button is tapped or otherwise activated.',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0013'),
          name: 'disabled',
          type: PropertyType.boolean,
          description: 'Whether the button is disabled.',
          synthetic: 'gateOnPressed',
          defaultSource: LiteralDefault(false),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0004'),
      name: 'CupertinoListSection',
      library: WidgetLibrary.cupertino,
      category: WidgetCategory.layout,
      description: 'An iOS-style list section.',
      flutterType:
          'package:flutter/src/cupertino/list_section.dart#CupertinoListSection',
      childrenSlot: ChildrenSlot.list,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0014'),
          name: 'children',
          type: PropertyType.widgetList,
          description:
              'The list of rows in the section. Usually a list of [CupertinoListTile]s.',
        ),
        PropertyEntry(
          wireId: WireId('p0015'),
          name: 'header',
          type: PropertyType.widget,
          description:
              'Sets the form section header. The section header lies above the [children] rows. Usually a [Text] widget.',
        ),
        PropertyEntry(
          wireId: WireId('p0016'),
          name: 'footer',
          type: PropertyType.widget,
          description:
              'Sets the form section footer. The section footer lies below the [children] rows. Usually a [Text] widget.',
        ),
        PropertyEntry(
          wireId: WireId('p0154'),
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
      wireId: WireId('w0005'),
      name: 'CupertinoListSectionInsetGrouped',
      library: WidgetLibrary.cupertino,
      category: WidgetCategory.layout,
      description: 'Inset-rounded variant of CupertinoListSection.',
      flutterType:
          'package:flutter/src/cupertino/list_section.dart#CupertinoListSection.insetGrouped',
      childrenSlot: ChildrenSlot.list,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0017'),
          name: 'children',
          type: PropertyType.widgetList,
          description:
              'The list of rows in the section. Usually a list of [CupertinoListTile]s.',
        ),
        PropertyEntry(
          wireId: WireId('p0018'),
          name: 'header',
          type: PropertyType.widget,
          description:
              'Sets the form section header. The section header lies above the [children] rows. Usually a [Text] widget.',
        ),
        PropertyEntry(
          wireId: WireId('p0019'),
          name: 'footer',
          type: PropertyType.widget,
          description:
              'Sets the form section footer. The section footer lies below the [children] rows. Usually a [Text] widget.',
        ),
        PropertyEntry(
          wireId: WireId('p0155'),
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
      wireId: WireId('w0006'),
      name: 'CupertinoListTile',
      library: WidgetLibrary.cupertino,
      category: WidgetCategory.layout,
      description: 'An iOS-style list tile.',
      flutterType:
          'package:flutter/src/cupertino/list_tile.dart#CupertinoListTile',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onTap],
      properties: [
        PropertyEntry(
          wireId: WireId('p0020'),
          name: 'title',
          type: PropertyType.widget,
          description:
              'A [title] is used to convey the central information. Usually a [Text].',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0021'),
          name: 'subtitle',
          type: PropertyType.widget,
          description:
              'A [subtitle] is used to display additional information. It is located below [title]. Usually a [Text] widget.',
        ),
        PropertyEntry(
          wireId: WireId('p0022'),
          name: 'leading',
          type: PropertyType.widget,
          description:
              'A widget displayed at the start of the [CupertinoListTile]. This is typically an `Icon` or an `Image`.',
        ),
        PropertyEntry(
          wireId: WireId('p0023'),
          name: 'trailing',
          type: PropertyType.widget,
          description:
              'A widget displayed at the end of the [CupertinoListTile]. This is usually a right chevron icon (e.g. `CupertinoListTileChevron`), or an `Icon`.',
        ),
        PropertyEntry(
          wireId: WireId('p0024'),
          name: 'onTap',
          type: PropertyType.event,
          description:
              'The [onTap] function is called when a user taps on [CupertinoListTile]. If left `null`, the [CupertinoListTile] will not react on taps. If this is a `Future<void> Function()`, then the [CupertinoListTile] remains activated until the returned future is awaited. This is according to iOS behavior. However, if this function is a `void Function()`, then the tile is active only for the duration of invocation.',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0025'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description:
              'The [backgroundColor] of the tile in normal state. Once the tile is tapped, the background color switches to [backgroundColorActivated]. It is set to match the iOS look by default.',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0007'),
      name: 'CupertinoNavigationBar',
      library: WidgetLibrary.cupertino,
      category: WidgetCategory.layout,
      description: 'An iOS-styled navigation bar.',
      flutterType:
          'package:flutter/src/cupertino/nav_bar.dart#CupertinoNavigationBar',
      childrenSlot: ChildrenSlot.none,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0026'),
          name: 'leading',
          type: PropertyType.widget,
          description:
              '{@template flutter.cupertino.CupertinoNavigationBar.leading} Widget to place at the start of the navigation bar. Normally a back button for a normal page or a cancel button for full page dialogs.',
        ),
        PropertyEntry(
          wireId: WireId('p0027'),
          name: 'middle',
          type: PropertyType.widget,
          description: 'The navigation bar\'s default title.',
        ),
        PropertyEntry(
          wireId: WireId('p0028'),
          name: 'trailing',
          type: PropertyType.widget,
          description:
              '{@template flutter.cupertino.CupertinoNavigationBar.trailing} Widget to place at the end of the navigation bar. Normally additional actions taken on the page such as a search or edit function. {@endtemplate}',
        ),
        PropertyEntry(
          wireId: WireId('p0029'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description:
              '{@template flutter.cupertino.CupertinoNavigationBar.backgroundColor} The background color of the navigation bar. If it contains transparency, the tab bar will automatically produce a blurring effect to the content behind it. This behavior can be disabled by setting [enableBackgroundFilterBlur] to false.',
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
      wireId: WireId('w0008'),
      name: 'CupertinoPageScaffold',
      library: WidgetLibrary.cupertino,
      category: WidgetCategory.layout,
      description: 'Implements a single iOS application page\'s layout.',
      flutterType:
          'package:flutter/src/cupertino/page_scaffold.dart#CupertinoPageScaffold',
      childrenSlot: ChildrenSlot.single,
      fires: [],
      properties: [
        PropertyEntry(
          wireId: WireId('p0030'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description:
              'The color of the widget that underlies the entire scaffold.',
          defaultBrandToken: 'background',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0031'),
          name: 'child',
          type: PropertyType.widget,
          description: 'Widget to show in the main content area.',
          required: true,
          priority: PropertyPriority.primary,
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0009'),
      name: 'CupertinoSwitch',
      library: WidgetLibrary.cupertino,
      category: WidgetCategory.input,
      description: 'An iOS-style switch.',
      flutterType: 'package:flutter/src/cupertino/switch.dart#CupertinoSwitch',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onChanged],
      properties: [
        PropertyEntry(
          wireId: WireId('p0032'),
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
          wireId: WireId('p0033'),
          name: 'onChanged',
          type: PropertyType.event,
          description: 'Called when the user toggles the switch on or off.',
          callbackSignature: 'ValueChanged<bool>',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0034'),
          name: 'activeTrackColor',
          type: PropertyType.color,
          description: '',
          defaultBrandToken: 'primary',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0010'),
      name: 'CupertinoTextField',
      library: WidgetLibrary.cupertino,
      category: WidgetCategory.input,
      description: 'An iOS-style text field.',
      flutterType:
          'package:flutter/src/cupertino/text_field.dart#CupertinoTextField',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onChanged, WidgetEventName.onSubmitted],
      properties: [
        PropertyEntry(
          wireId: WireId('p0035'),
          name: 'placeholder',
          type: PropertyType.string,
          description:
              'A lighter colored placeholder hint that appears on the first line of the text field when the text entry is empty.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0036'),
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
          wireId: WireId('p0037'),
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
          wireId: WireId('p0038'),
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
          wireId: WireId('p0039'),
          name: 'onChanged',
          type: PropertyType.event,
          description: '{@macro flutter.widgets.editableText.onChanged}',
          callbackSignature: 'ValueChanged<String>',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0040'),
          name: 'onSubmitted',
          type: PropertyType.event,
          description: '{@macro flutter.widgets.editableText.onSubmitted}',
          callbackSignature: 'ValueChanged<String>',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0156'),
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
      wireId: WireId('w0011'),
      name: 'CupertinoSlider',
      library: WidgetLibrary.cupertino,
      category: WidgetCategory.input,
      description: 'An iOS-style slider.',
      flutterType: 'package:flutter/src/cupertino/slider.dart#CupertinoSlider',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onChanged],
      properties: [
        PropertyEntry(
          wireId: WireId('p0041'),
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
          wireId: WireId('p0042'),
          name: 'onChanged',
          type: PropertyType.event,
          description:
              'Called when the user selects a new value for the slider.',
          callbackSignature: 'ValueChanged<double>',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0043'),
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
          wireId: WireId('p0044'),
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
          wireId: WireId('p0045'),
          name: 'divisions',
          type: PropertyType.integer,
          description: 'The number of discrete divisions.',
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0046'),
          name: 'activeColor',
          type: PropertyType.color,
          description:
              'The color to use for the portion of the slider that has been selected.',
          defaultBrandToken: 'primary',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0012'),
      name: 'CupertinoDatePicker',
      library: WidgetLibrary.cupertino,
      category: WidgetCategory.input,
      description: 'A date picker widget in iOS style.',
      flutterType:
          'package:flutter/src/cupertino/date_picker.dart#CupertinoDatePicker',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onChanged],
      properties: [
        PropertyEntry(
          wireId: WireId('p0047'),
          name: 'mode',
          type: PropertyType.enumValue,
          description:
              'The mode of the date picker as one of [CupertinoDatePickerMode]. Defaults to [CupertinoDatePickerMode.dateAndTime]. Value cannot change after initial build.',
          enumType: 'CupertinoDatePickerMode',
          defaultSource: LiteralDefault('dateAndTime'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/cupertino/date_picker.dart',
                  symbolName: 'CupertinoDatePickerMode')),
        ),
        PropertyEntry(
          wireId: WireId('p0048'),
          name: 'onDateTimeChanged',
          type: PropertyType.event,
          description:
              'Callback called when the selected date and/or time changes. If the new selected [DateTime] is not valid, or is not in the [minimumDate] through [maximumDate] range, this callback will not be called.',
          required: true,
          callbackSignature: 'ValueChanged<DateTime>',
          firesAs: 'onChanged',
          category: PropertyCategory.behavior,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0049'),
          name: 'minimumYear',
          type: PropertyType.integer,
          description:
              'Minimum year that the picker can be scrolled to in [CupertinoDatePickerMode.date] mode. Defaults to 1.',
          defaultSource: LiteralDefault(1),
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0050'),
          name: 'maximumYear',
          type: PropertyType.integer,
          description:
              'Maximum year that the picker can be scrolled to in [CupertinoDatePickerMode.date] mode. Null if there\'s no limit.',
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0051'),
          name: 'minuteInterval',
          type: PropertyType.integer,
          description:
              'The granularity of the minutes spinner, if it is shown in the current mode. Must be an integer factor of 60.',
          defaultSource: LiteralDefault(1),
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0052'),
          name: 'use24hFormat',
          type: PropertyType.boolean,
          description: 'Whether to use 24 hour format. Defaults to false.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0053'),
          name: 'dateOrder',
          type: PropertyType.enumValue,
          description:
              'Determines the order of the columns inside [CupertinoDatePicker] in [CupertinoDatePickerMode.date] and [CupertinoDatePickerMode.monthYear] mode. When using monthYear mode, both [DatePickerDateOrder.dmy] and [DatePickerDateOrder.mdy] will result in the month|year order. Defaults to the locale\'s default date format/order.',
          enumType: 'DatePickerDateOrder',
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri:
                      'package:flutter/src/cupertino/localizations.dart',
                  symbolName: 'DatePickerDateOrder')),
        ),
        PropertyEntry(
          wireId: WireId('p0054'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'Background color of date picker.',
          defaultBrandToken: 'background',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0055'),
          name: 'showDayOfWeek',
          type: PropertyType.boolean,
          description:
              'Whether to show the day of week alongside the day in [CupertinoDatePickerMode.date] mode.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0056'),
          name: 'showTimeSeparator',
          type: PropertyType.boolean,
          description:
              'Whether to show the time separator between hour and minute in the time [CupertinoDatePickerMode.time] and datetime [CupertinoDatePickerMode.dateAndTime] picker modes.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0057'),
          name: 'itemExtent',
          type: PropertyType.real,
          description: '{@macro flutter.cupertino.picker.itemExtent}',
          defaultSource: LiteralDefault(32.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0058'),
          name: 'changeReportingBehavior',
          type: PropertyType.enumValue,
          description: 'The behavior of reporting the selected date.',
          enumType: 'ChangeReportingBehavior',
          defaultSource: LiteralDefault('onScrollUpdate'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri:
                      'package:flutter/src/widgets/list_wheel_scroll_view.dart',
                  symbolName: 'ChangeReportingBehavior')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0013'),
      name: 'CupertinoTimerPicker',
      library: WidgetLibrary.cupertino,
      category: WidgetCategory.input,
      description: 'A countdown timer picker in iOS style.',
      flutterType:
          'package:flutter/src/cupertino/date_picker.dart#CupertinoTimerPicker',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onChanged],
      properties: [
        PropertyEntry(
          wireId: WireId('p0059'),
          name: 'mode',
          type: PropertyType.enumValue,
          description: 'The mode of the timer picker.',
          enumType: 'CupertinoTimerPickerMode',
          defaultSource: LiteralDefault('hms'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/cupertino/date_picker.dart',
                  symbolName: 'CupertinoTimerPickerMode')),
        ),
        PropertyEntry(
          wireId: WireId('p0060'),
          name: 'minuteInterval',
          type: PropertyType.integer,
          description:
              'The granularity of the minute spinner. Must be a positive integer factor of 60.',
          defaultSource: LiteralDefault(1),
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0061'),
          name: 'secondInterval',
          type: PropertyType.integer,
          description:
              'The granularity of the second spinner. Must be a positive integer factor of 60.',
          defaultSource: LiteralDefault(1),
          valueShape: ScalarShape(
              propertyType: PropertyType.integer,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'int')),
        ),
        PropertyEntry(
          wireId: WireId('p0062'),
          name: 'alignment',
          type: PropertyType.alignment,
          description:
              'Defines how the timer picker should be positioned within its parent.',
          defaultSource: LiteralDefault('center'),
          category: PropertyCategory.layout,
          valueShape: ScalarShape(
              propertyType: PropertyType.alignment,
              dartTypeRef: DartTypeRef(
                  libraryUri: 'package:flutter/src/painting/alignment.dart',
                  symbolName: 'AlignmentGeometry')),
        ),
        PropertyEntry(
          wireId: WireId('p0063'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'Background color of timer picker.',
          defaultBrandToken: 'background',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0064'),
          name: 'itemExtent',
          type: PropertyType.real,
          description: '{@macro flutter.cupertino.picker.itemExtent}',
          defaultSource: LiteralDefault(32.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0065'),
          name: 'onTimerDurationChanged',
          type: PropertyType.event,
          description: 'Callback called when the timer duration changes.',
          required: true,
          callbackSignature: 'ValueChanged<Duration>',
          firesAs: 'onChanged',
          category: PropertyCategory.behavior,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0066'),
          name: 'changeReportingBehavior',
          type: PropertyType.enumValue,
          description: 'The behavior of reporting the selected duration.',
          enumType: 'ChangeReportingBehavior',
          defaultSource: LiteralDefault('onScrollUpdate'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri:
                      'package:flutter/src/widgets/list_wheel_scroll_view.dart',
                  symbolName: 'ChangeReportingBehavior')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0014'),
      name: 'CupertinoPicker',
      library: WidgetLibrary.cupertino,
      category: WidgetCategory.input,
      description: 'An iOS-styled picker.',
      flutterType: 'package:flutter/src/cupertino/picker.dart#CupertinoPicker',
      childrenSlot: ChildrenSlot.list,
      fires: [WidgetEventName.onChanged],
      properties: [
        PropertyEntry(
          wireId: WireId('p0067'),
          name: 'diameterRatio',
          type: PropertyType.real,
          description:
              'Relative ratio between this picker\'s height and the simulated cylinder\'s diameter.',
          defaultSource: LiteralDefault(1.07),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0068'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'Background color behind the children.',
          defaultBrandToken: 'background',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0069'),
          name: 'offAxisFraction',
          type: PropertyType.real,
          description:
              '{@macro flutter.rendering.RenderListWheelViewport.offAxisFraction}',
          defaultSource: LiteralDefault(0.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0070'),
          name: 'useMagnifier',
          type: PropertyType.boolean,
          description:
              '{@macro flutter.rendering.RenderListWheelViewport.useMagnifier}',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0071'),
          name: 'magnification',
          type: PropertyType.real,
          description:
              '{@macro flutter.rendering.RenderListWheelViewport.magnification}',
          defaultSource: LiteralDefault(1.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0072'),
          name: 'squeeze',
          type: PropertyType.real,
          description:
              '{@macro flutter.rendering.RenderListWheelViewport.squeeze}',
          defaultSource: LiteralDefault(1.45),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0073'),
          name: 'changeReportingBehavior',
          type: PropertyType.enumValue,
          description: 'The behavior of reporting the selected item index.',
          enumType: 'ChangeReportingBehavior',
          defaultSource: LiteralDefault('onScrollUpdate'),
          valueShape: EnumShape(
              propertyType: PropertyType.enumValue,
              enumRef: DartTypeRef(
                  libraryUri:
                      'package:flutter/src/widgets/list_wheel_scroll_view.dart',
                  symbolName: 'ChangeReportingBehavior')),
        ),
        PropertyEntry(
          wireId: WireId('p0074'),
          name: 'itemExtent',
          type: PropertyType.real,
          description:
              '{@template flutter.cupertino.picker.itemExtent} The uniform height of all children.',
          required: true,
          priority: PropertyPriority.primary,
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        PropertyEntry(
          wireId: WireId('p0075'),
          name: 'onSelectedItemChanged',
          type: PropertyType.event,
          description: 'Called when the selected item changes.',
          required: true,
          callbackSignature: 'ValueChanged<int>',
          firesAs: 'onChanged',
          category: PropertyCategory.behavior,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0076'),
          name: 'children',
          type: PropertyType.widgetList,
          description: '',
          required: true,
          priority: PropertyPriority.primary,
        ),
        PropertyEntry(
          wireId: WireId('p0077'),
          name: 'looping',
          type: PropertyType.boolean,
          description: '',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0015'),
      name: 'CupertinoSearchTextField',
      library: WidgetLibrary.cupertino,
      category: WidgetCategory.input,
      description:
          'A [CupertinoTextField] that mimics the look and behavior of UIKit\'s `UISearchTextField`.',
      flutterType:
          'package:flutter/src/cupertino/search_field.dart#CupertinoSearchTextField',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onChanged, WidgetEventName.onSubmitted],
      properties: [
        PropertyEntry(
          wireId: WireId('p0078'),
          name: 'onChanged',
          type: PropertyType.event,
          description: 'Invoked upon user input.',
          callbackSignature: 'ValueChanged<String>',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0079'),
          name: 'onSubmitted',
          type: PropertyType.event,
          description: 'Invoked upon keyboard submission.',
          callbackSignature: 'ValueChanged<String>',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0080'),
          name: 'placeholder',
          type: PropertyType.string,
          description:
              'A hint placeholder text that appears when the text entry is empty.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        PropertyEntry(
          wireId: WireId('p0081'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'Set the [decoration] property\'s background color.',
          defaultBrandToken: 'background',
          category: PropertyCategory.style,
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0082'),
          name: 'itemSize',
          type: PropertyType.real,
          description:
              'Sets the base icon size for the suffix and prefix icons.',
          defaultSource: LiteralDefault(20.0),
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
      ],
    ),
    WidgetEntry(
      wireId: WireId('w0016'),
      name: 'CupertinoCheckbox',
      library: WidgetLibrary.cupertino,
      category: WidgetCategory.input,
      description: 'A macOS style checkbox.',
      flutterType:
          'package:flutter/src/cupertino/checkbox.dart#CupertinoCheckbox',
      childrenSlot: ChildrenSlot.none,
      fires: [WidgetEventName.onChanged],
      properties: [
        PropertyEntry(
          wireId: WireId('p0083'),
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
          wireId: WireId('p0084'),
          name: 'tristate',
          type: PropertyType.boolean,
          description:
              'If true, the checkbox\'s [value] can be true, false, or null.',
          defaultSource: LiteralDefault(false),
          valueShape: ScalarShape(
              propertyType: PropertyType.boolean,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'bool')),
        ),
        PropertyEntry(
          wireId: WireId('p0085'),
          name: 'onChanged',
          type: PropertyType.event,
          description: 'Called when the value of the checkbox should change.',
          callbackSignature: 'ValueChanged<bool?>',
          category: PropertyCategory.behavior,
        ),
        PropertyEntry(
          wireId: WireId('p0086'),
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
          wireId: WireId('p0087'),
          name: 'checkColor',
          type: PropertyType.color,
          description:
              'The color to use for the check icon when this checkbox is checked.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        PropertyEntry(
          wireId: WireId('p0088'),
          name: 'semanticLabel',
          type: PropertyType.string,
          description:
              'The semantic label for the checkbox that will be announced by screen readers.',
          category: PropertyCategory.accessibility,
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
      ],
    ),
  ],
  structuredTypes: [
    StructuredEntry(
      wireId: WireId('s0001'),
      name: 'BoxDecoration',
      library: WidgetLibrary.cupertino,
      description: 'An immutable description of how to paint a box.',
      sourceType:
          'package:flutter/src/painting/box_decoration.dart#BoxDecoration',
      fields: [
        StructuredField(
          wireId: WireId('p0089'),
          name: 'color',
          type: PropertyType.color,
          description: 'The color to fill in the background of the box.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        StructuredField(
          wireId: WireId('p0090'),
          name: 'border',
          type: PropertyType.border,
          description:
              'A border to draw above the background [color], [gradient], or [image].',
          unionRef:
              WireIdRef(library: 'restage.cupertino', wireId: WireId('u0002')),
          valueShape: UnionShape(
              propertyType: PropertyType.border,
              unionRef: WireIdRef(
                  library: 'restage.cupertino', wireId: WireId('u0002')),
              wireCodec: CatalogWireCodec.rfwBorder),
        ),
        StructuredField(
          wireId: WireId('p0091'),
          name: 'gradient',
          type: PropertyType.gradient,
          description: 'A gradient to use when filling the box.',
          unionRef:
              WireIdRef(library: 'restage.cupertino', wireId: WireId('u0001')),
          valueShape: UnionShape(
              propertyType: PropertyType.gradient,
              unionRef: WireIdRef(
                  library: 'restage.cupertino', wireId: WireId('u0001')),
              wireCodec: CatalogWireCodec.rfwGradient),
        ),
        StructuredField(
          wireId: WireId('p0132'),
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
          wireId: WireId('p0133'),
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
          wireId: WireId('v0001'),
          argMappings: {
            'backgroundBlendMode': ArgMapping(targetFields: [WireId('p0132')]),
            'border': ArgMapping(targetFields: [WireId('p0090')]),
            'color': ArgMapping(targetFields: [WireId('p0089')]),
            'gradient': ArgMapping(targetFields: [WireId('p0091')]),
            'shape': ArgMapping(targetFields: [WireId('p0133')]),
          },
          description: 'Creates a box decoration.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0002'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two box decorations.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0002'),
      name: 'Border',
      library: WidgetLibrary.cupertino,
      description:
          'A border of a box, comprised of four sides: top, right, bottom, left.',
      sourceType: 'package:flutter/src/painting/box_border.dart#Border',
      fields: [
        StructuredField(
          wireId: WireId('p0094'),
          name: 'top',
          type: PropertyType.structured,
          description: '',
          structuredRef:
              WireIdRef(library: 'restage.cupertino', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.cupertino', wireId: WireId('s0003'))),
        ),
        StructuredField(
          wireId: WireId('p0095'),
          name: 'right',
          type: PropertyType.structured,
          description: 'The right side of this border.',
          structuredRef:
              WireIdRef(library: 'restage.cupertino', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.cupertino', wireId: WireId('s0003'))),
        ),
        StructuredField(
          wireId: WireId('p0096'),
          name: 'bottom',
          type: PropertyType.structured,
          description: '',
          structuredRef:
              WireIdRef(library: 'restage.cupertino', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.cupertino', wireId: WireId('s0003'))),
        ),
        StructuredField(
          wireId: WireId('p0097'),
          name: 'left',
          type: PropertyType.structured,
          description: 'The left side of this border.',
          structuredRef:
              WireIdRef(library: 'restage.cupertino', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.cupertino', wireId: WireId('s0003'))),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0003'),
          argMappings: {
            'bottom': ArgMapping(targetFields: [WireId('p0096')]),
            'left': ArgMapping(targetFields: [WireId('p0097')]),
            'right': ArgMapping(targetFields: [WireId('p0095')]),
            'top': ArgMapping(targetFields: [WireId('p0094')]),
          },
          description: 'Creates a border.',
        ),
        ConstructorVariant(
          wireId: WireId('v0004'),
          namedConstructor: 'all',
          description:
              'A uniform border with all sides the same color and width.',
        ),
        ConstructorVariant(
          wireId: WireId('v0005'),
          namedConstructor: 'fromBorderSide',
          argMappings: {
            'side': ArgMapping(targetFields: [
              WireId('p0094'),
              WireId('p0095'),
              WireId('p0096'),
              WireId('p0097')
            ]),
          },
          description: 'Creates a border whose sides are all the same.',
        ),
        ConstructorVariant(
          wireId: WireId('v0006'),
          namedConstructor: 'symmetric',
          description:
              'Creates a border with symmetrical vertical and horizontal sides.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0007'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two borders.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0008'),
          staticAccessor: 'merge',
          description:
              'Creates a [Border] that represents the addition of the two given [Border]s.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0003'),
      name: 'BorderSide',
      library: WidgetLibrary.cupertino,
      description: 'A side of a border of a box.',
      sourceType: 'package:flutter/src/painting/borders.dart#BorderSide',
      fields: [],
      variants: [],
    ),
    StructuredEntry(
      wireId: WireId('s0004'),
      name: 'TextStyle',
      library: WidgetLibrary.cupertino,
      description:
          'An immutable style describing how to format and paint text.',
      sourceType: 'package:flutter/src/painting/text_style.dart#TextStyle',
      fields: [
        StructuredField(
          wireId: WireId('p0100'),
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
          wireId: WireId('p0101'),
          name: 'color',
          type: PropertyType.color,
          description: 'The color to use when painting the text.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        StructuredField(
          wireId: WireId('p0102'),
          name: 'backgroundColor',
          type: PropertyType.color,
          description: 'The color to use as the background for the text.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        StructuredField(
          wireId: WireId('p0103'),
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
          wireId: WireId('p0134'),
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
          wireId: WireId('p0104'),
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
          wireId: WireId('p0135'),
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
          wireId: WireId('p0136'),
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
          wireId: WireId('p0105'),
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
          wireId: WireId('p0106'),
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
          wireId: WireId('p0107'),
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
          wireId: WireId('p0137'),
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
          wireId: WireId('p0138'),
          name: 'foreground',
          type: PropertyType.paint,
          description: 'The paint drawn as a foreground for the text.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        StructuredField(
          wireId: WireId('p0139'),
          name: 'background',
          type: PropertyType.paint,
          description: 'The paint drawn as a background for the text.',
          valueShape: ScalarShape(
              propertyType: PropertyType.paint,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Paint')),
        ),
        StructuredField(
          wireId: WireId('p0140'),
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
          wireId: WireId('p0108'),
          name: 'decorationColor',
          type: PropertyType.color,
          description: 'The color in which to paint the text decorations.',
          valueShape: ScalarShape(
              propertyType: PropertyType.color,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:ui', symbolName: 'Color')),
        ),
        StructuredField(
          wireId: WireId('p0141'),
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
          wireId: WireId('p0109'),
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
          wireId: WireId('p0110'),
          name: 'debugLabel',
          type: PropertyType.string,
          description: 'A human-readable description of this text style.',
          valueShape: ScalarShape(
              propertyType: PropertyType.string,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'String')),
        ),
        StructuredField(
          wireId: WireId('p0142'),
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
          wireId: WireId('p0143'),
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
          wireId: WireId('p0144'),
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
          wireId: WireId('p0145'),
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
          wireId: WireId('v0009'),
          staticAccessor: 'lerp',
          description:
              'Interpolate between two text styles for animated transitions.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0005'),
      name: 'Radius',
      library: WidgetLibrary.cupertino,
      description: 'A radius for either circular or elliptical shapes.',
      sourceType: 'dart:ui#Radius',
      fields: [
        StructuredField(
          wireId: WireId('p0112'),
          name: 'x',
          type: PropertyType.real,
          description: 'The radius value on the horizontal axis.',
          valueShape: ScalarShape(
              propertyType: PropertyType.real,
              dartTypeRef:
                  DartTypeRef(libraryUri: 'dart:core', symbolName: 'double')),
        ),
        StructuredField(
          wireId: WireId('p0113'),
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
          wireId: WireId('v0010'),
          namedConstructor: 'elliptical',
          argMappings: {
            'x': ArgMapping(targetFields: [WireId('p0112')]),
            'y': ArgMapping(targetFields: [WireId('p0113')]),
          },
          description: 'Constructs an elliptical radius with the given radii.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0011'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two radii.',
        ),
        ConstValueVariant(
          wireId: WireId('v0013'),
          staticAccessor: 'zero',
          description: 'A radius with [x] and [y] values set to zero.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0006'),
      name: 'BorderRadius',
      library: WidgetLibrary.cupertino,
      description: 'An immutable set of radii for each corner of a rectangle.',
      sourceType:
          'package:flutter/src/painting/border_radius.dart#BorderRadius',
      fields: [
        StructuredField(
          wireId: WireId('p0115'),
          name: 'topLeft',
          type: PropertyType.structured,
          description: 'The top-left [Radius].',
          structuredRef:
              WireIdRef(library: 'restage.cupertino', wireId: WireId('s0005')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.cupertino', wireId: WireId('s0005'))),
        ),
        StructuredField(
          wireId: WireId('p0116'),
          name: 'topRight',
          type: PropertyType.structured,
          description: 'The top-right [Radius].',
          structuredRef:
              WireIdRef(library: 'restage.cupertino', wireId: WireId('s0005')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.cupertino', wireId: WireId('s0005'))),
        ),
        StructuredField(
          wireId: WireId('p0117'),
          name: 'bottomLeft',
          type: PropertyType.structured,
          description: 'The bottom-left [Radius].',
          structuredRef:
              WireIdRef(library: 'restage.cupertino', wireId: WireId('s0005')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.cupertino', wireId: WireId('s0005'))),
        ),
        StructuredField(
          wireId: WireId('p0118'),
          name: 'bottomRight',
          type: PropertyType.structured,
          description: 'The bottom-right [Radius].',
          structuredRef:
              WireIdRef(library: 'restage.cupertino', wireId: WireId('s0005')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.cupertino', wireId: WireId('s0005'))),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0014'),
          namedConstructor: 'only',
          argMappings: {
            'bottomLeft': ArgMapping(targetFields: [WireId('p0117')]),
            'bottomRight': ArgMapping(targetFields: [WireId('p0118')]),
            'topLeft': ArgMapping(targetFields: [WireId('p0115')]),
            'topRight': ArgMapping(targetFields: [WireId('p0116')]),
          },
          description:
              'Creates a border radius with only the given non-zero values. The other corners will be right angles.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0015'),
          staticAccessor: 'lerp',
          description:
              'Linearly interpolate between two [BorderRadius] objects.',
        ),
        ConstValueVariant(
          wireId: WireId('v0017'),
          staticAccessor: 'zero',
          description: 'A border radius with all zero radii.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0007'),
      name: 'LinearGradient',
      library: WidgetLibrary.cupertino,
      description: 'A 2D linear gradient.',
      sourceType: 'package:flutter/src/painting/gradient.dart#LinearGradient',
      fields: [
        StructuredField(
          wireId: WireId('p0146'),
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
          wireId: WireId('p0147'),
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
          wireId: WireId('p0148'),
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
          wireId: WireId('v0018'),
          argMappings: {
            'begin': ArgMapping(targetFields: [WireId('p0146')]),
            'end': ArgMapping(targetFields: [WireId('p0147')]),
            'tileMode': ArgMapping(targetFields: [WireId('p0148')]),
          },
          description: 'Creates a linear gradient.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0019'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two [LinearGradient]s.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0008'),
      name: 'RadialGradient',
      library: WidgetLibrary.cupertino,
      description: 'A 2D radial gradient.',
      sourceType: 'package:flutter/src/painting/gradient.dart#RadialGradient',
      fields: [
        StructuredField(
          wireId: WireId('p0149'),
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
          wireId: WireId('p0120'),
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
          wireId: WireId('p0150'),
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
          wireId: WireId('p0151'),
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
          wireId: WireId('p0121'),
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
          wireId: WireId('v0020'),
          argMappings: {
            'center': ArgMapping(targetFields: [WireId('p0149')]),
            'focal': ArgMapping(targetFields: [WireId('p0151')]),
            'focalRadius': ArgMapping(targetFields: [WireId('p0121')]),
            'radius': ArgMapping(targetFields: [WireId('p0120')]),
            'tileMode': ArgMapping(targetFields: [WireId('p0150')]),
          },
          description: 'Creates a radial gradient.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0021'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two [RadialGradient]s.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0009'),
      name: 'SweepGradient',
      library: WidgetLibrary.cupertino,
      description: 'A 2D sweep gradient.',
      sourceType: 'package:flutter/src/painting/gradient.dart#SweepGradient',
      fields: [
        StructuredField(
          wireId: WireId('p0152'),
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
          wireId: WireId('p0123'),
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
          wireId: WireId('p0124'),
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
          wireId: WireId('p0153'),
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
          wireId: WireId('v0022'),
          argMappings: {
            'center': ArgMapping(targetFields: [WireId('p0152')]),
            'endAngle': ArgMapping(targetFields: [WireId('p0124')]),
            'startAngle': ArgMapping(targetFields: [WireId('p0123')]),
            'tileMode': ArgMapping(targetFields: [WireId('p0153')]),
          },
          description: 'Creates a sweep gradient.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0023'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two [SweepGradient]s.',
        ),
      ],
    ),
    StructuredEntry(
      wireId: WireId('s0010'),
      name: 'BorderDirectional',
      library: WidgetLibrary.cupertino,
      description:
          'A border of a box, comprised of four sides, the lateral sides of which flip over based on the reading direction.',
      sourceType:
          'package:flutter/src/painting/box_border.dart#BorderDirectional',
      fields: [
        StructuredField(
          wireId: WireId('p0126'),
          name: 'top',
          type: PropertyType.structured,
          description: '',
          structuredRef:
              WireIdRef(library: 'restage.cupertino', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.cupertino', wireId: WireId('s0003'))),
        ),
        StructuredField(
          wireId: WireId('p0127'),
          name: 'start',
          type: PropertyType.structured,
          description: 'The start side of this border.',
          structuredRef:
              WireIdRef(library: 'restage.cupertino', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.cupertino', wireId: WireId('s0003'))),
        ),
        StructuredField(
          wireId: WireId('p0128'),
          name: 'end',
          type: PropertyType.structured,
          description: 'The end side of this border.',
          structuredRef:
              WireIdRef(library: 'restage.cupertino', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.cupertino', wireId: WireId('s0003'))),
        ),
        StructuredField(
          wireId: WireId('p0129'),
          name: 'bottom',
          type: PropertyType.structured,
          description: '',
          structuredRef:
              WireIdRef(library: 'restage.cupertino', wireId: WireId('s0003')),
          valueShape: StructuredShape(
              propertyType: PropertyType.structured,
              structuredRef: WireIdRef(
                  library: 'restage.cupertino', wireId: WireId('s0003'))),
        ),
      ],
      variants: [
        ConstructorVariant(
          wireId: WireId('v0024'),
          argMappings: {
            'bottom': ArgMapping(targetFields: [WireId('p0129')]),
            'end': ArgMapping(targetFields: [WireId('p0128')]),
            'start': ArgMapping(targetFields: [WireId('p0127')]),
            'top': ArgMapping(targetFields: [WireId('p0126')]),
          },
          description: 'Creates a border.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0025'),
          staticAccessor: 'lerp',
          description: 'Linearly interpolate between two borders.',
        ),
        StaticMethodVariant(
          wireId: WireId('v0026'),
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
      name: 'Gradient',
      library: WidgetLibrary.cupertino,
      description: 'A color gradient: linear, radial, or sweep.',
      sourceType: 'package:flutter/src/painting/gradient.dart#Gradient',
      memberSourceTypes: [
        'package:flutter/src/painting/gradient.dart#LinearGradient',
        'package:flutter/src/painting/gradient.dart#RadialGradient',
        'package:flutter/src/painting/gradient.dart#SweepGradient'
      ],
      discriminator: DiscriminatorSpec(field: '_s', values: [
        WireIdRef(library: 'restage.cupertino', wireId: WireId('s0007')),
        WireIdRef(library: 'restage.cupertino', wireId: WireId('s0008')),
        WireIdRef(library: 'restage.cupertino', wireId: WireId('s0009'))
      ]),
      members: [
        WireIdRef(library: 'restage.cupertino', wireId: WireId('s0007')),
        WireIdRef(library: 'restage.cupertino', wireId: WireId('s0008')),
        WireIdRef(library: 'restage.cupertino', wireId: WireId('s0009'))
      ],
    ),
    UnionEntry(
      wireId: WireId('u0002'),
      name: 'BoxBorder',
      library: WidgetLibrary.cupertino,
      description:
          'A box border: uniform or per-side Border, or text-direction-aware BorderDirectional.',
      sourceType: 'package:flutter/src/painting/box_border.dart#BoxBorder',
      memberSourceTypes: [
        'package:flutter/src/painting/box_border.dart#Border',
        'package:flutter/src/painting/box_border.dart#BorderDirectional'
      ],
      discriminator: DiscriminatorSpec(field: '_s', values: [
        WireIdRef(library: 'restage.cupertino', wireId: WireId('s0002')),
        WireIdRef(library: 'restage.cupertino', wireId: WireId('s0010'))
      ]),
      members: [
        WireIdRef(library: 'restage.cupertino', wireId: WireId('s0002')),
        WireIdRef(library: 'restage.cupertino', wireId: WireId('s0010'))
      ],
    ),
  ],
);

/// The content version of the `restage.cupertino` catalog —
/// the maximum widget `sinceVersion` in this library. Read by
/// the SDK to derive the installed built-in catalog version.
const int kCupertinoCatalogContentVersion = 1;
