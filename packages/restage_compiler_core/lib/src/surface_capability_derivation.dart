import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_compiler_core/src/builder_scope_values.dart';
import 'package:restage_compiler_core/src/rfw_program_envelope.dart';
import 'package:restage_compiler_core/src/rfw_scalar_callback_contract.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show kLocalValueSetEventName, kMeasurementPublicationItemArgumentKeyV1;
import 'package:restage_shared/restage_shared.dart'
    show
        LibraryRequirement,
        SurfaceScreenHostDataListShapeV1,
        SurfaceScreenHostDataMapShapeV1,
        SurfaceScreenHostDataNativeBindingShapeV1,
        SurfaceScreenHostDataNullableShapeV1,
        SurfaceScreenHostDataObjectShapeV1,
        SurfaceScreenHostDataSchema,
        SurfaceScreenHostDataShape,
        ValueOperation,
        ValueOperationContext,
        ValueType,
        WidgetVocabulary,
        colorValueType,
        canonicalMaterialColorNames,
        kGroupedWidgetListClientFloor,
        kIconThemeDataFallbackKey,
        kIconThemeDataLerpKey,
        kJoinedStringClientFloor,
        kNativeVoidCallbackType,
        kStandardValueOperations,
        kStructuredCopyWithKey,
        kTextSpanRecognizerDetailCallbacks,
        kTextSpanRecognizerVoidCallbacks,
        kSurfaceFeatureClientFloor,
        valueProgramCapability;
import 'package:restage_shared/rfw_formats.dart' hide WidgetLibrary;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
    show
        Catalog,
        CatalogValueShape,
        ConstructorVariant,
        ListShape,
        PropertyEntry,
        PropertyType,
        RfwConstructorPresenceProtocol,
        ScalarShape,
        StructuredEntry,
        StructuredShape,
        UnionEntry,
        UnionShape,
        WidgetEntry,
        WidgetLibrary,
        WireIdRef,
        kBaselineCatalogVersion,
        svgNativeBindingType;

/// What a surface library needs from a client, read against a catalog.
@immutable
final class SurfaceCapabilityDerivation {
  /// Creates a derivation result.
  const SurfaceCapabilityDerivation({
    required this.builtInFloor,
    required this.requiredLibraries,
    required this.referencedWidgets,
    required this.ambiguousNames,
    required this.unversionedLibraries,
  });

  /// The highest `sinceVersion` over the built-in widgets referenced, and the
  /// surface feature floor, never below [kBaselineCatalogVersion].
  final int builtInFloor;

  /// One requirement per referenced custom library that declares a capability
  /// version, by namespace.
  final List<LibraryRequirement> requiredLibraries;

  /// Every catalog widget referenced, deduplicated, by qualified name.
  final List<WidgetEntry> referencedWidgets;

  /// Widget names that resolve to more than one library, sorted.
  final List<String> ambiguousNames;

  /// Referenced custom libraries without a capability version, by namespace.
  final List<WidgetLibrary> unversionedLibraries;
}

/// The version of generated widget code that writes the current factories.
///
/// Version 2 decodes values built with named constructors, scalar-list fields
/// of data classes and built-in structured properties, and builds widgets that
/// leave out an optional property.
/// Version 3 adds typed deferred callbacks, native integer callback adapters,
/// computed constructor values, and ownership of interactive inline spans.
const int kGeneratedVocabularyVersion = 3;

/// The oldest generated widget code that builds [widget] from a payload, given
/// the shapes its catalog entry and its data classes use.
int generatedCodeFloor(WidgetEntry widget, Catalog catalog) {
  var callbackFloor = 1;
  for (final property in widget.properties) {
    final required = rfwCallbackGeneratedFloor(property, catalog);
    if (required > callbackFloor) callbackFloor = required;
  }
  if (callbackFloor > 1) return callbackFloor;
  final leavesOutProperty = catalog.exclusions.any(
    (exclusion) =>
        exclusion.property.isNotEmpty && exclusion.isOf(widget.flutterType),
  );
  if (leavesOutProperty) return 2;
  final byRef = <(String, String), StructuredEntry>{
    for (final structured in catalog.structuredTypes)
      (structured.library.namespace, structured.wireId.value): structured,
  };
  final seen = <StructuredEntry>{};
  bool needsNewer(WireIdRef? ref) {
    if (ref == null) return false;
    if (WidgetLibrary.builtInByNamespace(ref.library) != null) return true;
    final structured = byRef[(ref.library, ref.wireId.value)];
    if (structured == null || !seen.add(structured)) return false;
    if (structured.variants.any(
      (variant) =>
          variant is ConstructorVariant && variant.namedConstructor != null,
    )) {
      return true;
    }
    return structured.fields.any(
      (field) =>
          _isNewScalarList(field.type) ||
          needsNewer(field.structuredRef ?? _shapeRef(field.valueShape)),
    );
  }

  final nativeTypes = _NativeValueUse(catalog);
  for (final property in widget.properties) {
    // An optional key changes generated construction only when supplied.
    if (nativeTypes.bindingType(property) == 'flutter.Key') continue;
    if (needsNewer(property.structuredRef ?? _shapeRef(property.valueShape))) {
      return 2;
    }
  }
  return 1;
}

/// A scalar-list type a data class field could not carry before version 2.
bool _isNewScalarList(PropertyType type) =>
    type == PropertyType.booleanList ||
    type == PropertyType.integerList ||
    type == PropertyType.realList;

WireIdRef? _shapeRef(CatalogValueShape? shape) => switch (shape) {
      StructuredShape(:final structuredRef) => structuredRef,
      ListShape(:final itemShape) => _shapeRef(itemShape),
      _ => null,
    };

/// Derives what [library] needs from a client, resolving each widget by name
/// against [catalog]. Library-local declarations are not catalog references.
/// [requiresSurfaceFeatureFloor] raises the floor to
/// [kSurfaceFeatureClientFloor].
SurfaceCapabilityDerivation deriveSurfaceCapability(
  RemoteWidgetLibrary library,
  Catalog catalog, {
  bool requiresSurfaceFeatureFloor = false,
  SurfaceScreenHostDataSchema hostDataContract =
      const SurfaceScreenHostDataSchema.empty(),
  Map<String, ValueOperation> operations = kStandardValueOperations,
}) {
  final programScope = RfwProgramScope([
    for (final widget in library.widgets) ...[widget.initialState, widget.root]
  ],
      operations: operations,
      validateNativeBindingReferences: false,
      scopedNativeValues: rfwBuilderScopeValues(library, catalog));
  final referenced = <WidgetEntry>[];
  final ambiguous = <String>{};
  final expressionLibraries = <String>{};
  final nativeValues = _NativeValueUse(catalog, programScope: programScope);
  final canonicalColors = _NativeValueUse(catalog,
      canonicalColors: true,
      operations: operations,
      programScope: programScope);
  final geometryValues = _NativeValueUse(catalog,
      geometry: true, operations: operations, programScope: programScope);
  final expressionValues = _NativeValueUse(catalog,
      expressions: true, operations: operations, programScope: programScope);
  final nativeBindings = _NativeValueUse(catalog,
      bindings: true, operations: operations, programScope: programScope);
  final localWidgets = {
    for (final widget in library.widgets) widget.name: widget,
  };
  final localBudget = _LocalCapabilityBudget();
  var joinsStrings = false;
  var propertyFloor = programScope.requiredCapability > kBaselineCatalogVersion
      ? programScope.requiredCapability
      : kBaselineCatalogVersion;
  for (final widget in library.widgets) {
    _collectReferences(
      widget.root,
      catalog,
      localWidgets,
      referenced,
      ambiguous,
      operations: operations,
      expressionLibraries: expressionLibraries,
      nativeValues: nativeValues,
      canonicalColors: canonicalColors,
      nativeBindings: nativeBindings,
      geometryValues: geometryValues,
      expressionValues: expressionValues,
      localBudget: localBudget,
      onJoinedString: () => joinsStrings = true,
      onPropertyVersion: (version) {
        if (version > propertyFloor) propertyFloor = version;
      },
    );
  }

  var builtInFloor = kBaselineCatalogVersion;
  final customLibraries = <WidgetLibrary>{};
  for (final entry in referenced) {
    if (WidgetLibrary.builtInByNamespace(entry.library.namespace) != null) {
      if (entry.sinceVersion > builtInFloor) builtInFloor = entry.sinceVersion;
    } else if (!(catalog.libraries[entry.library]?.islands ?? false)) {
      customLibraries.add(entry.library);
    }
  }
  final featureFloor = surfaceFeatureClientFloor(library,
      operations: operations, hostDataContract: hostDataContract);
  if (builtInFloor < featureFloor) builtInFloor = featureFloor;
  if (joinsStrings && builtInFloor < kJoinedStringClientFloor) {
    builtInFloor = kJoinedStringClientFloor;
  }
  if (builtInFloor < propertyFloor) builtInFloor = propertyFloor;
  if (requiresSurfaceFeatureFloor &&
      builtInFloor < kSurfaceFeatureClientFloor) {
    builtInFloor = kSurfaceFeatureClientFloor;
  }

  final generatedFloors = <String, int>{};
  for (final entry in referenced) {
    final namespace = entry.library.namespace;
    if (WidgetLibrary.builtInByNamespace(namespace) != null) continue;
    var floor = generatedCodeFloor(entry, catalog);
    if (expressionLibraries.contains(namespace) && floor < 3) floor = 3;
    if (floor > (generatedFloors[namespace] ?? 1)) {
      generatedFloors[namespace] = floor;
    }
  }

  final requiredLibraries = <LibraryRequirement>[];
  final unversioned = <WidgetLibrary>[];
  for (final custom in customLibraries.toList()
    ..sort((a, b) => a.namespace.compareTo(b.namespace))) {
    final version = catalog.libraries[custom]?.capabilityVersion;
    if (version == null) {
      unversioned.add(custom);
    } else {
      requiredLibraries.add(
        LibraryRequirement(
          namespace: custom.namespace,
          minVersion: version,
          minGenerated: generatedFloors[custom.namespace] ?? 1,
        ),
      );
    }
  }

  final byQualifiedName = <String, WidgetEntry>{};
  for (final entry in referenced) {
    byQualifiedName.putIfAbsent(
      WidgetVocabulary.qualifiedName(entry.library.namespace, entry.name),
      () => entry,
    );
  }
  final names = byQualifiedName.keys.toList()..sort();
  return SurfaceCapabilityDerivation(
    builtInFloor: builtInFloor,
    requiredLibraries: List.unmodifiable(requiredLibraries),
    referencedWidgets: List.unmodifiable([
      for (final name in names) byQualifiedName[name]!,
    ]),
    ambiguousNames: List.unmodifiable(ambiguous.toList()..sort()),
    unversionedLibraries: List.unmodifiable(unversioned),
  );
}

/// Whether a raw preview needs native values that only an installed host supplies.
bool nativeBindingsNeedInstalledHost(
        RemoteWidgetLibrary library, Catalog catalog,
        {Map<String, Object?> context = const {}}) =>
    _inspectNativeBindings(library, catalog, previewContext: context).used;

/// Why a screen can only be validated against the app's compiled screen
/// contract.
sealed class CompiledScreenContractNeed {
  const CompiledScreenContractNeed();
}

/// `widget.property` calls an installed app function.
final class AppFunctionCallNeed extends CompiledScreenContractNeed {
  /// The widget and property the call feeds.
  const AppFunctionCallNeed(this.widget, this.property);

  /// The widget the call feeds.
  final String widget;

  /// The property of [widget] the call feeds.
  final String property;
}

/// [widget] is a split widget whose wrapper the catalog does not hold.
final class SplitWidgetNeed extends CompiledScreenContractNeed {
  /// The split widget, named as the app declares it.
  const SplitWidgetNeed(this.widget);

  /// The split widget's name.
  final String widget;
}

