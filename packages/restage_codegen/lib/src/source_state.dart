import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:restage_codegen/src/const_folding.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/owning_library_namespace.dart';
import 'package:restage_codegen/src/setstate_recognition.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';

/// Root-source build material for `@PaywallSource` and `@OnboardingSource`.
@immutable
final class SourceBuildBlueprint {
  /// Creates the source build blueprint.
  SourceBuildBlueprint({
    required this.rootExpression,
    this.buildContextParameter,
    List<CustomWidgetStateField>? state,
    List<RootContextParam> rootParams = const [],
    List<RootContextParam>? constructorParams,
    this.mountConstructorProblem,
    Map<String, RecognisedSetState> eventHandlers = const {},
    Map<Element, Expression> localBindings = const {},
  })  : state = state == null ? null : List.unmodifiable(state),
        rootParams = List.unmodifiable(rootParams),
        constructorParams = List.unmodifiable(constructorParams ?? rootParams),
        eventHandlers = Map.unmodifiable(eventHandlers),
        localBindings = Map.unmodifiable(localBindings);

  /// The returned expression from the effective `build()` host.
  final Expression rootExpression;

  /// The effective `build()`'s leading `final` locals, keyed by declared
  /// element; each reference resolves-through to the initializer.
  final Map<Element, Expression> localBindings;

  /// The effective `build()` method's `BuildContext` parameter element.
  final Element? buildContextParameter;

  /// Root `State` fields, or `null` for a stateless root.
  final List<CustomWidgetStateField>? state;

  /// Root constructor parameters in declaration order.
  final List<RootContextParam> rootParams;

  /// Every unnamed-constructor formal in declaration order.
  final List<RootContextParam> constructorParams;

  /// Why the selected constructor cannot preserve its key value in a mount.
  final String? mountConstructorProblem;

  /// Referenced State method tear-offs recognised as `setState` handlers.
  final Map<String, RecognisedSetState> eventHandlers;

  /// Roots for consumers that cannot resolve through [localBindings].
  /// Resolving consumers should walk [rootExpression] alone.
  late final List<Expression> collectorRoots = [
    rootExpression,
    ...localBindings.values,
  ];
}

enum _SourceWidgetKind { stateless, stateful }

const Set<String> _kLifecycleMethods = {
  'initState',
  'dispose',
  'didChangeDependencies',
  'didUpdateWidget',
  'deactivate',
  'activate',
  'reassemble',
};

/// Resolves [fragment] through the library that declares it.
Future<AstNode?> resolvedAstNodeFor(Fragment fragment) async {
  final library = fragment.libraryFragment?.element;
  if (library == null) return null;
  final result = await library.session.getResolvedLibraryByElement(library);
  if (result is! ResolvedLibraryResult) return null;
  return result.getFragmentDeclaration(fragment)?.node;
}

