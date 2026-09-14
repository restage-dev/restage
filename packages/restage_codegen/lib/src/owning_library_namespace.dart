import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/helper_registry.dart';

typedef _ActiveTypeAlias = ({TypeAliasElement element, DartType target});

/// Resolves spellings exactly as the generated part's library will see them.
final class OwningLibraryNamespace {
  /// Creates a namespace view for [library].
  const OwningLibraryNamespace(this.library);

  /// The library that will own the generated part.
  final LibraryElement library;

  /// Import prefixes declared by the owning library.
  Set<String> get prefixNames => {
        for (final prefix in library.firstFragment.prefixes)
          if (prefix.name case final name? when name.isNotEmpty) name,
      };

  /// Names contributed by visible unprefixed imports.
  Set<String> get unprefixedImportNames => {
        for (final import in library.firstFragment.libraryImports)
          if (import.prefix == null) ...import.namespace.definedNames2.keys,
      };

  /// Public names visible to importers of the owning library.
  Set<String> publicNamespaceNames({bool Function(Element)? exclude}) {
    final names = <String>{};
    for (final entry in library.exportNamespace.definedNames2.entries) {
      if (exclude?.call(entry.value) != true) {
        names.add(entry.key);
      }
    }
    for (final export in library.firstFragment.libraryExports) {
      final exported = export.exportedLibrary;
      if (exported == null) continue;
      for (final entry in exported.exportNamespace.definedNames2.entries) {
        if (_visibleThroughExport(entry.key, export.combinators) &&
            exclude?.call(entry.value) != true) {
          names.add(entry.key);
        }
      }
    }
    return names;
  }

