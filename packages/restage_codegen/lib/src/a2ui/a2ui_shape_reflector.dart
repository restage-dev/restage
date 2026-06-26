import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:meta/meta.dart';

import 'package:restage_codegen/src/a2ui/a2ui_event_lowering.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';

/// Why the reflector could not carry a Dart type as an A2UI data shape.
///
/// Each value is a governing-invariant scope-out reason: the reflector accepts
/// a defined shape set and **fails closed — LOUD — outside it** (never a silent
/// drop or a guess). Functions/closures are deliberately NOT here: a callback
/// is the interactivity surface, routed out as an [A2uiShapeEventSurface], not
/// a data scope-out.
///
/// The reasons split into STRUCTURAL (fundamentally unsupportable at this site)
/// and DEFERRED (a should-be-IN capability not yet implemented) — the
/// deferred-vs-structural diagnostic discipline.
enum A2uiShapeScopeOutReason {
  /// STRUCTURAL: `dynamic` or `Object` — no concrete type to read.
  dynamicOrObject,

  /// STRUCTURAL: a positional record / tuple — its fields have no names.
  positionalRecord,

  /// STRUCTURAL: a genuinely unbound (open) type parameter — there is no
  /// concrete type to read, and there never will be at this site. A CONCRETE
  /// instantiation (`List<String>`, or a customer `Box<int>`) resolves and is
  /// accepted — only an open type variable is structurally out.
  unboundGeneric,

  /// STRUCTURAL: a map whose key is not a non-nullable `String` — the keys are
  /// not JSON-object keys.
  nonStringKeyMap,

  /// DEFERRED: a sealed/abstract base — a discriminated-union shape whose
  /// recognition is not yet implemented (a should-be-IN capability, tracked as
  /// a follow-up). Distinct from the structural reasons.
  sealedUnionDeferred,

  /// DEFERRED: a record field that is not a scalar or enum. A record is
  /// reconstructed inline with per-field fallbacks (no helper, no return-null),
  /// so only scalar/enum fields are reconstructable today; records-of-objects /
  /// records-of-lists are the rare richer case, tracked as a follow-up.
  recordNonScalarFieldDeferred,

  /// DEFERRED: an OPTIONAL, NON-nullable constructor parameter whose type is a
  /// nested object / record / recursive value. The value-builder degrades a
  /// missing optional field to a default, but an arbitrary class/record has no
  /// statically-synthesizable default — extracting the real constructor default
  /// is tracked as a follow-up. (A REQUIRED such param is fine — a
  /// missing required value fails the whole object null; a NULLABLE optional
  /// such param is fine — null is the fallback.)
  optionalObjectParamDeferred,

  /// STRUCTURAL: a type outside the accepted shape set with no more specific
  /// reason (an unsupported `dart:` type, an unconstructable class, …).
  unsupported,
}

/// The result of reflecting one Dart type: a resolved data-shape node, a loud
/// scope-out, or the interactivity (event) surface.
@immutable
sealed class A2uiShapeResult {
  const A2uiShapeResult();
}

/// A type that resolved to a data-shape [node].
@immutable
final class A2uiShapeResolved extends A2uiShapeResult {
  /// Creates a resolved result wrapping [node].
  const A2uiShapeResolved(this.node);

  /// The resolved data-shape node.
  final A2uiSchemaNode node;

  @override
  bool operator ==(Object other) =>
      other is A2uiShapeResolved && other.node == node;

  @override
  int get hashCode => node.hashCode;

  @override
  String toString() => 'A2uiShapeResolved($node)';
}

/// A type that was scoped out (fail-closed-loud) with a [reason].
@immutable
final class A2uiShapeScopedOut extends A2uiShapeResult {
  /// Creates a scope-out for [typeDescription] with [reason].
  const A2uiShapeScopedOut(this.reason, this.typeDescription);

  /// Why the type was scoped out.
  final A2uiShapeScopeOutReason reason;

  /// A human-readable description of the offending type, for the diagnostic.
  final String typeDescription;

  @override
  bool operator ==(Object other) =>
      other is A2uiShapeScopedOut &&
      other.reason == reason &&
      other.typeDescription == typeDescription;

  @override
  int get hashCode => Object.hash(reason, typeDescription);

  @override
  String toString() => 'A2uiShapeScopedOut(${reason.name}, $typeDescription)';
}

