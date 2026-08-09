import 'dart:math' as math;

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/a2ui/a2ui_legacy_constraint_parser.dart';
import 'package:restage_codegen/src/callback_shape.dart';
import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_catalog_source_index.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_native_value_plan.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Sidebar control selected after a value has been lowered to native Dart.
enum WidgetbookStoryControl {
  /// Editable String control.
  string,

  /// Editable boolean control.
  boolean,

  /// Editable integer control.
  integer,

  /// Editable real-number control.
  real,

  /// Widgetbook Color control.
  color,

  /// Widgetbook Duration control.
  duration,

  /// Finite local choice mapped to the property's native value.
  choice,

  /// Read-only native value carried by a private story adapter.
  native,

  /// Boolean event flag mapped to a generated callback.
  event,
}

/// Editable controls that always carry a native seed.
enum WidgetbookStoryEditableControl {
  /// Editable String control.
  string,

  /// Editable boolean control.
  boolean,

  /// Editable integer control.
  integer,

  /// Editable real-number control.
  real,

  /// Widgetbook Color control.
  color,

  /// Widgetbook Duration control.
  duration,
}

/// Why a concrete value was selected as a story's initial value.
enum WidgetbookSeedProvenance {
  /// Catalog literal default.
  catalogLiteral,

  /// Analyzer-resolved constructor default.
  constructorDefault,

  /// First finite allowed value or enum member.
  finiteChoice,

  /// Deterministic scalar preview value.
  scalarPreview,

  /// Nullable property with no non-null default claim.
  nullableFallback,

  /// Deterministic native preview synthesized from Dart/catalog facts.
  synthesizedPreview,
}

/// Static callback facts for a root event property.
final class WidgetbookStoryCallbackPlan {
  /// Creates callback facts.
  const WidgetbookStoryCallbackPlan({
    required this.nullable,
    required this.parameterCount,
    this.constructorDefault,
  });

  /// Whether the widget constructor accepts a null callback.
  final bool nullable;

  /// Supported positional callback arity (zero or one).
  final int parameterCount;

  /// Public importable callback constructor default, when non-null.
  final WidgetbookFunctionReferenceValuePlan? constructorDefault;
}

/// Shared facts for one generated sidebar property.
sealed class WidgetbookStoryPropertyPlan {
  const WidgetbookStoryPropertyPlan({
    required this.property,
    required this.constraints,
    required this.dartType,
    required this.description,
    required this.positional,
  });

  /// Shared catalog metadata.
  final PropertyEntry property;

  /// Typed constraints, including parsed legacy `validationRule` authoring.
  final RestageConstraints constraints;

  /// Real constructor parameter type.
  final WidgetbookDartTypePlan dartType;

  /// Widgetbook sidebar/control strategy.
  WidgetbookStoryControl get control;

  /// Sidebar description, including preserved constraints/default semantics.
  final String description;

  /// Whether the native constructor receives this argument positionally.
  final bool positional;
}

/// Editable scalar property with one non-null initial native value.
final class WidgetbookStoryEditablePropertyPlan
    extends WidgetbookStoryPropertyPlan {
  WidgetbookStoryEditablePropertyPlan._({
    required super.property,
    required super.constraints,
    required super.dartType,
    required super.description,
    required super.positional,
    required this.editableControl,
    required this.seed,
    required this.seedProvenance,
  });

  /// Closed editable-control family for this property.
  final WidgetbookStoryEditableControl editableControl;

  @override
  WidgetbookStoryControl get control => switch (editableControl) {
        WidgetbookStoryEditableControl.string => WidgetbookStoryControl.string,
        WidgetbookStoryEditableControl.boolean =>
          WidgetbookStoryControl.boolean,
        WidgetbookStoryEditableControl.integer =>
          WidgetbookStoryControl.integer,
        WidgetbookStoryEditableControl.real => WidgetbookStoryControl.real,
        WidgetbookStoryEditableControl.color => WidgetbookStoryControl.color,
        WidgetbookStoryEditableControl.duration =>
          WidgetbookStoryControl.duration,
      };

  /// Concrete initial story value.
  final WidgetbookNativeValuePlan seed;

  /// Origin of [seed].
  final WidgetbookSeedProvenance seedProvenance;
}