/// Extracts the effective root build expression and optional declarative state
/// for a `@PaywallSource` / `@OnboardingSource` root class.
Future<SourceBuildBlueprint?> extractSourceBuildBlueprint({
  required ClassElement sourceClass,
  required LibraryElement library,
  required Future<AstNode?> Function(Fragment fragment) astNodeFor,
  required List<Issue> issues,
  required String location,
}) async {
  final kind = _widgetKind(sourceClass);
  if (kind == null) {
    return null;
  }

  var buildHost = sourceClass;
  ClassElement? stateClass;
  if (kind == _SourceWidgetKind.stateful) {
    stateClass = await _resolveStateClass(sourceClass, astNodeFor);
    if (stateClass == null) {
      issues.add(
        Issue(
          code: IssueCode.stateShapeUnsupported,
          message: 'StatefulWidget root ${sourceClass.name ?? '<unnamed>'} '
              'must expose a createState() method that resolves to a '
              'concrete State class. This transpiler increment can only lower '
              'root state once the State class is statically known.',
          location: '$location.createState',
        ),
      );
      return null;
    }
    buildHost = stateClass;
  }

  final buildMethod =
      buildHost.methods.where((method) => method.name == 'build').firstOrNull;
  if (buildMethod == null) {
    issues.add(
      Issue(
        code: IssueCode.buildMethodMissing,
        message: '${buildHost.name ?? '<unnamed>'} has no build() method.',
        location: '$location.build',
      ),
    );
    return null;
  }
  final buildNode = await astNodeFor(buildMethod.firstFragment);
  if (buildNode is! MethodDeclaration) {
    issues.add(
      Issue(
        code: IssueCode.analyzerResolutionFailed,
        message: 'Could not locate the effective build() method declaration '
            'in the resolved AST.',
        location: '$location.build',
      ),
    );
    return null;
  }
  final extracted = extractInlinableBuildBody(buildNode.body);
  if (extracted == null) {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message: preludeDeclarationProblem(buildNode.body) ??
            'build() must be one returned widget expression, optionally '
                'preceded by initialized simple final or const variable '
                'declarations.',
        location: '$location.build',
      ),
    );
    return null;
  }
  final localBindings = extracted.localBindings;
  final preludeProblem = inlinableBuildBodyProblem(extracted);
  if (preludeProblem != null) {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message: preludeProblem,
        location: '$location.build',
      ),
    );
    return null;
  }
  final buildContextParameter = _buildContextParameter(buildMethod);
  final constructorFacts = await _constructorParams(sourceClass, astNodeFor);
  final constructorParams = constructorFacts.params;
  final rootParams = constructorParams
      .where((parameter) => !parameter.forwardsFlutterKey)
      .toList(growable: false);
  final blueprint = SourceBuildBlueprint(
    rootExpression: extracted.expression,
    buildContextParameter: buildContextParameter,
    rootParams: rootParams,
    constructorParams: constructorParams,
    mountConstructorProblem: constructorFacts.mountProblem,
    localBindings: localBindings,
  );
  if (stateClass == null) return blueprint;

  final state = await _collectStateFields(
    stateClass,
    astNodeFor: astNodeFor,
    issues: issues,
    location: location,
  );
  if (state == null) return null;
  final eventHandlers = await _collectReferencedHandlers(
    blueprint.collectorRoots,
    stateClass: stateClass,
    stateFieldNames: state.map((field) => field.name).toSet(),
    astNodeFor: astNodeFor,
  );
  for (final entry in eventHandlers.entries) {
    final verdict = entry.value;
    if (verdict is SetStateUnrecognised) {
      issues.add(
        Issue(
          code: IssueCode.stateShapeUnsupported,
          message: "State handler '${entry.key}' cannot be lowered: "
              '${verdict.reason}. Rewrite it as a single setState(...) '
              'assignment to one supported State field.',
          location: '$location.${entry.key}',
        ),
      );
      return null;
    }
  }
  return SourceBuildBlueprint(
    rootExpression: blueprint.rootExpression,
    buildContextParameter: blueprint.buildContextParameter,
    state: state,
    rootParams: rootParams,
    constructorParams: constructorParams,
    mountConstructorProblem: blueprint.mountConstructorProblem,
    eventHandlers: eventHandlers,
    localBindings: blueprint.localBindings,
  );
}

Future<({List<RootContextParam> params, String? mountProblem})>
    _constructorParams(
  ClassElement sourceClass,
  Future<AstNode?> Function(Fragment fragment) astNodeFor,
) async {
  final constructor = sourceClass.unnamedConstructor;
  if (constructor == null) {
    return (params: const <RootContextParam>[], mountProblem: null);
  }
  final namespace = OwningLibraryNamespace(sourceClass.library);
  final resolvedConstructor = await resolveWidgetConstructorFormals(
    sourceClass,
    constructor,
    astNodeFor,
  );
  final params = <RootContextParam>[];
  for (var index = 0; index < constructor.formalParameters.length; index++) {
    final parameter = constructor.formalParameters[index];
    final name = parameter.name;
    if (name == null || name.isEmpty) continue;
    final resolved = resolvedConstructor.formals[index];
    final defaultValue =
        parameter.hasDefaultValue ? parameter.computeConstantValue() : null;
    final typeFact = await _rootParamTypeFact(
      parameter,
      resolved.type,
      namespace,
      astNodeFor,
    );
    final mountDefault = await _mountDefaultExpression(
      resolved,
      namespace,
      astNodeFor,
    );
    final hostData = deriveHostDataShape(resolved.type, root: name);
    params.add(
      RootContextParam(
        name: name,
        type: resolved.type,
        typeCode: typeFact.code,
        kind: parameter.isOptionalPositional
            ? RootContextParamKind.optionalPositional
            : parameter.isNamed
                ? RootContextParamKind.named
                : RootContextParamKind.requiredPositional,
        hostDataShape: hostData.shape,
        hostDataProblem: hostData.problem,
        field: resolved.field,
        isRequired: parameter.isRequired,
        defaultValueCode: parameter.defaultValueCode,
        hasNullDefault: parameter.hasDefaultValue &&
            defaultValue != null &&
            defaultValue.isNull,
        mountDefaultValueCode: mountDefault.code,
        mountDefaultProblem: mountDefault.problem,
        forwardsFlutterKey: resolved.forwardsFlutterKey,
        usesSuperFormal: parameter is SuperFormalParameterElement,
        usesStatelessWidgetSuperFormal: resolved.usesStatelessWidgetSuperFormal,
        hasExplicitType: typeFact.hasExplicitType,
      ),
    );
  }
  return (
    params: params,
    mountProblem: resolvedConstructor.mountProblem,
  );
}

