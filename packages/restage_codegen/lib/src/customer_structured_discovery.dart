import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/customer_structured_admissibility.dart'
    show reconstructionVariant, structuredSlotKey;
import 'package:restage_codegen/src/customer_structured_reconstruction.dart';
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
    required this.slotTargets,
    required this.nullableStructuredSlots,
    required this.localUnrenderable,
    required this.reconstructionPlans,
    required PolicyLedger policy,
    required Map<String, String> libraryNamespaceByFqn,
  })  : _policy = policy,
        _libraryNamespaceByFqn = libraryNamespaceByFqn;

  /// An empty discovery — no customer structured types were found.
  const CustomerStructuredDiscovery.empty()
      : structuredTypes = const [],
        unions = const [],
        slotTargets = const {},
        nullableStructuredSlots = const {},
        localUnrenderable = const {},
        reconstructionPlans = const {},
        _policy = const PolicyLedger.builtIn(),
        _libraryNamespaceByFqn = const {};

  /// The discovered structured types (unallocated wire IDs).
  final List<StructuredEntry> structuredTypes;

  /// The discovered unions (unallocated wire IDs).
  final List<UnionEntry> unions;

  /// Maps each `PropertyType.structured` slot — a widget property or a nested
  /// structured field, keyed `'<ownerFqn>.<slotName>'` (the same source-key
  /// convention the allocator uses) — to its target structured type's
  /// `sourceType` FQN. This is the identity the sentinel `structuredRef`
  /// (a bare `unallocatedStructured`) does not carry; the allocation pass reads
  /// it to resolve each slot's ref, and the admissibility check reads it to
  /// walk the closure.
  final Map<String, String> slotTargets;

  /// The subset of WIDGET structured-property slot keys (same
  /// `'<widgetFlutterType>.<propName>'` convention) whose Dart type is NULLABLE
  /// (`Badge?`). A build-time-only signal (never a wire field): the factory
  /// presence-checks a nullable widget structured prop to `null` on an absent
  /// map instead of reconstructing unconditionally (which would crash on an
  /// absent nested-required leaf). Nested-field nullability travels via the
  /// reconstruction plan; this covers only the level-0 widget prop.
  final Set<String> nullableStructuredSlots;

  /// Structured types whose walk warn+dropped an unsupported inner field
  /// (Map/record/list-of-objects/customer-union) — keyed by `sourceType`, value
  /// a human-readable reason. A type here is not fully renderable on the RFW
  /// path; the recursive gate excludes any widget whose closure reaches one.
  final Map<String, String> localUnrenderable;

  /// The build-time reconstruction recipe for each renderable structured type,
  /// keyed by `sourceType`. Derived from the SAME analyzer walk as the
  /// admissibility predicate (so they can't disagree), it carries the ctor arg
  /// kind/order the factory emitter needs but the (empty) wire `parameters`
  /// don't. A type whose plan can't place a required param is excluded-loud
  /// instead (a predicate gap), never given a partial plan.
  final Map<String, ReconstructionPlan> reconstructionPlans;

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
  // Structured slot -> target sourceType FQN, keyed '<ownerFqn>.<slotName>'.
  final slotTargets = <String, String>{};
  // Widget structured-prop slot keys whose Dart type is nullable (`Badge?`).
  final nullableStructuredSlots = <String>{};

  // Adds [type]'s class to the closure when it is a customer data class, and
  // returns the resolved element (or `null` when [type] is not a customer data
  // class) so the caller can reuse it without re-resolving.
  ClassElement? addDataClass(DartType type, String libraryNamespace) {
    final element = classElementFor(type);
    if (element == null || !_isCustomerDataClass(element)) return null;
    final fqn = elementFqn(element);
    if (!closure.containsKey(fqn)) {
      closure[fqn] = _StructuredRoot(element, libraryNamespace);
      worklist.add(element);
    }
    return element;
  }

  // First pass: seed from the `@RestageProperty` field types, and record each
  // structured widget property's slot target so a later pass can resolve its
  // bare sentinel `structuredRef`. The owner key is the widget's `flutterType`
  // (`'<library URI>#<class name>'`, == `elementFqn`) so it matches
  // `WidgetEntry.flutterType` at resolution time.
  for (final cls in widgetClasses) {
    final libraryNamespace = _widgetLibraryNamespace(cls);
    if (libraryNamespace == null) continue;
    final ownerFqn = elementFqn(cls);
    for (final field in cls.fields) {
      if (firstAnnotation(field, 'RestageProperty') == null) continue;
      final targetElement = addDataClass(field.type, libraryNamespace);
      final fieldName = field.name;
      if (targetElement != null && fieldName != null && fieldName.isNotEmpty) {
        final slotKey = structuredSlotKey(ownerFqn, fieldName);
        slotTargets[slotKey] = elementFqn(targetElement);
        // A build-time signal (never a wire field): an optional NULLABLE
        // widget structured prop yields `null` on an absent map, so the factory
        // must presence-check to null rather than reconstruct unconditionally.
        if (_isNullable(field.type)) nullableStructuredSlots.add(slotKey);
      }
    }
  }

  // Closure pass: transitively include each data class's structured field
  // types so nested data classes join the policy.
  while (worklist.isNotEmpty) {
    final element = worklist.removeLast();
    final libraryNamespace = closure[elementFqn(element)]!.libraryNamespace;
    for (final field in _structuredFields(element)) {
      addDataClass(field.type, libraryNamespace);
    }
  }

  if (closure.isEmpty) return const CustomerStructuredDiscovery.empty();

  // Policy pass: seed the structured-walk policy with the FULL closure so the
  // walker classifies every customer identity (root or nested) as concrete.
  final policy = const PolicyLedger.builtIn().extend(
    structuredWalk: StructuredWalkPolicy(
      concreteTypes: closure.keys.toSet(),
      abstractTypes: const <String>{},
    ),
  );

  // Lowering pass: walk EVERY closure member as a root so each materialises
  // its own full IR (a shallow descendant stub is never the source of truth).
  // Dedup by sourceType; descendants are redundant since every type is itself
  // a root.
  final structuredByFqn = <String, StructuredEntry>{};
  final libraryNamespaceByFqn = <String, String>{};
  // Types whose walk warn+dropped an unsupported inner field: they cannot
  // render faithfully, so the recursive gate excludes any widget reaching them.
  final localUnrenderable = <String, String>{};
  // The build-time reconstruction recipe per renderable type (arg kind/order).
  final reconstructionPlans = <String, ReconstructionPlan>{};
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
      // Exclude-loud, first-wins: record the first reason this type cannot
      // render, keyed by its `sourceType`. The distinct axes below (dropped
      // field, reconstructor-soundness, nameability) each feed this one sink
      // with their own reason, so the sourceType key lives in one place.
      void recordUnrenderable(String? reason) {
        if (reason != null) {
          localUnrenderable.putIfAbsent(lowered.sourceType, () => reason);
        }
      }

      // The walker records a diagnostic and DROPS an unsupported inner field
      // (Map/record/list-of-objects/customer-union) rather than failing the
      // build. A dropped field means the lowered entry is missing state, so the
      // type is not fully renderable — mark it loud rather than admit-and-drop.
      if (ir.diagnostics.isNotEmpty) {
        recordUnrenderable(_diagnosticReason(ir.diagnostics));
      }
      // Reconstructor-soundness (analyzer-level): the by-name reconstructor
      // sources each ctor parameter from the field of the same name. A required
      // param that name-matches no materialized field cannot be sourced — and
      // the lowered IR discards it (real `FactoryVariantIR.parameters` is empty
      // and `argMappings` skips an unmapped param), so a lowered-catalog-only
      // check is a no-op. Detect it here, over the real constructor. The target
      // ctor is derived from `reconstructionVariant` (the SAME selection the
      // reconstruction uses) so the check can't drift from what gets emitted.
      final materializedFieldNames = {
        for (final field in lowered.fields) field.name,
      };
      // The reconstruction ctor, selected ONCE — the obstruction check, the
      // plan, and the eventual emission all read the SAME variant so they can't
      // diverge.
      final reconVariant = reconstructionVariant(lowered);
      recordUnrenderable(
        _reconstructionObstruction(
          root.element,
          reconVariant,
          materializedFieldNames,
        ),
      );
      // Nameability (compilability, distinct from faithfulness): every type the
      // generated factory references — this type + its materialized field types
      // (a nested ctor call, an enum's `.values`) — must be NAMEABLE from the
      // generated library. A language-private type (`_Foo`) can't be named, so
      // the generated factory would not compile (a hard build failure). Exclude
      // it loud instead. Public referenced types are nameable; the import
      // closure consumes this same analysis to import them.
      recordUnrenderable(
        _unnameableReferencedType(root.element, materializedFieldNames),
      );
      // Importability of a referenced FLUTTER enum (a distinct compilability
      // axis — it must be in `widgets.dart`'s export namespace to be named
      // bare) is checked in the ASYNC walker (see
      // `collectRestageWidgetsForPackage`), where `widgets.dart` can be
      // resolved; a non-exported flutter enum's
      // owning structured type is marked `localUnrenderable` there.
      // The build-time reconstruction plan (arg kind/order + optional
      // non-nullable defaults), from the SAME analyzer ctor. It must place
      // EVERY required param and reproduce EVERY optional non-nullable param's
      // default; if it can't (a required param with no field, or an optional
      // non-nullable param whose default cannot be faithfully reproduced in the
      // generated library), that is a predicate gap — exclude-loud, never a
      // partial plan or silent value loss. Consistent by construction with the
      // obstruction check above, which reads the same variant + fields.
      final planResult = _buildReconstructionPlan(
        root.element,
        reconVariant,
        materializedFieldNames,
      );
      final plan = planResult.plan;
      if (plan == null) {
        recordUnrenderable(planResult.reason);
      } else {
        reconstructionPlans[lowered.sourceType] = plan;
      }
      // Record each nested structured field's slot target for ref resolution.
      for (final (fieldName, targetFqn)
          in _structuredFieldTargets(root.element)) {
        slotTargets[structuredSlotKey(lowered.sourceType, fieldName)] =
            targetFqn;
      }
    }
  }

  return CustomerStructuredDiscovery._(
    structuredTypes: List.unmodifiable(structuredByFqn.values),
    unions: const [],
    slotTargets: Map.unmodifiable(slotTargets),
    nullableStructuredSlots: Set.unmodifiable(nullableStructuredSlots),
    localUnrenderable: Map.unmodifiable(localUnrenderable),
    reconstructionPlans: Map.unmodifiable(reconstructionPlans),
    policy: policy,
    libraryNamespaceByFqn: libraryNamespaceByFqn,
  );
}

