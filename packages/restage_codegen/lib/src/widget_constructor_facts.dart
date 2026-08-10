import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_visitor.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/enum_constant_identity.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const String _catalogSchemaOrigin = 'package:rfw_catalog_schema';
const String _emitTargetOrigin =
    'package:rfw_catalog_schema/src/annotations/emit_target.dart';

ElementAnnotation? _catalogAnnotation(Element element, String name) =>
    firstAnnotationFromOriginAny(element, {name}, _catalogSchemaOrigin);

/// One public input of a widget's unnamed generative constructor.
@immutable
final class WidgetConstructorInput {
  /// Creates a normalized constructor input.
  const WidgetConstructorInput({
    required this.formal,
    required this.field,
    required this.type,
    required this.propertyAnnotation,
    required this.dartdocDescription,
    required this.constructorDefault,
    required this.assertedNonNull,
    required this.nullable,
    required this.inherited,
    this.ignoreTargets,
    this.hasIgnore = false,
  });

  /// The local constructor formal, in constructor order.
  final FormalParameterElement formal;

  /// Formal declarations from [formal] through its inherited constructor
  /// chain, ending at the declaration that initializes [field].
  Iterable<FormalParameterElement> get formalChain =>
      widgetConstructorFormalChain(formal);

  /// The one public final field initialized by [formal].
  final FieldElement field;

  /// The constructor-effective type, including inherited type substitution.
  final DartType type;

  /// The nearest resolved `RestageProperty` overlay, if any.
  final ElementAnnotation? propertyAnnotation;

  /// Normalized Dartdoc fallback after source-precedence resolution.
  final String? dartdocDescription;

  /// Analyzer-derived default semantics of [formal].
  final WidgetConstructorDefaultFact constructorDefault;

  /// Whether a constructor assert explicitly rejects `null` for [formal].
  final bool assertedNonNull;

  /// Whether [formal] is a supported super formal.
  final bool inherited;

  /// Whether an authored `Ignore` applies, independently of decoder omission.
  final bool hasIgnore;

  /// Selected exclusion targets, or `null` for every target when ignored.
  final Set<EmitTarget>? ignoreTargets;

  /// Whether the authored exclusion applies to [target].
  bool isIgnoredFor(EmitTarget target) =>
      hasIgnore && (ignoreTargets == null || ignoreTargets!.contains(target));

  /// The public constructor/property name.
  String get name => formal.name ?? field.name ?? '<unnamed>';

  /// Whether faithful generated construction requires this argument.
  ///
  /// A nullable optional formal guarded by `assert(formal != null)` is treated
  /// as required. Omitting it would violate the author's checked-build
  /// contract, while relying on the assertion at runtime would be unsafe
  /// because assertions are removed from release builds.
  bool get required => formal.isRequired || assertedNonNull;

  /// Whether the constructor-effective type admits null.
  ///
  /// Derived with analyzer's semantic type system after generic and
  /// super-formal substitution. This includes types such as `dynamic`, `void`,
  /// `Null`, and nullable `FutureOr<T>` whose nullability is not represented by
  /// an outer `?` suffix.
  final bool nullable;

  /// Whether generated construction may leave this argument out entirely.
  ///
  /// Omission is legal only when Dart itself applies the same result: the
  /// formal is optional, and either it declares a default or its type admits
  /// null. Passing an explicit `null` is not the same as omitting, and a
  /// required formal can never be omitted.
  ///
  bool get omissible =>
      !required &&
      (constructorDefault is! NoWidgetConstructorDefault || nullable);

  /// Whether generated construction must pass this argument positionally.
  bool get positional => formal.isPositional;
}

/// Analyzer-derived default semantics for one constructor input.
sealed class WidgetConstructorDefaultFact {
  const WidgetConstructorDefaultFact();

  /// Exact target-independent constant, or `null` when none is reconstructable.
  DartConstValue? get reconstructedValue;
}

/// The formal has no explicit default; optional nullable formals imply null.
final class NoWidgetConstructorDefault extends WidgetConstructorDefaultFact {
  /// Creates the absence fact.
  const NoWidgetConstructorDefault();

  @override
  DartConstValue? get reconstructedValue => null;
}

/// The formal explicitly defaults to null.
final class NullWidgetConstructorDefault extends WidgetConstructorDefaultFact {
  /// Creates the null fact.
  const NullWidgetConstructorDefault();

  @override
  DartConstValue get reconstructedValue => const DartConstNull();
}

/// The formal has a portable primitive literal default.
final class LiteralWidgetConstructorDefault
    extends WidgetConstructorDefaultFact {
  /// Creates a portable literal fact.
  const LiteralWidgetConstructorDefault(this.value);

  /// The evaluated bool, int, finite double, or String value.
  final Object value;

  @override
  DartConstValue get reconstructedValue => DartConstScalar(value);
}

/// The formal defaults to one resolved enum constant.
final class EnumWidgetConstructorDefault extends WidgetConstructorDefaultFact {
  /// Creates a portable enum-member fact.
  const EnumWidgetConstructorDefault({
    required this.libraryUri,
    required this.owner,
    required this.member,
  });

  /// Defining library URI.
  final String libraryUri;

  /// Public enum declaration name.
  final String owner;

  /// The resolved enum member name.
  final String member;

  @override
  DartConstValue get reconstructedValue => DartConstReference(
        libraryUri: libraryUri,
        owner: owner,
        member: member,
      );
}

/// The formal defaults to a public importable top-level/static constant or
/// function tear-off, recorded by identity rather than by its flattened value.
///
/// Recording preserves the target-independent fact without loss. Each target's
/// lowering decides whether it can reproduce the reference; some targets will
/// reject it.
final class StaticMemberWidgetConstructorDefault
    extends WidgetConstructorDefaultFact {
  /// Creates an importable-reference default fact.
  const StaticMemberWidgetConstructorDefault({
    required this.libraryUri,
    required this.owner,
    required this.member,
  });

  /// The defining library of the constant or function.
  final String libraryUri;

  /// The enclosing type name for a static member, or `null` for a top-level
  /// constant or function.
  final String? owner;

  /// The constant or function member's own name.
  final String member;

  @override
  DartConstValue get reconstructedValue => DartConstReference(
        libraryUri: libraryUri,
        owner: owner,
        member: member,
      );
}

/// A recursively reconstructable constructor, collection, or record constant.
final class StructuralWidgetConstructorDefault
    extends WidgetConstructorDefaultFact {
  /// Creates a structural constant fact.
  const StructuralWidgetConstructorDefault(this.value);

  /// Exact reconstructed value.
  final DartConstValue value;

  @override
  DartConstValue get reconstructedValue => value;
}

