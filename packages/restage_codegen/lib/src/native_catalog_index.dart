import 'package:restage_codegen/src/factory_variant_fields.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

typedef _LibraryWireKey = (String, WireId);
typedef _WidgetPropertyKey = (String, WireId, WireId);
typedef _StructuredFieldKey = (String, WireId, WireId);
typedef _VariantParameterKey = (String, WireId, WireId);

/// Codegen-side lookup table over a validated native catalog.
///
/// Wire IDs are library-scoped. This index keeps every lookup
/// library-qualified except where a bare ID is explicitly scoped by its
/// owning widget, structured entry, or factory variant.
final class NativeCatalogIndex {
  /// Builds an index over [catalog] after validating the native boundary.
  NativeCatalogIndex(Catalog catalog)
      : catalog = requireNativeCatalog(catalog) {
    for (final widget in this.catalog.widgets) {
      final widgetKey = (widget.library.namespace, widget.wireId);
      _widgetsByRef[widgetKey] = widget;
      _widgetsByName[(widget.library.namespace, widget.name)] = widget;
      final widgetType = _dartTypeRefFromSource(widget.flutterType);
      if (widgetType != null) {
        _widgetsByDartType[widgetType] = widget;
      }
      for (final property in widget.properties) {
        _widgetProperties[(
          widget.library.namespace,
          widget.wireId,
          property.wireId,
        )] = property;
      }
    }

    for (final structured in this.catalog.structuredTypes) {
      final structuredKey = (structured.library.namespace, structured.wireId);
      _structuredByRef[structuredKey] = structured;
      final structuredType = _dartTypeRefFromSource(structured.sourceType);
      if (structuredType != null) {
        _structuredByDartType[structuredType] = structured;
      }
      for (final field in structured.fields) {
        _structuredFields[(
          structured.library.namespace,
          structured.wireId,
          field.wireId,
        )] = field;
      }
      for (final variant in structured.variants) {
        final variantRef = WireIdRef(
          library: structured.library.namespace,
          wireId: variant.wireId,
        );
        _variantsByRef[(variantRef.library, variantRef.wireId)] = variant;
        _variantOwners[(variantRef.library, variantRef.wireId)] = WireIdRef(
          library: structured.library.namespace,
          wireId: structured.wireId,
        );
        _variantsByStructured[(
          structured.library.namespace,
          structured.wireId,
          variant.wireId,
        )] = variant;
        for (final parameter
            in factoryVariantCallableFields(variant).parameters) {
          _variantParameters[(
            variantRef.library,
            variantRef.wireId,
            parameter.wireId,
          )] = parameter;
        }
      }
    }

    for (final union in this.catalog.unions) {
      final unionKey = (union.library.namespace, union.wireId);
      _unionsByRef[unionKey] = union;
      for (final member in union.members) {
        final structured = structuredByRef(member);
        if (structured == null) continue;
        _unionMembers[(
          union.library.namespace,
          union.wireId,
          member.library,
          member.wireId,
        )] = structured;
      }
    }
  }

  /// Validated native catalog.
  final Catalog catalog;

  final Map<_LibraryWireKey, WidgetEntry> _widgetsByRef = {};
  final Map<(String, String), WidgetEntry> _widgetsByName = {};
  final Map<DartTypeRef, WidgetEntry> _widgetsByDartType = {};
  final Map<_WidgetPropertyKey, PropertyEntry> _widgetProperties = {};
  final Map<_LibraryWireKey, StructuredEntry> _structuredByRef = {};
  final Map<DartTypeRef, StructuredEntry> _structuredByDartType = {};
  final Map<_StructuredFieldKey, StructuredField> _structuredFields = {};
  final Map<_LibraryWireKey, FactoryVariant> _variantsByRef = {};
  final Map<_LibraryWireKey, WireIdRef> _variantOwners = {};
  final Map<_StructuredFieldKey, FactoryVariant> _variantsByStructured = {};
  final Map<_VariantParameterKey, FactoryParameter> _variantParameters = {};
  final Map<_LibraryWireKey, UnionEntry> _unionsByRef = {};
  final Map<(String, WireId, String, WireId), StructuredEntry> _unionMembers =
      {};

  /// Returns a widget by `(library, wireId)`.
  WidgetEntry? widgetByRef(WireIdRef ref) =>
      _widgetsByRef[(ref.library, ref.wireId)];

