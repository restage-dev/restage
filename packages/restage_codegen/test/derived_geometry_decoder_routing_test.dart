import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

void main() {
  group('derived geometry decoder routing', () {
    // These assertions cover which decoder the emitter selects. The decoders'
    // value repairs are tested separately at their runtime boundary.
    test('routes every constraint scalar slot', () {
      const slots = <(String, String, PropertyType)>[
        ('Container', 'width', PropertyType.length),
        ('Container', 'height', PropertyType.length),
        ('AnimatedContainer', 'width', PropertyType.length),
        ('AnimatedContainer', 'height', PropertyType.length),
        ('SizedBox', 'width', PropertyType.length),
        ('SizedBox', 'height', PropertyType.length),
        ('Icon', 'size', PropertyType.length),
        ('IconButton', 'iconSize', PropertyType.length),
        ('Positioned', 'left', PropertyType.length),
        ('Positioned', 'top', PropertyType.length),
        ('Positioned', 'right', PropertyType.length),
        ('Positioned', 'bottom', PropertyType.length),
        ('Positioned', 'width', PropertyType.length),
        ('Positioned', 'height', PropertyType.length),
        ('AnimatedPositioned', 'left', PropertyType.length),
        ('AnimatedPositioned', 'top', PropertyType.length),
        ('AnimatedPositioned', 'right', PropertyType.length),
        ('AnimatedPositioned', 'bottom', PropertyType.length),
        ('AnimatedPositioned', 'width', PropertyType.length),
        ('AnimatedPositioned', 'height', PropertyType.length),
        ('Image', 'width', PropertyType.length),
        ('Image', 'height', PropertyType.length),
        ('ImageAsset', 'width', PropertyType.length),
        ('ImageAsset', 'height', PropertyType.length),
        ('FadeInImageAssetNetwork', 'width', PropertyType.length),
        ('FadeInImageAssetNetwork', 'height', PropertyType.length),
      ];
      for (final (widgetName, propertyName, propertyType) in slots) {
        final source = _emissionFor(widgetName, propertyName, propertyType);
        expect(
          source,
          contains(
            'RestageDecoders.constraintScalar('
            "source, <Object>['$propertyName'])",
          ),
          reason: '$widgetName.$propertyName',
        );
      }
    });

    test('routes every layout factor slot', () {
      const slots = <(String, String, PropertyType)>[
        ('Align', 'widthFactor', PropertyType.real),
        ('Align', 'heightFactor', PropertyType.real),
        ('AnimatedAlign', 'widthFactor', PropertyType.real),
        ('AnimatedAlign', 'heightFactor', PropertyType.real),
        ('Center', 'widthFactor', PropertyType.real),
        ('Center', 'heightFactor', PropertyType.real),
        ('FractionallySizedBox', 'widthFactor', PropertyType.real),
        ('FractionallySizedBox', 'heightFactor', PropertyType.real),
        ('IntrinsicWidth', 'stepWidth', PropertyType.real),
        ('IntrinsicWidth', 'stepHeight', PropertyType.real),
        ('AppBar', 'toolbarHeight', PropertyType.length),
        ('AppBar', 'leadingWidth', PropertyType.length),
        ('Divider', 'height', PropertyType.length),
        ('Divider', 'thickness', PropertyType.length),
        ('Tab', 'height', PropertyType.length),
        ('CupertinoSearchTextField', 'itemSize', PropertyType.real),
      ];
      for (final (widgetName, propertyName, propertyType) in slots) {
        final source = _emissionFor(widgetName, propertyName, propertyType);
        expect(
          source,
          contains(
            'RestageDecoders.layoutFactor('
            "source, <Object>['$propertyName'])",
          ),
          reason: '$widgetName.$propertyName',
        );
      }
    });

    test('routes every optional positive layout scalar slot', () {
      const slots = <(String, String, PropertyType)>[
        ('CupertinoDatePicker', 'itemExtent', PropertyType.length),
        ('CupertinoTimerPicker', 'itemExtent', PropertyType.length),
        ('CupertinoPicker', 'squeeze', PropertyType.real),
        ('FadeInImageAssetNetwork', 'imageScale', PropertyType.real),
        ('LinearProgressIndicator', 'minHeight', PropertyType.length),
        ('CupertinoActivityIndicator', 'radius', PropertyType.length),
        ('CupertinoPicker', 'magnification', PropertyType.real),
      ];
      for (final (widgetName, propertyName, propertyType) in slots) {
        final source = _emissionFor(widgetName, propertyName, propertyType);
        expect(
          source,
          contains(
            'RestageDecoders.positiveLayoutScalar('
            "source, <Object>['$propertyName'])",
          ),
          reason: '$widgetName.$propertyName',
        );
      }
    });

    test('routes both bounded fractions through one decoder', () {
      const slots = <(String, String)>[
        ('RestageModalSheet', 'scrollControlDisabledMaxHeightRatio'),
        ('RestagePager', 'viewportFraction'),
      ];
      for (final (widgetName, propertyName) in slots) {
        final source = _emissionFor(
          widgetName,
          propertyName,
          PropertyType.real,
        );
        expect(
          source,
          contains(
            'RestageDecoders.unitIntervalFactor('
            "source, <Object>['$propertyName'])",
          ),
          reason: '$widgetName.$propertyName',
        );
      }
    });

    test('keeps Cupertino scalar repairs independent of derived products', () {
      const positiveDecoder = 'RestageDecoders.positiveLayoutScalar';
      const positiveRadius = "$positiveDecoder(source, <Object>['radius'])";
      final activity = emitFactoryFunction(_activityIndicatorEntry())!;
      expect(
        activity,
        contains(
          'radius: $positiveRadius ?? 10.0,',
        ),
      );
      expect(activity, isNot(contains('safeActivityIndicatorRadius')));

      const requiredDecoder = 'RestageDecoders.requiredLayoutScalar';
      const itemExtentPath = "<Object>['itemExtent']";
      const itemExtentSlot = "slot: 'CupertinoPicker.itemExtent'";
      const requiredItemExtent = '$requiredDecoder(source, $itemExtentPath, '
          '$itemExtentSlot, mustBePositive: true)';
      const magnificationPath = "<Object>['magnification']";
      const positiveMagnification =
          '$positiveDecoder(source, $magnificationPath)';
      final picker = emitFactoryFunction(_pickerEntry())!;
      expect(
        picker,
        contains('itemExtent: $requiredItemExtent,'),
      );
      expect(
        picker,
        contains(
          'magnification: $positiveMagnification ?? 1.0,',
        ),
      );
      expect(picker, isNot(contains('safePickerMagnification')));
      expect(picker, isNot(contains('final itemExtent =')));
      expect(
        _occurrences(picker, "source, <Object>['itemExtent']"),
        1,
      );
    });

    test('leaves colliding custom scalar slots unchanged', () {
      const customUri = 'package:acme/widgets.dart';
      final appBar = emitFactoryFunction(
        const WidgetEntry(
          wireId: WireId.unallocatedWidget,
          name: 'AppBar',
          library: WidgetLibrary.custom('acme.widgets'),
          category: WidgetCategory.decoration,
          description: 'Custom scalar collision fixture.',
          flutterType: '$customUri#AppBar',
          childrenSlot: ChildrenSlot.none,
          properties: [
            PropertyEntry(
              wireId: WireId.unallocatedProperty,
              name: 'toolbarHeight',
              type: PropertyType.length,
              description: 'Custom toolbar height.',
            ),
          ],
        ),
        aliases: const {customUri: 's0'},
      )!;
      expect(
        appBar,
        contains(
            "toolbarHeight: source.v<double>(const <Object>['toolbarHeight'])"),
      );
      expect(appBar, isNot(contains('RestageDecoders.layoutFactor')));

      final activity = emitFactoryFunction(
        _activityIndicatorEntry(
          library: const WidgetLibrary.custom('acme.widgets'),
          flutterType: '$customUri#CupertinoActivityIndicator',
        ),
        aliases: const {customUri: 's0'},
      )!;
      expect(
        activity,
        contains("radius: source.v<double>(const <Object>['radius']) ?? 10.0,"),
      );
      expect(activity, isNot(contains('safeActivityIndicatorRadius')));

      final picker = emitFactoryFunction(
        _pickerEntry(
          library: const WidgetLibrary.custom('acme.widgets'),
          flutterType: '$customUri#CupertinoPicker',
        ),
        aliases: const {customUri: 's0'},
      )!;
      expect(
        picker,
        contains(
          "itemExtent: source.v<double>(const <Object>['itemExtent']) ?? "
          "(throw ArgumentError('CupertinoPicker.itemExtent is required.'))",
        ),
      );
      expect(picker, isNot(contains('safePickerMagnification')));
    });

    test('classifies the seven layout exemptions with bounded reasons', () {
      const slots = <(String, String)>[
        ('BackdropFilter', 'blurSigmaX'),
        ('BackdropFilter', 'blurSigmaY'),
        ('RestageFormattedNumber', 'value'),
        ('RestagePrice', 'value'),
        ('Scrollbar', 'thickness'),
        ('CupertinoPicker', 'diameterRatio'),
        ('CupertinoPicker', 'offAxisFraction'),
      ];

      for (final slot in slots) {
        final reason = scalarDecoderExemptionsForTesting[slot];
        expect(reason, isNotNull, reason: '${slot.$1}.${slot.$2}');
        expect(reason, isNotEmpty, reason: '${slot.$1}.${slot.$2}');
        expect(
          scalarDecoderDeferredForTesting,
          isNot(contains(slot)),
          reason: '${slot.$1}.${slot.$2}',
        );
      }
    });

    test('routes every decomposed text metric slot', () {
      for (final widgetName in [
        'Text',
        'TextRich',
        'DefaultTextStyle',
        'AnimatedDefaultTextStyle',
        'RestagePrice',
        'RestageFormattedNumber',
      ]) {
        for (final propertyName in [
          'fontSize',
          'letterSpacing',
          'wordSpacing',
          'height',
          'decorationThickness',
        ]) {
          final source = _emissionFor(
            widgetName,
            propertyName,
            PropertyType.real,
          );
          expect(
            source,
            contains(
              'RestageDecoders.textMetric('
              "source, <Object>['$propertyName'])",
            ),
            reason: '$widgetName.$propertyName',
          );
        }
      }
    });

    test('routes required layout scalars through the throwing decoder', () {
      const slots = [
        (
          widget: 'AspectRatio',
          property: 'aspectRatio',
          type: PropertyType.real,
          positive: true,
        ),
        (
          widget: 'LimitedBox',
          property: 'maxWidth',
          type: PropertyType.length,
          positive: false,
        ),
        (
          widget: 'LimitedBox',
          property: 'maxHeight',
          type: PropertyType.length,
          positive: false,
        ),
        (
          widget: 'CupertinoPicker',
          property: 'itemExtent',
          type: PropertyType.length,
          positive: true,
        ),
      ];

      for (final slot in slots) {
        final source = _emissionFor(
          slot.widget,
          slot.property,
          slot.type,
          required: true,
        );
        final call = 'RestageDecoders.requiredLayoutScalar('
            "source, <Object>['${slot.property}'], "
            "slot: '${slot.widget}.${slot.property}', "
            'mustBePositive: ${slot.positive})';
        expect(
          source,
          contains(call),
          reason: '${slot.widget}.${slot.property}',
        );
        expect(
          source,
          isNot(contains('$call ??')),
          reason: '${slot.widget}.${slot.property}',
        );
      }
    });

    test('leaves a same-named application AspectRatio on the plain decoder',
        () {
      const applicationUri = 'package:acme/widgets.dart';
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'AspectRatio',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.layout,
        description: 'Application scalar routing fixture.',
        flutterType: '$applicationUri#AspectRatio',
        childrenSlot: ChildrenSlot.none,
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'aspectRatio',
            type: PropertyType.real,
            description: 'Optional application-defined aspect ratio.',
          ),
        ],
      );
      final source = emitFactoryFunction(
        entry,
        aliases: const {applicationUri: 's0'},
      )!;

      expect(source, contains('return s0.AspectRatio('));
      expect(
        source,
        contains(
          "aspectRatio: source.v<double>(const <Object>['aspectRatio']),",
        ),
      );
      expect(
        source,
        isNot(contains('RestageDecoders.requiredLayoutScalar')),
      );
    });

    test('keeps the built-in AspectRatio on the required scalar decoder', () {
      final source = _emissionFor(
        'AspectRatio',
        'aspectRatio',
        PropertyType.real,
        required: true,
      );

      expect(
        source,
        contains(
          'aspectRatio: ${_requiredAspectRatioCall()},',
        ),
      );
    });

    test('routes border and alignment slots', () {
      expect(
        _emissionFor('DecoratedBox', 'border', PropertyType.border),
        contains("RestageDecoders.border(source, <Object>['border'])"),
      );
      expect(
        _emissionFor('Align', 'alignment', PropertyType.alignment),
        contains(
          "RestageDecoders.alignment(source, <Object>['alignment'])",
        ),
      );
    });

    test('hoists and reuses the child list for flex spacing', () {
      for (final widgetName in ['Row', 'Column']) {
        final source = _spacingEmissionFor(widgetName);

        expect(
          source,
          contains(
            "final children = source.childList(<Object>['children']);",
          ),
          reason: widgetName,
        );
        expect(
          source,
          contains(
            'spacing: ${_derivedSpacingCall('spacing')},',
          ),
          reason: widgetName,
        );
        expect(
          source,
          contains('children: children,'),
          reason: widgetName,
        );
        expect(
          _occurrences(
            source,
            "source.childList(<Object>['children'])",
          ),
          1,
          reason: widgetName,
        );
      }
    });

    for (final widgetName in ['Row', 'Column']) {
      test('keeps exact framework $widgetName in a custom namespace', () {
        const frameworkUri = 'package:flutter/src/widgets/basic.dart';
        final source = _spacingEmissionFor(
          widgetName,
          library: const WidgetLibrary.custom('acme.widgets'),
          flutterType: '$frameworkUri#$widgetName',
          aliases: const {frameworkUri: 's0'},
          spacingDefault: 12,
        );

        expect(source, contains('return s0.$widgetName('));
        expect(
          source,
          contains(
            "spacing: source.v<double>(const <Object>['spacing']) ?? 12.0,",
          ),
        );
        expect(
          source,
          contains("children: source.childList(const <Object>['children']),"),
        );
        expect(source, isNot(contains('final children =')));
        expect(source, isNot(contains('RestageDecoders.derivedSpacing')));
      });
    }

    test('routes wrap spacings independently without a count preflight', () {
      final source = _spacingEmissionFor('Wrap');

      expect(
        source,
        contains(
          'spacing: ${_layoutFactorCall('spacing')} ?? 0.0,',
        ),
      );
      expect(
        source,
        contains(
          'runSpacing: ${_layoutFactorCall('runSpacing')} ?? 0.0,',
        ),
      );
      expect(source, isNot(contains('RestageDecoders.derivedSpacing')));
      expect(source, isNot(contains('final children =')));
      expect(
        _occurrences(
          source,
          "source.childList(const <Object>['children'])",
        ),
        1,
      );
    });

    test('keeps wrap scalar repair exact to the core framework source', () {
      final exact = _spacingEmissionFor('Wrap');
      expect(exact, contains('return RestageWrap('));
      expect(exact, contains(_layoutFactorCall('spacing')));
      expect(exact, contains(_layoutFactorCall('runSpacing')));

      const otherUri = 'package:acme/widgets.dart';
      for (final library in [
        WidgetLibrary.core,
        WidgetLibrary.material,
      ]) {
        final source = _spacingEmissionFor(
          'Wrap',
          library: library,
          flutterType: '$otherUri#Wrap',
          aliases: const {otherUri: 's0'},
        );
        expect(source, contains('return s0.Wrap('), reason: library.namespace);
        expect(
          source,
          contains(
              "spacing: source.v<double>(const <Object>['spacing']) ?? 0.0,"),
          reason: library.namespace,
        );
        expect(
          source,
          contains(
            "runSpacing: source.v<double>(const <Object>['runSpacing']) ?? 0.0,",
          ),
          reason: library.namespace,
        );
        expect(
          source,
          isNot(contains('RestageDecoders.layoutFactor')),
          reason: library.namespace,
        );
      }

      const frameworkUri = 'package:flutter/src/widgets/basic.dart';
      final custom = _spacingEmissionFor(
        'Wrap',
        library: const WidgetLibrary.custom('acme.widgets'),
        flutterType: '$frameworkUri#Wrap',
        aliases: const {frameworkUri: 's0'},
      );
      expect(custom, contains('return s0.Wrap('));
      expect(custom, isNot(contains('RestageDecoders.layoutFactor')));
      expect(
        _occurrences(custom, 'source.v<double>'),
        2,
      );
    });

    test('leaves a same-named custom Row outside built-in preflight', () {
      const customUri = 'package:acme/widgets.dart';
      const entry = WidgetEntry(
        wireId: WireId.unallocatedWidget,
        name: 'Row',
        library: WidgetLibrary.custom('acme.widgets'),
        category: WidgetCategory.layout,
        description: 'Custom spacing routing fixture.',
        flutterType: '$customUri#Row',
        childrenSlot: ChildrenSlot.list,
        properties: [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'spacing',
            type: PropertyType.real,
            description: 'Space between children.',
            defaultSource: LiteralDefault(0.0),
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'children',
            type: PropertyType.widgetList,
            description: 'Children to lay out.',
          ),
        ],
      );
      final source = emitFactoryFunction(
        entry,
        aliases: const {customUri: 's0'},
      )!;

      expect(source, contains('return s0.Row('));
      expect(
        source,
        contains(
          "spacing: source.v<double>(const <Object>['spacing']) ?? 0.0,",
        ),
      );
      expect(
        source,
        contains("children: source.childList(const <Object>['children']),"),
      );
      expect(source, isNot(contains('final children =')));
      expect(source, isNot(contains('RestageDecoders.derivedSpacing')));
    });

    test('leaves an unrelated widget-list factory unchanged', () {
      final source = _childListEmissionFor('Stack');

      expect(
        source,
        contains("children: source.childList(const <Object>['children'])"),
      );
      expect(source, isNot(contains('final children =')));
      expect(source, isNot(contains('RestageDecoders.derivedSpacing')));
    });

    test('leaves unrelated reals and constraint components unchanged', () {
      final elevation = _emissionFor('AppBar', 'elevation', PropertyType.real);
      expect(
        elevation,
        contains("source.v<double>(const <Object>['elevation'])"),
      );
      expect(elevation, isNot(contains('RestageDecoders.constraintScalar')));
      expect(elevation, isNot(contains('RestageDecoders.layoutFactor')));

      for (final widgetName in [
        'Container',
        'AnimatedContainer',
        'ConstrainedBox',
      ]) {
        for (final propertyName in [
          'minWidth',
          'maxWidth',
          'minHeight',
          'maxHeight',
        ]) {
          final source = _emissionFor(
            widgetName,
            propertyName,
            PropertyType.length,
          );
          expect(
            source,
            contains("source.v<double>(const <Object>['$propertyName'])"),
            reason: '$widgetName.$propertyName',
          );
          expect(
            source,
            isNot(contains('RestageDecoders.constraintScalar')),
            reason: '$widgetName.$propertyName',
          );
          expect(
            source,
            isNot(contains('RestageDecoders.layoutFactor')),
            reason: '$widgetName.$propertyName',
          );
        }
      }
    });
  });
}