/// The formal has a non-portable default expression.
final class UnsupportedWidgetConstructorDefault
    extends WidgetConstructorDefaultFact {
  /// Creates an unsupported default fact.
  const UnsupportedWidgetConstructorDefault(this.source);

  /// The source spelling used only for a path-qualified diagnostic.
  final String source;

  @override
  DartConstValue? get reconstructedValue => null;
}

/// Constructor-derived facts and diagnostics for one widget class.
@immutable
final class WidgetConstructorFacts {
  /// Creates a normalized constructor fact set.
  WidgetConstructorFacts({
    required List<WidgetConstructorInput> inputs,
    required List<WidgetConstructorInput> allInputs,
    required List<Issue> issues,
  })  : inputs = List.unmodifiable(inputs),
        allInputs = List.unmodifiable(allInputs),
        issues = List.unmodifiable(issues);

  /// Supported inputs, in constructor declaration order.
  final List<WidgetConstructorInput> inputs;

  /// Every neutral constructor input in declaration order, including inputs
  /// selectively omitted from [inputs] by target projection.
  final List<WidgetConstructorInput> allInputs;

  /// Loud failures and migration notices discovered during normalization.
  final List<Issue> issues;
}

/// Projects neutral constructor facts through one public emit target.
WidgetConstructorFacts projectWidgetConstructorFacts(
  ClassElement cls,
  AssetId assetId,
  WidgetConstructorFacts facts, {
  required EmitTarget target,
}) {
  final issues = <Issue>[...facts.issues];
  final inputs = <WidgetConstructorInput>[];
  final className = cls.name ?? '<unnamed>';
  final location = '${assetId.path}#$className';

  for (final input in facts.inputs) {
    if (!input.isIgnoredFor(target)) {
      inputs.add(input);
      continue;
    }
    final inputLocation = '$location.${input.name}';
    if (input.formal.isRequired) {
      issues.add(
        Issue(
          code: IssueCode.invalidWidgetConstructorInput,
          message: 'Constructor input $className.${input.name} is required '
              'and cannot be excluded with @Ignore. Give the parameter a '
              'default, or expose a catalog-facing wrapper that omits it.',
          location: inputLocation,
        ),
      );
    } else if (input.assertedNonNull) {
      issues.add(
        Issue(
          code: IssueCode.invalidWidgetConstructorInput,
          message: 'Constructor input $className.${input.name} is guarded by '
              'a non-null assert and cannot be excluded with @Ignore. '
              'Assertions are removed from release builds, so omission '
              'would not preserve the constructor contract. Give the '
              'parameter an ordinary default, or expose a catalog-facing '
              'wrapper that omits it.',
          location: inputLocation,
        ),
      );
    } else {
      // The omission is validated against the final emitted positional set,
      // after target capability exclusions are known.
    }
  }

  _addMigrationNotices(
    cls,
    inputs,
    assetId,
    issues,
    includeOrderNotice: false,
  );
  return WidgetConstructorFacts(
    inputs: inputs,
    allInputs: facts.allInputs,
    issues: issues,
  );
}

/// Returns [formal] and every analyzer-resolved inherited constructor formal.
///
/// The terminal element is ordinarily a field formal for an admitted inherited
/// input. A malformed cycle fails loudly rather than leaving constructor
/// authoring only partially inspected.
Iterable<FormalParameterElement> widgetConstructorFormalChain(
  FormalParameterElement formal,
) sync* {
  final seen = Set<FormalParameterElement>.identity();
  FormalParameterElement? current = formal;
  while (current != null) {
    final declaration = current.baseElement;
    if (!seen.add(declaration)) {
      throw StateError(
        'Constructor formal inheritance contains a cycle at '
        "'${declaration.name ?? '<unnamed>'}'.",
      );
    }
    yield declaration;
    current = declaration is SuperFormalParameterElement
        ? declaration.superConstructorParameter
        : null;
  }
}

/// Reads the unnamed generative constructor that generated factories call.
WidgetConstructorFacts readWidgetConstructorFacts(
  ClassElement cls,
  AssetId assetId,
) {
  final issues = <Issue>[];
  final inputs = <WidgetConstructorInput>[];
  final ignoredFields = <FieldElement>{};
  final className = cls.name ?? '<unnamed>';
  final location = '${assetId.path}#$className';
  final constructor = _unnamedGenerativeConstructor(cls);
  if (constructor == null) {
    issues.add(
      Issue(
        code: IssueCode.invalidWidgetConstructorInput,
        message: '$className has no unnamed generative constructor. Generated '
            'customer catalog factories require one.',
        location: location,
      ),
    );
    return WidgetConstructorFacts(
      inputs: inputs,
      allInputs: inputs,
      issues: issues,
    );
  }

  for (final formal in constructor.formalParameters) {
    final inputName = formal.name ?? '<unnamed>';
    final sourceName = formal is FieldFormalParameterElement
        ? formal.field?.name ?? inputName
        : inputName;
    final inputLocation = '$location.$sourceName';
    final resolved = _resolveInput(cls, constructor, formal);
    if (resolved case _ExcludedInput()) continue;
    if (resolved case _InvalidInput(:final reason)) {
      issues.add(
        Issue(
          code: IssueCode.invalidWidgetConstructorInput,
          message: 'Constructor input $inputName on $className cannot become '
              'a catalog property: $reason.',
          location: inputLocation,
        ),
      );
      continue;
    }
    final valid = resolved as _ResolvedInput;
    final assertedNonNull = _hasAssertedNonNullGuard(constructor, formal);
    final ignoreAnnotation = _inputAnnotation(formal, valid, 'Ignore');
    _IgnoreSelection? ignoreSelection;
    if (ignoreAnnotation != null) {
      ignoredFields.add(valid.field);
      final ignoreValue = ignoreAnnotation.computeConstantValue();
      if (ignoreValue == null) {
        // The exclusion is spelled but does not resolve, so it cannot be
        // honoured — and it must not be ignored either, because that would put
        // the input back into the catalog without saying so.
        issues.add(
          Issue(
            code: IssueCode.invalidWidgetConstructorInput,
            message: ignoreAnnotation.element == null
                ? '@ignore on $className.$inputName could not be resolved, so '
                    'the exclusion cannot be honoured. Treating it as absent '
                    'would put the input back into the generated catalog with '
                    'nothing to show for it. Check that the annotation is '
                    'imported.'
                : '@Ignore on $className.$inputName could not be '
                    'const-evaluated. Use a const list or set containing only '
                    'rfw_catalog_schema EmitTarget values.',
            location: inputLocation,
          ),
        );
        continue;
      }
      ignoreSelection = _readIgnoreSelection(
        ignoreValue,
        className: className,
        inputName: inputName,
        location: inputLocation,
        issues: issues,
      );
      if (ignoreSelection == null) {
        continue;
      }
    }
    final propertyAnnotation =
        _inputAnnotation(formal, valid, 'RestageProperty');
    final dartdocDescription = valid.inherited
        ? normalizeDartdoc(formal.documentationComment) ??
            normalizeDartdoc(valid.field.documentationComment) ??
            normalizeDartdoc(valid.backingFormal.documentationComment)
        : normalizeDartdoc(valid.field.documentationComment) ??
            normalizeDartdoc(formal.documentationComment);
    inputs.add(
      WidgetConstructorInput(
        formal: formal,
        field: valid.field,
        type: valid.type,
        propertyAnnotation: propertyAnnotation,
        dartdocDescription: dartdocDescription,
        constructorDefault: _constructorDefault(formal),
        assertedNonNull: assertedNonNull,
        nullable: cls.library.typeSystem.isNullable(valid.type),
        inherited: valid.inherited,
        hasIgnore: ignoreSelection != null,
        ignoreTargets: ignoreSelection?.targets,
      ),
    );
  }

  final boundFields = {
    for (final input in inputs) input.field,
    ...ignoredFields,
  };
  for (final field in cls.fields) {
    if (_catalogAnnotation(field, 'RestageProperty') == null ||
        boundFields.contains(field)) {
      continue;
    }
    issues.add(
      Issue(
        code: IssueCode.invalidWidgetConstructorInput,
        message: '@RestageProperty on $className.${field.name ?? '<unnamed>'} '
            'does not correspond to an input of the unnamed generative '
            'constructor. RestageProperty is an overlay, not an admission '
            'marker.',
        location: '$location.${field.name ?? '<unnamed>'}',
      ),
    );
  }

  // Preserve the neutral fact reader's historical migration diagnostics.
  // Selectively ignored inputs are added back only by target projection when
  // that target actually includes them.
  _addMigrationNotices(
    cls,
    inputs.where((input) => !input.hasIgnore).toList(growable: false),
    assetId,
    issues,
  );
  return WidgetConstructorFacts(
    inputs: inputs,
    allInputs: inputs,
    issues: issues,
  );
}

