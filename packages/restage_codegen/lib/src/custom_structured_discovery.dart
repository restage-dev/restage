import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/custom_map_plan.dart';
import 'package:restage_codegen/src/custom_record_plan.dart';
import 'package:restage_codegen/src/custom_structured_admissibility.dart'
    show structuredSlotKey;
import 'package:restage_codegen/src/custom_structured_reconstruction.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/theme_recognition.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';
import 'package:rfw_catalog_compiler/rfw_catalog_compiler.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// The catalog shape a custom `@RestageProperty` field lowers to when its
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

/// Discovers the custom structured types reachable from a library's
/// `@RestageWidget` property fields and lowers them to catalog
/// [StructuredEntry]/[UnionEntry] values (with unallocated wire IDs).
///
/// This is the custom-path analogue of the built-in widget reflector's
/// structured production: it seeds a [StructuredWalkPolicy] with the
/// discovered custom data-class identities, then drives the public
/// [walkStructuredType]/[lowerStructured] machinery. The wire IDs stay
/// unallocated here; a later allocation pass mints them.
@immutable
final class CustomStructuredDiscovery {
  const CustomStructuredDiscovery._({
    required this.structuredTypes,
    required this.unions,
    required this.slotTargets,
    required this.nullableStructuredSlots,
    required this.localUnrenderable,
    required this.reconstructionPlans,
    required this.mapPlans,
    required this.recordPlans,
    required PolicyLedger policy,
    required Map<String, String> libraryNamespaceByFqn,
  })  : _policy = policy,
        _libraryNamespaceByFqn = libraryNamespaceByFqn;

  /// An empty discovery — no custom structured types were found.
  const CustomStructuredDiscovery.empty()
      : structuredTypes = const [],
        unions = const [],
        slotTargets = const {},
        nullableStructuredSlots = const {},
        localUnrenderable = const {},
        reconstructionPlans = const {},
        mapPlans = const {},
        recordPlans = const {},
        _policy = const PolicyLedger.builtIn(),
        _libraryNamespaceByFqn = const {};

  /// The discovered structured types (unallocated wire IDs).
  final List<StructuredEntry> structuredTypes;

  /// The discovered unions (unallocated wire IDs).
  final List<UnionEntry> unions;

  /// Maps each nominal `PropertyType.structured` slot — a widget property or a
  /// nested structured field, keyed `'<ownerFqn>.<slotName>'` — to its target
  /// structured type's `sourceType` FQN. A nested map field may also leave an
  /// inert collector entry here; map consumers read only [mapPlans].
  final Map<String, String> slotTargets;

  /// The subset of WIDGET structured-property slot keys (same
  /// `'<widgetFlutterType>.<propName>'` convention) whose Dart type is NULLABLE
  /// (`Badge?`). A build-time-only signal (never a wire field): the factory
  /// presence-checks a nullable widget structured prop to `null` on an absent
  /// map instead of reconstructing unconditionally (which would crash on an
  /// absent nested-required leaf). Nested-field nullability travels via the
  /// reconstruction plan; this covers only the level-0 widget prop.
  final Set<String> nullableStructuredSlots;

  /// Structured types carrying an inner field that cannot be lowered — keyed
  /// by `sourceType`, value a human-readable reason. Two paths populate this:
  /// the walker warn+drops an unsupported field, and an
  /// out-of-boundary record field is recorded directly without going through
  /// the walker's diagnostics. A type here is not fully renderable on the RFW
  /// path; the recursive gate excludes any widget whose closure reaches one.
  final Map<String, String> localUnrenderable;

  /// The build-time reconstruction recipe for each renderable structured type,
  /// keyed by `sourceType`. Derived from the SAME analyzer walk as the
  /// admissibility predicate (so they can't disagree), it carries the ctor arg
  /// kind/order the factory emitter needs but the (empty) wire `parameters`
  /// don't. A type whose plan can't place a required param is excluded-loud
  /// instead (a predicate gap), never given a partial plan.
  final Map<String, ReconstructionPlan> reconstructionPlans;

  /// The build-time map reconstruction recipe for each map slot.
  final Map<String, MapPlan> mapPlans;

  /// The build-time record reconstruction recipe for each record slot.
  final Map<String, RecordPlan> recordPlans;

  final PolicyLedger _policy;

  /// The walk policy, exposed so a widget-property map classification can be
  /// decided against the same policy the structured walk used. Without it the
  /// classifier cannot tell a custom data class from any other type, and a
  /// map of one is refused as an unsupported value.
  PolicyLedger get policy => _policy;
  final Map<String, String> _libraryNamespaceByFqn;

