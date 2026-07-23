import 'dart:collection';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/a2ui/a2ui_catalog_model.dart';
import 'package:restage_codegen/src/a2ui/a2ui_data_builder.dart';
import 'package:restage_codegen/src/a2ui/a2ui_definition_registry.dart';
import 'package:restage_codegen/src/a2ui/a2ui_event_lowering.dart';
import 'package:restage_codegen/src/a2ui/a2ui_legacy_constraint_parser.dart';
import 'package:restage_codegen/src/a2ui/a2ui_safe_pattern.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_semantics.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Why an A2UI Dart emitter field or widget was not emitted.
enum A2uiDartCoverageReason {
  /// Event wiring is intentionally deferred to a fixed bridge convention.
  eventProperty,

  /// A theme-sourced default would bake host theme behavior into generated
  /// code, so the field is not advertised.
  themeDefault,

  /// Optional property type not supported by the A2UI Dart construction core.
  optionalUnsupportedPropertyType,

  /// Required property type not supported by the A2UI Dart construction core.
  requiredUnsupportedPropertyType,

  /// Native decompose reconstruction is intentionally outside this emitter.
  nativeDecomposeUnsupported,

  /// A synthetic construction strategy has no A2UI Dart projection.
  syntheticUnsupported,

  /// The widget declares a children slot without the canonical catalog field.
  unsupportedChildrenSlot,

  /// An enum field is missing the Dart enum type needed for fail-closed lookup.
  missingEnumType,

  /// A write-back callback could not be paired unambiguously: more than one
  /// write-back callback on the widget, or more than one matching-type value
  /// property (the auto single-pair fails closed on ambiguity).
  ambiguousWritePairing,

  /// An interactive callback has no matching-type value property to control —
  /// an uncontrolled widget whose state would live in ephemeral Flutter state,
  /// not the data model (not a controlled component).
  uncontrolledInteractiveWidget,

  /// The single matching-type value property is not a bindable data leaf (a
  /// theme-sourced / synthetic / reserved-identifier field), so its read cannot
  /// be rewritten to the write-back path.
  writeBackValueNotBound,

  /// An interactive callback whose signature the reflector could not lower —
  /// a multi-argument / named-argument / non-void callback (#sig), or a
  /// `ValueChanged<List<E>>` whose element `E` is not a scalar (#L). It fails
  /// closed loud rather than being mis-lowered or silently dropped.
  unsupportedInteractiveCallback,

  /// An explicit `@RestageProperty(writeBackValue:)` pairing that does not
  /// validate — the named value property does not exist, is not a matching-type
  /// bindable leaf, or two callbacks name the same value property (a
  /// collision). Fails closed loud rather than mis-wire the explicit pairing.
  invalidExplicitWritePairing,

  /// A built-in widget whose Flutter constructor requires an argument the
  /// built-in catalog cannot supply to the A2UI emit (a required callback
  /// marked optional by the catalog's event convention, or a required
  /// style/decoration represented only by a decompose / not as a property), so
  /// emitting it would produce an uncompilable constructor call. Scoped out by
  /// a contained interim guard so the merged built-in catalog compiles; the
  /// proper fix (the built-in emits the argument correctly) is tracked
  /// separately.
  unconstructableBuiltIn,
}

/// One omitted field in the A2UI Dart coverage record.
final class A2uiDartFieldOmission {
  /// Creates an omitted-field record.
  const A2uiDartFieldOmission({
    required this.widgetName,
    required this.fieldName,
    required this.reason,
  });

  /// Catalog widget name.
  final String widgetName;

  /// Catalog property name.
  final String fieldName;

  /// Why the field was omitted.
  final A2uiDartCoverageReason reason;
}

/// One widget dropped from the emitted A2UI Dart catalog.
final class A2uiDartWidgetDrop {
  /// Creates a dropped-widget record.
  const A2uiDartWidgetDrop({
    required this.widgetName,
    required this.reason,
    this.fieldName,
  });

  /// Catalog widget name.
  final String widgetName;

  /// Why the widget was dropped.
  final A2uiDartCoverageReason reason;

  /// The field that forced the drop, when field-specific.
  final String? fieldName;
}

/// Coverage summary for the A2UI Dart emitter.
final class A2uiDartCoverage {
  /// Creates a coverage summary.
  const A2uiDartCoverage({
    required this.totalWidgetCount,
    required this.omittedFields,
    required this.droppedWidgets,
  });

  /// Widgets presented to the classifier.
  final int totalWidgetCount;

  /// Optional fields deliberately omitted while still emitting the widget.
  final List<A2uiDartFieldOmission> omittedFields;

  /// Widgets deliberately not emitted.
  final List<A2uiDartWidgetDrop> droppedWidgets;

  /// Number of widgets emitted.
  int get emittableWidgetCount => totalWidgetCount - droppedWidgets.length;
}

/// Classified A2UI Dart catalog plan.
final class A2uiDartCatalogPlan {
  const A2uiDartCatalogPlan._({
    required this.widgets,
    required this.coverage,
  });

  /// Widgets that can be emitted.
  final List<A2uiDartWidgetPlan> widgets;

  /// Coverage details for omitted fields and dropped widgets.
  final A2uiDartCoverage coverage;
}

/// Classified widget emission plan.
final class A2uiDartWidgetPlan {
  const A2uiDartWidgetPlan._({
    required this.entry,
    required this.fields,
    this.writeBacks = const [],
    this.dispatches = const [],
  });

  /// Source catalog entry.
  final WidgetEntry entry;

  /// Fields included in schema and construction.
  final List<A2uiDartFieldPlan> fields;

  /// Write-back callbacks lowered to declarative data-model updates. These are
  /// emitted as constructor arguments (and drive the prelude path derivation)
  /// but are NOT data fields, so they never enter the data schema.
  final List<A2uiWriteBack> writeBacks;

  /// Dispatch callbacks (`VoidCallback`) lowered to an outward `dispatchEvent`
  /// with a compile-fixed event name. Emitted as constructor arguments; never
  /// data fields, so they never enter the data schema.
  final List<PropertyEntry> dispatches;
}

/// One lowered write-back pair: an interactive callback that writes its value
/// back into the data model at the path bound by its paired value property.
@immutable
final class A2uiWriteBack {
  /// Creates a write-back over [callbackProperty], targeting the data path of
  /// the paired [valuePropertyName].
  const A2uiWriteBack({
    required this.callbackProperty,
    required this.valuePropertyName,
  });

  /// The interactive callback property being lowered.
  final PropertyEntry callbackProperty;

  /// The paired value property whose data path the callback writes.
  final String valuePropertyName;

  @override
  bool operator ==(Object other) =>
      other is A2uiWriteBack &&
      other.callbackProperty == callbackProperty &&
      other.valuePropertyName == valuePropertyName;

  @override
  int get hashCode => Object.hash(callbackProperty, valuePropertyName);
}

/// Classified field emission plan.
final class A2uiDartFieldPlan {
  const A2uiDartFieldPlan._({
    required this.property,
    required this.emission,
  });

  /// Source catalog property.
  final PropertyEntry property;

  /// How the field is emitted — a bound data value or a host-built child slot.
  final A2uiFieldEmission emission;
}

/// How an included catalog field is emitted: either a bound data value
/// (described by an [A2uiSchemaNode]) or a host-built child slot (described by
/// an [A2uiChildSlot]). A field is exactly one of these — data is bound, a
/// child is built — so they form a sealed pair, switched exhaustively by the
/// schema projection and the widget-builder generation.
@immutable
sealed class A2uiFieldEmission {
  const A2uiFieldEmission();
}

/// Immutable, normalized JSON Schema constraint keywords for one data field.
///
/// This is deliberately attached to the per-property emission IR rather than
/// the recursive shape nodes: authored constraints describe the property as a
/// whole, not every nested occurrence of the same Dart shape.
@immutable
final class A2uiConstraintSet {
  const A2uiConstraintSet._(this.keywords);

  /// Copies the admitted typed constraints into canonical keyword order.
  factory A2uiConstraintSet.fromTyped(RestageConstraints constraints) {
    if (constraints.isEmpty) return empty;
    return A2uiConstraintSet._(
      Map<String, Object?>.unmodifiable({
        if (constraints.minimum != null) 'minimum': constraints.minimum,
        if (constraints.exclusiveMinimum != null)
          'exclusiveMinimum': constraints.exclusiveMinimum,
        if (constraints.maximum != null) 'maximum': constraints.maximum,
        if (constraints.exclusiveMaximum != null)
          'exclusiveMaximum': constraints.exclusiveMaximum,
        if (constraints.allowedValues != null)
          'enum': List<Object?>.unmodifiable(constraints.allowedValues!),
        if (constraints.pattern != null) 'pattern': constraints.pattern,
        if (constraints.minLength != null) 'minLength': constraints.minLength,
        if (constraints.maxLength != null) 'maxLength': constraints.maxLength,
        if (constraints.minItems != null) 'minItems': constraints.minItems,
        if (constraints.maxItems != null) 'maxItems': constraints.maxItems,
      }),
    );
  }

  /// The byte-neutral constraint set used by unconstrained fields.
  static const empty = A2uiConstraintSet._(<String, Object?>{});

  /// Canonically ordered JSON Schema keywords consumed by both projectors.
  final Map<String, Object?> keywords;

  /// Whether the field is unconstrained.
  bool get isEmpty => keywords.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is A2uiConstraintSet &&
      const DeepCollectionEquality().equals(other.keywords, keywords);

  @override
  int get hashCode => const DeepCollectionEquality().hash(keywords);
}

/// A bound data field, described by its data-shape [node].
@immutable
final class A2uiDataField extends A2uiFieldEmission {
  /// Creates a data-field emission over [node].
  ///
  /// [rich] is true for an analyzer-fed customer data shape (reconstructed
  /// through the value-builder, bound via `BoundObject`); false for the
  /// catalog-fed leaf binding. Catalog classification always yields false, so
  /// the built-in catalogs are byte-neutral.
  ///
  /// [writeBack] is true for the value property of a write-back pair: its leaf
  /// `Bound*` read is rewritten to the resolved data path `{'path': P}` (rather
  /// than the raw value) so it is subscribed to the exact path the paired
  /// callback writes. Catalog classification always yields false.
  const A2uiDataField(
    this.node, {
    this.rich = false,
    this.writeBack = false,
    this.constraints = A2uiConstraintSet.empty,
  });

  /// The data-shape node projected to a schema and a typed value binding.
  final A2uiSchemaNode node;

  /// Whether this field's value is reconstructed via the value-builder (a rich
  /// customer data shape) rather than the catalog-fed leaf binding.
  final bool rich;

  /// Whether this field is the value property of a write-back pair (its read is
  /// rewritten to the write-back data path).
  final bool writeBack;

  /// Normalized property constraints projected onto the literal schema only.
  final A2uiConstraintSet constraints;

  @override
  bool operator ==(Object other) =>
      other is A2uiDataField &&
      other.node == node &&
      other.rich == rich &&
      other.writeBack == writeBack &&
      other.constraints == constraints;

  @override
  int get hashCode => Object.hash(node, rich, writeBack, constraints);
}

/// A host-built child slot, described by its [slot] kind.
@immutable
final class A2uiChildField extends A2uiFieldEmission {
  /// Creates a child-slot emission over [slot].
  const A2uiChildField(this.slot);

  /// The child-slot kind (single child id, or a list of child ids).
  final A2uiChildSlot slot;

  @override
  bool operator ==(Object other) =>
      other is A2uiChildField && other.slot == slot;

  @override
  int get hashCode => slot.hashCode;
}

/// A map from `(widgetName, propertyName)` to the analyzer-fed shape for that
/// property, threaded alongside the serialized catalog (which has no analyzer
/// access). Structured object shapes take the rich-data path; scalar-list
/// shapes remain reactive leaf fields; catalog leaf and child shapes use the
/// analyzer only to retain source nullability.
typedef A2uiRichShapes = Map<(String, String), A2uiSchemaNode>;

/// Classifies [catalog] for A2UI Dart emission.
///
/// [eventSeam] carries the classified callback signature for each customer
/// `@RestageWidget` interactive property (the catalog discards it). A property
/// present there is lowered to a declarative action (write-back / dispatch);
/// every property absent from the seam takes the unchanged catalog-fed path, so
/// the built-in catalogs are byte-neutral.
A2uiDartCatalogPlan classifyA2uiCatalogDart(
  Catalog catalog, {
  NativeCatalogIndex? nativeIndex,
  A2uiRichShapes? richShapes,
  A2uiEventSeam? eventSeam,
  A2uiPairingSeam? pairingSeam,
}) {
  _rejectUnknownConstraintExtensions(catalog);
  final widgets = <A2uiDartWidgetPlan>[];
  final omitted = <A2uiDartFieldOmission>[];
  final dropped = <A2uiDartWidgetDrop>[];
  // Whether the generated file will import-prefix at least one customer
  // library — the condition under which a catalog-fed enum that lacks a
  // resolvable library (no `EnumShape`) cannot be safely spelled bare.
  final prefixesCustomerLibs =
      _catalogPrefixesCustomerLibs(catalog, richShapes);

  for (final entry in catalog.widgets) {
    final drop = _dropReasonForWidget(entry);
    if (drop != null) {
      _rejectA2uiConstraintsForDroppedWidget(entry, drop);
      dropped.add(drop);
      continue;
    }

    // Resolve the interaction lowering (write-back pairs + dispatch callbacks)
    // for this widget. A built-in catalog carries no seam → no interactions →
    // the loop is byte-neutral.
    final interactions =
        _resolveInteractions(entry, eventSeam, pairingSeam, richShapes);

    final consumed = _decomposeConsumedNames(entry);
    final fields = <A2uiDartFieldPlan>[];
    final writeBacks = <A2uiWriteBack>[];
    final dispatches = <PropertyEntry>[];
    A2uiDartWidgetDrop? lateDrop;
    for (final property in entry.properties) {
      if (consumed.contains(property.name)) {
        _rejectA2uiConstraintOmission(
          entry,
          property,
          'native decompose field is omitted',
        );
        omitted.add(
          A2uiDartFieldOmission(
            widgetName: entry.name,
            fieldName: property.name,
            reason: A2uiDartCoverageReason.nativeDecomposeUnsupported,
          ),
        );
        continue;
      }

      // A write-back callback is lowered to a declarative data-model update (or
      // fails closed loud), outside the catalog-fed field classification.
      final wired = interactions?.writeBacks
          .firstWhereOrNull((w) => w.callbackProperty.name == property.name);
      if (wired != null) {
        _rejectA2uiConstraintOmission(
          entry,
          property,
          'write-back callback is lowered without a data-schema node',
        );
        writeBacks.add(wired);
        continue;
      }
      // A dispatch callback is lowered to an outward `dispatchEvent`, likewise
      // outside the catalog-fed field classification.
      if (interactions?.dispatches.any((d) => d.name == property.name) ??
          false) {
        _rejectA2uiConstraintOmission(
          entry,
          property,
          'dispatch callback is lowered without a data-schema node',
        );
        dispatches.add(property);
        continue;
      }
      final scopedReason = interactions?.scopedByCallbackName[property.name];
      if (scopedReason != null) {
        _rejectA2uiConstraintOmission(
          entry,
          property,
          'callback-scoped field is omitted (${scopedReason.name})',
        );
        if (property.required) {
          lateDrop = A2uiDartWidgetDrop(
            widgetName: entry.name,
            fieldName: property.name,
            reason: scopedReason,
          );
          break;
        }
        omitted.add(
          A2uiDartFieldOmission(
            widgetName: entry.name,
            fieldName: property.name,
            reason: scopedReason,
          ),
        );
        continue;
      }

      final field = _classifyField(
        entry,
        property,
        richShapes,
        prefixesCustomerLibs,
      );
      switch (field) {
        case _EmitField(:final plan):
          // Mark the value property of a write-back pair so its leaf read is
          // rewritten to the write-back data path.
          final emission = plan.emission;
          final isBoundValue = interactions != null &&
              interactions.writeBacks
                  .any((w) => w.valuePropertyName == property.name);
          if (isBoundValue && emission is A2uiDataField) {
            fields.add(
              A2uiDartFieldPlan._(
                property: plan.property,
                emission: A2uiDataField(
                  emission.node,
                  rich: emission.rich,
                  writeBack: true,
                  constraints: emission.constraints,
                ),
              ),
            );
          } else {
            fields.add(plan);
          }
        case _OmitField(:final omission):
          omitted.add(omission);
        case _DropWidget(:final drop):
          lateDrop = drop;
      }
      if (lateDrop != null) {
        break;
      }
    }

    if (lateDrop != null) {
      _rejectA2uiConstraintsForDroppedWidget(entry, lateDrop);
      dropped.add(lateDrop);
      continue;
    }
    widgets.add(
      A2uiDartWidgetPlan._(
        entry: entry,
        fields: fields,
        writeBacks: writeBacks,
        dispatches: dispatches,
      ),
    );
  }

  return A2uiDartCatalogPlan._(
    widgets: List.unmodifiable(widgets),
    coverage: A2uiDartCoverage(
      totalWidgetCount: catalog.widgets.length,
      omittedFields: List.unmodifiable(omitted),
      droppedWidgets: List.unmodifiable(dropped),
    ),
  );
}

void _rejectUnknownConstraintExtensions(Catalog catalog) {
  for (final widget in catalog.widgets) {
    for (final property in widget.properties) {
      if (property.constraints.extensions.isEmpty) continue;
      final keywords = property.constraints.extensions.keys.toList()..sort();
      throw UnsupportedError(
        'A2UI projection cannot represent unknown constraint keywords on '
        'widget "${widget.name}", property "${property.name}": '
        '${keywords.join(', ')}.',
      );
    }
  }
}

/// Composes the genui `systemPromptFragments` for [plan]'s widgets, in the
/// plan's widget order (the production builder pre-sorts by library, then
/// name — this function itself does not sort).
///
/// For each widget, the fragment text is its [usageByWidget] entry when
/// non-empty, falling back to its catalog `description` when that is
/// non-empty; a widget with neither is skipped entirely (never an empty or
/// blank fragment line). Each surviving fragment is `"<name>: <text>"`.
///
/// This is the single source of the fragment list: both the generated
/// `.g.dart` (`emitA2uiCatalogDart`) and the standalone catalog document
/// (`emitA2uiCatalog`) call this same function, so they cannot drift.
List<String> composeSystemPromptFragments(
  A2uiDartCatalogPlan plan,
  Map<String, String> usageByWidget,
) {
  final fragments = <String>[];
  for (final widget in plan.widgets) {
    final name = widget.entry.name;
    final text = _normalizedDescription(usageByWidget[name]) ??
        _normalizedDescription(widget.entry.description);
    if (text != null) fragments.add('$name: $text');
  }
  return fragments;
}

/// Emits Dart source defining genui `CatalogItem`s for [catalog].
String emitA2uiCatalogDart(
  Catalog catalog, {
  RestageStampedA2uiCatalog? registration,
  NativeCatalogIndex? nativeIndex,
  A2uiRichShapes? richShapes,
  A2uiEventSeam? eventSeam,
  A2uiPairingSeam? pairingSeam,
  Map<String, String> usageByWidget = const {},
}) =>
    _emitA2uiCatalogDart(
      catalog,
      registration: registration,
      nativeIndex: nativeIndex,
      richShapes: richShapes,
      eventSeam: eventSeam,
      pairingSeam: pairingSeam,
      usageByWidget: usageByWidget,
    );

/// Emits Dart source with canonical examples attached to their catalog items.
///
/// This production-builder seam is intentionally not exported from the public
/// package barrel. [exampleRegistry] is neutral canonical data: component name
/// to example name to compact canonical component-array JSON. Widgetbook and
/// other visual tools adapt the generated registry downstream.
String emitA2uiCatalogDartWithExampleRegistry(
  Catalog catalog, {
  required Map<String, Map<String, String>> exampleRegistry,
  RestageStampedA2uiCatalog? registration,
  NativeCatalogIndex? nativeIndex,
  A2uiRichShapes? richShapes,
  A2uiEventSeam? eventSeam,
  A2uiPairingSeam? pairingSeam,
  Map<String, String> usageByWidget = const {},
}) =>
    _emitA2uiCatalogDart(
      catalog,
      exampleRegistry: exampleRegistry,
      registration: registration,
      nativeIndex: nativeIndex,
      richShapes: richShapes,
      eventSeam: eventSeam,
      pairingSeam: pairingSeam,
      usageByWidget: usageByWidget,
    );