/// Finite-choice property with a seed proven to be one of [choices].
final class WidgetbookStoryChoicePropertyPlan
    extends WidgetbookStoryPropertyPlan {
  WidgetbookStoryChoicePropertyPlan._({
    required super.property,
    required super.constraints,
    required super.dartType,
    required super.description,
    required super.positional,
    required this.seed,
    required this.seedProvenance,
    required this.choices,
    required this.choiceLabels,
  })  : assert(choices.isNotEmpty, 'a choice property needs a choice'),
        assert(
          choices.length == choiceLabels.length,
          'every Widgetbook choice needs one human-facing label',
        );

  @override
  WidgetbookStoryControl get control => WidgetbookStoryControl.choice;

  /// Concrete initial story value.
  final WidgetbookNativeValuePlan seed;

  /// Origin of [seed].
  final WidgetbookSeedProvenance seedProvenance;

  /// Finite native values represented by a generated local choice enum.
  final List<WidgetbookNativeValuePlan> choices;

  /// Human-facing labels parallel to [choices].
  final List<String> choiceLabels;
}

/// Read-only native property carried by a private generated wrapper.
final class WidgetbookStoryNativePropertyPlan
    extends WidgetbookStoryPropertyPlan {
  WidgetbookStoryNativePropertyPlan._({
    required super.property,
    required super.constraints,
    required super.dartType,
    required super.description,
    required super.positional,
    required this.seed,
    required this.seedProvenance,
  });

  @override
  WidgetbookStoryControl get control => WidgetbookStoryControl.native;

  /// Concrete initial story value.
  final WidgetbookNativeValuePlan seed;

  /// Origin of [seed].
  final WidgetbookSeedProvenance seedProvenance;
}

/// Root event property with a complete callback plan and no data seed.
final class WidgetbookStoryEventPropertyPlan
    extends WidgetbookStoryPropertyPlan {
  WidgetbookStoryEventPropertyPlan._({
    required super.property,
    required super.constraints,
    required super.description,
    required super.positional,
    required this.callback,
  }) : super(
          dartType: const WidgetbookDartTypePlan(
            libraryUri: 'dart:core',
            symbol: 'bool',
          ),
        );

  @override
  WidgetbookStoryControl get control => WidgetbookStoryControl.event;

  /// Static callback facts.
  final WidgetbookStoryCallbackPlan callback;
}

/// Complete backend plan consumed by the Widgetbook story source renderer.
final class WidgetbookStoryPlan {
  /// Creates a story plan.
  const WidgetbookStoryPlan({
    required this.widget,
    required this.properties,
    required this.exclusions,
  });

  /// Customer widget source facts.
  final WidgetbookWidgetSource widget;

  /// Properties in catalog/source order.
  final List<WidgetbookStoryPropertyPlan> properties;

  /// Constructor inputs omitted from this target's generated story.
  final List<PropertyExclusion> exclusions;

  /// Every native Dart value used by the emitted source.
  Iterable<WidgetbookDartValuePlan> get nativeValues sync* {
    for (final property in properties) {
      switch (property) {
        case WidgetbookStoryEditablePropertyPlan(:final seed) ||
              WidgetbookStoryNativePropertyPlan(:final seed):
          yield seed;
        case WidgetbookStoryChoicePropertyPlan(:final seed, :final choices):
          yield seed;
          yield* choices;
        case WidgetbookStoryEventPropertyPlan(:final callback):
          if (callback.constructorDefault case final defaultValue?) {
            yield defaultValue;
          }
      }
    }
  }
}

