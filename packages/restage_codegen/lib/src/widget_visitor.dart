import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/const_folding.dart';
import 'package:restage_codegen/src/customer_structured_discovery.dart';
import 'package:restage_codegen/src/customer_structured_reconstruction.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/json_scalar_type.dart';
import 'package:restage_codegen/src/type_inference.dart' as type_inference;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const String _unknownEnumHint =
    'The host SDK is older than this analyzer pass — update restage_shared '
    'or bump the catalog schema version.';

/// Result of walking a library for `@RestageWidget` classes.
@immutable
final class WidgetVisitorResult {
  /// Wraps the discovered [widgets] and [issues], storing each unmodifiable.
  WidgetVisitorResult({
    required List<WidgetEntry> widgets,
    required List<Issue> issues,
    List<StructuredEntry> structuredTypes = const [],
    List<UnionEntry> unions = const [],
    Map<String, String> slotTargets = const {},
    Set<String> nullableStructuredSlots = const {},
    Map<String, String> localUnrenderable = const {},
    Map<String, String> widgetUnrenderable = const {},
    Map<String, ReconstructionPlan> reconstructionPlans = const {},
  })  : widgets = List.unmodifiable(widgets),
        issues = List.unmodifiable(issues),
        structuredTypes = List.unmodifiable(structuredTypes),
        unions = List.unmodifiable(unions),
        slotTargets = Map.unmodifiable(slotTargets),
        nullableStructuredSlots = Set.unmodifiable(nullableStructuredSlots),
        localUnrenderable = Map.unmodifiable(localUnrenderable),
        widgetUnrenderable = Map.unmodifiable(widgetUnrenderable),
        reconstructionPlans = Map.unmodifiable(reconstructionPlans);

  /// Successfully extracted widget entries.
  final List<WidgetEntry> widgets;

  /// Diagnostics collected during the walk.
  final List<Issue> issues;

  /// Customer structured value types referenced by the widgets' properties
  /// (unallocated wire IDs; a later pass mints them).
  final List<StructuredEntry> structuredTypes;

  /// Customer unions referenced by the widgets' properties (unallocated wire
  /// IDs; a later pass mints them).
  final List<UnionEntry> unions;

  /// Structured slot -> target sourceType FQN, keyed `'<ownerFqn>.<slotName>'`
  /// (see [CustomerStructuredDiscovery.slotTargets]).
  final Map<String, String> slotTargets;

  /// Nullable WIDGET structured-prop slot keys (see
  /// [CustomerStructuredDiscovery.nullableStructuredSlots]).
  final Set<String> nullableStructuredSlots;

  /// Structured types whose walk dropped an unsupported inner field (see
  /// [CustomerStructuredDiscovery.localUnrenderable]).
  final Map<String, String> localUnrenderable;

  /// Widgets whose constructor has a positional hole, keyed by `flutterType` ->
  /// a human-readable reason. Excluded-loud at the admission point.
  final Map<String, String> widgetUnrenderable;

  /// The build-time reconstruction recipe per renderable structured type (see
  /// [CustomerStructuredDiscovery.reconstructionPlans]).
  final Map<String, ReconstructionPlan> reconstructionPlans;
}

/// Chooses the format-specific projection rules for [visitRestageWidgets].
enum WidgetVisitorTarget {
  /// Preserve the existing RFW catalog vocabulary and requiredness semantics.
  rfw,

  /// Preserve A2UI scalar lists and constructor-derived data requiredness.
  a2ui,
}

