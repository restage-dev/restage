import 'dart:collection';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/a2ui/a2ui_data_builder.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
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
  });

  /// Source catalog entry.
  final WidgetEntry entry;

  /// Fields included in schema and construction.
  final List<A2uiDartFieldPlan> fields;
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

/// A bound data field, described by its data-shape [node].
@immutable
final class A2uiDataField extends A2uiFieldEmission {
  /// Creates a data-field emission over [node].
  ///
  /// [rich] is true for an analyzer-fed customer data shape (reconstructed
  /// through the value-builder, bound via `BoundObject`); false for the
  /// catalog-fed leaf binding. Catalog classification always yields false, so
  /// the built-in catalogs are byte-neutral.
  const A2uiDataField(this.node, {this.rich = false});

  /// The data-shape node projected to a schema and a typed value binding.
  final A2uiSchemaNode node;

  /// Whether this field's value is reconstructed via the value-builder (a rich
  /// customer data shape) rather than the catalog-fed leaf binding.
  final bool rich;

  @override
  bool operator ==(Object other) =>
      other is A2uiDataField && other.node == node && other.rich == rich;

  @override
  int get hashCode => Object.hash(node, rich);
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

/// A map from `(widgetName, propertyName)` to the analyzer-fed rich data shape
/// for that property — the reflector's output, threaded into the emitter
/// alongside the serialized catalog (which has no analyzer access). A property
/// present here is emitted as a rich data field; everything else takes the
/// catalog-fed leaf path.
typedef A2uiRichShapes = Map<(String, String), A2uiSchemaNode>;

/// Classifies [catalog] for A2UI Dart emission.
A2uiDartCatalogPlan classifyA2uiCatalogDart(
  Catalog catalog, {
  NativeCatalogIndex? nativeIndex,
  A2uiRichShapes? richShapes,
}) {
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
      dropped.add(drop);
      continue;
    }