String _derivedSpacingCall(String slot) {
  const fn = 'RestageDecoders.derivedSpacing';
  return "$fn(source, <Object>['$slot'], children.length)";
}

String _layoutFactorCall(String slot) {
  const fn = 'RestageDecoders.layoutFactor';
  return "$fn(source, <Object>['$slot'])";
}

String _requiredAspectRatioCall() {
  const fn = 'RestageDecoders.requiredLayoutScalar';
  const slot = "slot: 'AspectRatio.aspectRatio'";
  return "$fn(source, <Object>['aspectRatio'], $slot, mustBePositive: true)";
}

String _emissionFor(
  String widgetName,
  String propertyName,
  PropertyType propertyType, {
  bool required = false,
}) {
  final entry = WidgetEntry(
    wireId: WireId.unallocatedWidget,
    name: widgetName,
    library: WidgetLibrary.core,
    category: WidgetCategory.decoration,
    description: 'Decoder routing fixture.',
    flutterType: 'package:flutter/widgets.dart#$widgetName',
    childrenSlot: ChildrenSlot.none,
    properties: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: propertyName,
        type: propertyType,
        description: 'Decoder routing property.',
        required: required,
      ),
    ],
  );
  return emitFactoryFunction(entry)!;
}

String _spacingEmissionFor(
  String widgetName, {
  WidgetLibrary library = WidgetLibrary.core,
  String? flutterType,
  Map<String, String> aliases = const {},
  double spacingDefault = 0.0,
}) {
  final spacingType =
      widgetName == 'Wrap' ? PropertyType.length : PropertyType.real;
  final entry = WidgetEntry(
    wireId: WireId.unallocatedWidget,
    name: widgetName,
    library: library,
    category: WidgetCategory.layout,
    description: 'Derived spacing routing fixture.',
    flutterType:
        flutterType ?? 'package:flutter/src/widgets/basic.dart#$widgetName',
    childrenSlot: ChildrenSlot.list,
    properties: [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'spacing',
        type: spacingType,
        description: 'Space between children.',
        defaultSource: LiteralDefault(spacingDefault),
      ),
      if (widgetName == 'Wrap')
        const PropertyEntry(
          wireId: WireId.unallocatedProperty,
          name: 'runSpacing',
          type: PropertyType.length,
          description: 'Space between runs.',
          defaultSource: LiteralDefault(0.0),
        ),
      const PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'children',
        type: PropertyType.widgetList,
        description: 'Children to lay out.',
      ),
    ],
  );
  return emitFactoryFunction(entry, aliases: aliases)!;
}

