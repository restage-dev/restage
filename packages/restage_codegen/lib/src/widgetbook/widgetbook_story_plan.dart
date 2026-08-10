import 'dart:math' as math;

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/a2ui/a2ui_legacy_constraint_parser.dart';
import 'package:restage_codegen/src/callback_shape.dart';
import 'package:restage_codegen/src/customer_structured_admissibility.dart';
import 'package:restage_codegen/src/dart_import_planner.dart';
import 'package:restage_codegen/src/enum_constant_identity.dart';
import 'package:restage_codegen/src/target_config_reader.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';
import 'package:restage_codegen/src/widget_visitor.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_catalog_source_index.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_native_value_plan.dart';
import 'package:restage_codegen/src/widgetbook/widgetbook_property_capability.dart';
import 'package:rfw_catalog_schema/constraint_validation.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:rfw_catalog_schema/widgetbook.dart' show StoryExpansion;

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
        ),
        assert(
          _choiceValueIndex(choices, seed) >= 0,
          'a choice property seed must belong to its choice domain',
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

  /// Returns the structural typed index of [value] in [choices].
  ///
  /// Planning assertions, finite-domain deduplication, and source rendering
  /// all use this identity seam. Rendered Dart source is deliberately not an
  /// equality representation.
  int choiceIndexOf(WidgetbookNativeValuePlan value) {
    final index = _choiceValueIndex(choices, value);
    if (index < 0) {
      throw StateError(
        "Widgetbook value for '${property.name}' is not one of its finite "
        'choices.',
      );
    }
    return index;
  }
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

/// Count limits applied before story tuples are materialized.
final class WidgetbookStoryLimitPolicy {
  /// Creates a valid package-default and absolute limit pair.
  const WidgetbookStoryLimitPolicy({
    required this.defaultLimit,
    required this.absoluteLimit,
  })  : assert(defaultLimit > 0, 'the default story limit must be positive'),
        assert(
          absoluteLimit >= defaultLimit,
          'the absolute story limit must cover the default limit',
        );

  /// Limit used when a widget does not declare `maxStories`.
  final int defaultLimit;

  /// Largest per-widget limit an annotation may request.
  final int absoluteLimit;
}

const _widgetbookStoryLimits = WidgetbookStoryLimitPolicy(
  defaultLimit: 32,
  absoluteLimit: 256,
);

/// One typed finite value on a configured story axis.
final class WidgetbookStoryAxisValuePlan {
  /// Creates a typed axis value.
  const WidgetbookStoryAxisValuePlan({
    required this.value,
    required this.identity,
    required this.nameFragment,
  });

  /// Native Dart value supplied to the generated story.
  final WidgetbookNativeValuePlan value;

  /// Exact typed identity used for ordering and deduplication.
  final String identity;

  /// Deterministic Dart-identifier fragment used in story names.
  final String nameFragment;
}

/// One configured finite property axis.
final class WidgetbookStoryAxisPlan {
  /// Creates a property axis whose first value is the selected default.
  WidgetbookStoryAxisPlan({
    required this.property,
    required List<WidgetbookStoryAxisValuePlan> values,
  }) : values = List.unmodifiable(values);

  /// Source property in catalog declaration order.
  final WidgetbookStoryPropertyPlan property;

  /// Default-first, typed-deduplicated finite values.
  final List<WidgetbookStoryAxisValuePlan> values;
}

/// One generated story tuple.
final class WidgetbookStoryVariantPlan {
  /// Creates a named tuple.
  WidgetbookStoryVariantPlan({
    required this.name,
    required Map<String, WidgetbookStoryAxisValuePlan> valuesByProperty,
  }) : valuesByProperty = Map.unmodifiable(valuesByProperty);

  /// Semantic generated name (`Default` for the all-default tuple).
  final String name;

  /// Axis values keyed by exact source property name.
  final Map<String, WidgetbookStoryAxisValuePlan> valuesByProperty;

  /// Whether this is the stable all-default story.
  bool get isDefault => name == 'Default';
}

/// Complete backend plan consumed by the Widgetbook story source renderer.
final class WidgetbookStoryPlan {
  /// Creates a story plan.
  const WidgetbookStoryPlan({
    required this.widget,
    required this.properties,
    required this.exclusions,
    required this.axes,
    required this.variants,
  });

  /// Customer widget source facts.
  final WidgetbookWidgetSource widget;

  /// Properties in catalog/source order.
  final List<WidgetbookStoryPropertyPlan> properties;

  /// Constructor inputs omitted from this target's generated story.
  final List<PropertyExclusion> exclusions;

  /// Configured finite axes in source property order.
  final List<WidgetbookStoryAxisPlan> axes;

  /// Materialized story tuples in deterministic output order.
  final List<WidgetbookStoryVariantPlan> variants;

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
    for (final axis in axes) {
      for (final axisValue in axis.values) {
        yield axisValue.value;
      }
    }
  }
}

