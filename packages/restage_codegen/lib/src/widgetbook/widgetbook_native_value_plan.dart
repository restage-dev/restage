import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:restage_codegen/src/dart_import_planner.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_catalog_source_index.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_property_capability.dart';
import 'package:restage_shared/restage_shared.dart' show kSupportedCurveNames;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Source-qualified Dart type retained by the native Widgetbook backend.
final class WidgetbookDartTypePlan {
  /// Creates a type plan.
  const WidgetbookDartTypePlan({
    required this.libraryUri,
    required this.symbol,
    this.typeArguments = const [],
    this.nullable = false,
  });

  /// Builds the supported interface-type subset from analyzer facts.
  factory WidgetbookDartTypePlan.fromAnalyzer(
    DartType type, {
    required String path,
  }) {
    if (type is! InterfaceType) {
      throw StateError(
        'Widgetbook native value at $path has unsupported Dart type '
        '`${type.getDisplayString()}`.',
      );
    }
    final symbol = type.element.name;
    if (symbol == null || symbol.isEmpty) {
      throw StateError('Widgetbook native value at $path has an unnamed type.');
    }
    return WidgetbookDartTypePlan(
      libraryUri: type.element.library.identifier,
      symbol: symbol,
      typeArguments: [
        for (final argument in type.typeArguments)
          WidgetbookDartTypePlan.fromAnalyzer(argument, path: path),
      ],
      nullable: type.nullabilitySuffix == NullabilitySuffix.question,
    );
  }

  /// Defining library URI.
  final String libraryUri;

  /// Declared type symbol.
  final String symbol;

  /// Generic arguments retained structurally.
  final List<WidgetbookDartTypePlan> typeArguments;

  /// Whether the outer type accepts null.
  final bool nullable;

  /// Returns this type without outer nullability.
  WidgetbookDartTypePlan get nonNullable => nullable
      ? WidgetbookDartTypePlan(
          libraryUri: libraryUri,
          symbol: symbol,
          typeArguments: typeArguments,
        )
      : this;
}

/// One story property type and the customer source path that requires
/// Widgetbook's generated part to reproduce it bare.
typedef WidgetbookDartTypeUse = ({
  WidgetbookDartTypePlan type,
  String sourcePath,
});

/// One constructor argument in a native expression plan.
final class WidgetbookNativeArgumentPlan {
  /// Creates a constructor argument.
  const WidgetbookNativeArgumentPlan({
    required this.value,
    this.name,
  });

  /// Named label, or `null` for a positional argument.
  final String? name;

  /// Lowered argument value.
  final WidgetbookNativeValuePlan value;
}

/// Native Dart expression IR used by the Widgetbook backend.
sealed class WidgetbookDartValuePlan {
  const WidgetbookDartValuePlan();
}

/// Native value with a representable named Dart type.
sealed class WidgetbookNativeValuePlan extends WidgetbookDartValuePlan {
  const WidgetbookNativeValuePlan({required this.type});

  /// Static Dart type of this expression.
  final WidgetbookDartTypePlan type;
}

/// Public importable top-level or static function tear-off.
final class WidgetbookFunctionReferenceValuePlan
    extends WidgetbookDartValuePlan {
  /// Creates an importable function-reference plan.
  const WidgetbookFunctionReferenceValuePlan({
    required this.libraryUri,
    required this.member,
    this.owner,
  });

  /// Defining library URI used for deterministic import aliasing.
  final String libraryUri;

  /// Enclosing type for a static method, or `null` for a top-level function.
  final String? owner;

  /// Public function or static method name.
  final String member;
}

/// Null literal.
final class WidgetbookNullValuePlan extends WidgetbookNativeValuePlan {
  /// Creates a null plan.
  const WidgetbookNullValuePlan({required super.type});
}

/// Primitive scalar or scalar-list leaf.
final class WidgetbookScalarValuePlan extends WidgetbookNativeValuePlan {
  /// Creates a scalar plan.
  const WidgetbookScalarValuePlan({required super.type, required this.value});

  /// JSON-compatible scalar value.
  final Object value;
}

/// Source-qualified enum member.
final class WidgetbookEnumValuePlan extends WidgetbookNativeValuePlan {
  /// Creates an enum-member plan.
  const WidgetbookEnumValuePlan({
    required super.type,
    required this.member,
  });

  /// Enum constant name.
  final String member;
}

/// Source-qualified top-level or static const member.
final class WidgetbookStaticMemberValuePlan extends WidgetbookNativeValuePlan {
  /// Creates a static member plan.
  const WidgetbookStaticMemberValuePlan({
    required super.type,
    required this.libraryUri,
    required this.member,
    this.owner,
  });

  /// Defining library URI used for deterministic import aliasing.
  final String libraryUri;

  /// Enclosing type for a static field, or `null` for a top-level constant.
  final String? owner;

  /// Static/top-level member name.
  final String member;
}

/// Lossless reconstructed constructor default rendered through the shared
/// Dart-const import and source planner.
final class WidgetbookDartConstValuePlan extends WidgetbookNativeValuePlan {
  /// Creates a reconstructed const plan.
  const WidgetbookDartConstValuePlan({
    required super.type,
    required this.value,
  });

  /// Target-independent reconstructed constant identity.
  final DartConstValue value;
}

/// Closed set of framework literal renderers admitted by Widgetbook.
enum WidgetbookFrameworkLiteralKind {
  /// ARGB color literal.
  color,

  /// Four-sided edge-insets literal.
  edgeInsets,

  /// Concrete or directional alignment literal.
  alignment,

  /// Two-dimensional offset literal.
  offset,