String _emitA2uiCatalogDart(
  Catalog catalog, {
  Map<String, Map<String, String>>? exampleRegistry,
  RestageStampedA2uiCatalog? registration,
  NativeCatalogIndex? nativeIndex,
  A2uiRichShapes? richShapes,
  A2uiEventSeam? eventSeam,
  A2uiPairingSeam? pairingSeam,
  Map<String, String> usageByWidget = const {},
}) {
  final plan = classifyA2uiCatalogDart(
    catalog,
    nativeIndex: nativeIndex,
    richShapes: richShapes,
    eventSeam: eventSeam,
    pairingSeam: pairingSeam,
  );
  final orderedExampleRegistry = exampleRegistry == null
      ? null
      : _orderedExampleRegistry(plan, exampleRegistry);
  final importUris = _importUris(plan);
  // Every customer library is imported under a distinct prefix (`p0`, `p1`, …),
  // so two same-named types from different libraries can never collide in the
  // generated source. Flutter / dart: / genui / json_schema_builder stay
  // unprefixed, so the built-in (flutter-only) catalogs are byte-neutral.
  final prefixes = _assignImportPrefixes(importUris);
  // One value-builder over every widget's rich data nodes (file-level dedup of
  // the per-class reconstruction helpers). With no rich field it emits nothing,
  // so the built-ins are unchanged.
  final dataBuilder = A2uiDataBuilder(
    _collectRichNodes(plan),
    prefixes: prefixes,
  );
  final emitsControlledValue = plan.widgets.any(
    (widget) => widget.fields.any(_usesControlledValue),
  );
  _assertPrefixableSpellings(plan, dataBuilder);
  final buf = StringBuffer();
  writeGeneratedHeader(buf);
  // The emitter emits its full helper set unconditionally (child-slot, color,
  // font-weight, and per-class rich-shape reconstruction helpers); a catalog
  // that uses only some leaves the rest unreferenced. Suppress the resulting
  // analyzer warning in the generated file so a consumer's `flutter analyze`
  // stays clean without them having to exclude the file.
  buf
    ..writeln('// ignore_for_file: unused_element')
    ..writeln();

  for (final uri in importUris) {
    final prefix = prefixes[uri];
    buf.writeln(
      prefix == null ? "import '$uri';" : "import '$uri' as $prefix;",
    );
  }
  if (emitsControlledValue) {
    buf.writeln("import 'dart:async';");
  }
  buf
    ..writeln("import 'package:genui/genui.dart';")
    ..writeln("import 'package:json_schema_builder/json_schema_builder.dart';")
    ..writeln();
  if (registration != null) {
    buf
      ..writeln('/// Items for the generated custom-only catalog.')
      ..writeln(
        '/// A composed Catalog must use a new application-owned catalog ID;',
      )
      ..writeln('/// do not reuse the generated catalog ID for a different')
      ..writeln('/// item or schema set.');
  }
  buf
    ..writeln('List<CatalogItem> buildRestageCatalogItems() {')
    ..writeln('  return <CatalogItem>[');

  for (final widget in plan.widgets) {
    _writeCatalogItem(
      buf,
      widget,
      dataBuilder,
      prefixes,
      catalogIdExpression:
          registration == null ? 'null' : 'restageA2uiCatalogId',
      exampleNames:
          orderedExampleRegistry?[widget.entry.name]?.keys ?? const [],
    );
  }

  final fragments = composeSystemPromptFragments(plan, usageByWidget);
  if (registration != null) {
    _verifyRegistrationContract(
      registration,
      plan,
      nonIdentitySystemPromptFragments: fragments,
    );
  }
  final emittedFragments = registration?.systemPromptFragments ?? fragments;
  buf
    ..writeln('  ];')
    ..writeln('}')
    ..writeln();
  if (orderedExampleRegistry != null) {
    _writeExampleRegistry(buf, orderedExampleRegistry);
  }
  if (registration != null) {
    buf
      ..writeln(
        '/// Content address for exactly the generated custom-only catalog.',
      )
      ..writeln(
        '/// Default A2A supportedCatalogIds use requires server registration',
      )
      ..writeln('/// of this exact predefined catalog contract.')
      ..writeln(
        '/// GenUI 0.10.1 inline catalogs are serialization-only here;',
      )
      ..writeln(
        '/// no end-to-end inline server interoperability is claimed.',
      )
      ..writeln(
        'const String restageA2uiCatalogId = '
        '${_dartStringLiteral(registration.documentId)};',
      )
      ..writeln();
  }
  buf.writeln(
    'const List<String> _restageA2uiSystemPromptFragments = <String>[',
  );
  for (final fragment in emittedFragments) {
    buf.writeln('  ${_dartStringLiteral(fragment)},');
  }
  buf
    ..writeln('];')
    ..writeln();
  if (registration != null) {
    buf
      ..writeln(
        '/// Builds the generated custom-only GenUI catalog identified by',
      )
      ..writeln('/// [restageA2uiCatalogId].')
      ..writeln('///')
      ..writeln('/// To compose a different catalog, use')
      ..writeln('/// [buildRestageCatalogItems] and assign the new Catalog an')
      ..writeln('/// application-owned catalog ID.');
  } else {
    buf
      ..writeln('/// The fully-assembled GenUI catalog: the generated items')
      ..writeln('/// plus the system-prompt fragments composed from each')
      ..writeln("/// widget's usage note (falling back to its description).");
  }
  buf
    ..writeln('Catalog buildRestageCatalog() => Catalog(')
    ..writeln('      buildRestageCatalogItems(),');
  if (registration != null) {
    buf.writeln('      catalogId: restageA2uiCatalogId,');
  }
  buf
    ..writeln('      systemPromptFragments: _restageA2uiSystemPromptFragments,')
    ..writeln('    );')
    ..writeln()
    ..writeln(
      'Widget? _restageA2uiBuildChild(CatalogItemContext itemContext, '
      'Object? childId) {',
    )
    ..writeln('  if (childId is! String || childId.isEmpty) return null;')
    // genui 0.10.1: CatalogItemContext.buildChild is a typed callback field
    // `Widget Function(String id, [DataContext? dataContext])` — render a
    // child by id with a direct typed call (no dynamic bridge).
    ..writeln('  return itemContext.buildChild(childId);')
    ..writeln('}')
    ..writeln()
    ..writeln(
      'Never _restageA2uiRequiredChildError(Object? childId, '
      'String propertyContext) {',
    )
    ..writeln('  final String reason;')
    ..writeln('  if (childId == null) {')
    ..writeln("    reason = 'the value was null or missing';")
    ..writeln('  } else if (childId is! String) {')
    ..writeln(
      r"    reason = 'the value had runtime type ${childId.runtimeType}, ' ",
    )
    ..writeln("        'but a String component id is required';")
    ..writeln('  } else if (childId.isEmpty) {')
    ..writeln("    reason = 'the value was the empty string';")
    ..writeln('  } else {')
    ..writeln(
      r'''    reason = 'component id "$childId" is not registered';''',
    )
    ..writeln('  }')
    ..writeln('  throw StateError(')
    ..writeln(
      r"""    'Required A2UI child "$propertyContext" could not resolve: '""",
    )
    ..writeln(r"    '$reason. Provide a non-empty String id for a component '")
    ..writeln("    'registered on this surface.',")
    ..writeln('  );')
    ..writeln('}')
    ..writeln()
    ..writeln(
      'Never _restageA2uiRequiredChildBuildError(String childId, '
      'String propertyContext, Object error) {',
    )
    ..writeln('  throw StateError(')
    ..writeln(
      r"""    'Required A2UI child "$propertyContext" with component id '""",
    )
    ..writeln(
      r"""    '"$childId" failed to build (${error.runtimeType}).',""",
    )
    ..writeln('  );')
    ..writeln('}')
    ..writeln()
    ..writeln(
      'Widget _restageA2uiRequireChild(CatalogItemContext itemContext, '
      'Object? childId, String propertyContext) {',
    )
    ..writeln(
      '  if (childId is! String || childId.isEmpty) {',
    )
    ..writeln('    _restageA2uiRequiredChildError(childId, propertyContext);')
    ..writeln('  }')
    ..writeln('  if (itemContext.getComponent(childId) == null) {')
    ..writeln('    _restageA2uiRequiredChildError(childId, propertyContext);')
    ..writeln('  }')
    ..writeln('  late final Widget child;')
    ..writeln('  try {')
    ..writeln('    child = itemContext.buildChild(childId);')
    ..writeln('  } catch (error) {')
    ..writeln(
      '    _restageA2uiRequiredChildBuildError(childId, '
      'propertyContext, error);',
    )
    ..writeln('  }')
    // GenUI 0.10.1's Surface converts a child build exception into an errored
    // FallbackWidget. Treat that as a failed required child, while preserving
    // loading and empty fallbacks whose error is null.
    ..writeln('  if (child is FallbackWidget && child.error != null) {')
    ..writeln(
      '    _restageA2uiRequiredChildBuildError(childId, '
      'propertyContext, child.error!);',
    )
    ..writeln('  }')
    ..writeln('  return child;')
    ..writeln('}')
    ..writeln()
    ..writeln(
      'List<Widget> _restageA2uiBuildChildren(CatalogItemContext itemContext, '
      'Object? childIds) {',
    )
    ..writeln('  if (childIds is! List<Object?>) return const <Widget>[];')
    ..writeln('  return <Widget>[')
    ..writeln('    for (final childId in childIds)')
    ..writeln('      if (_restageA2uiBuildChild(itemContext, childId) != null)')
    ..writeln('        _restageA2uiBuildChild(itemContext, childId)!,')
    ..writeln('  ];')
    ..writeln('}')
    ..writeln()
    ..writeln('Color? _restageA2uiColor(String? value) {')
    ..writeln('  if (value == null || value.isEmpty) return null;')
    ..writeln("  final normalized = value.startsWith('#')")
    ..writeln('      ? value.substring(1)')
    ..writeln('      : value.startsWith(')
    ..writeln("              '0x',")
    ..writeln('            )')
    ..writeln('          ? value.substring(2)')
    ..writeln('          : value;')
    ..writeln('  final parsed = int.tryParse(normalized, radix: 16);')
    ..writeln('  if (parsed == null) return null;')
    ..writeln(
      '  if (normalized.length <= 6) return Color(0xFF000000 | parsed);',
    )
    ..writeln('  return Color(parsed);')
    ..writeln('}')
    ..writeln()
    ..writeln('FontWeight _restageA2uiFontWeight(')
    ..writeln('  num? value,')
    ..writeln('  FontWeight fallback,')
    ..writeln(') {')
    ..writeln('  if (value == null) return fallback;')
    ..writeln('  final index = value.toInt();')
    ..writeln('  if (index < 0 || index >= FontWeight.values.length) {')
    ..writeln('    return fallback;')
    ..writeln('  }')
    ..writeln('  return FontWeight.values[index];')
    ..writeln('}');

  // The value-builder's once-emitted reconstruction support (the typed cast,
  // map helpers, depth ceiling, and per-class helpers) — empty when no rich
  // shape is present, so the built-in catalogs gain nothing.
  for (final definition in dataBuilder.supportDefinitions()) {
    buf
      ..writeln()
      ..writeln(definition);
  }
  if (emitsControlledValue) {
    buf
      ..writeln()
      ..writeln(_controlledValueSupportDefinition);
  }

  return formatGeneratedDart(buf.toString()).trimRight();
}

Map<String, Map<String, String>> _orderedExampleRegistry(
  A2uiDartCatalogPlan plan,
  Map<String, Map<String, String>> registry,
) {
  final catalogNames = <String>{
    for (final widget in plan.widgets) widget.entry.name,
  };
  final unknownNames = registry.keys
      .where((name) => !catalogNames.contains(name))
      .toList()
    ..sort();
  if (unknownNames.isNotEmpty) {
    throw StateError(
      'A2UI example registry contains component(s) outside the generated '
      'catalog: ${unknownNames.join(', ')}.',
    );
  }

  final componentNames = registry.keys.toList()..sort();
  return <String, Map<String, String>>{
    for (final componentName in componentNames)
      componentName: <String, String>{
        for (final exampleName
            in (registry[componentName]!.keys.toList()..sort()))
          exampleName: registry[componentName]![exampleName]!,
      },
  };
}

void _writeExampleRegistry(
  StringBuffer buf,
  Map<String, Map<String, String>> registry,
) {
  buf
    ..writeln('/// Canonical authored examples keyed by catalog component and')
    ..writeln('/// example name. Both map levels preserve deterministic order.')
    ..writeln(
      'const Map<String, Map<String, String>> '
      'restageA2uiExampleRegistry = <String, Map<String, String>>{',
    );
  for (final component in registry.entries) {
    buf.writeln(
      '  ${_dartStringLiteral(component.key)}: <String, String>{',
    );
    for (final example in component.value.entries) {
      buf.writeln(
        '    ${_dartStringLiteral(example.key)}: '
        '${_dartStringLiteral(example.value)},',
      );
    }
    buf.writeln('  },');
  }
  buf
    ..writeln('};')
    ..writeln();
}

void _verifyRegistrationContract(
  RestageStampedA2uiCatalog registration,
  A2uiDartCatalogPlan plan, {
  required List<String> nonIdentitySystemPromptFragments,
}) {
  final projectedComponents = <String, Object?>{
    for (final widget in plan.widgets)
      widget.entry.name: a2uiCatalogComponentSchemaMapForPlan(widget),
  };
  final registeredComponents = <String, Object?>{
    for (final component in registration.components)
      component.name: component.dataSchema,
  };
  const equality = DeepCollectionEquality();
  if (!equality.equals(projectedComponents, registeredComponents)) {
    throw StateError(
      'A2UI Dart emission registration mismatch: generated component schemas '
      'must equal the content-addressed registration contract.',
    );
  }
  if (registration.functions.isNotEmpty) {
    throw StateError(
      'A2UI Dart emission registration mismatch: function contracts were '
      'registered but no generated client functions are available.',
    );
  }
  if (!equality.equals(
    registration.nonIdentitySystemPromptFragments,
    nonIdentitySystemPromptFragments,
  )) {
    throw StateError(
      'A2UI Dart emission registration mismatch: producer guidance must equal '
      'the content-addressed registration contract.',
    );
  }
}

/// Every analyzer-fed rich data node across the plan's widgets, in widget then
/// field order — the value-builder dedups shared/recursive classes itself.
List<A2uiSchemaNode> _collectRichNodes(A2uiDartCatalogPlan plan) => [
      for (final widget in plan.widgets)
        for (final field in widget.fields)
          if (field.emission case A2uiDataField(:final node, rich: true)) node,
    ];

/// Whether emitting [catalog] (+ its [richShapes]) will import-prefix at least
/// one customer library — i.e. a widget constructor or a rich data shape lives
/// in a prefixable library. Computed before classification (independent of the
/// plan) so a catalog-fed enum lacking a library can be scoped out when bare
/// spelling is no longer safe.
bool _catalogPrefixesCustomerLibs(Catalog catalog, A2uiRichShapes? richShapes) {
  for (final widget in catalog.widgets) {
    final uri = _sourceUri(widget.flutterType);
    if (uri != null && isPrefixableLibrary(uri)) return true;
  }
  for (final node in richShapes?.values ?? const <A2uiSchemaNode>[]) {
    final libraries = <String>{};
    _collectRichNodeLibraries(node, libraries);
    if (libraries.any(isPrefixableLibrary)) return true;
  }
  return false;
}

/// Assigns a distinct import prefix (`p0`, `p1`, …) to each customer library in
/// [importUris], in sorted-URI order (deterministic). Framework libraries
/// ([isPrefixableLibrary] false) are absent — they import unprefixed.
Map<String, String> _assignImportPrefixes(Set<String> importUris) {
  final prefixable = importUris.where(isPrefixableLibrary).toList()..sort();
  return {
    for (var i = 0; i < prefixable.length; i++) prefixable[i]: 'p$i',
  };
}

/// Fails closed LOUD, at emit time, on any rich field whose data shape carries
/// a customer generic instantiated with another customer type (`Box<Inner>`) —
/// a spelling the leading-identifier prefix cannot qualify (the flat
/// instantiated spelling has no per-argument library). The diagnostic names the
/// widget, the field, and the offending shape, and points at the recursive-
/// prefix follow-up, so a developer sees WHY and WHERE rather than meeting a
/// cryptic compile error in their generated build.
void _assertPrefixableSpellings(
  A2uiDartCatalogPlan plan,
  A2uiDataBuilder dataBuilder,
) {
  for (final widget in plan.widgets) {
    for (final field in widget.fields) {
      if (field.emission case A2uiDataField(:final node, rich: true)) {
        final unprefixable = dataBuilder.firstUnprefixableSpelling(node);
        if (unprefixable != null) {
          throw StateError(
            'A2UI: ${widget.entry.name}.${field.property.name} uses the data '
            'shape "$unprefixable" — a customer generic type instantiated with '
            'another customer type, whose generated spelling cannot be '
            'import-prefixed component-by-component (the flat instantiated '
            'spelling carries no per-argument library). Failing closed rather '
            'than emit an ambiguous/uncompilable type; full recursive prefixing '
            'is a tracked follow-up.',
          );
        }
      }
    }
  }
}

void _writeCatalogItem(
  StringBuffer buf,
  A2uiDartWidgetPlan widget,
  A2uiDataBuilder dataBuilder,
  Map<String, String> prefixes, {
  required String catalogIdExpression,
  required Iterable<String> exampleNames,
}) {
  final entry = widget.entry;
  // Rich nested objects/maps/records/lists-of-objects are reconstructed
  // DIRECTLY from the widget data as a builder prelude (no BoundObject — its
  // `{path}`/`{call}` binding-sentinel patterns would misread a literal value
  // whose own field/key is named `path`/`call`). Top-level scalars/enums/
  // leaf-lists keep their reactive `Bound*` wrappers around the constructor.
  final prelude = [
    // The write-back path derivation comes first (it only reads `data`); both
    // the value field's `Bound*` and the callback's update reference its local.
    ..._writeBackPreludeStatements(widget),
    ..._richPreludeStatements(widget, dataBuilder),
  ];
  final returnExpression = _widgetReturnExpression(
    widget,
    prefixes,
    catalogIdExpression: catalogIdExpression,
  );
  buf
    ..writeln('    CatalogItem(')
    ..writeln('      name: ${_dartStringLiteral(entry.name)},')
    ..writeln('      dataSchema: ${_schemaExpression(widget)},')
    ..writeln('      widgetBuilder: (itemContext) {')
    ..writeln('        final data = itemContext.data as Map<String, Object?>;');
  for (final statement in prelude) {
    buf.writeln('        $statement');
  }
  buf
    ..writeln('        return $returnExpression;')
    ..writeln('      },');
  if (exampleNames.isNotEmpty) {
    buf.writeln('      exampleData: <ExampleBuilderCallback>[');
    for (final exampleName in exampleNames) {
      final componentLiteral = _dartStringLiteral(entry.name);
      final exampleLiteral = _dartStringLiteral(exampleName);
      final registryLookup =
          'restageA2uiExampleRegistry[$componentLiteral]![$exampleLiteral]!';
      buf.writeln('        () => $registryLookup,');
    }
    buf.writeln('      ],');
  }
  buf.writeln('    ),');
}

String _schemaExpression(A2uiDartWidgetPlan widget) {
  return _widgetDataSchemaExpressionForLayout(
    a2uiWidgetSchemaLayoutForPlan(widget),
    widgetDescription: _normalizedDescription(widget.entry.description),
  );
}