/// The structured (value-bearing) fields of [element] — the declared
/// `(name, type)` of fields named by a generative constructor parameter (the
/// same selection the structured walker recurses, mirrored here for closure
/// discovery). Computed getters and private/static fields are excluded.
Iterable<({String name, DartType type})> _structuredFields(
  ClassElement element,
) sync* {
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
    yield (name: name, type: field.type);
  }
}

/// The `(fieldName, targetSourceType)` for each of [element]'s fields whose
/// type is a customer data class — the slot targets a later pass uses to
/// resolve nested structured `structuredRef`s from their bare sentinels.
Iterable<(String, String)> _structuredFieldTargets(ClassElement element) sync* {
  for (final field in _structuredFields(element)) {
    final targetElement = classElementFor(field.type);
    if (targetElement == null || !_isCustomerDataClass(targetElement)) continue;
    yield (field.name, elementFqn(targetElement));
  }
}

/// A human-readable reason the EXACT constructor the reconstructor will use —
/// [reconVariant], resolved to the same-named analyzer constructor on
/// [element] — cannot faithfully reconstruct a value by name, else `null`.
///
/// Three obstructions:
///  * The ctor is a FACTORY. A factory's body may transform its input (an
///    un-curated customer `factory Badge.x({required String label}) =>
///    Badge.raw(label: 'x:$label')` doubles on round-trip), and the analyzer
///    can't see the body, so a factory reconstruction target is not
///    round-trip-safe for a customer type. (Built-in splatting factories like
///    `BorderRadius.circular` are curated and travel a different path.)
///  * A NAMED param — required OR optional — name-matches no field in
///    [fieldNames], so the by-name reconstructor could not source it (a
///    non-canonical shape like `Badge({required int c}) : count = c`, or
///    `Badge({int c = 0}) : count = c` — optionality doesn't make a renamed
///    param sourceable; the reconstructor would still supply `count:`, so a
///    genuinely-authored value silently reads back as whatever default the
///    reconstruction ctor gives `count`, never the author's actual value).
///    Optional POSITIONAL params are exempted here (a trailing extra is
///    harmless — the positional-hole check guards their emission order).
///  * A materialized FIELD in [fieldNames] name-matches no ctor parameter.
///    This is the field-side dual of the param check and closes the POSITIONAL
///    rename (`Badge([int label = 0]) : count = label`) the positional
///    exemption above lets slip: the encode sources each field by name, so a
///    field with no same-named param is dropped and mis-reconstructed. (It
///    also over-excludes a constant/derived initializer-list field — a
///    deliberate fail-safe; see the inline note.)
///
/// Returns `null` when [reconVariant] is null (no constructor variant), the
/// matching analyzer ctor can't be found, or the ctor is a faithful generative
/// ctor whose params and materialized fields name-match one-to-one.
///
/// The target ctor is derived from [reconstructionVariant] (over the
/// enumerator's already-filtered, already-sorted variants) rather than
/// re-selected here, so the soundness check stays aligned with the
/// reconstruction BY CONSTRUCTION — one source of truth for which ctor is
/// canonical. This alignment is load-bearing: a guard/reconstruction
/// ctor-selection divergence (e.g. picking the source-first named ctor when the
/// reconstruction picks the alphabetically first, inspecting a redirecting ctor
/// the enumerator dropped, or missing a transforming factory) is an
/// admitted-but-wrong = a customer build failure.
String? _reconstructionObstruction(
  ClassElement element,
  ConstructorVariant? reconVariant,
  Set<String?> fieldNames,
) {
  final ctor = _reconstructionCtor(element, reconVariant);
  if (ctor == null) return null;
  final targetName = _normalizedCtorName(ctor); // null == the unnamed ctor
  if (ctor.isFactory) {
    return 'the reconstruction constructor "${targetName ?? 'new'}" is a '
        'factory (its input may be transformed, so the value cannot be '
        'faithfully reconstructed by name)';
  }
  for (final parameter in ctor.formalParameters) {
    final name = parameter.name;
    if (name == null || name.isEmpty) continue;
    // A trailing OPTIONAL positional with no matching field is a deliberately
    // admitted shape (the reconstructor simply omits it — see the
    // positional-hole check below); an UNMAPPED optional positional is only a
    // problem when it precedes a mapped one (a hole), which that check
    // catches regardless of required-ness. A NAMED param, by contrast, can be
    // supplied deliberately by the author regardless of position, so a
    // name-mismatch is caught here whether it's required or optional — an
    // optional renamed param (e.g. `Badge({int label = 0}) : count = label`)
    // would otherwise silently feed `count` from a name the reconstructor
    // never supplies, reading back as whatever default the ctor gives it.
    if (parameter.isPositional && !parameter.isRequired) continue;
    if (!fieldNames.contains(name)) {
      return 'ctor parameter "$name" has no matching field '
          '(non-canonical shape)';
    }
  }
  // Field -> param (the encode's exact requirement, checked from the FIELD
  // side): the encode sources each materialized field BY NAME
  // (`argRefByField[field.name]` in the value emitter), so every field MUST
  // have a same-named parameter on the reconstruction ctor to be carried on
  // the wire. A field with no same-named param is dropped by the encode and
  // read back as whatever the ctor produces without it. The param loop above
  // exempts OPTIONAL POSITIONAL params (a trailing extra is harmless), so a
  // POSITIONAL rename (`Badge([int label = 0]) : count = label`) slips past
  // it — it is caught here, uniformly with the named rename. This also
  // excludes a materialized field fed by a constant/derived initializer with
  // no same-named param (e.g. `: kind = 'default'`), which would in fact
  // round-trip faithfully — a deliberate fail-safe over-exclusion (the shape
  // is uncommon for a value object, the exclusion is loud, and the author's
  // fix is trivial: expose the field as a ctor parameter — `{this.kind =
  // 'default'}`).
  final ctorParamNames = {
    for (final parameter in ctor.formalParameters)
      if (parameter.name case final paramName? when paramName.isNotEmpty)
        paramName,
  };
  for (final fieldName in fieldNames) {
    if (fieldName == null || fieldName.isEmpty) continue;
    if (!ctorParamNames.contains(fieldName)) {
      return 'materialized field "$fieldName" has no matching reconstruction '
          'constructor parameter (non-canonical shape)';
    }
  }
  // Positional-hole: the reconstructor omits an UNMAPPED (non-field) positional
  // argument, which shifts every later MAPPED (field) positional into the wrong
  // slot (reconstructing {count: 7} through `Badge([int unused, this.count])`
  // emits `Badge(7)`, binding 7 to `unused`). A non-field positional BEFORE a
  // field positional is therefore not faithfully reconstructable.
  return positionalHoleReason(ctor, fieldNames);
}