Future<({String? code, String? problem})> _mountDefaultExpression(
  ResolvedWidgetConstructorFormal resolved,
  OwningLibraryNamespace namespace,
  Future<AstNode?> Function(Fragment fragment) astNodeFor,
) async {
  final parameter = resolved.formal;
  if (!parameter.hasDefaultValue) return (code: null, problem: null);
  for (final declaration in resolved.defaultDeclarations) {
    final node = await astNodeFor(declaration.firstFragment);
    final expression =
        node is DefaultFormalParameter ? node.defaultValue : null;
    if (expression == null) continue;
    final contents = declaration.firstFragment.libraryFragment?.source.contents;
    if (contents == null || expression.end > contents.data.length) {
      return (
        code: null,
        problem: 'the resolved default source is unavailable',
      );
    }
    final compiler = _ResolvedDefaultExpressionCompiler(
      namespace,
      expression.offset,
    );
    expression.accept(compiler);
    if (compiler.problem case final problem?) {
      return (code: null, problem: problem);
    }
    var source = contents.data.substring(expression.offset, expression.end);
    final replacements = compiler.replacements
      ..sort((left, right) => right.start.compareTo(left.start));
    for (final replacement in replacements) {
      source = source.replaceRange(
        replacement.start,
        replacement.end,
        replacement.value,
      );
    }
    return (code: source, problem: null);
  }
  return (
    code: null,
    problem: 'the resolved default expression is unavailable',
  );
}