/// A developer-authored annotation text (a `@RestageProperty`/`@RestageWidget`
/// description or usage note) with an absent/blank value normalized to `null`
/// — an omitted description never emits an empty `description:` key, and an
/// omitted usage note falls through to the description.
String? _normalizedDescription(String? description) {
  final trimmed = description?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// Maps each field's property name to its normalized description, omitting
/// fields with no (or blank) description.
Map<String, String> _fieldDescriptions(List<A2uiDartFieldPlan> fields) => {
      for (final field in fields)
        if (_normalizedDescription(field.property.description) case final desc?)
          field.property.name: desc,
    };

/// One field in a widget's data schema: its property name, whether it is
/// required (present), and how it is emitted.
typedef A2uiWidgetField = ({
  String name,
  bool required,
  A2uiFieldEmission emission,
});

/// The effective schema-document layout shared by Dart emission, standalone
/// map emission, and canonical-example validation.
///
/// [fields] carry normalized top-level property-description overlays.
/// [residualDescriptions] retain the description-only scalar path. The
/// registry and its derived definition layout therefore describe the exact
/// schema document emitted for those effective fields.
@internal
final class A2uiWidgetSchemaLayout {
  const A2uiWidgetSchemaLayout._({
    required this.fields,
    required this.residualDescriptions,
    required this.registry,
    required this.hoistTargets,
    required this.includesSyntheticRoot,
    required this.definitionIds,
    required this.safeDefinitionKeys,
  });

  /// Effective widget fields after top-level occurrence overlays.
  final List<A2uiWidgetField> fields;

  /// Normalized property descriptions not represented by node overlays.
  final Map<String, String> residualDescriptions;

  /// Canonical definitions discovered from [fields].
  final A2uiDefinitionRegistry registry;

  /// Definition ids emitted at the root `$defs` object.
  final Set<String> hoistTargets;

  /// Whether the anonymous widget root is emitted beside [hoistTargets].
  final bool includesSyntheticRoot;

  /// Every emitted `$defs` id, including the synthetic root when present.
  final Set<String> definitionIds;

  /// Collision-safe emitted `$defs` key by canonical definition id.
  final Map<String, String> safeDefinitionKeys;
}

/// Resolves the exact effective schema layout for one classified widget plan.
///
/// Property descriptions are normalized here once, before they can affect
/// description-separation hoisting, so every consumer sees the same document.
@internal
A2uiWidgetSchemaLayout a2uiWidgetSchemaLayoutForPlan(
  A2uiDartWidgetPlan plan,
) {
  final descriptions = _fieldDescriptions(plan.fields);
  return _buildA2uiWidgetSchemaLayout(
    [
      for (final field in plan.fields)
        (
          name: field.property.name,
          required: field.property.required,
          emission: field.emission,
        ),
    ],
    (name) => descriptions[name],
  );
}

A2uiWidgetSchemaLayout _buildA2uiWidgetSchemaLayout(
  List<A2uiWidgetField> fields,
  String? Function(String fieldName)? fieldDescription,
) {
  final resolved = <A2uiWidgetField>[];
  final residual = <String, String>{};
  for (final field in fields) {
    final description =
        _normalizedDescription(fieldDescription?.call(field.name));
    final emission = field.emission;
    if (description != null && emission is A2uiDataField) {
      final node = _withOuterOccurrenceOverlay(emission.node, description);
      if (node != null) {
        resolved.add(
          (
            name: field.name,
            required: field.required,
            emission: A2uiDataField(
              node,
              rich: emission.rich,
              writeBack: emission.writeBack,
              constraints: emission.constraints,
            ),
          ),
        );
        continue;
      }
    }
    resolved.add(field);
    if (description != null) residual[field.name] = description;
  }
  final effectiveFields = List<A2uiWidgetField>.unmodifiable(resolved);
  final registry = A2uiDefinitionRegistry([
    for (final field in effectiveFields)
      if (field.emission case A2uiDataField(:final node)) node,
  ]);
  final hoistTargets = registry.hoistTargets;
  final includesSyntheticRoot = hoistTargets.isNotEmpty;
  final definitionIds = includesSyntheticRoot
      ? Set<String>.unmodifiable({
          a2uiSyntheticRootDefinitionId,
          ...hoistTargets,
        })
      : const <String>{};
  final safeDefinitionKeys = definitionIds.isEmpty
      ? const <String, String>{}
      : Map<String, String>.unmodifiable(
          assignA2uiSafeDefinitionKeys(definitionIds),
        );
  return A2uiWidgetSchemaLayout._(
    fields: effectiveFields,
    residualDescriptions: Map<String, String>.unmodifiable(residual),
    registry: registry,
    hoistTargets: hoistTargets,
    includesSyntheticRoot: includesSyntheticRoot,
    definitionIds: definitionIds,
    safeDefinitionKeys: safeDefinitionKeys,
  );
}

/// Applies the top-level `RestageProperty` occurrence overlay to every live
/// rich schema carrier, replacing any existing occurrence description.
/// Description-free scalars retain the legacy residual-description path so
/// their generated formatting stays byte-neutral. Dormant unions continue to
/// fail loud in projection.
A2uiSchemaNode? _withOuterOccurrenceOverlay(
  A2uiSchemaNode node,
  String description,
) =>
    switch (node) {
      ScalarNode(
        :final type,
        :final preserveNumericRuntimeType,
        :final occurrenceDescription,
        :final nullable,
      ) =>
        _normalizedDescription(occurrenceDescription) == null
            ? null
            : ScalarNode(
                type,
                preserveNumericRuntimeType: preserveNumericRuntimeType,
                occurrenceDescription: description,
                nullable: nullable,
              ),
      EnumNode(
        :final members,
        :final dartTypeName,
        :final libraryUri,
        :final nullable,
      ) =>
        EnumNode(
          members: members,
          dartTypeName: dartTypeName,
          libraryUri: libraryUri,
          occurrenceDescription: description,
          nullable: nullable,
        ),
      ListNode(:final element, :final nullable) => ListNode(
          element: element,
          occurrenceDescription: description,
          nullable: nullable,
        ),
      ObjectNode(
        :final fields,
        :final required,
        :final defId,
        :final construction,
        :final definitionDescription,
        :final nullable,
      ) =>
        ObjectNode(
          fields: fields,
          required: required,
          defId: defId,
          construction: construction,
          definitionDescription: definitionDescription,
          occurrenceDescription: description,
          nullable: nullable,
        ),
      MapNode(:final valueType, :final nullable) => MapNode(
          valueType: valueType,
          occurrenceDescription: description,
          nullable: nullable,
        ),
      RefNode(:final defId, :final nullable) => RefNode(
          defId,
          occurrenceDescription: description,
          nullable: nullable,
        ),
      _ => null,
    };

/// Projects a widget's whole data schema from its [fields].
///
/// This is the SOLE path for a widget's `dataSchema`: the `$defs`/`$ref`
/// two-pass runs ONCE at the document root, so reference targets and documented
/// definitions that need occurrence separation are hoisted to the top — never
/// nested inside a per-property schema, where a `#/$defs/…` pointer could not
/// resolve. Cross-field reuse of one hoisted type yields a single shared
/// `$def` referenced by each field.
///
/// With no reference target or description-separation target this is the bare
/// widget `S.object`, preserving the catalog-fed normal form.
///
/// [widgetDescription] and [fieldDescription] carry the developer-authored
/// `@RestageWidget`/`@RestageProperty` descriptions (already normalized —
/// blank/absent means no description); when both are absent the output is
/// unchanged from before descriptions existed.
String a2uiWidgetDataSchemaExpression(
  List<A2uiWidgetField> fields, {
  String? widgetDescription,
  String? Function(String fieldName)? fieldDescription,
}) =>
    _widgetDataSchemaExpressionForLayout(
      _buildA2uiWidgetSchemaLayout(fields, fieldDescription),
      widgetDescription: widgetDescription,
    );

String _widgetDataSchemaExpressionForLayout(
  A2uiWidgetSchemaLayout layout, {
  String? widgetDescription,
}) {
  final projectionFields = layout.fields;
  final residualDescriptions = layout.residualDescriptions;
  final registry = layout.registry;
  final definitionTargets = layout.hoistTargets;
  if (definitionTargets.isEmpty) {
    final ctx = registry.canonicalOrderTargets.isEmpty
        ? null
        : _DefsContext(
            definitionTargets: const {},
            safeKeys: const {},
            canonicalOrderTargets: registry.canonicalOrderTargets,
          );
    return _widgetObjectSchema(
      projectionFields,
      ctx: ctx,
      widgetDescription: widgetDescription,
      fieldDescription: (name) => residualDescriptions[name],
    );
  }

  // A reference or description-separation target is present: hoist the whole
  // widget body into `$defs` under a synthetic root key and emit a root `$ref`
  // (the widget object always exists, so the root itself is never nullable).
  // The widget description lands on the hoisted root object — the actual
  // widget shape — not on the `$ref` wrapper.
  final defIds = layout.definitionIds;
  final safeKeys = layout.safeDefinitionKeys;
  final ctx = _DefsContext(
    definitionTargets: definitionTargets,
    safeKeys: safeKeys,
    canonicalOrderTargets: registry.canonicalOrderTargets,
  );

  final nodeForDef = <String, A2uiSchemaNode>{
    for (final id in definitionTargets) id: registry.definitionFor(id),
  };

  final orderedIds = defIds.toList()
    ..sort((a, b) => safeKeys[a]!.compareTo(safeKeys[b]!));
  final defEntries = <String>[];
  for (final id in orderedIds) {
    final schema = id == a2uiSyntheticRootDefinitionId
        ? _widgetObjectSchema(
            projectionFields,
            ctx: ctx,
            widgetDescription: widgetDescription,
            fieldDescription: (name) => residualDescriptions[name],
          )
        : _projectNode(nodeForDef[id]!, ctx, atDefRoot: true);
    defEntries.add('${_dartStringLiteral(safeKeys[id]!)}: $schema');
  }
  return r'S.combined($ref: '
      '${_refLiteral(safeKeys[a2uiSyntheticRootDefinitionId]!)}, '
      r'$defs: {'
      '${defEntries.join(', ')}})';
}

// ── A2UI data-schema MAP projection (the standalone-document twin) ───────────
//
// The standalone `.a2ui.json` catalog document carries each component's full
// data schema (so a producer generating payloads against the document alone —
// not the generated `.g.dart` — can see a component's fields). It is projected
// from the SAME `plan.fields` the generated `CatalogItem.dataSchema` is, but as
// a plain `Map` built directly here — NOT via `json_schema_builder` (which the
// build-time toolchain must not depend on; see `a2ui_isolation_test`). Each map
// REPLICATES exactly what the `.g.dart`'s `S.*` constructor serializes to
// (`Schema.value` on json_schema_builder 0.1.x: `'type'` always present, all
// other keywords omitted when null but kept when an explicit empty
// `required: []` is passed). So a component's document data schema equals the
// runtime `CatalogItem.dataSchema.value`, and the `restage_a2ui` doc-tie pins
// that against the real genui SDK (it also fails loud if a future
// json_schema_builder serialization change makes the two diverge).
//
// Each `…Map` function below mirrors its `…Expression`/`…Schema` source twin
// arm-for-arm (same fail-loud arms, same nullability + `$defs`/`$ref` two-pass,
// same write-back value-reference shape), reusing the shared, output-agnostic
// helpers (`A2uiDefinitionRegistry`, `assignA2uiSafeDefinitionKeys`,
// `_DefsContext`, …).

/// The data-schema map for [plan] — the document-side twin of
/// [_schemaExpression]. Consumes the SAME field projection, so the document's
/// component schema and the generated `CatalogItem` schema agree.
Map<String, Object?> a2uiWidgetDataSchemaMapForPlan(A2uiDartWidgetPlan plan) {
  return _widgetDataSchemaMap(
    a2uiWidgetSchemaLayoutForPlan(plan),
    widgetDescription: _normalizedDescription(plan.entry.description),
  );
}

/// The full catalog component schema for [plan], including genui's required
/// `component` discriminator. This is the single projection used by both the
/// standalone registration and generated-Dart registration verification.
Map<String, Object?> a2uiCatalogComponentSchemaMapForPlan(
  A2uiDartWidgetPlan plan,
) {
  final data = a2uiWidgetDataSchemaMapForPlan(plan);
  final dataProperties =
      (data['properties'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{};
  final dataRequired = (data['required'] as List?) ?? const <Object?>[];
  return <String, Object?>{
    ...data,
    'properties': <String, Object?>{
      ...dataProperties,
      'component': <String, Object?>{
        'type': 'string',
        'enum': <String>[plan.entry.name],
      },
    },
    'required': <Object?>['component', ...dataRequired],
  };
}

/// Map mirror of [a2uiWidgetDataSchemaExpression].
Map<String, Object?> _widgetDataSchemaMap(
  A2uiWidgetSchemaLayout layout, {
  String? widgetDescription,
}) {
  final projectionFields = layout.fields;
  final residualDescriptions = layout.residualDescriptions;
  final registry = layout.registry;
  final definitionTargets = layout.hoistTargets;
  if (definitionTargets.isEmpty) {
    final ctx = registry.canonicalOrderTargets.isEmpty
        ? null
        : _DefsContext(
            definitionTargets: const {},
            safeKeys: const {},
            canonicalOrderTargets: registry.canonicalOrderTargets,
          );
    return _widgetObjectSchemaMap(
      projectionFields,
      ctx: ctx,
      widgetDescription: widgetDescription,
      fieldDescription: (name) => residualDescriptions[name],
    );
  }

  final defIds = layout.definitionIds;
  final safeKeys = layout.safeDefinitionKeys;
  final ctx = _DefsContext(
    definitionTargets: definitionTargets,
    safeKeys: safeKeys,
    canonicalOrderTargets: registry.canonicalOrderTargets,
  );

  final nodeForDef = <String, A2uiSchemaNode>{
    for (final id in definitionTargets) id: registry.definitionFor(id),
  };

  final orderedIds = defIds.toList()
    ..sort((a, b) => safeKeys[a]!.compareTo(safeKeys[b]!));
  final defs = <String, Object?>{};
  for (final id in orderedIds) {
    defs[safeKeys[id]!] = id == a2uiSyntheticRootDefinitionId
        ? _widgetObjectSchemaMap(
            projectionFields,
            ctx: ctx,
            widgetDescription: widgetDescription,
            fieldDescription: (name) => residualDescriptions[name],
          )
        : _projectNodeMap(nodeForDef[id]!, ctx, atDefRoot: true);
  }
  // `$defs` before `$ref` matches json_schema_builder's `S.combined` map order
  // (its factory literal lists `$defs` first), so the document is byte-stable
  // against what the `.g.dart`'s `S.combined($ref:, $defs:)` serializes to.
  return {
    r'$defs': defs,
    r'$ref': _refPointer(safeKeys[a2uiSyntheticRootDefinitionId]!),
  };
}

/// Map mirror of [_widgetObjectSchema].
Map<String, Object?> _widgetObjectSchemaMap(
  List<A2uiWidgetField> fields, {
  _DefsContext? ctx,
  String? widgetDescription,
  String? Function(String fieldName)? fieldDescription,
}) {
  final properties = <String, Object?>{
    for (final field in fields)
      field.name: _withMapDescription(
        _fieldSchemaMap(field.emission, ctx),
        fieldDescription?.call(field.name),
      ),
  };
  final required = <String>[
    for (final field in fields)
      if (field.required) field.name,
  ];
  final base = {
    'type': 'object',
    'properties': properties,
    'required': required,
  };
  return _withMapDescription(base, widgetDescription);
}

/// Inserts a `'description'` key into [schema] at the same position genui's
/// own `json_schema_builder` factories place it — immediately after `'type'`
/// (or first, for a `type`-less combined/`oneOf` schema) — so the emitted
/// `.a2ui.json` component schema matches what the generated `.g.dart`'s
/// `S.*(description: …)` call serializes to. A `null` [description] returns
/// [schema] unchanged (no empty `description` key).
Map<String, Object?> _withMapDescription(
  Map<String, Object?> schema,
  String? description,
) {
  if (description == null) return schema;
  if (!schema.containsKey('type')) {
    return {'description': description, ...schema};
  }
  final described = <String, Object?>{};
  for (final entry in schema.entries) {
    described[entry.key] = entry.value;
    if (entry.key == 'type') described['description'] = description;
  }
  return described;
}

/// Map mirror of [_fieldSchema].
Map<String, Object?> _fieldSchemaMap(
  A2uiFieldEmission emission,
  _DefsContext? ctx,
) {
  switch (emission) {
    case A2uiDataField(
        :final node,
        :final writeBack,
        :final constraints,
      ):
      final projectionNode = _orderedProjectionNode(
        node,
        atDefinitionRoot: _defIdOf(node) != null,
      );
      if (a2uiUsesValueReferenceSchema(
        projectionNode,
        writeBack: writeBack,
      )) {
        return _valueReferenceMap(projectionNode, constraints, ctx);
      }
      if (!constraints.isEmpty) {
        return _constrainedSchemaForNodeMap(
          projectionNode,
          constraints,
          ctx,
        );
      }
      return ctx == null
          ? _schemaForNodeMap(projectionNode)
          : _projectNodeMap(projectionNode, ctx, atDefRoot: false);
    case A2uiChildField(:final slot):
      switch (slot) {
        case A2uiChildNode(:final nullable):
          return _nullableSchemaMap({'type': 'string'}, nullable);
        case A2uiChildrenNode(:final nullable):
          return _nullableSchemaMap(
            {
              'type': 'array',
              'items': {'type': 'string'},
            },
            nullable,
          );
      }
  }
}

Map<String, Object?> _nullableSchemaMap(
  Map<String, Object?> schema,
  bool nullable,
) =>
    nullable
        ? {
            'anyOf': <Object?>[
              schema,
              {'type': 'null'},
            ],
          }
        : schema;

/// Map mirror of [_valueReferenceSchema] — the genui value-reference shape
/// (a literal OR a `{path}` binding OR a `{call}` function-call source).
Map<String, Object?> _valueReferenceMap(
  A2uiSchemaNode node,
  A2uiConstraintSet constraints,
  _DefsContext? ctx,
) =>
    _withMapDescription(
      {
        'oneOf': <Object?>[
          _constrainedSchemaForNodeMap(
            node,
            constraints,
            ctx,
            includeOccurrenceDescription: false,
          ),
          {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
            },
            'required': const ['path'],
          },
          {
            'type': 'object',
            'properties': {
              'call': {'type': 'string'},
              'args': {'type': 'object', 'additionalProperties': true},
            },
            'required': const ['call'],
          },
        ],
      },
      _normalizedDescription(node.occurrenceDescription),
    );

/// Projects constraints onto the non-null literal base, then applies the
/// property's nullability. Deferred `{path}`/`{call}` arms never pass here.
Map<String, Object?> _constrainedSchemaForNodeMap(
  A2uiSchemaNode node,
  A2uiConstraintSet constraints,
  _DefsContext? ctx, {
  bool includeOccurrenceDescription = true,
}) {
  final base = ctx == null
      ? _schemaForNodeBaseMap(node, includeOccurrenceDescription: false)
      : _projectNodeBaseMap(
          node,
          ctx,
          atDefRoot: false,
          includeOccurrenceDescription: false,
        );
  final constrained = constraints.isEmpty
      ? base
      : <String, Object?>{...base, ...constraints.keywords};
  final composed = _wrapNullableMap(constrained, node.nullable);
  return includeOccurrenceDescription
      ? _withMapDescription(
          composed,
          _normalizedDescription(node.occurrenceDescription),
        )
      : composed;
}

/// Map mirror of [_schemaForNode].
Map<String, Object?> _schemaForNodeMap(A2uiSchemaNode node) =>
    _withMapDescription(
      _wrapNullableMap(
        _schemaForNodeBaseMap(node, includeOccurrenceDescription: false),
        node.nullable,
      ),
      _normalizedDescription(node.occurrenceDescription),
    );

/// Map mirror of [_wrapNullable].
Map<String, Object?> _wrapNullableMap(
  Map<String, Object?> base,
  bool nullable,
) =>
    nullable
        ? {
            'anyOf': <Object?>[
              base,
              {'type': 'null'},
            ],
          }
        : base;

/// Map mirror of [_schemaForNodeBase].
Map<String, Object?> _schemaForNodeBaseMap(
  A2uiSchemaNode node, {
  required bool includeOccurrenceDescription,
}) {
  switch (node) {
    case ScalarNode(:final type):
      final base = switch (type) {
        A2uiScalarType.boolean => {'type': 'boolean'},
        A2uiScalarType.number => {'type': 'number'},
        A2uiScalarType.integer => {'type': 'integer'},
        A2uiScalarType.string => {'type': 'string'},
      };
      return _withMapDescription(
        base,
        includeOccurrenceDescription
            ? _normalizedDescription(node.occurrenceDescription)
            : null,
      );
    case EnumNode(:final members):
      return _withMapDescription(
        members.isEmpty
            ? {'type': 'string'}
            : {'type': 'string', 'enum': members.toList()},
        includeOccurrenceDescription
            ? _normalizedDescription(node.occurrenceDescription)
            : null,
      );
    case ListNode(:final element):
      return _withMapDescription(
        {'type': 'array', 'items': _schemaForNodeMap(element)},
        includeOccurrenceDescription
            ? _normalizedDescription(node.occurrenceDescription)
            : null,
      );
    case final ObjectNode object:
      return _withMapDescription(
        _objectSchemaMap(object.fields, object.required),
        includeOccurrenceDescription
            ? _inlineObjectDescription(object)
            : _definitionOnlyObjectDescription(object),
      );
    case MapNode(:final valueType):
      return _withMapDescription(
        {
          'type': 'object',
          'additionalProperties': _schemaForNodeMap(valueType),
        },
        includeOccurrenceDescription
            ? _normalizedDescription(node.occurrenceDescription)
            : null,
      );
    case UnionNode() || RefNode():
      throw StateError(_richNodeUnsupportedMessage(node));
  }
}

/// Map mirror of [_objectSchema].
Map<String, Object?> _objectSchemaMap(
  Map<String, A2uiSchemaNode> fields,
  Set<String> required,
) {
  final properties = <String, Object?>{
    for (final entry in fields.entries)
      entry.key: _schemaForNodeMap(entry.value),
  };
  return {
    'type': 'object',
    'properties': properties,
    'required': required.toList(),
  };
}

/// Map mirror of [_projectNode].
Map<String, Object?> _projectNodeMap(
  A2uiSchemaNode node,
  _DefsContext ctx, {
  required bool atDefRoot,
}) {
  final base = _projectNodeBaseMap(
    node,
    ctx,
    atDefRoot: atDefRoot,
    includeOccurrenceDescription: false,
  );
  final composed = _wrapNullableMap(base, !atDefRoot && node.nullable);
  return atDefRoot
      ? composed
      : _withMapDescription(
          composed,
          _normalizedDescription(node.occurrenceDescription),
        );
}

/// Map mirror of [_projectNodeBase].
Map<String, Object?> _projectNodeBaseMap(
  A2uiSchemaNode node,
  _DefsContext ctx, {
  required bool atDefRoot,
  required bool includeOccurrenceDescription,
}) {
  switch (node) {
    case ScalarNode() || EnumNode():
      return _schemaForNodeBaseMap(
        node,
        includeOccurrenceDescription: includeOccurrenceDescription,
      );
    case ListNode(:final element):
      return _withMapDescription(
        {
          'type': 'array',
          'items': _projectNodeMap(element, ctx, atDefRoot: false),
        },
        includeOccurrenceDescription
            ? _normalizedDescription(node.occurrenceDescription)
            : null,
      );
    case MapNode(:final valueType):
      return _withMapDescription(
        {
          'type': 'object',
          'additionalProperties':
              _projectNodeMap(valueType, ctx, atDefRoot: false),
        },
        includeOccurrenceDescription
            ? _normalizedDescription(node.occurrenceDescription)
            : null,
      );
    case final ObjectNode object:
      final defId = object.defId;
      final canonicalOrder =
          defId != null && ctx.canonicalOrderTargets.contains(defId);
      if (!atDefRoot &&
          defId != null &&
          ctx.definitionTargets.contains(defId)) {
        return _withMapDescription(
          _refMap(ctx, defId),
          includeOccurrenceDescription
              ? _normalizedDescription(object.occurrenceDescription)
              : null,
        );
      }
      final properties = <String, Object?>{
        for (final entry in _orderedFieldEntries(object.fields, canonicalOrder))
          entry.key: _projectNodeMap(entry.value, ctx, atDefRoot: false),
      };
      final base = <String, Object?>{
        'type': 'object',
        'properties': properties,
        'required': _orderedRequired(
          object.required,
          canonicalOrder,
        ),
      };
      return _withMapDescription(
        base,
        atDefRoot
            ? _normalizedDescription(object.definitionDescription)
            : includeOccurrenceDescription
                ? _inlineObjectDescription(object)
                : _definitionOnlyObjectDescription(object),
      );
    case RefNode(:final defId, :final occurrenceDescription):
      return _withMapDescription(
        _refMap(ctx, defId),
        includeOccurrenceDescription
            ? _normalizedDescription(occurrenceDescription)
            : null,
      );
    case UnionNode():
      throw StateError(_richNodeUnsupportedMessage(node));
  }
}

/// Map mirror of [_refExpression].
Map<String, Object?> _refMap(_DefsContext ctx, String defId) {
  final key = ctx.safeKeys[defId];
  if (key == null) {
    throw StateError('A2UI projection: no \$defs key assigned for "$defId".');
  }
  return {r'$ref': _refPointer(key)};
}

/// The JSON pointer `#/$defs/<key>` value (the runtime twin of [_refLiteral],
/// which produces the same pointer as Dart SOURCE).
String _refPointer(String key) => '#/\$defs/$key';

/// The widget `S.object` body for [fields]. With a [ctx] each data field is
/// projected cycle-aware (recursive occurrences become `$ref`s, the `$defs`
/// living at the document root); without one each is the bare projection.
///
/// [widgetDescription] and [fieldDescription] carry the developer-authored
/// descriptions (already normalized to absent when blank); each non-null
/// description is inserted as a `description:` argument on the corresponding
/// `S.*(...)` call via [_withSchemaDescription].
String _widgetObjectSchema(
  List<A2uiWidgetField> fields, {
  _DefsContext? ctx,
  String? widgetDescription,
  String? Function(String fieldName)? fieldDescription,
}) {
  final props = <String>[];
  for (final field in fields) {
    final schema = _withSchemaDescription(
      _fieldSchema(field.emission, ctx),
      fieldDescription?.call(field.name),
    );
    props.add('${_dartStringLiteral(field.name)}: $schema');
  }
  final required = [
    for (final field in fields)
      if (field.required) _dartStringLiteral(field.name),
  ];
  final base = 'S.object(properties: {${props.join(', ')}}, '
      'required: <String>[${required.join(', ')}],)';
  return _withSchemaDescription(base, widgetDescription);
}

/// Inserts a `description: <literal>,` named argument right after the
/// opening parenthesis of the outermost `S.*(...)` call in [schemaExpr] —
/// every genui `S.*` schema builder accepts `description`, so this works
/// uniformly whether [schemaExpr] is a scalar/enum/list/object/combined
/// schema. Named-argument order is immaterial to Dart, so inserting first is
/// always valid regardless of what other arguments follow. A `null`
/// [description] returns [schemaExpr] unchanged — the same rule as
/// [_withMapDescription], its document-side twin.
String _withSchemaDescription(String schemaExpr, String? description) {
  if (description == null) return schemaExpr;
  if (schemaExpr.startsWith('S.fromMap(<String, Object?>{')) {
    const spreadEnd = '.value,';
    final spreadEndIndex = schemaExpr.indexOf(spreadEnd);
    if (spreadEndIndex < 0) {
      throw StateError(
        'A2UI constrained schema expression missing its base spread: '
        '$schemaExpr',
      );
    }
    final insertion = spreadEndIndex + spreadEnd.length;
    return schemaExpr.replaceRange(
      insertion,
      insertion,
      ' ${_dartStringLiteral('description')}: '
      '${_dartStringLiteral(description)},',
    );
  }
  final openParen = schemaExpr.indexOf('(');
  if (openParen < 0) {
    throw StateError(
      'A2UI schema expression missing a call to describe: $schemaExpr',
    );
  }
  final before = schemaExpr.substring(0, openParen + 1);
  final after = schemaExpr.substring(openParen + 1);
  return '$before'
      'description: ${_dartStringLiteral(description)}, $after';
}

/// The schema for one field's [emission]: a bound data value (cycle-aware via
/// [ctx] when present) or a host-built child slot (a fixed leaf schema).
String _fieldSchema(A2uiFieldEmission emission, _DefsContext? ctx) {
  switch (emission) {
    case A2uiDataField(
        :final node,
        :final writeBack,
        :final constraints,
      ):
      final projectionNode = _orderedProjectionNode(
        node,
        atDefinitionRoot: _defIdOf(node) != null,
      );
      // Scalar-list bindings accept literal, `{path}`, and `{call}` values.
      // Scalar and enum leaves use that reference shape only when they
      // participate in write-back; ordinary enums remain literal-only.
      if (a2uiUsesValueReferenceSchema(
        projectionNode,
        writeBack: writeBack,
      )) {
        return _valueReferenceSchema(projectionNode, constraints, ctx);
      }
      if (!constraints.isEmpty) {
        return _constrainedSchemaForNode(
          projectionNode,
          constraints,
          ctx,
        );
      }
      return ctx == null
          ? _schemaForNode(projectionNode)
          : _projectNode(projectionNode, ctx, atDefRoot: false);
    case A2uiChildField(:final slot):
      switch (slot) {
        case A2uiChildNode(:final nullable):
          return _wrapNullable('S.string()', nullable);
        case A2uiChildrenNode(:final nullable):
          return _wrapNullable('S.list(items: S.string())', nullable);
      }
  }
}

/// The genui value-reference schema for a bound value — a literal OR a `{path}`
/// data binding OR a `{call}` function-call value source. For a scalar or enum
/// [node] the literal arm preserves its exact leaf schema (including enum
/// members), alongside genui's reference arms. Scalar leaves replicate
/// `A2uiSchemas.{boolean,number,string}Reference`
/// (a2ui_schemas.dart:299-343); for a `List<scalar>` [node] it replicates
/// `A2uiSchemas.listOrReference(items:)` / `stringArrayReference()`
/// (a2ui_schemas.dart:418-428, 522-531) — the same `oneOf` with
/// `S.list(items:)` as the literal option. The literal is the only difference
/// between the two; the `{path}` binding + `{call}` function-call options are
/// identical. The shape is
/// replicated raw from `json_schema_builder` primitives rather than by calling
/// genui's `A2uiSchemas` helper: genui is 0.x/experimental, so depending on its
/// helper API would risk inheriting its churn (a helper rename/signature change
/// would break the customer's generated build); raw + per-version grounding is
/// the churn-robust track-genui posture, and the producer-facing shape is
/// identical. (The toolchain emits source text and never imports genui either
/// way.) Re-ground the shape + those file:lines on a genui version bump.
String _valueReferenceSchema(
  A2uiSchemaNode node,
  A2uiConstraintSet constraints,
  _DefsContext? ctx,
) {
  final literal = _constrainedSchemaForNode(
    node,
    constraints,
    ctx,
    includeOccurrenceDescription: false,
  );
  const binding = "S.object(properties: {'path': S.string()}, "
      "required: <String>['path'])";
  const functionCall = "S.object(properties: {'call': S.string(), "
      "'args': S.object(additionalProperties: true)}, "
      "required: <String>['call'])";
  return _withSchemaDescription(
    'S.combined(oneOf: [$literal, $binding, $functionCall])',
    _normalizedDescription(node.occurrenceDescription),
  );
}

/// Projects a constrained literal through the builder's exact-map escape
/// hatch. This preserves combinations its leaf factories cannot spell (for
/// example fractional bounds on an integer schema, or enum plus bounds) while
/// retaining the leaf's exact `type` and nested structure.
String _constrainedSchemaForNode(
  A2uiSchemaNode node,
  A2uiConstraintSet constraints,
  _DefsContext? ctx, {
  bool includeOccurrenceDescription = true,
}) {
  final base = ctx == null
      ? _schemaForNodeBase(node, includeOccurrenceDescription: false)
      : _projectNodeBase(
          node,
          ctx,
          atDefRoot: false,
          includeOccurrenceDescription: false,
        );
  final entries = constraints.keywords.entries
      .map(
        (entry) => '${_dartStringLiteral(entry.key)}: '
            '${_dartJsonScalarOrListLiteral(entry.value)}',
      )
      .join(', ');
  final constrained = constraints.isEmpty
      ? base
      : 'S.fromMap(<String, Object?>{...$base.value, $entries})';
  final composed = _wrapNullable(constrained, node.nullable);
  return includeOccurrenceDescription
      ? _withSchemaDescription(
          composed,
          _normalizedDescription(node.occurrenceDescription),
        )
      : composed;
}

String _dartJsonScalarOrListLiteral(Object? value) {
  if (value == null) return 'null';
  if (value is String) return _dartStringLiteral(value);
  if (value is num || value is bool) return '$value';
  if (value is List) {
    return '<Object?>[${value.map(_dartJsonScalarOrListLiteral).join(', ')}]';
  }
  throw StateError(
    'A2UI constraint value is not a normalized JSON scalar/list: $value',
  );
}

/// Projects [node] to its bare (non-`$defs`) schema, applying nullability at
/// the occurrence as `anyOf[<non-null>, S.nil()]`.
String _schemaForNode(A2uiSchemaNode node) {
  if (!node.nullable) {
    return _schemaForNodeBase(node, includeOccurrenceDescription: true);
  }
  return _withSchemaDescription(
    _wrapNullable(
      _schemaForNodeBase(node, includeOccurrenceDescription: false),
      true,
    ),
    _normalizedDescription(node.occurrenceDescription),
  );
}

/// Wraps [base] to also accept JSON `null` when [nullable].
///
/// `defId` intentionally ignores outer nullability, so a `$defs` DEFINITION
/// stays non-null and the wrap is applied only at each OCCURRENCE/reference.
String _wrapNullable(String base, bool nullable) =>
    nullable ? 'S.combined(anyOf: [$base, S.nil()])' : base;

/// The NON-null schema for [node] (the caller applies nullability). Children
/// recurse through [_schemaForNode] so their own nullability is applied.
String _schemaForNodeBase(
  A2uiSchemaNode node, {
  required bool includeOccurrenceDescription,
}) {
  switch (node) {
    case ScalarNode(:final type):
      final factory = switch (type) {
        A2uiScalarType.boolean => 'boolean',
        A2uiScalarType.number => 'number',
        A2uiScalarType.integer => 'integer',
        A2uiScalarType.string => 'string',
      };
      final description = includeOccurrenceDescription
          ? _normalizedDescription(node.occurrenceDescription)
          : null;
      return description == null
          ? 'S.$factory()'
          : 'S.$factory(description: ${_dartStringLiteral(description)})';
    case EnumNode(:final members):
      // The catalog-fed path carries no member set → a plain string (byte-
      // neutral); the analyzer-fed path enriches it with the resolved members.
      final base = members.isEmpty
          ? 'S.string()'
          : 'S.string(enumValues: <Object?>['
              '${members.map(_dartStringLiteral).join(', ')}])';
      return _withSchemaDescription(
        base,
        includeOccurrenceDescription
            ? _normalizedDescription(node.occurrenceDescription)
            : null,
      );
    case ListNode(:final element):
      return _withSchemaDescription(
        'S.list(items: ${_schemaForNode(element)})',
        includeOccurrenceDescription
            ? _normalizedDescription(node.occurrenceDescription)
            : null,
      );
    case final ObjectNode object:
      return _withSchemaDescription(
        _objectSchema(object.fields, object.required),
        includeOccurrenceDescription
            ? _inlineObjectDescription(object)
            : _definitionOnlyObjectDescription(object),
      );
    case MapNode(:final valueType):
      return _withSchemaDescription(
        'S.object(additionalProperties: ${_schemaForNode(valueType)})',
        includeOccurrenceDescription
            ? _normalizedDescription(node.occurrenceDescription)
            : null,
      );
    case UnionNode() || RefNode():
      // Fail loud (no permissive schema): union recognition is the deferred
      // fast-follow; a RefNode only arises with a cycle, handled by the
      // two-pass `$defs` derivation (this bare path is reached only with no
      // cycle present).
      throw StateError(_richNodeUnsupportedMessage(node));
  }
}

/// Projects an [A2uiSchemaNode] to its `json_schema_builder` schema expression.
///
/// Exhaustive over the sealed node tree with fail-loud arms and NO permissive
/// default — a node the projection cannot yet emit throws rather than producing
/// an empty/permissive schema, so the governing invariant continues past the
/// reflector into the projection.
///
/// Genuine cycles and non-recursive named objects whose canonical and
/// occurrence descriptions need separate schema slots are emitted through a
/// `$defs`/`$ref` two-pass. Other non-recursive reuse remains inline. A schema
/// with neither target projects exactly as the bare node tree.
///
/// This projects ONE standalone node. For a widget's full `dataSchema` (whose
/// `$defs` must hoist to the document root across all fields) use
/// [a2uiWidgetDataSchemaExpression] — do not embed this result as a property
/// value, or a nested `$defs` could not resolve.
String a2uiDataSchemaExpression(A2uiSchemaNode node) {
  final registry = A2uiDefinitionRegistry([node]);
  final projectionNode = _orderedProjectionNode(
    node,
    atDefinitionRoot: _defIdOf(node) != null,
  );
  if (registry.hoistTargets.isEmpty) {
    // No reference or description-separation target: retain the bare normal
    // form, but canonicalize documented named-definition traversal.
    if (registry.canonicalOrderTargets.isEmpty) {
      return _schemaForNode(projectionNode);
    }
    return _projectNode(
      projectionNode,
      _DefsContext(
        definitionTargets: const {},
        safeKeys: const {},
        canonicalOrderTargets: registry.canonicalOrderTargets,
      ),
      atDefRoot: false,
    );
  }
  return _schemaWithDefs(projectionNode, registry);
}

/// Projects [root] with a `$defs`/`$ref` two-pass for the reference and
/// description-separation targets discovered by [registry].
///
/// `S.combined` carries `$defs`/`$ref` but not `properties`, so a schema that
/// needs `$defs` hoists its whole body into `$defs` (the root under its own
/// `defId`, or a synthetic key) and emits a root `$ref` into it. Every target
/// is projected once; unrelated non-recursive reuse stays inline.
String _schemaWithDefs(
  A2uiSchemaNode root,
  A2uiDefinitionRegistry registry,
) {
  final definitionTargets = registry.hoistTargets;
  final rootId = _defIdOf(root) ?? a2uiSyntheticRootDefinitionId;
  final defIds = <String>{rootId, ...definitionTargets};
  final safeKeys = assignA2uiSafeDefinitionKeys(defIds);
  final ctx = _DefsContext(
    definitionTargets: definitionTargets,
    safeKeys: safeKeys,
    canonicalOrderTargets: registry.canonicalOrderTargets,
  );

  // The node emitted under each `$defs` key: the root key maps to `root`; each
  // hoisted target maps to its canonical definition.
  final nodeForDef = <String, A2uiSchemaNode>{rootId: root};
  for (final id in definitionTargets) {
    nodeForDef[id] = registry.definitionFor(id);
  }

  // Emit `$defs` entries in safe-key order (stable, readable output).
  final orderedIds = defIds.toList()
    ..sort((a, b) => safeKeys[a]!.compareTo(safeKeys[b]!));
  final defEntries = <String>[];
  for (final id in orderedIds) {
    final schema = _projectNode(nodeForDef[id]!, ctx, atDefRoot: true);
    defEntries.add('${_dartStringLiteral(safeKeys[id]!)}: $schema');
  }

  final defsBody = '\$defs: {${defEntries.join(', ')}}';
  final rootPtr = _refLiteral(safeKeys[rootId]!);
  final rootReference = 'S.combined(\$ref: $rootPtr)';
  if (root.nullable) {
    // The root OCCURRENCE carries the root's nullability (the `$def` stays
    // non-null); `$defs` remain at the document root alongside the `anyOf`.
    return _withSchemaDescription(
      'S.combined(anyOf: [$rootReference, S.nil()], $defsBody)',
      _normalizedDescription(root.occurrenceDescription),
    );
  }
  return _withSchemaDescription(
    'S.combined(\$ref: $rootPtr, $defsBody)',
    _normalizedDescription(root.occurrenceDescription),
  );
}

/// Context for definition-aware projection: which `defId`s are hoisted, which
/// named objects require canonical traversal, and each collision-safe key.
@immutable
final class _DefsContext {
  const _DefsContext({
    required this.definitionTargets,
    required this.safeKeys,
    required this.canonicalOrderTargets,
  });

  /// Canonical ids materialized once in `$defs`.
  final Set<String> definitionTargets;

  /// Canonical id (including the root key) → its `$defs` key.
  final Map<String, String> safeKeys;

  /// Named object ids whose own field traversal is canonicalized.
  final Set<String> canonicalOrderTargets;
}

/// Projects [node] in the cycle-aware context.
///
/// A hoisted object occurrence emits a `$ref`, except at its own definition
/// root ([atDefRoot]), where it is projected inline so the definition is
/// materialized once. Non-hoisted shapes project inline.
String _projectNode(
  A2uiSchemaNode node,
  _DefsContext ctx, {
  required bool atDefRoot,
}) {
  final includeOccurrenceDescription = !atDefRoot && !node.nullable;
  final base = _projectNodeBase(
    node,
    ctx,
    atDefRoot: atDefRoot,
    includeOccurrenceDescription: includeOccurrenceDescription,
  );
  // The def root is non-null (canonical `defId` ignores outer nullability);
  // nullability applies only at occurrences.
  final composed = _wrapNullable(base, !atDefRoot && node.nullable);
  return atDefRoot || includeOccurrenceDescription
      ? composed
      : _withSchemaDescription(
          composed,
          _normalizedDescription(node.occurrenceDescription),
        );
}

/// The NON-null cycle-aware schema for [node] (the caller applies occurrence
/// nullability). A hoisted object occurrence becomes a `$ref` except at its own
/// definition root ([atDefRoot]), where it is materialized inline once.
String _projectNodeBase(
  A2uiSchemaNode node,
  _DefsContext ctx, {
  required bool atDefRoot,
  required bool includeOccurrenceDescription,
}) {
  switch (node) {
    case ScalarNode() || EnumNode():
      return _schemaForNodeBase(
        node,
        includeOccurrenceDescription: includeOccurrenceDescription,
      );
    case ListNode(:final element):
      return _withSchemaDescription(
        'S.list(items: ${_projectNode(element, ctx, atDefRoot: false)})',
        includeOccurrenceDescription
            ? _normalizedDescription(node.occurrenceDescription)
            : null,
      );
    case MapNode(:final valueType):
      return _withSchemaDescription(
        'S.object(additionalProperties: '
        '${_projectNode(valueType, ctx, atDefRoot: false)})',
        includeOccurrenceDescription
            ? _normalizedDescription(node.occurrenceDescription)
            : null,
      );
    case final ObjectNode object:
      final defId = object.defId;
      final canonicalOrder =
          defId != null && ctx.canonicalOrderTargets.contains(defId);
      if (!atDefRoot &&
          defId != null &&
          ctx.definitionTargets.contains(defId)) {
        return _withSchemaDescription(
          _refExpression(ctx, defId),
          includeOccurrenceDescription
              ? _normalizedDescription(object.occurrenceDescription)
              : null,
        );
      }
      final props = <String>[];
      for (final entry in _orderedFieldEntries(object.fields, canonicalOrder)) {
        final value = _projectNode(entry.value, ctx, atDefRoot: false);
        props.add('${_dartStringLiteral(entry.key)}: $value');
      }
      final req = [
        for (final name in _orderedRequired(object.required, canonicalOrder))
          _dartStringLiteral(name),
      ];
      final base = 'S.object(properties: {${props.join(', ')}}, '
          'required: <String>[${req.join(', ')}],)';
      return _withSchemaDescription(
        base,
        atDefRoot
            ? _normalizedDescription(object.definitionDescription)
            : includeOccurrenceDescription
                ? _inlineObjectDescription(object)
                : _definitionOnlyObjectDescription(object),
      );
    case RefNode(:final defId, :final occurrenceDescription):
      return _withSchemaDescription(
        _refExpression(ctx, defId),
        includeOccurrenceDescription
            ? _normalizedDescription(occurrenceDescription)
            : null,
      );
    case UnionNode():
      // Deferred — fail loud, never a permissive schema. Union-variant
      // recognition (the fast-follow) routes variant incorporation through the
      // same funnel.
      throw StateError(_richNodeUnsupportedMessage(node));
  }
}

/// The `S.combined($ref: …)` expression referencing [defId]'s `$defs` entry.
String _refExpression(_DefsContext ctx, String defId) {
  final key = ctx.safeKeys[defId];
  if (key == null) {
    throw StateError('A2UI projection: no \$defs key assigned for "$defId".');
  }
  return 'S.combined(\$ref: ${_refLiteral(key)})';
}

/// The Dart source literal for the JSON pointer `#/$defs/<key>`.
///
/// The `$` is backslash-escaped (`\$`) so the *emitted* Dart string literal
/// carries the pointer text rather than interpolating; built explicitly (not
/// via [_dartStringLiteral]) so the shared string helper stays untouched.
String _refLiteral(String key) => "'#/\\\$defs/$key'";

/// The `defId` of an object/union node, or null for any other node.
String? _defIdOf(A2uiSchemaNode node) => switch (node) {
      ObjectNode(:final defId) => defId,
      UnionNode(:final defId) => defId,
      _ => null,
    };

bool _hasOwnProjectionDocumentation(
  A2uiSchemaNode node, {
  required bool atDefinitionRoot,
}) {
  if (!atDefinitionRoot &&
      _normalizedDescription(node.occurrenceDescription) != null) {
    return true;
  }
  return switch (node) {
    ObjectNode(:final definitionDescription) ||
    UnionNode(:final definitionDescription) =>
      _normalizedDescription(definitionDescription) != null,
    _ => false,
  };
}

bool _hasProjectionDocumentation(
  A2uiSchemaNode node, {
  required bool atDefinitionRoot,
}) {
  if (_hasOwnProjectionDocumentation(
    node,
    atDefinitionRoot: atDefinitionRoot,
  )) {
    return true;
  }
  return switch (node) {
    ScalarNode() || EnumNode() || RefNode() => false,
    ListNode(:final element) => _hasProjectionDocumentation(
        element,
        atDefinitionRoot: false,
      ),
    MapNode(:final valueType) => _hasProjectionDocumentation(
        valueType,
        atDefinitionRoot: false,
      ),
    ObjectNode(:final fields) => fields.values.any(
        (field) => _hasProjectionDocumentation(
          field,
          atDefinitionRoot: false,
        ),
      ),
    UnionNode(:final variants) => variants.any(
        (variant) => _hasProjectionDocumentation(
          variant,
          atDefinitionRoot: false,
        ),
      ),
  };
}

/// Canonicalizes Object traversal only within documented data subtrees.
///
/// The synthetic widget root is not an [A2uiSchemaNode], so its authored field
/// order stays untouched. Named definition-root occurrence text is likewise a
/// use-site fact and does not enter the canonical ordering context.
A2uiSchemaNode _orderedProjectionNode(
  A2uiSchemaNode node, {
  required bool atDefinitionRoot,
  bool insideDocumentedSubtree = false,
}) {
  final descendantContext = insideDocumentedSubtree ||
      _hasOwnProjectionDocumentation(
        node,
        atDefinitionRoot: atDefinitionRoot,
      );
  switch (node) {
    case ScalarNode() || EnumNode() || RefNode():
      return node;
    case ListNode(
        :final element,
        :final occurrenceDescription,
        :final nullable,
      ):
      return ListNode(
        element: _orderedProjectionNode(
          element,
          atDefinitionRoot: false,
          insideDocumentedSubtree: descendantContext,
        ),
        occurrenceDescription: occurrenceDescription,
        nullable: nullable,
      );
    case MapNode(
        :final valueType,
        :final occurrenceDescription,
        :final nullable,
      ):
      return MapNode(
        valueType: _orderedProjectionNode(
          valueType,
          atDefinitionRoot: false,
          insideDocumentedSubtree: descendantContext,
        ),
        occurrenceDescription: occurrenceDescription,
        nullable: nullable,
      );
    case ObjectNode(
        :final fields,
        :final required,
        :final defId,
        :final construction,
        :final definitionDescription,
        :final occurrenceDescription,
        :final nullable,
      ):
      final canonicalOrder = insideDocumentedSubtree ||
          _hasProjectionDocumentation(
            node,
            atDefinitionRoot: atDefinitionRoot,
          );
      final fieldNames = fields.keys.toList();
      final requiredNames = required.toList();
      if (canonicalOrder) {
        fieldNames.sort();
        requiredNames.sort();
      }
      return ObjectNode(
        fields: {
          for (final name in fieldNames)
            name: _orderedProjectionNode(
              fields[name]!,
              atDefinitionRoot: false,
              insideDocumentedSubtree: descendantContext,
            ),
        },
        required: requiredNames.toSet(),
        defId: defId,
        construction: construction,
        definitionDescription: definitionDescription,
        occurrenceDescription: occurrenceDescription,
        nullable: nullable,
      );
    case UnionNode(
        :final variants,
        :final discriminatorField,
        :final defId,
        :final definitionDescription,
        :final occurrenceDescription,
        :final nullable,
      ):
      return UnionNode(
        variants: [
          for (final variant in variants)
            _orderedProjectionNode(
              variant,
              atDefinitionRoot: false,
              insideDocumentedSubtree: descendantContext,
            ),
        ],
        discriminatorField: discriminatorField,
        defId: defId,
        definitionDescription: definitionDescription,
        occurrenceDescription: occurrenceDescription,
        nullable: nullable,
      );
  }
}

String? _inlineObjectDescription(ObjectNode object) {
  final occurrence = _normalizedDescription(object.occurrenceDescription);
  final definition = _normalizedDescription(object.definitionDescription);
  if (occurrence != null && definition != null) {
    throw StateError(
      'A2UI projection: occurrence and canonical descriptions for '
      '"${object.defId ?? '<unnamed>'}" require a hoisted definition.',
    );
  }
  return occurrence ?? definition;
}

String? _definitionOnlyObjectDescription(ObjectNode object) {
  // Preserve the existing fail-loud rule for an anonymous inline object that
  // tries to carry both kinds of documentation in one schema slot.
  _inlineObjectDescription(object);
  return _normalizedDescription(object.definitionDescription);
}

List<MapEntry<String, A2uiSchemaNode>> _orderedFieldEntries(
  Map<String, A2uiSchemaNode> fields,
  bool canonical,
) {
  final entries = fields.entries.toList();
  if (canonical) entries.sort((a, b) => a.key.compareTo(b.key));
  return entries;
}

List<String> _orderedRequired(Set<String> required, bool canonical) {
  final names = required.toList();
  if (canonical) names.sort();
  return names;
}

/// The `S.object(...)` schema for an object's [fields] + [required] set, each
/// field projected recursively.
String _objectSchema(
  Map<String, A2uiSchemaNode> fields,
  Set<String> required,
) {
  final props = [
    for (final entry in fields.entries)
      '${_dartStringLiteral(entry.key)}: ${_schemaForNode(entry.value)}',
  ];
  final req = [for (final name in required) _dartStringLiteral(name)];
  return 'S.object(properties: {${props.join(', ')}}, '
      'required: <String>[${req.join(', ')}],)';
}

/// Message for a rich data-shape node the emitter cannot yet project.
///
/// The recursive object / map / union / reference shapes are declared on the
/// sealed model but their projection lands with the analyzer-fed reflector;
/// the catalog-fed path never produces them, so reaching here is a bug and
/// fails loud rather than emitting a schema/builder that silently drops data.
String _richNodeUnsupportedMessage(A2uiSchemaNode node) =>
    'A2UI emission for ${node.runtimeType} is not implemented; '
    'the catalog-fed path never produces it.';

/// The statements that reconstruct each rich field's typed value into a local
/// at the top of the widget builder. A REQUIRED, non-null reconstruction that
/// can be null fails the whole widget safe (`const SizedBox.shrink()`) — the
/// ruling-#5 fail-safe — while a nullable one passes the value through.
List<String> _richPreludeStatements(
  A2uiDartWidgetPlan widget,
  A2uiDataBuilder dataBuilder,
) {
  final statements = <String>[];
  for (final field in widget.fields) {
    final emission = field.emission;
    if (emission is! A2uiDataField || !emission.rich) continue;
    final property = field.property;
    final variable = _richLocalName(property);
    final access = 'data[${_dartStringLiteral(property.name)}]';
    final reconstruction = dataBuilder.valueExpression(emission.node, access);
    statements.add('final $variable = $reconstruction;');
    if (property.required &&
        !emission.node.nullable &&
        dataBuilder.valueCanBeNull(emission.node)) {
      statements.add('if ($variable == null) return const SizedBox.shrink();');
    }
  }
  return statements;
}

/// The statements that derive write-back paths at the top of the widget
/// builder. Controlled leaf values retain their raw producer descriptor
/// and allocate only a Restage self path; the generated state machine decides
/// whether a write targets an explicit producer path or that self path. Other
/// write-back families keep the established path-only lowering until their
/// own proof slices land.
List<String> _writeBackPreludeStatements(A2uiDartWidgetPlan widget) {
  final statements = <String>[];
  final seenPaths = <String>{};
  for (final writeBack in widget.writeBacks) {
    final valueField = _writeBackValueField(widget, writeBack);
    if (_usesControlledValue(valueField)) {
      final selfPathVar = _writeBackSelfPathVar(writeBack.valuePropertyName);
      if (!seenPaths.add(selfPathVar)) {
        throw StateError(
          'A2UI write-back: duplicate self path "$selfPathVar" on widget '
          '"${widget.entry.name}".',
        );
      }
      final selfScoped = "'\${itemContext.id}.${writeBack.valuePropertyName}'";
      statements.add('final $selfPathVar = $selfScoped;');
      continue;
    }
    final pathVar = _writeBackPathVar(writeBack.valuePropertyName);
    if (!seenPaths.add(pathVar)) {
      // Two write-backs resolving to the same data path would silently
      // cross-wire two controls — fail loud rather than emit a shared path.
      throw StateError(
        'A2UI write-back: duplicate data path "$pathVar" on widget '
        '"${widget.entry.name}".',
      );
    }
    final refVar = _writeBackRefVar(writeBack.valuePropertyName);
    final access = 'data[${_dartStringLiteral(writeBack.valuePropertyName)}]';
    final pathKey = _dartStringLiteral('path');
    // The emitted self-scoped path interpolates `itemContext.id` at render
    // time, so the `$` is escaped here to land in the generated source as-is.
    final selfScoped = "'\${itemContext.id}.${writeBack.valuePropertyName}'";
    statements
      ..add('final $refVar = $access;')
      ..add(
        'final $pathVar = ($refVar is Map && $refVar.containsKey($pathKey)) '
        '? $refVar[$pathKey] as String : $selfScoped;',
      );
  }
  return statements;
}

/// The widget builder's return expression: the constructor wrapped in the
/// reactive `Bound*` layers for the LEAF (catalog-fed scalar/enum/leaf-list)
/// fields. Rich fields are not wrapped here — they are reconstructed in the
/// prelude and referenced by the constructor as locals.
String _widgetReturnExpression(
  A2uiDartWidgetPlan widget,
  Map<String, String> prefixes, {
  required String catalogIdExpression,
}) {
  var expression = _constructorExpression(widget, prefixes);
  final leafFields = widget.fields
      .where(
        (field) => switch (field.emission) {
          A2uiDataField(rich: false) => true,
          _ => false,
        },
      )
      .toList(growable: false);

  for (final field in leafFields.reversed) {
    expression = _boundWrapperExpression(
      field,
      expression,
      catalogIdExpression: catalogIdExpression,
    );
  }
  return expression;
}

String _boundWrapperExpression(
  A2uiDartFieldPlan field,
  String child, {
  required String catalogIdExpression,
}) {
  final property = field.property;
  final emission = field.emission;
  if (emission is! A2uiDataField) {
    throw StateError('Children are not Bound fields.');
  }
  if (_usesControlledValue(field)) {
    final name = property.name;
    final raw = _controlledRawVar(name);
    final present = _controlledPresentVar(name);
    final kind = _controlledKindVar(name);
    final writer = _writeBackWriterVar(name);
    final normalized = switch (emission.node) {
      ScalarNode(type: A2uiScalarType.boolean) =>
        '_restageA2uiBool($raw, $kind)',
      ScalarNode(
        type: A2uiScalarType.number || A2uiScalarType.integer,
      ) =>
        '_restageA2uiNumber($raw, $kind)',
      ScalarNode(type: A2uiScalarType.string) => '_restageA2uiString($raw)',
      EnumNode() => '_restageA2uiEnumName($raw)',
      ListNode() => raw,
      ObjectNode() ||
      MapNode() ||
      UnionNode() ||
      RefNode() =>
        throw StateError(_richNodeUnsupportedMessage(emission.node)),
    };
    return '''
_RestageA2uiControlledValue(
  dataContext: itemContext.dataContext,
  source: data[${_dartStringLiteral(name)}],
  sourcePresent: data.containsKey(${_dartStringLiteral(name)}),
  surfaceId: itemContext.surfaceId,
  catalogId: $catalogIdExpression,
  componentId: itemContext.id,
  field: ${_dartStringLiteral(name)},
  selfPath: ${_writeBackSelfPathVar(name)},
  reportError: itemContext.reportError,
  builder: (context, $raw, $present, $kind, $writer) {
    final ${_identifierFor(name)} = $normalized;
    return $child;
  },
)''';
  }
  final bound = switch (emission.node) {
    ScalarNode(:final type) => switch (type) {
        A2uiScalarType.boolean => 'BoundBool',
        A2uiScalarType.number || A2uiScalarType.integer => 'BoundNumber',
        A2uiScalarType.string => 'BoundString',
      },
    EnumNode() => 'BoundString',
    ListNode() => 'BoundObject',
    ObjectNode() ||
    MapNode() ||
    UnionNode() ||
    RefNode() =>
      throw StateError(_richNodeUnsupportedMessage(emission.node)),
  };
  final variable = _identifierFor(property.name);
  // A write-back value field reads from its resolved data path (a literal
  // `{'path': P}` reference) — NOT the raw value — so the binding is subscribed
  // to the exact path the paired callback writes. A scalar value is never a
  // map, so the `{path}` map-pattern cannot hijack a scalar literal.
  final value = emission.writeBack
      ? "{'path': ${_writeBackPathVar(property.name)}}"
      : 'data[${_dartStringLiteral(property.name)}]';
  return '''
$bound(
  dataContext: itemContext.dataContext,
  value: $value,
  builder: (context, $variable) => $child,
)''';
}

String _constructorExpression(
  A2uiDartWidgetPlan widget,
  Map<String, String> prefixes,
) {
  final entry = widget.entry;
  final ctor = _ctorExpressionFor(entry, prefixes);
  final positional = <String>[];
  final named = <String>[];

  for (final field in widget.fields) {
    final property = field.property;
    final arg = _argumentExpression(
      field,
      prefixes,
      widgetName: entry.name,
    );
    if (property.positional) {
      positional.add(arg);
    } else {
      named.add('${property.name}: $arg');
    }
  }

  // A write-back callback delegates to the controlled field's shared writer;
  // an enum first lowers to its JSON-safe member name. Only NAMED callbacks
  // are wired (see [_resolveInteractions]), so they append to the named
  // arguments without disturbing positional order.
  for (final writeBack in widget.writeBacks) {
    final valueField = _writeBackValueField(widget, writeBack);
    if (_usesControlledValue(valueField)) {
      final writer = _writeBackWriterVar(writeBack.valuePropertyName);
      final enumWireWrite = switch (valueField.emission) {
        A2uiDataField(node: EnumNode()) => true,
        _ => false,
      };
      named.add(
        enumWireWrite
            ? '${writeBack.callbackProperty.name}: '
                '(restageA2uiNext) => $writer(restageA2uiNext.name)'
            : '${writeBack.callbackProperty.name}: $writer',
      );
    } else {
      final pathVar = _writeBackPathVar(writeBack.valuePropertyName);
      named.add(
        '${writeBack.callbackProperty.name}: (_restageA2uiNext) => '
        'itemContext.dataContext.update(DataPath($pathVar), _restageA2uiNext)',
      );
    }
  }

  // A dispatch callback fires an outward `UserActionEvent` whose name is
  // compile-fixed from the callback property name (the producer cannot repoint
  // it — load-bearing for inertness). Named-only, like write-backs.
  for (final dispatch in widget.dispatches) {
    final eventName = _dartStringLiteral(dispatch.name);
    named.add(
      '${dispatch.name}: () => '
      'itemContext.dispatchEvent(UserActionEvent(name: $eventName, '
      'sourceComponentId: itemContext.id))',
    );
  }

  final args = [...positional, ...named];
  if (args.isEmpty) return '$ctor()';
  return '$ctor(${args.map((arg) => '$arg,').join()})';
}

String _argumentExpression(
  A2uiDartFieldPlan field,
  Map<String, String> prefixes, {
  required String widgetName,
}) {
  final property = field.property;
  final variable = _identifierFor(property.name);
  switch (field.emission) {
    // A rich field's prelude has reconstructed the typed value into a
    // reserved-prefixed local; the constructor just references it. The reserved
    // prefix makes a customer property named `data`/`context`/`itemContext`
    // collision-proof against the generated scaffolding.
    case A2uiDataField(rich: true):
      return _richLocalName(property);
    case A2uiDataField(:final node):
      return _dataArgumentExpression(
        node,
        property,
        variable,
        prefixes,
        controlled: _usesControlledValue(field),
      );
    case A2uiChildField(:final slot):
      switch (slot) {
        case A2uiChildNode(:final nullable):
          final child = '_restageA2uiBuildChild(itemContext, '
              'data[${_dartStringLiteral(property.name)}])';
          if (!nullable && property.required) {
            return '_restageA2uiRequireChild(itemContext, '
                'data[${_dartStringLiteral(property.name)}], '
                '${_dartStringLiteral('$widgetName.${property.name}')})';
          }
          if (!nullable) return child;
          return _nullableDataPresenceExpression(property, child, 'null');
        case A2uiChildrenNode(:final nullable):
          final children = '_restageA2uiBuildChildren(itemContext, '
              'data[${_dartStringLiteral(property.name)}])';
          if (!nullable) return children;
          final nullableChildren =
              'data[${_dartStringLiteral(property.name)}] == null '
              '? null : $children';
          return _nullableDataPresenceExpression(
            property,
            '($nullableChildren)',
            children,
          );
      }
  }
}

/// Preserves the child-slot distinction between an omitted nullable input and
/// an input explicitly set to JSON `null`.
///
/// Child builders consume the raw value directly, so they do not have the
/// normalized-null third state handled by [_nullableLeafExpression].
/// Required nullable child fields are guaranteed present by their schema and
/// keep the direct expression.
String _nullableDataPresenceExpression(
  PropertyEntry property,
  String whenPresent,
  String whenAbsent,
) {
  if (property.required) return whenPresent;
  final key = _dartStringLiteral(property.name);
  return 'data.containsKey($key) ? $whenPresent : $whenAbsent';
}

/// Preserves the complete three-state invariant for a nullable leaf.
///
/// A missing optional source uses [fallback]. A present raw JSON or local
/// override `null` remains `null`. A present non-null raw value whose binding,
/// lookup, or conversion produces `null` fails closed to [fallback]. Required
/// nullable fields implement only the latter two states because their schema
/// already requires the source.
String _nullableLeafExpression(
  PropertyEntry property,
  String normalizedValue,
  String fallback, {
  required bool controlled,
}) {
  final key = _dartStringLiteral(property.name);
  final raw = controlled ? _controlledRawVar(property.name) : 'data[$key]';
  final present = controlled
      ? _controlledPresentVar(property.name)
      : 'data.containsKey($key)';
  final recovered =
      fallback == 'null' ? normalizedValue : '($normalizedValue ?? $fallback)';
  final whenPresent = '$raw == null ? null : $recovered';
  if (property.required) return whenPresent;
  return '$present ? ($whenPresent) : $fallback';
}

String _dataArgumentExpression(
  A2uiSchemaNode node,
  PropertyEntry property,
  String variable,
  Map<String, String> prefixes, {
  required bool controlled,
}) {
  switch (node) {
    case ScalarNode(:final type):
      switch (type) {
        case A2uiScalarType.boolean:
          return node.nullable
              ? _nullableLeafExpression(
                  property,
                  variable,
                  _defaultFor(property, prefixes),
                  controlled: controlled,
                )
              : '$variable ?? ${_defaultFor(property, prefixes)}';
        case A2uiScalarType.number:
        case A2uiScalarType.integer:
          return _numberArgumentExpression(
            property,
            variable,
            prefixes,
            nullable: node.nullable,
            controlled: controlled,
          );
        case A2uiScalarType.string:
          if (property.type == PropertyType.color) {
            final color = '_restageA2uiColor($variable)';
            return node.nullable
                ? _nullableLeafExpression(
                    property,
                    color,
                    _defaultFor(property, prefixes),
                    controlled: controlled,
                  )
                : '$color ?? ${_defaultFor(property, prefixes)}';
          }
          return node.nullable
              ? _nullableLeafExpression(
                  property,
                  variable,
                  _defaultFor(property, prefixes),
                  controlled: controlled,
                )
              : '$variable ?? ${_defaultFor(property, prefixes)}';
      }
    case EnumNode(:final dartTypeName, :final nullable):
      final fallback = _defaultFor(property, prefixes);
      final enumType =
          prefixedType(dartTypeName, _enumLibraryUri(property), prefixes);
      final lookup = '$enumType.values.asNameMap()[$variable]';
      // Fail closed: an unknown/absent member resolves to the catalog default
      // — a required enum with no declared default resolves to the first
      // member (via _defaultFor), never a throw; an optional enum keeps the
      // nullable lookup so the widget's own default applies.
      return nullable
          ? _nullableLeafExpression(
              property,
              lookup,
              fallback,
              controlled: controlled,
            )
          : '$lookup ?? $fallback';
    case final ListNode list:
      return _scalarListArgumentExpression(
        list,
        property,
        variable,
        controlled: controlled,
      );
    case ObjectNode():
    case MapNode():
    case UnionNode():
    case RefNode():
      throw StateError(_richNodeUnsupportedMessage(node));
  }
}

/// Reconstructs a reactive bound value as the exact Dart scalar-list type the
/// reflected constructor accepts. A non-list value resolves to null before the
/// existing property fallback policy runs. Non-null elements drop malformed
/// values; nullable elements preserve their position as null. Numeric JSON
/// values normalize to `int` / `double`; Dart `num` preserves the delivered
/// numeric runtime type. Keep this policy aligned with [A2uiDataBuilder].
String _scalarListArgumentExpression(
  ListNode list,
  PropertyEntry property,
  String variable, {
  required bool controlled,
}) {
  final element = list.element;
  if (element is! ScalarNode) {
    throw StateError(
      'A2UI scalar-list construction requires a scalar element; got '
      '${element.runtimeType}. Use a supported List<scalar> field or wrap '
      'the value in a structured data object.',
    );
  }

  final literalFallback = _scalarListLiteralDefault(property, list);
  final normalized = '($variable is List '
      '? $variable.cast<Object?>() '
      ': null)';
  final source = switch ((list.nullable, literalFallback)) {
    (true, final String fallback) => '(${_nullableLeafExpression(
        property,
        normalized,
        fallback,
        controlled: controlled,
      )})',
    (true, null) => '(${_nullableLeafExpression(
        property,
        normalized,
        'null',
        controlled: controlled,
      )})',
    (false, final String fallback) => '($normalized ?? $fallback)',
    (false, null) => '($normalized ?? const <Object?>[])',
  };
  final nullAware = list.nullable ? '?' : '';
  final mapped = switch (element.type) {
    A2uiScalarType.string => element.nullable
        ? '.map((value) => value is String ? value : null)'
        : '.whereType<String>()',
    A2uiScalarType.boolean => element.nullable
        ? '.map((value) => value is bool ? value : null)'
        : '.whereType<bool>()',
    A2uiScalarType.integer =>
      '.map((value) => value is num ? value.toInt() : null)'
          '${element.nullable ? '' : '.whereType<int>()'}',
    A2uiScalarType.number => element.preserveNumericRuntimeType
        ? '.map((value) => value is num ? value : null)'
            '${element.nullable ? '' : '.whereType<num>()'}'
        : '.map((value) => value is num ? value.toDouble() : null)'
            '${element.nullable ? '' : '.whereType<double>()'}',
  };
  return '$source$nullAware$mapped.toList(growable: false)';
}

