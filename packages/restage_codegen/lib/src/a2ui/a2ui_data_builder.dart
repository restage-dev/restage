import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';

/// Whether [uri] is a CUSTOMER library that the generated file imports with a
/// prefix. Flutter, `dart:`, genui, and `json_schema_builder` are imported
/// unprefixed — they are framework/runtime libraries with no collision risk and
/// keeping them bare leaves the built-in (flutter-only) catalogs byte-neutral.
bool isPrefixableLibrary(String uri) =>
    !uri.startsWith('dart:') &&
    !uri.startsWith('package:flutter/') &&
    !uri.startsWith('package:genui/') &&
    !uri.startsWith('package:json_schema_builder/');

/// Spells [typeName] (a leading type identifier optionally followed by
/// dart:core-argument generics, e.g. `PlanTier` or `Box<int>`) qualified by the
/// import prefix assigned to [libraryUri] in [prefixes], or bare when the
/// library is unprefixed. The prefix qualifies the LEADING identifier (Dart
/// parses `p0.Box<int>` as `(p0.Box)<int>`); a customer TYPE ARGUMENT cannot be
/// prefixed from the flat spelling and is rejected upstream by the
/// prefixability guard, never reaching here.
String prefixedType(
  String typeName,
  String? libraryUri,
  Map<String, String> prefixes,
) {
  final prefix = libraryUri == null ? null : prefixes[libraryUri];
  return prefix == null ? typeName : '$prefix.$typeName';
}

/// Generates the Dart source that reconstructs a typed value from decoded
/// (untrusted) genui JSON at render time, for a widget's rich data shapes.
///
/// The contract is RUNTIME fail-SAFE — graceful degradation, never a thrown
/// cast — distinct from the compile-time fail-closed-LOUD reflector, which has
/// already scoped out unsupported SHAPES before the builder sees a node. The
/// spine is the optional/required asymmetry: a missing OPTIONAL field degrades
/// to a default (the author sanctioned one); a missing REQUIRED field fails the
/// whole object null (load-bearing data is never fabricated), propagating up to
/// a widget-level fail-safe.
///
/// Built from a widget's data-shape roots. The builder discovers every nested
/// data class (one generated helper per class type) and which runtime helpers
/// it references, then emits only what it uses.
class A2uiDataBuilder {
  /// Builds a value-builder over a widget's data-shape [roots].
  ///
  /// [prefixes] maps each customer `libraryUri` to its import prefix (`p0`,
  /// `p1`, …); the builder spells every customer type qualified by it, so two
  /// same-named classes from different libraries can never collide in the
  /// generated source. Empty (the default) emits bare spellings — used when no
  /// rich shape is present.
  A2uiDataBuilder(
    Iterable<A2uiSchemaNode> roots, {
    Map<String, String> prefixes = const {},
  }) : _prefixes = prefixes {
    roots.forEach(_walk);
    _assignClassHelpers();
  }

  /// libraryUri → import prefix for the customer libraries the spellings carry.
  final Map<String, String> _prefixes;

  /// The generated runtime recursion-depth ceiling (a defense against a
  /// pathologically deep render-time JSON graph; cycles are bounded by it too).
  static const int _maxBuildDepth = 64;

  /// Whether any reconstruction references the typed-cast runtime helper.
  bool _usesTypedCast = false;

  /// Whether a non-null-value map references the drop-null map helper.
  bool _usesMap = false;

  /// Whether a nullable-value map references the keep-null map helper.
  bool _usesMapNullable = false;

  /// Every nested data CLASS reachable from the roots, keyed by its canonical
  /// `defId` (deduped — a shared/recursive class registers once). Records carry
  /// no `defId` and are reconstructed inline, so they are not registered here.
  final Map<String, ObjectNode> _classes = {};

  /// The collision-safe helper name per class `defId`.
  final Map<String, String> _classHelperNames = {};