/// Builds a total, seed-resolved story plan for one customer widget.
WidgetbookStoryPlan planWidgetbookStory({
  required WidgetbookCatalogSourceIndex index,
  required WidgetbookWidgetSource widget,
}) {
  final unrenderable = index.unrenderableByWidget[widget.entry.flutterType];
  if (unrenderable != null) {
    throw StateError(
      "Widgetbook story for '${widget.entry.name}' cannot be generated: "
      '$unrenderable. This is a Restage compiler capability gap.',
    );
  }
  final constructor = widget.constructor;
  if (constructor == null) {
    throw StateError(
      "Widgetbook story for '${widget.entry.name}' has no automatic "
      'constructor. This is outside the admitted automatic catalog contract.',
    );
  }

  final lowerer = WidgetbookNativeValuePlanner(index);
  final properties = <WidgetbookStoryPropertyPlan>[];

  for (final property in widget.entry.properties) {
    final constraints = widgetbookConstraintsFor(property);
    final input = widget.constructorInputs[property.name];
    if (input == null) {
      throw StateError(
        "Widgetbook story for '${widget.entry.name}' cannot bind property "
        "'${property.name}' to its constructor.",
      );
    }
    if (input.positional != property.positional) {
      throw StateError(
        "Widgetbook story for '${widget.entry.name}' has inconsistent "
        "positional metadata for '${property.name}'.",
      );
    }
    if (property.type == PropertyType.event) {
      final callback = _callbackPlan(widget, property, input);
      properties.add(
        WidgetbookStoryEventPropertyPlan._(
          property: property,
          constraints: constraints,
          description: _propertyDescription(
            property,
            seedProvenance: callback.constructorDefault == null
                ? null
                : WidgetbookSeedProvenance.constructorDefault,
          ),
          positional: property.positional,
          callback: callback,
        ),
      );
      continue;
    }
    lowerer.validatePropertyType(
      widget: widget,
      property: property,
      path: '${widget.entry.name}.${property.name}',
    );

    final type = WidgetbookDartTypePlan.fromAnalyzer(
      input.type,
      path: '${widget.entry.name}.${property.name}',
    );
    final choices = _choicePlans(
      property: property,
      dartType: type,
      input: input,
      lowerer: lowerer,
      widget: widget,
    );
    final selected = _selectSeed(
      widget: widget,
      property: property,
      input: input,
      lowerer: lowerer,
      choices: choices.values,
    );
    final description = _propertyDescription(
      property,
      seedProvenance: selected.provenance,
    );
    if (choices.values.isNotEmpty) {
      properties.add(
        WidgetbookStoryChoicePropertyPlan._(
          property: property,
          constraints: constraints,
          dartType: type,
          description: description,
          positional: property.positional,
          seed: selected.value,
          seedProvenance: selected.provenance,
          choices: choices.values,
          choiceLabels: choices.labels,
        ),
      );
      continue;
    }
    final editableControl = _editableControlFor(property);
    properties.add(
      editableControl == null
          ? WidgetbookStoryNativePropertyPlan._(
              property: property,
              constraints: constraints,
              dartType: type,
              description: description,
              positional: property.positional,
              seed: selected.value,
              seedProvenance: selected.provenance,
            )
          : WidgetbookStoryEditablePropertyPlan._(
              property: property,
              constraints: constraints,
              dartType: type,
              description: description,
              positional: property.positional,
              editableControl: editableControl,
              seed: selected.value,
              seedProvenance: selected.provenance,
            ),
    );
  }

  final widgetLocationPrefix =
      '${widget.sourceAsset.path}#${widget.className}.';
  return WidgetbookStoryPlan(
    widget: widget,
    properties: List.unmodifiable(properties),
    exclusions: List.unmodifiable(
      index.exclusions.where(
        (exclusion) =>
            exclusion.widget == widget.className &&
            exclusion.target == WidgetVisitorTarget.widgetbook.name &&
            exclusion.location.startsWith(widgetLocationPrefix),
      ),
    ),
  );
}

typedef _SeedSelection = ({
  WidgetbookNativeValuePlan value,
  WidgetbookSeedProvenance provenance,
});

/// Resolves typed or legacy property constraints to one backend view.
RestageConstraints widgetbookConstraintsFor(PropertyEntry property) {
  final legacy = property.validationRule;
  return legacy == null
      ? property.constraints
      : parseA2uiLegacyConstraint(legacy.expression);
}