  /// Named Flutter font-weight literal.
  fontWeight,

  /// Millisecond duration literal.
  duration,

  /// Named Flutter curve literal.
  curve,
}

/// One supported Flutter/Dart framework literal.
final class WidgetbookFrameworkValuePlan extends WidgetbookNativeValuePlan {
  /// Creates a framework literal plan.
  const WidgetbookFrameworkValuePlan({
    required super.type,
    required this.kind,
    required this.value,
  });

  /// Closed renderer family selected during lowering.
  final WidgetbookFrameworkLiteralKind kind;

  /// Validated canonical transport value.
  final Object value;
}

/// Typed Dart list expression.
final class WidgetbookListValuePlan extends WidgetbookNativeValuePlan {
  /// Creates a list plan.
  const WidgetbookListValuePlan({
    required super.type,
    required this.values,
  });

  /// Lowered list items.
  final List<WidgetbookNativeValuePlan> values;
}

/// Neutral Flutter widget used when a catalog slot has no Dart default.
final class WidgetbookPlaceholderWidgetValuePlan
    extends WidgetbookNativeValuePlan {
  /// Creates a placeholder assignable to the base Flutter `Widget` type.
  const WidgetbookPlaceholderWidgetValuePlan({required super.type});
}

/// Customer structured or widget constructor expression.
final class WidgetbookConstructorValuePlan extends WidgetbookNativeValuePlan {
  /// Creates a constructor plan.
  const WidgetbookConstructorValuePlan({
    required super.type,
    required this.arguments,
    this.namedConstructor,
  });

  /// Named constructor suffix, or `null` for the unnamed constructor.
  final String? namedConstructor;

  /// Arguments in source constructor order.
  final List<WidgetbookNativeArgumentPlan> arguments;
}

/// Lowers validated canonical customer values to typed native-Dart IR.
final class WidgetbookNativeValuePlanner {
  /// Creates a planner over one package index.
  const WidgetbookNativeValuePlanner(this.index);

  /// Package-wide catalog/analyzer facts.
  final WidgetbookCatalogSourceIndex index;

  /// Verifies that a catalog property's analyzer type is the exact Dart or
  /// Flutter type promised by its catalog semantic.
  void validatePropertyType({
    required WidgetbookWidgetSource widget,
    required PropertyEntry property,
    required String path,
  }) {
    final input = _constructorInput(widget, property.name, path);
    _validatePropertyDartType(
      property.type,
      input.type,
      path,
      context: WidgetbookPropertyContext.widgetProperty,
      customerStructuredList: isCustomerStructuredListShape(
        property.valueShape,
      ),
    );
  }

  /// Lowers one root-widget property value.
  WidgetbookNativeValuePlan lowerProperty({
    required WidgetbookWidgetSource widget,
    required PropertyEntry property,
    required Object? value,
    required String path,
  }) {
    final input = _constructorInput(widget, property.name, path);
    return _lower(
      ownerSourceType: widget.entry.flutterType,
      name: property.name,
      propertyType: property.type,
      valueShape: property.valueShape,
      dartType: input.type,
      value: value,
      path: path,
    );
  }

  /// Synthesizes a native preview using only Dart and catalog facts.
  WidgetbookNativeValuePlan synthesizeProperty({
    required WidgetbookWidgetSource widget,
    required PropertyEntry property,
    required int minimumItems,
    required String path,
  }) {
    final input = _constructorInput(widget, property.name, path);
    return _synthesize(
      ownerSourceType: widget.entry.flutterType,
      name: property.name,
      propertyType: property.type,
      valueShape: property.valueShape,
      dartType: input.type,
      minimumItems: minimumItems,
      path: path,
      visiting: <String>{},
    );
  }

