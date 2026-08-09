import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/callback_shape.dart';
import 'package:restage_codegen/src/const_folding.dart';
import 'package:restage_codegen/src/customer_map_plan.dart';
import 'package:restage_codegen/src/customer_record_plan.dart';
import 'package:restage_codegen/src/customer_structured_admissibility.dart'
    show isCustomerRecordPropertySlot, structuredSlotKey;
import 'package:restage_codegen/src/customer_structured_discovery.dart';
import 'package:restage_codegen/src/customer_structured_reconstruction.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/json_scalar_type.dart';
import 'package:restage_codegen/src/rfw_callback_signature.dart';
import 'package:restage_codegen/src/type_inference.dart' as type_inference;
import 'package:restage_codegen/src/widget_constructor_facts.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart'
    show
        MapAdmitted,
        MapExcluded,
        NotAMap,
        NotARecord,
        RecordAdmitted,
        RecordExcluded,
        classifyMapType,
        classifyRecordType;
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
    Map<String, MapPlan> mapPlans = const {},
    Map<String, RecordPlan> recordPlans = const {},
    List<PropertyExclusion> exclusions = const [],
  })  : widgets = List.unmodifiable(widgets),
        issues = List.unmodifiable(issues),
        structuredTypes = List.unmodifiable(structuredTypes),
        unions = List.unmodifiable(unions),
        slotTargets = Map.unmodifiable(slotTargets),
        nullableStructuredSlots = Set.unmodifiable(nullableStructuredSlots),
        localUnrenderable = Map.unmodifiable(localUnrenderable),
        widgetUnrenderable = Map.unmodifiable(widgetUnrenderable),
        reconstructionPlans = Map.unmodifiable(reconstructionPlans),
        mapPlans = Map.unmodifiable(mapPlans),
        recordPlans = Map.unmodifiable(recordPlans),
        exclusions = List.unmodifiable(exclusions);

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

  /// Widgets excluded before admission, keyed by `flutterType` to a
  /// human-readable reason.
  final Map<String, String> widgetUnrenderable;

  /// The build-time reconstruction recipe per renderable structured type (see
  /// [CustomerStructuredDiscovery.reconstructionPlans]).
  final Map<String, ReconstructionPlan> reconstructionPlans;

  /// The build-time map reconstruction recipe per map slot.
  final Map<String, MapPlan> mapPlans;

  /// The build-time record reconstruction recipe per record slot.
  final Map<String, RecordPlan> recordPlans;

  /// Constructor inputs dropped because this target has no decoder for their
  /// type, recorded so the omission is queryable rather than silent.
  final List<PropertyExclusion> exclusions;
}

/// Chooses the format-specific projection rules for [visitRestageWidgets].
enum WidgetVisitorTarget {
  /// Preserve the existing RFW catalog vocabulary and requiredness semantics.
  rfw,

  /// Preserve the shared catalog vocabulary for Widgetbook story generation.
  widgetbook,

  /// Preserve A2UI scalar lists and constructor-derived data requiredness.
  a2ui,
}

const _catalogSchemaOrigin = 'package:rfw_catalog_schema';

ElementAnnotation? _catalogAnnotation(Element element, String name) =>
    firstAnnotationFromOriginAny(
      element,
      {name},
      _catalogSchemaOrigin,
    );