  /// Returns a widget by `(library, name)`.
  WidgetEntry? widgetByName(WidgetLibrary library, String name) =>
      _widgetsByName[(library.namespace, name)];

  /// Returns a widget by source-qualified Dart type.
  WidgetEntry? widgetByDartType(DartTypeRef typeRef) =>
      _widgetsByDartType[typeRef];

  /// Returns a widget property by `(widget library, widget wireId, property)`.
  PropertyEntry? widgetProperty(WireIdRef widgetRef, WireId propertyId) =>
      _widgetProperties[(widgetRef.library, widgetRef.wireId, propertyId)];

  /// Returns a structured entry by `(library, wireId)`.
  StructuredEntry? structuredByRef(WireIdRef ref) =>
      _structuredByRef[(ref.library, ref.wireId)];

  /// Returns a structured entry by source-qualified Dart type.
  StructuredEntry? structuredByDartType(DartTypeRef typeRef) =>
      _structuredByDartType[typeRef];

  /// Returns a structured field by `(structuredRef, field wireId)`.
  StructuredField? structuredField(
    WireIdRef structuredRef,
    WireId fieldId,
  ) =>
      _structuredFields[(
        structuredRef.library,
        structuredRef.wireId,
        fieldId,
      )];

  /// Returns a factory variant by library-qualified variant wire ID.
  FactoryVariant? variantByRef(WireIdRef variantRef) =>
      _variantsByRef[(variantRef.library, variantRef.wireId)];

  /// Returns the structured entry that owns [variantRef].
  StructuredEntry? variantOwner(WireIdRef variantRef) {
    final ownerRef = _variantOwners[(variantRef.library, variantRef.wireId)];
    if (ownerRef == null) return null;
    return structuredByRef(ownerRef);
  }

  /// Returns a variant by `(structuredRef, variant wireId)`.
  FactoryVariant? variantFor(WireIdRef structuredRef, WireId variantId) =>
      _variantsByStructured[(
        structuredRef.library,
        structuredRef.wireId,
        variantId,
      )];

  /// Returns a variant parameter by `(variantRef, parameter wireId)`.
  FactoryParameter? variantParameter(
    WireIdRef variantRef,
    WireId parameterId,
  ) =>
      _variantParameters[(
        variantRef.library,
        variantRef.wireId,
        parameterId,
      )];

  /// Returns a union by `(library, wireId)`.
  UnionEntry? unionByRef(WireIdRef ref) =>
      _unionsByRef[(ref.library, ref.wireId)];

  /// Returns a union member structured entry when [memberRef] belongs to
  /// [unionRef].
  StructuredEntry? unionMember(WireIdRef unionRef, WireIdRef memberRef) =>
      _unionMembers[(
        unionRef.library,
        unionRef.wireId,
        memberRef.library,
        memberRef.wireId,
      )];

  /// Resolves receiver metadata to the source-qualified Dart type to invoke.
  DartTypeRef receiverDartType(
    FactoryReceiver receiver, {
    required WidgetEntry owningWidget,
    required StructuredEntry resultStructured,
  }) {
    switch (receiver) {
      case ResultStructuredTypeReceiver():
        final ref = _dartTypeRefFromSource(resultStructured.sourceType);
        if (ref == null) {
          throw StateError(
            "Structured entry '${resultStructured.name}' has malformed "
            "sourceType '${resultStructured.sourceType}'.",
          );
        }
        return ref;
      case OwningWidgetTypeReceiver():
        final ref = _dartTypeRefFromSource(owningWidget.flutterType);
        if (ref == null) {
          throw StateError(
            "Widget entry '${owningWidget.name}' has malformed flutterType "
            "'${owningWidget.flutterType}'.",
          );
        }
        return ref;
      case ExplicitDartTypeReceiver(:final dartTypeRef):
        return dartTypeRef;
    }
  }
}

DartTypeRef? _dartTypeRefFromSource(String sourceType) {
  final hash = sourceType.indexOf('#');
  if (hash <= 0 || hash == sourceType.length - 1) return null;
  final libraryUri = sourceType.substring(0, hash);
  var symbolName = sourceType.substring(hash + 1);
  final memberSeparator = symbolName.indexOf('.');
  if (memberSeparator > 0) {
    symbolName = symbolName.substring(0, memberSeparator);
  }
  if (libraryUri.isEmpty || symbolName.isEmpty) return null;
  return DartTypeRef(libraryUri: libraryUri, symbolName: symbolName);
}