  /// Finds one spelling that resolves every entry in [symbols] to [origin].
  String? prefixForOrigin(String origin, Set<String> symbols) {
    final importsByPrefix = Map<PrefixElement?, List<LibraryImport>>.identity();
    for (final import in library.firstFragment.libraryImports) {
      final prefix = import.prefix?.element;
      importsByPrefix.putIfAbsent(prefix, () => []).add(import);
    }

    final candidates = <String>[];
    for (final entry in importsByPrefix.entries) {
      final prefix = entry.key;
      final visible = symbols.every((symbol) {
        final resolved = prefix == null
            ? library.firstFragment.scope.lookup(symbol).getter
            : prefix.scope.lookup(symbol).getter;
        if (resolved == null ||
            !libraryUriMatchesOrigin(
              resolved.library?.identifier ?? '',
              origin,
            )) {
          return false;
        }
        return entry.value.any(
          (import) =>
              import.prefix?.isDeferred != true &&
              _sameElement(
                import.namespace.get2(_importedName(prefix, symbol)),
                resolved,
              ),
        );
      });
      if (visible) {
        final name = prefix?.name;
        candidates.add(name == null || name.isEmpty ? '' : '$name.');
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort(_comparePrefixes);
    return candidates.first;
  }

  /// Returns an exact reusable spelling of [type], when one is visible.
  String? typeCode(DartType type) => _typeCode(
        type,
        const {},
        _visibleAliases(),
        const {},
      );

  /// Returns the visible spelling of [element], when one exists.
  String? elementName(Element element) => _visibleElementName(element);

  /// Returns an exact visible spelling of a static [member].
  String? staticMemberName(
    Element member, {
    bool includeAliases = true,
  }) {
    final element = _referencedElement(member);
    final owner = element.enclosingElement;
    final name = element.name;
    final isStatic = switch (element) {
      VariableElement(:final isStatic) => isStatic,
      ExecutableElement(:final isStatic) => isStatic,
      _ => false,
    };
    if (!isStatic ||
        owner is! InstanceElement ||
        name == null ||
        name.isEmpty ||
        element.isPrivate && element.library != library ||
        !_declaresMember(owner, element, name)) {
      return null;
    }

    final ownerName = _visibleElementName(owner);
    if (ownerName != null) return '$ownerName.$name';
    if (!includeAliases || owner is! InterfaceElement) return null;

    final aliases = _visibleAliases()
        .where((alias) => alias.names(owner))
        .toList(growable: false);
    return aliases.isEmpty ? null : '${aliases.first.name}.$name';
  }

  String? _typeCode(
    DartType type,
    Set<TypeParameterElement> localTypeParameters,
    List<_VisibleTypeAlias> allAliases,
    Set<_ActiveTypeAlias> activeAliases,
  ) {
    // A function type's own type parameters hide same-named library names.
    final shadowed = {
      for (final parameter in localTypeParameters) parameter.name,
    };
    final aliases = shadowed.isEmpty
        ? allAliases
        : allAliases
            .where((alias) => !shadowed.contains(alias.name.split('.').first))
            .toList(growable: false);
    final alias = type.alias;
    if (alias != null) {
      final code = _attachedAliasCode(
        type,
        alias,
        localTypeParameters,
        aliases,
        activeAliases,
      );
      if (code != null) return code;
    }
    final direct = switch (type) {
      DynamicType() => 'dynamic',
      VoidType() => 'void',
      NeverType() => _namedType(
          type,
          const [],
          localTypeParameters,
          aliases,
          activeAliases,
        ),
      InterfaceType(:final typeArguments) => _namedType(
          type,
          typeArguments,
          localTypeParameters,
          aliases,
          activeAliases,
        ),
      TypeParameterType() => _typeParameterType(type, localTypeParameters),
      FunctionType() => _functionType(
          type,
          localTypeParameters,
          aliases,
          activeAliases,
        ),
      RecordType() => _recordType(
          type,
          localTypeParameters,
          aliases,
          activeAliases,
        ),
      InvalidType() => null,
      _ => null,
    };
    if (direct != null) return direct;
    if (type is! InterfaceType &&
        type is! FunctionType &&
        type is! RecordType) {
      return null;
    }
    return _discoveredAliasCode(
      type,
      localTypeParameters,
      aliases,
      activeAliases,
    );
  }

  String? _attachedAliasCode(
    DartType type,
    InstantiatedTypeAliasElement alias,
    Set<TypeParameterElement> localTypeParameters,
    List<_VisibleTypeAlias> aliases,
    Set<_ActiveTypeAlias> activeAliases,
  ) {
    final visible = aliases.where(
      (candidate) => _sameElement(candidate.element, alias.element),
    );
    if (visible.isEmpty) return null;
    final key = (element: alias.element, target: type);
    if (activeAliases.contains(key)) return null;
    final arguments = _typeArguments(
      alias.typeArguments,
      localTypeParameters,
      aliases,
      {...activeAliases, key},
    );
    final suffix = _nullabilitySuffix(alias.nullabilitySuffix);
    return arguments == null || suffix == null
        ? null
        : '${visible.first.name}$arguments$suffix';
  }

  String? _namedType(
    DartType type,
    List<DartType> typeArguments,
    Set<TypeParameterElement> localTypeParameters,
    List<_VisibleTypeAlias> aliases,
    Set<_ActiveTypeAlias> activeAliases,
  ) {
    final element = type.element;
    if (element == null) return null;
    final name = _visibleElementName(
      element,
      shadowed: {for (final parameter in localTypeParameters) parameter.name},
    );
    if (name == null) return null;
    final arguments = _typeArguments(
      typeArguments,
      localTypeParameters,
      aliases,
      activeAliases,
    );
    final suffix = _nullabilitySuffix(type.nullabilitySuffix);
    return arguments == null || suffix == null
        ? null
        : '$name$arguments$suffix';
  }

  String? _typeParameterType(
    TypeParameterType type,
    Set<TypeParameterElement> localTypeParameters,
  ) {
    final element = type.element.baseElement;
    if (!localTypeParameters.contains(element)) return null;
    final name = element.name;
    final suffix = _nullabilitySuffix(type.nullabilitySuffix);
    return name == null || name.isEmpty || suffix == null
        ? null
        : '$name$suffix';
  }

  String? _typeArguments(
    List<DartType> arguments,
    Set<TypeParameterElement> localTypeParameters,
    List<_VisibleTypeAlias> aliases,
    Set<_ActiveTypeAlias> activeAliases,
  ) {
    if (arguments.isEmpty) return '';
    final values = <String>[];
    for (final argument in arguments) {
      final value = _typeCode(
        argument,
        localTypeParameters,
        aliases,
        activeAliases,
      );
      if (value == null) return null;
      values.add(value);
    }
    return '<${values.join(', ')}>';
  }

  String? _functionType(
    FunctionType type,
    Set<TypeParameterElement> outerTypeParameters,
    List<_VisibleTypeAlias> aliases,
    Set<_ActiveTypeAlias> activeAliases,
  ) {
    final typeParameters = {
      ...outerTypeParameters,
      for (final parameter in type.typeParameters) parameter.baseElement,
    };
    final returnType = _typeCode(
      type.returnType,
      typeParameters,
      aliases,
      activeAliases,
    );
    if (returnType == null) return null;

    final typeParameterSources = <String>[];
    for (final parameter in type.typeParameters) {
      final parameterName = parameter.name;
      if (parameterName == null || parameterName.isEmpty) return null;
      final bound = parameter.bound;
      final boundCode = bound == null
          ? null
          : _typeCode(
              bound,
              typeParameters,
              aliases,
              activeAliases,
            );
      if (bound != null && boundCode == null) return null;
      typeParameterSources.add(
        boundCode == null ? parameterName : '$parameterName extends $boundCode',
      );
    }
    final parameters = _functionParameters(
      type,
      typeParameters,
      aliases,
      activeAliases,
    );
    if (parameters == null) return null;
    final generics = typeParameterSources.isEmpty
        ? ''
        : '<${typeParameterSources.join(', ')}>';
    final source = '$returnType Function$generics$parameters';
    return switch (type.nullabilitySuffix) {
      NullabilitySuffix.none => source,
      NullabilitySuffix.question => '$source?',
      NullabilitySuffix.star => null,
    };
  }

  String? _functionParameters(
    FunctionType type,
    Set<TypeParameterElement> localTypeParameters,
    List<_VisibleTypeAlias> aliases,
    Set<_ActiveTypeAlias> activeAliases,
  ) {
    final requiredPositional = <String>[];
    final optionalPositional = <String>[];
    final named = <String>[];
    for (final parameter in type.formalParameters) {
      final typeCode = _typeCode(
        parameter.type,
        localTypeParameters,
        aliases,
        activeAliases,
      );
      if (typeCode == null) return null;
      if (parameter.isNamed) {
        named.add(
          '${parameter.isRequiredNamed ? 'required ' : ''}'
          '$typeCode ${parameter.name}',
        );
      } else if (parameter.isOptionalPositional) {
        optionalPositional.add(typeCode);
      } else {
        requiredPositional.add(typeCode);
      }
    }
    final values = <String>[
      ...requiredPositional,
      if (optionalPositional.isNotEmpty) '[${optionalPositional.join(', ')}]',
      if (named.isNotEmpty) '{${named.join(', ')}}',
    ];
    return '(${values.join(', ')})';
  }

  String? _recordType(
    RecordType type,
    Set<TypeParameterElement> localTypeParameters,
    List<_VisibleTypeAlias> aliases,
    Set<_ActiveTypeAlias> activeAliases,
  ) {
    final positional = <String>[];
    for (final field in type.positionalFields) {
      final typeCode = _typeCode(
        field.type,
        localTypeParameters,
        aliases,
        activeAliases,
      );
      if (typeCode == null) return null;
      positional.add(typeCode);
    }
    final named = <String>[];
    for (final field in type.namedFields) {
      final typeCode = _typeCode(
        field.type,
        localTypeParameters,
        aliases,
        activeAliases,
      );
      if (typeCode == null) return null;
      named.add('$typeCode ${field.name}');
    }
    final values = <String>[
      ...positional,
      if (positional.length == 1 && named.isEmpty) '',
      if (named.isNotEmpty) '{${named.join(', ')}}',
    ];
    final suffix = _nullabilitySuffix(type.nullabilitySuffix);
    return suffix == null ? null : '(${values.join(', ')})$suffix';
  }

  // [shadowed] names an enclosing function type's own type parameters, which
  // hide any library-level name they collide with.
  String? _visibleElementName(
    Element element, {
    Set<String?> shadowed = const {},
  }) {
    final name = element.name;
    if (name == null || name.isEmpty) return null;
    final unprefixed = library.firstFragment.scope.lookup(name).getter;
    if (!shadowed.contains(name) &&
        _sameElement(unprefixed, element) &&
        _hasNonDeferredRoute(null, name, element)) {
      return name;
    }

    final prefixes = library.firstFragment.prefixes.toList(growable: false)
      ..sort((left, right) => (left.name ?? '').compareTo(right.name ?? ''));
    for (final prefix in prefixes) {
      final prefixName = prefix.name;
      if (prefixName == null || prefixName.isEmpty) continue;
      if (shadowed.contains(prefixName)) continue;
      if (_sameElement(prefix.scope.lookup(name).getter, element) &&
          _hasNonDeferredRoute(prefix, name, element)) {
        return '$prefixName.$name';
      }
    }
    return null;
  }

  bool _hasNonDeferredRoute(
    PrefixElement? prefix,
    String name,
    Element element,
  ) {
    if (prefix == null && element.library == library) return true;
    if (prefix == null && element.library?.identifier == 'dart:core') {
      return true;
    }
    final imports = prefix?.imports ??
        library.firstFragment.libraryImports.where(
          (import) => import.prefix == null,
        );
    return imports.any(
      (import) =>
          import.prefix?.isDeferred != true &&
          _sameElement(
            import.namespace.get2(_importedName(prefix, name)),
            element,
          ),
    );
  }

  String? _discoveredAliasCode(
    DartType target,
    Set<TypeParameterElement> localTypeParameters,
    List<_VisibleTypeAlias> aliases,
    Set<_ActiveTypeAlias> activeAliases,
  ) {
    if (_nullabilitySuffix(target.nullabilitySuffix) == null) return null;
    for (final visible in aliases) {
      final alias = visible.element;
      final key = (element: alias, target: target);
      if (activeAliases.contains(key)) continue;
      final nextAliases = {...activeAliases, key};
      final toBounds = library.typeSystem.instantiateTypeAliasToBounds(
        element: alias,
        nullabilitySuffix: target.nullabilitySuffix,
      );
      final defaults = toBounds.alias;
      if (toBounds == target &&
          defaults != null &&
          _sameElement(defaults.element, alias) &&
          defaults.typeArguments.length == alias.typeParameters.length) {
        final code = _aliasVectorCode(
          visible,
          target,
          defaults.typeArguments,
          localTypeParameters,
          aliases,
          nextAliases,
        );
        if (code != null) return code;
      }
      if (alias.typeParameters.isEmpty ||
          alias.typeParameters.any((parameter) => parameter.bound != null)) {
        continue;
      }

      final bindings = _reverseAliasBindings(alias, target);
      if (bindings == null ||
          defaults == null ||
          !_sameElement(defaults.element, alias) ||
          defaults.typeArguments.length != alias.typeParameters.length) {
        continue;
      }
      final arguments = <DartType>[
        for (var index = 0; index < alias.typeParameters.length; index++)
          bindings[alias.typeParameters[index].baseElement] ??
              defaults.typeArguments[index],
      ];
      final code = _aliasVectorCode(
        visible,
        target,
        arguments,
        localTypeParameters,
        aliases,
        nextAliases,
      );
      if (code != null) return code;
    }
    return null;
  }

  String? _aliasVectorCode(
    _VisibleTypeAlias visible,
    DartType target,
    List<DartType> arguments,
    Set<TypeParameterElement> localTypeParameters,
    List<_VisibleTypeAlias> aliases,
    Set<_ActiveTypeAlias> activeAliases,
  ) {
    final alias = visible.element;
    if (arguments.length != alias.typeParameters.length) return null;
    final instantiated = alias.instantiate(
      typeArguments: arguments,
      nullabilitySuffix: target.nullabilitySuffix,
    );
    if (instantiated != target) return null;
    final argumentCode = _typeArguments(
      arguments,
      localTypeParameters,
      aliases,
      activeAliases,
    );
    final suffix = _nullabilitySuffix(target.nullabilitySuffix);
    if (argumentCode == null || suffix == null) return null;
    return '${visible.name}$argumentCode$suffix';
  }

  List<_VisibleTypeAlias> _visibleAliases() {
    final aliases = Set<TypeAliasElement>.identity()
      ..addAll(library.typeAliases);
    for (final import in library.firstFragment.libraryImports) {
      aliases.addAll(
        import.namespace.definedNames2.values.whereType<TypeAliasElement>(),
      );
    }

    final visible = <_VisibleTypeAlias>[];
    for (final alias in aliases) {
      final name = _visibleElementName(alias);
      if (name != null) visible.add(_VisibleTypeAlias(alias, name));
    }
    visible.sort((left, right) => _compareElementNames(left.name, right.name));
    return List.unmodifiable(visible);
  }
}

final class _VisibleTypeAlias {
  const _VisibleTypeAlias(this.element, this.name);

  final TypeAliasElement element;
  final String name;

  bool names(InterfaceElement owner) {
    final type = element.aliasedType;
    return type is InterfaceType && _sameElement(type.element, owner);
  }
}

Map<TypeParameterElement, DartType>? _reverseAliasBindings(
  TypeAliasElement alias,
  DartType target,
) {
  final parameters = Set<TypeParameterElement>.identity()
    ..addAll(alias.typeParameters.map((parameter) => parameter.baseElement));
  final bindings = Map<TypeParameterElement, DartType>.identity();
  return _matchAliasType(alias.aliasedType, target, parameters, bindings)
      ? bindings
      : null;
}

bool _matchAliasType(
  DartType pattern,
  DartType target,
  Set<TypeParameterElement> parameters,
  Map<TypeParameterElement, DartType> bindings,
) {
  if (pattern case TypeParameterType(:final element)
      when parameters.contains(element.baseElement)) {
    if (pattern.nullabilitySuffix != NullabilitySuffix.none) return false;
    final parameter = element.baseElement;
    final existing = bindings[parameter];
    if (existing == null) {
      bindings[parameter] = target;
      return true;
    }
    return existing == target;
  }
  if (pattern.nullabilitySuffix != target.nullabilitySuffix) return false;
  return switch ((pattern, target)) {
    (DynamicType(), DynamicType()) => true,
    (VoidType(), VoidType()) => true,
    (NeverType(), NeverType()) => true,
    (
      InterfaceType(:final element, :final typeArguments),
      InterfaceType(element: final targetElement, typeArguments: final targets),
    ) =>
      _sameElement(element, targetElement) &&
          _matchAliasTypes(typeArguments, targets, parameters, bindings),
    (
      TypeParameterType(:final element),
      TypeParameterType(element: final targetElement),
    ) =>
      _sameElement(element, targetElement),
    (final FunctionType function, final FunctionType targetFunction) =>
      _matchAliasFunctionType(function, targetFunction, parameters, bindings),
    (final RecordType record, final RecordType targetRecord) =>
      _matchAliasRecordType(record, targetRecord, parameters, bindings),
    _ => false,
  };
}

bool _matchAliasTypes(
  List<DartType> patterns,
  List<DartType> targets,
  Set<TypeParameterElement> parameters,
  Map<TypeParameterElement, DartType> bindings,
) {
  if (patterns.length != targets.length) return false;
  for (var index = 0; index < patterns.length; index++) {
    if (!_matchAliasType(
      patterns[index],
      targets[index],
      parameters,
      bindings,
    )) {
      return false;
    }
  }
  return true;
}

bool _matchAliasFunctionType(
  FunctionType pattern,
  FunctionType target,
  Set<TypeParameterElement> parameters,
  Map<TypeParameterElement, DartType> bindings,
) {
  if (pattern.typeParameters.isNotEmpty ||
      target.typeParameters.isNotEmpty ||
      pattern.formalParameters.length != target.formalParameters.length ||
      !_matchAliasType(
        pattern.returnType,
        target.returnType,
        parameters,
        bindings,
      )) {
    return false;
  }
  for (var index = 0; index < pattern.formalParameters.length; index++) {
    final left = pattern.formalParameters[index];
    final right = target.formalParameters[index];
    if (left.isNamed != right.isNamed ||
        left.isOptional != right.isOptional ||
        left.isRequiredNamed != right.isRequiredNamed ||
        left.isNamed && left.name != right.name ||
        !_matchAliasType(left.type, right.type, parameters, bindings)) {
      return false;
    }
  }
  return true;
}

bool _matchAliasRecordType(
  RecordType pattern,
  RecordType target,
  Set<TypeParameterElement> parameters,
  Map<TypeParameterElement, DartType> bindings,
) {
  if (!_matchAliasTypes(
        pattern.positionalFields.map((field) => field.type).toList(),
        target.positionalFields.map((field) => field.type).toList(),
        parameters,
        bindings,
      ) ||
      pattern.namedFields.length != target.namedFields.length) {
    return false;
  }
  final targets = {
    for (final field in target.namedFields) field.name: field.type,
  };
  for (final field in pattern.namedFields) {
    final targetType = targets[field.name];
    if (targetType == null ||
        !_matchAliasType(field.type, targetType, parameters, bindings)) {
      return false;
    }
  }
  return true;
}

String _importedName(PrefixElement? prefix, String name) {
  final prefixName = prefix?.name;
  return prefixName == null || prefixName.isEmpty ? name : '$prefixName.$name';
}

bool _visibleThroughExport(
  String name,
  List<NamespaceCombinator> combinators,
) {
  var visible = true;
  for (final combinator in combinators) {
    switch (combinator) {
      case ShowElementCombinator(:final shownNames):
        visible = visible && shownNames.contains(name);
      case HideElementCombinator(:final hiddenNames):
        visible = visible && !hiddenNames.contains(name);
    }
  }
  return visible;
}

int _comparePrefixes(String left, String right) {
  if (left.isEmpty) return right.isEmpty ? 0 : -1;
  if (right.isEmpty) return 1;
  return left.compareTo(right);
}

int _compareElementNames(String left, String right) {
  final leftIsPrefixed = left.contains('.');
  final rightIsPrefixed = right.contains('.');
  if (leftIsPrefixed != rightIsPrefixed) return leftIsPrefixed ? 1 : -1;
  return left.compareTo(right);
}

bool _declaresMember(InstanceElement owner, Element member, String name) {
  final declaration = switch (member) {
    VariableElement() => owner.getField(name),
    ExecutableElement() => owner.getMethod(name),
    _ => null,
  };
  return declaration != null && _sameElement(declaration, member);
}

bool _sameElement(Element? left, Element right) {
  if (left == null) return false;
  return _referencedElement(left) == _referencedElement(right);
}

Element _referencedElement(Element element) =>
    (element is PropertyAccessorElement ? element.variable : element)
        .baseElement;

String? _nullabilitySuffix(NullabilitySuffix suffix) => switch (suffix) {
      NullabilitySuffix.none => '',
      NullabilitySuffix.question => '?',
      NullabilitySuffix.star => null,
    };