/// The first reason, in source order, that [library] can only be validated
/// against the app's compiled screen contract: it calls an installed app
/// function, or places a split widget's wrapper that [catalog] does not hold.
/// Null when it needs neither.
CompiledScreenContractNeed? compiledScreenContractNeed(
  RemoteWidgetLibrary library,
  Catalog catalog,
) {
  final local = {for (final widget in library.widgets) widget.name};
  // A program is JSON text; a callback's nested program is text inside it.
  bool callsApp(Object? json) => switch (json) {
        {'op': 'native.call'} => true,
        Map() => json.values.any(callsApp) ||
            (json['program'] is String &&
                callsApp(_programJson(json['program']))),
        List() => json.any(callsApp),
        _ => false,
      };
  // [widget] and [property] name the nearest constructor argument [node] is in.
  CompiledScreenContractNeed? visit(
    Object? node,
    String widget,
    String property,
  ) {
    CompiledScreenContractNeed? all(Iterable<Object?> nodes) {
      for (final child in nodes) {
        if (visit(child, widget, property) case final need?) return need;
      }
      return null;
    }

    switch (node) {
      case ConstructorCall(:final name, :final arguments):
        if (name.endsWith(kSplitWrapperSuffix) &&
            !local.contains(name) &&
            catalog.widgets.every((entry) => entry.name != name)) {
          return SplitWidgetNeed(
            name.substring(0, name.length - kSplitWrapperSuffix.length),
          );
        }
        for (final MapEntry(:key, :value) in arguments.entries) {
          if (visit(value, name, key) case final need?) return need;
        }
        return null;
      case Map():
        if (callsApp({'program': node['program']})) {
          return AppFunctionCallNeed(widget, property);
        }
        return all(node.values);
      case List():
        return all(node);
      case Loop(:final input, :final output):
        return all([input, output]);
      case Switch(:final input, :final outputs):
        return all([input, ...outputs.values]);
      case WidgetBuilderDeclaration(:final widget):
        return all([widget]);
      case EventHandler(:final eventArguments):
        return all([eventArguments]);
      case SetStateHandler(:final value):
        return all([value]);
    }
    return null;
  }

  for (final declaration in library.widgets) {
    final need = visit(declaration.initialState, declaration.name, 'state') ??
        visit(declaration.root, declaration.name, 'build');
    if (need != null) return need;
  }
  return null;
}

Object? _programJson(Object? program) {
  try {
    return jsonDecode(program! as String);
  } on FormatException {
    return null;
  }
}

/// Validates every native reference at its catalog-linked destination.
void validateRfwNativeReferences(RemoteWidgetLibrary library, Catalog catalog,
    {required RfwProgramScope scope,
    void Function(Object? value, ValueType expected, bool nativeOnly)?
        onReference}) {
  _inspectNativeBindings(library, catalog,
      scope: scope, operations: scope.operations,
      onNativeReference: (value, type, context, nativeOnly) {
    final expected = ValueType.native(type, nullable: true);
    scope.requireNativeValue(value, expected, context: context);
    onReference?.call(value, expected, nativeOnly);
  });
}

_NativeValueUse _inspectNativeBindings(
  RemoteWidgetLibrary library,
  Catalog catalog, {
  Map<String, Object?>? previewContext,
  RfwProgramScope? scope,
  void Function(Object? value, String type, ValueOperationContext? context,
          bool nativeOnly)?
      onNativeReference,
  Map<String, ValueOperation> operations = kStandardValueOperations,
}) {
  final programScope = scope ??
      RfwProgramScope([
        for (final widget in library.widgets) ...[
          widget.initialState,
          widget.root
        ]
      ], operations: operations);
  final bindings = _NativeValueUse(catalog,
      bindings: true,
      previewContext: previewContext,
      onNativeReference: onNativeReference,
      operations: operations,
      programScope: programScope);
  final locals = {for (final widget in library.widgets) widget.name: widget};
  for (final widget in library.widgets) {
    _collectReferences(
        widget.root, catalog, locals, <WidgetEntry>[], <String>{},
        operations: operations,
        expressionLibraries: <String>{},
        nativeValues: bindings,
        canonicalColors: bindings,
        nativeBindings: bindings,
        geometryValues: bindings,
        expressionValues: bindings,
        localBudget: _LocalCapabilityBudget(),
        onJoinedString: () {},
        onPropertyVersion: (_) {});
  }
  return bindings;
}

/// Appends the catalog entry of every non-local constructor under [node] to
/// [out]; a name found in more than one library goes to [ambiguous]. A string
/// slot given a list of parts calls [onJoinedString], and each property set
/// reports its [PropertyEntry.sinceVersion] to [onPropertyVersion].
void _collectReferences(
  Object? node,
  Catalog catalog,
  Map<String, WidgetDeclaration> localWidgets,
  List<WidgetEntry> out,
  Set<String> ambiguous, {
  required Map<String, ValueOperation> operations,
  required Set<String> expressionLibraries,
  required _NativeValueUse nativeValues,
  required _NativeValueUse canonicalColors,
  required _NativeValueUse nativeBindings,
  required _NativeValueUse geometryValues,
  required _NativeValueUse expressionValues,
  required void Function() onJoinedString,
  required void Function(int version) onPropertyVersion,
  required _LocalCapabilityBudget localBudget,
  Map<String, _CapabilityValue> argumentBindings = const {},
  Set<String> activeLocals = const {},
  ValueOperationContext? lexicalContext,
}) {
  lexicalContext ??= ValueOperationContext(operations: operations);
  void visit(Object? child, {ValueOperationContext? context}) =>
      _collectReferences(
        child,
        catalog,
        localWidgets,
        out,
        ambiguous,
        operations: operations,
        expressionLibraries: expressionLibraries,
        nativeValues: nativeValues,
        canonicalColors: canonicalColors,
        nativeBindings: nativeBindings,
        geometryValues: geometryValues,
        expressionValues: expressionValues,
        onJoinedString: onJoinedString,
        onPropertyVersion: onPropertyVersion,
        localBudget: localBudget,
        argumentBindings: argumentBindings,
        activeLocals: activeLocals,
        lexicalContext: context ?? lexicalContext,
      );
  final envelope = decodeRfwProgramEnvelope(node,
      operations: operations, context: lexicalContext);
  if (envelope != null) {
    for (final capture in envelope.captures.values) visit(capture);
    final child = lexicalContext.nested(locals: envelope.values.locals);
    for (final body in envelope.bodies) visit(body.widget, context: child);
    return;
  }
  switch (node) {
    case ConstructorCall(:final name, :final arguments):
      final local = localWidgets[name];
      if (local != null) {
        if (activeLocals.contains(name) || !localBudget.expand()) {
          onPropertyVersion(
            _localValueFloor(
              name,
              localWidgets,
              catalog,
              expressionLibraries,
              nativeValues,
              canonicalColors,
              nativeBindings,
              geometryValues,
              expressionValues,
              {
                for (final entry in arguments.entries)
                  entry.key: _CapabilityValue(
                      entry.value, argumentBindings, lexicalContext),
              },
            ),
          );
        } else {
          _collectReferences(
            local.root,
            catalog,
            localWidgets,
            out,
            ambiguous,
            operations: operations,
            expressionLibraries: expressionLibraries,
            nativeValues: nativeValues,
            canonicalColors: canonicalColors,
            nativeBindings: nativeBindings,
            geometryValues: geometryValues,
            expressionValues: expressionValues,
            onJoinedString: onJoinedString,
            onPropertyVersion: onPropertyVersion,
            localBudget: localBudget,
            argumentBindings: {
              for (final entry in arguments.entries)
                entry.key: _CapabilityValue(
                    entry.value, argumentBindings, lexicalContext),
            },
            activeLocals: {
              ...activeLocals,
              name,
            },
            lexicalContext: lexicalContext,
          );
        }
      } else {
        final candidates = [
          for (final widget in catalog.widgets)
            if (widget.name == name) widget,
        ];
        if (candidates.map((c) => c.library).toSet().length > 1) {
          ambiguous.add(name);
        } else if (candidates.isNotEmpty) {
          final entry = candidates.first;
          out.add(entry);
          final builtIn =
              WidgetLibrary.builtInByNamespace(entry.library.namespace) != null;
          for (final property in entry.properties) {
            if (!arguments.containsKey(property.name)) {
              if (property.required &&
                  (property.type == PropertyType.scalarCallback ||
                      property.type == PropertyType.widgetBuilder)) {
                throw const FormatException(
                  'Missing required native callback.',
                );
              }
              continue;
            }
            if (property.constructorNullable &&
                (property.type == PropertyType.widgetBuilder ||
                    property.type == PropertyType.scalarCallback) &&
                normalizeRfwCallbackPresence(
                      arguments[property.name],
                      property,
                    ) ==
                    null) {
              continue;
            }
            onPropertyVersion(
              validateRfwPropertyCallbacks(
                arguments[property.name],
                property,
                catalog,
                operations: operations,
                scope: expressionValues.programScope,
              ),
            );
            final scoped = _CapabilityValue(
                arguments[property.name], argumentBindings, lexicalContext);
            if (!builtIn &&
                expressionValues.uses(scoped, property,
                    root: _CapabilityValue(
                        arguments, argumentBindings, lexicalContext))) {
              expressionLibraries.add(entry.library.namespace);
            }
            if (geometryValues.uses(scoped, property)) {
              onPropertyVersion(_geometryFloor);
              if (!builtIn &&
                  geometryValues.uses(scoped, property, factory: true)) {
                expressionLibraries.add(entry.library.namespace);
              }
            }
            final usesNativeBinding = nativeBindings.uses(scoped, property);
            if (canonicalColors.uses(scoped, property) || usesNativeBinding) {
              onPropertyVersion(24);
            }
            // A supplied Key slot needs the new factory even when the
            // existing constructor-presence envelope supplies null.
            if (!builtIn && nativeBindings.usesKeyFactory(scoped, property)) {
              expressionLibraries.add(entry.library.namespace);
            }
            if (nativeValues.uses(scoped, property)) {
              onPropertyVersion(valueProgramCapability);
              if (!builtIn &&
                  nativeValues.uses(scoped, property, factory: true)) {
                expressionLibraries.add(entry.library.namespace);
              }
            }
            if (property.type == PropertyType.inlineSpan &&
                _usesInlineSpanFeature(
                    scoped, _InlineSpanFeature.recursiveChildren)) {
              onPropertyVersion(24);
            }
            final interactiveSpan = property.type == PropertyType.inlineSpan &&
                _usesInlineSpanFeature(scoped, _InlineSpanFeature.recognizer);
            if (interactiveSpan) {
              onPropertyVersion(_interactiveSpanFloor);
              if (!builtIn) expressionLibraries.add(entry.library.namespace);
            }
            if (builtIn &&
                (property.type != PropertyType.inlineSpan || interactiveSpan) &&
                (nativeBindings.bindingType(property) != 'flutter.Key' ||
                    usesNativeBinding)) {
              onPropertyVersion(property.sinceVersion);
            }
            if (property.type == PropertyType.string &&
                _carriesList(arguments[property.name])) {
              onJoinedString();
            }
          }
        }
      }
      arguments.values.forEach(visit);
    case List<Object?>():
      node.forEach(visit);
    case Switch(:final outputs):
      outputs.values.forEach(visit);
    case Loop(:final output):
      visit(output);
    case WidgetBuilderDeclaration(:final widget):
      visit(widget);
    case Map<Object?, Object?>():
      node.values.forEach(visit);
  }
}

final class _CapabilityValue {
  const _CapabilityValue(this.value, this.arguments,
      [this.lexicalContext, this.projectionExhausted = false]);
  final Object? value;
  final Map<String, _CapabilityValue> arguments;
  final ValueOperationContext? lexicalContext;
  // A bounded approximation cannot stand in for a genuine formal reference
  // when proving authority at a native consumer.
  final bool projectionExhausted;
}

final class _LocalCapabilityBudget {
  int _remaining = 4096;
  bool expand() => _remaining-- > 0;
}

const _interactiveSpanFloor = 22;
const _geometryFloor = 17;