/// Walks [library] for classes annotated with `@RestageWidget`. For each:
/// - Extracts the annotation's catalog metadata (name, library, category,
///   description, and childrenSlot).
/// - Synthesizes `flutterType` from the annotated class's library URI +
///   class name.
/// - Walks public constructor-bound inputs in constructor order, applies an
///   optional `@RestageProperty` overlay, and infers each property type.
///
/// When [target] is [WidgetVisitorTarget.a2ui], direct `List<String>`,
/// `List<int>`, `List<double>`, `List<num>`, and `List<bool>` properties are
/// admitted through the analyzer seam. The RFW and Widgetbook targets retain
/// the shared catalog projection.
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
      if (_catalogAnnotation(cls, 'RestageWidget') != null) cls,
  ];
  final constructorFacts = <ClassElement, WidgetConstructorFacts>{};
  for (final cls in widgetClasses) {
    final facts = readWidgetConstructorFacts(cls, assetId);
    constructorFacts[cls] = facts;
    issues.addAll(
      facts.issues.map(
        (issue) => Issue(
          code: issue.code,
          message: 'For the ${target.name} target, ${issue.message}',
          location: issue.location,
          capabilityGapSubject: issue.capabilityGapSubject,
        ),
      ),
    );
  }
  final structured = discoverCustomerStructured(
    widgetClasses: widgetClasses,
    widgetInputs: {
      for (final entry in constructorFacts.entries)
        entry.key: entry.value.inputs,
    },
    assetId: assetId,
    issues: issues,
  );
  final mapPlans = <String, MapPlan>{...structured.mapPlans};
  final recordPlans = <String, RecordPlan>{...structured.recordPlans};

  // Widget-level exclusions are collected first-wins and surfaced at the one
  // admission point. Keyed by `flutterType`.
  final widgetUnrenderable = <String, String>{};
  // Property-level exclusions: inputs dropped because this target has no
  // decoder for their type. Recorded rather than raised, because an optional
  // input the compiler cannot decode is ordinary Dart omission.
  final exclusions = <PropertyExclusion>[];
  for (final cls in widgetClasses) {
    final annotation = _catalogAnnotation(cls, 'RestageWidget')!;
    final entry = _readWidgetAnnotation(
      cls,
      annotation,
      assetId,
      issues,
      structured,
      widgetUnrenderable: widgetUnrenderable,
      exclusions: exclusions,
      target: target,
      mapPlans: mapPlans,
      recordPlans: recordPlans,
      constructorFacts: constructorFacts[cls]!,
    );
    if (entry == null) continue;
    widgets.add(entry);
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

  final nullableStructuredSlots = <String>{
    ...structured.nullableStructuredSlots,
    for (final widget in widgets)
      for (final property in widget.properties)
        if (property.constructorNullable &&
            isCustomerRecordPropertySlot(property))
          structuredSlotKey(widget.flutterType, property.name),
  };

  return WidgetVisitorResult(
    widgets: widgets,
    issues: issues,
    structuredTypes: structured.structuredTypes,
    unions: structured.unions,
    slotTargets: structured.slotTargets,
    nullableStructuredSlots: nullableStructuredSlots,
    localUnrenderable: structured.localUnrenderable,
    widgetUnrenderable: widgetUnrenderable,
    reconstructionPlans: structured.reconstructionPlans,
    mapPlans: mapPlans,
    recordPlans: recordPlans,
    exclusions: exclusions,
  );
}