/// Walks [library] for classes annotated with `@RestageWidget`. For each:
/// - Extracts the annotation's catalog metadata (name, library, category,
///   description, fires, childrenSlot, deprecatedSince).
/// - Synthesizes `flutterType` from the annotated class's library URI +
///   class name.
/// - Walks `@RestageProperty`-annotated fields, infers each property type
///   from the field's static Dart type, and decodes literal defaults.
///
/// When [target] is [WidgetVisitorTarget.a2ui], direct `List<String>`,
/// `List<int>`, `List<double>`, `List<num>`, and `List<bool>` properties are
/// admitted through the analyzer seam. The default remains the RFW target so
/// existing RFW catalog bytes and callers are unchanged.
///
/// At end-of-pass, detects within-library duplicate widget names (same
/// `(library namespace, name)`) and emits [IssueCode.duplicateWidgetName].
WidgetVisitorResult visitRestageWidgets(
  LibraryElement library,
  AssetId assetId, {
  WidgetVisitorTarget target = WidgetVisitorTarget.rfw,
}) {
  final widgets = <WidgetEntry>[];
  final issues = <Issue>[];

  // Identify the `@RestageWidget` classes once so a structured pre-pass can
  // discover the customer value types their properties reference before the
  // per-widget property build reads them.
  final widgetClasses = [
    for (final cls in library.classes)
      if (firstAnnotation(cls, 'RestageWidget') != null) cls,
  ];
  final structured = discoverCustomerStructured(
    widgetClasses: widgetClasses,
    assetId: assetId,
    issues: issues,
  );

  // Widgets whose constructor has a POSITIONAL HOLE — excluded-loud at the one
  // admission point (a silent wrong-render otherwise). Keyed by `flutterType`.
  final widgetUnrenderable = <String, String>{};
  for (final cls in widgetClasses) {
    final annotation = firstAnnotation(cls, 'RestageWidget')!;
    final entry = _readWidgetAnnotation(
      cls,
      annotation,
      assetId,
      issues,
      structured,
      target: target,
    );
    if (entry == null) continue;
    widgets.add(entry);
    // A positional ctor param NOT bound to an annotated `@RestageProperty`
    // field (the factory emits no arg for it) before an annotated
    // field-positional
    // shifts the later prop's value into the hole's slot — the widget-level
    // analog of the nested positional-hole guard, sharing one hole definition.
    final ctor = defaultGenerativeConstructor(cls);
    if (ctor != null) {
      final propNames = {for (final p in entry.properties) p.name};
      final hole = positionalHoleReason(ctor, propNames);
      if (hole != null) widgetUnrenderable[entry.flutterType] = hole;
    }
  }

  final byKey = <String, List<WidgetEntry>>{};
  for (final w in widgets) {
    final key = '${w.library.namespace}#${w.name}';
    byKey.putIfAbsent(key, () => []).add(w);
  }
  final duplicateKeys = byKey.entries.where((e) => e.value.length > 1);
  if (duplicateKeys.isNotEmpty) {
    for (final entry in duplicateKeys) {
      final classes =
          entry.value.map((w) => w.flutterType.split('#').last).join(', ');
      issues.add(
        Issue(
          code: IssueCode.duplicateWidgetName,
          message: 'Multiple @RestageWidget classes share name in '
              '${entry.key}: $classes.',
          location: assetId.path,
        ),
      );
    }
    final dupKeySet = duplicateKeys.map((e) => e.key).toSet();
    widgets.removeWhere(
      (w) => dupKeySet.contains('${w.library.namespace}#${w.name}'),
    );
  }

  return WidgetVisitorResult(
    widgets: widgets,
    issues: issues,
    structuredTypes: structured.structuredTypes,
    unions: structured.unions,
    slotTargets: structured.slotTargets,
    nullableStructuredSlots: structured.nullableStructuredSlots,
    localUnrenderable: structured.localUnrenderable,
    widgetUnrenderable: widgetUnrenderable,
    reconstructionPlans: structured.reconstructionPlans,
  );
}