  WidgetbookNativeValuePlan _lower({
    required String ownerSourceType,
    required String name,
    required PropertyType propertyType,
    required CatalogValueShape? valueShape,
    required DartType dartType,
    required Object? value,
    required String path,
  }) {
    _validatePropertyDartType(
      propertyType,
      dartType,
      path,
      context: index.structuredBySourceType.containsKey(ownerSourceType)
          ? WidgetbookPropertyContext.structuredField
          : WidgetbookPropertyContext.widgetProperty,
      customerStructuredList: isCustomerStructuredListShape(valueShape),
    );
    final type = WidgetbookDartTypePlan.fromAnalyzer(dartType, path: path);
    if (value == null) {
      if (!type.nullable) {
        throw StateError('Widgetbook native value at $path cannot be null.');
      }
      return WidgetbookNullValuePlan(type: type);
    }

    if (!isCustomerStructuredListShape(valueShape)) {
      _validateNativeInput(propertyType, dartType, value, path);
    }

    if (isCustomerStructuredListShape(valueShape)) {
      if (value is! List<Object?> || dartType is! InterfaceType) {
        throw StateError(
          'Widgetbook native value at $path is not a typed structured list.',
        );
      }
      final itemType = dartType.typeArguments.single;
      return WidgetbookListValuePlan(
        type: type,
        values: [
          for (var position = 0; position < value.length; position++)
            _lowerStructured(
              ownerSourceType: ownerSourceType,
              name: name,
              dartType: itemType,
              value: value[position],
              path: '$path/$position',
            ),
        ],
      );
    }

    return switch (propertyType) {
      PropertyType.structured => _lowerStructured(
          ownerSourceType: ownerSourceType,
          name: name,
          dartType: dartType,
          value: value,
          path: path,
        ),
      PropertyType.enumValue
          when value is String && _enumMembers(dartType).contains(value) =>
        WidgetbookEnumValuePlan(
          type: type,
          member: value,
        ),
      PropertyType.color => WidgetbookFrameworkValuePlan(
          type: type,
          kind: WidgetbookFrameworkLiteralKind.color,
          value: value,
        ),
      PropertyType.edgeInsets => WidgetbookFrameworkValuePlan(
          type: type,
          kind: WidgetbookFrameworkLiteralKind.edgeInsets,
          value: value,
        ),
      PropertyType.alignment => WidgetbookFrameworkValuePlan(
          type: type,
          kind: WidgetbookFrameworkLiteralKind.alignment,
          value: value,
        ),
      PropertyType.offset => WidgetbookFrameworkValuePlan(
          type: type,
          kind: WidgetbookFrameworkLiteralKind.offset,
          value: value,
        ),
      PropertyType.fontWeight => WidgetbookFrameworkValuePlan(
          type: type,
          kind: WidgetbookFrameworkLiteralKind.fontWeight,
          value: value,
        ),
      PropertyType.duration => WidgetbookFrameworkValuePlan(
          type: type,
          kind: WidgetbookFrameworkLiteralKind.duration,
          value: value,
        ),
      PropertyType.curve => WidgetbookFrameworkValuePlan(
          type: type,
          kind: WidgetbookFrameworkLiteralKind.curve,
          value: value,
        ),
      PropertyType.string when value is String =>
        WidgetbookScalarValuePlan(type: type, value: value),
      PropertyType.boolean when value is bool =>
        WidgetbookScalarValuePlan(type: type, value: value),
      PropertyType.integer when value is int =>
        WidgetbookScalarValuePlan(type: type, value: value),
      PropertyType.real when value is num && value.isFinite =>
        WidgetbookScalarValuePlan(type: type, value: value),
      PropertyType.stringList
          when value is List<Object?> &&
              value.every((item) => item is String) &&
              dartType is InterfaceType =>
        WidgetbookListValuePlan(
          type: type,
          values: [
            for (final item in value)
              WidgetbookScalarValuePlan(
                type: WidgetbookDartTypePlan.fromAnalyzer(
                  dartType.typeArguments.single,
                  path: path,
                ),
                value: item!,
              ),
          ],
        ),
      PropertyType.widget ||
      PropertyType.widgetList ||
      PropertyType.string ||
      PropertyType.boolean ||
      PropertyType.integer ||
      PropertyType.real ||
      PropertyType.stringList ||
      PropertyType.enumValue ||
      PropertyType.event ||
      PropertyType.length ||
      PropertyType.alignmentXY ||
      PropertyType.booleanList ||
      PropertyType.dataReference ||
      PropertyType.gradient ||
      PropertyType.border ||
      PropertyType.boxShadowList ||
      PropertyType.locale ||
      PropertyType.paint ||
      PropertyType.shadowList ||
      PropertyType.fontFeatureList ||
      PropertyType.fontVariationList ||
      PropertyType.textDecoration ||
      PropertyType.shapeBorder ||
      PropertyType.inlineSpan ||
      PropertyType.decorationImage ||
      PropertyType.selectionOptionList ||
      PropertyType.unknown =>
        throw StateError(
          'Widgetbook native value at $path has unsupported admitted type '
          '${propertyType.name}.',
        ),
    };
  }