String _childListEmissionFor(String widgetName) {
  final entry = WidgetEntry(
    wireId: WireId.unallocatedWidget,
    name: widgetName,
    library: WidgetLibrary.core,
    category: WidgetCategory.layout,
    description: 'Widget-list routing fixture.',
    flutterType: 'package:flutter/widgets.dart#$widgetName',
    childrenSlot: ChildrenSlot.list,
    properties: const [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'children',
        type: PropertyType.widgetList,
        description: 'Children to lay out.',
      ),
    ],
  );
  return emitFactoryFunction(entry)!;
}

WidgetEntry _activityIndicatorEntry({
  WidgetLibrary library = WidgetLibrary.cupertino,
  String flutterType =
      'package:flutter/src/cupertino/activity_indicator.dart#CupertinoActivityIndicator',
}) =>
    WidgetEntry(
      wireId: WireId.unallocatedWidget,
      name: 'CupertinoActivityIndicator',
      library: library,
      category: WidgetCategory.decoration,
      description: 'Activity indicator product fixture.',
      flutterType: flutterType,
      childrenSlot: ChildrenSlot.none,
      properties: const [
        PropertyEntry(
          wireId: WireId.unallocatedProperty,
          name: 'radius',
          type: PropertyType.length,
          description: 'Indicator radius.',
          defaultSource: LiteralDefault(10.0),
        ),
      ],
    );

WidgetEntry _pickerEntry({
  WidgetLibrary library = WidgetLibrary.cupertino,
  String flutterType =
      'package:flutter/src/cupertino/picker.dart#CupertinoPicker',
}) =>
    WidgetEntry(
      wireId: WireId.unallocatedWidget,
      name: 'CupertinoPicker',
      library: library,
      category: WidgetCategory.input,
      description: 'Picker product fixture.',
      flutterType: flutterType,
      childrenSlot: ChildrenSlot.none,
      properties: const [
        PropertyEntry(
          wireId: WireId.unallocatedProperty,
          name: 'magnification',
          type: PropertyType.real,
          description: 'Picker magnification.',
          defaultSource: LiteralDefault(1.0),
        ),
        PropertyEntry(
          wireId: WireId.unallocatedProperty,
          name: 'itemExtent',
          type: PropertyType.real,
          description: 'Picker item extent.',
          required: true,
        ),
      ],
    );

int _occurrences(String source, String pattern) =>
    RegExp(RegExp.escape(pattern)).allMatches(source).length;