/// A function / callback-typed field: the interactivity (write-back / dispatch)
/// surface handled by the Phase-2 event layer.
///
/// The deliberate reclassification — a callback is **not** data and is **not**
/// a data scope-out; it is excluded from the data schema and routed to the
/// interactivity layer, so it carries no diagnostic. It carries the
/// [signature], the classified callback disposition the Phase-2 lowering reads
/// (a customer `@RestageWidget` callback's signature is otherwise discarded —
/// the catalog collapses every callback to a bare event property).
@immutable
final class A2uiShapeEventSurface extends A2uiShapeResult {
  /// Creates the event-surface marker carrying its callback [signature].
  const A2uiShapeEventSurface(this.signature);

  /// The classified callback disposition (dispatch / write-back / unsupported).
  final A2uiCallbackSignature signature;

  @override
  bool operator ==(Object other) =>
      other is A2uiShapeEventSurface && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;

  @override
  String toString() => 'A2uiShapeEventSurface($signature)';
}

/// The reflection depth ceiling — a defense against a pathologically deep
/// (but non-cyclic) type graph; cycles are broken earlier by the visited path.
const int _maxReflectDepth = 64;

/// Reflects a resolved Dart [type] into an A2UI data-shape node, a loud
/// scope-out, or the event surface.
///
/// The accepted set (each carried, never silently dropped): scalars, nullable,
/// enums, lists (including lists-of-objects), `Map<String, V>` open
/// dictionaries, named records, and nested data classes — read from the
/// instantiated constructor (so a customer `Box<int>` resolves with its type
/// arguments substituted). Anything else returns an [A2uiShapeScopedOut]; a
/// callback returns an [A2uiShapeEventSurface].
A2uiShapeResult reflectType(DartType type) => _reflect(type, const {}, 0);