/// Emits a type-checked literal fallback for a scalar list, or null when the
/// property declares no literal default.
///
/// Invalid declared defaults fail at generation time. Runtime-bound values
/// still use the conversion/filter policy in [_scalarListArgumentExpression].
String? _scalarListLiteralDefault(PropertyEntry property, ListNode list) {
  final source = property.defaultSource;
  if (source is! LiteralDefault) return null;
  final value = source.value;
  if (value is! List) {
    throw StateError(
      'A2UI scalar-list default for "${property.name}" must be a list; '
      'got ${value.runtimeType}.',
    );
  }
  final element = list.element;
  if (element is! ScalarNode) {
    throw StateError(
      'A2UI scalar-list default for "${property.name}" requires a scalar '
      'element; got ${element.runtimeType}.',
    );
  }

  final typeName = switch (element.type) {
    A2uiScalarType.string => 'String',
    A2uiScalarType.boolean => 'bool',
    A2uiScalarType.integer => 'int',
    A2uiScalarType.number =>
      element.preserveNumericRuntimeType ? 'num' : 'double',
  };
  final nullableTypeName = '$typeName${element.nullable ? '?' : ''}';
  final values = <String>[];
  for (var index = 0; index < value.length; index++) {
    final item = value[index];
    if (item == null) {
      if (!element.nullable) {
        throw StateError(
          'A2UI scalar-list default for "${property.name}" has null at '
          'index $index, but its element type is $typeName.',
        );
      }
      values.add('null');
      continue;
    }

    final literal = switch (element.type) {
      A2uiScalarType.string => item is String ? _dartStringLiteral(item) : null,
      A2uiScalarType.boolean => item is bool ? item.toString() : null,
      A2uiScalarType.integer => item is int ? item.toString() : null,
      A2uiScalarType.number => _numericListDefaultLiteral(
          item,
          preserveNumericRuntimeType: element.preserveNumericRuntimeType,
        ),
    };
    if (literal == null) {
      throw StateError(
        'A2UI scalar-list default for "${property.name}" has '
        '${item.runtimeType} at index $index; expected $nullableTypeName.',
      );
    }
    values.add(literal);
  }
  return 'const <$nullableTypeName>[${values.join(', ')}]';
}