  WidgetbookNativeValuePlan _synthesize({
    required String ownerSourceType,
    required String name,
    required PropertyType propertyType,
    required CatalogValueShape? valueShape,
    required DartType dartType,
    required int minimumItems,
    required String path,
    required Set<String> visiting,
    bool nullableFallback = false,
  }) {
    _validatePropertyDartType(
      propertyType,
      dartType,
      path,
      context: index.structuredBySourceType.containsKey(ownerSourceType)
          ? WidgetbookPropertyContext.structuredField
          : WidgetbookPropertyContext.widgetProperty,
      customerStructuredList: isCustomerStructuredListShape(valueShape),
    );
    final type = WidgetbookDartTypePlan.fromAnalyzer(dartType, path: path);
    if (nullableFallback && type.nullable) {
      return WidgetbookNullValuePlan(type: type);
    }
    if (isCustomerStructuredListShape(valueShape)) {
      if (dartType is! InterfaceType || dartType.typeArguments.length != 1) {
        throw StateError('Widgetbook preview at $path is not a typed list.');
      }
      return WidgetbookListValuePlan(
        type: type,
        values: [
          for (var index = 0; index < minimumItems; index++)
            _synthesizeStructured(
              ownerSourceType: ownerSourceType,
              name: name,
              dartType: dartType.typeArguments.single,
              path: '$path/$index',
              visiting: visiting,
            ),
        ],
      );
    }
    switch (propertyType) {
      case PropertyType.widget:
        final element = dartType.element;
        if (element == null ||
            element.name != 'Widget' ||
            element.library?.identifier.startsWith('package:flutter/') !=
                true) {
          throw StateError(
            'Widgetbook preview at $path cannot synthesize the specialized '
            'widget type `${dartType.getDisplayString()}`. This is a Restage '
            'compiler capability gap.',
          );
        }
        return WidgetbookPlaceholderWidgetValuePlan(type: type);
      case PropertyType.widgetList:
        if (dartType is! InterfaceType || dartType.typeArguments.length != 1) {
          throw StateError('Widgetbook preview at $path is not a typed list.');
        }
        final itemType = WidgetbookDartTypePlan.fromAnalyzer(
          dartType.typeArguments.single,
          path: '$path/items',
        );
        return WidgetbookListValuePlan(
          type: type,
          values: [
            for (var index = 0; index < minimumItems; index++)
              WidgetbookPlaceholderWidgetValuePlan(type: itemType),
          ],
        );
      case PropertyType.structured:
        return _synthesizeStructured(
          ownerSourceType: ownerSourceType,
          name: name,
          dartType: dartType,
          path: path,
          visiting: visiting,
        );
      case PropertyType.enumValue:
        final members = _enumMembers(dartType);
        if (members.isEmpty) {
          throw StateError('Widgetbook preview at $path has no enum member.');
        }
        return WidgetbookEnumValuePlan(type: type, member: members.first);
      case PropertyType.color:
        return _lower(
          ownerSourceType: ownerSourceType,
          name: name,
          propertyType: propertyType,
          valueShape: valueShape,
          dartType: dartType,
          value: 0xFF000000,
          path: path,
        );
      case PropertyType.edgeInsets:
        return _lower(
          ownerSourceType: ownerSourceType,
          name: name,
          propertyType: propertyType,
          valueShape: valueShape,
          dartType: dartType,
          value: const <Object?>[0, 0, 0, 0],
          path: path,
        );
      case PropertyType.alignment:
        return _lower(
          ownerSourceType: ownerSourceType,
          name: name,
          propertyType: propertyType,
          valueShape: valueShape,
          dartType: dartType,
          value: 'center',
          path: path,
        );
      case PropertyType.offset:
        return _lower(
          ownerSourceType: ownerSourceType,
          name: name,
          propertyType: propertyType,
          valueShape: valueShape,
          dartType: dartType,
          value: const <String, Object?>{'x': 0, 'y': 0},
          path: path,
        );
      case PropertyType.fontWeight:
        return _lower(
          ownerSourceType: ownerSourceType,
          name: name,
          propertyType: propertyType,
          valueShape: valueShape,
          dartType: dartType,
          value: 'normal',
          path: path,
        );
      case PropertyType.duration:
        return _lower(
          ownerSourceType: ownerSourceType,
          name: name,
          propertyType: propertyType,
          valueShape: valueShape,
          dartType: dartType,
          value: 0,
          path: path,
        );
      case PropertyType.curve:
        return _lower(
          ownerSourceType: ownerSourceType,
          name: name,
          propertyType: propertyType,
          valueShape: valueShape,
          dartType: dartType,
          value: 'linear',
          path: path,
        );
      case PropertyType.stringList:
        if (dartType is! InterfaceType || dartType.typeArguments.length != 1) {
          throw StateError('Widgetbook preview at $path is not a typed list.');
        }
        return _lower(
          ownerSourceType: ownerSourceType,
          name: name,
          propertyType: propertyType,
          valueShape: valueShape,
          dartType: dartType,
          value: <Object?>[
            for (var index = 0; index < minimumItems; index++) '',
          ],
          path: path,
        );
      case PropertyType.string:
        return WidgetbookScalarValuePlan(type: type, value: '');
      case PropertyType.boolean:
        return WidgetbookScalarValuePlan(type: type, value: false);
      case PropertyType.integer:
        return WidgetbookScalarValuePlan(type: type, value: 0);
      case PropertyType.real:
        return WidgetbookScalarValuePlan(type: type, value: 0.0);
      case PropertyType.event ||
            PropertyType.length ||
            PropertyType.alignmentXY ||
            PropertyType.booleanList ||
            PropertyType.dataReference ||
            PropertyType.gradient ||
            PropertyType.border ||
            PropertyType.boxShadowList ||
            PropertyType.locale ||
            PropertyType.paint ||
            PropertyType.shadowList ||
            PropertyType.fontFeatureList ||
            PropertyType.fontVariationList ||
            PropertyType.textDecoration ||
            PropertyType.shapeBorder ||
            PropertyType.inlineSpan ||
            PropertyType.decorationImage ||
            PropertyType.selectionOptionList ||
            PropertyType.unknown:
        throw StateError(
          'Widgetbook preview at $path has no total synthesizer for '
          '${propertyType.name}. This is a Restage compiler capability gap.',
        );
    }
  }

  WidgetbookNativeValuePlan _synthesizeStructured({
    required String ownerSourceType,
    required String name,
    required DartType dartType,
    required String path,
    required Set<String> visiting,
  }) {
    final target = index.slotTargets[structuredSlotKey(ownerSourceType, name)];
    if (target == null || !visiting.add(target)) {
      throw StateError(
        'Widgetbook preview at $path cannot synthesize structured type '
        '${target ?? '<missing>'}.',
      );
    }
    try {
      final source = index.structuredSources[target];
      final reconstruction = index.reconstructionPlans[target];
      if (source == null || reconstruction == null) {
        throw StateError(
          'Widgetbook preview at $path cannot reconstruct $target.',
        );
      }
      final constructor = source.constructorFor(reconstruction);
      if (constructor == null) {
        throw StateError(
          'Widgetbook preview at $path cannot resolve $target constructor.',
        );
      }
      final fields = {
        for (final field in source.entry.fields) field.name: field,
      };
      final parameters = <String, FormalParameterElement>{
        for (final parameter in constructor.formalParameters)
          if (parameter.name case final String parameterName)
            parameterName: parameter,
      };
      final arguments = <WidgetbookNativeArgumentPlan>[];
      for (final argument in reconstruction.args) {
        if (!argument.isRequired) continue;
        final field = fields[argument.fieldName];
        final parameter = parameters[argument.fieldName];
        if (field == null || parameter == null) {
          throw StateError(
            'Widgetbook preview at $path has an incomplete reconstruction '
            'plan for ${argument.fieldName}.',
          );
        }
        final literal = field.defaultSource;
        final value = literal is LiteralDefault
            ? _lower(
                ownerSourceType: target,
                name: field.name,
                propertyType: field.type,
                valueShape: field.valueShape,
                dartType: parameter.type,
                value: literal.value,
                path: '$path/${field.name}',
              )
            : _synthesize(
                ownerSourceType: target,
                name: field.name,
                propertyType: field.type,
                valueShape: field.valueShape,
                dartType: parameter.type,
                minimumItems: 0,
                path: '$path/${field.name}',
                visiting: visiting,
                nullableFallback: true,
              );
        arguments.add(
          WidgetbookNativeArgumentPlan(
            name: argument.isNamed ? argument.fieldName : null,
            value: value,
          ),
        );
      }
      return WidgetbookConstructorValuePlan(
        type: WidgetbookDartTypePlan.fromAnalyzer(dartType, path: path),
        namedConstructor: reconstruction.namedConstructor,
        arguments: arguments,
      );
    } finally {
      visiting.remove(target);
    }
  }