  /// Walks [node] to discover referenced helpers and nested class types.
  void _walk(A2uiSchemaNode node) {
    switch (node) {
      case ScalarNode():
        _usesTypedCast = true;
      case EnumNode():
        _usesTypedCast = true;
      case ListNode(:final element):
        _usesTypedCast = true;
        _walk(element);
      case MapNode(:final valueType):
        _usesTypedCast = true;
        if (valueType.nullable) {
          _usesMapNullable = true;
        } else {
          _usesMap = true;
        }
        _walk(valueType);
      case ObjectNode(:final construction, :final fields, :final defId):
        _usesTypedCast = true;
        if (construction is A2uiClassConstruction && defId != null) {
          // Register each class once; its fields (and any recursion, broken by
          // a RefNode leaf) are walked once.
          if (!_classes.containsKey(defId)) {
            _classes[defId] = node;
            fields.values.forEach(_walk);
          }
        } else {
          // A record is reconstructed inline — walk its (scalar/enum) fields.
          fields.values.forEach(_walk);
        }
      case RefNode():
        // A RefNode references an already-registered class (its definition is
        // an ancestor in the tree); the value-builder reuses that helper.
        _usesTypedCast = true;
      case UnionNode():
        // Unreachable: the reflector scopes unions out before the builder.
        break;
    }
  }

  /// Assigns a collision-safe helper name to each registered class, in sorted
  /// `defId` order (deterministic; two same-named types from different
  /// libraries get distinct names: `_restageA2uiBuild_Node`,
  /// `_restageA2uiBuild_Node_2`).
  void _assignClassHelpers() {
    final used = <String>{};
    for (final defId in _classes.keys.toList()..sort()) {
      final base = _safeSymbol(defId);
      var name = '_restageA2uiBuild_$base';
      var n = 2;
      while (used.contains(name)) {
        name = '_restageA2uiBuild_${base}_$n';
        n++;
      }
      used.add(name);
      _classHelperNames[defId] = name;
    }
  }

  /// The first customer-generic-over-customer-type spelling reachable from
  /// [node] that cannot be import-prefixed, or null when every spelling under
  /// [node] is prefixable.
  ///
  /// Uniform import prefixing makes same-name cross-library collisions
  /// unrepresentable (each library has a distinct prefix), so the legacy
  /// collision guard is retired. The one spelling the leading-identifier prefix
  /// cannot render is a customer generic instantiated with ANOTHER customer
  /// type (`Box<Inner>`): the flat instantiated spelling carries no
  /// per-argument library, so the inner customer type cannot be qualified. The
  /// caller fails
  /// closed LOUD on a non-null result (naming the widget/field) rather than
  /// emit ambiguous/uncompilable source; full recursive prefixing (which needs
  /// the reflector to carry a structured spelling) is a tracked follow-up.
  String? firstUnprefixableSpelling(A2uiSchemaNode node) {
    String? result;
    void visit(A2uiSchemaNode current) {
      if (result != null) return;
      switch (current) {
        case ScalarNode() || EnumNode() || RefNode() || UnionNode():
          break;
        case ListNode(:final element):
          visit(element);
        case MapNode(:final valueType):
          visit(valueType);
        case ObjectNode(:final construction, :final fields):
          if (construction is A2uiClassConstruction &&
              _spellingHasCustomerTypeArgument(construction)) {
            result = construction.dartTypeName;
            return;
          }
          fields.values.forEach(visit);
      }
    }

    visit(node);
    return result;
  }

  /// The dart:core type names that may appear UNPREFIXED as a generic type
  /// argument (the reconstructable type-argument set the reflector accepts:
  /// scalars + the collection constructors). Any OTHER identifier in a type-
  /// argument position is presumed a customer type — which the leading-
  /// identifier prefix cannot qualify — and fails the spelling closed.
  static const Set<String> _unprefixedSafeTypeArgNames = {
    'int',
    'double',
    'num',
    'String',
    'bool',
    'List',
    'Map',
    'Set',
    'Iterable',
    'Object',
    'dynamic',
    'void',
    'Null',
  };

  /// Matches each type identifier in a generic spelling's argument list.
  static final RegExp _typeArgIdentifier = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');