final class _ResolvedDefaultExpressionCompiler
    extends RecursiveAstVisitor<void> {
  _ResolvedDefaultExpressionCompiler(
    this.namespace,
    this.baseOffset,
  );

  final OwningLibraryNamespace namespace;
  final int baseOffset;
  final List<({int start, int end, String value})> replacements = [];
  String? problem;

  @override
  void visitDotShorthandConstructorInvocation(
    DotShorthandConstructorInvocation node,
  ) {
    final constructor = node.element;
    final owner = constructor?.enclosingElement;
    final ownerName = owner == null ? null : namespace.elementName(owner);
    final constructorName = constructor?.name;
    if (constructor == null ||
        !_memberIsVisible(constructor) ||
        ownerName == null ||
        constructorName == null) {
      _fail();
      return;
    }
    final suffix = constructorName == 'new' ? '' : '.$constructorName';
    _replace(node.period.offset, node.constructorName.end, '$ownerName$suffix');
    node.typeArguments?.accept(this);
    node.argumentList.accept(this);
  }

  @override
  void visitDotShorthandInvocation(DotShorthandInvocation node) {
    final element = node.memberName.element;
    final spelling = element == null
        ? null
        : namespace.staticMemberName(element, includeAliases: false);
    if (spelling == null) {
      _fail();
      return;
    }
    _replace(node.offset, node.memberName.end, spelling);
    node.typeArguments?.accept(this);
    node.argumentList.accept(this);
  }

  @override
  void visitDotShorthandPropertyAccess(DotShorthandPropertyAccess node) {
    final element = node.propertyName.element;
    final spelling = element == null
        ? null
        : namespace.staticMemberName(element, includeAliases: false);
    if (spelling == null) {
      _fail();
      return;
    }
    _replace(node.offset, node.end, spelling);
  }

  @override
  void visitConstructorName(ConstructorName node) {
    final constructor = node.element;
    if (constructor == null || !_memberIsVisible(constructor)) {
      _fail();
      return;
    }
    node.type.accept(this);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final element = node.methodName.element;
    if (element == null) {
      _fail();
      return;
    }
    final spelling = _referenceSpelling(element);
    final target = node.target;
    if (spelling != null) {
      final start = target?.offset ?? node.methodName.offset;
      _replace(start, node.methodName.end, spelling);
    } else if (target == null || !_memberIsVisible(element)) {
      _fail();
      return;
    } else {
      target.accept(this);
    }
    node.typeArguments?.accept(this);
    node.argumentList.accept(this);
  }

  @override
  void visitNamedType(NamedType node) {
    final element = node.element;
    if (element == null) {
      if (node.name.lexeme != 'dynamic' && node.name.lexeme != 'void') {
        _fail();
      }
    } else {
      final spelling = namespace.elementName(element);
      if (spelling == null) {
        _fail();
        return;
      }
      _replace(
        node.importPrefix?.offset ?? node.name.offset,
        node.name.end,
        spelling,
      );
    }
    node.typeArguments?.accept(this);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final element = node.identifier.element;
    if (element == null) {
      _fail();
      return;
    }
    final spelling = _referenceSpelling(element);
    if (spelling != null) {
      _replace(node.offset, node.end, spelling);
      return;
    }
    if (!_memberIsVisible(element)) {
      _fail();
      return;
    }
    node.prefix.accept(this);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final element = node.propertyName.element;
    if (element == null) {
      _fail();
      return;
    }
    final spelling = _referenceSpelling(element);
    if (spelling != null) {
      _replace(node.offset, node.end, spelling);
      return;
    }
    if (!_memberIsVisible(element) || node.target == null) {
      _fail();
      return;
    }
    node.target!.accept(this);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.inDeclarationContext() || _isSelectorName(node)) {
      return;
    }
    final element = node.element;
    final spelling = element == null ? null : _referenceSpelling(element);
    if (spelling == null) {
      _fail();
      return;
    }
    _replace(node.offset, node.end, spelling);
  }

  String? _referenceSpelling(Element rawElement) {
    final element = _referencedDefaultElement(rawElement);
    final enclosing = element.enclosingElement;
    if (enclosing is LibraryElement) {
      return namespace.elementName(element);
    }
    return namespace.staticMemberName(element);
  }

  bool _memberIsVisible(Element rawElement) {
    final element = _referencedDefaultElement(rawElement);
    return !element.isPrivate || element.library == namespace.library;
  }

  void _replace(int start, int end, String value) {
    replacements.add(
      (
        start: start - baseOffset,
        end: end - baseOffset,
        value: value,
      ),
    );
  }

  void _fail() {
    problem ??= 'a referenced declaration has no visible spelling';
  }
}

Element _referencedDefaultElement(Element element) =>
    (element is PropertyAccessorElement ? element.variable : element)
        .baseElement;

bool _isSelectorName(SimpleIdentifier identifier) =>
    switch (identifier.parent) {
      ConstructorName(:final name) when identical(name, identifier) => true,
      Label(:final label) when identical(label, identifier) => true,
      MethodInvocation(:final methodName)
          when identical(methodName, identifier) =>
        true,
      PrefixedIdentifier(identifier: final selector)
          when identical(selector, identifier) =>
        true,
      PropertyAccess(:final propertyName)
          when identical(propertyName, identifier) =>
        true,
      _ => false,
    };

Future<({String? code, bool hasExplicitType})> _rootParamTypeFact(
  FormalParameterElement parameter,
  DartType effectiveType,
  OwningLibraryNamespace namespace,
  Future<AstNode?> Function(Fragment fragment) astNodeFor,
) async {
  final node = await astNodeFor(parameter.firstFragment);
  final formal = switch (node) {
    DefaultFormalParameter(:final parameter) => parameter,
    NormalFormalParameter() => node,
    _ => null,
  };
  if (formal == null) {
    return (
      code: namespace.typeCode(effectiveType),
      hasExplicitType: false,
    );
  }

  final explicit = _formalTypeCode(formal);
  if (explicit != null) return (code: explicit, hasExplicitType: true);

  final field =
      parameter is FieldFormalParameterElement ? parameter.field : null;
  if (field != null) {
    for (var fieldNode = await astNodeFor(field.firstFragment);
        fieldNode != null;
        fieldNode = fieldNode.parent) {
      if (fieldNode case VariableDeclarationList(:final type?)) {
        return (code: type.toSource(), hasExplicitType: false);
      }
    }
  }
  return (
    code: namespace.typeCode(effectiveType),
    hasExplicitType: false,
  );
}