/// Reflects [type], threading the visited [path] (canonical type ids on the
/// current branch, for cycle detection → [RefNode]) and the recursion [depth].
A2uiShapeResult _reflect(DartType type, Set<String> path, int depth) {
  if (depth > _maxReflectDepth) {
    return A2uiShapeScopedOut(
      A2uiShapeScopeOutReason.unsupported,
      '${type.getDisplayString()} (exceeds the reflection depth ceiling)',
    );
  }
  final nullable = type.nullabilitySuffix == NullabilitySuffix.question;

  // A function/closure with a signature is the Phase-2 event surface; it
  // carries the classified callback disposition the lowering reads.
  if (type is FunctionType) {
    return A2uiShapeEventSurface(_classifyCallback(type));
  }

  // STRUCTURAL OUT: no concrete type to read.
  if (type is DynamicType || type is InvalidType || type.isDartCoreObject) {
    return A2uiShapeScopedOut(
      A2uiShapeScopeOutReason.dynamicOrObject,
      type.getDisplayString(),
    );
  }

  // STRUCTURAL OUT: an open (unbound) type parameter. A concrete instantiation
  // is an InterfaceType and resolves below.
  if (type is TypeParameterType) {
    return A2uiShapeScopedOut(
      A2uiShapeScopeOutReason.unboundGeneric,
      type.getDisplayString(),
    );
  }

  // Scalars and enums must match before the dart:-library catch-all in the
  // class gate (they ARE dart:core / customer enums).
  final scalar = _scalarTypeOf(type);
  if (scalar != null) {
    return A2uiShapeResolved(ScalarNode(scalar, nullable: nullable));
  }

  final enumNode = _enumNodeOf(type, nullable: nullable);
  if (enumNode != null) {
    // The value-builder emits `<EnumName>.values` into a separate library; a
    // private enum name cannot be referenced there → fail closed.
    if (type is InterfaceType && !_isSpellable(type)) {
      return A2uiShapeScopedOut(
        A2uiShapeScopeOutReason.unsupported,
        '${type.getDisplayString()} (enum not importable into generated code)',
      );
    }
    return A2uiShapeResolved(enumNode);
  }

  if (type is RecordType) {
    if (type.positionalFields.isNotEmpty) {
      return A2uiShapeScopedOut(
        A2uiShapeScopeOutReason.positionalRecord,
        type.getDisplayString(),
      );
    }
    // A private record field label is library-scoped — a `(_x: …)` literal in
    // the generated (separate) library is a different record type than the
    // customer's, so it would not be assignable. Fail closed (same class as the
    // private-type spellability gate).
    final privateLabel = type.namedFields
        .map((f) => f.name)
        .where((name) => name.startsWith('_'));
    if (privateLabel.isNotEmpty) {
      return A2uiShapeScopedOut(
        A2uiShapeScopeOutReason.unsupported,
        '${type.getDisplayString()} (private record field label '
        '"${privateLabel.first}" is not nameable in generated code)',
      );
    }
    // Every named record field is always present → all required.
    return _objectFromFields(
      [
        for (final f in type.namedFields)
          (name: f.name, type: f.type, required: true),
      ],
      defId: null,
      construction: const A2uiRecordConstruction(),
      nullable: nullable,
      path: path,
      depth: depth,
    );
  }

  if (type is InterfaceType) {
    if (type.isDartCoreList && type.typeArguments.length == 1) {
      final element = _reflect(type.typeArguments.single, path, depth + 1);
      return _wrapContainer(
        element,
        type,
        (node) => ListNode(element: node, nullable: nullable),
      );
    }
    if (type.isDartCoreMap && type.typeArguments.length == 2) {
      final key = type.typeArguments[0];
      if (!key.isDartCoreString ||
          key.nullabilitySuffix != NullabilitySuffix.none) {
        return A2uiShapeScopedOut(
          A2uiShapeScopeOutReason.nonStringKeyMap,
          type.getDisplayString(),
        );
      }
      final value = _reflect(type.typeArguments[1], path, depth + 1);
      return _wrapContainer(
        value,
        type,
        (node) => MapNode(valueType: node, nullable: nullable),
      );
    }

    // A bare `Function` (no signature) is still a callback → event surface,
    // but with no signature it cannot be lowered to a declarative action.
    if (type.isDartCoreFunction) {
      return const A2uiShapeEventSurface(
        A2uiCallbackUnsupported('a bare Function has no callback signature'),
      );
    }

    final element = type.element;
    // Any other `dart:` type (Set/Future/FutureOr/Stream/Iterable/Null/…) is
    // outside the data shape set → loud scope-out.
    if (element.library.identifier.startsWith('dart:')) {
      return A2uiShapeScopedOut(
        A2uiShapeScopeOutReason.unsupported,
        type.getDisplayString(),
      );
    }
    if (element is ClassElement) {
      // A sealed / abstract base is a discriminated-union shape; recognition is
      // deferred (loud, deferred-flavored).
      if (element.isAbstract || element.isSealed) {
        return A2uiShapeScopedOut(
          A2uiShapeScopeOutReason.sealedUnionDeferred,
          type.getDisplayString(),
        );
      }
      final id = _canonicalId(type);
      if (path.contains(id)) {
        return A2uiShapeResolved(RefNode(id, nullable: nullable));
      }
      return _objectFromClass(
        type,
        id,
        nullable: nullable,
        path: path,
        depth: depth,
      );
    }
    // A non-class interface type (e.g. an extension type / mixin) → loud.
    return A2uiShapeScopedOut(
      A2uiShapeScopeOutReason.unsupported,
      type.getDisplayString(),
    );
  }

  // void / Never / anything else → loud scope-out (never a silent guess).
  return A2uiShapeScopedOut(
    A2uiShapeScopeOutReason.unsupported,
    type.getDisplayString(),
  );
}

/// Wraps a container element [result] in [build] when it resolved; a container
/// over a scoped-out or event-surface element fails the whole container closed
/// — a collection of callbacks or unsupported values is not data.
A2uiShapeResult _wrapContainer(
  A2uiShapeResult result,
  DartType containerType,
  A2uiSchemaNode Function(A2uiSchemaNode element) build,
) {
  switch (result) {
    case A2uiShapeResolved(:final node):
      return A2uiShapeResolved(build(node));
    case A2uiShapeScopedOut():
      return result;
    case A2uiShapeEventSurface():
      return A2uiShapeScopedOut(
        A2uiShapeScopeOutReason.unsupported,
        containerType.getDisplayString(),
      );
  }
}