ConstructorElement? _unnamedGenerativeConstructor(ClassElement cls) =>
    cls.constructors
        .where(
          (candidate) =>
              !candidate.isFactory &&
              const {null, '', 'new'}.contains(candidate.name),
        )
        .firstOrNull;

final class _IgnoreSelection {
  const _IgnoreSelection({required this.targets});

  final Set<EmitTarget>? targets;
}

_IgnoreSelection? _readIgnoreSelection(
  DartObject value, {
  required String className,
  required String inputName,
  required String location,
  required List<Issue> issues,
}) {
  final targetValue = value.getField('targets');
  if (targetValue == null || targetValue.isNull) {
    return const _IgnoreSelection(targets: null);
  }
  final values =
      targetValue.toListValue() ?? targetValue.toSetValue()?.toList();
  if (values == null) {
    issues.add(
      Issue(
        code: IssueCode.invalidWidgetConstructorInput,
        message: '@Ignore on $className.$inputName uses a custom const '
            'Iterable that analyzer cannot enumerate. Use a const list or '
            'set of EmitTarget values.',
        location: location,
      ),
    );
    return null;
  }
  if (values.isEmpty) {
    issues.add(
      Issue(
        code: IssueCode.invalidWidgetConstructorInput,
        message: '@Ignore targets on $className.$inputName must not be empty. '
            'Omit targets to exclude every emit target.',
        location: location,
      ),
    );
    return null;
  }
  final targets = <EmitTarget>{};
  for (final targetValue in values) {
    final element = targetValue.type?.element;
    if (element is! EnumElement ||
        element.name != 'EmitTarget' ||
        element.library.identifier != _emitTargetOrigin) {
      issues.add(
        Issue(
          code: IssueCode.invalidWidgetConstructorInput,
          message: '@Ignore on $className.$inputName accepts only values from '
              'rfw_catalog_schema EmitTarget.',
          location: location,
        ),
      );
      return null;
    }
    final constant = canonicalAnalyzerEnumConstant(targetValue, element);
    final target = switch (constant?.identity.member) {
      'rfw' => EmitTarget.rfw,
      'a2ui' => EmitTarget.a2ui,
      'widgetbook' => EmitTarget.widgetbook,
      _ => null,
    };
    if (target == null) {
      issues.add(
        Issue(
          code: IssueCode.invalidWidgetConstructorInput,
          message: '@Ignore on $className.$inputName contains an unknown '
              'rfw_catalog_schema EmitTarget value.',
          location: location,
        ),
      );
      return null;
    }
    targets.add(target);
  }
  return _IgnoreSelection(
    targets: Set.unmodifiable([
      for (final target in EmitTarget.values)
        if (targets.contains(target)) target,
    ]),
  );
}

bool _hasAssertedNonNullGuard(
  ConstructorElement constructor,
  FormalParameterElement formal,
) {
  final name = formal.name;
  final declaration = _constructorDeclaration(constructor);
  if (name == null || declaration == null) return false;
  return declaration.initializers.whereType<AssertInitializer>().any(
        (initializer) => _assertRequiresNonNull(
          initializer.condition,
          constructor,
          formal,
        ),
      );
}

bool _assertRequiresNonNull(
  Expression expression,
  ConstructorElement constructor,
  FormalParameterElement formal,
) {
  final unwrapped = _unwrappedExpression(expression);
  if (unwrapped is IsExpression &&
      _isFormalReference(unwrapped.expression, formal)) {
    final testedType = _semanticTypeOf(unwrapped.type, constructor);
    if (testedType == null) return false;
    if (unwrapped.notOperator != null) return testedType.isDartCoreNull;
    return constructor.library.typeSystem.isNonNullable(testedType);
  }
  if (unwrapped is! BinaryExpression) return false;
  if (unwrapped.operator.lexeme == '&&') {
    return _assertRequiresNonNull(unwrapped.leftOperand, constructor, formal) ||
        _assertRequiresNonNull(unwrapped.rightOperand, constructor, formal);
  }
  if (unwrapped.operator.lexeme != '!=') return false;
  return (_isFormalReference(unwrapped.leftOperand, formal) &&
          _unwrappedExpression(unwrapped.rightOperand) is NullLiteral) ||
      (_unwrappedExpression(unwrapped.leftOperand) is NullLiteral &&
          _isFormalReference(unwrapped.rightOperand, formal));
}