enum _InlineSpanPosition { span, children, child, recognizer }

enum _InlineSpanFeature { recognizer, recursiveChildren }

// Resolve only statically known local argument projections. The visitor retains
// the catalog type at the destination; unrelated maps are never scanned.
bool _visitCapabilityValue(
  _CapabilityValue scoped,
  bool Function(_CapabilityValue, int depth) visitor, {
  bool unresolvedArguments = false,
  List<Object> path = const [],
  int depth = 0,
  bool preserveLoops = false,
  bool Function(_CapabilityValue)? onLimit,
}) {
  if (depth > 128) return onLimit?.call(scoped) ?? true;
  bool visit(
    Object? value, {
    List<Object>? remaining,
    Map<String, _CapabilityValue>? bindings,
    ValueOperationContext? lexicalContext,
    bool projectionExhausted = false,
  }) =>
      _visitCapabilityValue(
        _CapabilityValue(
            value,
            bindings ?? scoped.arguments,
            lexicalContext ?? scoped.lexicalContext,
            projectionExhausted || scoped.projectionExhausted),
        visitor,
        unresolvedArguments: unresolvedArguments,
        path: remaining ?? path,
        depth: depth + 1,
        preserveLoops: preserveLoops,
        onLimit: onLimit,
      );
  switch (scoped.value) {
    case final _CapabilityValue bound:
      return visit(bound.value,
          bindings: bound.arguments,
          lexicalContext: bound.lexicalContext,
          projectionExhausted: bound.projectionExhausted);
    case ArgsReference(:final parts):
      if (unresolvedArguments &&
          (parts.isEmpty || !scoped.arguments.containsKey(parts.first))) {
        return visitor(scoped, depth);
      }
      return visit(
        scoped.arguments,
        remaining: [...parts, ...path],
        bindings: const {},
      );
    case BoundArgsReference(:final arguments, :final parts):
      return visit(arguments, remaining: [...parts, ...path]);
    case Switch(:final outputs):
      return outputs.values.any(visit);
    case Loop(:final output):
      if (preserveLoops && path.isEmpty) return visitor(scoped, depth);
      return visit(output);
    case Map<Object?, Object?>():
      final value = scoped.value! as Map<Object?, Object?>;
      if (path.isNotEmpty) {
        return visit(value[path.first], remaining: path.skip(1).toList());
      }
    case List<Object?>():
      final value = scoped.value! as List<Object?>;
      if (path.isNotEmpty) {
        final index = path.first;
        return index is int &&
            index >= 0 &&
            index < value.length &&
            visit(value[index], remaining: path.skip(1).toList());
      }
  }
  return visitor(scoped, depth);
}

// A child-list loop can contribute zero slots. Ordinary entries always occupy
// one slot, including malformed entries that decode as an empty TextSpan.
bool _spanChildrenMayBeEmpty(_CapabilityValue scoped,
        {required bool unresolvedArguments, int depth = 0}) =>
    _visitCapabilityValue(scoped, (resolved, resolvedDepth) {
      final value = resolved.value;
      if (value is! List) return true;
      return value.every((child) => _visitCapabilityValue(
              _CapabilityValue(
                  child,
                  resolved.arguments,
                  resolved.lexicalContext,
                  resolved.projectionExhausted), (entry, entryDepth) {
            final loop = entry.value;
            return loop is Loop &&
                _spanChildrenMayBeEmpty(
                    _CapabilityValue(loop.input, entry.arguments,
                        entry.lexicalContext, entry.projectionExhausted),
                    unresolvedArguments: unresolvedArguments,
                    depth: entryDepth + 1);
          },
              unresolvedArguments: unresolvedArguments,
              depth: resolvedDepth + 1,
              preserveLoops: true));
    },
        unresolvedArguments: unresolvedArguments,
        depth: depth,
        preserveLoops: true);

bool _usesInlineSpanFeature(
  _CapabilityValue scoped,
  _InlineSpanFeature feature, {
  _InlineSpanPosition position = _InlineSpanPosition.span,
  bool unresolvedArguments = false,
  int depth = 0,
}) =>
    _visitCapabilityValue(
      scoped,
      (resolved, resolvedDepth) {
        bool visit(Object? value, _InlineSpanPosition nestedPosition) =>
            _usesInlineSpanFeature(
              _CapabilityValue(value, resolved.arguments,
                  resolved.lexicalContext, resolved.projectionExhausted),
              feature,
              position: nestedPosition,
              unresolvedArguments: unresolvedArguments,
              depth: resolvedDepth + 1,
            );
        final recursive = feature == _InlineSpanFeature.recursiveChildren;
        switch (resolved.value) {
          case Map<Object?, Object?>():
            final value = resolved.value! as Map<Object?, Object?>;
            if (position == _InlineSpanPosition.recognizer) return !recursive;
            if (position != _InlineSpanPosition.span &&
                position != _InlineSpanPosition.child) return false;
            return (!recursive &&
                    visit(
                        value['recognizer'], _InlineSpanPosition.recognizer)) ||
                visit(value['children'], _InlineSpanPosition.children);
          case List<Object?>():
            if (position != _InlineSpanPosition.children &&
                position != _InlineSpanPosition.child) return false;
            if (recursive &&
                (position == _InlineSpanPosition.child ||
                    _spanChildrenMayBeEmpty(resolved,
                        unresolvedArguments: unresolvedArguments,
                        depth: resolvedDepth + 1))) return true;
            return (resolved.value! as List<Object?>)
                .any((child) => visit(child, _InlineSpanPosition.child));
          case Loop(:final input, :final output):
            if (position != _InlineSpanPosition.children &&
                position != _InlineSpanPosition.child) return false;
            if (recursive &&
                position == _InlineSpanPosition.children &&
                _spanChildrenMayBeEmpty(
                    _CapabilityValue(input, resolved.arguments,
                        resolved.lexicalContext, resolved.projectionExhausted),
                    unresolvedArguments: unresolvedArguments,
                    depth: resolvedDepth + 1)) return true;
            return visit(output, _InlineSpanPosition.child);
          case Reference():
            // An unresolved value in a typed span slot may carry either feature.
            return !recursive || position != _InlineSpanPosition.recognizer;
          default:
            return false;
        }
      },
      unresolvedArguments: unresolvedArguments,
      depth: depth,
      preserveLoops: true,
    );

// Normalize only argument projections, retaining each resulting map's caller
// scope. This lets bounded fallback recognize a stable recursive call without
// following an ever-growing chain of equivalent argument aliases.
_CapabilityValue _projectCapabilityArgument(_CapabilityValue value) {
  final alternatives = <_CapabilityValue>[];
  _visitCapabilityValue(
    value,
    (resolved, _) {
      alternatives.add(resolved);
      return false;
    },
    onLimit: (scoped) {
      alternatives.add(_CapabilityValue(
          const DataReference([]), const {}, scoped.lexicalContext, true));
      return false;
    },
  );
  if (alternatives.length == 1) return alternatives.single;
  return _CapabilityValue(
    Switch(false, {
      for (var index = 0; index < alternatives.length; index++)
        index: alternatives[index],
    }),
    const {},
  );
}

bool _sameCapabilityArguments(
  Map<String, _CapabilityValue> left,
  Map<String, _CapabilityValue> right,
) =>
    left.length == right.length &&
    left.entries.every((entry) {
      final other = right[entry.key];
      final value = entry.value.value;
      return other != null &&
          entry.value.projectionExhausted == other.projectionExhausted &&
          value == other.value &&
          (value == null ||
              value is num ||
              value is String ||
              value is bool ||
              identical(entry.value.arguments, other.arguments));
    });

// Once ordinary expansion stops, retain incoming scopes while inspecting the
// same typed destinations. A second bound limits recursive graphs. Beyond it,
// unresolved values on decoder-read paths qualify conservatively.
int _localValueFloor(
  String name,
  Map<String, WidgetDeclaration> locals,
  Catalog catalog,
  Set<String> expressionLibraries,
  _NativeValueUse nativeValues,
  _NativeValueUse canonicalColors,
  _NativeValueUse nativeBindings,
  _NativeValueUse geometryValues,
  _NativeValueUse expressionValues,
  Map<String, _CapabilityValue> arguments,
) {
  var remaining = 4096;
  var floor = kBaselineCatalogVersion;
  final unresolvedLocals = <String>{};
  final active = <String, List<Map<String, _CapabilityValue>>>{};
  late void Function(
    Object?,
    Map<String, _CapabilityValue>,
    int, {
    bool unresolved,
    bool projectionExhausted,
  }) visit;
  void visitLocal(
    String name,
    Map<String, _CapabilityValue> bindings,
    int depth,
  ) {
    final projected = {
      for (final entry in bindings.entries)
        entry.key: _projectCapabilityArgument(entry.value),
    };
    final states = active.putIfAbsent(name, () => []);
    if (states.any((state) => _sameCapabilityArguments(state, projected))) {
      return;
    }
    states.add(projected);
    visit(locals[name]?.root, projected, depth);
    states.removeLast();
  }

  visit = (
    node,
    bindings,
    depth, {
    unresolved = false,
    projectionExhausted = false,
  }) {
    void child(Object? value) => visit(value, bindings, depth,
        unresolved: unresolved, projectionExhausted: projectionExhausted);
    switch (node) {
      case ConstructorCall(:final name, :final arguments):
        final local = locals[name];
        if (local != null) {
          if (unresolved || depth >= 64 || remaining-- <= 0) {
            if (unresolvedLocals.add(name)) {
              visit(local.root, const {}, 0,
                  unresolved: true, projectionExhausted: true);
            }
          } else {
            visitLocal(
              name,
              {
                for (final entry in arguments.entries)
                  entry.key: _CapabilityValue(
                      entry.value, bindings, null, projectionExhausted),
              },
              depth + 1,
            );
          }
        } else {
          for (final widget
              in catalog.widgets.where((entry) => entry.name == name)) {
            final builtIn =
                WidgetLibrary.builtInByNamespace(widget.library.namespace) !=
                    null;
            for (final property in widget.properties) {
              if (!arguments.containsKey(property.name)) continue;
              final scoped = _CapabilityValue(arguments[property.name],
                  bindings, null, projectionExhausted);
              if (!builtIn &&
                  expressionValues.uses(scoped, property,
                      root: _CapabilityValue(
                          arguments, bindings, null, projectionExhausted),
                      unresolvedArguments: true)) {
                expressionLibraries.add(widget.library.namespace);
              }
              if (geometryValues.uses(scoped, property,
                  unresolvedArguments: true)) {
                if (_geometryFloor > floor) floor = _geometryFloor;
                if (!builtIn &&
                    geometryValues.uses(scoped, property,
                        factory: true, unresolvedArguments: true)) {
                  expressionLibraries.add(widget.library.namespace);
                }
              }
              final usesNativeBinding = nativeBindings.uses(scoped, property,
                  unresolvedArguments: true);
              if ((canonicalColors.uses(scoped, property,
                          unresolvedArguments: true) ||
                      usesNativeBinding) &&
                  floor < 24) floor = 24;
              if (!builtIn &&
                  nativeBindings.usesKeyFactory(scoped, property,
                      unresolvedArguments: true)) {
                expressionLibraries.add(widget.library.namespace);
              }
              if (nativeValues.uses(
                scoped,
                property,
                unresolvedArguments: true,
              )) {
                if (valueProgramCapability > floor) {
                  floor = valueProgramCapability;
                }
                if (!builtIn &&
                    nativeValues.uses(
                      scoped,
                      property,
                      factory: true,
                      unresolvedArguments: true,
                    )) {
                  expressionLibraries.add(widget.library.namespace);
                }
              }
              if (property.type == PropertyType.inlineSpan &&
                  _usesInlineSpanFeature(
                      scoped, _InlineSpanFeature.recursiveChildren,
                      unresolvedArguments: true)) {
                if (floor < 24) floor = 24;
              }
              if (property.type == PropertyType.inlineSpan &&
                  _usesInlineSpanFeature(scoped, _InlineSpanFeature.recognizer,
                      unresolvedArguments: true)) {
                if (_interactiveSpanFloor > floor) {
                  floor = _interactiveSpanFloor;
                }
                if (!builtIn) {
                  expressionLibraries.add(widget.library.namespace);
                } else if (property.sinceVersion > floor) {
                  floor = property.sinceVersion;
                }
              }
            }
          }
        }
        arguments.values.forEach(child);
      case Switch(:final outputs):
        outputs.values.forEach(child);
      case List<Object?>():
        node.forEach(child);
      case Map<Object?, Object?>():
        node.values.forEach(child);
      case Loop(:final output):
        child(output);
      case WidgetBuilderDeclaration(:final widget):
        child(widget);
    }
  };
  visitLocal(name, arguments, 0);
  return floor;
}