_SeedSelection _selectSeed({
  required WidgetbookWidgetSource widget,
  required PropertyEntry property,
  required WidgetConstructorInput input,
  required WidgetbookNativeValuePlanner lowerer,
  required List<WidgetbookNativeValuePlan> choices,
}) {
  final parameterType = input.type;
  final constructorDefault = input.constructorDefault;
  final literal = property.defaultSource;
  if (constructorDefault is! NoWidgetConstructorDefault) {
    final value = _portableConstructorDefault(input, property);
    if (value != null) {
      return (
        value: value,
        provenance: WidgetbookSeedProvenance.constructorDefault,
      );
    }
    if (constructorDefault
        case UnsupportedWidgetConstructorDefault(:final source)) {
      throw StateError(
        'Widgetbook seed at /constructorDefaults/${property.name} cannot '
        'reproduce constructor default $source. Make the Dart default public, '
        'importable, and reconstructable; change the constructor contract '
        '(for example, to a safe nullable input without a non-null default); '
        'use a catalog-facing wrapper; or ignore the optional input where '
        'omission is semantically legal.',
      );
    }
  }

  if (literal is LiteralDefault) {
    final value = lowerer.lowerProperty(
      widget: widget,
      property: property,
      value: literal.value,
      path: '/defaults/${property.name}',
    );
    _validateSeed(property, literal.value, path: '/defaults/${property.name}');
    return (value: value, provenance: WidgetbookSeedProvenance.catalogLiteral);
  }

  if (choices.isNotEmpty) {
    return (
      value: choices.first,
      provenance: WidgetbookSeedProvenance.finiteChoice,
    );
  }

  final preview = _scalarPreview(parameterType, property);
  if (preview != null) {
    return (
      value: lowerer.lowerProperty(
        widget: widget,
        property: property,
        value: preview,
        path: '/preview/${property.name}',
      ),
      provenance: WidgetbookSeedProvenance.scalarPreview,
    );
  }

  final constructorClaimsNonNull = switch (constructorDefault) {
    NoWidgetConstructorDefault() || NullWidgetConstructorDefault() => false,
    LiteralWidgetConstructorDefault() ||
    EnumWidgetConstructorDefault() ||
    StaticMemberWidgetConstructorDefault() ||
    StructuralWidgetConstructorDefault() ||
    UnsupportedWidgetConstructorDefault() =>
      true,
  };
  final runtimeClaimsNonNull = literal is TokenRefDefault ||
      literal is ThemeBindingDefault ||
      property.defaultBrandToken != null ||
      literal is FlutterCtorDefault ||
      constructorClaimsNonNull;
  if (input.nullable && !runtimeClaimsNonNull) {
    return (
      value: WidgetbookNullValuePlan(
        type: WidgetbookDartTypePlan.fromAnalyzer(
          parameterType,
          path: '/defaults/${property.name}',
        ),
      ),
      provenance: WidgetbookSeedProvenance.nullableFallback,
    );
  }

  _validateSynthesizedConstraints(property);

  return (
    value: lowerer.synthesizeProperty(
      widget: widget,
      property: property,
      minimumItems: widgetbookConstraintsFor(property).minItems ?? 0,
      path: '/generated/${property.name}',
    ),
    provenance: WidgetbookSeedProvenance.synthesizedPreview,
  );
}

typedef _ChoicePlans = ({
  List<WidgetbookNativeValuePlan> values,
  List<String> labels,
});

_ChoicePlans _choicePlans({
  required PropertyEntry property,
  required WidgetbookDartTypePlan dartType,
  required WidgetConstructorInput input,
  required WidgetbookNativeValuePlanner lowerer,
  required WidgetbookWidgetSource widget,
}) {
  final allowed = widgetbookConstraintsFor(property).allowedValues;
  if (allowed != null) {
    final choices = <WidgetbookNativeValuePlan>[];
    for (var index = 0; index < allowed.length; index++) {
      final path = '/constraints/${property.name}/enum/$index';
      _validateSeed(property, allowed[index], path: path);
      choices.add(
        lowerer.lowerProperty(
          widget: widget,
          property: property,
          value: allowed[index],
          path: path,
        ),
      );
    }
    return (
      values: choices,
      labels: [for (final value in allowed) '$value'],
    );
  }
  if (property.type != PropertyType.enumValue) {
    return (values: const [], labels: const []);
  }
  final type = input.type;
  final element = type is InterfaceType ? type.element : null;
  if (element is! EnumElement) {
    throw StateError("property '${property.name}' does not resolve to an enum");
  }
  final members = element.fields
      .where((field) => field.isEnumConstant)
      .map((field) => field.name)
      .whereType<String>()
      .toList(growable: false);
  if (members.isEmpty) {
    throw StateError("enum property '${property.name}' has no members");
  }
  return (
    values: [
      for (final member in members)
        WidgetbookEnumValuePlan(type: dartType, member: member),
    ],
    labels: members,
  );
}