  /// Whether [construction]'s instantiated spelling is a generic whose type
  /// arguments include a non-dart:core (presumed customer) type — which the
  /// leading-identifier prefix would leave bare and unresolved.
  ///
  /// Fail-closed-conservative: rather than enumerate customer types (which can
  /// miss a phantom/inherited type-argument dependency that never appears as a
  /// reconstructed field), this allow-lists the dart:core type names that are
  /// safe to spell bare and treats every other type-argument identifier as
  /// unprefixable.
  bool _spellingHasCustomerTypeArgument(A2uiClassConstruction construction) {
    final spelling = construction.dartTypeName;
    final lt = spelling.indexOf('<');
    if (lt < 0) return false;
    final typeArgs = spelling.substring(lt);
    for (final match in _typeArgIdentifier.allMatches(typeArgs)) {
      if (!_unprefixedSafeTypeArgNames.contains(match.group(0))) return true;
    }
    return false;
  }

  /// The fail-safe reconstruction expression for [node], reading the JSON value
  /// from the [raw] expression. [depth] is the recursion-depth expression
  /// threaded into nested class-helper calls (the literal `'0'` at the value
  /// root; `'_depth + 1'` inside a helper body).
  String valueExpression(
    A2uiSchemaNode node,
    String raw, {
    String depth = '0',
  }) {
    switch (node) {
      case ScalarNode(:final type):
        return _scalarExpression(type, raw);
      case EnumNode(:final dartTypeName, :final libraryUri):
        // Fail-safe: an unknown / absent member name resolves to null (the
        // map lookup), never a thrown cast.
        final type = prefixedType(dartTypeName, libraryUri, _prefixes);
        return '$type.values.asNameMap()[_restageA2uiAs<String>($raw)]';
      case ListNode(:final element):
        // Element coercion runs at the SAME depth as the list (a list is not an
        // object-nesting level); a class-element helper increments for its own
        // fields. Non-null elements drop coercion failures via `whereType`;
        // nullable elements keep nulls.
        final elementExpr = valueExpression(element, 'e', depth: depth);
        final mapped =
            '_restageA2uiAs<List<Object?>>($raw)?.map((e) => $elementExpr)';
        return element.nullable
            ? '$mapped.toList()'
            : '$mapped.whereType<${_dartType(element)}>().toList()';
      case MapNode(:final valueType):
        // The value coercion runs at the SAME depth as the map; a class-value
        // helper increments for its own fields. Non-null values drop
        // null-coercing entries; nullable values keep them.
        final valueExpr = valueExpression(valueType, 'v', depth: depth);
        final base = _dartTypeBase(valueType);
        return valueType.nullable
            ? '_restageA2uiMapNullable<$base>($raw, (v) => $valueExpr)'
            : '_restageA2uiMap<$base>($raw, (v) => $valueExpr)';
      case final ObjectNode object:
        return object.construction is A2uiClassConstruction
            ? '${_helperNameFor(object.defId)}($raw, $depth)'
            : _recordExpression(object, raw, depth);
      case RefNode(:final defId):
        return '${_helperNameFor(defId)}($raw, $depth)';
      case UnionNode():
        throw StateError(
          'A2UI value reconstruction for a union is not implemented; the '
          'reflector scopes unions out before the builder.',
        );
    }
  }

  /// The generated helper name for a class [defId], failing loud if the class
  /// was not registered (a contract violation — the reflector always supplies a
  /// `defId` for a class object, and every `RefNode` references one).
  String _helperNameFor(String? defId) {
    final name = defId == null ? null : _classHelperNames[defId];
    if (name == null) {
      throw StateError(
        'A2UI value-builder: no helper registered for class defId "$defId".',
      );
    }
    return name;
  }