String? _numericListDefaultLiteral(
  Object? value, {
  required bool preserveNumericRuntimeType,
}) {
  if (preserveNumericRuntimeType) {
    if (value is int) return value.toString();
    if (value is double && value.isFinite) return value.toString();
    return null;
  }
  return value is double && value.isFinite ? value.toString() : null;
}

String _numberArgumentExpression(
  PropertyEntry property,
  String variable,
  Map<String, String> prefixes, {
  required bool nullable,
  required bool controlled,
}) {
  final fallback = _defaultFor(property, prefixes);
  switch (property.type) {
    case PropertyType.integer:
      if (nullable) {
        return _nullableLeafExpression(
          property,
          '$variable?.toInt()',
          '($variable ?? $fallback).toInt()',
          controlled: controlled,
        );
      }
      return '($variable ?? $fallback).toInt()';
    case PropertyType.real:
    case PropertyType.length:
      if (nullable) {
        return _nullableLeafExpression(
          property,
          '$variable?.toDouble()',
          '($variable ?? $fallback).toDouble()',
          controlled: controlled,
        );
      }
      return '($variable ?? $fallback).toDouble()';
    case PropertyType.duration:
      if (nullable) {
        return _nullableLeafExpression(
          property,
          '($variable == null '
              '? null : Duration(milliseconds: $variable.toInt()))',
          'Duration(milliseconds: ($variable ?? $fallback).toInt())',
          controlled: controlled,
        );
      }
      return 'Duration(milliseconds: ($variable ?? $fallback).toInt())';
    case PropertyType.fontWeight:
      if (nullable) {
        return _nullableLeafExpression(
          property,
          '($variable == null '
              '? null : _restageA2uiFontWeight($variable, $fallback))',
          '_restageA2uiFontWeight($variable, $fallback)',
          controlled: controlled,
        );
      }
      return '_restageA2uiFontWeight($variable, $fallback)';
    case PropertyType.widget:
    case PropertyType.widgetList:
    case PropertyType.color:
    case PropertyType.edgeInsets:
    case PropertyType.alignment:
    case PropertyType.alignmentXY:
    case PropertyType.offset:
    case PropertyType.boolean:
    case PropertyType.string:
    case PropertyType.stringList:
    case PropertyType.event:
    case PropertyType.dataReference:
    case PropertyType.enumValue:
    case PropertyType.gradient:
    case PropertyType.border:
    case PropertyType.boxShadowList:
    case PropertyType.locale:
    case PropertyType.paint:
    case PropertyType.shadowList:
    case PropertyType.fontFeatureList:
    case PropertyType.fontVariationList:
    case PropertyType.textDecoration:
    case PropertyType.shapeBorder:
    case PropertyType.structured:
    case PropertyType.decorationImage:
    case PropertyType.inlineSpan:
    case PropertyType.selectionOptionList:
    case PropertyType.booleanList:
    case PropertyType.curve:
    case PropertyType.unknown:
      throw StateError(
        'PropertyType.${property.type.name} is not a BoundNumber field.',
      );
  }
}