/// A reason [ctor] has a POSITIONAL HOLE — an UNMAPPED positional parameter
/// (one whose name is NOT in [mappedNames], the names the factory emits an
/// argument for) appearing BEFORE a MAPPED positional parameter — else `null`.
/// The reconstructor/factory omits the unmapped arg, so every later mapped
/// positional shifts into the wrong slot (a silent wrong-render). A TRAILING
/// unmapped positional is fine (nothing shifts).
///
/// Shared by the nested structured-type reconstruction guard
/// ([_reconstructionObstruction], `mappedNames` = the materialized fields) and
/// the WIDGET-ctor guard (`mappedNames` = the annotated `@RestageProperty`
/// fields the factory emits), so the two levels use the SAME hole definition
/// and can't disagree.
String? positionalHoleReason(
  ConstructorElement ctor,
  Set<String?> mappedNames,
) {
  var sawUnmappedPositional = false;
  for (final parameter in ctor.formalParameters) {
    if (!parameter.isPositional) continue;
    final name = parameter.name;
    if (name != null && mappedNames.contains(name)) {
      if (sawUnmappedPositional) {
        return 'positional parameter "$name" follows an unmapped positional '
            'parameter, so its reconstructed argument would bind to the '
            'wrong slot';
      }
    } else {
      sawUnmappedPositional = true;
    }
  }
  return null;
}