/// Builds a total, seed-resolved story plan for one customer widget.
WidgetbookStoryPlan planWidgetbookStory({
  required WidgetbookCatalogSourceIndex index,
  required WidgetbookWidgetSource widget,
  WidgetbookStoryLimitPolicy storyLimits = _widgetbookStoryLimits,
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
    final constraints = widgetbookConstraintsFor(
      property,
      path: '${widget.entry.name}.${property.name}',
    );
    validateWidgetbookConstraintApplicability(
      property,
      constraints,
      path: '${widget.entry.name}.${property.name}',
    );
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
    final initialChoices = _choicePlans(
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
      choices: initialChoices.values,
    );
    final seed = initialChoices.values.isEmpty
        ? selected.value
        : _canonicalFiniteChoiceSeed(
            seed: selected.value,
            provenance: selected.provenance,
            choices: initialChoices.values,
            widget: widget,
            property: property,
            input: input,
            lowerer: lowerer,
          );
    final choices = initialChoices.values.isEmpty
        ? initialChoices
        : _choicePlansIncludingSeed(
            initialChoices,
            seed,
            allowWiden: constraints.allowedValues == null,
            seedPath: _finiteSeedPath(
              selected.provenance,
              property,
            ),
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
          seed: seed,
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
              seed: seed,
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
  final axes = _planStoryAxes(widget, properties);
  final variants = _planStoryVariants(
    widget: widget,
    axes: axes,
    storyLimits: storyLimits,
  );
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
    axes: List.unmodifiable(axes),
    variants: List.unmodifiable(variants),
  );
}

List<WidgetbookStoryAxisPlan> _planStoryAxes(
  WidgetbookWidgetSource widget,
  List<WidgetbookStoryPropertyPlan> properties,
) {
  final configured = widget.targetConfig.properties;
  if (configured.isEmpty) return const [];
  final propertiesByName = {
    for (final property in properties) property.property.name: property,
  };
  final axes = <WidgetbookStoryAxisPlan>[];
  for (final property in properties) {
    final name = property.property.name;
    final config = configured[name];
    if (config == null) continue;
    if (property is WidgetbookStoryEventPropertyPlan) {
      throw StateError(
        'Widgetbook story config at ${_propertyConfigLocation(config)} cannot '
        "turn callback property '$name' into a story axis. Callbacks are never "
        'story axes.',
      );
    }
    final input = widget.constructorInputs[name];
    if (input == null) {
      throw StateError(
        "Widgetbook story config for '${widget.entry.name}.$name' does not "
        'resolve to an unnamed-constructor property.',
      );
    }
    _validateAxisPropertyFamily(
      input,
      config,
      location: _propertyConfigLocation(config),
    );
    final seed = _propertySeed(property);
    final defaultValue = seed is WidgetbookStaticMemberValuePlan
        ? _axisValueFromStaticConstructorDefault(
            property,
            input,
            path: '${widget.entry.name}.$name/default',
          )
        : _axisValueFromNative(
            property,
            seed,
            path: '${widget.entry.name}.$name/default',
          );
    final selected = config.allValues
        ? _allAxisValues(property, input)
        : [
            for (final value in config.storyValues ?? const <DartObject>[])
              _axisValueFromDartObject(
                property,
                input,
                value,
                path: config.storyValuesLocation ??
                    '${widget.sourceAsset.path}#${widget.className}.$name',
              ),
          ];
    final values = <WidgetbookStoryAxisValuePlan>[defaultValue];
    final identities = <String>{defaultValue.identity};
    for (final value in selected) {
      if (identities.add(value.identity)) values.add(value);
    }
    axes.add(WidgetbookStoryAxisPlan(property: property, values: values));
  }
  final unresolved = configured.keys
      .where((name) => !propertiesByName.containsKey(name))
      .toList(growable: false);
  if (unresolved.isNotEmpty) {
    throw StateError(
      'Widgetbook story config for ${widget.entry.name} names property '
      '${unresolved.join(', ')} that is not an admitted constructor input.',
    );
  }
  return axes;
}

void _validateAxisPropertyFamily(
  WidgetConstructorInput input,
  WidgetbookPropertyTargetConfigFacts config, {
  required String location,
}) {
  final type = input.type;
  final element = type is InterfaceType ? type.element : null;
  final isBool =
      element?.library.identifier == 'dart:core' && element?.name == 'bool';
  if (isBool || element is EnumElement) return;
  final selector = config.allValues ? 'allValues' : 'storyValues';
  final acceptedSet = config.allValues
      ? 'allValues supports only exact bool and enum properties.'
      : 'storyValues supports only the exact bool/enum/null accepted set.';
  throw StateError(
    'Widgetbook story config at $location uses $selector on '
    '`${type.getDisplayString()}`. $acceptedSet',
  );
}

String _propertyConfigLocation(WidgetbookPropertyTargetConfigFacts config) =>
    config.storyValuesLocation ?? config.allValuesLocation ?? '<unknown>';

WidgetbookNativeValuePlan _propertySeed(
  WidgetbookStoryPropertyPlan property,
) =>
    switch (property) {
      WidgetbookStoryEditablePropertyPlan(:final seed) ||
      WidgetbookStoryChoicePropertyPlan(:final seed) ||
      WidgetbookStoryNativePropertyPlan(:final seed) =>
        seed,
      WidgetbookStoryEventPropertyPlan() => throw StateError(
          "callback property '${property.property.name}' has no data seed",
        ),
    };

WidgetbookStoryAxisValuePlan _axisValueFromNative(
  WidgetbookStoryPropertyPlan property,
  WidgetbookNativeValuePlan value, {
  required String path,
}) {
  return switch (value) {
    WidgetbookNullValuePlan() => WidgetbookStoryAxisValuePlan(
        value: value,
        identity: '${_typeIdentity(value.type)}:null',
        nameFragment: 'Null',
      ),
    WidgetbookScalarValuePlan(value: final bool scalar) =>
      WidgetbookStoryAxisValuePlan(
        value: value,
        identity: 'dart:core#bool:$scalar',
        nameFragment: scalar ? 'True' : 'False',
      ),
    WidgetbookEnumValuePlan(:final type, :final member, :final ordinal) =>
      WidgetbookStoryAxisValuePlan(
        value: value,
        identity: '${_typeIdentity(type)}:$member@$ordinal',
        nameFragment: _nameFragment(member, path: path),
      ),
    _ => throw StateError(
        'Widgetbook story axis at $path has a default outside the exact '
        'bool/enum/null accepted set for `${property.dartType.symbol}`.',
      ),
  };
}

WidgetbookStoryAxisValuePlan _axisValueFromStaticConstructorDefault(
  WidgetbookStoryPropertyPlan property,
  WidgetConstructorInput input, {
  required String path,
}) {
  final value = input.formal.computeConstantValue();
  if (value == null) {
    throw StateError(
      'Widgetbook story axis at $path could not evaluate its public const '
      'constructor default.',
    );
  }
  return _axisValueFromDartObject(
    property,
    input,
    value,
    path: path,
  );
}

List<WidgetbookStoryAxisValuePlan> _allAxisValues(
  WidgetbookStoryPropertyPlan property,
  WidgetConstructorInput input,
) {
  final path = '${input.field.library.identifier}#'
      '${input.field.enclosingElement.name}.${input.name}';
  final type = input.type;
  final element = type is InterfaceType ? type.element : null;
  final values = <WidgetbookStoryAxisValuePlan>[];
  if (element?.library.identifier == 'dart:core' && element?.name == 'bool') {
    for (final value in const [false, true]) {
      _validateSeed(property.property, value, path: path);
      values.add(
        WidgetbookStoryAxisValuePlan(
          value: WidgetbookScalarValuePlan(
            type: property.dartType,
            value: value,
          ),
          identity: 'dart:core#bool:$value',
          nameFragment: value ? 'True' : 'False',
        ),
      );
    }
  } else if (element is EnumElement) {
    for (final (ordinal, constant) in element.constants.indexed) {
      final member = constant.name;
      if (member == null) continue;
      _validateSeed(property.property, member, path: path);
      values.add(
        WidgetbookStoryAxisValuePlan(
          value: WidgetbookEnumValuePlan(
            type: property.dartType,
            member: member,
            ordinal: ordinal,
          ),
          identity: '${_typeIdentity(property.dartType)}:$member@$ordinal',
          nameFragment: _nameFragment(member, path: path),
        ),
      );
    }
  } else {
    throw StateError(
      'Widgetbook story config at $path uses allValues on '
      '`${type.getDisplayString()}`. allValues supports only exact bool and '
      'enum properties.',
    );
  }
  if (input.nullable) {
    _validateSeed(property.property, null, path: path);
    values.add(
      WidgetbookStoryAxisValuePlan(
        value: WidgetbookNullValuePlan(type: property.dartType),
        identity: '${_typeIdentity(property.dartType)}:null',
        nameFragment: 'Null',
      ),
    );
  }
  return values;
}

WidgetbookStoryAxisValuePlan _axisValueFromDartObject(
  WidgetbookStoryPropertyPlan property,
  WidgetConstructorInput input,
  DartObject value, {
  required String path,
}) {
  if (value.isNull) {
    if (!input.nullable) {
      throw StateError(
        'Widgetbook story config at $path selects null for non-nullable '
        "property '${input.name}'.",
      );
    }
    _validateSeed(property.property, null, path: path);
    return WidgetbookStoryAxisValuePlan(
      value: WidgetbookNullValuePlan(type: property.dartType),
      identity: '${_typeIdentity(property.dartType)}:null',
      nameFragment: 'Null',
    );
  }

  final expectedType = input.type;
  final expectedElement =
      expectedType is InterfaceType ? expectedType.element : null;
  final boolValue = value.toBoolValue();
  if (expectedElement?.library.identifier == 'dart:core' &&
      expectedElement?.name == 'bool' &&
      boolValue != null) {
    _validateSeed(property.property, boolValue, path: path);
    return WidgetbookStoryAxisValuePlan(
      value: WidgetbookScalarValuePlan(
        type: property.dartType,
        value: boolValue,
      ),
      identity: 'dart:core#bool:$boolValue',
      nameFragment: boolValue ? 'True' : 'False',
    );
  }

  final canonical = expectedElement is EnumElement
      ? canonicalAnalyzerEnumConstant(value, expectedElement)
      : null;
  if (canonical != null) {
    final identity = canonical.identity;
    _validateSeed(property.property, identity.member, path: path);
    return WidgetbookStoryAxisValuePlan(
      value: WidgetbookEnumValuePlan(
        type: property.dartType,
        member: identity.member,
        ordinal: identity.ordinal,
      ),
      identity: '${identity.definingLibrary}#${identity.enumName}:'
          '${identity.member}@${identity.ordinal}',
      nameFragment: _nameFragment(identity.member, path: path),
    );
  }

  throw StateError(
    'Widgetbook story config at $path has a value outside the exact accepted '
    "set for '${input.name}'. Use bool literals, members of the property's "
    'resolved enum type, and null only when nullable.',
  );
}

String _typeIdentity(WidgetbookDartTypePlan type) =>
    '${type.libraryUri}#${type.symbol}';

List<WidgetbookStoryVariantPlan> _planStoryVariants({
  required WidgetbookWidgetSource widget,
  required List<WidgetbookStoryAxisPlan> axes,
  required WidgetbookStoryLimitPolicy storyLimits,
}) {
  final configuredLimit = widget.targetConfig.maxStories;
  if (axes.isEmpty && configuredLimit == null) {
    return [
      WidgetbookStoryVariantPlan(
        name: 'Default',
        valuesByProperty: const {},
      ),
    ];
  }
  final limitContext = _storyLimitContext(
    axes: axes,
    configuredLimit: configuredLimit,
    storyLimits: storyLimits,
  );
  if (configuredLimit != null && configuredLimit <= 0) {
    throw StateError(
      'Widgetbook maxStories for ${widget.entry.name} must be greater than '
      'zero; received $configuredLimit. $limitContext Remove maxStories to '
      'use the package default, or set it from 1 through '
      '${storyLimits.absoluteLimit}.',
    );
  }
  if (configuredLimit != null && configuredLimit > storyLimits.absoluteLimit) {
    throw StateError(
      'Widgetbook maxStories for ${widget.entry.name} is $configuredLimit, '
      'above the absolute ceiling ${storyLimits.absoluteLimit}. $limitContext '
      'Use independent expansion, select fewer values, or set maxStories no '
      'higher than ${storyLimits.absoluteLimit}.',
    );
  }
  final expansion = widget.targetConfig.expansion ?? StoryExpansion.independent;
  final count = switch (expansion) {
    StoryExpansion.independent => 1 +
        axes.fold<int>(
          0,
          (total, axis) => total + math.max(0, axis.values.length - 1),
        ),
    StoryExpansion.cartesian => axes.fold<int>(
        1,
        (total, axis) => total * axis.values.length,
      ),
  };
  final effectiveLimit = configuredLimit ?? storyLimits.defaultLimit;
  if (count > effectiveLimit) {
    throw StateError(
      'Widgetbook story count for ${widget.entry.name} is $count '
      'and exceeds its effective limit $effectiveLimit. $limitContext Use '
      'independent expansion, select fewer values, or deliberately raise '
      'maxStories within the absolute ceiling ${storyLimits.absoluteLimit}.',
    );
  }

  final defaults = {
    for (final axis in axes) axis.property.property.name: axis.values.first,
  };
  final tuples = <Map<String, WidgetbookStoryAxisValuePlan>>[];
  switch (expansion) {
    case StoryExpansion.independent:
      tuples.add(defaults);
      for (final axis in axes) {
        final propertyName = axis.property.property.name;
        for (final value in axis.values.skip(1)) {
          tuples.add({...defaults, propertyName: value});
        }
      }
    case StoryExpansion.cartesian:
      final selectedIndexes = List<int>.filled(axes.length, 0);
      for (var tupleIndex = 0; tupleIndex < count; tupleIndex++) {
        var remainder = tupleIndex;
        for (var axisIndex = axes.length - 1; axisIndex >= 0; axisIndex--) {
          final cardinality = axes[axisIndex].values.length;
          selectedIndexes[axisIndex] = remainder % cardinality;
          remainder ~/= cardinality;
        }
        tuples.add(
          Map.unmodifiable({
            for (var axisIndex = 0; axisIndex < axes.length; axisIndex++)
              axes[axisIndex].property.property.name:
                  axes[axisIndex].values[selectedIndexes[axisIndex]],
          }),
        );
      }
  }

  final variants = <WidgetbookStoryVariantPlan>[];
  final names = <String, String>{};
  final declarations = <String, String>{};
  for (final tuple in tuples) {
    final name = _storyName(axes, tuple);
    final signature = axes
        .map(
          (axis) => '${axis.property.property.name}='
              '${tuple[axis.property.property.name]!.identity}',
        )
        .join(', ');
    final prior = names[name];
    if (prior != null && prior != signature) {
      throw StateError(
        "Widgetbook story name '$name' collides after normalization for "
        'tuples [$prior] and [$signature]. Rename a property or enum member.',
      );
    }
    names[name] = signature;
    final declaration = variants.isEmpty ? r'$RestageCatalog' : '\$$name';
    final priorDeclaration = declarations[declaration];
    if (priorDeclaration != null && priorDeclaration != signature) {
      throw StateError(
        "Widgetbook story declaration '$declaration' collides after "
        'normalization for tuples [$priorDeclaration] and [$signature]. '
        'Rename a property or enum member.',
      );
    }
    declarations[declaration] = signature;
    variants.add(
      WidgetbookStoryVariantPlan(
        name: name,
        valuesByProperty: tuple,
      ),
    );
  }
  return variants;
}

String _storyLimitContext({
  required List<WidgetbookStoryAxisPlan> axes,
  required int? configuredLimit,
  required WidgetbookStoryLimitPolicy storyLimits,
}) {
  final effectiveLimit = configuredLimit ?? storyLimits.defaultLimit;
  final limitSource =
      configuredLimit == null ? 'package default' : 'configured maxStories';
  final cardinalities = axes.isEmpty
      ? 'none'
      : axes
          .map(
            (axis) => '${axis.property.property.name}=${axis.values.length}',
          )
          .join(', ');
  return 'Effective limit: $effectiveLimit ($limitSource); package default: '
      '${storyLimits.defaultLimit}; absolute ceiling: '
      '${storyLimits.absoluteLimit}; axes/cardinalities: $cardinalities.';
}

String _storyName(
  List<WidgetbookStoryAxisPlan> axes,
  Map<String, WidgetbookStoryAxisValuePlan> tuple,
) {
  final out = StringBuffer();
  for (final axis in axes) {
    final propertyName = axis.property.property.name;
    final value = tuple[propertyName]!;
    if (value.identity == axis.values.first.identity) continue;
    out
      ..write(_nameFragment(propertyName, path: propertyName))
      ..write(value.nameFragment);
  }
  return out.isEmpty ? 'Default' : out.toString();
}

String _nameFragment(String value, {required String path}) {
  final words = value.split(RegExp(r'[_$]+')).where((word) => word.isNotEmpty);
  final fragment = words
      .map(
        (word) => word.length == 1
            ? word.toUpperCase()
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join();
  if (fragment.isEmpty ||
      !RegExp(r'^[A-Za-z][A-Za-z0-9]*$').hasMatch(fragment)) {
    throw StateError(
      "Widgetbook story name source '$value' at $path cannot be normalized "
      'to a stable Dart identifier fragment.',
    );
  }
  return fragment;
}

typedef _SeedSelection = ({
  WidgetbookNativeValuePlan value,
  WidgetbookSeedProvenance provenance,
});

/// Resolves typed or legacy property constraints to one backend view.
RestageConstraints widgetbookConstraintsFor(
  PropertyEntry property, {
  String? path,
}) {
  final legacy = property.validationRule;
  if (legacy == null) return property.constraints;
  try {
    return parseA2uiLegacyConstraint(legacy.expression);
  } on A2uiLegacyConstraintParseException catch (error) {
    throw StateError(
      'Widgetbook validation rule at ${path ?? property.name}: authored '
      'expression "${legacy.expression}" is invalid (${error.detail}). '
      'Supported legacy forms are '
      'range(<finite JSON number>, <finite JSON number>), '
      'oneOf(<JSON scalar>, ...), and matches(<JSON string>).',
    );
  }
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
    final value = _portableConstructorDefault(
      input,
      property,
      hasFiniteChoices: choices.isNotEmpty,
    );
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
    if (choices.isNotEmpty) {
      throw StateError(
        'Widgetbook seed at /constructorDefaults/${property.name} cannot be '
        'reduced losslessly to the native transport for its finite choice '
        'domain. Change the constructor default, finite allowed values, or '
        'catalog-facing wrapper.',
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
    _validateSeed(
      property,
      literal.value,
      path: '/defaults/${property.name}',
      validateAllowedValues: choices.isEmpty,
    );
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

_ChoicePlans _choicePlansIncludingSeed(
  _ChoicePlans choices,
  WidgetbookNativeValuePlan seed, {
  required bool allowWiden,
  required String seedPath,
}) {
  if (_choiceValueIndex(choices.values, seed) >= 0) return choices;
  if (!allowWiden) {
    throw StateError(
      'Widgetbook seed at $seedPath violates its finite allowed-value '
      'constraints.',
    );
  }
  return (
    values: [...choices.values, seed],
    labels: [...choices.labels, _choiceSeedLabel(seed)],
  );
}

WidgetbookNativeValuePlan _canonicalFiniteChoiceSeed({
  required WidgetbookNativeValuePlan seed,
  required WidgetbookSeedProvenance provenance,
  required List<WidgetbookNativeValuePlan> choices,
  required WidgetbookWidgetSource widget,
  required PropertyEntry property,
  required WidgetConstructorInput input,
  required WidgetbookNativeValuePlanner lowerer,
}) {
  final path = _finiteSeedPath(provenance, property);
  var value = seed;
  if (provenance == WidgetbookSeedProvenance.constructorDefault) {
    final canonical = _finiteConstructorDefaultValue(input, property);
    if (!canonical.available) {
      throw StateError(
        'Widgetbook seed at $path cannot be reduced losslessly to the native '
        'transport for its finite choice domain. Change the constructor '
        'default, finite allowed values, or catalog-facing wrapper.',
      );
    }
    value = lowerer.lowerProperty(
      widget: widget,
      property: property,
      value: canonical.value,
      path: path,
    );
  }
  final choiceIndex = _choiceValueIndex(choices, value);
  if (choiceIndex >= 0) return choices[choiceIndex];
  if (widgetbookConstraintsFor(property).allowedValues != null) {
    throw StateError(
      'Widgetbook seed at $path violates its finite allowed-value '
      'constraints.',
    );
  }
  return value;
}

String _finiteSeedPath(
  WidgetbookSeedProvenance provenance,
  PropertyEntry property,
) =>
    switch (provenance) {
      WidgetbookSeedProvenance.catalogLiteral => '/defaults/${property.name}',
      WidgetbookSeedProvenance.constructorDefault =>
        '/constructorDefaults/${property.name}',
      WidgetbookSeedProvenance.finiteChoice =>
        widgetbookConstraintsFor(property).allowedValues == null
            ? '/generated/${property.name}'
            : '/constraints/${property.name}/enum/0',
      WidgetbookSeedProvenance.scalarPreview => '/preview/${property.name}',
      WidgetbookSeedProvenance.nullableFallback => '/defaults/${property.name}',
      WidgetbookSeedProvenance.synthesizedPreview =>
        '/generated/${property.name}',
    };

int _choiceValueIndex(
  List<WidgetbookNativeValuePlan> choices,
  WidgetbookNativeValuePlan value,
) =>
    choices.indexWhere((choice) => _sameChoiceValue(choice, value));

bool _sameChoiceValue(
  WidgetbookNativeValuePlan left,
  WidgetbookNativeValuePlan right,
) {
  if (!_sameChoiceType(left.type, right.type)) return false;
  return switch ((left, right)) {
    (WidgetbookNullValuePlan(), WidgetbookNullValuePlan()) => true,
    (
      WidgetbookScalarValuePlan(value: final leftValue),
      WidgetbookScalarValuePlan(value: final rightValue),
    ) =>
      _sameScalarChoiceValue(left.type, leftValue, rightValue),
    (
      WidgetbookEnumValuePlan(
        member: final leftMember,
        ordinal: final leftOrdinal,
      ),
      WidgetbookEnumValuePlan(
        member: final rightMember,
        ordinal: final rightOrdinal,
      ),
    ) =>
      leftMember == rightMember && leftOrdinal == rightOrdinal,
    (
      WidgetbookStaticMemberValuePlan(
        libraryUri: final leftLibrary,
        owner: final leftOwner,
        member: final leftMember,
      ),
      WidgetbookStaticMemberValuePlan(
        libraryUri: final rightLibrary,
        owner: final rightOwner,
        member: final rightMember,
      ),
    ) =>
      leftLibrary == rightLibrary &&
          leftOwner == rightOwner &&
          leftMember == rightMember,
    (
      WidgetbookDartConstValuePlan(value: final leftValue),
      WidgetbookDartConstValuePlan(value: final rightValue),
    ) =>
      leftValue == rightValue,
    (
      WidgetbookFrameworkValuePlan(
        kind: final leftKind,
        value: final leftValue,
      ),
      WidgetbookFrameworkValuePlan(
        kind: final rightKind,
        value: final rightValue,
      ),
    ) =>
      leftKind == rightKind &&
          _frameworkChoiceIdentity(leftKind, leftValue) ==
              _frameworkChoiceIdentity(rightKind, rightValue),
    _ => identical(left, right),
  };
}

bool _sameScalarChoiceValue(
  WidgetbookDartTypePlan type,
  Object left,
  Object right,
) {
  final signedReal = type.libraryUri == 'dart:core' &&
      (type.symbol == 'double' || type.symbol == 'num');
  if (signedReal && left is num && right is num && left == 0 && right == 0) {
    return left.isNegative == right.isNegative;
  }
  return left == right;
}

Object _frameworkChoiceIdentity(
  WidgetbookFrameworkLiteralKind kind,
  Object value,
) =>
    switch (kind) {
      WidgetbookFrameworkLiteralKind.color => _colorChoiceIdentity(value),
      WidgetbookFrameworkLiteralKind.fontWeight =>
        _fontWeightChoiceIdentity(value),
      WidgetbookFrameworkLiteralKind.duration => value,
      WidgetbookFrameworkLiteralKind.edgeInsets ||
      WidgetbookFrameworkLiteralKind.alignment ||
      WidgetbookFrameworkLiteralKind.offset ||
      WidgetbookFrameworkLiteralKind.curve =>
        value,
    };

int _colorChoiceIdentity(Object value) {
  if (value is int) return value;
  final text = (value as String).trim();
  final digits = text.startsWith('#')
      ? text.substring(1)
      : text.toLowerCase().startsWith('0x')
          ? text.substring(2)
          : text;
  return int.parse(digits.length == 6 ? 'FF$digits' : digits, radix: 16);
}

int _fontWeightChoiceIdentity(Object value) {
  if (value is int) return value;
  return switch (value as String) {
    'normal' => 400,
    'bold' => 700,
    final member => int.parse(member.substring(1)),
  };
}

bool _sameChoiceType(
  WidgetbookDartTypePlan left,
  WidgetbookDartTypePlan right,
) {
  if (left.libraryUri != right.libraryUri ||
      left.symbol != right.symbol ||
      left.nullable != right.nullable ||
      left.typeArguments.length != right.typeArguments.length) {
    return false;
  }
  for (var index = 0; index < left.typeArguments.length; index++) {
    if (!_sameChoiceType(
      left.typeArguments[index],
      right.typeArguments[index],
    )) {
      return false;
    }
  }
  return true;
}

String _choiceSeedLabel(WidgetbookNativeValuePlan seed) => switch (seed) {
      WidgetbookNullValuePlan() => 'null',
      WidgetbookScalarValuePlan(:final value) => '$value',
      WidgetbookEnumValuePlan(:final member) => member,
      WidgetbookStaticMemberValuePlan(:final member) => member,
      WidgetbookFrameworkValuePlan(:final value) => '$value',
      WidgetbookDartConstValuePlan() ||
      WidgetbookListValuePlan() ||
      WidgetbookPlaceholderWidgetValuePlan() ||
      WidgetbookConstructorValuePlan() =>
        'default',
    };

_ChoicePlans _choicePlans({
  required PropertyEntry property,
  required WidgetbookDartTypePlan dartType,
  required WidgetConstructorInput input,
  required WidgetbookNativeValuePlanner lowerer,
  required WidgetbookWidgetSource widget,
}) {
  final inputType = input.type;
  final enumElement = inputType is InterfaceType ? inputType.element : null;
  if (property.type == PropertyType.enumValue) {
    if (enumElement is! EnumElement) {
      throw StateError(
        "property '${property.name}' does not resolve to an enum",
      );
    }
    _validateImportableEnumType(
      enumElement,
      path: '${widget.entry.name}.${property.name}',
    );
  }
  final allowed = widgetbookConstraintsFor(property).allowedValues;
  if (allowed != null) {
    final choices = <WidgetbookNativeValuePlan>[];
    final labels = <String>[];
    for (var index = 0; index < allowed.length; index++) {
      final path = '/constraints/${property.name}/enum/$index';
      _validateSeed(property, allowed[index], path: path);
      final choice = lowerer.lowerProperty(
        widget: widget,
        property: property,
        value: allowed[index],
        path: path,
      );
      if (_choiceValueIndex(choices, choice) >= 0) continue;
      choices.add(choice);
      labels.add('${allowed[index]}');
    }
    return (values: choices, labels: labels);
  }
  if (property.type != PropertyType.enumValue) {
    return (values: const [], labels: const []);
  }
  if (enumElement is! EnumElement) {
    throw StateError(
      "property '${property.name}' does not resolve to an enum",
    );
  }
  final constants = [
    for (final (ordinal, field) in enumElement.constants.indexed)
      if (field.name case final member?)
        if (_seedSatisfiesConstraints(property, member))
          (member: member, ordinal: ordinal),
  ];
  if (constants.isEmpty) {
    throw StateError(
      "enum property '${property.name}' has no members that satisfy its "
      'constraints',
    );
  }
  final includeNullChoice = input.nullable &&
      widget.targetConfig.properties.containsKey(property.name);
  return (
    values: [
      for (final constant in constants)
        WidgetbookEnumValuePlan(
          type: dartType,
          member: constant.member,
          ordinal: constant.ordinal,
        ),
      if (includeNullChoice) WidgetbookNullValuePlan(type: dartType),
    ],
    labels: [
      for (final constant in constants) constant.member,
      if (includeNullChoice) 'null',
    ],
  );
}

void _validateImportableEnumType(
  EnumElement element, {
  required String path,
}) {
  final library = element.library.identifier;
  final name = element.name;
  var importable = name != null && isPublicDartTypeIdentity(library, name);
  if (importable) {
    try {
      publicDartImportUri(library);
      // The resolver reports malformed or unmapped source identities as an
      // Error; translate that failure to this customer property path.
      // ignore: avoid_catching_errors
    } on StateError {
      importable = false;
    }
  }
  if (importable) return;
  throw StateError(
    'Widgetbook enum property at $path has type '
    '`${library.isEmpty ? '<unknown>' : library}#${name ?? '<unnamed>'}` '
    'that cannot be named from generated Widgetbook source. Expose a public '
    'enum type from an importable library or use a catalog-facing wrapper.',
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
  PropertyEntry property, {
  required bool hasFiniteChoices,
}) {
  final constructorDefault = input.constructorDefault;
  final parameterType = input.type;
  final type = WidgetbookDartTypePlan.fromAnalyzer(
    parameterType,
    path: '/constructorDefaults/${property.name}',
  );
  WidgetbookNativeValuePlan? plan;
  if (property.type == PropertyType.enumValue &&
      constructorDefault is! NoWidgetConstructorDefault) {
    final canonical = _canonicalEnumConstructorDefault(input);
    if (canonical != null) {
      plan = WidgetbookEnumValuePlan(
        type: type,
        member: canonical.identity.member,
        ordinal: canonical.identity.ordinal,
      );
    }
  }
  plan ??= switch (constructorDefault) {
    NoWidgetConstructorDefault() ||
    UnsupportedWidgetConstructorDefault() =>
      null,
    StructuralWidgetConstructorDefault(:final value) =>
      WidgetbookDartConstValuePlan(type: type, value: value),
    NullWidgetConstructorDefault() =>
      input.nullable ? WidgetbookNullValuePlan(type: type) : null,
    LiteralWidgetConstructorDefault(:final value) =>
      value is double && !value.isFinite
          ? null
          : WidgetbookScalarValuePlan(type: type, value: value),
    EnumWidgetConstructorDefault() => null,
    StaticMemberWidgetConstructorDefault(
      :final libraryUri,
      :final owner,
      :final member,
    ) =>
      WidgetbookStaticMemberValuePlan(
        type: type,
        libraryUri: libraryUri,
        owner: owner,
        member: member,
      ),
  };
  if (plan != null) {
    _validateConstructorDefaultConstraints(
      input,
      property,
      hasFiniteChoices: hasFiniteChoices,
    );
  }
  return plan;
}

AnalyzerEnumConstant? _canonicalEnumConstructorDefault(
  WidgetConstructorInput input,
) {
  final value = input.formal.computeConstantValue();
  final type = input.type;
  final element = type is InterfaceType ? type.element : null;
  if (value == null || value.isNull || element is! EnumElement) return null;
  return canonicalAnalyzerEnumConstant(value, element);
}

// Semantic constraint input only. The exact emitted constructor-default plan
// stays separate so successful validation never flattens a customer's const
// identity or source reference.
sealed class _ConstraintValidationTransport {
  const _ConstraintValidationTransport();
}

final class _ScalarConstraintValidationTransport
    extends _ConstraintValidationTransport {
  const _ScalarConstraintValidationTransport(this.value);

  final Object? value;
}

final class _CollectionConstraintValidationTransport
    extends _ConstraintValidationTransport {
  const _CollectionConstraintValidationTransport(this.length);

  final int length;
}

void _validateConstructorDefaultConstraints(
  WidgetConstructorInput input,
  PropertyEntry property, {
  required bool hasFiniteChoices,
}) {
  final constraints = widgetbookConstraintsFor(property);
  final hasValueConstraint = constraints.minimum != null ||
      constraints.exclusiveMinimum != null ||
      constraints.maximum != null ||
      constraints.exclusiveMaximum != null ||
      constraints.allowedValues != null ||
      constraints.pattern != null ||
      constraints.minLength != null ||
      constraints.maxLength != null ||
      constraints.minItems != null ||
      constraints.maxItems != null;
  if (!hasValueConstraint) return;

  final path = '/constructorDefaults/${property.name}';
  final transport = _constructorConstraintValidationTransport(input, property);
  if (transport == null) {
    throw StateError(
      'Widgetbook seed at $path cannot be reduced losslessly to the '
      'target-neutral constraint-validation transport.',
    );
  }
  final value = switch (transport) {
    _ScalarConstraintValidationTransport(:final value) => value,
    _CollectionConstraintValidationTransport() => transport,
  };
  _validateSeed(
    property,
    value,
    path: path,
    validateAllowedValues: !hasFiniteChoices,
  );
}

_ConstraintValidationTransport? _constructorConstraintValidationTransport(
  WidgetConstructorInput input,
  PropertyEntry property,
) {
  final value = input.formal.computeConstantValue();
  if (value == null) return null;
  if (value.isNull) {
    return input.nullable
        ? const _ScalarConstraintValidationTransport(null)
        : null;
  }

  if (property.type == PropertyType.widgetList ||
      isCustomerStructuredListShape(property.valueShape)) {
    final values = value.toListValue();
    return values == null
        ? null
        : _CollectionConstraintValidationTransport(values.length);
  }

  final finite = _finiteConstructorDefaultValue(input, property);
  if (!finite.available) return null;
  if (property.type == PropertyType.color) {
    final argb = finite.value;
    if (argb is! int) return null;
    return _ScalarConstraintValidationTransport(
      '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}',
    );
  }
  return _ScalarConstraintValidationTransport(finite.value);
}

({bool available, Object? value}) _finiteConstructorDefaultValue(
  WidgetConstructorInput input,
  PropertyEntry property,
) {
  final value = input.formal.computeConstantValue();
  if (value == null) return (available: false, value: null);
  final transport = widgetbookFiniteChoiceTransport(property.type);
  if (transport == null) return (available: false, value: null);
  if (value.isNull) {
    return (available: input.nullable, value: null);
  }

  final type = input.type;
  final element = type is InterfaceType ? type.element : null;
  bool isDartCore(String symbol) =>
      element?.library.identifier == 'dart:core' && element?.name == symbol;
  return switch (transport) {
    WidgetbookFiniteChoiceTransport.boolean => () {
        final decoded = isDartCore('bool') ? value.toBoolValue() : null;
        return (available: decoded != null, value: decoded);
      }(),
    WidgetbookFiniteChoiceTransport.integer => () {
        final decoded = isDartCore('int') ? value.toIntValue() : null;
        return (available: decoded != null, value: decoded);
      }(),
    WidgetbookFiniteChoiceTransport.real => () {
        if (!isDartCore('double') && !isDartCore('num')) {
          return (available: false, value: null);
        }
        final decoded = value.toDoubleValue() ?? value.toIntValue()?.toDouble();
        return (
          available: decoded != null && decoded.isFinite,
          value: decoded,
        );
      }(),
    WidgetbookFiniteChoiceTransport.string => () {
        final decoded = isDartCore('String') ? value.toStringValue() : null;
        return (available: decoded != null, value: decoded);
      }(),
    WidgetbookFiniteChoiceTransport.enumMember => () {
        final canonical = element is EnumElement
            ? canonicalAnalyzerEnumConstant(value, element)
            : null;
        return (
          available: canonical != null,
          value: canonical?.identity.member,
        );
      }(),
    WidgetbookFiniteChoiceTransport.color =>
      _finiteColorConstructorValue(value),
    WidgetbookFiniteChoiceTransport.durationMilliseconds =>
      _finiteDurationConstructorValue(value),
    WidgetbookFiniteChoiceTransport.fontWeight =>
      _finiteFontWeightConstructorValue(value),
  };
}

({bool available, Object? value}) _finiteColorConstructorValue(
  DartObject value,
) {
  final invocation = _exactFrameworkInvocation(
    value,
    libraryUri: 'dart:ui',
    owner: 'Color',
  );
  if (invocation == null) return (available: false, value: null);
  final name = invocation.constructor.name;
  if (name == 'new' || name == null || name.isEmpty) {
    if (invocation.positionalArguments case [final argument]) {
      final color = argument.toIntValue();
      return (
        available: color != null,
        value: color == null ? null : color & 0xFFFFFFFF,
      );
    }
    return (available: false, value: null);
  }
  if (name == 'fromARGB' && invocation.positionalArguments.length == 4) {
    final [alpha, red, green, blue] = invocation.positionalArguments;
    final channels = [
      alpha.toIntValue(),
      red.toIntValue(),
      green.toIntValue(),
      blue.toIntValue(),
    ];
    if (channels.any((channel) => channel == null)) {
      return (available: false, value: null);
    }
    return (
      available: true,
      value: ((channels[0]! & 0xFF) << 24) |
          ((channels[1]! & 0xFF) << 16) |
          ((channels[2]! & 0xFF) << 8) |
          (channels[3]! & 0xFF),
    );
  }
  return (available: false, value: null);
}

({bool available, Object? value}) _finiteDurationConstructorValue(
  DartObject value,
) {
  final invocation = _exactFrameworkInvocation(
    value,
    libraryUri: 'dart:core',
    owner: 'Duration',
  );
  final name = invocation?.constructor.name;
  if (invocation == null || name != 'new' && name != null && name.isNotEmpty) {
    return (available: false, value: null);
  }
  const microsecondsPerUnit = <String, int>{
    'days': Duration.microsecondsPerDay,
    'hours': Duration.microsecondsPerHour,
    'minutes': Duration.microsecondsPerMinute,
    'seconds': Duration.microsecondsPerSecond,
    'milliseconds': Duration.microsecondsPerMillisecond,
    'microseconds': 1,
  };
  var totalMicroseconds = 0;
  for (final entry in invocation.namedArguments.entries) {
    final multiplier = microsecondsPerUnit[entry.key];
    final argument = entry.value.toIntValue();
    if (multiplier == null || argument == null) {
      return (available: false, value: null);
    }
    totalMicroseconds += argument * multiplier;
  }
  if (totalMicroseconds % Duration.microsecondsPerMillisecond != 0) {
    return (available: false, value: null);
  }
  return (
    available: true,
    value: totalMicroseconds ~/ Duration.microsecondsPerMillisecond,
  );
}

({bool available, Object? value}) _finiteFontWeightConstructorValue(
  DartObject value,
) {
  final invocation = _exactFrameworkInvocation(
    value,
    libraryUri: 'dart:ui',
    owner: 'FontWeight',
  );
  final name = invocation?.constructor.name;
  if (invocation == null ||
      name != 'new' && name != null && name.isNotEmpty ||
      invocation.positionalArguments.length != 1) {
    return (available: false, value: null);
  }
  final weight = invocation.positionalArguments.single.toIntValue();
  final representable =
      weight != null && weight >= 100 && weight <= 900 && weight % 100 == 0;
  return (available: representable, value: representable ? weight : null);
}

ConstructorInvocation? _exactFrameworkInvocation(
  DartObject value, {
  required String libraryUri,
  required String owner,
}) {
  final invocation = value.constructorInvocation;
  if (invocation == null) return null;
  final enclosing = invocation.constructor.enclosingElement;
  if (enclosing.library.identifier != libraryUri || enclosing.name != owner) {
    return null;
  }
  return invocation;
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
  bool validateAllowedValues = true,
}) {
  if (!_seedSatisfiesConstraints(
    property,
    value,
    validateAllowedValues: validateAllowedValues,
  )) {
    throw StateError('Widgetbook seed at $path violates its constraints.');
  }
}

bool _seedSatisfiesConstraints(
  PropertyEntry property,
  Object? value, {
  bool validateAllowedValues = true,
}) {
  final constraints = widgetbookConstraintsFor(property);
  final allowed = constraints.allowedValues;
  if (validateAllowedValues && allowed != null && !allowed.contains(value)) {
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
  final itemCount = switch (value) {
    List(:final length) => length,
    _CollectionConstraintValidationTransport(:final length) => length,
    _ => null,
  };
  if (itemCount != null) {
    if (constraints.minItems != null && itemCount < constraints.minItems! ||
        constraints.maxItems != null && itemCount > constraints.maxItems!) {
      return false;
    }
  }
  return true;
}

/// Validates shared constraint values before Widgetbook applicability checks.
///
/// Kept in the target planner library so tests can prove Widgetbook consumes
/// the shared value contract without exposing a Widgetbook-specific API.
void validateWidgetbookConstraintApplicability(
  PropertyEntry property,
  RestageConstraints constraints, {
  required String path,
}) {
  final issue = validateRestageConstraintValues(constraints);
  if (issue != null) {
    final relativePath = issue.pathSuffix.startsWith('.')
        ? issue.pathSuffix.substring(1)
        : issue.pathSuffix;
    late final String detail;
    if (issue.message.startsWith('duplicate value ')) {
      detail = 'duplicate $relativePath '
          '${issue.message.substring('duplicate '.length)}';
    } else if (relativePath.isEmpty) {
      detail = issue.message;
    } else {
      detail = '$relativePath ${issue.message}';
    }
    throw StateError('Widgetbook constraints at $path: $detail.');
  }

  if (constraints.pattern case final pattern?) {
    try {
      RegExp(pattern);
    } on FormatException {
      throw StateError(
        'Widgetbook constraints at $path: pattern is not valid Dart RegExp '
        'syntax.',
      );
    }
  }

  final hasNumeric = constraints.minimum != null ||
      constraints.exclusiveMinimum != null ||
      constraints.maximum != null ||
      constraints.exclusiveMaximum != null;
  final numericProperty = property.type == PropertyType.integer ||
      property.type == PropertyType.real ||
      property.type == PropertyType.duration ||
      property.type == PropertyType.fontWeight;
  if (hasNumeric && !numericProperty) {
    throw StateError(
      'Widgetbook constraints at $path: numeric constraints are not valid for '
      'PropertyType.${property.type.name}.',
    );
  }

  final hasString = constraints.pattern != null ||
      constraints.minLength != null ||
      constraints.maxLength != null;
  final stringProperty = property.type == PropertyType.string ||
      property.type == PropertyType.color ||
      property.type == PropertyType.enumValue;
  if (hasString && !stringProperty) {
    throw StateError(
      'Widgetbook constraints at $path: string constraints are not valid for '
      'PropertyType.${property.type.name}.',
    );
  }

  final hasItems = constraints.minItems != null || constraints.maxItems != null;
  final collectionProperty = property.type == PropertyType.widgetList ||
      property.type == PropertyType.stringList ||
      property.type == PropertyType.booleanList ||
      isCustomerStructuredListShape(property.valueShape);
  if (hasItems && !collectionProperty) {
    throw StateError(
      'Widgetbook constraints at $path: item constraints are not valid for '
      'PropertyType.${property.type.name}.',
    );
  }

  final allowedValues = constraints.allowedValues;
  if (allowedValues == null) return;
  if (widgetbookFiniteChoiceTransport(property.type) == null) {
    throw StateError(
      'Widgetbook constraints at $path: allowedValues requires a supported '
      'scalar property; got PropertyType.${property.type.name}.',
    );
  }
  for (var index = 0; index < allowedValues.length; index++) {
    final value = allowedValues[index];
    if (value == null) continue;
    final compatible = switch (property.type) {
      PropertyType.boolean => value is bool,
      PropertyType.integer => value is int,
      PropertyType.real ||
      PropertyType.duration ||
      PropertyType.fontWeight =>
        value is num && value.isFinite,
      PropertyType.string ||
      PropertyType.color ||
      PropertyType.enumValue =>
        value is String,
      _ => false,
    };
    if (!compatible) {
      throw StateError(
        'Widgetbook constraints at $path: allowedValues[$index] value $value '
        '(${value.runtimeType}) is not compatible with '
        'PropertyType.${property.type.name}.',
      );
    }
  }
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