  /// The structured property shape for [fieldType], or `null` when the field
  /// is not a discovered structured value (the caller falls back to scalar /
  /// enum / widget / event inference).
  StructuredPropertyShape? shapeFor(DartType fieldType) {
    final itemType = listItemType(fieldType);
    final targetType = itemType ?? fieldType;
    if (classifyStructured(targetType, _policy) != StructuredKind.concrete) {
      return null;
    }
    final fqn = typeFqn(targetType);
    if (fqn == null) return null;
    final libraryNamespace = _libraryNamespaceByFqn[fqn];
    if (libraryNamespace == null) return null;
    final ref = WireIdRef(
      library: libraryNamespace,
      wireId: WireId.unallocatedStructured,
    );
    if (itemType != null) {
      return StructuredPropertyShape(
        type: PropertyType.unknown,
        valueShape: ListShape.opaqueStructured(ref),
      );
    }
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

/// A discovered custom structured root: the data-class element plus the
/// custom library namespace of the `@RestageWidget` that references it.
class _StructuredRoot {
  _StructuredRoot(this.element, this.libraryNamespace);

  final ClassElement element;
  final String libraryNamespace;
}

/// The innermost value type of a (possibly nested) `Map`, or null when [type]
/// is not a map.
///
/// Bounded rather than recursive without limit, for the same reason the alias
/// unwrapper is: a pathological type must terminate rather than spin. On
/// hitting the bound this yields the type reached there rather than null —
/// null means "not a map", and reporting that for a map nested past the bound
/// would seed discovery with the wrong type instead of a deeper one.
DartType? _mapValueSeedType(DartType type) {
  final first = mapValueType(type);
  if (first == null) return null;
  // Held in a non-nullable local: reassigning the nullable one inside the loop
  // would drop its promotion and the next read would not compile.
  var current = first;
  for (var i = 0; i < 8; i++) {
    final next = mapValueType(current);
    if (next == null) return current;
    current = next;
  }
  return current;
}

/// Walks [widgetClasses]' constructor-bound inputs, discovers the custom
/// structured value types they reference (transitively, so a data class that
/// nests another data class materialises both), and lowers each to a catalog
/// [StructuredEntry] (unallocated).
CustomStructuredDiscovery discoverCustomStructured({
  required List<ClassElement> widgetClasses,
  required Map<ClassElement, List<WidgetConstructorInput>> widgetInputs,
  required AssetId assetId,
  required List<Issue> issues,
  Map<ClassElement, WidgetLibrary>? widgetLibraries,
}) {
  // The transitive closure of custom data-class identities reachable from
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
  final mapPlans = <String, MapPlan>{};

  // Adds [type]'s class to the closure when it is a custom data class, and
  // returns the resolved element (or `null` when [type] is not a custom data
  // class) so the caller can reuse it without re-resolving.
  ClassElement? addDataClass(DartType type, String libraryNamespace) {
    final element = classElementFor(listItemType(type) ?? type);
    if (element == null || !_isCustomDataClass(element)) return null;
    final fqn = elementFqn(element);
    if (!closure.containsKey(fqn)) {
      closure[fqn] = _StructuredRoot(element, libraryNamespace);
      worklist.add(element);
    }
    return element;
  }

  // First pass: seed from constructor-bound input types, and record each
  // structured widget property's slot target so a later pass can resolve its
  // bare sentinel `structuredRef`. The owner key is the widget's `flutterType`
  // (`'<library URI>#<class name>'`, == `elementFqn`) so it matches
  // `WidgetEntry.flutterType` at resolution time.
  for (final cls in widgetClasses) {
    final libraryNamespace =
        widgetLibraries?[cls]?.namespace ?? _widgetLibraryNamespace(cls);
    if (libraryNamespace == null) continue;
    final ownerFqn = elementFqn(cls);
    for (final input in widgetInputs[cls] ?? const <WidgetConstructorInput>[]) {
      // A widget property's innermost map value is seeded here so a data-class
      // value is discoverable. The transitive pass below applies the same rule
      // to map fields nested inside data classes.
      final mapValueSeed = _mapValueSeedType(input.type);
      final targetElement =
          addDataClass(mapValueSeed ?? input.type, libraryNamespace);
      final fieldName = input.name;
      // The nominal slot bookkeeping below applies to nominal structured slots
      // only. A map slot carries its target through its own build-time recipe,
      // so recording it here too would give the same fact two homes that can
      // disagree.
      if (mapValueSeed == null &&
          targetElement != null &&
          fieldName.isNotEmpty) {
        final slotKey = structuredSlotKey(ownerFqn, fieldName);
        slotTargets[slotKey] = elementFqn(targetElement);
        // A build-time signal (never a wire field): an optional NULLABLE
        // widget structured prop yields `null` on an absent map, so the factory
        // must presence-check to null rather than reconstruct unconditionally.
        if (_isNullable(input.type)) nullableStructuredSlots.add(slotKey);
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

  if (closure.isEmpty) return const CustomStructuredDiscovery.empty();

  // Policy pass: seed the structured-walk policy with the FULL closure so the
  // walker classifies every custom identity (root or nested) as concrete.
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
  final recordPlans = <String, RecordPlan>{};
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

      // Materialized once and shared by both passes below: the generator
      // rebuilds the generative-parameter name set from every constructor on
      // each enumeration, and this root's fields do not change between them.
      final structuredFields = _structuredFields(root.element).toList();

      // Map and record fields stay disjoint from nominal structured fields.
      // Their reconstruction identities live in their slot-keyed sidecars.
      for (final field in structuredFields) {
        final mapClassification = classifyMapType(
          field.type,
          structuredValuesAdmitted: false,
        );
        if (mapClassification case final MapAdmitted admitted) {
          mapPlans[structuredSlotKey(lowered.sourceType, field.name)] =
              mapPlanFromClassification(admitted);
        }
        final classification = classifyRecordType(
          field.type,
          library: library,
          policy: policy,
        );
        if (classification case final RecordAdmitted admitted) {
          recordPlans[structuredSlotKey(lowered.sourceType, field.name)] =
              recordPlanFromClassification(admitted);
        }
        if (classification case RecordExcluded(:final reason)) {
          recordUnrenderable('record field "${field.name}": $reason');
        }
      }

      // The walker records a diagnostic and drops an unsupported inner field
      // rather than failing the build. A dropped field means the lowered entry
      // is missing state, so the type is not fully renderable.
      if (ir.diagnostics.isNotEmpty) {
        recordUnrenderable(_diagnosticReason(ir.diagnostics));
      }
      final materializedFieldNames = {
        for (final field in lowered.fields) field.name,
      };
      // Every constructor a value can be rebuilt through.
      final constructorPlans = reconstructionPlanFor(
        root.element,
        materializedFieldNames,
      );
      final plan = constructorPlans.plan;
      if (plan == null) {
        recordUnrenderable(constructorPlans.reason);
      } else {
        reconstructionPlans[lowered.sourceType] = plan;
      }
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
      // Record each nested structured field's slot target for ref resolution.
      for (final (fieldName, targetFqn)
          in _structuredFieldTargets(structuredFields)) {
        slotTargets[structuredSlotKey(lowered.sourceType, fieldName)] =
            targetFqn;
      }
    }
  }

  return CustomStructuredDiscovery._(
    structuredTypes: List.unmodifiable(structuredByFqn.values),
    unions: const [],
    slotTargets: Map.unmodifiable(slotTargets),
    nullableStructuredSlots: Set.unmodifiable(nullableStructuredSlots),
    localUnrenderable: Map.unmodifiable(localUnrenderable),
    reconstructionPlans: Map.unmodifiable(reconstructionPlans),
    mapPlans: Map.unmodifiable(mapPlans),
    recordPlans: Map.unmodifiable(recordPlans),
    policy: policy,
    libraryNamespaceByFqn: libraryNamespaceByFqn,
  );
}

/// Maps one admitted map classification to the build-time sidecar consumed by
/// the generated factory.
MapPlan mapPlanFromClassification(MapAdmitted classification) {
  final keys = <MapKeyPlan>[];
  var current = classification;
  while (true) {
    keys.add((enumRef: current.keyEnumRef));
    // Descend through the classification the caller already computed. It was
    // classified WITH the library and policy, which the custom-structured
    // branch requires; re-classifying here would drop both and mis-read a
    // nested map of a custom data class as excluded, leaving the outer
    // map's own opaque marker as the terminal value shape.
    final nested = current.nestedValue;
    if (nested != null) {
      current = nested;
      continue;
    }
    final shape = current.valueShape;
    final valueElement = classElementFor(current.valueType);
    // A map value is only ever a scalar, an enum, a nested map, or a custom
    // data class: the classifier excludes every other shape before a plan
    // exists, so a list value cannot reach here.
    final valueSourceType = shape is StructuredShape && valueElement != null
        ? elementFqn(valueElement)
        : null;
    return (
      keys: List<MapKeyPlan>.unmodifiable(keys),
      valueShape: shape,
      valueSourceType: valueSourceType,
    );
  }
}

/// Maps one admitted record classification to the build-time sidecar the
/// generated factory consumes.
///
/// Both widget properties and nested structured fields call this conversion on
/// the same admitted verdict that produced their catalog slot, so the emitted
/// label set and the recognized value shape cannot disagree.
RecordPlan recordPlanFromClassification(RecordAdmitted classification) => (
      labels: List<RecordLabelPlan>.unmodifiable(
        classification.labels.map((label) {
          final shape = label.shape;
          final enumShape = shape is EnumShape ? shape : null;
          return (
            name: label.name,
            type: shape.propertyType,
            shape: shape,
            enumLibraryUri: enumShape?.enumRef.libraryUri,
            enumTypeName: enumShape?.enumRef.symbolName,
          );
        }),
      ),
    );

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

/// The `(fieldName, targetSourceType)` for each of [fields] whose direct,
/// list-item, or innermost map-value type is a custom data class.
/// Nominal slots use these targets to resolve bare structured references; a
/// map entry produced by the shared collector is inert.
///
/// Takes the already-materialized fields rather than the owning element so the
/// caller enumerates them once and shares them across its passes.
Iterable<(String, String)> _structuredFieldTargets(
  Iterable<({String name, DartType type})> fields,
) sync* {
  for (final field in fields) {
    final targetElement = classElementFor(
      _mapValueSeedType(field.type) ?? listItemType(field.type) ?? field.type,
    );
    if (targetElement == null || !_isCustomDataClass(targetElement)) continue;
    yield (field.name, elementFqn(targetElement));
  }
}

/// Why [ctor] cannot rebuild a value from its fields by name, else `null`.
///
/// A factory may transform its input, and every parameter must name a field.
/// With [byFields] the value is encoded field by field, so every field must
/// also name a parameter; otherwise the wire carries the constructor's own
/// arguments, so every parameter must name a field of the same type.
String? _reconstructionObstruction(
  ConstructorElement ctor,
  Set<String?> fieldNames, {
  required bool byFields,
}) {
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
  if (!byFields) {
    for (final parameter in ctor.formalParameters) {
      final name = parameter.name;
      if (name == null || !fieldNames.contains(name)) {
        return 'constructor "${targetName ?? 'new'}" parameter '
            '"${name ?? '<positional>'}" has no matching field';
      }
      final field = ctor.enclosingElement.getField(name);
      if (field == null ||
          _nonNullDisplay(field.type) != _nonNullDisplay(parameter.type)) {
        return 'constructor "${targetName ?? 'new'}" parameter "$name" '
            "does not have its field's type";
      }
    }
    return positionalHoleReason(ctor, fieldNames);
  }
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

/// The reconstruction plan for [element], or the reason it has none.
///
/// The unnamed constructor rebuilds a value from its fields. Each public named
/// constructor that can be called with the value's arguments is listed too,
/// selected on the wire by [kStructuredConstructorKey].
({ReconstructionPlan? plan, String? reason}) reconstructionPlanFor(
  ClassElement element,
  Set<String?> materializedFieldNames,
) {
  List<ReconstructionArg>? unnamedArgs;
  String? firstReason;
  final named = <String, List<ReconstructionArg>>{};
  for (final constructor in element.constructors) {
    final name = _normalizedCtorName(constructor);
    if (name != null && name.startsWith('_')) continue;
    if (constructor.redirectedConstructor != null) continue;
    if (constructor.isFactory && name != null) continue;
    final result = constructorPlan(constructor, materializedFieldNames);
    if (result.args == null) {
      firstReason ??= result.reason;
      continue;
    }
    if (name == null) {
      unnamedArgs = result.args;
    } else {
      named[name] = result.args!;
    }
  }
  if (unnamedArgs == null && named.isEmpty) {
    return (
      plan: null,
      reason: firstReason ?? 'no constructor can rebuild a value',
    );
  }
  // Without an unnamed constructor the primary is the alphabetically first
  // named one, the constructor a value without a selector was built through.
  final firstNamed = (named.keys.toList()..sort()).firstOrNull;
  final primary = unnamedArgs != null
      ? (name: null, args: unnamedArgs)
      : (name: firstNamed, args: named[firstNamed]!);
  return (
    plan: (
      namedConstructor: primary.name,
      args: primary.args,
      hasUnnamed: unnamedArgs != null,
      constructors: named,
    ),
    reason: null,
  );
}

/// The arguments [constructor] rebuilds a value with, or the reason it cannot.
///
/// The encoder and the generated decoder both call this, so a constructor the
/// encoder writes is always one the decoder reads.
({List<ReconstructionArg>? args, String? reason}) constructorPlan(
  ConstructorElement constructor,
  Set<String?> fieldNames,
) {
  final obstruction = _reconstructionObstruction(
    constructor,
    fieldNames,
    byFields: _normalizedCtorName(constructor) == null,
  );
  if (obstruction != null) return (args: null, reason: obstruction);
  return _buildConstructorArgs(constructor, fieldNames);
}

String _nonNullDisplay(DartType type) {
  final display = type.getDisplayString();
  return display.endsWith('?')
      ? display.substring(0, display.length - 1)
      : display;
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

/// The arguments [ctor] is called with, in declaration order, each sourced
/// from its same-named field. An optional non-nullable parameter carries its
/// reproduced default. Returns a reason instead when a required parameter has
/// no field or a default cannot be reproduced.
({List<ReconstructionArg>? args, String? reason}) _buildConstructorArgs(
  ConstructorElement ctor,
  Set<String?> materializedFieldNames,
) {
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
      // primitive literal, or a custom-enum constant the emitter qualifies
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
            args: null,
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
        args: null,
        reason: 'required constructor parameter "${name ?? '<positional>'}" '
            'has no matching field',
      );
    }
    // else: optional + no field -> omit (the ctor default applies).
  }
  return (args: args, reason: null);
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
/// re-parseable form independent of the app's source spelling.
String? _reproducibleDefaultLiteral(FormalParameterElement parameter) {
  final value = parameter.computeConstantValue();
  if (value == null) return null;
  final items = value.toListValue();
  if (items != null) return _reproducibleScalarListLiteral(parameter, items);
  return _primitiveLiteral(value);
}

/// A `const <T>[...]` literal for a scalar-list default, or `null`.
String? _reproducibleScalarListLiteral(
  FormalParameterElement parameter,
  List<DartObject> items,
) {
  final type = parameter.type;
  if (type is! InterfaceType || type.typeArguments.length != 1) return null;
  final item = type.typeArguments.single;
  final scalar = item.isDartCoreString ||
      item.isDartCoreBool ||
      item.isDartCoreInt ||
      item.isDartCoreDouble ||
      item.isDartCoreNum;
  if (!scalar || item.nullabilitySuffix != NullabilitySuffix.none) return null;
  final literals = <String>[];
  for (final value in items) {
    final literal = _primitiveLiteral(value);
    if (literal == null) return null;
    literals.add(literal);
  }
  return 'const <${item.getDisplayString()}>[${literals.join(', ')}]';
}

String? _primitiveLiteral(DartObject value) {
  final stringValue = value.toStringValue();
  if (stringValue != null) return dartStringLiteral(stringValue);
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
  final annotation = _catalogAnnotation(cls, 'RestageWidget');
  return annotation
      ?.computeConstantValue()
      ?.getField('library')
      ?.getField('namespace')
      ?.toStringValue();
}

/// Whether [element] is a custom data class — a concrete, non-`dart:`/
/// non-`package:flutter/` class with at least one generative-constructor
/// parameter (i.e. it carries value state). A class with no constructor
/// parameters (`Mystery {}`) is NOT a data class and falls through to the
/// caller's existing unsupported-type handling.
bool _isCustomDataClass(ClassElement element) {
  if (element.isAbstract) return false;
  final libraryId = element.library.identifier;
  // The design packages carry copies of the framework's own value types, and
  // one of those has exactly the shape this predicate looks for: a generative
  // constructor with parameters, declared outside the framework's own library
  // prefix. Admitting it produces a structured entry keyed to the design
  // package, which no catalog entry names, and the widget carrying it is
  // dropped at admission with nothing to point at.
  if (libraryId.startsWith('dart:') ||
      kFrameworkLibraryPrefixes.any(libraryId.startsWith)) {
    return false;
  }
  return element.constructors.any(
    (constructor) =>
        !constructor.isFactory && constructor.formalParameters.isNotEmpty,
  );
}

const _catalogSchemaOrigin = 'package:rfw_catalog_schema';

ElementAnnotation? _catalogAnnotation(Element element, String name) =>
    firstAnnotationFromOriginAny(
      element,
      {name},
      _catalogSchemaOrigin,
    );