DartType? _semanticTypeOf(
  TypeAnnotation annotation,
  ConstructorElement constructor,
) {
  final resolved = annotation.type;
  if (resolved != null) return resolved;
  if (annotation is! NamedType) return null;

  final suffix = annotation.question == null
      ? NullabilitySuffix.none
      : NullabilitySuffix.question;
  final name = annotation.name.lexeme;
  final typeProvider = constructor.library.typeProvider;
  if (annotation.importPrefix == null) {
    if (name == 'dynamic') return typeProvider.dynamicType;
    if (name == 'void') return typeProvider.voidType;
    if (name == 'Never') return typeProvider.neverType;
    if (name == 'Null') return typeProvider.nullType;
  }

  var element = annotation.element;
  if (element == null && annotation.importPrefix == null) {
    element = constructor.enclosingElement.typeParameters
        .where((parameter) => parameter.name == name)
        .firstOrNull;
  }
  final fragment = constructor.firstFragment.libraryFragment;
  if (element == null) {
    final prefixName = annotation.importPrefix?.name.lexeme;
    if (prefixName == null) {
      element = fragment.scope.lookup(name).getter;
    } else {
      final prefix = fragment.scope.lookup(prefixName).getter;
      if (prefix is PrefixElement) {
        element = prefix.scope.lookup(name).getter;
      }
    }
  }

  final arguments = <DartType>[];
  for (final argument
      in annotation.typeArguments?.arguments ?? const <TypeAnnotation>[]) {
    final type = _semanticTypeOf(argument, constructor);
    if (type == null) return null;
    arguments.add(type);
  }
  final typeSystem = constructor.library.typeSystem;
  return switch (element) {
    final TypeParameterElement parameter when arguments.isEmpty =>
      parameter.instantiate(nullabilitySuffix: suffix),
    final InterfaceElement interface when annotation.typeArguments == null =>
      typeSystem.instantiateInterfaceToBounds(
        element: interface,
        nullabilitySuffix: suffix,
      ),
    final InterfaceElement interface
        when arguments.length == interface.typeParameters.length =>
      interface.instantiate(
        typeArguments: arguments,
        nullabilitySuffix: suffix,
      ),
    final TypeAliasElement alias when annotation.typeArguments == null =>
      typeSystem.instantiateTypeAliasToBounds(
        element: alias,
        nullabilitySuffix: suffix,
      ),
    final TypeAliasElement alias
        when arguments.length == alias.typeParameters.length =>
      alias.instantiate(
        typeArguments: arguments,
        nullabilitySuffix: suffix,
      ),
    _ => null,
  };
}

bool _isFormalReference(
  Expression expression,
  FormalParameterElement formal,
) {
  final unwrapped = _unwrappedExpression(expression);
  return switch (unwrapped) {
    final SimpleIdentifier identifier =>
      _identifierRefersToFormal(identifier, formal),
    PropertyAccess(
      target: ThisExpression(),
      :final propertyName,
    ) =>
      formal is FieldFormalParameterElement &&
          (propertyName.element == null
              ? propertyName.name == formal.name
              : _identifierRefersToFormal(propertyName, formal)),
    _ => false,
  };
}

bool _identifierRefersToFormal(
  SimpleIdentifier identifier,
  FormalParameterElement formal,
) {
  final resolved = identifier.element;
  if (resolved != null) {
    if (identical(resolved.baseElement, formal.baseElement)) return true;
    final field = formal is FieldFormalParameterElement ? formal.field : null;
    return field != null && identical(resolved.baseElement, field.baseElement);
  }
  return identifier.name == formal.name &&
      _canBeUnresolvedValueReference(identifier, formal);
}

bool _canBeUnresolvedValueReference(
  SimpleIdentifier identifier,
  FormalParameterElement formal,
) {
  final parent = identifier.parent;
  if (parent is Label ||
      parent is BreakStatement ||
      parent is ContinueStatement ||
      parent is ConstructorFieldInitializer &&
          identical(parent.fieldName, identifier) ||
      parent is PrefixedIdentifier &&
          identical(parent.identifier, identifier) ||
      parent is PropertyAccess && identical(parent.propertyName, identifier) ||
      parent is NamedExpression && identical(parent.name.label, identifier)) {
    return false;
  }
  if (parent is MethodInvocation && identical(parent.methodName, identifier)) {
    return parent.target == null && formal.type is FunctionType;
  }
  return true;
}

Expression _unwrappedExpression(Expression expression) {
  var current = expression;
  while (current is ParenthesizedExpression) {
    current = current.expression;
  }
  return current;
}

WidgetConstructorDefaultFact _constructorDefault(
  FormalParameterElement formal,
) {
  if (!formal.hasDefaultValue) return const NoWidgetConstructorDefault();
  final value = formal.computeConstantValue();
  if (value == null) {
    return UnsupportedWidgetConstructorDefault(
      formal.defaultValueCode ?? '<unresolved>',
    );
  }
  final variable = value.variable;
  if (variable is FieldElement && variable.isEnumConstant) {
    final member = variable.name;
    final owner = variable.enclosingElement.name;
    final libraryUri = variable.library.identifier;
    if (member != null &&
        member.isNotEmpty &&
        !member.startsWith('_') &&
        owner != null &&
        owner.isNotEmpty &&
        !owner.startsWith('_') &&
        libraryUri.isNotEmpty) {
      return EnumWidgetConstructorDefault(
        libraryUri: libraryUri,
        owner: owner,
        member: member,
      );
    }
  }
  final staticMember = _staticMemberDefault(variable);
  if (staticMember != null) return staticMember;
  if (variable?.isConst ?? false) {
    return UnsupportedWidgetConstructorDefault(
      formal.defaultValueCode ?? '<unimportable const>',
    );
  }
  final function = value.toFunctionValue();
  if (function != null) {
    return _functionTearoffDefault(function) ??
        UnsupportedWidgetConstructorDefault(
          formal.defaultValueCode ?? '<unimportable function tear-off>',
        );
  }
  final reconstructed = _reconstructConstant(value);
  if (reconstructed != null) {
    return switch (reconstructed) {
      DartConstNull() => const NullWidgetConstructorDefault(),
      DartConstScalar(:final value) => LiteralWidgetConstructorDefault(value),
      _ => StructuralWidgetConstructorDefault(reconstructed),
    };
  }
  return UnsupportedWidgetConstructorDefault(
    formal.defaultValueCode ?? '<unrepresentable>',
  );
}