bool _carriesList(Object? value) => switch (value) {
      List<Object?>() => true,
      Switch(:final outputs) => outputs.values.any(_carriesList),
      _ => false,
    };

// Follow catalog fields and the closed nested paths read by native decoders.
final class _NativeValueUse {
  _NativeValueUse(Catalog catalog,
      {this.canonicalColors = false,
      this.bindings = false,
      this.expressions = false,
      this.geometry = false,
      this.operations = const {},
      this.programScope,
      this.previewContext,
      this.onNativeReference})
      : structured = {
          for (final entry in catalog.structuredTypes)
            (entry.library.namespace, entry.wireId.value): entry,
        },
        unions = {
          for (final entry in catalog.unions)
            (entry.library.namespace, entry.wireId.value): entry,
        };

  // Native style records and computed scalars share scoped, bounded traversal.
  // Computed values additionally cover each scalar read of the native decoders.
  final bool canonicalColors;
  final bool bindings;
  final Map<String, Object?>? previewContext;
  final void Function(Object? value, String type,
      ValueOperationContext? context, bool nativeOnly)? onNativeReference;
  bool used = false;
  final bool expressions;
  final bool geometry;
  final Map<String, ValueOperation> operations;
  final RfwProgramScope? programScope;

  final Map<(String, String), StructuredEntry> structured;
  final Map<(String, String), UnionEntry> unions;

  String? bindingType(PropertyEntry property) {
    final shape = property.valueShape;
    final ref = property.structuredRef ??
        (shape is StructuredShape ? shape.structuredRef : null);
    if (property.type != PropertyType.structured || ref == null) return null;
    final entry = structured[(ref.library, ref.wireId.value)];
    return entry == null ? null : _bindingSourceType(entry);
  }

  // A marker-only presence envelope supplies null and needs the key-aware
  // factory. A missing forwarded outer argument still means omission. The
  // existing presence wire format itself adds no native-binding SDK floor.
  bool usesKeyFactory(_CapabilityValue scoped, PropertyEntry property,
          {bool unresolvedArguments = false}) =>
      bindingType(property) == 'flutter.Key' &&
      _NativeValue(scoped, unresolvedArguments: unresolvedArguments)
          .any((node) => node.value != null);

  bool uses(
    _CapabilityValue scoped,
    PropertyEntry property, {
    bool factory = false,
    bool unresolvedArguments = false,
    _CapabilityValue? root,
  }) {
    final found = _NativeValue(scoped,
            root: root,
            unresolvedArguments: unresolvedArguments,
            requiresNativeProjection: _requiresNativeProjection(property.type,
                shape: property.valueShape, ref: property.structuredRef))
        .any((value) => _uses(value, property, factory: factory));
    used |= found;
    return found;
  }

  Object? _previewValue(DataReference value) {
    Object? actual = previewContext;
    for (final part in value.parts.skip(1)) {
      actual = switch (actual) {
        Map<Object?, Object?>() when actual.containsKey(part) => actual[part],
        List<Object?>() when part is int && part >= 0 && part < actual.length =>
          actual[part],
        _ => missing,
      };
    }
    return actual;
  }

  bool _previewAny(_NativeValue node, bool Function(_NativeValue) visitor,
          {bool preserveLoops = false}) =>
      node.any((resolved) {
        if (previewContext == null) return visitor(resolved);
        final value = resolved.value;
        final actual = value is DataReference &&
                value.parts.isNotEmpty &&
                value.parts.first == 'context'
            ? _previewValue(value)
            : value;
        return visitor(
            identical(actual, value) ? resolved : resolved.child(actual));
      }, preserveLoops: preserveLoops);

  bool _unavailableNativeValue(Object? value) =>
      previewContext != null &&
      (identical(value, missing) || _isNativeReference(value));

  bool _isNativeReference(Object? value) =>
      value is Map &&
      value['kind'] == 'nativeBinding' &&
      value['key'] is String &&
      value['type'] is String &&
      value['nullable'] is bool;

  bool _uses(
    _NativeValue node,
    PropertyEntry property, {
    bool factory = false,
  }) {
    final value = node.value;
    final actual = RfwConstructorPresenceProtocol.appliesTo(property) &&
            value is Map &&
            _maySelect(
              node.child(value[RfwConstructorPresenceProtocol.markerKey]),
              {RfwConstructorPresenceProtocol.version},
            )
        ? value[RfwConstructorPresenceProtocol.valueKey]
        : value;
    return visit(
      node.child(actual),
      property.type,
      shape: property.valueShape,
      ref: property.structuredRef,
      factory: factory,
      // An event with no derivable type accepts no native callback.
      event: property.type == PropertyType.event
          ? eventNativeType(property) ?? 'unsupported'
          : null,
    );
  }

  bool visit(
    _NativeValue node,
    PropertyType type, {
    CatalogValueShape? shape,
    WireIdRef? ref,
    bool factory = false,
    String? event,
  }) {
    return node
        .withNativeProjection(
            _requiresNativeProjection(type, shape: shape, ref: ref),
            inherit: false)
        .any(
          (resolved) => _visit(resolved, type,
              shape: shape, ref: ref, factory: factory, event: event),
        );
  }

  bool _requiresNativeProjection(PropertyType type,
          {CatalogValueShape? shape, WireIdRef? ref}) =>
      onNativeReference != null &&
      _bindingPotential(type, shape: shape, ref: ref, forAdmission: true);

  bool _visit(
    _NativeValue node,
    PropertyType type, {
    CatalogValueShape? shape,
    WireIdRef? ref,
    bool factory = false,
    String? event,
  }) {
    final value = node.value;
    if (bindings) {
      return _bindingValue(node, type, shape: shape, ref: ref, event: event);
    }
    if (geometry) {
      if (value is Reference) {
        return _potential(type, shape: shape, ref: ref, factory: factory);
      }
      return _geometryNative(node, type, factory: factory) ??
          _catalogValue(node, type, shape: shape, ref: ref, factory: factory);
    }
    if (expressions && !_readsScalar(type, shape: shape, ref: ref))
      return false;
    if (expressions &&
        decodeRfwProgramEnvelope(value,
                operations: operations, scope: programScope) !=
            null) {
      return true;
    }
    if (expressions) {
      final native = _computedNative(node, type);
      if (native != null) return native;
      final itemFields = switch (type) {
        PropertyType.fontFeatureList => const ['feature', 'value'],
        PropertyType.fontVariationList => const ['axis', 'value'],
        PropertyType.selectionOptionList => const ['value', 'label'],
        _ => const <String>[],
      };
      if (itemFields.isNotEmpty &&
          _items(node, (item) => _scalarFields(item, itemFields))) return true;
      if (type == PropertyType.offset && _scalarFields(node, const ['x', 'y']))
        return true;
    }
    // These factory calls already delegate their nested values to shared code.
    if (factory &&
        (type == PropertyType.textDecoration ||
            type == PropertyType.shadowList ||
            type == PropertyType.border ||
            type == PropertyType.shapeBorder ||
            type == PropertyType.inlineSpan)) {
      return false;
    }
    if (node.unresolvedArguments && value is Reference) {
      return _potential(type, shape: shape, ref: ref, factory: factory);
    }
    switch (type) {
      case PropertyType.color:
        if (canonicalColors) {
          return value is Map &&
              value.containsKey('material') &&
              node.child(value['material']).any((token) {
                final value = token.value;
                if (value is Reference ||
                    decodeRfwProgramEnvelope(value, operations: operations) !=
                        null) return true;
                if (value == '') return false;
                if (canonicalMaterialColorNames.contains(value)) return true;
                throw const FormatException('Unknown Material color');
              });
        }
        final fields =
            colorValueType.fields.keys.where((key) => key != 'material');
        return expressions
            ? _scalarFields(node, colorValueType.fields.keys)
            : value is Map && fields.every(value.containsKey);
      case PropertyType.fontWeight:
        return !canonicalColors && !expressions && value is int;
      case PropertyType.textDecoration:
        return !canonicalColors && !expressions && value is int ||
            value is List && value.any((item) => visit(node.child(item), type));
      case PropertyType.paint:
        return value is Map &&
            (_scalarFields(node, const [
                  'blendMode',
                  'isAntiAlias',
                  'style',
                  'strokeWidth',
                  'strokeCap',
                  'strokeJoin',
                  'strokeMiterLimit',
                  'filterQuality',
                  'invertColors'
                ]) ||
                visit(node.child(value['color']), PropertyType.color) ||
                _colorFilter(node.child(value['colorFilter'])));
      case PropertyType.gradient:
        return value is Map &&
            _maySelect(
              node.child(value['type']),
              const {'linear', 'radial', 'sweep'},
            ) &&
            _items(
              node.child(value['colors']),
              (item) => visit(item, PropertyType.color),
            );
      case PropertyType.boxShadowList:
      case PropertyType.shadowList:
        return _items(node, _shadow);
      case PropertyType.border:
        return _items(node, _shadow);
      case PropertyType.shapeBorder:
        return value is List
            ? value.any((item) => visit(node.child(item), type))
            : value is Map &&
                _maySelect(node.child(value['type']), const {
                  'rounded',
                  'roundedSuperellipse',
                  'circle',
                  'stadium',
                  'continuous',
                  'beveled',
                  'linear',
                  'star',
                  'polygon',
                }) &&
                _shadow(node.child(value['side']));
      case PropertyType.inlineSpan:
        return value is Map &&
            (_scalarFields(
                    node, const ['text', 'semanticsLabel', 'spellOut']) ||
                _textStyle(node.child(value['style'])) ||
                _spanChildren(node.child(value['children'])));
      case PropertyType.widget:
      case PropertyType.widgetList:
      case PropertyType.widgetBuilder:
      case PropertyType.scalarCallback:
      case PropertyType.length:
      case PropertyType.edgeInsets:
      case PropertyType.alignment:
      case PropertyType.alignmentXY:
      case PropertyType.offset:
      case PropertyType.duration:
      case PropertyType.curve:
      case PropertyType.boolean:
      case PropertyType.integer:
      case PropertyType.real:
      case PropertyType.string:
      case PropertyType.stringList:
      case PropertyType.booleanList:
      case PropertyType.integerList:
      case PropertyType.realList:
      case PropertyType.event:
      case PropertyType.dataReference:
      case PropertyType.enumValue:
      case PropertyType.locale:
      case PropertyType.fontFeatureList:
      case PropertyType.fontVariationList:
      case PropertyType.structured:
      case PropertyType.decorationImage:
      case PropertyType.selectionOptionList:
      case PropertyType.unknown:
        break;
    }
    if (expressions &&
        const {
          PropertyType.string,
          PropertyType.stringList,
          PropertyType.booleanList,
          PropertyType.integerList,
          PropertyType.realList,
        }.contains(type)) {
      return _items(node, (item) => visit(item, PropertyType.string));
    }
    return _catalogValue(node, type, shape: shape, ref: ref, factory: factory);
  }