void _validateSynthesizedConstraints(PropertyEntry property) {
  final constraints = widgetbookConstraintsFor(property);
  if (constraints.isEmpty) return;

  final isCollection = property.type == PropertyType.widgetList ||
      property.type == PropertyType.stringList ||
      property.type == PropertyType.booleanList ||
      isCustomerStructuredListShape(property.valueShape);
  final collectionOnly = isCollection &&
      constraints.minimum == null &&
      constraints.exclusiveMinimum == null &&
      constraints.maximum == null &&
      constraints.exclusiveMaximum == null &&
      constraints.allowedValues == null &&
      constraints.pattern == null &&
      constraints.minLength == null &&
      constraints.maxLength == null &&
      constraints.extensions.isEmpty;
  if (collectionOnly) {
    final minimumItems = constraints.minItems ?? 0;
    final maximumItems = constraints.maxItems;
    if (minimumItems >= 0 &&
        (maximumItems == null || minimumItems <= maximumItems)) {
      return;
    }
  }

  throw StateError(
    'Widgetbook seed at /generated/${property.name} cannot deterministically '
    'satisfy its constraints. Supply a valid explicit default source or '
    'finite allowed values.',
  );
}

WidgetbookNativeValuePlan? _portableConstructorDefault(
  WidgetConstructorInput input,
  PropertyEntry property,
) {
  final constructorDefault = input.constructorDefault;
  final parameterType = input.type;
  final type = WidgetbookDartTypePlan.fromAnalyzer(
    parameterType,
    path: '/constructorDefaults/${property.name}',
  );
  switch (constructorDefault) {
    case NoWidgetConstructorDefault() || UnsupportedWidgetConstructorDefault():
      return null;
    case StructuralWidgetConstructorDefault(:final value):
      return WidgetbookDartConstValuePlan(type: type, value: value);
    case NullWidgetConstructorDefault():
      if (!input.nullable) return null;
      _validateSeed(
        property,
        null,
        path: '/constructorDefaults/${property.name}',
      );
      return WidgetbookNullValuePlan(type: type);
    case LiteralWidgetConstructorDefault(:final value):
      if (value is double && !value.isFinite) return null;
      _validateSeed(
        property,
        value,
        path: '/constructorDefaults/${property.name}',
      );
      return WidgetbookScalarValuePlan(type: type, value: value);
    case EnumWidgetConstructorDefault(:final member):
      _validateSeed(
        property,
        member,
        path: '/constructorDefaults/${property.name}',
      );
      return WidgetbookEnumValuePlan(type: type, member: member);
    case StaticMemberWidgetConstructorDefault(
        :final libraryUri,
        :final owner,
        :final member,
      ):
      if (!widgetbookConstraintsFor(property).isEmpty) return null;
      return WidgetbookStaticMemberValuePlan(
        type: type,
        libraryUri: libraryUri,
        owner: owner,
        member: member,
      );
  }
}