/// The default generative (unnamed) constructor of [element], or `null` when it
/// has none. The constructor the widget factory / reconstruction targets.
ConstructorElement? defaultGenerativeConstructor(ClassElement element) =>
    element.constructors
        .where((c) => !c.isFactory && const {null, '', 'new'}.contains(c.name))
        .firstOrNull;

/// A human-readable reason a type referenced by [element]'s reconstruction —
/// [element] itself, or the type of one of its materialized fields (named by
/// [materializedFieldNames]) — cannot be NAMED from the generated factory
/// library, or `null` when every referenced type is nameable.
///
/// A language-private type (`_Foo`, name starts with `_`) is unnameable from
/// another library, so the generated factory would fail to compile — a hard
/// build failure. A public type is always nameable (its defining library can be
/// imported directly; the import closure does exactly that over the nameable
/// referenced types of admitted widgets). This is a COMPILABILITY axis,
/// distinct from round-trip faithfulness. A private nested data class is also
/// caught here (and recursively, when it is itself discovered).
String? _unnameableReferencedType(
  ClassElement element,
  Set<String?> materializedFieldNames,
) {
  final ownName = element.name;
  if (ownName != null && ownName.startsWith('_')) {
    return 'the type "$ownName" is private, so the generated factory library '
        'cannot name it';
  }
  for (final field in element.fields) {
    final name = field.name;
    if (name == null || !materializedFieldNames.contains(name)) continue;
    final type = field.type;
    if (type is! InterfaceType) continue;
    final typeName = type.element.name;
    if (typeName != null && typeName.startsWith('_')) {
      return 'the field "$name" has a private type "$typeName", so the '
          'generated factory library cannot name it';
    }
  }
  return null;
}