/// The authored type spelling of [formal], or null when it has none.
String? _formalTypeCode(NormalFormalParameter formal) => switch (formal) {
      SimpleFormalParameter(:final type) => type?.toSource(),
      FieldFormalParameter(:final type, parameters: null) => type?.toSource(),
      SuperFormalParameter(:final type, parameters: null) => type?.toSource(),
      FieldFormalParameter() ||
      SuperFormalParameter() ||
      FunctionTypedFormalParameter() =>
        _functionFormalType(formal),
    };

/// Renders an old-style function-typed formal as a function type. Parameter
/// modifiers, metadata and defaults are declaration-only and are dropped.
String _functionFormalType(NormalFormalParameter formal) {
  final (
    TypeAnnotation? returnType,
    TypeParameterList? typeParameters,
    FormalParameterList parameters,
    Token? question,
  ) = switch (formal) {
    FunctionTypedFormalParameter(
      :final returnType,
      :final typeParameters,
      :final parameters,
      :final question,
    ) =>
      (returnType, typeParameters, parameters, question),
    FieldFormalParameter(
      :final type,
      :final typeParameters,
      :final parameters!,
      :final question,
    ) =>
      (type, typeParameters, parameters, question),
    SuperFormalParameter(
      :final type,
      :final typeParameters,
      :final parameters!,
      :final question,
    ) =>
      (type, typeParameters, parameters, question),
    _ => throw StateError('Expected a function-typed parameter.'),
  };
  final requiredPositional = <String>[];
  final optionalPositional = <String>[];
  final named = <String>[];
  for (final parameter in parameters.parameters) {
    final normal = switch (parameter) {
      DefaultFormalParameter(:final parameter) => parameter,
      NormalFormalParameter() => parameter,
    };
    final type = _formalTypeCode(normal) ?? 'dynamic';
    final name = normal.name?.lexeme;
    final source = name == null ? type : '$type $name';
    if (parameter.isNamed) {
      named.add('${parameter.isRequiredNamed ? 'required ' : ''}$source');
    } else if (parameter.isOptionalPositional) {
      optionalPositional.add(source);
    } else {
      requiredPositional.add(source);
    }
  }
  final arguments = [
    ...requiredPositional,
    if (optionalPositional.isNotEmpty) '[${optionalPositional.join(', ')}]',
    if (named.isNotEmpty) '{${named.join(', ')}}',
  ].join(', ');
  final source = '${returnType?.toSource() ?? 'dynamic'} Function'
      '${typeParameters?.toSource() ?? ''}($arguments)';
  return question == null ? source : '$source?';
}

Element? _buildContextParameter(MethodElement buildMethod) {
  final parameters = buildMethod.formalParameters;
  if (parameters.length != 1) return null;
  final parameter = parameters.single;
  final type = parameter.type;
  if (type is! InterfaceType || type.element.name != 'BuildContext') {
    return null;
  }
  return parameter;
}

_SourceWidgetKind? _widgetKind(ClassElement cls) {
  var supertype = cls.supertype;
  while (supertype != null) {
    final name = supertype.element.name;
    if (name == 'StatelessWidget') return _SourceWidgetKind.stateless;
    if (name == 'StatefulWidget') return _SourceWidgetKind.stateful;
    supertype = supertype.element.supertype;
  }
  return null;
}

Future<ClassElement?> _resolveStateClass(
  ClassElement widget,
  Future<AstNode?> Function(Fragment fragment) astNodeFor,
) async {
  final createState = widget.methods
      .where((method) => method.name == 'createState')
      .firstOrNull;
  if (createState == null) return null;
  final returnType = createState.returnType;
  if (returnType is InterfaceType) {
    final element = returnType.element;
    if (element is ClassElement && element.name != 'State') {
      return element;
    }
  }
  final node = await astNodeFor(createState.firstFragment);
  if (node is MethodDeclaration) {
    final returned = singleReturnExpressionOf(node.body);
    if (returned is InstanceCreationExpression) {
      final element = returned.constructorName.type.element;
      if (element is ClassElement) return element;
    }
  }
  return null;
}