WidgetbookStoryCallbackPlan _callbackPlan(
  WidgetbookWidgetSource widget,
  PropertyEntry property,
  WidgetConstructorInput input,
) {
  final type = input.type;
  final count = switch (classifyResolvedCallbackShape(type)) {
    ZeroArgumentCallback() => 0,
    SingleValueCallback() => 1,
    UnsupportedCallback(:final reason) => throw StateError(
        "Widgetbook event '${widget.entry.name}.${property.name}' has an "
        'unsupported callback signature ($reason). This is a Restage compiler '
        'capability gap.',
      ),
  };
  final constructorDefault = switch (input.constructorDefault) {
    NoWidgetConstructorDefault() || NullWidgetConstructorDefault() => null,
    StaticMemberWidgetConstructorDefault(
      :final libraryUri,
      :final owner,
      :final member,
    ) =>
      WidgetbookFunctionReferenceValuePlan(
        libraryUri: libraryUri,
        owner: owner,
        member: member,
      ),
    LiteralWidgetConstructorDefault() ||
    EnumWidgetConstructorDefault() ||
    StructuralWidgetConstructorDefault() ||
    UnsupportedWidgetConstructorDefault() =>
      throw StateError(
        'Widgetbook seed at /constructorDefaults/${property.name} cannot '
        'reproduce constructor default '
        '${input.formal.defaultValueCode ?? '<unrepresentable>'}. Make the '
        'Dart default public, importable, and reconstructable; change the '
        'constructor contract; use a catalog-facing wrapper; or ignore the '
        'optional input where omission is semantically legal.',
      ),
  };
  return WidgetbookStoryCallbackPlan(
    nullable: input.nullable,
    parameterCount: count,
    constructorDefault: constructorDefault,
  );
}

WidgetbookStoryEditableControl? _editableControlFor(PropertyEntry property) {
  if (_needsNativeWrapper(property)) return null;
  return switch (property.type) {
    PropertyType.string => WidgetbookStoryEditableControl.string,
    PropertyType.boolean => WidgetbookStoryEditableControl.boolean,
    PropertyType.integer => WidgetbookStoryEditableControl.integer,
    PropertyType.real => WidgetbookStoryEditableControl.real,
    PropertyType.color => WidgetbookStoryEditableControl.color,
    PropertyType.duration => WidgetbookStoryEditableControl.duration,
    PropertyType.edgeInsets ||
    PropertyType.alignment ||
    PropertyType.offset ||
    PropertyType.fontWeight ||
    PropertyType.curve =>
      null,
    PropertyType.widget ||
    PropertyType.widgetList ||
    PropertyType.enumValue ||
    PropertyType.structured ||
    PropertyType.event ||
    PropertyType.length ||
    PropertyType.alignmentXY ||
    PropertyType.stringList ||
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
        "property '${property.name}' has no Widgetbook control",
      ),
  };
}

bool _needsNativeWrapper(PropertyEntry property) =>
    property.type == PropertyType.widget ||
    property.type == PropertyType.widgetList ||
    property.type == PropertyType.structured ||
    isCustomerStructuredListShape(property.valueShape);

Object? _scalarPreview(DartType type, PropertyEntry property) {
  switch (property.type) {
    case PropertyType.string:
      final constraints = widgetbookConstraintsFor(property);
      if (constraints.pattern != null) return null;
      final minimum = constraints.minLength ?? 0;
      final maximum = constraints.maxLength;
      if (maximum != null && maximum < minimum) return null;
      final length = math.max(minimum, 0);
      return length == 0 ? '' : ''.padRight(length, 'x');
    case PropertyType.boolean:
      return false;
    case PropertyType.integer:
      return _numericPreview(property, integral: true);
    case PropertyType.real || PropertyType.length:
      return _numericPreview(property, integral: false);
    case PropertyType.widget ||
          PropertyType.widgetList ||
          PropertyType.color ||
          PropertyType.edgeInsets ||
          PropertyType.alignment ||
          PropertyType.alignmentXY ||
          PropertyType.offset ||
          PropertyType.fontWeight ||
          PropertyType.duration ||
          PropertyType.curve ||
          PropertyType.stringList ||
          PropertyType.booleanList ||
          PropertyType.event ||
          PropertyType.dataReference ||
          PropertyType.enumValue ||
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
          PropertyType.structured ||
          PropertyType.inlineSpan ||
          PropertyType.decorationImage ||
          PropertyType.selectionOptionList ||
          PropertyType.unknown:
      return null;
  }
}

num? _numericPreview(PropertyEntry property, {required bool integral}) {
  final constraints = widgetbookConstraintsFor(property);
  var candidate = integral ? 0 : 0.0;
  if (constraints.minimum case final minimum?) {
    if (candidate < minimum) candidate = minimum;
  }
  if (constraints.exclusiveMinimum case final minimum?) {
    if (candidate <= minimum) {
      candidate = integral ? minimum.floor() + 1 : minimum + 1.0;
    }
  }
  if (constraints.maximum case final maximum?) {
    if (candidate > maximum) candidate = maximum;
  }
  if (constraints.exclusiveMaximum case final maximum?) {
    if (candidate >= maximum) {
      candidate = integral ? maximum.ceil() - 1 : maximum - 1.0;
    }
  }
  if (integral) candidate = candidate.round();
  return _seedSatisfiesConstraints(property, candidate) ? candidate : null;
}