String _defaultFor(PropertyEntry property, Map<String, String> prefixes) {
  final source = property.defaultSource;
  final value = source is LiteralDefault ? source.value : property.defaultValue;
  if (value != null) {
    final literal = _literalDefaultExpression(property, value, prefixes);
    if (literal != null) return literal;
  }

  // A required (non-nullable) enum with no catalog-declared default must still
  // receive a valid member when the bound value is null/unknown — fail CLOSED
  // to the first declared member, never a throw (an unknown enum member must
  // never crash the render, per the capability fail-closed contract).
  if (property.required && property.type == PropertyType.enumValue) {
    final enumType = _enumDartTypeName(property);
    if (enumType != null) {
      final spelled =
          prefixedType(enumType, _enumLibraryUri(property), prefixes);
      return '$spelled.values.first';
    }
  }

  switch (property.type) {
    case PropertyType.boolean:
      return 'false';
    case PropertyType.integer:
    case PropertyType.real:
    case PropertyType.length:
    case PropertyType.duration:
      return '0';
    case PropertyType.fontWeight:
      return 'FontWeight.normal';
    case PropertyType.string:
      return "''";
    case PropertyType.color:
      return 'const Color(0x00000000)';
    case PropertyType.enumValue:
      return 'null';
    case PropertyType.stringList:
      return 'const <Object?>[]';
    case PropertyType.widget:
    case PropertyType.widgetList:
    case PropertyType.edgeInsets:
    case PropertyType.alignment:
    case PropertyType.alignmentXY:
    case PropertyType.offset:
    case PropertyType.event:
    case PropertyType.dataReference:
    case PropertyType.gradient:
    case PropertyType.border:
    case PropertyType.boxShadowList:
    case PropertyType.locale:
    case PropertyType.paint:
    case PropertyType.shadowList:
    case PropertyType.fontFeatureList:
    case PropertyType.fontVariationList:
    case PropertyType.textDecoration:
    case PropertyType.shapeBorder:
    case PropertyType.structured:
    case PropertyType.decorationImage:
    case PropertyType.inlineSpan:
    case PropertyType.selectionOptionList:
    case PropertyType.booleanList:
    case PropertyType.curve:
    case PropertyType.unknown:
      return 'null';
  }
}

String? _literalDefaultExpression(
  PropertyEntry property,
  Object value,
  Map<String, String> prefixes,
) {
  if (value is bool) return value.toString();
  if (value is int) {
    if (property.type == PropertyType.color) {
      return 'const Color(0x${value.toRadixString(16).padLeft(8, '0')})';
    }
    return value.toString();
  }
  if (value is double) return value.toString();
  if (value is String) {
    if (property.type == PropertyType.enumValue) {
      final enumType = _enumDartTypeName(property);
      if (enumType == null) return null;
      final spelled =
          prefixedType(enumType, _enumLibraryUri(property), prefixes);
      return '$spelled.$value';
    }
    if (property.type == PropertyType.color) {
      return '_restageA2uiColor(${_dartStringLiteral(value)}) ?? '
          'const Color(0x00000000)';
    }
    return _dartStringLiteral(value);
  }
  if (value is List && property.type == PropertyType.stringList) {
    final values = [
      for (final item in value)
        if (item is String) _dartStringLiteral(item),
    ];
    return 'const <Object?>[${values.join(', ')}]';
  }
  return null;
}

/// The per-widget interaction lowering plan: wired write-back pairs, wired
/// dispatch callbacks, and any callbacks scoped out loud (with the reason).
@immutable
class _InteractionPlan {
  const _InteractionPlan({
    this.writeBacks = const [],
    this.dispatches = const [],
    this.scopedByCallbackName = const {},
  });

  /// Wired write-back pairs (the auto single-pair rule resolves at most one).
  final List<A2uiWriteBack> writeBacks;

  /// Wired dispatch callbacks (named `VoidCallback`s).
  final List<PropertyEntry> dispatches;

  /// Callbacks scoped out loud, keyed by callback property name.
  final Map<String, A2uiDartCoverageReason> scopedByCallbackName;
}

/// Resolves the interaction lowering for [entry] from [eventSeam]: write-back
/// pairs (the auto single-pair rule) plus dispatch callbacks. A built-in
/// catalog carries no seam → no interactions → returns null (byte-neutral).
///
/// Only NAMED callbacks are wired (a positional callback's constructor slot
/// cannot be allocated without risking a positional shift, so it falls through
/// to the unchanged catalog-fed event path). An unsupported-signature callback
/// likewise falls through to the catalog-fed event path.
_InteractionPlan? _resolveInteractions(
  WidgetEntry entry,
  A2uiEventSeam? eventSeam,
  A2uiPairingSeam? pairingSeam,
  A2uiRichShapes? richShapes,
) {
  if (eventSeam == null) return null;
  final writeBackCallbacks =
      <({PropertyEntry property, A2uiCallbackWriteBack signature})>[];
  final dispatches = <PropertyEntry>[];
  final unsupported = <String>[];
  final invalidPairings = <String>[];
  for (final property in entry.properties) {
    // A positional callback is skipped REGARDLESS of its signature: its ctor
    // slot cannot be allocated without risking a positional shift, so it falls
    // through to the catalog-fed event path (`eventProperty`) — the position is
    // the blocker. The distinct `#sig`/`#L` census below is for a NAMED
    // callback whose SIGNATURE is the blocker (it could lower if supported).
    if (property.type != PropertyType.event || property.positional) continue;
    final signature = eventSeam[(entry.name, property.name)];
    if (signature is A2uiCallbackWriteBack) {
      writeBackCallbacks.add((property: property, signature: signature));
    } else if (pairingSeam?[(entry.name, property.name)] != null) {
      // A `writeBackValue` pairing on a NON-write-back callback (dispatch /
      // unsupported / unclassified) is incoherent — there is no value to write
      // back — so fail closed loud rather than silently honour the callback's
      // normal disposition and ignore the bad pairing.
      invalidPairings.add(property.name);
    } else if (signature is A2uiCallbackDispatch) {
      dispatches.add(property);
    } else if (signature is A2uiCallbackUnsupported) {
      // The reflector could not lower this callback's signature (#sig / #L) —
      // scope it out loud rather than mis-lower or silently drop it.
      unsupported.add(property.name);
    }
  }

  final (:writeBacks, :scoped) = _resolveWriteBackPairs(
    entry,
    writeBackCallbacks,
    pairingSeam,
    richShapes,
  );

  final scopedByCallbackName = {
    ...scoped,
    for (final name in unsupported)
      name: A2uiDartCoverageReason.unsupportedInteractiveCallback,
    for (final name in invalidPairings)
      name: A2uiDartCoverageReason.invalidExplicitWritePairing,
  };

  if (writeBacks.isEmpty &&
      dispatches.isEmpty &&
      scopedByCallbackName.isEmpty) {
    return null;
  }
  return _InteractionPlan(
    writeBacks: writeBacks,
    dispatches: dispatches,
    scopedByCallbackName: scopedByCallbackName,
  );
}

/// Resolves the write-back pairs for [entry]'s write-back [callbacks].
///
/// A callback with an explicit `@RestageProperty(writeBackValue:)` pairing (in
/// [pairingSeam]) OVERRIDES the auto rule: it resolves the named pair directly,
/// validated the same way (the named value prop exists + is a matching-type
/// bindable leaf), enabling MULTIPLE write-backs on a multi-control widget. Two
/// callbacks naming the SAME value property collide → both fail closed loud. A
/// callback WITHOUT a pairing takes the auto single-pair rule ONLY when it is
/// the sole write-back callback and no explicit pairing is present (the
/// zero-annotation default); otherwise it is ambiguous (`#pair` — annotate
/// every control). Every ambiguity / bad pairing fails closed loud with a
/// named reason.
({
  List<A2uiWriteBack> writeBacks,
  Map<String, A2uiDartCoverageReason> scoped,
}) _resolveWriteBackPairs(
  WidgetEntry entry,
  List<({PropertyEntry property, A2uiCallbackWriteBack signature})> callbacks,
  A2uiPairingSeam? pairingSeam,
  A2uiRichShapes? richShapes,
) {
  if (callbacks.isEmpty) {
    return (writeBacks: const [], scoped: const {});
  }

  String? targetOf(PropertyEntry callback) =>
      pairingSeam?[(entry.name, callback.name)];

  final annotated =
      callbacks.where((c) => targetOf(c.property) != null).toList();
  final unAnnotated =
      callbacks.where((c) => targetOf(c.property) == null).toList();

  final writeBacks = <A2uiWriteBack>[];
  final scoped = <String, A2uiDartCoverageReason>{};

  // Explicit pairings. Two annotated callbacks naming the SAME value property
  // collide (ambiguous which one controls it) → both fail closed loud.
  final targetCounts = <String, int>{};
  for (final c in annotated) {
    final target = targetOf(c.property)!;
    targetCounts[target] = (targetCounts[target] ?? 0) + 1;
  }
  for (final c in annotated) {
    final target = targetOf(c.property)!;
    final reason = (targetCounts[target] ?? 0) > 1
        ? A2uiDartCoverageReason.invalidExplicitWritePairing
        : _validateExplicitPairing(entry, c.signature, target, richShapes);
    if (reason != null) {
      scoped[c.property.name] = reason;
    } else {
      writeBacks.add(
        A2uiWriteBack(
          callbackProperty: c.property,
          valuePropertyName: target,
        ),
      );
    }
  }

  // Un-annotated callbacks: the auto single-pair rule applies ONLY when there
  // are no explicit pairings AND exactly one un-annotated callback (the
  // zero-annotation default). Otherwise each is ambiguous (annotate every
  // control).
  if (unAnnotated.isNotEmpty) {
    if (annotated.isEmpty && unAnnotated.length == 1) {
      final (writeBacks: autoWriteBacks, scoped: autoScoped) =
          _autoSinglePair(entry, unAnnotated.single, richShapes);
      writeBacks.addAll(autoWriteBacks);
      scoped.addAll(autoScoped);
    } else {
      for (final c in unAnnotated) {
        scoped[c.property.name] = A2uiDartCoverageReason.ambiguousWritePairing;
      }
    }
  }

  return (writeBacks: writeBacks, scoped: scoped);
}

/// Validates an explicit pairing of a write-back [signature] to the value
/// property named [valuePropertyName]. Returns a fail-closed reason when the
/// named property does not exist, does not match the callback's value type, or
/// is not a bindable leaf; null when the pairing is valid.
A2uiDartCoverageReason? _validateExplicitPairing(
  WidgetEntry entry,
  A2uiCallbackWriteBack signature,
  String valuePropertyName,
  A2uiRichShapes? richShapes,
) {
  final valueProp =
      entry.properties.firstWhereOrNull((p) => p.name == valuePropertyName);
  if (valueProp == null ||
      !_valuePropMatchesSignature(
        signature,
        entry.name,
        valueProp,
        richShapes,
      ) ||
      !_isBindableLeaf(entry.name, valueProp, richShapes)) {
    return A2uiDartCoverageReason.invalidExplicitWritePairing;
  }
  return null;
}

/// The auto single-pair rule for one un-annotated write-back [callback]: it
/// pairs with the widget's single matching-type value property. 0 matches →
/// uncontrolled; >1 → ambiguous; a non-bindable match → `#lit`. Fails closed
/// loud on each.
({
  List<A2uiWriteBack> writeBacks,
  Map<String, A2uiDartCoverageReason> scoped,
}) _autoSinglePair(
  WidgetEntry entry,
  ({PropertyEntry property, A2uiCallbackWriteBack signature}) callback,
  A2uiRichShapes? richShapes,
) {
  final matching = [
    for (final property in entry.properties)
      if (property.type != PropertyType.event)
        if (_valuePropMatchesSignature(
          callback.signature,
          entry.name,
          property,
          richShapes,
        ))
          property,
  ];
  final reason = switch (matching.length) {
    // No value property to control → an uncontrolled widget whose state would
    // be ephemeral Flutter state, not the data model.
    0 => A2uiDartCoverageReason.uncontrolledInteractiveWidget,
    1 => null,
    // More than one matching value property → which to write is ambiguous.
    _ => A2uiDartCoverageReason.ambiguousWritePairing,
  };
  if (reason != null) {
    return (writeBacks: const [], scoped: {callback.property.name: reason});
  }

  final valueProperty = matching.single;
  if (!_isBindableLeaf(entry.name, valueProperty, richShapes)) {
    // The value property is not a bindable data leaf, so its read cannot be
    // rewritten to the write-back path and the write-back could not round-trip.
    return (
      writeBacks: const [],
      scoped: {
        callback.property.name: A2uiDartCoverageReason.writeBackValueNotBound,
      },
    );
  }
  return (
    writeBacks: [
      A2uiWriteBack(
        callbackProperty: callback.property,
        valuePropertyName: valueProperty.name,
      ),
    ],
    scoped: const {},
  );
}

/// Whether [type] is one of the numeric scalar kinds (the catalog collapses
/// `int` / `double` to [A2uiScalarType.number], so they are one family).
bool _isNumericScalar(A2uiScalarType type) =>
    type == A2uiScalarType.number || type == A2uiScalarType.integer;

/// Whether a write-back value [callbackType] and a value-property [valueType]
/// are the same scalar family — the numeric kinds match each other; otherwise
/// equal.
bool _scalarFamilyMatches(
  A2uiScalarType callbackType,
  A2uiScalarType valueType,
) =>
    (_isNumericScalar(callbackType) && _isNumericScalar(valueType)) ||
    callbackType == valueType;

/// Whether [node] is the analyzer/catalog leaf admitted as `List<scalar>`.
bool _isScalarListNode(A2uiSchemaNode? node) => isA2uiScalarListNode(node);

/// Whether [property] is the controlled value for write-back [signature]. A
/// scalar callback pairs a `ScalarNode` value prop of the same scalar family,
/// while an enum pairs with its string wire representation;
/// a `List<scalar>` callback pairs only a list with the exact same outer
/// nullability, element nullability, scalar type, and numeric reconstruction
/// behavior. Analyzer-fed scalar-list leaves use their reflected node, so the
/// complete Dart list shape remains available at this round-trip boundary.
bool _valuePropMatchesSignature(
  A2uiCallbackWriteBack signature,
  String widgetName,
  PropertyEntry property,
  A2uiRichShapes? richShapes,
) {
  final reflected = richShapes?[(widgetName, property.name)];
  final node = reflected is ScalarNode ||
          reflected is EnumNode ||
          _isScalarListNode(reflected)
      ? reflected
      : _dataNode(property);
  if (signature.isList) {
    return switch (node) {
      ListNode(
        nullable: final nullable,
        element: ScalarNode(
          :final type,
          nullable: final elementNullable,
          :final preserveNumericRuntimeType,
        ),
      ) =>
        signature.nullable == nullable &&
            signature.elementNullable == elementNullable &&
            signature.valueType == type &&
            signature.preserveNumericRuntimeType == preserveNumericRuntimeType,
      _ => false,
    };
  }
  return (node is ScalarNode &&
          _scalarFamilyMatches(signature.valueType, node.type)) ||
      (node is EnumNode && signature.valueType == A2uiScalarType.string);
}

/// Whether [property] (on widget [widgetName]) classifies to a bindable
/// catalog-fed leaf — a scalar, enum, or `List<scalar>` — using the same
/// conditions
/// [_classifyField] applies before emitting a leaf data field, so a value
/// property that passes here can route through the shared controlled-value
/// state machine.
///
/// An analyzer-fed scalar list IS a bindable leaf: classification keeps it in a
/// safe object binding, using its reflected element node for type-safe list
/// construction.
/// Other analyzer-fed shapes reconstruct raw in the prelude and remain
/// non-bindable, keeping rich reconstruction and `{path:P}` binding mutually
/// exclusive.
bool _isBindableLeaf(
  String widgetName,
  PropertyEntry property,
  A2uiRichShapes? richShapes,
) {
  if (_childSlot(property) != null) return false;
  if (property.type == PropertyType.event) return false;
  if (property.defaultSource is ThemeBindingDefault) return false;
  if (property.synthetic != null) return false;
  if (_isReservedBuilderIdentifier(property.name)) return false;
  final node = _bindableLeafNode(widgetName, property, richShapes);
  return node is ScalarNode || node is EnumNode || _isScalarListNode(node);
}