  WidgetbookNativeValuePlan _lowerStructured({
    required String ownerSourceType,
    required String name,
    required DartType dartType,
    required Object? value,
    required String path,
  }) {
    if (value is! Map<String, Object?>) {
      throw StateError('Widgetbook native value at $path must be an object.');
    }
    final target = index.slotTargets[structuredSlotKey(ownerSourceType, name)];
    if (target == null) {
      throw StateError('Widgetbook native value at $path has no target type.');
    }
    final source = index.structuredSources[target];
    final reconstruction = index.reconstructionPlans[target];
    if (source == null || reconstruction == null) {
      throw StateError(
        'Widgetbook native value at $path cannot reconstruct $target.',
      );
    }
    final fields = {for (final field in source.entry.fields) field.name: field};
    final constructor = source.constructorFor(reconstruction);
    if (constructor == null) {
      throw StateError(
        'Widgetbook native value at $path cannot resolve the constructor for '
        '$target.',
      );
    }
    final parameters = <String, FormalParameterElement>{
      for (final parameter in constructor.formalParameters)
        if (parameter.name case final String parameterName)
          parameterName: parameter,
    };
    final arguments = <WidgetbookNativeArgumentPlan>[];
    for (final argument in reconstruction.args) {
      if (!value.containsKey(argument.fieldName)) {
        if (argument.isRequired) {
          throw StateError(
            'Widgetbook native value at $path is missing required field '
            '${argument.fieldName}.',
          );
        }
        continue;
      }
      final field = fields[argument.fieldName];
      final parameter = parameters[argument.fieldName];
      if (field == null || parameter == null) {
        throw StateError(
          'Widgetbook native value at $path has an incomplete reconstruction '
          'plan for ${argument.fieldName}.',
        );
      }
      arguments.add(
        WidgetbookNativeArgumentPlan(
          name: argument.isNamed ? argument.fieldName : null,
          value: _lower(
            ownerSourceType: target,
            name: field.name,
            propertyType: field.type,
            valueShape: field.valueShape,
            dartType: parameter.type,
            value: value[field.name],
            path: '$path/${field.name}',
          ),
        ),
      );
    }
    return WidgetbookConstructorValuePlan(
      type: WidgetbookDartTypePlan.fromAnalyzer(dartType, path: path),
      namedConstructor: reconstruction.namedConstructor,
      arguments: arguments,
    );
  }

  WidgetConstructorInput _constructorInput(
    WidgetbookWidgetSource widget,
    String name,
    String path,
  ) {
    final input = widget.constructorInputs[name];
    if (input == null) {
      throw StateError(
        'Widgetbook native value at $path cannot resolve constructor '
        'parameter $name.',
      );
    }
    return input;
  }
}

/// Deterministic renderer for native value/type plans.
final class WidgetbookNativeDartRenderer {
  /// Creates a renderer and assigns aliases from the full plan set before any
  /// source is written.
  WidgetbookNativeDartRenderer({
    required this.currentLibraryUri,
    required Iterable<WidgetbookDartValuePlan> values,
    this.currentLibraryAlias,
    Iterable<WidgetbookDartTypeUse> additionalTypeUses = const [],
    Iterable<DartBareSymbolImport> additionalBareSymbolImports = const [],
    Iterable<DartBareSymbolReservation> bareSymbolReservations = const [],
  }) {
    final additionalTypeList = additionalTypeUses.toList(growable: false);
    final uris = <String>{};
    for (final value in values) {
      _collectValueUris(value, uris);
    }
    final bareSymbolImports = additionalBareSymbolImports.toList();
    for (final use in additionalTypeList) {
      _collectTypeUris(use.type, uris);
      _collectBareTypeImports(
        use.type,
        sourcePath: use.sourcePath,
        imports: bareSymbolImports,
      );
    }
    _imports = DartImportPlanner(
      libraryUris: uris,
      prefixStem: 'restage_native_',
      fixedPrefixes: {
        if (currentLibraryAlias case final alias?) currentLibraryUri: alias,
      },
      bareSymbolImports: bareSymbolImports,
      bareSymbolReservations: bareSymbolReservations,
    );
  }

  /// Defining library of the generated story's widget.
  final String currentLibraryUri;

  /// Optional prefix for symbols imported from [currentLibraryUri].
  final String? currentLibraryAlias;

  late final DartImportPlanner _imports;

  /// Deterministic prefixed customer imports required by the plans.
  Iterable<String> get importDirectives => _imports.importDirectives;

  /// Renders a static Dart type.
  String renderType(WidgetbookDartTypePlan type) =>
      _imports.renderType(_dartTypeIdentity(type));