DartConstValue? _reconstructConstant(DartObject value) {
  // Preserve public const identity at every depth, not only for the formal's
  // outermost default. Analyzer exposes the referenced variable on nested
  // invocation arguments and collection members too. Resolve that identity
  // before inspecting the evaluated value so a public `const Object? x = null`
  // does not collapse to a literal null.
  final variable = value.variable;
  final referencedConstant = _staticMemberDefault(variable);
  if (referencedConstant != null) {
    return referencedConstant.reconstructedValue;
  }
  if (variable?.isConst ?? false) return null;
  if (value.isNull) return const DartConstNull();

  final invocation = value.constructorInvocation;
  if (invocation != null) {
    final constructor = invocation.constructor;
    final constructorName = constructor.name;
    final owner = constructor.enclosingElement;
    final ownerName = owner.name;
    final type = _reconstructType(value.type);
    final constructorIsPublic = constructorName == null ||
        constructorName.isEmpty ||
        !constructorName.startsWith('_');
    if (ownerName != null &&
        ownerName.isNotEmpty &&
        !ownerName.startsWith('_') &&
        constructorIsPublic &&
        type != null) {
      final positional = <DartConstValue>[];
      for (final argument in invocation.positionalArguments) {
        final reconstructed = _reconstructConstant(argument);
        if (reconstructed == null) return null;
        positional.add(reconstructed);
      }
      final named = <DartConstNamedValue>[];
      for (final argument in invocation.namedArguments.entries) {
        final reconstructed = _reconstructConstant(argument.value);
        if (reconstructed == null) return null;
        named.add(DartConstNamedValue(argument.key, reconstructed));
      }
      named.sort((a, b) => a.name.compareTo(b.name));
      return DartConstInvocation(
        type: type,
        constructorName: constructorName == null || constructorName.isEmpty
            ? null
            : constructorName,
        positional: positional,
        named: named,
      );
    }
  }

  final stringValue = value.toStringValue();
  if (stringValue != null) return DartConstScalar(stringValue);
  final boolValue = value.toBoolValue();
  if (boolValue != null) return DartConstScalar(boolValue);
  final intValue = value.toIntValue();
  if (intValue != null) return DartConstScalar(intValue);
  final doubleValue = value.toDoubleValue();
  if (doubleValue != null && doubleValue.isFinite) {
    return DartConstScalar(doubleValue);
  }

  final list = value.toListValue();
  if (list != null) {
    final type = _reconstructType(value.type);
    if (type == null) return null;
    final values = _reconstructValues(list);
    return values == null ? null : DartConstList(values, type: type);
  }
  final set = value.toSetValue();
  if (set != null) {
    final type = _reconstructType(value.type);
    if (type == null) return null;
    final values = _reconstructValues(set);
    return values == null ? null : DartConstSet(values, type: type);
  }
  final map = value.toMapValue();
  if (map != null) {
    final type = _reconstructType(value.type);
    if (type == null) return null;
    final entries = <DartConstMapEntry>[];
    for (final entry in map.entries) {
      final key = entry.key;
      final mapValue = entry.value;
      if (key == null || mapValue == null) return null;
      final reconstructedKey = _reconstructConstant(key);
      final reconstructedValue = _reconstructConstant(mapValue);
      if (reconstructedKey == null || reconstructedValue == null) return null;
      entries.add(DartConstMapEntry(reconstructedKey, reconstructedValue));
    }
    return DartConstMap(entries, type: type);
  }
  final record = value.toRecordValue();
  if (record != null) {
    final positional = _reconstructValues(record.positional);
    if (positional == null) return null;
    final named = <DartConstNamedValue>[];
    for (final field in record.named.entries) {
      final reconstructed = _reconstructConstant(field.value);
      if (reconstructed == null) return null;
      named.add(DartConstNamedValue(field.key, reconstructed));
    }
    named.sort((a, b) => a.name.compareTo(b.name));
    return DartConstRecord(positional: positional, named: named);
  }
  return null;
}

List<DartConstValue>? _reconstructValues(Iterable<DartObject> objects) {
  final result = <DartConstValue>[];
  for (final object in objects) {
    final reconstructed = _reconstructConstant(object);
    if (reconstructed == null) return null;
    result.add(reconstructed);
  }
  return result;
}

DartTypeIdentity? _reconstructType(DartType? type) {
  if (type == null) return null;
  final alias = type.alias;
  if (alias != null) {
    return _reconstructNamedType(
      name: alias.element.name,
      libraryUri: alias.element.library.identifier,
      typeArguments: alias.typeArguments,
      nullable: type.nullabilitySuffix == NullabilitySuffix.question,
    );
  }
  if (type is DynamicType) {
    return const DartTypeIdentity(
      libraryUri: 'dart:core',
      symbolName: 'dynamic',
    );
  }
  if (type is NeverType) {
    return DartTypeIdentity(
      libraryUri: 'dart:core',
      symbolName: 'Never',
      nullable: type.nullabilitySuffix == NullabilitySuffix.question,
    );
  }
  if (type is VoidType) {
    return const DartTypeIdentity(
      libraryUri: 'dart:core',
      symbolName: 'void',
    );
  }
  if (type is RecordType) {
    final positional = <DartTypeIdentity>[];
    for (final field in type.positionalFields) {
      final identity = _reconstructType(field.type);
      if (identity == null) return null;
      positional.add(identity);
    }
    final named = <DartRecordTypeNamedField>[];
    for (final field in type.namedFields) {
      if (field.name.startsWith('_')) return null;
      final identity = _reconstructType(field.type);
      if (identity == null) return null;
      named.add(DartRecordTypeNamedField(field.name, identity));
    }
    named.sort((a, b) => a.name.compareTo(b.name));
    return DartRecordTypeIdentity(
      positional: positional,
      named: named,
      nullable: type.nullabilitySuffix == NullabilitySuffix.question,
    );
  }
  if (type is! InterfaceType) return null;
  return _reconstructNamedType(
    name: type.element.name,
    libraryUri: type.element.library.identifier,
    typeArguments: type.typeArguments,
    nullable: type.nullabilitySuffix == NullabilitySuffix.question,
  );
}

DartTypeIdentity? _reconstructNamedType({
  required String? name,
  required String libraryUri,
  required Iterable<DartType> typeArguments,
  required bool nullable,
}) {
  if (name == null ||
      name.isEmpty ||
      name.startsWith('_') ||
      libraryUri.isEmpty) {
    return null;
  }
  final arguments = <DartTypeIdentity>[];
  for (final argument in typeArguments) {
    final reconstructed = _reconstructType(argument);
    if (reconstructed == null) return null;
    arguments.add(reconstructed);
  }
  return DartTypeIdentity(
    libraryUri: libraryUri,
    symbolName: name,
    typeArguments: arguments,
    nullable: nullable,
  );
}