WidgetEntry? _readWidgetAnnotation(
  ClassElement cls,
  ElementAnnotation annotation,
  AssetId assetId,
  List<Issue> issues,
  CustomerStructuredDiscovery structured, {
  required WidgetVisitorTarget target,
}) {
  final value = annotation.computeConstantValue();
  final className = cls.name ?? '<unnamed>';
  final widgetLocation = '${assetId.path}#$className';
  if (value == null) {
    issues.add(
      Issue(
        code: IssueCode.missingAnnotationField,
        message: '@RestageWidget on $className could not be const-evaluated. '
            'Check that every argument is a compile-time constant '
            '(no references to non-const variables, no null where a '
            'non-nullable value is required).',
        location: widgetLocation,
      ),
    );
    return null;
  }
  if (cls.isAbstract || (cls.name?.startsWith('_') ?? false)) {
    issues.add(
      Issue(
        code: IssueCode.invalidWidgetClass,
        message: '@RestageWidget on $className: customer widget classes must '
            'be public and non-abstract so generated factories can construct '
            'them.',
        location: widgetLocation,
      ),
    );
    return null;
  }

  final name = value.getField('name')?.toStringValue();
  final libraryNamespace =
      value.getField('library')?.getField('namespace')?.toStringValue();
  final categoryName = _enumName(value.getField('category'));
  final description = value.getField('description')?.toStringValue();

  if (name == null ||
      libraryNamespace == null ||
      categoryName == null ||
      description == null) {
    issues.add(
      Issue(
        code: IssueCode.missingAnnotationField,
        message: 'Missing required fields on @RestageWidget for $className '
            '(name/library/category/description).',
        location: widgetLocation,
      ),
    );
    return null;
  }

  final library = WidgetLibrary.fromNamespace(libraryNamespace);
  final category =
      WidgetCategory.values.where((e) => e.name == categoryName).firstOrNull;
  if (category == null) {
    issues.add(
      Issue(
        code: IssueCode.unknownEnumValue,
        message: 'Unknown category "$categoryName". $_unknownEnumHint',
        location: widgetLocation,
      ),
    );
    return null;
  }

  final childrenSlot =
      _childrenSlotFromAnnotation(value, issues, widgetLocation);
  final fires = _firesFromAnnotation(value, issues, widgetLocation);
  final deprecatedSince = value.getField('deprecatedSince')?.toStringValue();

  // Collect each property with a stable ordering key so POSITIONAL args emit in
  // CONSTRUCTOR order, not field-declaration order: a positional ctor param
  // gets its ctor index (0,1,...); everything else keeps field order after the
  // positionals. The factory emits positional args first, in this order, so a
  // widget whose fields are declared out of ctor order (`Card(this.a, this.b)`
  // with `b` declared first) still emits `Card(<a>, <b>)`. Named args are
  // order-independent. Same analyzer-ctor-order view the reconstruction plan
  // uses for nested positional args.
  final keyed = <({int key, PropertyEntry prop})>[];
  var fieldOrder = 0;
  for (final field in cls.fields) {
    final propAnnotation = firstAnnotation(field, 'RestageProperty');
    if (propAnnotation == null) continue;
    final order = fieldOrder++;
    final p = _readPropertyAnnotation(
      field,
      propAnnotation,
      assetId,
      issues,
      structured,
      target: target,
    );
    // A bad property emits its own issue; keep collecting so a typo on one
    // field doesn't silently drop the entire widget from the catalog.
    if (p == null) continue;
    final positionalIndex = _positionalCtorIndex(field);
    final key = positionalIndex ?? (_namedSortBase + order);
    keyed.add((key: key, prop: p));
  }
  // Every key is distinct (positional ctor indices are small + unique; named
  // keys are `_namedSortBase + order`, unique + strictly larger), so an
  // unstable sort is deterministic.
  keyed.sort((a, b) => a.key.compareTo(b.key));
  final properties = [for (final entry in keyed) entry.prop];

  return WidgetEntry(
    wireId: WireId.unallocatedWidget,
    name: name,
    library: library,
    category: category,
    description: description,
    flutterType: _flutterTypeOf(cls),
    childrenSlot: childrenSlot,
    fires: fires,
    properties: properties,
    deprecatedSince: deprecatedSince,
  );
}

/// The property-ordering key base for NAMED (or non-constructor) properties —
/// strictly larger than any positional ctor index, so positional properties
/// sort first (in ctor order) and named properties follow (in field order).
const int _namedSortBase = 1 << 20;

/// The index of [field]'s parameter in its owning class's default generative
/// constructor's formal-parameter list WHEN that parameter is POSITIONAL, else
/// `null` (a named param, or not a constructor param). Positional parameters
/// precede named ones in `formalParameters`, so the index is the positional
/// slot — the order the generated factory must emit positional args in.
int? _positionalCtorIndex(FieldElement field) {
  final owner = field.enclosingElement;
  if (owner is! ClassElement) return null;
  final fieldName = field.name;
  if (fieldName == null) return null;
  final ctor = owner.constructors
      .where((c) => !c.isFactory && const {null, '', 'new'}.contains(c.name))
      .firstOrNull;
  if (ctor == null) return null;
  final params = ctor.formalParameters;
  for (var i = 0; i < params.length; i++) {
    if (params[i].name == fieldName) {
      return params[i].isPositional ? i : null;
    }
  }
  return null;
}