/// The write-back value field paired with [writeBack]. Pairing validation has
/// already guaranteed exactly one field; keep the lookup central so every
/// emitter seam applies the same controlled-leaf rollout predicate.
A2uiDartFieldPlan _writeBackValueField(
  A2uiDartWidgetPlan widget,
  A2uiWriteBack writeBack,
) =>
    widget.fields.singleWhere(
      (field) => field.property.name == writeBack.valuePropertyName,
    );

/// Whether [field] uses the shared controlled-value state machine. Every
/// supported write-back leaf family routes through this single predicate so
/// source identity, local override provenance, cancellation, and stale-event
/// rejection cannot drift between scalar and scalar-list constructor paths.
bool _usesControlledValue(A2uiDartFieldPlan field) {
  final emission = field.emission;
  if (emission is! A2uiDataField || !emission.writeBack) return false;
  return switch (emission.node) {
    ScalarNode() || EnumNode() => true,
    final ListNode node => _isScalarListNode(node),
    _ => false,
  };
}

/// The effective leaf node for [property], preferring an analyzer-fed scalar
/// list over the coarser catalog type. Any other analyzer-fed shape is rich and
/// therefore not bindable.
A2uiSchemaNode? _bindableLeafNode(
  String widgetName,
  PropertyEntry property,
  A2uiRichShapes? richShapes,
) {
  final reflected = richShapes?[(widgetName, property.name)];
  if (reflected != null) {
    if (reflected is ScalarNode || reflected is EnumNode) return reflected;
    if (_isScalarListNode(reflected)) {
      if (!property.required && !reflected.nullable) return null;
      return reflected;
    }
    return null;
  }
  return _dataNode(property);
}

/// The prelude local naming the resolved write-back data path for a value
/// property [valuePropertyName].
String _writeBackPathVar(String valuePropertyName) =>
    '_restageA2uiPath_${_identifierFor(valuePropertyName)}';

/// The prelude local holding the raw value reference (a `{path}` binding or a
/// literal) the data path is derived from.
String _writeBackRefVar(String valuePropertyName) =>
    '_restageA2uiRef_${_identifierFor(valuePropertyName)}';

/// The self-scoped allocation path used by a controlled leaf literal or
/// function-call override.
String _writeBackSelfPathVar(String valuePropertyName) =>
    'restageA2uiSelfPath${_controlledLocalSuffix(valuePropertyName)}';

/// The state-machine writer supplied to the paired Flutter callback.
String _writeBackWriterVar(String valuePropertyName) =>
    'restageA2uiWrite${_controlledLocalSuffix(valuePropertyName)}';

/// The effective raw source value supplied by the controlled state machine.
String _controlledRawVar(String valuePropertyName) =>
    'restageA2uiRaw${_controlledLocalSuffix(valuePropertyName)}';

/// Whether the effective controlled source is present (distinct from null).
String _controlledPresentVar(String valuePropertyName) =>
    'restageA2uiPresent${_controlledLocalSuffix(valuePropertyName)}';

/// The effective source kind supplied by the controlled state machine.
String _controlledKindVar(String valuePropertyName) =>
    'restageA2uiKind${_controlledLocalSuffix(valuePropertyName)}';

String _controlledLocalSuffix(String valuePropertyName) {
  final identifier = _identifierFor(valuePropertyName);
  return '${identifier[0].toUpperCase()}${identifier.substring(1)}';
}

_FieldClassification _classifyField(
  WidgetEntry entry,
  PropertyEntry property,
  A2uiRichShapes? richShapes,
  bool prefixesCustomerLibs,
) {
  if (isReservedA2uiComponentEnvelopeField(property.name)) {
    _rejectA2uiConstraintOmission(
      entry,
      property,
      'reserved GenUI component-envelope field drops the widget',
    );
    return _DropWidget(
      A2uiDartWidgetDrop(
        widgetName: entry.name,
        fieldName: property.name,
        reason: A2uiDartCoverageReason.requiredUnsupportedPropertyType,
      ),
    );
  }

  final reflectedNode = richShapes?[(entry.name, property.name)];
  final childSlot = _childSlot(property, reflectedNode);
  if (childSlot != null) {
    _rejectA2uiConstraintsWithoutDataNode(entry, property, 'child slot');
    return _EmitField(
      A2uiDartFieldPlan._(
        property: property,
        emission: A2uiChildField(childSlot),
      ),
    );
  }

  // The analyzer-fed rich shape is authoritative for the properties it covers
  // (the reflector already routed events out and scoped unsupported shapes
  // loud), so it overrides the catalog classification below.
  if (reflectedNode != null) {
    if (reflectedNode is ScalarNode || reflectedNode is EnumNode) {
      if (_isReservedBuilderIdentifier(property.name)) {
        return _fieldUnsupported(
          entry,
          property,
          reason: property.required
              ? A2uiDartCoverageReason.requiredUnsupportedPropertyType
              : A2uiDartCoverageReason.optionalUnsupportedPropertyType,
        );
      }
      return _EmitField(
        A2uiDartFieldPlan._(
          property: property,
          emission: A2uiDataField(
            reflectedNode,
            constraints: _normalizeA2uiConstraints(
              entry,
              property,
              reflectedNode,
            ),
          ),
        ),
      );
    }
    final constraints = _normalizeA2uiConstraints(
      entry,
      property,
      reflectedNode,
    );
    return _classifyRichField(
      entry,
      property,
      reflectedNode,
      constraints,
    );
  }

  if (property.type == PropertyType.event) {
    _rejectA2uiConstraintsWithoutDataNode(entry, property, 'event');
    if (property.required) {
      return _DropWidget(
        A2uiDartWidgetDrop(
          widgetName: entry.name,
          fieldName: property.name,
          reason: A2uiDartCoverageReason.eventProperty,
        ),
      );
    }
    return _OmitField(
      A2uiDartFieldOmission(
        widgetName: entry.name,
        fieldName: property.name,
        reason: A2uiDartCoverageReason.eventProperty,
      ),
    );
  }

  if (property.defaultSource is ThemeBindingDefault) {
    _rejectA2uiConstraintOmission(
      entry,
      property,
      'theme default field is omitted',
    );
    return _OmitField(
      A2uiDartFieldOmission(
        widgetName: entry.name,
        fieldName: property.name,
        reason: A2uiDartCoverageReason.themeDefault,
      ),
    );
  }

  if (property.synthetic != null) {
    return _fieldUnsupported(
      entry,
      property,
      reason: A2uiDartCoverageReason.syntheticUnsupported,
    );
  }

  if (property.type == PropertyType.enumValue &&
      _enumDartTypeName(property) == null) {
    return _fieldUnsupported(
      entry,
      property,
      reason: A2uiDartCoverageReason.missingEnumType,
    );
  }

  // A catalog-fed enum without a resolvable library (no `EnumShape`, only the
  // bare `enumType` name) can be spelled bare safely only when nothing is
  // import-prefixed — a flutter enum (`Axis`) resolves through the unprefixed
  // flutter import. Once the file prefixes a customer library, a bare enum that
  // is actually a customer type would be unresolved; fail closed loud rather
  // than emit it. (Properly compiled customer catalogs carry an `EnumShape`
  // with the library URI; this guards the legacy/hand-built gap.)
  if (property.type == PropertyType.enumValue &&
      prefixesCustomerLibs &&
      _enumLibraryUri(property) == null) {
    return _fieldUnsupported(
      entry,
      property,
      reason: A2uiDartCoverageReason.missingEnumType,
    );
  }

  final node = _dataNode(property);
  if (node == null) {
    return _fieldUnsupported(
      entry,
      property,
      reason: property.required
          ? A2uiDartCoverageReason.requiredUnsupportedPropertyType
          : A2uiDartCoverageReason.optionalUnsupportedPropertyType,
    );
  }

  // A catalog-fed leaf field binds through a `Bound*` builder whose value
  // parameter is named after the property; a property whose generated
  // identifier is one of the builder scaffolding names (`data` / `context` /
  // `itemContext`) would shadow the scaffolding and mis-render. Fail closed
  // loud rather than emit a shadowed local (built-ins never hit this — the only
  // such built-in property, `Text.data`, is curated to `text`). The rich path
  // is immune (its locals are reserved-prefixed).
  if (_isReservedBuilderIdentifier(property.name)) {
    return _fieldUnsupported(
      entry,
      property,
      reason: property.required
          ? A2uiDartCoverageReason.requiredUnsupportedPropertyType
          : A2uiDartCoverageReason.optionalUnsupportedPropertyType,
    );
  }

  final constraints = _normalizeA2uiConstraints(entry, property, node);
  return _EmitField(
    A2uiDartFieldPlan._(
      property: property,
      emission: A2uiDataField(node, constraints: constraints),
    ),
  );
}

/// Normalizes the mutually exclusive typed/legacy property surfaces once,
/// before either schema projector can observe them.
A2uiConstraintSet _normalizeA2uiConstraints(
  WidgetEntry entry,
  PropertyEntry property,
  A2uiSchemaNode node,
) {
  final typed = property.constraints;
  final legacy = property.validationRule;
  if (legacy != null && !typed.isEmpty) {
    _a2uiConstraintFailure(
      entry,
      property,
      'validationRule and typed constraints are mutually exclusive',
    );
  }
  if (legacy != null) {
    late final RestageConstraints parsed;
    try {
      parsed = parseA2uiLegacyConstraint(legacy.expression);
      _validateA2uiTypedConstraints(entry, property, node, parsed);
      _validateA2uiPattern(entry, property, parsed.pattern);
    } on A2uiLegacyConstraintParseException catch (error) {
      _a2uiLegacyConstraintFailure(entry, property, legacy, error.detail);
      // The shared typed validator intentionally reports contract violations
      // as UnsupportedError; legacy authoring adds its source expression here.
      // ignore: avoid_catching_errors
    } on UnsupportedError catch (error) {
      _a2uiLegacyConstraintFailure(
        entry,
        property,
        legacy,
        error.message ?? error.toString(),
      );
    }
    return A2uiConstraintSet.fromTyped(parsed);
  }
  _validateA2uiTypedConstraints(entry, property, node, typed);
  _validateA2uiPattern(entry, property, typed.pattern);
  return A2uiConstraintSet.fromTyped(typed);
}

void _validateA2uiPattern(
  WidgetEntry entry,
  PropertyEntry property,
  String? pattern,
) {
  if (pattern == null) return;
  final rejection = a2uiSafePatternRejection(pattern);
  if (rejection == null) return;
  _a2uiConstraintFailure(
    entry,
    property,
    'pattern "$pattern" is outside the safe ASCII pattern grammar: $rejection',
  );
}

Never _a2uiLegacyConstraintFailure(
  WidgetEntry entry,
  PropertyEntry property,
  ValidationExpr legacy,
  String detail,
) =>
    throw UnsupportedError(
      'A2UI validation rule "${legacy.expression}" on widget '
      '"${entry.name}", property "${property.name}" is invalid: $detail. '
      'Supported legacy forms are '
      'range(<finite number>, <finite number>), '
      'oneOf(<JSON scalar>, ...), and matches(<JSON string>). '
      'Authored message: "${legacy.message}".',
    );

void _rejectA2uiConstraintsWithoutDataNode(
  WidgetEntry entry,
  PropertyEntry property,
  String target,
) {
  if (!_hasExplicitA2uiConstraintMetadata(property)) return;
  _a2uiConstraintFailure(
    entry,
    property,
    'constraints require a data-schema node; $target fields do not have one',
  );
}

void _validateA2uiTypedConstraints(
  WidgetEntry entry,
  PropertyEntry property,
  A2uiSchemaNode node,
  RestageConstraints constraints,
) {
  if (constraints.minimum != null && constraints.exclusiveMinimum != null) {
    _a2uiConstraintFailure(
      entry,
      property,
      'minimum and exclusiveMinimum are mutually exclusive',
    );
  }
  if (constraints.maximum != null && constraints.exclusiveMaximum != null) {
    _a2uiConstraintFailure(
      entry,
      property,
      'maximum and exclusiveMaximum are mutually exclusive',
    );
  }

  final numericBounds = <String, num?>{
    'minimum': constraints.minimum,
    'exclusiveMinimum': constraints.exclusiveMinimum,
    'maximum': constraints.maximum,
    'exclusiveMaximum': constraints.exclusiveMaximum,
  };
  final hasNumeric = numericBounds.values.any((value) => value != null);
  final numericNode = node is ScalarNode &&
      (node.type == A2uiScalarType.number ||
          node.type == A2uiScalarType.integer);
  if (hasNumeric && !numericNode) {
    _a2uiConstraintFailure(
      entry,
      property,
      'numeric constraints require a number or integer node; '
      'got ${node.runtimeType}',
    );
  }
  for (final bound in numericBounds.entries) {
    final value = bound.value;
    if (value != null && !value.isFinite) {
      _a2uiConstraintFailure(
        entry,
        property,
        '${bound.key} must be finite',
      );
    }
  }
  final lower = constraints.minimum ?? constraints.exclusiveMinimum;
  final upper = constraints.maximum ?? constraints.exclusiveMaximum;
  if (lower != null && upper != null) {
    final equalWithExclusive = lower == upper &&
        (constraints.exclusiveMinimum != null ||
            constraints.exclusiveMaximum != null);
    if (lower > upper || equalWithExclusive) {
      _a2uiConstraintFailure(
        entry,
        property,
        'contradictory numeric lower and upper bounds',
      );
    }
  }

  final hasString = constraints.pattern != null ||
      constraints.minLength != null ||
      constraints.maxLength != null;
  final stringNode = node is EnumNode ||
      node is ScalarNode && node.type == A2uiScalarType.string;
  if (hasString && !stringNode) {
    _a2uiConstraintFailure(
      entry,
      property,
      'string constraints require a string or enum node; '
      'got ${node.runtimeType}',
    );
  }
  _validateA2uiNonNegativePair(
    entry,
    property,
    constraints.minLength,
    constraints.maxLength,
    minimumName: 'minLength',
    maximumName: 'maxLength',
  );

  final hasItems = constraints.minItems != null || constraints.maxItems != null;
  if (hasItems && node is! ListNode) {
    _a2uiConstraintFailure(
      entry,
      property,
      'item constraints require a list node; got ${node.runtimeType}',
    );
  }
  _validateA2uiNonNegativePair(
    entry,
    property,
    constraints.minItems,
    constraints.maxItems,
    minimumName: 'minItems',
    maximumName: 'maxItems',
  );

  final allowed = constraints.allowedValues;
  if (allowed == null) return;
  if (allowed.isEmpty) {
    _a2uiConstraintFailure(entry, property, 'allowedValues must not be empty');
  }
  if (node is! ScalarNode && node is! EnumNode) {
    _a2uiConstraintFailure(
      entry,
      property,
      'allowedValues require a scalar node; got ${node.runtimeType}',
    );
  }
  if (node is EnumNode && node.members.isEmpty) {
    _a2uiConstraintFailure(
      entry,
      property,
      'allowedValues on an enum require an analyzer-resolved enum member set',
    );
  }
  for (var i = 0; i < allowed.length; i++) {
    final value = allowed[i];
    if (value is! String && value is! num && value is! bool && value != null) {
      _a2uiConstraintFailure(
        entry,
        property,
        'allowedValues[$i] must be a JSON scalar; got ${value.runtimeType}',
      );
    }
    if (value is num && !value.isFinite) {
      _a2uiConstraintFailure(
        entry,
        property,
        'allowedValues[$i] numeric value must be finite',
      );
    }
    for (var previous = 0; previous < i; previous++) {
      if (allowed[previous] == value) {
        _a2uiConstraintFailure(
          entry,
          property,
          'duplicate allowedValues[$i] value $value',
        );
      }
    }
    if (value == null) continue;
    final compatible = switch (node) {
      ScalarNode(type: A2uiScalarType.boolean) => value is bool,
      ScalarNode(type: A2uiScalarType.integer) => value is int,
      ScalarNode(type: A2uiScalarType.number) => value is num && value.isFinite,
      ScalarNode(type: A2uiScalarType.string) || EnumNode() => value is String,
      _ => false,
    };
    if (!compatible) {
      _a2uiConstraintFailure(
        entry,
        property,
        'allowedValues[$i] value $value (${value.runtimeType}) is not '
        'compatible with ${node.runtimeType}',
      );
    }
    if (node case EnumNode(:final members) when !members.contains(value)) {
      _a2uiConstraintFailure(
        entry,
        property,
        'allowedValues[$i] "$value" is not a resolved enum member',
      );
    }
  }
}

void _validateA2uiNonNegativePair(
  WidgetEntry entry,
  PropertyEntry property,
  int? minimum,
  int? maximum, {
  required String minimumName,
  required String maximumName,
}) {
  if (minimum != null && minimum < 0) {
    _a2uiConstraintFailure(
      entry,
      property,
      '$minimumName must be non-negative',
    );
  }
  if (maximum != null && maximum < 0) {
    _a2uiConstraintFailure(
      entry,
      property,
      '$maximumName must be non-negative',
    );
  }
  if (minimum != null && maximum != null && minimum > maximum) {
    _a2uiConstraintFailure(
      entry,
      property,
      '$minimumName must not exceed $maximumName',
    );
  }
}

Never _a2uiConstraintFailure(
  WidgetEntry entry,
  PropertyEntry property,
  String detail,
) =>
    throw UnsupportedError(
      'A2UI constraint validation failed on widget "${entry.name}", '
      'property "${property.name}": $detail.',
    );

/// Classifies a property the reflector resolved to an analyzer-fed data [node].
///
/// An OPTIONAL, NON-null argument has no synthesizable default, so it is
/// omitted (loud) — the widget's own constructor default applies, the correct
/// optional fail-safe (mirroring the reflector's optional-object scope-out, one
/// level up at the argument site). A REQUIRED argument (fail-safe-guarded) or a
/// NULLABLE argument (pass-through) is emitted as a rich data field. A scalar
/// list is instead emitted as a reactive leaf for literal/path/write-back
/// parity.
_FieldClassification _classifyRichField(
  WidgetEntry entry,
  PropertyEntry property,
  A2uiSchemaNode node,
  A2uiConstraintSet constraints,
) {
  if (!property.required && !node.nullable) {
    _rejectA2uiConstraintOmission(
      entry,
      property,
      'optional non-null rich field is omitted',
    );
    // A POSITIONAL field cannot be omitted without shifting every later
    // positional argument into the wrong slot — drop the whole widget closed.
    // A named field is safely omitted (the constructor default applies).
    if (property.positional) {
      return _DropWidget(
        A2uiDartWidgetDrop(
          widgetName: entry.name,
          fieldName: property.name,
          reason: A2uiDartCoverageReason.optionalUnsupportedPropertyType,
        ),
      );
    }
    return _OmitField(
      A2uiDartFieldOmission(
        widgetName: entry.name,
        fieldName: property.name,
        reason: A2uiDartCoverageReason.optionalUnsupportedPropertyType,
      ),
    );
  }
  return _EmitField(
    A2uiDartFieldPlan._(
      property: property,
      // Analyzer-fed List<scalar> fields remain reactive object-bound leaves.
      // Their element node preserves the type information the shared catalog
      // taxonomy does not, while leaf classification preserves literal/path
      // bindings and makes the value eligible for list write-back.
      emission: A2uiDataField(
        node,
        rich: !_isScalarListNode(node),
        constraints: constraints,
      ),
    ),
  );
}

_FieldClassification _fieldUnsupported(
  WidgetEntry entry,
  PropertyEntry property, {
  required A2uiDartCoverageReason reason,
}) {
  _rejectA2uiConstraintOmission(
    entry,
    property,
    property.required
        ? 'unsupported field drops the widget (${reason.name})'
        : 'unsupported field is omitted (${reason.name})',
  );
  if (property.required) {
    return _DropWidget(
      A2uiDartWidgetDrop(
        widgetName: entry.name,
        fieldName: property.name,
        reason: reason == A2uiDartCoverageReason.optionalUnsupportedPropertyType
            ? A2uiDartCoverageReason.requiredUnsupportedPropertyType
            : reason,
      ),
    );
  }
  return _OmitField(
    A2uiDartFieldOmission(
      widgetName: entry.name,
      fieldName: property.name,
      reason: reason,
    ),
  );
}

bool _hasExplicitA2uiConstraintMetadata(PropertyEntry property) =>
    property.validationRule != null || !property.constraints.isEmpty;

void _rejectA2uiConstraintOmission(
  WidgetEntry entry,
  PropertyEntry property,
  String disposition,
) {
  if (!_hasExplicitA2uiConstraintMetadata(property)) return;
  _a2uiConstraintFailure(
    entry,
    property,
    'explicit validation metadata cannot be projected because $disposition',
  );
}

void _rejectA2uiConstraintsForDroppedWidget(
  WidgetEntry entry,
  A2uiDartWidgetDrop drop,
) {
  for (final property in entry.properties) {
    _rejectA2uiConstraintOmission(
      entry,
      property,
      'widget is dropped (${drop.reason.name})',
    );
  }
}

A2uiChildSlot? _childSlot(
  PropertyEntry property, [
  A2uiSchemaNode? reflectedNode,
]) {
  final nullable = reflectedNode?.nullable ?? false;
  if (property.type == PropertyType.widget) {
    return A2uiChildNode(nullable: nullable);
  }
  if (property.type == PropertyType.widgetList) {
    return A2uiChildrenNode(nullable: nullable);
  }
  return null;
}

