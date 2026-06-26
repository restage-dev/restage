import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/const_folding.dart';
import 'package:restage_codegen/src/customer_structured_discovery.dart';
import 'package:restage_codegen/src/issue.dart';
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
  })  : widgets = List.unmodifiable(widgets),
        issues = List.unmodifiable(issues),
        structuredTypes = List.unmodifiable(structuredTypes),
        unions = List.unmodifiable(unions);

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
}

/// Walks [library] for classes annotated with `@RestageWidget`. For each:
/// - Extracts the annotation's catalog metadata (name, library, category,
///   description, fires, childrenSlot, deprecatedSince).
/// - Synthesizes `flutterType` from the annotated class's library URI +
///   class name.
/// - Walks `@RestageProperty`-annotated fields, infers each property type
///   from the field's static Dart type, and decodes literal defaults.
///
/// At end-of-pass, detects within-library duplicate widget names (same
/// `(library namespace, name)`) and emits [IssueCode.duplicateWidgetName].
WidgetVisitorResult visitRestageWidgets(
  LibraryElement library,
  AssetId assetId,
) {
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

  for (final cls in widgetClasses) {
    final annotation = firstAnnotation(cls, 'RestageWidget')!;
    final entry =
        _readWidgetAnnotation(cls, annotation, assetId, issues, structured);
    if (entry != null) widgets.add(entry);
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
  );
}

WidgetEntry? _readWidgetAnnotation(
  ClassElement cls,
  ElementAnnotation annotation,
  AssetId assetId,
  List<Issue> issues,
  CustomerStructuredDiscovery structured,
) {
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

  final properties = <PropertyEntry>[];
  for (final field in cls.fields) {
    final propAnnotation = firstAnnotation(field, 'RestageProperty');
    if (propAnnotation == null) continue;
    final p = _readPropertyAnnotation(
      field,
      propAnnotation,
      assetId,
      issues,
      structured,
    );
    // A bad property emits its own issue; keep collecting so a typo on one
    // field doesn't silently drop the entire widget from the catalog.
    if (p != null) properties.add(p);
  }

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
  CustomerStructuredDiscovery structured,
) {
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
  final type = structuredShape?.type ??
      _inferPropertyType(field.type, field, assetId, issues);
  if (type == null) return null;

  // The default generative constructor binds this field — the source of truth
  // for its required-ness and positional-ness.
  final ctorFormal = _defaultConstructorFormalFor(field);

  // The constructor is the source of truth for whether a STRUCTURED property is
  // required: a structured argument the constructor requires must be marked
  // required, or the rich-field emit omits a non-nullable optional field and
  // the generated reconstruction cannot supply the required constructor
  // argument. A genuinely-optional structured property stays optional (the
  // constructor default applies — the documented fail-safe). Scoped to
  // structured so it never forces a required event (which would drop the
  // widget) or perturb a scalar/built-in catalog.
  final required = structuredShape != null
      ? (annotationRequired || (ctorFormal?.isRequired ?? false))
      : annotationRequired;

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

  return PropertyEntry(
    wireId: WireId.unallocatedProperty,
    name: fieldName,
    type: type,
    description: description,
    required: required,
    positional: positional,
    defaultBrandToken: defaultBrandToken,
    defaultSource: resolvedSource,
    structuredRef: structuredShape?.structuredRef,
    valueShape: structuredShape?.valueShape,
  );
}

PropertyType? _inferPropertyType(
  DartType t,
  FieldElement field,
  AssetId assetId,
  List<Issue> issues,
) {
  final inferred = type_inference.inferPropertyType(t);
  if (inferred != null) return inferred;
  final fieldName = field.name ?? '<unnamed>';
  final ownerName = field.enclosingElement.name ?? '<unnamed>';
  issues.add(
    Issue(
      code: IssueCode.unsupportedPropertyType,
      message: 'Unsupported property type ${t.getDisplayString()} '
          'on $ownerName.$fieldName. Supported types: Widget, List<Widget>, '
          'Color, EdgeInsets(Geometry|Directional), '
          'Alignment(Geometry|Directional), FontWeight, bool, int, double, '
          'String, VoidCallback (and similar function types), and any Dart '
          'enum.',
      location: '${assetId.path}#$ownerName.$fieldName',
    ),
  );
  return null;
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