  /// A record reconstructed inline `(f1: <coerce> ?? <fallback>, …)`, guarded
  /// so the WHOLE record reconstructs to null when [raw] is not a map — both a
  /// nullable record (the author allowed null) AND a non-null record. A
  /// non-null record that is entirely absent/malformed is the same case as a
  /// missing nested data class: it propagates null so the enclosing object /
  /// widget fails safe (the ruling-#5 never-fabricate-a-required-value
  /// contract), rather than fabricating a record from per-field fallbacks. Only
  /// when [raw] IS a map do the per-field fallbacks apply — a record's internal
  /// fields cannot be null, so a present-but-missing internal field degrades to
  /// its fallback. (Every record field is a scalar or enum — reflector.)
  String _recordExpression(ObjectNode record, String raw, String depth) {
    final parts = <String>[];
    for (final entry in record.fields.entries) {
      final key = _stringLiteral(entry.key);
      final access = '_restageA2uiAs<Map<String, Object?>>($raw)?[$key]';
      // Through the same field-value funnel as class fields, so a nullable
      // record field passes through (not fabricated) by construction.
      final value = _fieldValueExpression(entry.value, access, depth);
      parts.add('${entry.key}: $value');
    }
    final inline = '(${parts.join(', ')})';
    final notMap = '_restageA2uiAs<Map<String, Object?>>($raw) == null';
    return '$notMap ? null : $inline';
  }

  /// The SINGLE field-value funnel that honors `node.nullable`, used by every
  /// non-fail-object field site (record fields, class optional/nullable
  /// fields). A NULLABLE node passes the coercion through (null-capable); a
  /// NON-null node is defaulted (every coercion is null-capable, so a
  /// missing/malformed value degrades to the generic fallback at a field site).
  /// This is the chokepoint that keeps nullability from being forgotten at a
  /// field site. The one arm it does NOT cover is a required NON-null field
  /// that fails the whole object on null (a statement in the class helper).
  String _fieldValueExpression(
    A2uiSchemaNode node,
    String access,
    String depth,
  ) {
    final coerce = valueExpression(node, access, depth: depth);
    if (node.nullable) return coerce;
    return '$coerce ?? ${_genericFallback(node)}';
  }

  /// The Dart type name for [node], including a trailing `?` when nullable.
  String _dartType(A2uiSchemaNode node) {
    final base = _dartTypeBase(node);
    return node.nullable ? '$base?' : base;
  }

  /// The NON-null Dart type name for [node] (the caller adds nullability).
  String _dartTypeBase(A2uiSchemaNode node) {
    switch (node) {
      case ScalarNode(:final type):
        switch (type) {
          case A2uiScalarType.string:
            return 'String';
          case A2uiScalarType.integer:
            return 'int';
          // A `double` and a (rare) `num` field both project as `number`;
          // `double` is the safe common type (`double <: num`, so it satisfies
          // both — a `num` field's int values widen to double, fail-safe).
          case A2uiScalarType.number:
            return 'double';
          case A2uiScalarType.boolean:
            return 'bool';
        }
      case EnumNode(:final dartTypeName, :final libraryUri):
        return prefixedType(dartTypeName, libraryUri, _prefixes);
      case ListNode(:final element):
        return 'List<${_dartType(element)}>';
      case MapNode(:final valueType):
        return 'Map<String, ${_dartType(valueType)}>';
      case final ObjectNode object:
        final construction = object.construction;
        return construction is A2uiClassConstruction
            ? prefixedType(
                construction.dartTypeName,
                construction.libraryUri,
                _prefixes,
              )
            : _recordTypeName(object);
      case RefNode(:final defId):
        if (_classes[defId] == null) {
          throw StateError(
            'A2UI value-builder: no Dart type for ref "$defId".',
          );
        }
        final construction =
            _classes[defId]!.construction! as A2uiClassConstruction;
        return prefixedType(
          construction.dartTypeName,
          construction.libraryUri,
          _prefixes,
        );
      case UnionNode():
        throw StateError('union has no value-builder Dart type');
    }
  }

  /// The named-record Dart type `({<type> name, …})` for a record [node].
  String _recordTypeName(ObjectNode node) {
    final fields = [
      for (final entry in node.fields.entries)
        '${_dartType(entry.value)} ${entry.key}',
    ];
    return '({${fields.join(', ')}})';
  }