/// Maps a catalog property to its behaviour-neutral data-shape leaf node, or
/// null when the property type is not a bound data value the emitter carries.
///
/// Integer fields stay [A2uiScalarType.integer], while real-valued construction
/// kinds share [A2uiScalarType.number]. Runtime reconstruction remains driven
/// by the catalog property type (`.toInt()`, `.toDouble()`, `Duration(...)`, or
/// font-weight lookup), independently of this schema distinction.
A2uiSchemaNode? _dataNode(
  PropertyEntry property, {
  bool nullable = false,
}) {
  switch (property.type) {
    case PropertyType.boolean:
      return ScalarNode(A2uiScalarType.boolean, nullable: nullable);
    case PropertyType.integer:
      return ScalarNode(A2uiScalarType.integer, nullable: nullable);
    case PropertyType.real:
    case PropertyType.length:
    case PropertyType.duration:
    case PropertyType.fontWeight:
      return ScalarNode(A2uiScalarType.number, nullable: nullable);
    case PropertyType.string:
    case PropertyType.color:
      return ScalarNode(A2uiScalarType.string, nullable: nullable);
    case PropertyType.enumValue:
      final dartTypeName = _enumDartTypeName(property);
      // The caller guards `enumValue` with a non-null Dart type name before
      // reaching here (otherwise it is a missing-enum-type drop); the absent
      // case stays null so it routes through the unsupported path.
      if (dartTypeName == null) return null;
      return EnumNode(
        members: const [],
        dartTypeName: dartTypeName,
        libraryUri: _enumLibraryUri(property),
        nullable: nullable,
      );
    case PropertyType.stringList:
      return ListNode(
        element: const ScalarNode(A2uiScalarType.string),
        nullable: nullable,
      );
    case PropertyType.widget:
    case PropertyType.widgetList:
    case PropertyType.event:
    case PropertyType.dataReference:
    case PropertyType.gradient:
    case PropertyType.border:
    case PropertyType.shapeBorder:
    case PropertyType.boxShadowList:
    case PropertyType.shadowList:
    case PropertyType.inlineSpan:
    case PropertyType.edgeInsets:
    case PropertyType.offset:
    case PropertyType.alignment:
    case PropertyType.alignmentXY:
    case PropertyType.paint:
    case PropertyType.textDecoration:
    case PropertyType.structured:
    case PropertyType.decorationImage:
    case PropertyType.selectionOptionList:
    case PropertyType.booleanList:
    case PropertyType.locale:
    case PropertyType.fontFeatureList:
    case PropertyType.fontVariationList:
    case PropertyType.curve:
    case PropertyType.unknown:
      return null;
  }
}

/// The catalog-fed data node for [property], enriched only with analyzer-known
/// source [nullable] state. Used by production seam assembly so ordinary A2UI
/// leaves preserve nullability without widening the shared RFW catalog model.
A2uiSchemaNode? a2uiCatalogDataNodeForProperty(
  PropertyEntry property, {
  required bool nullable,
}) =>
    _dataNode(property, nullable: nullable);

/// Built-in widgets that cannot currently be emitted to a compilable A2UI
/// catalog: their Flutter constructor requires an argument the built-in catalog
/// does not expose to the emit — a required callback the catalog marks optional
/// (the event convention), or a required `style` / `decoration` represented
/// only through a decompose recipe rather than a property. Emitting them
/// produces a constructor call missing a required argument. A contained interim
/// guard scopes them out so the merged built-in catalog compiles; the proper
/// fix (the built-in supplies the argument) is tracked in the toolchain
/// follow-ups. Gated on a built-in library so a same-named customer widget is
/// unaffected.
///
/// INVARIANT: the merged built-in A2UI catalog MUST compile. This list is the
/// interim guard that keeps it compiling. Adding a built-in widget requires
/// verifying it is A2UI-constructable — if its Flutter constructor needs a
/// required argument the emit cannot supply (a required callback, or a required
/// structured value the catalog does not expose as a property), it would break
/// the merged catalog's compilation and must be added here. The structural fix
/// (the built-in catalog carries the required-ness so the emit scopes out any
/// such widget by construction, plus a permanent merged-catalog-compiles test)
/// retires this list entirely — see the catalog-capability follow-up.
const Set<String> _unconstructableBuiltIns = {
  // Required callback marked optional by the catalog's event convention.
  'FilterChip',
  'FloatingActionButton',
  'Slider',
  'CupertinoButton',
  'CupertinoButtonFilled',
  'CupertinoCheckbox',
  'CupertinoSlider',
  'CupertinoSwitch',
  // Required style/decoration not exposed as a constructable property.
  'AnimatedDefaultTextStyle',
  'DefaultTextStyle',
  'DecoratedBox',
};

A2uiDartWidgetDrop? _dropReasonForWidget(WidgetEntry entry) {
  if (WidgetLibrary.builtInByNamespace(entry.library.namespace) != null &&
      _unconstructableBuiltIns.contains(entry.name)) {
    return A2uiDartWidgetDrop(
      widgetName: entry.name,
      reason: A2uiDartCoverageReason.unconstructableBuiltIn,
    );
  }
  switch (entry.childrenSlot) {
    case ChildrenSlot.none:
      return null;
    case ChildrenSlot.single:
      final hasChild = entry.properties.any(
        (p) => p.name == 'child' && p.type == PropertyType.widget,
      );
      return hasChild
          ? null
          : A2uiDartWidgetDrop(
              widgetName: entry.name,
              reason: A2uiDartCoverageReason.unsupportedChildrenSlot,
            );
    case ChildrenSlot.list:
      final hasChildren = entry.properties.any(
        (p) => p.name == 'children' && p.type == PropertyType.widgetList,
      );
      return hasChildren
          ? null
          : A2uiDartWidgetDrop(
              widgetName: entry.name,
              reason: A2uiDartCoverageReason.unsupportedChildrenSlot,
            );
  }
}

Set<String> _decomposeConsumedNames(WidgetEntry entry) {
  final consumed = <String>{};
  for (final recipe in entry.decomposes) {
    for (final mapping in recipe.fieldMappings) {
      final property = entry.properties.firstWhereOrNull(
        (property) => property.wireId == mapping.propertyRef,
      );
      if (property != null) consumed.add(property.name);
    }
    for (final mapping in recipe.parameterMappings) {
      final property = entry.properties.firstWhereOrNull(
        (property) => property.wireId == mapping.propertyRef,
      );
      if (property != null) consumed.add(property.name);
    }
  }
  return consumed;
}

Set<String> _importUris(A2uiDartCatalogPlan plan) {
  final uris = <String>{'package:flutter/widgets.dart'};
  for (final widget in plan.widgets) {
    final widgetUri = _sourceUri(widget.entry.flutterType);
    if (widgetUri != null) uris.add(widgetUri);
    for (final field in widget.fields) {
      final shape = field.property.valueShape;
      if (shape is EnumShape) uris.add(shape.enumRef.libraryUri);
      // A rich field's customer data classes/enums can live in libraries the
      // catalog never names (the data model is separate from the widget). Every
      // one must be imported, or the generated helper references a bare,
      // unimported type.
      final emission = field.emission;
      if (emission is A2uiDataField && emission.rich) {
        _collectRichNodeLibraries(emission.node, uris);
      }
    }
  }
  return SplayTreeSet<String>.of(uris);
}

/// Collects every library URI a rich data [node] references (the constructor
/// classes and enums, recursively through lists / maps / nested objects), into
/// [into] — so the emitter imports each before assigning prefixes.
void _collectRichNodeLibraries(A2uiSchemaNode node, Set<String> into) {
  switch (node) {
    case ScalarNode() || RefNode() || UnionNode():
      break;
    case EnumNode(:final libraryUri):
      if (libraryUri != null) into.add(libraryUri);
    case ListNode(:final element):
      _collectRichNodeLibraries(element, into);
    case MapNode(:final valueType):
      _collectRichNodeLibraries(valueType, into);
    case ObjectNode(:final construction, :final fields):
      if (construction is A2uiClassConstruction &&
          construction.libraryUri != null) {
        into.add(construction.libraryUri!);
      }
      for (final field in fields.values) {
        _collectRichNodeLibraries(field, into);
      }
  }
}

String _ctorExpressionFor(WidgetEntry entry, Map<String, String> prefixes) {
  final hashIndex = entry.flutterType.indexOf('#');
  if (hashIndex < 0 || hashIndex == entry.flutterType.length - 1) {
    throw StateError(
      "Catalog entry '${entry.name}' has malformed flutterType "
      "'${entry.flutterType}'.",
    );
  }
  final typeName = entry.flutterType.substring(hashIndex + 1);
  return prefixedType(typeName, _sourceUri(entry.flutterType), prefixes);
}

String? _sourceUri(String sourceType) {
  final hash = sourceType.indexOf('#');
  if (hash <= 0) return null;
  return sourceType.substring(0, hash);
}

String? _enumDartTypeName(PropertyEntry property) {
  final shape = property.valueShape;
  final enumRef = shape is EnumShape ? shape.enumRef : null;
  return enumRef?.symbolName ?? property.enumType;
}

String? _enumLibraryUri(PropertyEntry property) {
  final shape = property.valueShape;
  return shape is EnumShape ? shape.enumRef.libraryUri : null;
}

String _identifierFor(String name) {
  final identifier = name.replaceAll(RegExp(r'[^A-Za-z0-9_$]'), '_');
  if (identifier.isEmpty) return 'value';
  if (RegExp(r'^[A-Za-z_$]').hasMatch(identifier)) return identifier;
  return 'value_$identifier';
}

/// The fixed generated identifiers (the data map, the widget-builder parameter,
/// the `Bound*` builder parameter) a customer property's leaf binding could
/// shadow.
const _reservedBuilderIdentifiers = {'data', 'context', 'itemContext'};

/// Whether [propertyName]'s generated identifier collides with the reserved
/// scaffolding namespace — the fixed [_reservedBuilderIdentifiers] OR any local
/// in the generated `_restageA2ui` / `restageA2ui` namespaces (the rich
/// reconstruction and controlled-value locals). A customer leaf bound to such
/// an identifier would shadow them, so it fails closed by construction.
bool _isReservedBuilderIdentifier(String propertyName) {
  final identifier = _identifierFor(propertyName);
  return _reservedBuilderIdentifiers.contains(identifier) ||
      identifier.startsWith('_restageA2ui') ||
      identifier.startsWith('restageA2ui');
}

/// Whether [propertyName]'s generated identifier collides with the generated
/// builder scaffolding namespace (`data` / `context` / `itemContext`, or the
/// reserved `_restageA2ui` / `restageA2ui` local prefixes). Exposed so
/// build-time coverage diagnostics can name the actual cause — a reserved
/// property name — rather than reporting a generic unsupported property type.
bool isReservedA2uiBuilderIdentifier(String propertyName) =>
    _isReservedBuilderIdentifier(propertyName);

/// The reserved-prefixed local a rich field's reconstructed value is bound to,
/// so a customer property named `data`/`context`/`itemContext` can never
/// collide with the generated scaffolding.
String _richLocalName(PropertyEntry property) =>
    '_restageA2uiArg_${_identifierFor(property.name)}';

String _dartStringLiteral(String value) {
  // Backslash MUST be escaped first — every other replacement below inserts a
  // literal backslash into the output, and re-running this pass over that
  // output would double-escape it.
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}

/// Runtime support emitted only when the catalog contains a controlled leaf
/// value. It deliberately owns source identity, semantic identity,
/// subscription invalidation, and local override provenance in one widget so
/// those concerns cannot drift across generated constructor expressions.
const String _controlledValueSupportDefinition = '''
enum _RestageA2uiSourceKind { literal, path, call, localOverride }

typedef _RestageA2uiControlledBuilder = Widget Function(
  BuildContext context,
  Object? rawValue,
  bool sourcePresent,
  _RestageA2uiSourceKind sourceKind,
  ValueChanged<Object?> write,
);

final class _RestageA2uiControlledValue extends StatefulWidget {
  const _RestageA2uiControlledValue({
    required this.dataContext,
    required this.source,
    required this.sourcePresent,
    required this.surfaceId,
    required this.catalogId,
    required this.componentId,
    required this.field,
    required this.selfPath,
    required this.reportError,
    required this.builder,
  });

  final DataContext dataContext;
  final Object? source;
  final bool sourcePresent;
  final String surfaceId;
  final String? catalogId;
  final String componentId;
  final String field;
  final String selfPath;
  final void Function(Object error, StackTrace? stack) reportError;
  final _RestageA2uiControlledBuilder builder;

  @override
  State<_RestageA2uiControlledValue> createState() =>
      _RestageA2uiControlledValueState();
}

final class _RestageA2uiControlledValueState
    extends State<_RestageA2uiControlledValue> {
  StreamSubscription<Object?>? _subscription;
  void Function(Object error, StackTrace? stack)? _subscriptionReportError;
  var _epoch = 0;
  late _RestageA2uiSourceDescriptor _descriptor;
  late _RestageA2uiSemanticIdentity _semanticIdentity;
  Object? _sourceValue;
  var _sourcePresent = false;
  var _hasOverride = false;
  Object? _overrideValue;

  @override
  void initState() {
    super.initState();
    _adoptBinding(
      _RestageA2uiSourceDescriptor.from(widget.source),
      _RestageA2uiSemanticIdentity.from(widget),
    );
    _subscribe();
  }

  @override
  void didUpdateWidget(_RestageA2uiControlledValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextDescriptor =
        _RestageA2uiSourceDescriptor.from(widget.source);
    final nextSemantic = _RestageA2uiSemanticIdentity.from(widget);
    final bindingChanged = !_descriptor.sameBinding(nextDescriptor) ||
        _semanticIdentity != nextSemantic ||
        oldWidget.componentId != widget.componentId ||
        oldWidget.field != widget.field ||
        oldWidget.selfPath != widget.selfPath;
    if (bindingChanged) {
      _invalidateSubscription();
      _adoptBinding(nextDescriptor, nextSemantic);
      _subscribe();
      return;
    }

    final literalPayloadChanged =
        nextDescriptor.kind == _RestageA2uiSourceKind.literal &&
            (!_restageA2uiLiteralEqual(oldWidget.source, widget.source) ||
                oldWidget.sourcePresent != widget.sourcePresent);
    if (literalPayloadChanged && !_hasOverride) {
      _invalidateSubscription();
      _sourceValue = widget.source;
      _sourcePresent = widget.sourcePresent;
      _subscribe();
    }
  }

  void _adoptBinding(
    _RestageA2uiSourceDescriptor descriptor,
    _RestageA2uiSemanticIdentity semanticIdentity,
  ) {
    _descriptor = descriptor;
    _semanticIdentity = semanticIdentity;
    _sourceValue = switch (descriptor.kind) {
      _RestageA2uiSourceKind.literal => widget.source,
      _RestageA2uiSourceKind.path =>
        widget.dataContext.getValue<Object?>(DataPath(descriptor.path!)),
      _RestageA2uiSourceKind.call ||
      _RestageA2uiSourceKind.localOverride =>
        null,
    };
    _sourcePresent = widget.sourcePresent;
    _hasOverride = false;
    _overrideValue = null;
  }

  void _subscribe() {
    final subscribedEpoch = _epoch;
    final literalPresence = widget.sourcePresent;
    final reportError = widget.reportError;
    _subscriptionReportError = reportError;
    _subscription = widget.dataContext.resolve(widget.source).listen(
      (value) {
        if (!mounted || subscribedEpoch != _epoch || _hasOverride) return;
        setState(() {
          _sourceValue = value;
          _sourcePresent =
              _descriptor.kind == _RestageA2uiSourceKind.literal
                  ? literalPresence
                  : true;
        });
      },
      onError: (Object error, StackTrace stack) {
        if (!mounted || subscribedEpoch != _epoch) return;
        reportError(error, stack);
      },
    );
  }

  void _invalidateSubscription() {
    final previous = _subscription;
    final reportError = _subscriptionReportError ?? widget.reportError;
    _subscription = null;
    _subscriptionReportError = null;
    _epoch += 1;
    if (previous == null) return;
    Future<void> cancellation;
    try {
      cancellation = previous.cancel();
    } catch (error, stack) {
      reportError(error, stack);
      return;
    }
    unawaited(
      cancellation.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          reportError(error, stack);
        },
      ),
    );
  }

  void _write(Object? next) {
    if (!mounted) return;
    if (_descriptor.kind == _RestageA2uiSourceKind.path) {
      widget.dataContext.update(DataPath(_descriptor.path!), next);
      return;
    }

    _invalidateSubscription();
    _hasOverride = true;
    _overrideValue = next;
    widget.dataContext.update(DataPath(widget.selfPath), next);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final overridden = _hasOverride;
    return widget.builder(
      context,
      overridden ? _overrideValue : _sourceValue,
      overridden ? true : _sourcePresent,
      overridden
          ? _RestageA2uiSourceKind.localOverride
          : _descriptor.kind,
      _write,
    );
  }

  @override
  void dispose() {
    _invalidateSubscription();
    super.dispose();
  }
}

final class _RestageA2uiSourceDescriptor {
  const _RestageA2uiSourceDescriptor._(
    this.kind, {
    this.path,
    this.callName,
    this.callArgs,
  });

  factory _RestageA2uiSourceDescriptor.from(Object? source) {
    if (source is Map && source.containsKey('path')) {
      final path = source['path'];
      if (path is! String) {
        throw ArgumentError.value(
          path,
          'source.path',
          'A controlled A2UI path must be a String.',
        );
      }
      return _RestageA2uiSourceDescriptor._(
        _RestageA2uiSourceKind.path,
        path: path,
      );
    }
    if (source is Map && source.containsKey('call')) {
      final callName = source['call'];
      if (callName != null && callName is! String) {
        throw ArgumentError.value(
          callName,
          'source.call',
          'A controlled A2UI call name must be a String or null.',
        );
      }
      final args = source['args'];
      return _RestageA2uiSourceDescriptor._(
        _RestageA2uiSourceKind.call,
        callName: callName as String?,
        callArgs: args is Map ? args : const <String, Object?>{},
      );
    }
    return const _RestageA2uiSourceDescriptor._(
      _RestageA2uiSourceKind.literal,
    );
  }

  final _RestageA2uiSourceKind kind;
  final String? path;
  final String? callName;
  final Map<Object?, Object?>? callArgs;

  bool sameBinding(_RestageA2uiSourceDescriptor other) {
    if (kind != other.kind) return false;
    return switch (kind) {
      _RestageA2uiSourceKind.literal => true,
      _RestageA2uiSourceKind.path => path == other.path,
      _RestageA2uiSourceKind.call =>
        callName == other.callName &&
            _restageA2uiCallIdentityEqual(callArgs, other.callArgs),
      _RestageA2uiSourceKind.localOverride => false,
    };
  }
}

final class _RestageA2uiSemanticIdentity {
  const _RestageA2uiSemanticIdentity(
    this.surfaceId,
    this.catalogId,
    this.dataModel,
    this.contextPath,
  );

  factory _RestageA2uiSemanticIdentity.from(
    _RestageA2uiControlledValue widget,
  ) =>
      _RestageA2uiSemanticIdentity(
        widget.surfaceId,
        widget.catalogId,
        widget.dataContext.dataModel,
        widget.dataContext.path,
      );

  final String surfaceId;
  final String? catalogId;
  final Object dataModel;
  final DataPath contextPath;

  @override
  bool operator ==(Object other) =>
      other is _RestageA2uiSemanticIdentity &&
      surfaceId == other.surfaceId &&
      catalogId == other.catalogId &&
      identical(dataModel, other.dataModel) &&
      contextPath == other.contextPath;

  @override
  int get hashCode => Object.hash(
        surfaceId,
        catalogId,
        identityHashCode(dataModel),
        contextPath,
      );
}

bool _restageA2uiCallIdentityEqual(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is num && right is num) return left == right;
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (!_restageA2uiCallIdentityEqual(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_restageA2uiCallIdentityEqual(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

bool _restageA2uiLiteralEqual(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left == null || right == null) return false;
  if (left is num && right is num) {
    return left.runtimeType == right.runtimeType && left == right;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (!_restageA2uiLiteralEqual(left[index], right[index])) return false;
    }
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_restageA2uiLiteralEqual(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return left.runtimeType == right.runtimeType && left == right;
}

num? _restageA2uiNumber(
  Object? rawValue,
  _RestageA2uiSourceKind sourceKind,
) {
  if (rawValue is num) return rawValue;
  if ((sourceKind == _RestageA2uiSourceKind.path ||
          sourceKind == _RestageA2uiSourceKind.call) &&
      rawValue is String) {
    return num.tryParse(rawValue);
  }
  return null;
}

bool? _restageA2uiBool(
  Object? rawValue,
  _RestageA2uiSourceKind sourceKind,
) {
  if (rawValue is bool) return rawValue;
  if (sourceKind == _RestageA2uiSourceKind.path) {
    if (rawValue is String) {
      final normalized = rawValue.toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    if (rawValue is num) return rawValue != 0;
  }
  if (sourceKind == _RestageA2uiSourceKind.call) {
    return rawValue != null;
  }
  return null;
}

String? _restageA2uiString(Object? rawValue) => rawValue?.toString();

String? _restageA2uiEnumName(Object? rawValue) =>
    rawValue is Enum ? rawValue.name : rawValue?.toString();
''';

sealed class _FieldClassification {
  const _FieldClassification();
}

final class _EmitField extends _FieldClassification {
  const _EmitField(this.plan);

  final A2uiDartFieldPlan plan;
}

final class _OmitField extends _FieldClassification {
  const _OmitField(this.omission);

  final A2uiDartFieldOmission omission;
}

final class _DropWidget extends _FieldClassification {
  const _DropWidget(this.drop);

  final A2uiDartWidgetDrop drop;
}