  /// Renders one native expression.
  String renderValue(WidgetbookDartValuePlan value) => switch (value) {
        WidgetbookNullValuePlan() => 'null',
        WidgetbookScalarValuePlan(:final value) => _dartLiteral(value),
        WidgetbookFunctionReferenceValuePlan(
          :final libraryUri,
          :final owner,
          :final member,
        ) =>
          _imports.qualifyReference(
            libraryUri: libraryUri,
            owner: owner,
            member: member,
          ),
        WidgetbookEnumValuePlan(:final type, :final member) =>
          '${renderType(type.nonNullable)}.$member',
        WidgetbookStaticMemberValuePlan(
          :final libraryUri,
          :final owner,
          :final member,
        ) =>
          _imports.qualifyReference(
            libraryUri: libraryUri,
            owner: owner,
            member: member,
          ),
        WidgetbookDartConstValuePlan(:final value) =>
          renderDartConstValueFromPrefixes(
            value,
            _imports.prefixesBySourceUri,
          ),
        WidgetbookFrameworkValuePlan(
          :final type,
          :final kind,
          :final value,
        ) =>
          _frameworkLiteral(type, kind, value),
        WidgetbookListValuePlan(:final type, :final values) =>
          '<${renderType(type.typeArguments.single)}>'
              '[${values.map(renderValue).join(', ')}]',
        WidgetbookPlaceholderWidgetValuePlan(:final type) =>
          'const ${_imports.qualify(type.libraryUri, 'SizedBox')}.shrink()',
        WidgetbookConstructorValuePlan(
          :final type,
          :final namedConstructor,
          :final arguments,
        ) =>
          '${renderType(type.nonNullable)}'
              '${namedConstructor == null ? '' : '.$namedConstructor'}('
              '${arguments.map(_renderArgument).join(', ')})',
      };

  String _renderArgument(WidgetbookNativeArgumentPlan argument) {
    final value = renderValue(argument.value);
    return argument.name == null ? value : '${argument.name}: $value';
  }

  String _frameworkLiteral(
    WidgetbookDartTypePlan type,
    WidgetbookFrameworkLiteralKind kind,
    Object value,
  ) {
    final renderedType = renderType(type.nonNullable);
    String owner(String symbol) => _imports.qualify(type.libraryUri, symbol);
    return switch (kind) {
      WidgetbookFrameworkLiteralKind.color =>
        _colorLiteral(value, renderedType),
      WidgetbookFrameworkLiteralKind.edgeInsets => _edgeInsetsLiteral(
          value,
          type.symbol == 'EdgeInsetsDirectional'
              ? owner('EdgeInsetsDirectional')
              : owner('EdgeInsets'),
          directional: type.symbol == 'EdgeInsetsDirectional',
        ),
      WidgetbookFrameworkLiteralKind.alignment =>
        _alignmentLiteral(value, type.symbol, owner),
      WidgetbookFrameworkLiteralKind.offset =>
        _offsetLiteral(value, renderedType),
      WidgetbookFrameworkLiteralKind.fontWeight =>
        _fontWeightLiteral(value, renderedType),
      WidgetbookFrameworkLiteralKind.duration =>
        'const $renderedType(milliseconds: $value)',
      WidgetbookFrameworkLiteralKind.curve
          when value is String && kSupportedCurveNames.contains(value) =>
        '${owner('Curves')}.$value',
      WidgetbookFrameworkLiteralKind.curve => throw StateError(
          'unsupported framework curve literal: $value',
        ),
    };
  }
}

DartTypeIdentity _dartTypeIdentity(WidgetbookDartTypePlan type) =>
    DartTypeIdentity(
      libraryUri: type.libraryUri,
      symbolName: type.symbol,
      typeArguments: [
        for (final argument in type.typeArguments) _dartTypeIdentity(argument),
      ],
      nullable: type.nullable,
    );

void _collectValueUris(
  WidgetbookDartValuePlan value,
  Set<String> uris,
) {
  if (value is WidgetbookNativeValuePlan) {
    _collectTypeUris(value.type, uris);
  }
  switch (value) {
    case WidgetbookFunctionReferenceValuePlan(:final libraryUri):
      uris.add(libraryUri);
    case WidgetbookStaticMemberValuePlan(:final libraryUri):
      uris.add(libraryUri);
    case WidgetbookDartConstValuePlan(:final value):
      uris.addAll(dartConstValueLibraryUris(value));
    case WidgetbookListValuePlan(:final values):
      for (final child in values) {
        _collectValueUris(child, uris);
      }
    case WidgetbookConstructorValuePlan(:final arguments):
      for (final argument in arguments) {
        _collectValueUris(argument.value, uris);
      }
    case WidgetbookNullValuePlan() ||
          WidgetbookScalarValuePlan() ||
          WidgetbookEnumValuePlan() ||
          WidgetbookFrameworkValuePlan() ||
          WidgetbookPlaceholderWidgetValuePlan():
      break;
  }
}

void _collectTypeUris(WidgetbookDartTypePlan type, Set<String> uris) {
  uris.add(type.libraryUri);
  for (final argument in type.typeArguments) {
    _collectTypeUris(argument, uris);
  }
}

void _collectBareTypeImports(
  WidgetbookDartTypePlan type, {
  required String sourcePath,
  required List<DartBareSymbolImport> imports,
}) {
  imports.add(
    DartBareSymbolImport(
      libraryUri: type.libraryUri,
      symbol: type.symbol,
      sourcePath: sourcePath,
    ),
  );
  for (final argument in type.typeArguments) {
    _collectBareTypeImports(
      argument,
      sourcePath: sourcePath,
      imports: imports,
    );
  }
}