  /// A fail-safe non-null default for an OPTIONAL non-null field that is absent
  /// at render time. Only the inline-defaultable shapes reach here: an optional
  /// non-null object/record/recursive param is scoped out by the reflector
  /// (no synthesizable default), so those arms are unreachable.
  String _genericFallback(A2uiSchemaNode node) {
    switch (node) {
      case ScalarNode(:final type):
        switch (type) {
          case A2uiScalarType.string:
            return "''";
          case A2uiScalarType.integer:
            return '0';
          case A2uiScalarType.number:
            return '0.0';
          case A2uiScalarType.boolean:
            return 'false';
        }
      case EnumNode(:final dartTypeName, :final libraryUri):
        return '${prefixedType(dartTypeName, libraryUri, _prefixes)}'
            '.values.first';
      case ListNode(:final element):
        return 'const <${_dartType(element)}>[]';
      case MapNode(:final valueType):
        return 'const <String, ${_dartType(valueType)}>{}';
      case ObjectNode() || RefNode() || UnionNode():
        throw StateError(
          'no fail-safe default for ${node.runtimeType}; the reflector scopes '
          'an optional non-null object/record/recursive parameter out.',
        );
    }
  }

  /// The fail-safe coercion for a scalar [type] reading from [raw]: a single
  /// typed cast that yields null (never throws) on a type mismatch.
  String _scalarExpression(A2uiScalarType type, String raw) {
    switch (type) {
      case A2uiScalarType.string:
        return '_restageA2uiAs<String>($raw)';
      case A2uiScalarType.boolean:
        return '_restageA2uiAs<bool>($raw)';
      case A2uiScalarType.integer:
        return '_restageA2uiAs<num>($raw)?.toInt()';
      case A2uiScalarType.number:
        return '_restageA2uiAs<num>($raw)?.toDouble()';
    }
  }