  bool _bindingValue(_NativeValue node, PropertyType type,
      {CatalogValueShape? shape, WireIdRef? ref, String? event}) {
    final value = node.value;
    if (previewContext != null && identical(value, missing))
      return _bindingPotential(type, shape: shape, ref: ref);
    if (previewContext != null &&
        value is DataReference &&
        value.parts.isNotEmpty &&
        value.parts.first == 'context') {
      final actual = _previewValue(value);
      return identical(actual, missing)
          ? _bindingPotential(type, shape: shape, ref: ref)
          : _bindingValue(node.child(actual), type, shape: shape, ref: ref);
    }
    if (previewContext != null &&
        _isNativeReference(value) &&
        _bindingPotential(type, shape: shape, ref: ref)) return true;
    if (type == PropertyType.scalarCallback &&
        value is Map &&
        value.containsKey('nativeKeyIndex')) {
      if (onNativeReference != null) {
        _bindingReference(
            node.child(value['nativeKeyIndex']), 'flutter.ChildIndexGetter',
            strict: true);
        return false;
      }
      return true;
    }
    if (type == PropertyType.event &&
        value is Map &&
        value.containsKey('nativeEvent')) {
      // A typed event takes the app's callback of exactly its type.
      return _bindingReference(
          node.child(value['nativeEvent']), event ?? kNativeVoidCallbackType,
          strict: true);
    }
    if (type == PropertyType.color &&
        _bindingReference(node, 'flutter.Color')) {
      return true;
    }
    if (value is Map) {
      switch (type) {
        case PropertyType.inlineSpan:
          if (_gestureRecognizer(node.child(value['recognizer'])) ||
              _textStyle(node.child(value['style'])) ||
              _spanChildren(node.child(value['children']))) return true;
        case PropertyType.paint:
          if (visit(node.child(value['color']), PropertyType.color) ||
              _colorFilter(node.child(value['colorFilter']))) return true;
        case PropertyType.gradient:
          if (_items(node.child(value['colors']),
              (item) => visit(item, PropertyType.color))) return true;
        case PropertyType.shapeBorder:
          if (_shadow(node.child(value['side']))) return true;
        default:
          break;
      }
    }
    if (const {
          PropertyType.shadowList,
          PropertyType.boxShadowList,
          PropertyType.border
        }.contains(type) &&
        _items(node, _shadow)) return true;
    return _catalogValue(node, type, shape: shape, ref: ref);
  }

  bool _bindingPotential(PropertyType type,
      {CatalogValueShape? shape,
      WireIdRef? ref,
      Set<(String, String)> seen = const {},
      bool forAdmission = false}) {
    // Unknown or unresolved metadata cannot prove a destination ordinary.
    if (forAdmission &&
        const {PropertyType.event, PropertyType.scalarCallback}
            .contains(type)) {
      return true;
    }
    if (const {
      PropertyType.color,
      PropertyType.inlineSpan,
      PropertyType.paint,
      PropertyType.gradient,
      PropertyType.boxShadowList,
      PropertyType.shadowList,
      PropertyType.border,
      PropertyType.shapeBorder,
    }.contains(type)) return true;
    if (shape is ListShape) {
      return _bindingPotential(shape.itemShape.propertyType,
          shape: shape.itemShape, seen: seen, forAdmission: forAdmission);
    }
    if (forAdmission && shape is UnionShape) {
      final union =
          unions[(shape.unionRef.library, shape.unionRef.wireId.value)];
      if (union == null) return true;
      return union.members.any((member) => _bindingPotential(
          PropertyType.structured,
          ref: member,
          seen: seen,
          forAdmission: forAdmission));
    }
    final target =
        ref ?? (shape is StructuredShape ? shape.structuredRef : null);
    if (target == null) {
      if (forAdmission &&
          type == PropertyType.unknown &&
          shape is ScalarShape &&
          (shape.isOpaqueRecord || shape.isOpaqueStringKeyedMap)) return false;
      return forAdmission &&
          const {PropertyType.structured, PropertyType.unknown}.contains(type);
    }
    final key = (target.library, target.wireId.value);
    if (seen.contains(key)) return false;
    final entry = structured[key];
    if (entry == null) return forAdmission;
    return (_bindingSourceType(entry) != null ||
        forAdmission &&
            (_sharedFactoryType(entry.sourceType) ||
                _nativeStyleType(entry.sourceType) ||
                entry.library.namespace == 'restage.svg' &&
                    _svgNativeType(entry.sourceType)) ||
        entry.fields.any((field) => _bindingPotential(field.type,
            shape: field.valueShape ??
                (!forAdmission || field.unionRef == null
                    ? null
                    : UnionShape(
                        propertyType: PropertyType.unknown,
                        unionRef: field.unionRef!)),
            ref: field.structuredRef,
            seen: {...seen, key},
            forAdmission: forAdmission)));
  }

  bool _gestureRecognizer(_NativeValue node) => _previewAny(node, (record) {
        final value = record.value;
        if (_unavailableNativeValue(value)) return true;
        if (value is! Map)
          return _bindingReference(record, 'flutter.GestureRecognizer');
        if (value.containsKey('borrowed')) {
          return _bindingReference(
              record.child(value['borrowed']), 'flutter.GestureRecognizer',
              strict: true);
        }
        var found = _bindingReference(record, 'flutter.GestureRecognizer');
        for (final kind in kTextSpanRecognizerDetailCallbacks.entries) {
          if (!_maySelect(record.child(value['kind']), {kind.key})) continue;
          for (final setter in kind.value.entries) {
            if (value.containsKey(setter.key)) {
              final used = _bindingReference(
                  record.child(value[setter.key]), setter.value,
                  strict: true);
              found |= used;
            }
          }
        }
        for (final kind in kTextSpanRecognizerVoidCallbacks.entries) {
          if (!_maySelect(record.child(value['kind']), {kind.key})) continue;
          for (final setter in kind.value) {
            if (value.containsKey(setter)) {
              found |= visit(record.child(value[setter]), PropertyType.event);
            }
          }
        }
        return found;
      });

  bool _bindingReference(_NativeValue node, String type,
          {bool strict = false}) =>
      _previewAny(node.withNativeProjection(onNativeReference != null),
          (resolved) {
        final value = resolved.value;
        if (onNativeReference != null) {
          final native = value is Map &&
              const {'nativeBinding', 'nativeLocal'}.contains(value['kind']);
          final envelope = decodeRfwProgramEnvelope(value,
              operations: operations, scope: programScope);
          if (value != null &&
              (strict ||
                  native ||
                  value is Reference ||
                  envelope?.values.nodes[envelope.values.root].type.kind ==
                      'native')) {
            onNativeReference!(
                value, type, resolved.scoped.lexicalContext, strict);
          }
          return false;
        }
        if (value is Map && value['kind'] == 'nativeLocal') {
          programScope?.requireNativeValue(
              value, ValueType.native(type, nullable: true),
              context: resolved.scoped.lexicalContext);
          return true;
        }
        final envelope = decodeRfwProgramEnvelope(value,
            operations: operations, scope: programScope);
        if (envelope?.values.nodes[envelope.values.root].type.kind == 'native')
          return true;
        if (_unavailableNativeValue(value)) return true;
        if (strict &&
            (value is Reference ||
                value is Map &&
                    (value['kind'] == 'nativeLocal' ||
                        decodeRfwProgramEnvelope(value,
                                operations: operations, scope: programScope) !=
                            null))) return true;
        return value is Map &&
            _maySelect(
                resolved.child(value['kind']), const {'nativeBinding'}) &&
            _maySelect(resolved.child(value['type']), {type}) &&
            value.containsKey('key') &&
            value.containsKey('nullable');
      });

  bool _catalogValue(
    _NativeValue node,
    PropertyType type, {
    CatalogValueShape? shape,
    WireIdRef? ref,
    bool factory = false,
  }) {
    final value = node.value;
    if (shape is ListShape) {
      return _items(
        node,
        (item) => visit(
          item,
          shape.itemShape.propertyType,
          shape: shape.itemShape,
          factory: factory,
        ),
      );
    }
    final target =
        ref ?? (shape is StructuredShape ? shape.structuredRef : null);
    if (target != null) {
      final entry = structured[(target.library, target.wireId.value)];
      return entry != null && _structured(node, entry, factory: factory);
    }
    if (value is! Map) return false;
    if (shape is UnionShape) {
      final union =
          unions[(shape.unionRef.library, shape.unionRef.wireId.value)];
      if (union == null) return false;
      for (final member in union.members) {
        final entry = structured[(member.library, member.wireId.value)];
        if (entry != null &&
            _maySelect(node.child(value[union.discriminator.field]), {
              entry.name,
              entry.wireId.value,
              entry.sourceType.split('#').last,
            }) &&
            _structured(node, entry, factory: factory)) {
          return true;
        }
      }
    }
    return false;
  }

  // New geometry forms raise SDK requirements without changing slot versions.
  // Only gradients need newer factories; other geometry uses shared decoders.
  bool? _geometryNative(_NativeValue node, PropertyType type,
      {required bool factory}) {
    final value = node.value;
    switch (type) {
      case PropertyType.edgeInsets:
        return !factory && value is Map;
      case PropertyType.shapeBorder:
        if (factory) return false;
        if (value is List) {
          return _items(node, (item) => visit(item, type));
        }
        return value is Map &&
            _maySelect(node.child(value['type']), const {
              'rounded',
              'roundedSuperellipse',
              'continuous',
              'beveled',
            }) &&
            node.child(value['borderRadius']).any((radius) {
              if (radius.value is Reference) return true;
              final corners = radius.value;
              return corners is Map &&
                  const [
                    'topStart',
                    'topEnd',
                    'bottomStart',
                    'bottomEnd',
                  ].any((key) => _geometryComponent(
                      radius.child(corners[key]), (value) => value is num));
            });
      case PropertyType.decorationImage:
        if (factory || value is! Map) return false;
        final provider = node.child(value['image']).any((image) {
          if (image.value is Reference) return true;
          final fields = image.value;
          return fields is Map &&
              _maySelect(
                  image.child(fields['kind']), const {'asset', 'network'}) &&
              _geometryComponent(
                  image.child(fields['src']), (value) => value is String);
        });
        return provider &&
            node.child(value['alignment']).any((alignment) {
              if (alignment.value is Reference) return true;
              final fields = alignment.value;
              return fields is Map &&
                  _geometryComponent(alignment.child(fields['start']),
                      (value) => value is double) &&
                  _geometryComponent(
                      alignment.child(fields['y']), (value) => value is double);
            });
      case PropertyType.gradient:
        if (value is! Map) return false;
        // rfw already accepted directional alignment. Only these numeric reads
        // gained integer widening when generated factories switched helpers.
        return _maySelect(node.child(value['type']), const {'radial'}) &&
                const ['radius', 'focalRadius'].any((key) => _geometryComponent(
                    node.child(value[key]), (value) => value is int)) ||
            _maySelect(node.child(value['type']), const {'sweep'}) &&
                const ['startAngle', 'endAngle'].any((key) =>
                    _geometryComponent(
                        node.child(value[key]), (value) => value is int));
      case PropertyType.structured:
      case PropertyType.unknown:
        return null;
      default:
        return false;
    }
  }

  bool _geometryComponent(_NativeValue node, bool Function(Object?) accepts) =>
      node.any((resolved) =>
          resolved.value is Reference ||
          decodeRfwProgramEnvelope(resolved.value,
                  operations: operations, scope: programScope) !=
              null ||
          accepts(resolved.value));

  bool _readsScalar(PropertyType type,
          {CatalogValueShape? shape, WireIdRef? ref}) =>
      !const {
        PropertyType.widget,
        PropertyType.widgetList,
        PropertyType.widgetBuilder,
        PropertyType.scalarCallback,
        PropertyType.event,
        PropertyType.dataReference,
      }.contains(type) &&
      (type != PropertyType.unknown || shape != null || ref != null);

  bool _scalarFields(_NativeValue node, Iterable<String> fields) =>
      expressions &&
      fields.isNotEmpty &&
      node.any((resolved) {
        final value = resolved.value;
        if (resolved.unresolvedArguments && value is Reference) return true;
        return value is Map &&
            fields.any((field) => _scalar(resolved.child(value[field])));
      });