/// Reflects a concrete data class [type] (id [id]) from its instantiated
/// generative constructor — substituting type arguments, including
/// super-parameters, and reading required-ness from the params.
A2uiShapeResult _objectFromClass(
  InterfaceType type,
  String id, {
  required bool nullable,
  required Set<String> path,
  required int depth,
}) {
  // The value-builder emits this type's instantiated spelling (helper return
  // type / constructor reference / whereType) into a SEPARATE generated
  // library. A private type or an unbound/phantom type argument cannot be named
  // there, so it must fail closed here rather than emit uncompilable source.
  if (!_isSpellable(type)) {
    return A2uiShapeScopedOut(
      A2uiShapeScopeOutReason.unsupported,
      '${type.getDisplayString()} (not importable into generated code: a '
      'private type or an unbound type argument)',
    );
  }
  final ctor = _usableGenerativeConstructor(type);
  if (ctor == null) {
    return A2uiShapeScopedOut(
      A2uiShapeScopeOutReason.unsupported,
      '${type.getDisplayString()} (no unambiguous generative constructor)',
    );
  }
  final entries = <({String name, DartType type, bool required})>[];
  final parameters = <A2uiConstructorParameter>[];
  var skippedPositional = false;
  for (final p in ctor.formalParameters) {
    final name = p.name;
    if (name == null || name.isEmpty || name.startsWith('_')) {
      // A private/unnameable param the generated (separate-library) code cannot
      // supply: skippable only when optional; a REQUIRED one makes the object
      // unconstructable → fail closed (never emit an object missing a required
      // input).
      if (p.isRequired) {
        return A2uiShapeScopedOut(
          A2uiShapeScopeOutReason.unsupported,
          '${type.getDisplayString()} (required parameter '
          '"${name ?? ''}" is not representable)',
        );
      }
      // A skipped POSITIONAL param shifts every later positional argument, so a
      // representable positional after a skip is unconstructable → fail closed.
      if (!p.isNamed) skippedPositional = true;
      continue;
    }
    if (!p.isNamed && skippedPositional) {
      return A2uiShapeScopedOut(
        A2uiShapeScopeOutReason.unsupported,
        '${type.getDisplayString()} (representable positional parameter '
        '"$name" follows an unrepresentable positional parameter)',
      );
    }
    // The param type is correctly substituted for field-formal and regular
    // params; only a SUPER-formal reports its own type as `dynamic`, so look
    // the inherited field's substituted type up by name (a super-parameter
    // provably names a real inherited field, so the getter is field-induced).
    final fieldType = p is SuperFormalParameterElement
        ? (_inheritedFieldType(type, name) ?? p.type)
        : p.type;
    entries.add((name: name, type: fieldType, required: p.isRequired));
    parameters.add(A2uiConstructorParameter(name: name, named: p.isNamed));
  }
  final ctorName = ctor.name;
  return _objectFromFields(
    entries,
    defId: id,
    construction: A2uiClassConstruction(
      dartTypeName: _instantiatedTypeName(type),
      libraryUri: type.element.library.identifier,
      constructorName:
          (ctorName == null || ctorName.isEmpty || ctorName == 'new')
              ? null
              : ctorName,
      parameters: parameters,
    ),
    nullable: nullable,
    path: {...path, id},
    depth: depth,
  );
}

/// Whether [type]'s instantiated spelling is importable into the generated
/// (separate-library) source. A PRIVATE type, or an unbound/phantom TYPE
/// ARGUMENT, cannot be named there — the value-builder would emit `_Private`,
/// `Box<_Private>`, or `Box<T>` and fail to compile in the customer's build —
/// so the whole type graph (the type and every type argument, recursively) must
/// be spellable. Bare tokens (`dynamic`/`void`/`Never`) are spellable but do not
/// reach a data-class spelling.
bool _isSpellable(DartType type) {
  if (type is TypeParameterType) return false;
  if (type is InterfaceType) {
    final name = type.element.name;
    if (name == null || name.isEmpty || name.startsWith('_')) return false;
    return type.typeArguments.every(_isSpellable);
  }
  if (type is RecordType) {
    return type.positionalFields.every((f) => _isSpellable(f.type)) &&
        type.namedFields.every((f) => _isSpellable(f.type));
  }
  return true;
}

/// The instantiated, NON-null Dart type spelling for a data-class [type] — e.g.
/// `Box<int>` for a `Box<int>` field, not the raw `Box` (the value-builder
/// emits this as a helper return type / constructor reference / `whereType<T>`,
/// and a raw `Box` is not assignable to a `Box<int>` parameter). The node's own
/// `nullable` flag carries outer nullability, so the trailing `?` is stripped.
String _instantiatedTypeName(InterfaceType type) {
  final display = type.getDisplayString();
  return display.endsWith('?')
      ? display.substring(0, display.length - 1)
      : display;
}