StaticMemberWidgetConstructorDefault? _staticMemberDefault(
  VariableElement? variable,
) {
  if (variable == null || !variable.isConst) return null;

  final member = variable.name;
  final libraryUri = variable.library?.identifier;
  String? owner;
  var importable = member != null &&
      member.isNotEmpty &&
      !member.startsWith('_') &&
      libraryUri != null &&
      libraryUri.isNotEmpty;
  if (variable is FieldElement) {
    final enclosing = variable.enclosingElement;
    owner = switch (enclosing) {
      final InterfaceElement element => element.name,
      final ExtensionElement element => element.name,
      _ => null,
    };
    importable = importable &&
        variable.isStatic &&
        owner != null &&
        owner.isNotEmpty &&
        !owner.startsWith('_');
  } else if (variable is! TopLevelVariableElement) {
    importable = false;
  }
  if (!importable) return null;
  return StaticMemberWidgetConstructorDefault(
    libraryUri: libraryUri!,
    owner: owner,
    member: member!,
  );
}

StaticMemberWidgetConstructorDefault? _functionTearoffDefault(
  ExecutableElement function,
) {
  final member = function.name;
  final libraryUri = function.library.identifier;
  String? owner;
  var importable = member != null &&
      member.isNotEmpty &&
      !member.startsWith('_') &&
      libraryUri.isNotEmpty;
  if (function is MethodElement) {
    final enclosing = function.enclosingElement;
    owner = switch (enclosing) {
      final InterfaceElement element => element.name,
      final ExtensionElement element => element.name,
      _ => null,
    };
    importable = importable &&
        function.isStatic &&
        owner != null &&
        owner.isNotEmpty &&
        !owner.startsWith('_');
  } else if (function is! TopLevelFunctionElement) {
    importable = false;
  }
  if (!importable) return null;
  return StaticMemberWidgetConstructorDefault(
    libraryUri: libraryUri,
    owner: owner,
    member: member!,
  );
}

sealed class _InputResolution {
  const _InputResolution();
}

final class _ExcludedInput extends _InputResolution {
  const _ExcludedInput();
}

final class _InvalidInput extends _InputResolution {
  const _InvalidInput(this.reason);

  final String reason;
}

final class _ResolvedInput extends _InputResolution {
  const _ResolvedInput({
    required this.field,
    required this.backingFormal,
    required this.type,
    required this.inherited,
  });

  final FieldElement field;
  final FormalParameterElement backingFormal;
  final DartType type;
  final bool inherited;
}

/// Finds an annotation in constructor-authoring precedence order.
///
/// A local formal overrides its backing field, which overrides the inherited
/// field formal when this input is inherited.
ElementAnnotation? _inputAnnotation(
  FormalParameterElement formal,
  _ResolvedInput input,
  String name,
) =>
    _catalogAnnotation(formal, name) ??
    _catalogAnnotation(input.field, name) ??
    (input.inherited ? _catalogAnnotation(input.backingFormal, name) : null);

_InputResolution _resolveInput(
  ClassElement cls,
  ConstructorElement constructor,
  FormalParameterElement formal,
) {
  if (formal is FieldFormalParameterElement) {
    final field = formal.field;
    if (field == null) {
      return const _InvalidInput('the field formal has no resolved field');
    }
    final obstruction = _fieldObstruction(field, formal.type);
    if (obstruction != null) return _InvalidInput(obstruction);
    return _ResolvedInput(
      field: field,
      backingFormal: formal,
      type: formal.type,
      inherited: false,
    );
  }
  if (formal is! SuperFormalParameterElement) {
    if (_isFlutterKeyForwarding(constructor, formal)) {
      return const _ExcludedInput();
    }
    return _resolveOrdinaryInput(cls, constructor, formal);
  }

  if (_isFlutterKeySuperFormal(formal)) return const _ExcludedInput();

  final backing = _backingFieldFormal(formal);
  if (backing == null || backing.field == null) {
    return const _InvalidInput(
      'the super formal does not resolve through one field formal',
    );
  }
  final field = backing.field!;
  final type = effectiveWidgetConstructorFormalType(cls, formal);
  if (_isFlutterKeyPlumbing(field, type)) return const _ExcludedInput();
  final obstruction = _fieldObstruction(field, type);
  if (obstruction != null) return _InvalidInput(obstruction);
  if (_containsUnresolvedTypeParameter(type)) {
    return _InvalidInput(
      'the subclass-effective type ${type.getDisplayString()} contains an '
      'unresolved type parameter',
    );
  }
  return _ResolvedInput(
    field: field,
    backingFormal: backing,
    type: type,
    inherited: true,
  );
}

_InputResolution _resolveOrdinaryInput(
  ClassElement cls,
  ConstructorElement constructor,
  FormalParameterElement formal,
) {
  final declaration = _constructorDeclaration(constructor);
  if (formal.name == null || declaration == null) {
    return const _InvalidInput(
      'the ordinary parameter binding could not be resolved from its '
      'constructor declaration',
    );
  }

  final fieldInitializers = declaration.initializers
      .whereType<ConstructorFieldInitializer>()
      .toList(growable: false);
  final bindingInitializers = fieldInitializers
      .where(
        (initializer) => _isFormalReference(initializer.expression, formal),
      )
      .toList(growable: false);
  final transformedInitializers = fieldInitializers.where(
    (initializer) =>
        !bindingInitializers.contains(initializer) &&
        _referencesFormal(initializer.expression, formal),
  );
  if (bindingInitializers.isEmpty && transformedInitializers.isNotEmpty) {
    return const _InvalidInput(
      'the ordinary parameter is initializer-transformed before field '
      'assignment',
    );
  }
  final otherBindingUses = declaration.initializers.where((initializer) {
    if (initializer is AssertInitializer) return false;
    if (bindingInitializers.contains(initializer)) return false;
    return _referencesFormal(initializer, formal);
  });
  if (bindingInitializers.length != 1 || otherBindingUses.isNotEmpty) {
    return const _InvalidInput(
      'the ordinary parameter does not initialize exactly one field; '
      'initializer-transformed or otherwise non-bijective bindings are not '
      'admitted',
    );
  }
  final initializer = bindingInitializers.single;

  final matches = cls.fields.where(
    (field) => field.name == initializer.fieldName.name,
  );
  if (matches.length != 1) {
    return const _InvalidInput(
      'the ordinary parameter initializer has no unique backing field',
    );
  }
  final field = matches.single;
  final obstruction = _fieldObstruction(field, formal.type);
  if (obstruction != null) return _InvalidInput(obstruction);
  return _ResolvedInput(
    field: field,
    backingFormal: formal,
    type: formal.type,
    inherited: false,
  );
}