/// [field]'s parameter on its owning class's default (unnamed) generative
/// constructor — the constructor the generated reconstruction / factory
/// targets — or `null` when there is no such constructor or no parameter
/// binds the field. The constructor is the source of truth for a property's
/// required-ness (a structured argument the constructor requires) and its
/// positional-ness (a positional argument must emit positionally, not as a
/// named argument).
FormalParameterElement? _defaultConstructorFormalFor(FieldElement field) {
  final owner = field.enclosingElement;
  if (owner is! ClassElement) return null;
  final fieldName = field.name;
  if (fieldName == null) return null;
  final ctor = owner.constructors
      .where(
        (c) => !c.isFactory && const {null, '', 'new'}.contains(c.name),
      )
      .firstOrNull;
  if (ctor == null) return null;
  return ctor.formalParameters.where((p) => p.name == fieldName).firstOrNull;
}

/// Synthesizes a `flutterType` string for an `@RestageWidget`-annotated
/// class. The format is `'<library URI>#<class name>'`, which lets codegen
/// pattern-match generated factories against the annotated class.
String _flutterTypeOf(ClassElement cls) {
  final libraryUri = cls.library.identifier;
  final className = cls.name ?? '';
  return '$libraryUri#$className';
}

PropertyEntry? _readPropertyAnnotation(
  FieldElement field,
  ElementAnnotation annotation,
  AssetId assetId,
  List<Issue> issues,
  CustomerStructuredDiscovery structured, {
  required WidgetVisitorTarget target,
}) {
  final value = annotation.computeConstantValue();
  final fieldName = field.name ?? '<unnamed>';
  final ownerName = field.enclosingElement.name ?? '<unnamed>';
  final propertyLocation = '${assetId.path}#$ownerName.$fieldName';
  if (value == null) {
    issues.add(
      Issue(
        code: IssueCode.missingAnnotationField,
        message:
            '@RestageProperty on $ownerName.$fieldName could not be evaluated.',
        location: propertyLocation,
      ),
    );
    return null;
  }
  final description = value.getField('description')?.toStringValue();
  final annotationRequired = value.getField('required')?.toBoolValue() ?? false;
  final defaultBrandToken =
      value.getField('defaultBrandToken')?.toStringValue();
  final defaultValue = _decodeDefaultValue(
    value.getField('defaultValue'),
    issues,
    propertyLocation,
  );
  final defaultSource = _decodeDefaultSource(
    value.getField('defaultSource'),
    issues,
    propertyLocation,
  );
  final decodedValidationRule = _decodeValidationRule(
    value.getField('validationRule'),
    issues: issues,
    location: propertyLocation,
    ownerName: ownerName,
    fieldName: fieldName,
  );
  if (!decodedValidationRule.valid) return null;
  final validationRule = decodedValidationRule.value;
  final constraints = _decodeConstraints(
    value.getField('constraints'),
    issues: issues,
    location: propertyLocation,
    ownerName: ownerName,
    fieldName: fieldName,
  );
  if (constraints == null) return null;

  final declaredDefaults = (defaultValue == null ? 0 : 1) +
      (defaultBrandToken == null ? 0 : 1) +
      (defaultSource == null ? 0 : 1);
  if (declaredDefaults > 1) {
    issues.add(
      Issue(
        code: IssueCode.conflictingDefaultStrategy,
        message:
            '@RestageProperty on $ownerName.$fieldName supplies more than one '
            'of defaultValue / defaultBrandToken / defaultSource. Use at most '
            'one defaulting strategy.',
        location: propertyLocation,
      ),
    );
    return null;
  }

  if (validationRule != null && !constraints.isEmpty) {
    issues.add(
      Issue(
        code: IssueCode.conflictingValidationStrategy,
        message: '@RestageProperty on $ownerName.$fieldName supplies both '
            'typed constraints and validationRule. Use exactly one validation '
            'strategy.',
        location: propertyLocation,
      ),
    );
    return null;
  }

  if (description == null) {
    issues.add(
      Issue(
        code: IssueCode.missingAnnotationField,
        message:
            '@RestageProperty on $ownerName.$fieldName requires a description.',
        location: propertyLocation,
      ),
    );
    return null;
  }

  // A customer structured value (a nested data class, or a list/map/record of
  // one, or a sealed union) is resolved by the structured pre-pass; a scalar /
  // enum / widget / event falls through to the legacy type inference.
  final structuredShape = structured.shapeFor(field.type);
  final isA2ui = target == WidgetVisitorTarget.a2ui;
  final a2uiScalarList = isA2ui && _isA2uiScalarList(field.type);
  // The A2UI target preserves each scalar-list element type through its
  // analyzer seam without widening the shared RFW catalog taxonomy.
  // `structured` is the target-local carrier; seam assembly reflects the real
  // ListNode before emission.
  final PropertyType? type;
  if (structuredShape != null) {
    type = structuredShape.type;
  } else if (a2uiScalarList) {
    type = PropertyType.structured;
  } else {
    type = _inferPropertyType(
      field.type,
      field,
      assetId,
      issues,
      target: target,
    );
  }
  if (type == null) return null;

  // The default generative constructor binds this field — the source of truth
  // for its required-ness and positional-ness.
  final ctorFormal = _defaultConstructorFormalFor(field);

  // RFW retains its historical annotation-only rule for ordinary properties,
  // with constructor-derived requiredness only for structured data. A2UI uses
  // the constructor for every data-bearing property because its JSON Schema
  // must describe what generated construction actually requires. Events are
  // excluded from the A2UI data schema even when their constructor formal is
  // required; the builder's separate loud-coverage gate still verifies that a
  // required callback can be lowered.
  final required = switch (target) {
    WidgetVisitorTarget.rfw => structuredShape != null
        ? (annotationRequired || (ctorFormal?.isRequired ?? false))
        : annotationRequired,
    WidgetVisitorTarget.a2ui => type != PropertyType.event &&
        (annotationRequired || (ctorFormal?.isRequired ?? false)),
  };

  // A POSITIONAL constructor argument must emit positionally — `Widget(arg)`,
  // not `Widget(name: arg)` — or the generated factory / A2UI reconstruction
  // does not compile. Derived from the constructor formal for EVERY property
  // type (positional-ness is not structured-specific); defaults to named when
  // no default-constructor parameter binds the field.
  final positional = ctorFormal?.isPositional ?? false;

  // Mutual exclusion (checked above) guarantees at most one defaulting
  // strategy is set, so an explicit literal `defaultValue` folds into a
  // canonical LiteralDefault source — the legacy field is no longer stored.
  final resolvedSource = defaultSource ??
      (defaultValue != null ? LiteralDefault(defaultValue) : null);

  // The shared RFW visitor output remains byte-neutral. The A2UI target alone
  // retains a source-qualified enum identity so generated code can import and
  // spell customer enums instead of dropping an otherwise representable
  // required enum at the emitter boundary.
  final EnumShape? a2uiEnumShape;
  final fieldType = field.type;
  if (isA2ui &&
      type == PropertyType.enumValue &&
      fieldType is InterfaceType &&
      fieldType.element is EnumElement) {
    final element = fieldType.element as EnumElement;
    a2uiEnumShape = EnumShape(
      propertyType: PropertyType.enumValue,
      enumRef: DartTypeRef(
        libraryUri: element.library.identifier,
        symbolName: element.name ?? field.type.getDisplayString(),
      ),
    );
  } else {
    a2uiEnumShape = null;
  }

  return PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: fieldName,
    type: type,
    description: description,
    required: required,
    positional: positional,
    defaultBrandToken: defaultBrandToken,
    defaultSource: resolvedSource,
    enumType: a2uiEnumShape?.enumRef.symbolName,
    structuredRef: structuredShape?.structuredRef,
    valueShape: structuredShape?.valueShape ?? a2uiEnumShape,
    validationRule: validationRule,
    constraints: constraints,
  );
}