/// Normalizes an analyzer constructor's name to the convention the variant
/// enumerator uses for `namedConstructor`: the unnamed constructor (name null,
/// empty, or `new`) is `null`; a named constructor keeps its bare name. Used to
/// match a lowered [ConstructorVariant] back to its analyzer constructor.
String? _normalizedCtorName(ConstructorElement constructor) {
  final name = constructor.name;
  if (name == null || name.isEmpty || name == 'new') return null;
  return name;
}

/// The analyzer constructor the reconstruction targets: the one on [element]
/// whose [_normalizedCtorName] matches [reconVariant]'s `namedConstructor`.
/// This is the SINGLE ctor selection shared by [_reconstructionObstruction] and
/// [_buildReconstructionPlan] — one analyzer view they both read, so the
/// admission decision and the emitted arg list can't diverge on which ctor is
/// canonical. Returns `null` when there is no variant or no matching ctor.
ConstructorElement? _reconstructionCtor(
  ClassElement element,
  ConstructorVariant? reconVariant,
) {
  if (reconVariant == null) return null;
  final targetName = reconVariant.namedConstructor;
  for (final constructor in element.constructors) {
    if (_normalizedCtorName(constructor) == targetName) return constructor;
  }
  return null;
}

/// The build-time reconstruction plan for [element]'s reconstruction ctor
/// ([reconVariant]) over [materializedFieldNames]: every constructor parameter,
/// IN DECLARATION ORDER, that is PLACED (sourced from a same-named materialized
/// field) with its arg kind (named vs positional) and — for an optional
/// non-nullable param — its reproduced ctor default. Returns `plan: null` +
/// a `reason` when the type is a predicate gap (a required param with no field,
/// or an optional non-nullable param whose default cannot be faithfully
/// reproduced in the generated library) — the caller excludes-loud, NEVER a
/// partial plan or a silent value loss.
///
/// Uses the SAME constructor selection as [_reconstructionObstruction] (unnamed/
/// named via [_normalizedCtorName] against [reconstructionVariant]), so the
/// admission decision and the emitted arg list read one analyzer view and can't
/// disagree. An optional param with no field is validly omitted (its default
/// applies); the positional-hole predicate guarantees no placed positional
/// follows an omitted one, so emitting the placed args in order is faithful.
({ReconstructionPlan? plan, String? reason}) _buildReconstructionPlan(
  ClassElement element,
  ConstructorVariant? reconVariant,
  Set<String?> materializedFieldNames,
) {
  final ctor = _reconstructionCtor(element, reconVariant);
  if (ctor == null) {
    return (plan: null, reason: 'no reconstruction constructor variant');
  }
  final args = <ReconstructionArg>[];
  for (final parameter in ctor.formalParameters) {
    final name = parameter.name;
    if (name != null &&
        name.isNotEmpty &&
        materializedFieldNames.contains(name)) {
      // An optional NON-NULLABLE param needs its ctor default on the absent
      // branch (the decode `source.v<T>` returns `T?`); a REQUIRED param
      // fail-closes on absence; an optional NULLABLE param assigns the nullable
      // decode directly. Only the first needs a reproduced default — a
      // primitive literal, or a customer-enum constant the emitter qualifies
      // through the field's import alias.
      String? defaultCode;
      String? defaultEnumValue;
      if (!parameter.isRequired && !_isNullable(parameter.type)) {
        defaultCode = _reproducibleDefaultLiteral(parameter);
        if (defaultCode == null) {
          defaultEnumValue = _reproducibleEnumDefault(parameter);
        }
        if (defaultCode == null && defaultEnumValue == null) {
          // The default is neither a primitive literal nor an enum constant (a
          // const constructor, a framework const the generated library can't
          // name, an unresolvable expression). Reproducing it would need
          // imports/qualification the generated library does not carry —
          // exclude-loud rather than emit a non-compiling fallback or silently
          // drop the field's value.
          return (
            plan: null,
            reason: 'optional non-nullable parameter "$name" has a default '
                '(${parameter.defaultValueCode}) that the generated factory '
                'cannot faithfully reproduce',
          );
        }
      }
      final placed = (
        fieldName: name,
        isNamed: parameter.isNamed,
        isRequired: parameter.isRequired,
        defaultCode: defaultCode,
        defaultEnumValue: defaultEnumValue,
      );
      args.add(placed);
    } else if (parameter.isRequired) {
      // A required param with no field can neither be sourced nor omitted.
      return (
        plan: null,
        reason: 'required constructor parameter "${name ?? '<positional>'}" '
            'has no matching field',
      );
    }
    // else: optional + no field -> omit (the ctor default applies).
  }
  return (
    plan: (namedConstructor: _normalizedCtorName(ctor), args: args),
    reason: null,
  );
}