    final consumed = _decomposeConsumedNames(entry);
    final fields = <A2uiDartFieldPlan>[];
    A2uiDartWidgetDrop? lateDrop;
    for (final property in entry.properties) {
      if (consumed.contains(property.name)) {
        omitted.add(
          A2uiDartFieldOmission(
            widgetName: entry.name,
            fieldName: property.name,
            reason: A2uiDartCoverageReason.nativeDecomposeUnsupported,
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
          fields.add(plan);
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
      dropped.add(lateDrop);
      continue;
    }
    widgets.add(A2uiDartWidgetPlan._(entry: entry, fields: fields));
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

/// Emits Dart source defining genui `CatalogItem`s for [catalog].
String emitA2uiCatalogDart(
  Catalog catalog, {
  NativeCatalogIndex? nativeIndex,
  A2uiRichShapes? richShapes,
}) {
  final plan = classifyA2uiCatalogDart(
    catalog,
    nativeIndex: nativeIndex,
    richShapes: richShapes,
  );
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
  _assertPrefixableSpellings(plan, dataBuilder);
  final buf = StringBuffer();
  writeGeneratedHeader(buf);
  buf.writeln();

  for (final uri in importUris) {
    final prefix = prefixes[uri];
    buf.writeln(
      prefix == null ? "import '$uri';" : "import '$uri' as $prefix;",
    );
  }
  buf
    ..writeln("import 'package:genui/genui.dart';")
    ..writeln("import 'package:json_schema_builder/json_schema_builder.dart';")
    ..writeln()
    ..writeln('List<CatalogItem> buildRestageCatalogItems() {')
    ..writeln('  return <CatalogItem>[');

  for (final widget in plan.widgets) {
    _writeCatalogItem(buf, widget, dataBuilder, prefixes);
  }

  buf
    ..writeln('  ];')
    ..writeln('}')
    ..writeln()
    ..writeln(
      'Widget? _restageA2uiBuildChild(CatalogItemContext itemContext, '
      'Object? childId) {',
    )
    ..writeln('  if (childId is! String || childId.isEmpty) return null;')
    // genui 0.9.2: CatalogItemContext.buildChild is a typed callback field
    // `Widget Function(String id, [DataContext? dataContext])` — render a
    // child by id with a direct typed call (no dynamic bridge).
    ..writeln('  return itemContext.buildChild(childId);')
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

  return formatGeneratedDart(buf.toString()).trimRight();
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
  Map<String, String> prefixes,
) {
  final entry = widget.entry;
  // Rich nested objects/maps/records/lists-of-objects are reconstructed
  // DIRECTLY from the widget data as a builder prelude (no BoundObject — its
  // `{path}`/`{call}` binding-sentinel patterns would misread a literal value
  // whose own field/key is named `path`/`call`). Top-level scalars/enums/
  // leaf-lists keep their reactive `Bound*` wrappers around the constructor.
  final prelude = _richPreludeStatements(widget, dataBuilder);
  final returnExpression = _widgetReturnExpression(widget, prefixes);
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
    ..writeln('      },')
    ..writeln('    ),');
}

String _schemaExpression(A2uiDartWidgetPlan widget) =>
    a2uiWidgetDataSchemaExpression([
      for (final field in widget.fields)
        (
          name: field.property.name,
          required: field.property.required,
          emission: field.emission,
        ),
    ]);

/// One field in a widget's data schema: its property name, whether it is
/// required (present), and how it is emitted.
typedef A2uiWidgetField = ({
  String name,
  bool required,
  A2uiFieldEmission emission,
});

/// Projects a widget's whole data schema from its [fields].
///
/// This is the SOLE path for a widget's `dataSchema`: the `$defs`/`$ref`
/// two-pass runs ONCE at the document root, so a recursive definition is
/// hoisted to the top — never nested inside a per-property schema, where a
/// `#/$defs/…` pointer could not resolve. Cross-field reuse of one recursive
/// type yields a single shared `$def` referenced by each field.
///
/// With no recursive field this is the bare widget `S.object` (byte-neutral
/// with the catalog-fed path, which never mints a [RefNode]).
String a2uiWidgetDataSchemaExpression(List<A2uiWidgetField> fields) {
  final refTargets = <String>{};
  for (final field in fields) {
    final emission = field.emission;
    if (emission is A2uiDataField) {
      refTargets.addAll(_collectRefTargets(emission.node));
    }
  }
  if (refTargets.isEmpty) {
    return _widgetObjectSchema(fields);
  }

  // A recursive type is present somewhere: hoist the whole widget body into
  // `$defs` under a synthetic root key and emit a root `$ref` (the widget
  // object always exists, so the root itself is never nullable).
  final defIds = <String>{_syntheticRootDefId, ...refTargets};
  final safeKeys = _assignSafeDefKeys(defIds);
  final ctx = _DefsContext(refTargets: refTargets, safeKeys: safeKeys);

  final nodeForDef = <String, A2uiSchemaNode>{
    for (final id in refTargets) id: _findFieldNodeWithDefId(fields, id),
  };

  final orderedIds = defIds.toList()
    ..sort((a, b) => safeKeys[a]!.compareTo(safeKeys[b]!));
  final defEntries = <String>[];
  for (final id in orderedIds) {
    final schema = id == _syntheticRootDefId
        ? _widgetObjectSchema(fields, ctx: ctx)
        : _projectNode(nodeForDef[id]!, ctx, atDefRoot: true);
    defEntries.add('${_dartStringLiteral(safeKeys[id]!)}: $schema');
  }
  return 'S.combined(\$ref: ${_refLiteral(safeKeys[_syntheticRootDefId]!)}, '
      '\$defs: {${defEntries.join(', ')}})';
}

/// Finds the object/union that defines [target] across all data [fields].
A2uiSchemaNode _findFieldNodeWithDefId(
  List<A2uiWidgetField> fields,
  String target,
) {
  for (final field in fields) {
    final emission = field.emission;
    if (emission is A2uiDataField) {
      final defined = _findNodeWithDefId(emission.node, target);
      if (defined != null) return defined;
    }
  }
  throw StateError(
    'A2UI projection: a reference to "$target" has no defining object/union '
    'across the widget fields.',
  );
}

/// The widget `S.object` body for [fields]. With a [ctx] each data field is
/// projected cycle-aware (recursive occurrences become `$ref`s, the `$defs`
/// living at the document root); without one each is the bare projection.
String _widgetObjectSchema(List<A2uiWidgetField> fields, {_DefsContext? ctx}) {
  final props = <String>[];
  for (final field in fields) {
    final schema = _fieldSchema(field.emission, ctx);
    props.add('${_dartStringLiteral(field.name)}: $schema');
  }
  final required = [
    for (final field in fields)
      if (field.required) _dartStringLiteral(field.name),
  ];
  return 'S.object(properties: {${props.join(', ')}}, '
      'required: <String>[${required.join(', ')}],)';
}

/// The schema for one field's [emission]: a bound data value (cycle-aware via
/// [ctx] when present) or a host-built child slot (a fixed leaf schema).
String _fieldSchema(A2uiFieldEmission emission, _DefsContext? ctx) {
  switch (emission) {
    case A2uiDataField(:final node):
      return ctx == null
          ? _schemaForNode(node)
          : _projectNode(node, ctx, atDefRoot: false);
    case A2uiChildField(:final slot):
      switch (slot) {
        case A2uiChildNode():
          return 'S.string()';
        case A2uiChildrenNode():
          return 'S.list(items: S.string())';
      }
  }
}

/// Projects [node] to its bare (non-`$defs`) schema, applying nullability at
/// the occurrence as `anyOf[<non-null>, S.nil()]`.
String _schemaForNode(A2uiSchemaNode node) =>
    _wrapNullable(_schemaForNodeBase(node), node.nullable);

/// Wraps [base] to also accept JSON `null` when [nullable].
///
/// `defId` intentionally ignores outer nullability, so a `$defs` DEFINITION
/// stays non-null and the wrap is applied only at each OCCURRENCE/reference.
String _wrapNullable(String base, bool nullable) =>
    nullable ? 'S.combined(anyOf: [$base, S.nil()])' : base;

/// The NON-null schema for [node] (the caller applies nullability). Children
/// recurse through [_schemaForNode] so their own nullability is applied.
String _schemaForNodeBase(A2uiSchemaNode node) {
  switch (node) {
    case ScalarNode(:final type):
      switch (type) {
        case A2uiScalarType.boolean:
          return 'S.boolean()';
        case A2uiScalarType.number:
          return 'S.number()';
        case A2uiScalarType.integer:
          return 'S.integer()';
        case A2uiScalarType.string:
          return 'S.string()';
      }
    case EnumNode(:final members):
      // The catalog-fed path carries no member set → a plain string (byte-
      // neutral); the analyzer-fed path enriches it with the resolved members.
      if (members.isEmpty) return 'S.string()';
      final values = members.map(_dartStringLiteral).join(', ');
      return 'S.string(enumValues: <Object?>[$values])';
    case ListNode(:final element):
      return 'S.list(items: ${_schemaForNode(element)})';
    case ObjectNode(:final fields, :final required):
      return _objectSchema(fields, required);
    case MapNode(:final valueType):
      return 'S.object(additionalProperties: ${_schemaForNode(valueType)})';
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
/// Genuine cycles (a [RefNode] referencing an enclosing object's `defId`) are
/// emitted via a `$defs`/`$ref` two-pass: every recursive definition is hoisted
/// once into `$defs` and referenced by `$ref`, while non-recursive reuse is
/// inlined. A schema with no cycles projects exactly as the bare node tree
/// (byte-neutral — the catalog-fed path never produces a [RefNode]).
///
/// This projects ONE standalone node. For a widget's full `dataSchema` (whose
/// `$defs` must hoist to the document root across all fields) use
/// [a2uiWidgetDataSchemaExpression] — do not embed this result as a property
/// value, or a nested `$defs` could not resolve.
String a2uiDataSchemaExpression(A2uiSchemaNode node) {
  final refTargets = _collectRefTargets(node);
  if (refTargets.isEmpty) {
    // No genuine cycle → the bare projection (byte-neutral with the catalog
    // path, which never mints a RefNode).
    return _schemaForNode(node);
  }
  return _schemaWithDefs(node, refTargets);
}

/// A synthetic root `$defs` id for a recursion-bearing root that has no `defId`
/// of its own (a record root). Never collides with a `<libraryUri>#<symbol>`
/// canonical id.
const String _syntheticRootDefId = '__a2ui_root__';

/// Projects [root] with a `$defs`/`$ref` two-pass given the genuine cycle
/// targets [refTargets].
///
/// `S.combined` carries `$defs`/`$ref` but not `properties`, so a schema that
/// needs `$defs` hoists its whole body into `$defs` (the root under its own
/// `defId`, or a synthetic key) and emits a root `$ref` into it. Every
/// recursive definition is projected once; non-recursive reuse stays inline.
String _schemaWithDefs(A2uiSchemaNode root, Set<String> refTargets) {
  final rootId = _defIdOf(root) ?? _syntheticRootDefId;
  final defIds = <String>{rootId, ...refTargets};
  final safeKeys = _assignSafeDefKeys(defIds);
  final ctx = _DefsContext(refTargets: refTargets, safeKeys: safeKeys);

  // The node emitted under each `$defs` key: the root key maps to `root`; a
  // genuine cycle target maps to the object/union that defines it.
  final nodeForDef = <String, A2uiSchemaNode>{rootId: root};
  for (final id in refTargets) {
    final defined = _findNodeWithDefId(root, id);
    if (defined == null) {
      throw StateError(
        'A2UI projection: a reference to "$id" has no defining object/union '
        'in the node tree.',
      );
    }
    nodeForDef[id] = defined;
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
  if (root.nullable) {
    // The root OCCURRENCE carries the root's nullability (the `$def` stays
    // non-null); `$defs` remain at the document root alongside the `anyOf`.
    return 'S.combined(anyOf: [S.combined(\$ref: $rootPtr), S.nil()], '
        '$defsBody)';
  }
  return 'S.combined(\$ref: $rootPtr, $defsBody)';
}

/// Context for the cycle-aware projection: which `defId`s are genuine cycle
/// targets, and the collision-safe `$defs` key assigned to each.
@immutable
final class _DefsContext {
  const _DefsContext({required this.refTargets, required this.safeKeys});

  /// Canonical ids referenced by a [RefNode] — the genuine recursive types.
  final Set<String> refTargets;

  /// Canonical id (including the root key) → its `$defs` key.
  final Map<String, String> safeKeys;
}

/// Projects [node] in the cycle-aware context.
///
/// A recursive object/union occurrence (a `defId` in [_DefsContext.refTargets])
/// emits a `$ref`, except at its own definition root ([atDefRoot]), where it is
/// projected inline so the definition is materialized once. Non-recursive
/// shapes project inline exactly as the bare projection.
String _projectNode(
  A2uiSchemaNode node,
  _DefsContext ctx, {
  required bool atDefRoot,
}) {
  final base = _projectNodeBase(node, ctx, atDefRoot: atDefRoot);
  // The def root is non-null (canonical `defId` ignores outer nullability);
  // nullability applies only at occurrences.
  return _wrapNullable(base, !atDefRoot && node.nullable);
}

/// The NON-null cycle-aware schema for [node] (the caller applies occurrence
/// nullability). A recursive object occurrence becomes a `$ref` except at its
/// own definition root ([atDefRoot]), where it is materialized inline once.
String _projectNodeBase(
  A2uiSchemaNode node,
  _DefsContext ctx, {
  required bool atDefRoot,
}) {
  switch (node) {
    case ScalarNode() || EnumNode():
      return _schemaForNodeBase(node);
    case ListNode(:final element):
      return 'S.list(items: ${_projectNode(element, ctx, atDefRoot: false)})';
    case MapNode(:final valueType):
      return 'S.object(additionalProperties: '
          '${_projectNode(valueType, ctx, atDefRoot: false)})';
    case ObjectNode(:final fields, :final required, :final defId):
      if (!atDefRoot && defId != null && ctx.refTargets.contains(defId)) {
        return _refExpression(ctx, defId);
      }
      final props = <String>[];
      for (final entry in fields.entries) {
        final value = _projectNode(entry.value, ctx, atDefRoot: false);
        props.add('${_dartStringLiteral(entry.key)}: $value');
      }
      final req = [for (final name in required) _dartStringLiteral(name)];
      return 'S.object(properties: {${props.join(', ')}}, '
          'required: <String>[${req.join(', ')}],)';
    case RefNode(:final defId):
      return _refExpression(ctx, defId);
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

/// Collects every canonical id referenced by a [RefNode] in the node tree —
/// the genuine cycle targets. The tree is finite (a cycle is already broken by
/// a [RefNode] leaf), so the walk terminates.
Set<String> _collectRefTargets(A2uiSchemaNode root) {
  final targets = <String>{};
  void visit(A2uiSchemaNode node) {
    switch (node) {
      case ScalarNode() || EnumNode():
        break;
      case ListNode(:final element):
        visit(element);
      case MapNode(:final valueType):
        visit(valueType);
      case ObjectNode(:final fields):
        fields.values.forEach(visit);
      case UnionNode(:final variants):
        variants.forEach(visit);
      case RefNode(:final defId):
        targets.add(defId);
    }
  }

  visit(root);
  return targets;
}

/// Finds the object/union node that defines [target] (the first occurrence in a
/// pre-order walk; a [RefNode] is a reference, not a definition, so it is
/// skipped). Returns null when no node defines it.
A2uiSchemaNode? _findNodeWithDefId(A2uiSchemaNode root, String target) {
  A2uiSchemaNode? found;
  void visit(A2uiSchemaNode node) {
    if (found != null) return;
    if (_defIdOf(node) == target) {
      found = node;
      return;
    }
    switch (node) {
      case ScalarNode() || EnumNode() || RefNode():
        break;
      case ListNode(:final element):
        visit(element);
      case MapNode(:final valueType):
        visit(valueType);
      case ObjectNode(:final fields):
        fields.values.forEach(visit);
      case UnionNode(:final variants):
        variants.forEach(visit);
    }
  }

  visit(root);
  return found;
}

/// Assigns a collision-safe, readable `$defs` key to each canonical id.
///
/// Keys are derived from the symbol name and disambiguated in sorted-canonical-
/// id order (so the assignment is deterministic and two same-named types from
/// different libraries get distinct keys: `Node`, `Node_2`).
Map<String, String> _assignSafeDefKeys(Set<String> defIds) {
  final keys = <String, String>{};
  final used = <String>{};
  for (final id in defIds.toList()..sort()) {
    final base = _defKeyBase(id);
    var key = base;
    var n = 2;
    while (used.contains(key)) {
      key = '${base}_$n';
      n++;
    }
    used.add(key);
    keys[id] = key;
  }
  return keys;
}

/// A readable, JSON-pointer-safe base key from a canonical id
/// `<libraryUri>#<symbol>[<typeArgs>]`: the symbol name with any generic suffix
/// stripped, sanitized to `[A-Za-z0-9_]`.
String _defKeyBase(String canonicalId) {
  final hash = canonicalId.indexOf('#');
  var symbol = hash < 0 ? canonicalId : canonicalId.substring(hash + 1);
  final lt = symbol.indexOf('<');
  if (lt >= 0) symbol = symbol.substring(0, lt);
  final sanitized = symbol.replaceAll(RegExp('[^A-Za-z0-9_]'), '_');
  return sanitized.isEmpty ? 'def' : sanitized;
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
    'A2UI emission for ${node.runtimeType} is not implemented in this '
    'milestone; the catalog-fed path never produces it.';

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

/// The widget builder's return expression: the constructor wrapped in the
/// reactive `Bound*` layers for the LEAF (catalog-fed scalar/enum/leaf-list)
/// fields. Rich fields are not wrapped here — they are reconstructed in the
/// prelude and referenced by the constructor as locals.
String _widgetReturnExpression(
  A2uiDartWidgetPlan widget,
  Map<String, String> prefixes,
) {
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
    expression = _boundWrapperExpression(field, expression);
  }
  return expression;
}

String _boundWrapperExpression(A2uiDartFieldPlan field, String child) {
  final property = field.property;
  final emission = field.emission;
  if (emission is! A2uiDataField) {
    throw StateError('Children are not Bound fields.');
  }
  final bound = switch (emission.node) {
    ScalarNode(:final type) => switch (type) {
        A2uiScalarType.boolean => 'BoundBool',
        A2uiScalarType.number || A2uiScalarType.integer => 'BoundNumber',
        A2uiScalarType.string => 'BoundString',
      },
    EnumNode() => 'BoundString',
    ListNode() => 'BoundList',
    ObjectNode() ||
    MapNode() ||
    UnionNode() ||
    RefNode() =>
      throw StateError(_richNodeUnsupportedMessage(emission.node)),
  };
  final variable = _identifierFor(property.name);
  return '''
$bound(
  dataContext: itemContext.dataContext,
  value: data[${_dartStringLiteral(property.name)}],
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
    final arg = _argumentExpression(field, prefixes);
    if (property.positional) {
      positional.add(arg);
    } else {
      named.add('${property.name}: $arg');
    }
  }

  final args = [...positional, ...named];
  if (args.isEmpty) return '$ctor()';
  return '$ctor(${args.map((arg) => '$arg,').join()})';
}

String _argumentExpression(
  A2uiDartFieldPlan field,
  Map<String, String> prefixes,
) {
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
      return _dataArgumentExpression(node, property, variable, prefixes);
    case A2uiChildField(:final slot):
      switch (slot) {
        case A2uiChildNode():
          final child = '_restageA2uiBuildChild(itemContext, '
              'data[${_dartStringLiteral(property.name)}])';
          return property.required ? '$child!' : child;
        case A2uiChildrenNode():
          return '_restageA2uiBuildChildren(itemContext, '
              'data[${_dartStringLiteral(property.name)}])';
      }
  }
}

String _dataArgumentExpression(
  A2uiSchemaNode node,
  PropertyEntry property,
  String variable,
  Map<String, String> prefixes,
) {
  switch (node) {
    case ScalarNode(:final type):
      switch (type) {
        case A2uiScalarType.boolean:
          return '$variable ?? ${_defaultFor(property, prefixes)}';
        case A2uiScalarType.number:
        case A2uiScalarType.integer:
          return _numberArgumentExpression(property, variable, prefixes);
        case A2uiScalarType.string:
          if (property.type == PropertyType.color) {
            return '_restageA2uiColor($variable) ?? '
                '${_defaultFor(property, prefixes)}';
          }
          return '$variable ?? ${_defaultFor(property, prefixes)}';
      }
    case EnumNode(:final dartTypeName):
      final fallback = _defaultFor(property, prefixes);
      final enumType =
          prefixedType(dartTypeName, _enumLibraryUri(property), prefixes);
      final lookup = '$enumType.values.asNameMap()[$variable]';
      // Fail closed: an unknown/absent member resolves to the catalog default
      // — a required enum with no declared default resolves to the first
      // member (via _defaultFor), never a throw; an optional enum keeps the
      // nullable lookup so the widget's own default applies.
      return fallback == 'null' ? lookup : '$lookup ?? $fallback';
    case ListNode(:final element):
      // The catalog-fed path only produces String-element lists; the schema
      // side advertises the element type, so construct loud-or-nothing rather
      // than silently coercing a non-String list through `whereType<String>`.
      if (element is! ScalarNode || element.type != A2uiScalarType.string) {
        throw StateError(
          'A2UI list construction supports only String elements in this '
          'milestone; got ${element.runtimeType}. The catalog-fed path never '
          'produces a non-String list.',
        );
      }
      return [
        '($variable ?? const <Object?>[]).whereType<String>().toList(',
        'growable: false)',
      ].join();
    case ObjectNode():
    case MapNode():
    case UnionNode():
    case RefNode():
      throw StateError(_richNodeUnsupportedMessage(node));
  }
}

String _numberArgumentExpression(
  PropertyEntry property,
  String variable,
  Map<String, String> prefixes,
) {
  final fallback = _defaultFor(property, prefixes);
  switch (property.type) {
    case PropertyType.integer:
      return '($variable ?? $fallback).toInt()';
    case PropertyType.real:
    case PropertyType.length:
      return '($variable ?? $fallback).toDouble()';
    case PropertyType.duration:
      return 'Duration(milliseconds: ($variable ?? $fallback).toInt())';
    case PropertyType.fontWeight:
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

_FieldClassification _classifyField(
  WidgetEntry entry,
  PropertyEntry property,
  A2uiRichShapes? richShapes,
  bool prefixesCustomerLibs,
) {
  final childSlot = _childSlot(property);
  if (childSlot != null) {
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
  final richNode = richShapes?[(entry.name, property.name)];
  if (richNode != null) {
    return _classifyRichField(entry, property, richNode);
  }

  if (property.type == PropertyType.event) {
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
  if (_reservedBuilderIdentifiers.contains(_identifierFor(property.name))) {
    return _fieldUnsupported(
      entry,
      property,
      reason: property.required
          ? A2uiDartCoverageReason.requiredUnsupportedPropertyType
          : A2uiDartCoverageReason.optionalUnsupportedPropertyType,
    );
  }

  return _EmitField(
    A2uiDartFieldPlan._(property: property, emission: A2uiDataField(node)),
  );
}

/// Classifies a property the reflector resolved to a rich data [node].
///
/// An OPTIONAL, NON-null argument has no synthesizable default, so it is
/// omitted (loud) — the widget's own constructor default applies, the correct
/// optional fail-safe (mirroring the reflector's optional-object scope-out, one
/// level up at the argument site). A REQUIRED argument (fail-safe-guarded) or a
/// NULLABLE argument (pass-through) is emitted as a rich data field.
_FieldClassification _classifyRichField(
  WidgetEntry entry,
  PropertyEntry property,
  A2uiSchemaNode node,
) {
  if (!property.required && !node.nullable) {
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
      emission: A2uiDataField(node, rich: true),
    ),
  );
}

_FieldClassification _fieldUnsupported(
  WidgetEntry entry,
  PropertyEntry property, {
  required A2uiDartCoverageReason reason,
}) {
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

A2uiChildSlot? _childSlot(PropertyEntry property) {
  if (property.type == PropertyType.widget) return const A2uiChildNode();
  if (property.type == PropertyType.widgetList) {
    return const A2uiChildrenNode();
  }
  return null;
}

/// Maps a catalog property to its behaviour-neutral data-shape leaf node, or
/// null when the property type is not a bound data value the emitter carries.
///
/// Numeric kinds collapse to [A2uiScalarType.number] (the construction detail —
/// `.toInt()` / `.toDouble()` / `Duration(...)` / font-weight lookup — is driven
/// by the property type at argument-emission time, not the node), matching the
/// long-standing emitter output.
A2uiSchemaNode? _dataNode(PropertyEntry property) {
  switch (property.type) {
    case PropertyType.boolean:
      return const ScalarNode(A2uiScalarType.boolean);
    case PropertyType.integer:
    case PropertyType.real:
    case PropertyType.length:
    case PropertyType.duration:
    case PropertyType.fontWeight:
      return const ScalarNode(A2uiScalarType.number);
    case PropertyType.string:
    case PropertyType.color:
      return const ScalarNode(A2uiScalarType.string);
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
      );
    case PropertyType.stringList:
      return const ListNode(element: ScalarNode(A2uiScalarType.string));
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

A2uiDartWidgetDrop? _dropReasonForWidget(WidgetEntry entry) {
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

/// The generated identifiers (the data map, the widget-builder parameter, the
/// `Bound*` builder parameter) a customer property's leaf binding could shadow.
const _reservedBuilderIdentifiers = {'data', 'context', 'itemContext'};

/// The reserved-prefixed local a rich field's reconstructed value is bound to,
/// so a customer property named `data`/`context`/`itemContext` can never
/// collide with the generated scaffolding.
String _richLocalName(PropertyEntry property) =>
    '_restageA2uiArg_${_identifierFor(property.name)}';

String _dartStringLiteral(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}

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