({bool valid, ValidationExpr? value}) _decodeValidationRule(
  DartObject? value, {
  required List<Issue> issues,
  required String location,
  required String ownerName,
  required String fieldName,
}) {
  if (value == null || value.isNull) return (valid: true, value: null);
  final expression = value.getField('expression')?.toStringValue();
  final message = value.getField('message')?.toStringValue();
  if (expression == null || message == null) {
    issues.add(
      Issue(
        code: IssueCode.missingAnnotationField,
        message: '@RestageProperty validationRule on $ownerName.$fieldName '
            'has an expression or message that could not be read as a '
            'compile-time constant String. Use compile-time constant Strings '
            'for both fields.',
        location: location,
      ),
    );
    return (valid: false, value: null);
  }
  return (
    valid: true,
    value: ValidationExpr(expression: expression, message: message),
  );
}

RestageConstraints? _decodeConstraints(
  DartObject? value, {
  required List<Issue> issues,
  required String location,
  required String ownerName,
  required String fieldName,
}) {
  if (value == null || value.isNull) return RestageConstraints.empty;
  final allowedValues = value.getField('allowedValues')?.toListValue();
  final decodedAllowedValues = <Object?>[];
  if (allowedValues != null) {
    for (var index = 0; index < allowedValues.length; index++) {
      final decoded = _decodeConstraintScalar(allowedValues[index]);
      if (!decoded.valid) {
        final typeName =
            allowedValues[index].type?.getDisplayString() ?? '<unknown>';
        issues.add(
          Issue(
            code: IssueCode.invalidConstraintValue,
            message: '@RestageProperty constraints.allowedValues[$index] on '
                '$ownerName.$fieldName has non-JSON const type '
                '$typeName. '
                'Use null, a finite int/double, bool, or String.',
            location: location,
          ),
        );
        return null;
      }
      decodedAllowedValues.add(decoded.value);
    }
  }
  final minimum = _decodeNum(value.getField('minimum'));
  final exclusiveMinimum = _decodeNum(value.getField('exclusiveMinimum'));
  final maximum = _decodeNum(value.getField('maximum'));
  final exclusiveMaximum = _decodeNum(value.getField('exclusiveMaximum'));
  final bounds = <({String name, ({bool valid, num? value}) decoded})>[
    (
      name: 'minimum',
      decoded: minimum,
    ),
    (
      name: 'exclusiveMinimum',
      decoded: exclusiveMinimum,
    ),
    (
      name: 'maximum',
      decoded: maximum,
    ),
    (
      name: 'exclusiveMaximum',
      decoded: exclusiveMaximum,
    ),
  ];
  var validBounds = true;
  for (final bound in bounds) {
    if (bound.decoded.valid) continue;
    validBounds = false;
    issues.add(
      Issue(
        code: IssueCode.invalidConstraintValue,
        message: '@RestageProperty constraints.${bound.name} on '
            '$ownerName.$fieldName must be a finite compile-time constant int '
            'or double.',
        location: location,
      ),
    );
  }
  if (!validBounds) return null;
  return RestageConstraints(
    minimum: minimum.value,
    exclusiveMinimum: exclusiveMinimum.value,
    maximum: maximum.value,
    exclusiveMaximum: exclusiveMaximum.value,
    allowedValues: allowedValues == null
        ? null
        : List<Object?>.unmodifiable(decodedAllowedValues),
    pattern: value.getField('pattern')?.toStringValue(),
    minLength: value.getField('minLength')?.toIntValue(),
    maxLength: value.getField('maxLength')?.toIntValue(),
    minItems: value.getField('minItems')?.toIntValue(),
    maxItems: value.getField('maxItems')?.toIntValue(),
  );
}