  // These are the closed scalar reads of installed native decoders. All child
  // access retains the same argument scope and projection/recursion bounds.
  bool _scalar(_NativeValue node) => node.any((value) =>
      value.unresolvedArguments && value.value is Reference ||
      decodeRfwProgramEnvelope(value.value,
              operations: operations, scope: programScope) !=
          null);

  bool _mapReads(_NativeValue node,
          bool Function(_NativeValue node, Map<Object?, Object?> value) read) =>
      _previewAny(node, (resolved) {
        final value = resolved.value;
        if (_unavailableNativeValue(value)) return true;
        if (!bindings && resolved.unresolvedArguments && value is Reference)
          return true;
        return value is Map && read(resolved, value);
      });

  bool _prefixItems(
    _NativeValue node,
    int count,
    bool Function(_NativeValue) read,
  ) =>
      _items(node, read, limit: count);

  bool? _computedNative(_NativeValue node, PropertyType type) => switch (type) {
        PropertyType.gradient => _computedGradient(node),
        PropertyType.shapeBorder => _computedShape(node),
        PropertyType.decorationImage => _computedImage(node),
        PropertyType.paint => _computedPaint(node),
        PropertyType.boxShadowList =>
          _items(node, (item) => _computedShadow(item, box: true)),
        PropertyType.shadowList => _items(node, _computedShadow),
        PropertyType.border => _prefixItems(node, 4, _computedSide),
        PropertyType.edgeInsets => _scalarFields(node,
                const ['top', 'right', 'bottom', 'left', 'start', 'end']) ||
            _prefixItems(node, 4, _scalar),
        PropertyType.alignment ||
        PropertyType.alignmentXY =>
          _scalarFields(node, const ['x', 'y', 'start']),
        PropertyType.locale => false, // ArgumentDecoders.locale reads a string.
        PropertyType.inlineSpan => _mapReads(
            node,
            (node, value) =>
                visit(node.child(value['text']), PropertyType.string) ||
                _textStyle(node.child(value['style'])) ||
                _spanChildren(node.child(value['children']))),
        _ => null,
      };

  bool _computedGradient(_NativeValue node,
          {String? kind, bool legacy = false}) =>
      _mapReads(node, (node, value) {
        bool selected(String name) => kind == null
            ? _maySelect(node.child(value['type']), {name})
            : kind == name;
        if (kind == null && _scalarFields(node, const ['type'])) return true;
        if (!['linear', 'radial', 'sweep'].any(selected)) return false;
        if (_scalarFields(node, const ['tileMode']) ||
            _items(node.child(value['stops']), _scalar) ||
            _items(
                node.child(value['colors']),
                (item) =>
                    legacy ? _scalar(item) : visit(item, PropertyType.color)))
          return true;
        bool alignment(String field) =>
            visit(node.child(value[field]), PropertyType.alignment);
        return selected('linear') && (alignment('begin') || alignment('end')) ||
            selected('radial') &&
                (alignment('center') ||
                    alignment('focal') ||
                    _scalarFields(node, const ['radius', 'focalRadius'])) ||
            selected('sweep') &&
                (alignment('center') ||
                    _scalarFields(node, const ['startAngle', 'endAngle']));
      });

  bool _computedSide(_NativeValue node, {bool legacy = false}) => _mapReads(
      node,
      (node, value) =>
          _scalarFields(node, const ['width', 'style']) ||
          (legacy
              ? _scalar(node.child(value['color']))
              : visit(node.child(value['color']), PropertyType.color)));

  bool _computedShadow(_NativeValue node, {bool box = false}) => _mapReads(
      node,
      (node, value) =>
          _scalarFields(
              node,
              box
                  ? const ['blurRadius', 'spreadRadius']
                  : const ['blurRadius']) ||
          visit(node.child(value['offset']), PropertyType.offset) ||
          visit(node.child(value['color']), PropertyType.color));

  bool _computedRadius(_NativeValue node) =>
      _scalar(node) ||
      _scalarFields(node, const [
        'topLeft',
        'topRight',
        'bottomLeft',
        'bottomRight',
        'topStart',
        'topEnd',
        'bottomStart',
        'bottomEnd'
      ]);

  bool _computedShape(_NativeValue node) => node.any((node) {
        final value = node.value;
        if (node.unresolvedArguments && value is Reference) return true;
        if (value is List) return _items(node, _computedShape);
        if (value is! Map) return false;
        // The shared shape decoder reads the side before selecting the shape.
        if (_computedSide(node.child(value['side'])) ||
            _scalarFields(node, const ['type'])) return true;
        bool selected(Set<Object?> kinds) =>
            _maySelect(node.child(value['type']), kinds);
        if (selected(const {
              'rounded',
              'roundedSuperellipse',
              'continuous',
              'beveled'
            }) &&
            _computedRadius(node.child(value['borderRadius']))) return true;
        if (selected(const {'circle'}) &&
            _scalarFields(node, const ['eccentricity'])) return true;
        if (selected(const {'linear'}) &&
            const ['start', 'end', 'top', 'bottom'].any((field) =>
                _scalarFields(
                    node.child(value[field]), const ['size', 'alignment'])))
          return true;
        if (selected(const {'star'}) &&
            _scalarFields(node, const [
              'points',
              'innerRadiusRatio',
              'pointRounding',
              'valleyRounding',
              'rotation',
              'squash'
            ])) return true;
        if (selected(const {'polygon'}) &&
            _scalarFields(
                node, const ['sides', 'pointRounding', 'rotation', 'squash']))
          return true;
        return selected(const {'box'}) &&
            _prefixItems(node.child(value['sides']), 4,
                (side) => _computedSide(side, legacy: true));
      });

  bool _computedImage(_NativeValue node) => _mapReads(
      node,
      (node, value) =>
          _scalarFields(node, const ['fit', 'repeat', 'opacity', 'scale']) ||
          visit(node.child(value['alignment']), PropertyType.alignment) ||
          _mapReads(
              node.child(value['image']),
              (image, value) =>
                  _scalarFields(image, const ['kind', 'src']) ||
                  _maySelect(image.child(value['kind']), const {'network'}) &&
                      _scalarFields(image, const ['scale']) ||
                  _maySelect(image.child(value['kind']), const {'asset'}) &&
                      _scalarFields(image, const ['package'])));

  bool _computedFilter(_NativeValue node, {bool svg = false}) =>
      _mapReads(node, (node, value) {
        final field = svg ? 'kind' : 'type';
        if (_scalarFields(node, [field])) return true;
        return _maySelect(node.child(value[field]), const {'mode'}) &&
                (_scalarFields(node, const ['blendMode']) ||
                    visit(node.child(value['color']), PropertyType.color)) ||
            _maySelect(node.child(value[field]), const {'matrix'}) &&
                _prefixItems(node.child(value['matrix']), 20, _scalar);
      });

  bool _computedPaint(_NativeValue node) => _mapReads(
      node,
      (node, value) =>
          _scalarFields(node, const ['blendMode', 'filterQuality', 'isAntiAlias']) ||
          visit(node.child(value['color']), PropertyType.color) ||
          _computedFilter(node.child(value['colorFilter'])) ||
          _mapReads(
              node.child(value['maskFilter']),
              (mask, value) =>
                  _scalarFields(mask, const ['type']) ||
                  _maySelect(mask.child(value['type']), const {'blur'}) &&
                      _scalarFields(mask, const ['style', 'sigma'])) ||
          _mapReads(
              node.child(value['shader']),
              (shader, value) =>
                  _computedGradient(shader, legacy: true) ||
                  _maySelect(shader.child(value['type']),
                          const {'linear', 'radial', 'sweep'}) &&
                      (_scalarFields(shader.child(value['rect']), const ['x', 'y', 'w', 'h']) ||
                          (node.root == null
                              ? false
                              : _scalarFields(
                                  _NativeValue(node.root!,
                                      depth: node.depth + 1,
                                      unresolvedArguments:
                                          node.unresolvedArguments,
                                      requiresNativeProjection:
                                          node.requiresNativeProjection),
                                  const ['textDirection'])))));

  bool _iconTheme(_NativeValue node) => _mapReads(node, (node, value) {
        final base =
            _previewAny(node.child(value[kIconThemeDataLerpKey]), (lerp) {
          if (_unavailableNativeValue(lerp.value)) return true;
          if (!bindings && lerp.unresolvedArguments && lerp.value is Reference)
            return true;
          final value = lerp.value;
          if (value != null)
            return value is Map &&
                (_scalarFields(lerp, const ['t']) ||
                    _iconTheme(lerp.child(value['a'])) ||
                    _iconTheme(lerp.child(value['b'])));
          return _previewAny(
              node.child((node.value! as Map)[kIconThemeDataFallbackKey]),
              (fallback) {
            if (_unavailableNativeValue(fallback.value)) return true;
            if (expressions) {
              return fallback.value == null
                  ? _iconThemeFields(node)
                  : _scalar(fallback);
            }
            return (fallback.value == null ||
                    !bindings &&
                        fallback.unresolvedArguments &&
                        fallback.value is Reference) &&
                _iconThemeFields(node);
          });
        });
        return base ||
            _items(node.child(value[kStructuredCopyWithKey]), _iconThemeFields);
      });

  bool _systemUiOverlayStyle(_NativeValue node) => _mapReads(
      node,
      (node, value) =>
          _scalarFields(node, const [
            'statusBarBrightness',
            'statusBarIconBrightness',
            'systemStatusBarContrastEnforced',
            'systemNavigationBarIconBrightness',
            'systemNavigationBarContrastEnforced'
          ]) ||
          const [
            'statusBarColor',
            'systemNavigationBarColor',
            'systemNavigationBarDividerColor'
          ].any((key) => visit(node.child(value[key]), PropertyType.color)) ||
          _items(node.child(value[kStructuredCopyWithKey]),
              _systemUiOverlayStyle));

  bool _computedPhysics(_NativeValue node) => _mapReads(
      node,
      (node, value) =>
          _scalarFields(node, const ['_s']) ||
          _computedPhysics(node.child(value['parent'])) ||
          _maySelect(
                  node.child(value['_s']), const {'BouncingScrollPhysics'}) &&
              _scalarFields(node, const ['decelerationRate']));

  bool _svgTheme(_NativeValue node) => _mapReads(
      node,
      (node, value) =>
          _scalarFields(node, const ['fontSize', 'xHeight']) ||
          visit(node.child(value['currentColor']), PropertyType.color));
  bool _computedHeaders(_NativeValue node) =>
      _items(node, (item) => _scalarFields(item, const ['key', 'value']));
  bool _svgNativeValue(_NativeValue node, String sourceType) {
    final bindingType =
        svgNativeBindingType(sourceType, namespace: 'restage.svg');
    if (bindings &&
        bindingType != null &&
        _bindingReference(node, bindingType)) {
      return true;
    }
    return switch (sourceType) {
      'package:flutter_svg/src/loaders.dart#SvgTheme' => _svgTheme(node),
      'dart:typed_data#Uint8List' =>
        _items(node, (item) => visit(item, PropertyType.integer)),
      'dart:core#Map' => _computedHeaders(node),
      _ => false,
    };
  }