/// Whether [type] is a nullable type (`T?`).
bool _isNullable(DartType type) =>
    type.nullabilitySuffix == NullabilitySuffix.question;

/// The reproduced Dart source for [parameter]'s default value when it is a
/// primitive literal (bool / int / double / String) — the only defaults the
/// generated factory library can name without extra imports or alias
/// qualification. Returns `null` for any non-primitive default (an enum value,
/// a const constructor, a named const, an unresolvable/non-finite value), which
/// the caller treats as a predicate gap and excludes-loud.
///
/// Derived from the analyzer's evaluated constant (`computeConstantValue`),
/// not the raw `defaultValueCode` text — so the emitted literal is a canonical,
/// re-parseable form independent of the customer's source spelling.
String? _reproducibleDefaultLiteral(FormalParameterElement parameter) {
  final value = parameter.computeConstantValue();
  if (value == null) return null;
  final stringValue = value.toStringValue();
  if (stringValue != null) return _dartStringLiteral(stringValue);
  final boolValue = value.toBoolValue();
  if (boolValue != null) return boolValue.toString();
  final intValue = value.toIntValue();
  if (intValue != null) return intValue.toString();
  final doubleValue = value.toDoubleValue();
  if (doubleValue != null && doubleValue.isFinite) {
    return doubleValue.toString();
  }
  return null;
}

