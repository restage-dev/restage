import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The catalog shape a customer `@RestageProperty` field lowers to when its
/// static type is a structured value (a nested data class, a list/map/record
/// of such, or a sealed union) rather than a scalar/enum/widget/event.
@immutable
final class StructuredPropertyShape {
  /// Creates a structured property shape.
  const StructuredPropertyShape({
    required this.type,
    required this.valueShape,
    this.structuredRef,
  });

  /// The catalog property type — [PropertyType.structured] for a structured
  /// value, or the union's effective property type for a union value.
  final PropertyType type;

  /// The structured wire reference (for a direct structured value), carrying
  /// the unallocated-structured sentinel until the allocator mints a real ID.
  final WireIdRef? structuredRef;

  /// The full value shape (a [StructuredShape], or a list/union shape) the
  /// property carries on the catalog.
  final CatalogValueShape valueShape;
}

/// Discovers the customer structured types reachable from a library's
/// `@RestageWidget` property fields and lowers them to catalog
/// [StructuredEntry]/[UnionEntry] values (with unallocated wire IDs).
///
/// This is the customer-path analogue of the built-in widget reflector's
/// structured production: it seeds a [StructuredWalkPolicy] with the
/// discovered customer data-class identities, then drives the public
/// [walkStructuredType]/[lowerStructured] machinery. The wire IDs stay
/// unallocated here; a later allocation pass mints them.
@immutable
final class CustomerStructuredDiscovery {
  const CustomerStructuredDiscovery._({
    required this.structuredTypes,
    required this.unions,
    required PolicyLedger policy,
    required Map<String, String> libraryNamespaceByFqn,
  })  : _policy = policy,
        _libraryNamespaceByFqn = libraryNamespaceByFqn;

  /// An empty discovery — no customer structured types were found.
  const CustomerStructuredDiscovery.empty()
      : structuredTypes = const [],
        unions = const [],
        _policy = const PolicyLedger.builtIn(),
        _libraryNamespaceByFqn = const {};

  /// The discovered structured types (unallocated wire IDs).
  final List<StructuredEntry> structuredTypes;

  /// The discovered unions (unallocated wire IDs).
  final List<UnionEntry> unions;

  final PolicyLedger _policy;
  final Map<String, String> _libraryNamespaceByFqn;

  /// The structured property shape for [fieldType], or `null` when the field
  /// is not a discovered structured value (the caller falls back to scalar /
  /// enum / widget / event inference).
  StructuredPropertyShape? shapeFor(DartType fieldType) {
    if (classifyStructured(fieldType, _policy) != StructuredKind.concrete) {
      return null;
    }
    final fqn = typeFqn(fieldType);
    if (fqn == null) return null;
    final libraryNamespace = _libraryNamespaceByFqn[fqn];
    if (libraryNamespace == null) return null;
    final ref = WireIdRef(
      library: libraryNamespace,
      wireId: WireId.unallocatedStructured,
    );
    return StructuredPropertyShape(
      type: PropertyType.structured,
      structuredRef: ref,
      valueShape: StructuredShape(
        propertyType: PropertyType.structured,
        structuredRef: ref,
      ),
    );
  }
}

/// A discovered customer structured root: the data-class element plus the
/// customer library namespace of the `@RestageWidget` that references it.
class _StructuredRoot {
  _StructuredRoot(this.element, this.libraryNamespace);

  final ClassElement element;
  final String libraryNamespace;
}