  bool _svgLoader(_NativeValue node) => _mapReads(node, (node, value) {
        if (_scalarFields(node, const ['kind'])) return true;
        bool selected(String kind) =>
            _maySelect(node.child(value['kind']), {kind});
        if (!const [
          'SvgStringLoader',
          'SvgBytesLoader',
          'SvgAssetLoader',
          'SvgNetworkLoader',
          'SvgFileLoader',
        ].any(selected)) {
          return false;
        }
        if (_svgNativeValue(
              node.child(value['theme']),
              'package:flutter_svg/src/loaders.dart#SvgTheme',
            ) ||
            _svgNativeValue(
              node.child(value['colorMapper']),
              'package:flutter_svg/src/loaders.dart#ColorMapper',
            )) {
          return true;
        }
        return (selected('SvgStringLoader') ||
                    selected('SvgAssetLoader') ||
                    selected('SvgNetworkLoader')) &&
                _scalarFields(node, const ['value']) ||
            selected('SvgBytesLoader') &&
                _svgNativeValue(
                  node.child(value['value']),
                  'dart:typed_data#Uint8List',
                ) ||
            selected('SvgAssetLoader') &&
                (_scalarFields(node, const ['packageName']) ||
                    _svgNativeValue(
                      node.child(value['assetBundle']),
                      'package:flutter/src/services/asset_bundle.dart#AssetBundle',
                    )) ||
            selected('SvgNetworkLoader') &&
                (_svgNativeValue(
                      node.child(value['headers']),
                      'dart:core#Map',
                    ) ||
                    _svgNativeValue(
                      node.child(value['httpClient']),
                      'package:http/src/client.dart#Client',
                    )) ||
            selected('SvgFileLoader') &&
                _svgNativeValue(node.child(value['value']), 'dart:io#File');
      });

  bool? _computedStructured(_NativeValue node, String sourceType,
      {required bool svg}) {
    switch (sourceType) {
      case 'dart:core#Map':
        return svg ? _computedHeaders(node) : null;
      case 'dart:typed_data#Uint8List':
        return svg ? _items(node, _scalar) : null;
      case 'package:flutter_svg/src/loaders.dart#SvgTheme':
        return svg ? _svgTheme(node) : null;
      case 'package:vector_graphics/src/loader.dart#BytesLoader':
        return svg ? _svgLoader(node) : null;
      case 'dart:ui#ColorFilter':
        return _computedFilter(node, svg: svg);
      case 'dart:ui#Paint':
        return _computedPaint(node);
      case 'dart:ui#Size':
        return _scalarFields(node, const ['width', 'height']);
      case 'dart:ui#Shadow':
        return _computedShadow(node);
      case 'package:flutter/src/painting/box_shadow.dart#BoxShadow':
        return _computedShadow(node, box: true);
      case 'package:flutter/src/painting/borders.dart#BorderSide':
        return _computedSide(node);
      case 'package:flutter/src/painting/text_style.dart#TextStyle':
        return _textStyle(node);
      case 'package:flutter/src/widgets/icon_theme_data.dart#IconThemeData':
        return _iconTheme(node);
      case 'package:flutter/src/services/system_chrome.dart#SystemUiOverlayStyle':
        return _systemUiOverlayStyle(node);
      case 'package:flutter/src/painting/gradient.dart#LinearGradient':
        return _computedGradient(node, kind: 'linear');
      case 'package:flutter/src/painting/gradient.dart#RadialGradient':
        return _computedGradient(node, kind: 'radial');
      case 'package:flutter/src/painting/gradient.dart#SweepGradient':
        return _computedGradient(node, kind: 'sweep');
      case 'package:flutter/src/painting/text_scaler.dart#TextScaler':
        return _mapReads(
            node,
            (node, value) =>
                _scalarFields(node, const ['kind']) ||
                _maySelect(node.child(value['kind']), const {'linear'}) &&
                    _scalarFields(node, const ['factor']) ||
                _maySelect(node.child(value['kind']), const {'native'}) &&
                    _scalarFields(node, const ['key']));
      case 'package:flutter/src/rendering/viewport.dart#ScrollCacheExtent':
        return _scalarFields(node, const ['_s', 'value']);
      case 'package:flutter/src/widgets/scroll_physics.dart#ScrollPhysics':
        return _computedPhysics(node);
      case 'package:flutter/src/rendering/sliver_grid.dart#SliverGridDelegate':
      case 'package:flutter/src/rendering/sliver_grid.dart#SliverGridDelegateWithFixedCrossAxisCount':
      case 'package:flutter/src/rendering/sliver_grid.dart#SliverGridDelegateWithMaxCrossAxisExtent':
        return _mapReads(
            node,
            (node, value) =>
                _scalarFields(node, const [
                  '_s',
                  'mainAxisSpacing',
                  'crossAxisSpacing',
                  'childAspectRatio',
                  'mainAxisExtent'
                ]) ||
                _maySelect(node.child(value['_s']),
                        const {'SliverGridDelegateWithFixedCrossAxisCount'}) &&
                    _scalarFields(node, const ['crossAxisCount']) ||
                _maySelect(node.child(value['_s']),
                        const {'SliverGridDelegateWithMaxCrossAxisExtent'}) &&
                    _scalarFields(node, const ['maxCrossAxisExtent']));
      case 'package:flutter/src/widgets/scroll_delegate.dart#SliverChildDelegate':
      case 'package:flutter/src/widgets/scroll_delegate.dart#SliverChildListDelegate':
      case 'package:flutter/src/widgets/scroll_delegate.dart#SliverChildBuilderDelegate':
        return _mapReads(
            node,
            (node, value) =>
                _scalarFields(node, const [
                  '_s',
                  'addAutomaticKeepAlives',
                  'addRepaintBoundaries',
                  'addSemanticIndexes',
                  'semanticIndexOffset'
                ]) ||
                _maySelect(node.child(value['_s']),
                        const {'SliverChildListDelegate'}) &&
                    _scalarFields(node, const ['fixed']) ||
                _maySelect(node.child(value['_s']),
                        const {'SliverChildBuilderDelegate'}) &&
                    _scalarFields(node, const ['childCount']));
    }
    return null;
  }

  bool _potential(
    PropertyType type, {
    CatalogValueShape? shape,
    WireIdRef? ref,
    bool factory = false,
    Set<(String, String)> seen = const {},
  }) {
    if (canonicalColors &&
        !const {
          PropertyType.color,
          PropertyType.paint,
          PropertyType.gradient,
          PropertyType.boxShadowList,
          PropertyType.shadowList,
          PropertyType.border,
          PropertyType.shapeBorder,
          PropertyType.inlineSpan,
          PropertyType.structured,
          PropertyType.unknown,
        }.contains(type) &&
        shape == null &&
        ref == null) return false;
    if (geometry &&
        const {
          PropertyType.edgeInsets,
          PropertyType.shapeBorder,
          PropertyType.decorationImage,
          PropertyType.gradient
        }.contains(type)) {
      return !factory || type == PropertyType.gradient;
    }
    if (expressions &&
        type != PropertyType.structured &&
        type != PropertyType.unknown &&
        _readsScalar(type, shape: shape, ref: ref)) return true;
    if (factory &&
        const {
          PropertyType.textDecoration,
          PropertyType.shadowList,
          PropertyType.border,
          PropertyType.shapeBorder,
          PropertyType.inlineSpan,
        }.contains(type)) {
      return false;
    }
    if (!geometry &&
        const {
          PropertyType.color,
          PropertyType.fontWeight,
          PropertyType.textDecoration,
          PropertyType.paint,
          PropertyType.gradient,
          PropertyType.boxShadowList,
          PropertyType.shadowList,
          PropertyType.border,
          PropertyType.shapeBorder,
          PropertyType.inlineSpan,
        }.contains(type)) {
      return true;
    }
    if (shape is ListShape) {
      return _potential(
        shape.itemShape.propertyType,
        shape: shape.itemShape,
        factory: factory,
        seen: seen,
      );
    }
    final target =
        ref ?? (shape is StructuredShape ? shape.structuredRef : null);
    bool entryUses(WireIdRef target) {
      final key = (target.library, target.wireId.value);
      if (seen.contains(key)) return false;
      final entry = structured[key];
      if (entry == null) return false;
      if (expressions &&
          _computedStructured(
                  const _NativeValue(_CapabilityValue(ArgsReference([]), {}),
                      unresolvedArguments: true),
                  entry.sourceType,
                  svg: entry.library.namespace == 'restage.svg') ==
              true) return true;
      if (!geometry && _sharedFactoryType(entry.sourceType)) return !factory;
      if (!geometry &&
          entry.library.namespace == 'restage.svg' &&
          _svgNativeType(entry.sourceType)) return true;
      if (!geometry && _nativeStyleType(entry.sourceType)) {
        return true;
      }
      return entry.fields.any(
        (field) => _potential(
          field.type,
          shape: field.valueShape ??
              (field.unionRef == null
                  ? null
                  : UnionShape(
                      propertyType: PropertyType.unknown,
                      unionRef: field.unionRef!,
                    )),
          ref: field.structuredRef,
          factory: factory,
          seen: {...seen, key},
        ),
      );
    }

    if (target != null) return entryUses(target);
    if (shape is UnionShape) {
      return unions[(shape.unionRef.library, shape.unionRef.wireId.value)]
              ?.members
              .any(entryUses) ??
          false;
    }
    return false;
  }

  String? _bindingSourceType(StructuredEntry entry) =>
      svgNativeBindingType(
        entry.sourceType,
        namespace: entry.library.namespace,
      ) ??
      _commonBindingSourceType(entry.sourceType);

  String? _commonBindingSourceType(String sourceType) => switch (sourceType) {
        'dart:ui#Color' => 'flutter.Color',
        'package:flutter/src/painting/text_scaler.dart#TextScaler' =>
          'flutter.TextScaler',
        'package:flutter/src/widgets/scroll_controller.dart#ScrollController' =>
          'flutter.ScrollController',
        'package:flutter/src/material/tab_controller.dart#TabController' =>
          'flutter.TabController',
        'package:flutter/src/gestures/recognizer.dart#GestureRecognizer' =>
          'flutter.GestureRecognizer',
        'package:flutter/src/foundation/key.dart#Key' => 'flutter.Key',
        _ => null,
      };

  bool _svgNativeType(String sourceType) => const {
        'package:flutter_svg/src/loaders.dart#SvgTheme',
        'package:vector_graphics/src/loader.dart#BytesLoader',
      }.contains(sourceType);

  bool _sharedFactoryType(String sourceType) => const {
        'package:flutter/src/painting/text_style.dart#TextStyle',
        'package:flutter/src/services/system_chrome.dart#SystemUiOverlayStyle',
        'package:flutter/src/widgets/icon_theme_data.dart#IconThemeData',
        'package:flutter/src/painting/borders.dart#BorderSide',
      }.contains(sourceType);

  bool _nativeStyleType(String sourceType) => const {
        'dart:ui#Paint',
        'dart:ui#ColorFilter',
        'dart:ui#Shadow',
        'package:flutter/src/painting/box_shadow.dart#BoxShadow',
        'package:flutter/src/painting/gradient.dart#LinearGradient',
        'package:flutter/src/painting/gradient.dart#RadialGradient',
        'package:flutter/src/painting/gradient.dart#SweepGradient',
      }.contains(sourceType);

  bool _structured(
    _NativeValue node,
    StructuredEntry entry, {
    bool factory = false,
  }) {
    final value = node.value;
    if ((bindings ? _bindingSourceType(entry) : null) case final type?) {
      if (_bindingReference(node, type, strict: type == 'flutter.Key'))
        return true;
    }
    if (expressions) {
      final computed = _computedStructured(node, entry.sourceType,
          svg: entry.library.namespace == 'restage.svg');
      if (computed != null) return computed;
    }
    if (value is! Map) return false;
    if (!geometry && factory && _sharedFactoryType(entry.sourceType))
      return false;
    if (!geometry &&
        !factory &&
        _nativeFields(node, entry.sourceType,
            svg: entry.library.namespace == 'restage.svg')) return true;
    for (final field in entry.fields) {
      final shape = field.valueShape ??
          (field.unionRef == null
              ? null
              : UnionShape(
                  propertyType: PropertyType.unknown,
                  unionRef: field.unionRef!,
                ));
      if (visit(
        node.child(value[field.name]),
        field.type,
        shape: shape,
        ref: field.structuredRef,
        factory: factory,
      )) {
        return true;
      }
    }
    return false;
  }