String _colorLiteral(Object value, String type) {
  final int argb;
  if (value is int) {
    argb = value;
  } else if (value is String) {
    final normalized = value.startsWith('#')
        ? value.substring(1)
        : value.startsWith('0x') || value.startsWith('0X')
            ? value.substring(2)
            : '';
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null || normalized.length != 6 && normalized.length != 8) {
      throw StateError('invalid color literal $value');
    }
    argb = normalized.length == 6 ? 0xFF000000 | parsed : parsed;
  } else {
    throw StateError('invalid color literal $value');
  }
  final hex = argb.toRadixString(16).padLeft(8, '0').toUpperCase();
  return 'const $type(0x$hex)';
}

String _edgeInsetsLiteral(
  Object value,
  String type, {
  required bool directional,
}) {
  final values = _numberList(value, 4).join(', ');
  return directional
      ? 'const $type.fromSTEB($values)'
      : 'const $type.fromLTRB($values)';
}

String _alignmentLiteral(
  Object value,
  String type,
  String Function(String symbol) qualify,
) {
  if (value is String) {
    final directional = value.contains('Start') || value.contains('End');
    final owner = type == 'AlignmentDirectional' ||
            type == 'AlignmentGeometry' && directional
        ? qualify('AlignmentDirectional')
        : qualify('Alignment');
    return '$owner.$value';
  }
  if (value is! Map<String, Object?>) {
    throw StateError('invalid alignment literal $value');
  }
  final y = _number(value['y']);
  if (value['start'] case final num start) {
    return 'const ${qualify('AlignmentDirectional')}(${_number(start)}, $y)';
  }
  return 'const ${qualify('Alignment')}(${_number(value['x'])}, $y)';
}

String _offsetLiteral(Object value, String type) {
  if (value is! Map<String, Object?>) {
    throw StateError('invalid offset literal $value');
  }
  return 'const $type(${_number(value['x'])}, ${_number(value['y'])})';
}

String _fontWeightLiteral(Object value, String type) {
  final member = value is int ? 'w$value' : value;
  return '$type.$member';
}

List<String> _numberList(Object value, int length) {
  if (value is! List<Object?> || value.length != length) {
    throw StateError('expected $length numbers, got $value');
  }
  return [for (final item in value) _number(item)];
}

String _number(Object? value) {
  if (value is! num || !value.isFinite) {
    throw StateError('expected finite number, got $value');
  }
  return value.toString();
}

String _dartLiteral(Object value) {
  if (value is String) return jsonEncode(value).replaceAll(r'$', r'\$');
  if (value is num && !value.isFinite) {
    throw StateError('non-finite Dart literal $value');
  }
  return jsonEncode(value);
}

Set<String> _enumMembers(DartType type) {
  final element = type is InterfaceType ? type.element : null;
  if (element is! EnumElement) return const {};
  return {
    for (final field in element.fields)
      if (field.isEnumConstant && field.name != null) field.name!,
  };
}

void _validateNativeInput(
  PropertyType propertyType,
  DartType dartType,
  Object value,
  String path,
) {
  bool finite(Object? candidate) => candidate is num && candidate.isFinite;
  bool coordinateMap(Object candidate, String horizontal) =>
      candidate is Map<String, Object?> &&
      candidate.length == 2 &&
      finite(candidate[horizontal]) &&
      finite(candidate['y']);
  final valid = switch (propertyType) {
    PropertyType.color => _isColorValue(value),
    PropertyType.edgeInsets =>
      value is List<Object?> && value.length == 4 && value.every(finite),
    PropertyType.alignment => _isAlignmentValue(value, dartType),
    PropertyType.offset => coordinateMap(value, 'x'),
    PropertyType.fontWeight =>
      value is int && value >= 100 && value <= 900 && value % 100 == 0 ||
          value is String && _fontWeightMembers.contains(value),
    PropertyType.duration => value is int,
    PropertyType.curve =>
      value is String && kSupportedCurveNames.contains(value),
    PropertyType.widget ||
    PropertyType.widgetList ||
    PropertyType.boolean ||
    PropertyType.integer ||
    PropertyType.real ||
    PropertyType.string ||
    PropertyType.stringList ||
    PropertyType.enumValue ||
    PropertyType.structured =>
      true,
    PropertyType.event ||
    PropertyType.length ||
    PropertyType.alignmentXY ||
    PropertyType.booleanList ||
    PropertyType.dataReference ||
    PropertyType.gradient ||
    PropertyType.border ||
    PropertyType.boxShadowList ||
    PropertyType.locale ||
    PropertyType.paint ||
    PropertyType.shadowList ||
    PropertyType.fontFeatureList ||
    PropertyType.fontVariationList ||
    PropertyType.textDecoration ||
    PropertyType.shapeBorder ||
    PropertyType.inlineSpan ||
    PropertyType.decorationImage ||
    PropertyType.selectionOptionList ||
    PropertyType.unknown =>
      false,
  };
  if (!valid) {
    throw StateError(
      'Widgetbook native value at $path is not a valid '
      '${propertyType.name} value.',
    );
  }
}

bool _isColorValue(Object value) {
  if (value is int) return value >= 0 && value <= 0xFFFFFFFF;
  if (value is! String) return false;
  final normalized = value.startsWith('#')
      ? value.substring(1)
      : value.startsWith('0x') || value.startsWith('0X')
          ? value.substring(2)
          : '';
  return (normalized.length == 6 || normalized.length == 8) &&
      RegExp(r'^[0-9a-fA-F]+$').hasMatch(normalized);
}