/// Walks [widgetClasses]' `@RestageProperty` fields, discovers the customer
/// structured value types they reference (transitively, so a data class that
/// nests another data class materialises both), and lowers each to a catalog
/// [StructuredEntry] (unallocated).
CustomerStructuredDiscovery discoverCustomerStructured({
  required List<ClassElement> widgetClasses,
  required AssetId assetId,
  required List<Issue> issues,
}) {
  // The transitive closure of customer data-class identities reachable from
  // the widgets' properties. Every member must be in the structured-walk
  // policy BEFORE the walk, or the walker warn+drops a nested field as a
  // "policy gap" — so the closure is computed first, by a policy-free
  // traversal, then handed to the walker complete.
  final closure = <String, _StructuredRoot>{};
  final worklist = <ClassElement>[];

  void addDataClass(DartType type, String libraryNamespace) {
    final element = classElementFor(type);
    if (element == null || !_isCustomerDataClass(element)) return;
    final fqn = elementFqn(element);
    if (closure.containsKey(fqn)) return;
    closure[fqn] = _StructuredRoot(element, libraryNamespace);
    worklist.add(element);
  }

  // Phase 1 — seed from the `@RestageProperty` field types.
  for (final cls in widgetClasses) {
    final libraryNamespace = _widgetLibraryNamespace(cls);
    if (libraryNamespace == null) continue;
    for (final field in cls.fields) {
      if (firstAnnotation(field, 'RestageProperty') == null) continue;
      addDataClass(field.type, libraryNamespace);
    }
  }

  // Phase 1b — transitively close over each data class's structured field
  // types so nested data classes join the policy.
  while (worklist.isNotEmpty) {
    final element = worklist.removeLast();
    final libraryNamespace = closure[elementFqn(element)]!.libraryNamespace;
    for (final fieldType in _structuredFieldTypes(element)) {
      addDataClass(fieldType, libraryNamespace);
    }
  }

  if (closure.isEmpty) return const CustomerStructuredDiscovery.empty();

  // Phase 2 — seed the structured-walk policy with the FULL closure so the
  // walker classifies every customer identity (root or nested) as concrete.
  final policy = const PolicyLedger.builtIn().extend(
    structuredWalk: StructuredWalkPolicy(
      concreteTypes: closure.keys.toSet(),
      abstractTypes: const <String>{},
    ),
  );

  // Phase 3 — walk EVERY closure member as a root so each materialises its own
  // full IR (a shallow descendant stub is never the source of truth). Dedup by
  // sourceType; descendants are redundant since every type is itself a root.
  final structuredByFqn = <String, StructuredEntry>{};
  final libraryNamespaceByFqn = <String, String>{};
  for (final entry in closure.entries) {
    final fqn = entry.key;
    final root = entry.value;
    final library = WidgetLibrary.fromNamespace(root.libraryNamespace);
    final walk = walkStructuredType(
      element: root.element,
      library: library,
      policy: policy,
      location: '${assetId.path}#${root.element.name ?? '<unnamed>'}',
      visited: <String>{},
      depth: 0,
    );
    final ir = walk.ir;
    if (ir != null) {
      final lowered = lowerStructured(ir);
      structuredByFqn.putIfAbsent(lowered.sourceType, () => lowered);
      libraryNamespaceByFqn[fqn] = root.libraryNamespace;
    }
  }

  return CustomerStructuredDiscovery._(
    structuredTypes: List.unmodifiable(structuredByFqn.values),
    unions: const [],
    policy: policy,
    libraryNamespaceByFqn: libraryNamespaceByFqn,
  );
}

/// The structured field types of [element] — the declared types of fields
/// named by a generative constructor parameter (the same selection the
/// structured walker recurses, mirrored here for closure discovery). Computed
/// getters and private/static fields are excluded.
Iterable<DartType> _structuredFieldTypes(ClassElement element) sync* {
  final generativeParamNames = <String>{
    for (final constructor in element.constructors)
      if (!constructor.isFactory)
        for (final parameter in constructor.formalParameters)
          if (parameter.name case final name? when name.isNotEmpty) name,
  };
  for (final field in element.fields) {
    final name = field.name;
    if (name == null || name.isEmpty || name.startsWith('_')) continue;
    if (field.isStatic) continue;
    if (!generativeParamNames.contains(name)) continue;
    yield field.type;
  }
}

/// Reads the `@RestageWidget(library:)` namespace off [cls], or `null` when
/// the annotation is absent or not const-evaluable.
String? _widgetLibraryNamespace(ClassElement cls) {
  final annotation = firstAnnotation(cls, 'RestageWidget');
  return annotation
      ?.computeConstantValue()
      ?.getField('library')
      ?.getField('namespace')
      ?.toStringValue();
}

/// Whether [element] is a customer data class — a concrete, non-`dart:`/
/// non-`package:flutter/` class with at least one generative-constructor
/// parameter (i.e. it carries value state). A class with no constructor
/// parameters (`Mystery {}`) is NOT a data class and falls through to the
/// caller's existing unsupported-type handling.
bool _isCustomerDataClass(ClassElement element) {
  if (element.isAbstract) return false;
  final libraryId = element.library.identifier;
  if (libraryId.startsWith('dart:') ||
      libraryId.startsWith('package:flutter/')) {
    return false;
  }
  return element.constructors.any(
    (constructor) =>
        !constructor.isFactory && constructor.formalParameters.isNotEmpty,
  );
}