/// The substituted type of an INHERITED field [name] (for a super-parameter),
/// found by walking the instantiated supertypes. Restricted to supertypes (not
/// the subclass's own accessors) so it never picks up a same-named computed
/// getter on the subclass.
DartType? _inheritedFieldType(InterfaceType type, String name) {
  for (final supertype in type.allSupertypes) {
    final inherited = supertype.getGetter(name);
    if (inherited != null) return inherited.returnType;
  }
  return null;
}

/// The canonical generative constructor for a data class, or null when there is
/// no unambiguous choice (factory-only / none, or several named generatives
/// with no default). Never picks arbitrarily.
ConstructorElement? _usableGenerativeConstructor(InterfaceType type) {
  final generative = [
    // Exclude factories (not a settable shape) and PRIVATE constructors (the
    // generated, separate-library code cannot call a private constructor).
    for (final c in type.constructors)
      if (!c.isFactory && !(c.name?.startsWith('_') ?? false)) c,
  ];
  if (generative.isEmpty) return null;
  for (final c in generative) {
    final name = c.name;
    if (name == null || name.isEmpty || name == 'new') return c;
  }
  return generative.length == 1 ? generative.single : null;
}

/// Builds an [ObjectNode] from named field entries (each with its required
/// flag), reflecting every field type. A scoped-out field fails the whole
/// object closed (loud); a callback field is excluded (the event surface).
A2uiShapeResult _objectFromFields(
  List<({String name, DartType type, bool required})> entries, {
  required String? defId,
  required A2uiObjectConstruction construction,
  required bool nullable,
  required Set<String> path,
  required int depth,
}) {
  final fields = <String, A2uiSchemaNode>{};
  final required = <String>{};
  for (final entry in entries) {
    final result = _reflect(entry.type, path, depth + 1);
    switch (result) {
      case A2uiShapeResolved(:final node):
        final unbuildable = _buildabilityScopeOut(construction, entry, node);
        if (unbuildable != null) return unbuildable;
        fields[entry.name] = node;
        if (entry.required) required.add(entry.name);
      case A2uiShapeScopedOut():
        return result;
      case A2uiShapeEventSurface():
        // A callback buried in a data object cannot be routed to the event
        // layer (there is no caller mid-recursion) and the object cannot be
        // constructed without it — fail the whole object closed, never drop
        // the field silently.
        return A2uiShapeScopedOut(
          A2uiShapeScopeOutReason.unsupported,
          '${entry.name}: ${entry.type.getDisplayString()} '
          '(callback field inside a data object)',
        );
    }
  }
  return A2uiShapeResolved(
    ObjectNode(
      fields: fields,
      required: required,
      defId: defId,
      construction: construction,
      nullable: nullable,
    ),
  );
}

/// A loud DEFERRED scope-out when a resolved field [node] is structurally fine
/// but the value-builder has no fail-safe way to reconstruct it at this site —
/// so neither a schema nor a builder is emitted for it (no schema/builder
/// divergence). Returns null when the field is buildable.
A2uiShapeScopedOut? _buildabilityScopeOut(
  A2uiObjectConstruction construction,
  ({String name, DartType type, bool required}) entry,
  A2uiSchemaNode node,
) {
  // R-a: a RECORD is reconstructed inline with per-field fallbacks (no helper,
  // no return-null), so only a scalar/enum field is reconstructable.
  if (construction is A2uiRecordConstruction &&
      node is! ScalarNode &&
      node is! EnumNode) {
    return A2uiShapeScopedOut(
      A2uiShapeScopeOutReason.recordNonScalarFieldDeferred,
      '${entry.name}: ${entry.type.getDisplayString()} '
      '(a record field must be a scalar or enum)',
    );
  }
  // R-b: an OPTIONAL, NON-nullable object/record/recursive CLASS param has no
  // statically-synthesizable default for the absent case.
  if (construction is A2uiClassConstruction &&
      !entry.required &&
      !node.nullable &&
      (node is ObjectNode || node is RefNode)) {
    return A2uiShapeScopedOut(
      A2uiShapeScopeOutReason.optionalObjectParamDeferred,
      '${entry.name}: ${entry.type.getDisplayString()} '
      '(optional non-null object parameter has no synthesizable default)',
    );
  }
  return null;
}