  /// Every once-emitted declaration the roots reference: the depth ceiling, the
  /// runtime fail-safe helpers actually used, and one helper per nested class
  /// type. Emits only what is referenced (no unused declarations).
  List<String> supportDefinitions() {
    final defs = <String>[];
    if (_usesTypedCast) {
      defs.add(_typedCastHelper);
    }
    if (_usesMap) {
      defs.add(_mapHelper);
    }
    if (_usesMapNullable) {
      defs.add(_mapNullableHelper);
    }
    if (_classes.isNotEmpty) {
      defs.add('const int _kA2uiMaxBuildDepth = $_maxBuildDepth;');
      final ordered = _classHelperNames.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final entry in ordered) {
        defs.add(_classHelperDefinition(entry.key));
      }
    }
    return defs;
  }

  /// The generated helper that reconstructs the class registered under [defId].
  ///
  /// Fail-safe at every step: depth-bounded, Map-guarded, each REQUIRED field
  /// null-guarded (a missing required value fails the whole object null — never
  /// a fabricated value), each OPTIONAL non-null field defaulted, each optional
  /// nullable field passed through. `_raw`/`_depth` are underscore-prefixed so
  /// they can never collide with a (always-public) field local.
  String _classHelperDefinition(String defId) {
    final object = _classes[defId]!;
    final ctor = object.construction! as A2uiClassConstruction;
    final helper = _classHelperNames[defId]!;
    final typeName = prefixedType(
      ctor.dartTypeName,
      ctor.libraryUri,
      _prefixes,
    );
    final lines = <String>[
      '$typeName? $helper(Object? _raw, int _depth) {',
      '  if (_depth > _kA2uiMaxBuildDepth) return null;',
      '  if (_raw is! Map<String, Object?>) return null;',
    ];
    final positional = <String>[];
    final named = <String>[];
    for (final parameter in ctor.parameters) {
      final field = object.fields[parameter.name]!;
      final access = '_raw[${_stringLiteral(parameter.name)}]';
      final required = object.required.contains(parameter.name);
      if (required && !field.nullable) {
        // The one statement-context arm: a REQUIRED, NON-nullable field fails
        // the whole object when its coercion is null (every coercion is
        // null-capable). A missing/malformed required value is never
        // fabricated; it propagates to a widget-level fail-safe.
        final coerce = valueExpression(field, access, depth: '_depth + 1');
        lines
          ..add('  final ${parameter.name} = $coerce;')
          ..add('  if (${parameter.name} == null) return null;');
      } else {
        // Every other field routes through the shared nullability funnel: a
        // nullable field passes through, a non-null field is made non-null.
        final value = _fieldValueExpression(field, access, '_depth + 1');
        lines.add('  final ${parameter.name} = $value;');
      }
      if (parameter.named) {
        named.add('${parameter.name}: ${parameter.name}');
      } else {
        positional.add(parameter.name);
      }
    }
    final ctorRef = ctor.constructorName == null
        ? typeName
        : '$typeName.${ctor.constructorName}';
    lines
      ..add('  return $ctorRef(${[...positional, ...named].join(', ')});')
      ..add('}');
    return lines.join('\n');
  }

  /// Whether [valueExpression] for [node] can evaluate to null on bad render
  /// data — the predicate the emitter's widget-argument site uses to decide
  /// whether a required, non-null argument needs a fail-safe null guard. EVERY
  /// value-builder coercion is null-capable: every shape (scalar, enum, list,
  /// map, nested data class, AND record) reconstructs to null when its raw
  /// value is missing or the wrong type, so a required-missing value always
  /// fails safe and is never fabricated.
  bool valueCanBeNull(A2uiSchemaNode node) => true;

  /// A collision-safe, identifier-safe symbol fragment from a canonical
  /// `defId` (`<libraryUri>#<symbol>[<typeArgs>]`): the symbol name with any
  /// generic suffix stripped, sanitized to `[A-Za-z0-9_]`.
  String _safeSymbol(String defId) {
    final hash = defId.indexOf('#');
    var symbol = hash < 0 ? defId : defId.substring(hash + 1);
    final lt = symbol.indexOf('<');
    if (lt >= 0) symbol = symbol.substring(0, lt);
    final sanitized = symbol.replaceAll(RegExp('[^A-Za-z0-9_]'), '_');
    return sanitized.isEmpty ? 'Type' : sanitized;
  }

  /// A Dart single-quoted string literal for [value], escaping `\`, `'`, `$`
  /// and newlines so a field name carrying any of them stays inert in the
  /// emitted source (no interpolation, no premature string close).
  String _stringLiteral(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll(r'$', r'\$')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n');
    return "'$escaped'";
  }

  /// The typed-cast runtime helper: a fail-safe cast that yields null rather
  /// than throwing on a type mismatch.
  static const String _typedCastHelper =
      'T? _restageA2uiAs<T>(Object? v) => v is T ? v : null;';

  /// The drop-null map helper: reconstructs a `Map<String, V>` (non-null V),
  /// dropping any non-String key or null-coercing value (a partial map is
  /// fail-safer than a thrown cast). Returns null when `raw` is not a map, so a
  /// map coercion yields null on failure uniformly with scalars and lists (the
  /// field site then handles it: required → object null, optional → default).
  static const String _mapHelper = '''
Map<String, V>? _restageA2uiMap<V>(Object? raw, V? Function(Object?) coerce) {
  if (raw is! Map) return null;
  final result = <String, V>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String) continue;
    final value = coerce(entry.value);
    if (value == null) continue;
    result[key] = value;
  }
  return result;
}''';

  /// The keep-null map helper: reconstructs a `Map<String, V?>`, keeping
  /// null-coercing values (the value type is nullable). Returns null when `raw`
  /// is not a map (uniform null-on-failure).
  static const String _mapNullableHelper = '''
Map<String, V?>? _restageA2uiMapNullable<V>(
  Object? raw,
  V? Function(Object?) coerce,
) {
  if (raw is! Map) return null;
  final result = <String, V?>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String) continue;
    result[key] = coerce(entry.value);
  }
  return result;
}''';
}