bool _isAlignmentValue(
  Object value,
  DartType dartType,
) {
  final typeName = dartType.element?.name;
  final directional = typeName == 'AlignmentDirectional';
  final concrete = typeName == 'Alignment';
  if (value is String) {
    if (directional) return _alignmentDirectionalMembers.contains(value);
    if (concrete) return _alignmentMembers.contains(value);
    return _alignmentMembers.contains(value) ||
        _alignmentDirectionalMembers.contains(value);
  }
  bool coordinate(String horizontal) =>
      value is Map<String, Object?> &&
      value.length == 2 &&
      value[horizontal] is num &&
      (value[horizontal]! as num).isFinite &&
      value['y'] is num &&
      (value['y']! as num).isFinite;
  if (directional) return coordinate('start');
  if (concrete) return coordinate('x');
  return coordinate('x') || coordinate('start');
}

const _alignmentMembers = <String>{
  'topLeft',
  'topCenter',
  'topRight',
  'centerLeft',
  'center',
  'centerRight',
  'bottomLeft',
  'bottomCenter',
  'bottomRight',
};

const _alignmentDirectionalMembers = <String>{
  'topStart',
  'topCenter',
  'topEnd',
  'centerStart',
  'center',
  'centerEnd',
  'bottomStart',
  'bottomCenter',
  'bottomEnd',
};

const _fontWeightMembers = <String>{
  'w100',
  'w200',
  'w300',
  'w400',
  'w500',
  'w600',
  'w700',
  'w800',
  'w900',
  'normal',
  'bold',
};

void _validatePropertyDartType(
  PropertyType propertyType,
  DartType dartType,
  String path, {
  required WidgetbookPropertyContext context,
  required bool customerStructuredList,
}) {
  if (!customerStructuredList &&
      widgetbookPropertyCapability(propertyType, context: context) ==
          WidgetbookPropertyCapability.rejected) {
    throw StateError(
      'Widgetbook native value at $path has no ${context.name} lowering for '
      '${propertyType.name}.',
    );
  }
  if (dartType is! InterfaceType) {
    throw StateError(
      'Widgetbook native value at $path has unsupported analyzer type '
      '`${dartType.getDisplayString()}`.',
    );
  }
  final element = dartType.element;
  final library = element.library.identifier;
  final name = element.name;
  bool isDartCore(String symbol) => library == 'dart:core' && name == symbol;
  bool isFlutterType(Set<String> symbols) =>
      library.startsWith('package:flutter/') && symbols.contains(name);
  bool isWidgetType(DartType type) {
    if (type is! InterfaceType) return false;
    return <InterfaceType>[type, ...type.allSupertypes].any(
      (candidate) =>
          candidate.element.name == 'Widget' &&
          candidate.element.library.identifier.startsWith('package:flutter/'),
    );
  }

  if (customerStructuredList) {
    if (!isDartCore('List') || dartType.typeArguments.length != 1) {
      throw StateError(
        'Widgetbook native value at $path expected a customer structured '
        'List, but the analyzer resolved `${dartType.getDisplayString()}`.',
      );
    }
    return;
  }

  final valid = switch (propertyType) {
    PropertyType.widget => isWidgetType(dartType),
    PropertyType.widgetList => isDartCore('List') &&
        dartType.typeArguments.length == 1 &&
        isWidgetType(dartType.typeArguments.single),
    PropertyType.string => isDartCore('String'),
    PropertyType.boolean => isDartCore('bool'),
    PropertyType.integer => isDartCore('int'),
    PropertyType.real => isDartCore('double') || isDartCore('num'),
    // Classification in type_inference.dart decides whether a type is a
    // framework value type. This defensively verifies a pairing produced
    // elsewhere: lookalikes cannot reach here, but other disagreements can.
    PropertyType.stringList => isDartCore('List') &&
        dartType.typeArguments.length == 1 &&
        dartType.typeArguments.single.element?.library?.identifier ==
            'dart:core' &&
        dartType.typeArguments.single.element?.name == 'String',
    PropertyType.enumValue => element is EnumElement,
    PropertyType.color => library == 'dart:ui' && name == 'Color',
    PropertyType.edgeInsets => isFlutterType(const {
        'EdgeInsets',
        'EdgeInsetsDirectional',
        'EdgeInsetsGeometry',
      }),
    PropertyType.alignment => isFlutterType(const {
        'Alignment',
        'AlignmentDirectional',
        'AlignmentGeometry',
      }),
    PropertyType.offset => library == 'dart:ui' && name == 'Offset',
    PropertyType.fontWeight => library == 'dart:ui' && name == 'FontWeight',
    PropertyType.duration => isDartCore('Duration'),
    PropertyType.curve => isFlutterType(const {'Curve'}),
    PropertyType.structured => true,
    PropertyType.event ||
    PropertyType.length ||
    PropertyType.alignmentXY ||
    PropertyType.booleanList ||
    PropertyType.dataReference ||
    PropertyType.gradient ||
    PropertyType.border ||
    PropertyType.boxShadowList ||
    PropertyType.locale ||
    PropertyType.paint ||
    PropertyType.shadowList ||
    PropertyType.fontFeatureList ||
    PropertyType.fontVariationList ||
    PropertyType.textDecoration ||
    PropertyType.shapeBorder ||
    PropertyType.inlineSpan ||
    PropertyType.decorationImage ||
    PropertyType.selectionOptionList ||
    PropertyType.unknown =>
      false,
  };
  if (!valid) {
    throw StateError(
      'Widgetbook native value at $path expected ${propertyType.name}, but '
      'the analyzer resolved `${dartType.getDisplayString()}` from $library.',
    );
  }
}