/// Classifies a callback [type] into the disposition the lowering reads.
///
/// A 0-argument callback dispatches an event; a single-positional value
/// callback (`ValueChanged<T>` = `void Function(T)`) whose value `T` is a
/// scalar or a `List<scalar>` writes the value back; any other shape —
/// multiple arguments, a named/optional argument, or a non-scalar value — is
/// unsupported and fails loud before lowering (never treated as a dispatch).
A2uiCallbackSignature _classifyCallback(FunctionType type) {
  // A `VoidCallback` / `ValueChanged<T>` returns void (a setter, not a
  // transformer). A value-returning callback is not one of those shapes and
  // would emit an unassignable void-returning lambda → unsupported.
  if (type.returnType is! VoidType) {
    return A2uiCallbackUnsupported(
      '${type.getDisplayString()} does not return void',
    );
  }
  final parameters = type.formalParameters;
  if (parameters.isEmpty) return const A2uiCallbackDispatch();
  // A `ValueChanged<T>` takes exactly one REQUIRED POSITIONAL value argument;
  // a named or optional argument is not that shape.
  if (parameters.length != 1 || !parameters.single.isRequiredPositional) {
    return A2uiCallbackUnsupported(
      '${type.getDisplayString()} is neither a 0-argument dispatch callback '
      'nor a single-value ValueChanged',
    );
  }
  final value = parameters.single.type;
  final nullable = value.nullabilitySuffix == NullabilitySuffix.question;
  final scalar = _scalarTypeOf(value);
  if (scalar != null) {
    return A2uiCallbackWriteBack(scalar, nullable: nullable, isList: false);
  }
  if (value is InterfaceType &&
      value.isDartCoreList &&
      value.typeArguments.length == 1) {
    final element = _scalarTypeOf(value.typeArguments.single);
    if (element != null) {
      return A2uiCallbackWriteBack(element, nullable: nullable, isList: true);
    }
  }
  return A2uiCallbackUnsupported(
    'callback value type ${value.getDisplayString()} is not a scalar or a '
    'List<scalar>',
  );
}

/// The JSON scalar category for a core scalar [type], or null.
A2uiScalarType? _scalarTypeOf(DartType type) {
  if (type.isDartCoreBool) return A2uiScalarType.boolean;
  if (type.isDartCoreInt) return A2uiScalarType.integer;
  if (type.isDartCoreDouble || type.isDartCoreNum) return A2uiScalarType.number;
  if (type.isDartCoreString) return A2uiScalarType.string;
  return null;
}

/// An [EnumNode] for an enum [type], or null when [type] is not an enum.
EnumNode? _enumNodeOf(DartType type, {required bool nullable}) {
  if (type is! InterfaceType) return null;
  final element = type.element;
  if (element is! EnumElement) return null;
  final members = element.fields
      .where((f) => f.isEnumConstant)
      .map((f) => f.name)
      .whereType<String>()
      .toList(growable: false);
  return EnumNode(
    members: members,
    dartTypeName: element.name ?? '<unnamed>',
    libraryUri: element.library.identifier,
    nullable: nullable,
  );
}

/// The canonical identity for an interface [type] — `<libraryUri>#<symbol>`,
/// with type arguments recursively canonicalized (NOT by display text, which
/// is not collision-safe across same-named types from different libraries).
String _canonicalId(InterfaceType type) {
  final element = type.element;
  final base = '${element.library.identifier}#${element.name ?? '<unnamed>'}';
  if (type.typeArguments.isEmpty) return base;
  final args = type.typeArguments.map(_typeArgId).join(',');
  return '$base<$args>';
}

/// The identity fragment for a type argument — recursive for interface types,
/// best-effort display for the rest (type params, dynamic, …).
///
/// A type argument's nullability is part of the SHAPE (`Box<String>` and
/// `Box<String?>` are different shapes), so it is included here — whereas a
/// type's OWN outer nullability is carried by the node's `nullable` flag and is
/// deliberately NOT in [_canonicalId] (`Box<int>` and `Box<int>?` are the same
/// shape for cycle/definition purposes).
String _typeArgId(DartType type) {
  if (type is InterfaceType) {
    final suffix =
        type.nullabilitySuffix == NullabilitySuffix.question ? '?' : '';
    return '${_canonicalId(type)}$suffix';
  }
  // getDisplayString() already carries the nullability suffix for non-interface
  // types (e.g. `T?`).
  return type.getDisplayString();
}