ConstructorDeclaration? _constructorDeclaration(
  ConstructorElement constructor,
) {
  final session = constructor.session;
  if (session == null) return null;
  final parsedLibrary = session.getParsedLibraryByElement(constructor.library);
  if (parsedLibrary is! ParsedLibraryResult) return null;
  final node =
      parsedLibrary.getFragmentDeclaration(constructor.firstFragment)?.node;
  return node is ConstructorDeclaration ? node : null;
}

bool _referencesFormal(AstNode node, FormalParameterElement formal) {
  final visitor = _FormalReferenceVisitor(formal);
  node.accept(visitor);
  return visitor.found;
}

final class _FormalReferenceVisitor extends RecursiveAstVisitor<void> {
  _FormalReferenceVisitor(this.formal);

  final FormalParameterElement formal;
  bool found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (_identifierRefersToFormal(node, formal)) found = true;
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    final shadowsFormal = node.parameters?.parameters.any(
          (parameter) => parameter.name?.lexeme == formal.name,
        ) ??
        false;
    if (!shadowsFormal) super.visitFunctionExpression(node);
  }

  @override
  void visitBlock(Block node) {
    var shadowed = false;
    for (final statement in node.statements) {
      if (shadowed) continue;
      if (statement
          case FunctionDeclarationStatement(:final functionDeclaration)
          when functionDeclaration.name.lexeme == formal.name) {
        shadowed = true;
        continue;
      }
      statement.accept(this);
      if (statement case VariableDeclarationStatement(:final variables)
          when variables.variables.any(
            (variable) => variable.name.lexeme == formal.name,
          )) {
        shadowed = true;
      }
    }
  }

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {
    if (node.functionDeclaration.name.lexeme != formal.name) {
      super.visitFunctionDeclarationStatement(node);
    }
  }
}

bool _isFlutterKeyForwarding(
  ConstructorElement constructor,
  FormalParameterElement formal,
) {
  final name = formal.name;
  if (name != 'key' || !_isFlutterKeyType(formal.type)) return false;
  final declaration = _constructorDeclaration(constructor);
  if (declaration == null) return false;
  final uses = declaration.initializers.where((initializer) {
    if (initializer is AssertInitializer) return false;
    return _referencesFormal(initializer, formal);
  }).toList(growable: false);
  if (uses.length != 1 || uses.single is! SuperConstructorInvocation) {
    return false;
  }
  final superCall = uses.single as SuperConstructorInvocation;
  return superCall.argumentList.arguments.any(
    (argument) =>
        argument is NamedExpression &&
        argument.name.label.name == 'key' &&
        _isFormalReference(argument.expression, formal),
  );
}

bool _isFlutterKeyType(DartType type) =>
    type is InterfaceType &&
    type.element.name == 'Key' &&
    type.element.library.identifier.startsWith('package:flutter/');

bool _isFlutterKeySuperFormal(SuperFormalParameterElement formal) {
  if (formal.name != 'key' || !_isFlutterKeyType(formal.type)) return false;

  final current = _terminalSuperConstructorParameter(formal);
  if (current == null || current.name != 'key') return false;
  if (current.library?.identifier.startsWith('package:flutter/') ?? false) {
    return true;
  }
  final enclosing = current.enclosingElement;
  return enclosing is ConstructorElement &&
      _isFlutterKeyForwarding(enclosing, current);
}

FieldFormalParameterElement? _backingFieldFormal(
  SuperFormalParameterElement formal,
) =>
    switch (_terminalSuperConstructorParameter(formal)) {
      final FieldFormalParameterElement parameter => parameter,
      _ => null,
    };

FormalParameterElement? _terminalSuperConstructorParameter(
  SuperFormalParameterElement formal,
) {
  FormalParameterElement? terminal;
  for (final current in widgetConstructorFormalChain(formal)) {
    terminal = current;
  }
  return terminal is SuperFormalParameterElement ? null : terminal;
}

String? _fieldObstruction(FieldElement field, DartType type) {
  final name = field.name;
  if (name == null || name.isEmpty || name.startsWith('_')) {
    return 'the backing field is private or unnamed';
  }
  if (field.isStatic || !field.isFinal) {
    return 'the backing member must be one final instance field';
  }
  if (_containsUnresolvedTypeParameter(type)) {
    return 'the effective type ${type.getDisplayString()} contains an '
        'unresolved type parameter';
  }
  return null;
}

bool _isFlutterKeyPlumbing(FieldElement field, DartType type) {
  return field.name == 'key' &&
      field.library.identifier.startsWith('package:flutter/') &&
      _isFlutterKeyType(type);
}

/// Returns [formal]'s subclass-effective type.
///
/// A super formal's own type can retain a type parameter from the declaring
/// constructor. Match the inherited accessor by analyzer element identity—not
/// by bare member name—before taking the instantiated return type.
DartType effectiveWidgetConstructorFormalType(
  ClassElement cls,
  FormalParameterElement formal,
) {
  if (formal is! SuperFormalParameterElement) return formal.type;
  final field = _backingFieldFormal(formal)?.field;
  if (field == null) return formal.type;
  return _inheritedFieldType(cls.thisType, field) ?? formal.type;
}

DartType? _inheritedFieldType(InterfaceType type, FieldElement field) {
  final name = field.name;
  if (name == null) return null;
  for (final supertype in type.allSupertypes) {
    final inherited = supertype.getGetter(name);
    if (inherited != null &&
        inherited.variable.baseElement == field.baseElement) {
      return inherited.returnType;
    }
  }
  return null;
}

bool _containsUnresolvedTypeParameter(DartType type) =>
    type.accept(const _UnresolvedTypeVisitor());

final class _UnresolvedTypeVisitor extends TypeVisitor<bool> {
  const _UnresolvedTypeVisitor();

  @override
  bool visitDynamicType(DynamicType type) => false;

  @override
  bool visitFunctionType(FunctionType type) =>
      _containsUnresolvedTypeParameter(type.returnType) ||
      type.formalParameters.any(
        (parameter) => _containsUnresolvedTypeParameter(parameter.type),
      );

  @override
  bool visitInterfaceType(InterfaceType type) =>
      type.typeArguments.any(_containsUnresolvedTypeParameter);

  @override
  bool visitInvalidType(InvalidType type) => true;

  @override
  bool visitNeverType(NeverType type) => false;