({bool valid, Object? value}) _decodeConstraintScalar(DartObject value) {
  if (value.isNull) return (valid: true, value: null);
  final integer = value.toIntValue();
  if (integer != null) return (valid: true, value: integer);
  final real = value.toDoubleValue();
  if (real != null && real.isFinite) return (valid: true, value: real);
  final boolean = value.toBoolValue();
  if (boolean != null) return (valid: true, value: boolean);
  final string = value.toStringValue();
  if (string != null) return (valid: true, value: string);
  return (valid: false, value: null);
}

({bool valid, num? value}) _decodeNum(DartObject? value) {
  if (value == null || value.isNull) return (valid: true, value: null);
  final integer = value.toIntValue();
  if (integer != null) return (valid: true, value: integer);
  final real = value.toDoubleValue();
  if (real != null && real.isFinite) return (valid: true, value: real);
  return (valid: false, value: null);
}

PropertyType? _inferPropertyType(
  DartType t,
  FieldElement field,
  AssetId assetId,
  List<Issue> issues, {
  required WidgetVisitorTarget target,
}) {
  final inferred = type_inference.inferPropertyType(t);
  if (inferred != null) return inferred;
  final fieldName = field.name ?? '<unnamed>';
  final ownerName = field.enclosingElement.name ?? '<unnamed>';
  final a2uiListHint = target == WidgetVisitorTarget.a2ui
      ? ', and List<scalar> (String, int, double, num, or bool)'
      : '';
  issues.add(
    Issue(
      code: IssueCode.unsupportedPropertyType,
      message: 'Unsupported property type ${t.getDisplayString()} '
          'on $ownerName.$fieldName. Supported types: Widget, List<Widget>, '
          'Color, EdgeInsets(Geometry|Directional), '
          'Alignment(Geometry|Directional), FontWeight, bool, int, double, '
          'String, VoidCallback (and similar function types), and any Dart '
          'enum$a2uiListHint.',
      location: '${assetId.path}#$ownerName.$fieldName',
    ),
  );
  return null;
}