Future<List<CustomWidgetStateField>?> _collectStateFields(
  ClassElement stateClass, {
  required Future<AstNode?> Function(Fragment fragment) astNodeFor,
  required List<Issue> issues,
  required String location,
}) async {
  for (final method in stateClass.methods) {
    if (_kLifecycleMethods.contains(method.name)) {
      issues.add(
        Issue(
          code: IssueCode.stateShapeUnsupported,
          message: 'State lifecycle method ${method.name}() cannot be '
              'represented in declarative root source state. Move lifecycle '
              'work into host code or a custom widget.',
          location: '$location.${method.name}',
        ),
      );
      return null;
    }
  }
  final primitiveFields = <FieldElement>[];
  for (final field in stateClass.fields) {
    if (field.isStatic) continue;
    if (!_isPrimitiveType(field.type)) {
      issues.add(
        Issue(
          code: IssueCode.stateShapeUnsupported,
          message: "State field '${field.name}' has unsupported type "
              '${field.type}. Root source state supports only bool, int, '
              'double, num, String, and enum fields with constant '
              'initializers.',
          location: '$location.${field.name ?? '<unnamed>'}',
        ),
      );
      return null;
    }
    primitiveFields.add(field);
  }
  final initialValues = await Future.wait([
    for (final field in primitiveFields)
      _foldFieldInitialiser(field, astNodeFor: astNodeFor),
  ]);
  for (var i = 0; i < primitiveFields.length; i++) {
    if (initialValues[i] == null) {
      final field = primitiveFields[i];
      issues.add(
        Issue(
          code: IssueCode.stateShapeUnsupported,
          message: "State field '${field.name}' must have a non-null "
              'constant scalar or enum initializer for root source state.',
          location: '$location.${field.name ?? '<unnamed>'}',
        ),
      );
      return null;
    }
  }
  return [
    for (var i = 0; i < primitiveFields.length; i++)
      CustomWidgetStateField(
        name: primitiveFields[i].name ?? '<unnamed>',
        isNumeric: _isNumericType(primitiveFields[i].type),
        initialValue: initialValues[i],
      ),
  ];
}

Future<Object?> _foldFieldInitialiser(
  FieldElement field, {
  required Future<AstNode?> Function(Fragment fragment) astNodeFor,
}) async {
  final node = await astNodeFor(field.firstFragment);
  if (node is! VariableDeclaration) return null;
  final initializer = node.initializer;
  if (initializer == null) return null;
  return tryFoldConstant(initializer) ?? enumConstantName(initializer);
}

Future<Map<String, RecognisedSetState>> _collectReferencedHandlers(
  Iterable<Expression> roots, {
  required ClassElement stateClass,
  required Set<String> stateFieldNames,
  required Future<AstNode?> Function(Fragment fragment) astNodeFor,
}) async {
  final collector = _ReferencedStateMethodCollector(stateClass);
  for (final root in roots) {
    root.accept(collector);
  }
  final methods = collector.methods.toList();
  final methodNodes = await Future.wait([
    for (final method in methods) astNodeFor(method.firstFragment),
  ]);
  return {
    for (var i = 0; i < methods.length; i++)
      methods[i].name ?? '<unnamed>': switch (methodNodes[i]) {
        final MethodDeclaration methodNode => recogniseSetState(
            methodNode,
            stateFieldNames: stateFieldNames,
          ),
        _ => const SetStateUnrecognised(
            reason: 'the method source was not available to the transpiler',
          ),
      },
  };
}

final class _ReferencedStateMethodCollector extends RecursiveAstVisitor<void> {
  _ReferencedStateMethodCollector(this.stateClass);

  final ClassElement stateClass;
  final Set<MethodElement> methods = {};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _add(node.element);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _add(node.identifier.element);
    super.visitPrefixedIdentifier(node);
  }

  void _add(Element? element) {
    final resolved = _unwrapAccessor(element);
    if (resolved is MethodElement && resolved.enclosingElement == stateClass) {
      methods.add(resolved);
    }
  }
}

Element? _unwrapAccessor(Element? element) =>
    element is PropertyAccessorElement ? element.variable : element;

bool _isPrimitiveType(DartType type) {
  if (type is! InterfaceType) return false;
  final element = type.element;
  if (element is EnumElement) return true;
  const primitives = {'bool', 'int', 'double', 'num', 'String'};
  return primitives.contains(element.name);
}

bool _isNumericType(DartType type) {
  if (type is! InterfaceType) return false;
  final name = type.element.name;
  return name == 'double' || name == 'num';
}