  @override
  bool visitRecordType(RecordType type) =>
      type.positionalFields.any(
        (field) => _containsUnresolvedTypeParameter(field.type),
      ) ||
      type.namedFields.any(
        (field) => _containsUnresolvedTypeParameter(field.type),
      );

  @override
  bool visitTypeParameterType(TypeParameterType type) => true;

  @override
  bool visitVoidType(VoidType type) => false;
}

void _addMigrationNotices(
  ClassElement cls,
  List<WidgetConstructorInput> inputs,
  AssetId assetId,
  List<Issue> issues, {
  bool includeOrderNotice = true,
}) {
  final className = cls.name ?? '<unnamed>';
  for (final input in inputs) {
    final annotation = input.propertyAnnotation;
    final String? message;
    if (annotation == null) {
      message = '$className.${input.name} is a supported public constructor '
          'input and is now included without @RestageProperty.';
    } else if (input.inherited) {
      message = '$className.${input.name} is a supported inherited constructor '
          'input and is now included. Legacy catalog discovery only '
          'admitted @RestageProperty fields declared directly on '
          '$className.';
    } else if (input.required && _declaresRequiredFalse(annotation)) {
      message = '$className.${input.name} is now a required catalog property. '
          'The constructor declares the parameter required, and the '
          'constructor is authoritative, so @RestageProperty(required: false) '
          'no longer weakens it.';
    } else {
      message = null;
    }
    if (message == null) continue;
    final location = '${assetId.path}#$className.${input.name}';
    if (!issues.any(
      (issue) =>
          issue.code == IssueCode.constructorCatalogMigration &&
          issue.location == location,
    )) {
      issues.add(
        Issue(
          code: IssueCode.constructorCatalogMigration,
          message: message,
          location: location,
        ),
      );
    }
  }

  if (includeOrderNotice) {
    _addConstructorOrderMigrationNotice(
      cls,
      inputs,
      assetId,
      issues,
    );
  }
}

/// Adds target-specific order migration diagnostics after final property
/// capability and positional-hole validation are known.
@internal
void addProjectedConstructorOrderMigrationNotice(
  ClassElement cls,
  WidgetConstructorFacts facts,
  AssetId assetId, {
  required EmitTarget target,
  required Set<String> emittedPropertyNames,
  required List<Issue> issues,
}) {
  if (!facts.allInputs.any((input) => input.ignoreTargets != null)) return;

  final legallyOmittedFields = Set<FieldElement>.identity();
  for (final (index, input) in facts.allInputs.indexed) {
    if (input.ignoreTargets == null ||
        !input.isIgnoredFor(target) ||
        input.required) {
      continue;
    }
    final createsPositionalHole = input.positional &&
        facts.allInputs.skip(index + 1).any(
              (later) =>
                  later.positional && emittedPropertyNames.contains(later.name),
            );
    if (!createsPositionalHole) legallyOmittedFields.add(input.field);
  }

  _addConstructorOrderMigrationNotice(
    cls,
    facts.inputs,
    assetId,
    issues,
    existingIssues: facts.issues,
    messagePrefix: 'For the ${target.name} target, ',
    omittedFields: legallyOmittedFields,
  );
}

void _addConstructorOrderMigrationNotice(
  ClassElement cls,
  List<WidgetConstructorInput> inputs,
  AssetId assetId,
  List<Issue> issues, {
  Iterable<Issue> existingIssues = const [],
  String messagePrefix = '',
  Set<FieldElement> omittedFields = const {},
}) {
  final className = cls.name ?? '<unnamed>';
  final annotated = [
    for (final input in inputs)
      if (input.propertyAnnotation != null) input,
  ];

  final fieldOrder = [
    for (final field in cls.fields)
      if (_catalogAnnotation(field, 'RestageProperty') != null &&
          !omittedFields.contains(field))
        field.name,
  ];
  final constructorOrder = [for (final input in annotated) input.name];
  if (fieldOrder.length == constructorOrder.length &&
      !_sameSequence(fieldOrder, constructorOrder)) {
    final location = '${assetId.path}#$className';
    if (!issues.any(
          (issue) =>
              issue.code == IssueCode.constructorCatalogMigration &&
              issue.location == location,
        ) &&
        !existingIssues.any(
          (issue) =>
              issue.code == IssueCode.constructorCatalogMigration &&
              issue.location == location,
        )) {
      issues.add(
        Issue(
          code: IssueCode.constructorCatalogMigration,
          message: '$messagePrefix$className catalog properties move '
              'from field order '
              '${fieldOrder.join(', ')} to constructor order '
              '${constructorOrder.join(', ')}.',
          location: location,
        ),
      );
    }
  }
}

/// Whether [annotation] explicitly writes `required: false`.
///
/// The annotation's `required` defaults to `false`, so the resolved constant
/// cannot tell an author who wrote `required: false` from one who omitted the
/// argument entirely. Only the first is a disagreement with the constructor
/// worth announcing; treating the second the same way would emit a migration
/// notice for every annotated required input in ordinary, correct code.
bool _declaresRequiredFalse(ElementAnnotation annotation) {
  final value = annotation.computeConstantValue();
  if (value?.getField('required')?.toBoolValue() != false) return false;
  return annotation
      .toSource()
      .replaceAll(RegExp(r'\s+'), '')
      .contains('required:false');
}

bool _sameSequence(List<String?> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// Normalizes a Dart documentation comment while preserving paragraphs.
///
/// Lines within one paragraph are joined with spaces. Paragraphs are retained
/// with a blank line so generated catalogs do not discard author context.
String? normalizeDartdoc(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final lines = <String>[];
  for (final line in raw.split('\n')) {
    var text = line.trimLeft();
    if (text.startsWith('///')) {
      text = text.substring(3);
      if (text.startsWith(' ')) text = text.substring(1);
    } else {
      if (text.startsWith('/**')) text = text.substring(3);
      if (text.endsWith('*/')) text = text.substring(0, text.length - 2);
      text = text.trimLeft();
      if (text.startsWith('*')) {
        text = text.substring(1);
        if (text.startsWith(' ')) text = text.substring(1);
      }
    }
    lines.add(text.trimRight());
  }
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  if (lines.isEmpty) return null;

  final paragraphs = <String>[];
  final current = <String>[];
  void flush() {
    if (current.isEmpty) return;
    paragraphs.add(current.map((line) => line.trim()).join(' ').trim());
    current.clear();
  }

  for (final line in lines) {
    if (line.trim().isEmpty) {
      flush();
    } else {
      current.add(line);
    }
  }
  flush();
  final normalized = paragraphs.where((text) => text.isNotEmpty).join('\n\n');
  return normalized.isEmpty ? null : normalized;
}