/// Whether [type] is a `List<T>` whose element is one of A2UI's JSON scalar
/// families. Nullability on the list or element is carried by the reflector.
bool _isA2uiScalarList(DartType type) {
  if (type is! InterfaceType ||
      !type.isDartCoreList ||
      type.typeArguments.length != 1) {
    return false;
  }
  final element = type.typeArguments.single;
  return classifyJsonScalarType(element) != null;
}

ChildrenSlot _childrenSlotFromAnnotation(
  DartObject value,
  List<Issue> issues,
  String location,
) {
  final name = _enumName(value.getField('childrenSlot'));
  if (name == null) return ChildrenSlot.none;
  final match = ChildrenSlot.values.where((e) => e.name == name).firstOrNull;
  if (match != null) return match;
  issues.add(
    Issue(
      code: IssueCode.unknownEnumValue,
      message: 'Unknown childrenSlot "$name". $_unknownEnumHint',
      location: location,
    ),
  );
  return ChildrenSlot.none;
}

List<WidgetEventName> _firesFromAnnotation(
  DartObject value,
  List<Issue> issues,
  String location,
) {
  final list = value.getField('fires')?.toListValue();
  if (list == null) return const [];
  final result = <WidgetEventName>[];
  for (final entry in list) {
    final n = _enumName(entry);
    if (n == null) continue;
    final match = WidgetEventName.values.where((e) => e.name == n).firstOrNull;
    if (match != null) {
      result.add(match);
    } else {
      issues.add(
        Issue(
          code: IssueCode.unknownEnumValue,
          message: 'Unknown fires entry "$n". $_unknownEnumHint',
          location: location,
        ),
      );
    }
  }
  return result;
}

/// Reads the string `name` of an enum-valued [DartObject] via the analyzer's
/// internal `_name` field. The analyzer's public API exposes enum names only
/// on real `Enum` instances — at constant-evaluation time we have a
/// `DartObject`, so we drop down to the implementation field.
String? _enumName(DartObject? value) {
  if (value == null || value.isNull) return null;
  return value.getField('_name')?.toStringValue();
}

Object? _decodeDefaultValue(
  DartObject? v,
  List<Issue> issues,
  String location,
) {
  if (v == null || v.isNull) return null;
  final scalar = decodeConstScalar(v);
  if (scalar != null) return scalar;
  final list = v.toListValue();
  if (list != null) {
    return list.map((e) => _decodeDefaultValue(e, issues, location)).toList();
  }
  final typeName = v.type?.getDisplayString() ?? '<unknown>';
  issues.add(
    Issue(
      code: IssueCode.invalidDefault,
      message: 'Unsupported defaultValue type $typeName. '
          'Supported: String, bool, int, double, and lists of these.',
      location: location,
    ),
  );
  return null;
}