/// The enum CONSTANT name (`soft`) of [parameter]'s default when it is a single
/// enum value (`Tone.soft`), or `null` otherwise. The emitter qualifies the
/// enum type through the field's import alias, so only the value name is needed
/// here. Derived from the analyzer's evaluated constant's backing variable
/// (an enum constant is a `FieldElement` with `isEnumConstant`), so a computed
/// or non-enum default (`Tone.values.first`) yields `null` and excludes-loud.
String? _reproducibleEnumDefault(FormalParameterElement parameter) {
  final variable = parameter.computeConstantValue()?.variable;
  if (variable is FieldElement && variable.isEnumConstant) {
    final name = variable.name;
    if (name != null && name.isNotEmpty) return name;
  }
  return null;
}

/// Renders [value] as a single-quoted Dart string literal, escaping
/// backslashes, single quotes, `$` (so it is a literal, not interpolation),
/// and newlines so the emitted default parses byte-stably.
String _dartStringLiteral(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}

/// A concise human-readable reason from a structured type's walk diagnostics,
/// naming the first dropped/unsupported field for the exclusion log.
String _diagnosticReason(List<DiagnosticIR> diagnostics) {
  final first = diagnostics.first;
  final target = first.target;
  return target == null ? first.message : '$target: ${first.message}';
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