void _validateSeed(
  PropertyEntry property,
  Object? value, {
  required String path,
}) {
  if (!_seedSatisfiesConstraints(property, value)) {
    throw StateError('Widgetbook seed at $path violates its constraints.');
  }
}

bool _seedSatisfiesConstraints(PropertyEntry property, Object? value) {
  final constraints = widgetbookConstraintsFor(property);
  final allowed = constraints.allowedValues;
  if (allowed != null && !allowed.contains(value)) {
    return false;
  }
  if (value is num) {
    if (!value.isFinite ||
        constraints.minimum != null && value < constraints.minimum! ||
        constraints.exclusiveMinimum != null &&
            value <= constraints.exclusiveMinimum! ||
        constraints.maximum != null && value > constraints.maximum! ||
        constraints.exclusiveMaximum != null &&
            value >= constraints.exclusiveMaximum!) {
      return false;
    }
  }
  if (value is String) {
    if (constraints.minLength != null &&
            value.length < constraints.minLength! ||
        constraints.maxLength != null &&
            value.length > constraints.maxLength! ||
        constraints.pattern != null &&
            !RegExp(constraints.pattern!).hasMatch(value)) {
      return false;
    }
  }
  if (value is List) {
    if (constraints.minItems != null && value.length < constraints.minItems! ||
        constraints.maxItems != null && value.length > constraints.maxItems!) {
      return false;
    }
  }
  return true;
}

String _propertyDescription(
  PropertyEntry property, {
  WidgetbookSeedProvenance? seedProvenance,
}) {
  final details = <String>[property.description.trim()];
  final constraints = widgetbookConstraintsFor(property);
  if (constraints.allowedValues case final values?) {
    details.add('Allowed: ${values.join(', ')}.');
  }
  if (constraints.minimum != null || constraints.maximum != null) {
    details.add(
      'Inclusive range: ${constraints.minimum ?? 'unbounded'}–'
      '${constraints.maximum ?? 'unbounded'}.',
    );
  }
  if (constraints.exclusiveMinimum != null ||
      constraints.exclusiveMaximum != null) {
    details.add(
      'Exclusive range: ${constraints.exclusiveMinimum ?? 'unbounded'}–'
      '${constraints.exclusiveMaximum ?? 'unbounded'}.',
    );
  }
  if (constraints.minLength != null || constraints.maxLength != null) {
    details.add(
      'Length: ${constraints.minLength ?? 0}–'
      '${constraints.maxLength ?? 'unbounded'}.',
    );
  }
  if (constraints.pattern case final pattern?) {
    details.add('Pattern: $pattern.');
  }
  if (constraints.minItems != null || constraints.maxItems != null) {
    details.add(
      'Items: ${constraints.minItems ?? 0}–'
      '${constraints.maxItems ?? 'unbounded'}.',
    );
  }
  final source = property.defaultSource;
  if (seedProvenance == WidgetbookSeedProvenance.constructorDefault) {
    details.add("Default: the widget constructor's Dart default.");
  } else {
    switch (source) {
      case TokenRefDefault():
        details.add('Default: resolved from a design token at runtime.');
      case ThemeBindingDefault():
        details.add('Default: resolved from the Flutter theme at runtime.');
      case FlutterCtorDefault():
        details.add("Default: the widget constructor's Flutter default.");
      case LiteralDefault(:final value):
        details.add(_sentence('Default: $value'));
      case null:
        if (property.defaultBrandToken != null) {
          details.add('Default: resolved from a brand token at runtime.');
        }
    }
  }
  return details.where((part) => part.isNotEmpty).join(' ');
}

String _sentence(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || RegExp(r'[.!?]$').hasMatch(trimmed)) return trimmed;
  return '$trimmed.';
}