DefaultValueSource? _decodeDefaultSource(
  DartObject? v,
  List<Issue> issues,
  String location,
) {
  if (v == null || v.isNull) return null;
  final typeName = v.type?.element?.name;
  switch (typeName) {
    case 'LiteralDefault':
      final literal =
          _decodeDefaultValue(v.getField('value'), issues, location);
      if (literal == null) return null;
      return LiteralDefault(literal);
    case 'TokenRefDefault':
      final token = _decodeWireIdRef(
        v.getField('token'),
        expectedKind: WireIdKind.designToken,
        issues: issues,
        location: location,
      );
      return token == null ? null : TokenRefDefault(token);
    case 'ThemeBindingDefault':
      final path = _decodeThemeBindingPath(
        v.getField('path'),
        issues,
        location,
      );
      return path == null ? null : ThemeBindingDefault(path);
    case 'FlutterCtorDefault':
      return const FlutterCtorDefault();
  }
  issues.add(
    Issue(
      code: IssueCode.invalidDefault,
      message: 'Unsupported defaultSource type '
          '${v.type?.getDisplayString() ?? '<unknown>'}.',
      location: location,
    ),
  );
  return null;
}

WireIdRef? _decodeWireIdRef(
  DartObject? v, {
  required WireIdKind expectedKind,
  required List<Issue> issues,
  required String location,
}) {
  if (v == null || v.isNull) return null;
  final library = v.getField('library')?.toStringValue();
  final wireId = _decodeWireId(v.getField('wireId'), issues, location);
  if (library == null || wireId == null) {
    issues.add(
      Issue(
        code: IssueCode.invalidDefault,
        message: 'Malformed tokenRef defaultSource; expected a WireIdRef '
            'with library and wireId.',
        location: location,
      ),
    );
    return null;
  }
  if (wireId.kind != expectedKind) {
    issues.add(
      Issue(
        code: IssueCode.invalidDefault,
        message: 'Malformed tokenRef defaultSource; expected '
            '${expectedKind.prefix}* but got ${wireId.value}.',
        location: location,
      ),
    );
    return null;
  }
  return WireIdRef(library: library, wireId: wireId);
}

WireId? _decodeWireId(
  DartObject? v,
  List<Issue> issues,
  String location,
) {
  final value = v?.getField('value')?.toStringValue();
  if (value == null || value.isEmpty) return null;
  try {
    final sequence = int.tryParse(value.substring(1), radix: 10);
    if (sequence == 0) {
      return switch (value.codeUnitAt(0)) {
        119 => WireId.unallocatedWidget,
        112 => WireId.unallocatedProperty,
        115 => WireId.unallocatedStructured,
        118 => WireId.unallocatedVariant,
        117 => WireId.unallocatedUnion,
        116 => WireId.unallocatedDesignToken,
        97 => WireId.unallocatedParameter,
        _ => WireId(value),
      };
    }
    return WireId(value);
  } on Object catch (error) {
    issues.add(
      Issue(
        code: IssueCode.invalidDefault,
        message: 'Malformed wireId in defaultSource: $error',
        location: location,
      ),
    );
    return null;
  }
}

ThemeBindingPath? _decodeThemeBindingPath(
  DartObject? v,
  List<Issue> issues,
  String location,
) {
  if (v == null || v.isNull) return null;
  final path = v.getField('path')?.toStringValue();
  final resolverName = v.getField('resolverName')?.toStringValue();
  if (path == null && resolverName == null) {
    issues.add(
      Issue(
        code: IssueCode.invalidDefault,
        message: 'Malformed themeBinding defaultSource; expected path or '
            'resolverName.',
        location: location,
      ),
    );
    return null;
  }
  if (path != null && resolverName != null) {
    return ThemeBindingPath.both(path: path, resolverName: resolverName);
  }
  return path != null
      ? ThemeBindingPath.path(path)
      : ThemeBindingPath.resolver(resolverName!);
}