  bool _nativeFields(_NativeValue node, String sourceType,
          {bool svg = false}) =>
      _previewAny(node, (node) {
        final value = node.value;
        if (_unavailableNativeValue(value)) return true;
        if (!bindings && node.unresolvedArguments && value is Reference) {
          return (svg && _svgNativeType(sourceType)) ||
              _sharedFactoryType(sourceType) ||
              _nativeStyleType(sourceType);
        }
        if (value is! Map) return false;
        switch (sourceType) {
          case 'package:flutter/src/painting/text_style.dart#TextStyle':
            return _textStyle(node);
          case 'package:flutter/src/painting/borders.dart#BorderSide':
          case 'package:flutter/src/painting/box_shadow.dart#BoxShadow':
          case 'dart:ui#Shadow':
            return _shadow(node);
          case 'dart:ui#Paint':
            return visit(node, PropertyType.paint);
          case 'dart:ui#ColorFilter':
            return _colorFilter(node, discriminator: svg ? 'kind' : 'type');
          case 'package:flutter_svg/src/loaders.dart#SvgTheme':
            return svg && _svgTheme(node);
          case 'package:vector_graphics/src/loader.dart#BytesLoader':
            return svg && _svgLoader(node);
          case 'package:flutter/src/painting/gradient.dart#LinearGradient':
          case 'package:flutter/src/painting/gradient.dart#RadialGradient':
          case 'package:flutter/src/painting/gradient.dart#SweepGradient':
            return _items(
              node.child(value['colors']),
              (item) => visit(item, PropertyType.color),
            );
          case 'package:flutter/src/services/system_chrome.dart#SystemUiOverlayStyle':
            return _systemUiOverlayStyle(node);
          case 'package:flutter/src/widgets/icon_theme_data.dart#IconThemeData':
            return _iconTheme(node);
        }
        return false;
      });

  bool _textStyle(_NativeValue node) => _mapReads(
      node,
      (node, value) =>
          _scalarFields(node, const [
            'inherit',
            'fontSize',
            'fontStyle',
            'letterSpacing',
            'wordSpacing',
            'textBaseline',
            'height',
            'leadingDistribution',
            'decorationStyle',
            'decorationThickness',
            'debugLabel',
            'fontFamily',
            'fontPackage',
            'overflow'
          ]) ||
          visit(node.child(value['fontFamilyFallback']),
              PropertyType.stringList) ||
          visit(node.child(value['color']), PropertyType.color) ||
          visit(
            node.child(value['backgroundColor']),
            PropertyType.color,
          ) ||
          visit(
            node.child(value['decorationColor']),
            PropertyType.color,
          ) ||
          visit(
            node.child(value['fontWeight']),
            PropertyType.fontWeight,
          ) ||
          visit(
            node.child(value['decoration']),
            PropertyType.textDecoration,
          ) ||
          visit(node.child(value['locale']), PropertyType.locale) ||
          visit(node.child(value['fontFeatures']),
              PropertyType.fontFeatureList) ||
          visit(node.child(value['fontVariations']),
              PropertyType.fontVariationList) ||
          visit(node.child(value['foreground']), PropertyType.paint) ||
          visit(node.child(value['background']), PropertyType.paint) ||
          visit(node.child(value['shadows']), PropertyType.shadowList));

  bool _iconThemeFields(_NativeValue node) => _mapReads(
      node,
      (node, value) =>
          _scalarFields(node, const [
            'size',
            'fill',
            'weight',
            'grade',
            'opticalSize',
            'opacity',
            'applyTextScaling'
          ]) ||
          (expressions
              ? visit(node.child(value['color']), PropertyType.color)
              : _shadow(node)) ||
          visit(node.child(value['shadows']), PropertyType.shadowList));

  bool _shadow(_NativeValue node) => _mapReads(
      node,
      (node, value) =>
          _scalarFields(node, const [
            'blurRadius',
            'spreadRadius',
            'style',
            'width',
            'strokeAlign'
          ]) ||
          visit(node.child(value['offset']), PropertyType.offset) ||
          visit(node.child(value['color']), PropertyType.color));

  bool _colorFilter(_NativeValue node, {String discriminator = 'type'}) =>
      _mapReads(
          node,
          (node, value) =>
              _maySelect(node.child(value[discriminator]), const {'mode'}) &&
              (visit(node.child(value['color']), PropertyType.color) ||
                  _scalarFields(node, const ['blendMode'])));

  bool _spanChildren(_NativeValue node) => _items(
      node,
      (item) => _previewAny(
          item,
          (resolved) => resolved.value is List
              ? _spanChildren(resolved)
              : visit(resolved, PropertyType.inlineSpan)));

  bool _items(_NativeValue node, bool Function(_NativeValue) item,
          {int? limit}) =>
      _previewAny(
        node,
        (resolved) {
          final value = resolved.value;
          if (_unavailableNativeValue(value)) return item(resolved);
          if (resolved.unresolvedArguments && value is Reference) {
            return item(resolved);
          }
          if (value is Loop)
            return _items(resolved.child(value.output), item, limit: limit);
          bool element(_NativeValue node) => _previewAny(
                node,
                (resolved) {
                  final value = resolved.value;
                  if (value is Loop) {
                    return resolved.child(value.output).any(
                          (output) => output.value is List
                              ? _items(output, item, limit: limit)
                              : element(output),
                        );
                  }
                  return item(resolved);
                },
                preserveLoops: true,
              );
          if (value is! List) return false;
          // A flattened loop may contribute any number of elements. Keep its
          // possible prefix; ordinary list references occupy one fixed slot.
          final items = limit == null ||
                  value.any((item) => item is Loop || item is Switch)
              ? value
              : value.take(limit);
          return items.any((value) => element(resolved.child(value)));
        },
        preserveLoops: true,
      );

  bool _maySelect(_NativeValue node, Set<Object?> names) => node.any(
        (resolved) =>
            resolved.value is Reference || names.contains(resolved.value),
      );
}

// Typed descent retains the caller's argument scope and projection bound.
final class _NativeValue {
  const _NativeValue(
    this.scoped, {
    this.depth = 0,
    this.root,
    this.unresolvedArguments = false,
    this.requiresNativeProjection = false,
  });
  final _CapabilityValue scoped;
  final int depth;
  final _CapabilityValue? root;
  final bool unresolvedArguments;
  // Untyped recipe descent retains the proof obligation. An explicit schema
  // destination recomputes it without discarding any projection evidence.
  final bool requiresNativeProjection;
  Object? get value => scoped.value;
  _NativeValue withNativeProjection(bool required, {bool inherit = true}) =>
      _NativeValue(
        scoped,
        depth: depth,
        root: root,
        unresolvedArguments: unresolvedArguments,
        requiresNativeProjection:
            required || inherit && requiresNativeProjection,
      );
  _NativeValue child(Object? value) => _NativeValue(
        _CapabilityValue(value, scoped.arguments, scoped.lexicalContext,
            scoped.projectionExhausted),
        depth: depth + 1,
        root: root,
        unresolvedArguments: unresolvedArguments,
        requiresNativeProjection: requiresNativeProjection,
      );
  Never _projectionFailure() => throw const FormatException(
      'Native reference projection exceeds its bound.');

  bool any(bool Function(_NativeValue) visitor, {bool preserveLoops = false}) {
    if (requiresNativeProjection && scoped.projectionExhausted) {
      _projectionFailure();
    }
    return _visitCapabilityValue(
      scoped,
      (resolved, depth) {
        if (requiresNativeProjection && resolved.projectionExhausted) {
          _projectionFailure();
        }
        return visitor(
          _NativeValue(
            resolved,
            depth: depth,
            root: root,
            unresolvedArguments: unresolvedArguments,
            requiresNativeProjection: requiresNativeProjection,
          ),
        );
      },
      depth: depth,
      preserveLoops: preserveLoops,
      unresolvedArguments: unresolvedArguments,
      onLimit: (value) {
        // Capability walks may approximate an unknown value. Native authority
        // admission must fail before a recipe helper can mistake it for absence.
        if (requiresNativeProjection) _projectionFailure();
        return visitor(
          _NativeValue(
            _CapabilityValue(const ArgsReference([]), value.arguments,
                value.lexicalContext, true),
            root: root,
            unresolvedArguments: true,
            requiresNativeProjection: requiresNativeProjection,
          ),
        );
      },
    );
  }
}

/// The client floor [library]'s surface features need: icon literals,
/// screen-local value writes and counted tap items need
/// [kSurfaceFeatureClientFloor], a loop that emits a widget list needs
/// [kGroupedWidgetListClientFloor]. [kBaselineCatalogVersion] otherwise.
int surfaceFeatureClientFloor(
  RemoteWidgetLibrary library, {
  SurfaceScreenHostDataSchema hostDataContract =
      const SurfaceScreenHostDataSchema.empty(),
  Map<String, ValueOperation> operations = kStandardValueOperations,
}) {
  final programScope = RfwProgramScope([
    for (final widget in library.widgets) ...[widget.initialState, widget.root]
  ], operations: operations, validateNativeBindingReferences: false);
  var floor = literalIconCodePoints(library).isNotEmpty
      ? kSurfaceFeatureClientFloor
      : kBaselineCatalogVersion;
  void require(int version) {
    if (floor < version) floor = version;
  }

  require(programScope.requiredCapability);

  void visit(Object? node) {
    switch (node) {
      case EventHandler():
        if (node.eventName == kLocalValueSetEventName ||
            node.eventArguments
                .containsKey(kMeasurementPublicationItemArgumentKeyV1)) {
          require(kSurfaceFeatureClientFloor);
        }
        visit(node.eventArguments);
      case DataReference(:final parts):
        if (_readsNativeBinding(parts, hostDataContract)) require(24);
        if (parts.length >= 2 &&
            parts.first == 'device' &&
            const {
              'viewInsetsTop',
              'viewInsetsRight',
              'viewInsetsBottom',
              'viewInsetsLeft',
              'boldText',
              'disableAnimations',
              'accessibleNavigation',
              'highContrast',
            }.contains(parts[1])) {
          require(18);
        }
      case ConstructorCall():
        final envelope = decodeRfwProgramEnvelope(node,
            operations: operations, scope: programScope);
        if (envelope != null) require(envelope.capability);
        visit(node.arguments);
      case WidgetBuilderDeclaration():
        visit(node.widget);
      case Loop():
        if (node.output is List) require(kGroupedWidgetListClientFloor);
        visit(node.input);
        visit(node.output);
      case Switch():
        visit(node.input);
        node.outputs.values.forEach(visit);
      case Map():
        final envelope = decodeRfwProgramEnvelope(node,
            operations: operations, scope: programScope);
        if (envelope != null) require(envelope.capability);
        node.values.forEach(visit);
      case List():
        node.forEach(visit);
    }
  }

  for (final widget in library.widgets) {
    visit(widget.initialState);
    visit(widget.root);
  }
  return floor;
}

bool _readsNativeBinding(
    List<Object> parts, SurfaceScreenHostDataSchema schema) {
  if (parts.length < 2 || parts.first != 'context') return false;
  var shape = schema.inputs[parts[1]];
  for (final part in parts.skip(2)) {
    while (shape is SurfaceScreenHostDataNullableShapeV1) {
      shape = shape.value;
    }
    shape = switch (shape) {
      SurfaceScreenHostDataObjectShapeV1(:final fields) => fields[part],
      SurfaceScreenHostDataMapShapeV1(:final values) when part is String =>
        values,
      SurfaceScreenHostDataListShapeV1(:final items)
          when part is int && part >= 0 =>
        items,
      _ => null,
    };
  }
  return shape != null && _containsNativeBinding(shape);
}

bool _containsNativeBinding(SurfaceScreenHostDataShape shape) =>
    switch (shape) {
      SurfaceScreenHostDataNativeBindingShapeV1() => true,
      SurfaceScreenHostDataNullableShapeV1(:final value) =>
        _containsNativeBinding(value),
      SurfaceScreenHostDataListShapeV1(:final items) =>
        _containsNativeBinding(items),
      SurfaceScreenHostDataMapShapeV1(:final values) =>
        _containsNativeBinding(values),
      SurfaceScreenHostDataObjectShapeV1(:final fields) =>
        fields.values.any(_containsNativeBinding),
      _ => false,
    };