WidgetEntry? _readWidgetAnnotation(
  ClassElement cls,
  ElementAnnotation annotation,
  AssetId assetId,
  List<Issue> issues,
  CustomerStructuredDiscovery structured, {
  required Map<String, String> widgetUnrenderable,
  required List<PropertyExclusion> exclusions,
  required WidgetVisitorTarget target,
  required Map<String, MapPlan> mapPlans,
  required Map<String, RecordPlan> recordPlans,
  required WidgetConstructorFacts constructorFacts,
}) {
  final value = annotation.computeConstantValue();
  final className = cls.name ?? '<unnamed>';
  final widgetLocation = '${assetId.path}#$className';
  if (constructorFacts.issues.any(
    (issue) =>
        issue.code == IssueCode.invalidWidgetConstructorInput &&
        issue.location == widgetLocation,
  )) {
    return null;
  }
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
  final explicitDescription =
      value.getField('description')?.toStringValue() ?? '';
  final description = explicitDescription.trim().isNotEmpty
      ? explicitDescription
      : normalizeDartdoc(cls.documentationComment);

  if (name == null || libraryNamespace == null || categoryName == null) {
    issues.add(
      Issue(
        code: IssueCode.missingAnnotationField,
        message: 'Missing required fields on @RestageWidget for $className '
            '(name/library/category).',
        location: widgetLocation,
      ),
    );
    return null;
  }
  if (description == null) {
    issues.add(
      Issue(
        code: IssueCode.missingCatalogDescription,
        message: '$className requires either RestageWidget.description or '
            'Dart documentation on the class.',
        location: widgetLocation,
      ),
    );
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
  final flutterType = _flutterTypeOf(cls);

  final properties = <PropertyEntry>[];
  final exclusionStart = exclusions.length;
  for (final input in constructorFacts.inputs) {
    final p = _readPropertyInput(
      input,
      assetId,
      issues,
      structured,
      widgetFlutterType: flutterType,
      library: library,
      widgetUnrenderable: widgetUnrenderable,
      exclusions: exclusions,
      target: target,
      mapPlans: mapPlans,
      recordPlans: recordPlans,
    );
    if (p == null) continue;
    properties.add(p);
  }
  _validateTargetPositionalExclusions(
    className: className,
    target: target,
    inputs: constructorFacts.inputs,
    properties: properties,
    exclusions: exclusions.skip(exclusionStart),
    issues: issues,
  );
  if (description == null) return null;

  return WidgetEntry(
    wireId: WireId.unallocatedWidget,
    name: name,
    library: library,
    category: category,
    description: description,
    flutterType: flutterType,
    childrenSlot: childrenSlot,
    properties: properties,
  );
}

/// Synthesizes a `flutterType` string for an `@RestageWidget`-annotated
/// class. The format is `'<library URI>#<class name>'`, which lets codegen
/// pattern-match generated factories against the annotated class.
String _flutterTypeOf(ClassElement cls) {
  final libraryUri = cls.library.identifier;
  final className = cls.name ?? '';
  return '$libraryUri#$className';
}

PropertyEntry? _readPropertyInput(
  WidgetConstructorInput input,
  AssetId assetId,
  List<Issue> issues,
  CustomerStructuredDiscovery structured, {
  required WidgetVisitorTarget target,
  required WidgetLibrary library,
  required String widgetFlutterType,
  required Map<String, String> widgetUnrenderable,
  required List<PropertyExclusion> exclusions,
  required Map<String, MapPlan> mapPlans,
  required Map<String, RecordPlan> recordPlans,
}) {
  final field = input.field;
  final annotation = input.propertyAnnotation;
  final value = annotation?.computeConstantValue();
  final fieldName = input.name;
  final ownerName = widgetFlutterType.split('#').last;
  final propertyLocation = '${assetId.path}#$ownerName.$fieldName';
  if (annotation != null && value == null) {
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
  final explicitDescription =
      value?.getField('description')?.toStringValue() ?? '';
  final description = explicitDescription.trim().isNotEmpty
      ? explicitDescription
      : input.dartdocDescription;
  final annotationRequired =
      value?.getField('required')?.toBoolValue() ?? false;
  final defaultBrandToken =
      value?.getField('defaultBrandToken')?.toStringValue();
  final defaultSource = _decodeDefaultSource(
    value?.getField('defaultSource'),
    issues,
    propertyLocation,
  );
  final decodedValidationRule = _decodeValidationRule(
    value?.getField('validationRule'),
    issues: issues,
    location: propertyLocation,
    ownerName: ownerName,
    fieldName: fieldName,
  );
  if (!decodedValidationRule.valid) return null;
  final validationRule = decodedValidationRule.value;
  final constraints = _decodeConstraints(
    value?.getField('constraints'),
    issues: issues,
    location: propertyLocation,
    ownerName: ownerName,
    fieldName: fieldName,
  );
  if (constraints == null) return null;

  final declaredDefaults =
      (defaultBrandToken == null ? 0 : 1) + (defaultSource == null ? 0 : 1);
  if (declaredDefaults > 1) {
    issues.add(
      Issue(
        code: IssueCode.conflictingDefaultStrategy,
        message:
            '@RestageProperty on $ownerName.$fieldName supplies more than one '
            'of defaultBrandToken / defaultSource. Use at most '
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
        code: IssueCode.missingCatalogDescription,
        message: '$ownerName.$fieldName requires either '
            'RestageProperty.description or Dart documentation.',
        location: propertyLocation,
      ),
    );
    return null;
  }

  // A customer structured value (a nested data class, a list of one, or a
  // sealed union) is resolved by the structured pre-pass. Named records with
  // admitted scalar or enum labels are resolved at the RFW boundary below;
  // scalar / enum / widget / event types fall through to legacy type inference.
  final structuredShape = structured.shapeFor(input.type);
  final isA2ui = target == WidgetVisitorTarget.a2ui;
  final a2uiScalarList = isA2ui && _isA2uiScalarList(input.type);
  // Record and map value shapes mark this wire format only; other emit targets
  // keep an independent data-shape boundary. Both ride the same gate, and they
  // are mutually exclusive: a type classified as a record is never offered to
  // the map classifier.
  final customerValueSlot = target == WidgetVisitorTarget.rfw &&
      structuredShape == null &&
      !a2uiScalarList;
  final recordClassification = customerValueSlot
      ? classifyRecordType(input.type, admitNullableSlot: true)
      : const NotARecord();
  final mapClassification =
      customerValueSlot && recordClassification is NotARecord
          ? classifyMapType(
              input.type,
              structuredValuesAdmitted: true,
              library: library,
              policy: structured.policy,
            )
          : const NotAMap();
  final excludedReason = switch ((recordClassification, mapClassification)) {
    (RecordAdmitted(), _) when input.nullable && input.required =>
      'a required nullable record cannot preserve explicit null through RFW. '
          'Record slot on $ownerName.$fieldName was excluded.',
    (RecordExcluded(:final reason), _) =>
      '$reason Record slot on $ownerName.$fieldName was excluded.',
    (_, MapExcluded(:final reason)) =>
      '$reason Map slot on $ownerName.$fieldName was excluded.',
    _ => null,
  };
  if (excludedReason != null) {
    widgetUnrenderable.putIfAbsent(widgetFlutterType, () => excludedReason);
    return null;
  }
  // The admitted slot's opaque marker, recorded alongside its build-time plan
  // so the shape and the sidecar cannot be set without each other.
  //
  // ONE local can stand for both kinds only because they are mutually
  // exclusive, and that is not incidental: the map classifier above runs only
  // when `recordClassification is NotARecord`, so a record slot is never
  // offered to it and the two arms below can never both apply. If that gate
  // ever loosens, this local has to split back into two.
  final ScalarShape? customerShape;
  if (recordClassification case final RecordAdmitted admitted) {
    recordPlans[structuredSlotKey(widgetFlutterType, fieldName)] =
        recordPlanFromClassification(admitted);
    customerShape = ScalarShape.opaqueRecord();
  } else if (mapClassification case final MapAdmitted admitted) {
    mapPlans[structuredSlotKey(widgetFlutterType, fieldName)] =
        mapPlanFromClassification(admitted);
    customerShape = ScalarShape.opaqueStringKeyedMap();
  } else {
    customerShape = null;
  }
  // The A2UI target preserves each scalar-list element type through its
  // analyzer seam without widening the shared RFW catalog taxonomy.
  // `structured` is the target-local carrier; seam assembly reflects the real
  // ListNode before emission.
  final PropertyType? type;
  if (structuredShape != null) {
    type = structuredShape.type;
  } else if (a2uiScalarList) {
    type = PropertyType.structured;
  } else if (customerShape != null) {
    type = PropertyType.unknown;
  } else {
    type = _inferPropertyType(
      input.type,
      field,
      assetId,
      issues,
      target: target,
      input: input,
      widgetName: ownerName,
      exclusions: exclusions,
    );
  }
  if (type == null) return null;

  // The default generative constructor binds this field — the source of truth
  // for its required-ness and positional-ness.
  final required = annotationRequired || input.required;

  // A POSITIONAL constructor argument must emit positionally — `Widget(arg)`,
  // not `Widget(name: arg)` — or the generated factory / A2UI reconstruction
  // does not compile. Derived from the constructor formal for EVERY property
  // type (positional-ness is not structured-specific); defaults to named when
  // no default-constructor parameter binds the field.
  final positional = input.positional;

  // Mutual exclusion (checked above) guarantees at most one defaulting
  // strategy is set.
  var resolvedSource = defaultSource;
  if (target != WidgetVisitorTarget.widgetbook) {
    final constructorDefault = input.constructorDefault;
    if (constructorDefault
        case UnsupportedWidgetConstructorDefault(:final source)) {
      issues.add(
        Issue(
          code: IssueCode.invalidWidgetConstructorInput,
          message: '$ownerName.$fieldName has constructor default '
              '$source, which the ${target.name} target cannot reproduce. '
              'Make the Dart default public, importable, and reconstructable; '
              'change the constructor contract (for example, to a safe '
              'nullable input without a non-null default); use a '
              'catalog-facing wrapper; or ignore the optional input where '
              'omission is semantically legal.',
          location: propertyLocation,
        ),
      );
      return null;
    }
    if (resolvedSource == null && defaultBrandToken == null) {
      resolvedSource = switch (constructorDefault) {
        NoWidgetConstructorDefault() || NullWidgetConstructorDefault() => null,
        LiteralWidgetConstructorDefault(:final value) => LiteralDefault(value),
        EnumWidgetConstructorDefault(:final member) => LiteralDefault(member),
        StaticMemberWidgetConstructorDefault() ||
        StructuralWidgetConstructorDefault() ||
        UnsupportedWidgetConstructorDefault() =>
          null,
      };
    }
  }

  // Every projection retains a source-qualified enum identity for an
  // enum-valued property. The shared catalog needs it so `encodeCatalog`
  // accepts the enum slot (an enumValue property must carry `enumType` or an
  // `EnumShape`) and so generated code can import + spell a customer enum
  // instead of dropping an otherwise representable value; a built-in
  // (Flutter/Dart) enum comes bare through the emitter's Flutter import.
  // A2UI's projection is unchanged.
  final EnumShape? enumShape;
  final fieldType = input.type;
  if (type == PropertyType.enumValue &&
      fieldType is InterfaceType &&
      fieldType.element is EnumElement) {
    final element = fieldType.element as EnumElement;
    enumShape = EnumShape(
      propertyType: PropertyType.enumValue,
      enumRef: DartTypeRef(
        libraryUri: element.library.identifier,
        symbolName: element.name ?? input.type.getDisplayString(),
      ),
    );
  } else {
    enumShape = null;
  }
  final callback =
      target == WidgetVisitorTarget.rfw && type == PropertyType.event
          ? _rfwCallbackSignature(input.type)
          : const _CallbackSignatureResult.valid(null);
  if (target == WidgetVisitorTarget.rfw && !callback.valid) {
    issues.add(
      Issue(
        code: IssueCode.invalidEventConfiguration,
        message: '$ownerName.$fieldName has unsupported callback signature '
            '${input.type.getDisplayString()}. RFW customer events support a '
            'zero-argument void callback, one required positional dart:core '
            'scalar payload (nullable allowed), or one non-null List of those '
            'scalars (nullable elements allowed).',
        location: propertyLocation,
      ),
    );
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
    constructorNullable: input.nullable,
    constructorDefault: input.constructorDefault.reconstructedValue,
    enumType: enumShape?.enumRef.symbolName,
    structuredRef: structuredShape?.structuredRef,
    valueShape: structuredShape?.valueShape ?? customerShape ?? enumShape,
    validationRule: validationRule,
    constraints: constraints,
    callbackSignature: callback.signature,
  );
}

final class _CallbackSignatureResult {
  const _CallbackSignatureResult.valid(this.signature) : valid = true;

  const _CallbackSignatureResult.invalid()
      : valid = false,
        signature = null;

  final bool valid;
  final String? signature;
}

_CallbackSignatureResult _rfwCallbackSignature(DartType type) {
  return switch (classifyResolvedCallbackShape(type)) {
    ZeroArgumentCallback() => const _CallbackSignatureResult.valid(null),
    SingleValueCallback(:final valueType) =>
      _rfwSingleValueCallbackSignature(valueType),
    UnsupportedCallback() => const _CallbackSignatureResult.invalid(),
  };
}

_CallbackSignatureResult _rfwSingleValueCallbackSignature(DartType valueType) {
  final signature = RfwCallbackSignature.fromResolvedCustomerPayload(valueType);
  return signature == null
      ? const _CallbackSignatureResult.invalid()
      : _CallbackSignatureResult.valid(signature.source);
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
  required WidgetConstructorInput input,
  required String widgetName,
  required List<PropertyExclusion> exclusions,
}) {
  final inferred = type_inference.inferPropertyType(t);
  if (inferred != null) return inferred;
  final fieldName = input.name;
  final ownerName = field.enclosingElement.name ?? '<unnamed>';
  final location = '${assetId.path}#$ownerName.$fieldName';
  // A direct scalar-list property is supported on the A2UI target (it rides a
  // DynamicList) but the RFW customer catalog has no vocabulary for it. Fail
  // loud with a boundary-aware, customer-actionable diagnostic rather than the
  // generic "unsupported type" message: name the widget + property, state the
  // A2UI-supported / RFW-unsupported boundary, and name the remedies. The
  // message keeps the "Unsupported property type <T> on <owner>.<field>" prefix
  // the existing loud-failure assertions match.
  if (target != WidgetVisitorTarget.a2ui && _isA2uiScalarList(t)) {
    final boundary = switch (target) {
      WidgetVisitorTarget.rfw =>
        'are supported on the A2UI target but are not carried by the RFW '
            'customer catalog',
      WidgetVisitorTarget.widgetbook =>
        'are supported on the A2UI target but are not admitted by automatic '
            'Widgetbook stories; use a customer structured data class when '
            'the list is part of a richer value',
      WidgetVisitorTarget.a2ui => throw StateError(
          'A2UI scalar-list boundary reached from the A2UI target.',
        ),
    };
    final remedies = switch (target) {
      WidgetVisitorTarget.rfw =>
        'restrict the field to a supported RFW type (for example, a single '
            'scalar or List<Widget>), or scope this package to A2UI by '
            'disabling the RFW customer-catalog builders in build.yaml',
      WidgetVisitorTarget.widgetbook =>
        'use a currently admitted automatic-story type; support for this '
            'direct shape is a Restage compiler capability gap',
      WidgetVisitorTarget.a2ui => throw StateError(
          'A2UI scalar-list remedies reached from the A2UI target.',
        ),
    };
    return _undecodable(
      reason: 'Unsupported property type ${t.getDisplayString()} '
          'on $ownerName.$fieldName. Scalar-list properties (a List of '
          'String, int, double, num, or bool) $boundary. '
          'Remedies: $remedies.',
      input: input,
      target: target,
      widgetName: widgetName,
      fieldName: fieldName,
      location: location,
      issues: issues,
      exclusions: exclusions,
    );
  }
  final lookalike = type_inference.frameworkLookalike(t);
  if (lookalike != null) {
    // Deliberately NOT routed through `_undecodable`, and it must stay that
    // way. That helper drops an optional input whose type the compiler cannot
    // decode, on the grounds that the author cannot close a gap in our
    // decoders. A lookalike is the opposite situation: the author's own class
    // shadows a framework type name, which they can fix by renaming it or by
    // importing the real one. Excluding it silently would withhold a property
    // over a problem entirely in their hands, and would let precisely the
    // mis-resolution this check exists to catch reach the catalog unnoticed.
    // So it fails whether or not the input is omissible.
    issues.add(
      Issue(
        code: IssueCode.unsupportedPropertyType,
        message: 'Unsupported property type ${t.getDisplayString()} '
            'on $ownerName.$fieldName: this is '
            "`${lookalike.library}#${lookalike.name}`, not Flutter's "
            '`${lookalike.name}`. Framework value types are matched by '
            'defining library, not by name. This rejection applies to the '
            '${target.name} target.',
        location: location,
      ),
    );
    return null;
  }
  final a2uiListHint = switch (target) {
    WidgetVisitorTarget.a2ui =>
      ', and List<scalar> (String, int, double, num, or bool)',
    WidgetVisitorTarget.rfw || WidgetVisitorTarget.widgetbook => '',
  };
  return _undecodable(
    reason: 'Unsupported property type ${t.getDisplayString()} '
        'on $ownerName.$fieldName. Supported types: Widget, List<Widget>, '
        'Color, EdgeInsets(Geometry|Directional), '
        'Alignment(Geometry|Directional), FontWeight, bool, int, double, '
        'String, VoidCallback (and similar function types), and any Dart '
        'enum$a2uiListHint.',
    input: input,
    target: target,
    widgetName: widgetName,
    fieldName: fieldName,
    location: '${assetId.path}#$ownerName.$fieldName',
    issues: issues,
    exclusions: exclusions,
  );
}

void _validateTargetPositionalExclusions({
  required String className,
  required WidgetVisitorTarget target,
  required List<WidgetConstructorInput> inputs,
  required List<PropertyEntry> properties,
  required Iterable<PropertyExclusion> exclusions,
  required List<Issue> issues,
}) {
  final inputIndex = {
    for (final (index, input) in inputs.indexed) input.name: index,
  };
  final includedPositional = {
    for (final property in properties)
      if (property.positional) property.name,
  };
  for (final exclusion in exclusions) {
    final excludedIndex = inputIndex[exclusion.property];
    if (excludedIndex == null || !inputs[excludedIndex].positional) continue;
    final later = inputs
        .skip(excludedIndex + 1)
        .where(
          (input) =>
              input.positional && includedPositional.contains(input.name),
        )
        .firstOrNull;
    if (later == null) continue;
    issues.add(
      Issue(
        code: IssueCode.invalidWidgetConstructorInput,
        message: 'Constructor input $className.${exclusion.property} cannot '
            'be auto-excluded for the ${target.name} target while later '
            'positional input ${later.name} is included, because excluding an '
            'earlier positional would shift the arguments after it. Make '
            '${exclusion.property} named, or ensure ${later.name} and all '
            'later positional inputs are omitted too.',
        location: exclusion.location,
      ),
    );
  }
}

/// Resolves one input whose type has no decoder on [target].
///
/// An omissible input is dropped and recorded: generated construction leaves
/// the argument out, which is what plain Dart would do, so the widget's own
/// semantics are unchanged and the build succeeds. The omission is reported as
/// data rather than as a build failure, because an author cannot supply a
/// decoder that does not exist yet — failing here would convert a compiler gap
/// into their problem.
///
/// An input that cannot be omitted has no such escape, so it stays a loud
/// failure, and the diagnostic names the two things the author can actually do.
PropertyType? _undecodable({
  required String reason,
  required WidgetConstructorInput input,
  required WidgetVisitorTarget target,
  required String widgetName,
  required String fieldName,
  required String location,
  required List<Issue> issues,
  required List<PropertyExclusion> exclusions,
}) {
  final targetReason = '$reason Target: ${target.name}.';
  if (input.omissible) {
    exclusions.add(
      PropertyExclusion(
        widget: widgetName,
        property: fieldName,
        target: target.name,
        reason: targetReason,
        location: location,
      ),
    );
    return null;
  }
  issues.add(
    Issue(
      code: IssueCode.unsupportedPropertyType,
      message: '$targetReason $widgetName.$fieldName cannot be left out of '
          'generated construction, so it cannot be dropped. Give it a '
          'default so the generated code can omit it, or expose a '
          'catalog-facing wrapper that omits it.',
      location: location,
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
