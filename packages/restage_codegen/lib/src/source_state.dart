import 'dart:collection';

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
import 'package:restage_codegen/src/dot_shorthand_expansion.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_codegen/src/islands/context_reach.dart';
import 'package:restage_codegen/src/islands/islands.dart' show readableSource;
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/owning_library_namespace.dart';
import 'package:restage_codegen/src/setstate_recognition.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

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
    List<FormalParameterElement> buildArguments = const [],
    Map<String, RecognisedSetState> eventHandlers = const {},
    Map<Element, Expression> localBindings = const {},
    Map<Element, HelperDef> helpers = const {},
    this.liftedState,
    this.liftable,
    this.stateKeptInApp,
    this.contentFree = ContentFreeBuilders.none,
    List<Statement> statements = const [],
    List<ReturnStatement> returns = const [],
  }) : state = state == null ? null : List.unmodifiable(state),
       rootParams = List.unmodifiable(rootParams),
       constructorParams = List.unmodifiable(constructorParams ?? rootParams),
       buildArguments = List.unmodifiable(buildArguments),
       eventHandlers = Map.unmodifiable(eventHandlers),
       inlined = InlinedDefinitions(
         localBindings: Map.unmodifiable(
           withHelperLocals(localBindings, helpers.values),
         ),
         helpers: Map.unmodifiable(helpers),
         statements: List.unmodifiable(statements),
         returns: List.unmodifiable(returns),
       );

  /// The returned expression from the effective `build()` host.
  final Expression rootExpression;

  /// The effective `build()`'s leading `final` locals and the same-class and
  /// same-library helpers its calls inline.
  final InlinedDefinitions inlined;

  /// The effective `build()`'s leading `final` locals and those of its
  /// helpers, keyed by declared element; each reference resolves-through to
  /// the initializer.
  Map<Element, Expression> get localBindings => inlined.localBindings;

  /// Same-class and same-library helpers `build()` calls, keyed by element;
  /// each call inlines the helper's body.
  Map<Element, HelperDef> get helpers => inlined.helpers;

  /// The effective `build()` method's `BuildContext` parameter element.
  final Element? buildContextParameter;

  /// The parameters `build()` takes after its context, such as a `ref`.
  final List<FormalParameterElement> buildArguments;

  /// Root `State` fields, or `null` for a stateless root.
  final List<CustomWidgetStateField>? state;

  /// The root's `State` class when it moves into the generated mount whole.
  final ClassElement? liftedState;

  /// This build with its `State` also in the mount, for the mount's copy of
  /// the build; the next one keeps none of it in the design.
  final SourceBuildBlueprint? liftable;

  /// Why this build's `State` stays in the app, when it does.
  final Issue? stateKeptInApp;

  /// This build with its whole `State` in the mount and none in the design.
  SourceBuildBlueprint? get wholeLift =>
      liftedState != null && state == null ? this : liftable?.wholeLift;

  /// Which builders in this build run once per build of their widget.
  final ContentFreeBuilders contentFree;

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
    for (final helper in helpers.values) helper.body,
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
  final result = await resolveLibraryInLongForm(library);
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
  Catalog? catalog,
  bool liftState = false,
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
          message:
              'StatefulWidget root ${sourceClass.name ?? '<unnamed>'} '
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

  final buildMethod = buildHost.methods
      .where((method) => method.name == 'build')
      .firstOrNull;
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
        message:
            'Could not locate the effective build() method declaration '
            'in the resolved AST.',
        location: '$location.build',
      ),
    );
    return null;
  }
  // A mounted surface's mount runs any other build as written.
  final mounted = liftState ? mountedBuildBody(buildNode.body) : null;
  var extracted = extractInlinableBuildBody(buildNode.body);
  final preludeProblem = extracted == null
      ? null
      : inlinableBuildBodyProblem(extracted, keepsKeys: mounted != null);
  final statements = <Statement>[];
  final returns = <ReturnStatement>[];
  if ((extracted == null || preludeProblem != null) && mounted != null) {
    statements.addAll(mounted.statements);
    if (mounted.returns.length > 1) returns.addAll(mounted.returns);
    extracted = InlinableBuildBody(
      expression: mounted.returns.last.expression!,
      declarations: const [],
      finalLocals: const [],
    );
  } else if (extracted == null) {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message:
            preludeDeclarationProblem(buildNode.body) ??
            _buildStatementRefusal(
              refusedBuildStatement(
                    buildNode.body,
                    mounted: mounted == null && liftState,
                  ) ??
                  buildNode.body,
            ),
        location: '$location.build',
      ),
    );
    return null;
  } else if (preludeProblem != null) {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message: preludeProblem,
        location: '$location.build',
      ),
    );
    return null;
  }
  final localBindings = extracted.localBindings;
  final reachable = await reachableArtifactHelpers(
    [
      extracted.expression,
      ...localBindings.values,
      for (final statement in returns) statement.expression!,
    ],
    astNodeFor: astNodeFor,
    admittedHelperPackages: artifactHelperPackages(catalog),
  );
  if (reachable.recursive case final helper?) {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message:
            "build() makes a recursive helper call ('${helper.name}'); "
            'a helper cannot call itself.',
        location: '$location.${helper.name}',
      ),
    );
    return null;
  }
  final buildContextParameter = _buildContextParameter(buildMethod);
  final buildArguments = buildContextParameter == null
      ? const <FormalParameterElement>[]
      : buildMethod.formalParameters.skip(1).toList();
  final constructorFacts = await _constructorParams(sourceClass, astNodeFor);
  final constructorParams = constructorFacts.params;
  final rootParams = constructorParams
      .where((parameter) => !parameter.forwardsFlutterKey)
      .toList(growable: false);
  final contentFree = await contentFreeBuilders(
    [extracted.expression, ...localBindings.values],
    astNodeFor: astNodeFor,
  );
  final blueprint = SourceBuildBlueprint(
    contentFree: contentFree,
    rootExpression: extracted.expression,
    buildContextParameter: buildContextParameter,
    rootParams: rootParams,
    constructorParams: constructorParams,
    mountConstructorProblem: constructorFacts.mountProblem,
    buildArguments: buildArguments,
    localBindings: localBindings,
    helpers: reachable.helpers,
    statements: statements,
    returns: returns,
  );
  if (stateClass == null) return blueprint;

  SourceBuildBlueprint lifted({
    List<CustomWidgetStateField>? state,
    Map<String, RecognisedSetState> eventHandlers = const {},
    SourceBuildBlueprint? liftable,
    Issue? keptInApp,
  }) => SourceBuildBlueprint(
    contentFree: contentFree,
    rootExpression: blueprint.rootExpression,
    buildContextParameter: blueprint.buildContextParameter,
    state: state,
    eventHandlers: eventHandlers,
    rootParams: rootParams,
    constructorParams: constructorParams,
    mountConstructorProblem: blueprint.mountConstructorProblem,
    localBindings: blueprint.localBindings,
    helpers: blueprint.helpers,
    liftedState: stateClass,
    liftable: liftable,
    stateKeptInApp: keptInApp,
    statements: statements,
    returns: returns,
  );
  // A build the mount runs as written runs where its State is.
  if (statements.isNotEmpty) return lifted();
  // A mounted surface whose State does not lower moves it into the mount.
  final stateIssues = <Issue>[];
  final state = await _collectStateFields(
    stateClass,
    astNodeFor: astNodeFor,
    issues: liftState ? stateIssues : issues,
    location: location,
  );
  if (state == null) return liftState ? lifted() : null;
  final eventHandlers = await _collectReferencedHandlers(
    [blueprint.rootExpression, ...blueprint.localBindings.values],
    stateClass: stateClass,
    stateFieldNames: state.map((field) => field.name).toSet(),
    helpers: blueprint.helpers,
    astNodeFor: astNodeFor,
  );
  for (final entry in eventHandlers.entries) {
    final verdict = entry.value;
    if (verdict is SetStateUnrecognised) {
      if (liftState) {
        final kept =
            "`${stateClass.name}` stays in your app's code, so a published "
            "design can't change it";
        // The advice follows what the method does: set state, compute a
        // value, or call back into the app.
        final declaration = switch (stateClass.getMethod(entry.key)) {
          final method? => await astNodeFor(method.firstFragment),
          null => null,
        };
        // An async callback returning `Future<void>` returns nothing either.
        final returnsValue = switch (declaration) {
          MethodDeclaration(returnType: TypeAnnotation(:final type?)) =>
            !(type is VoidType ||
                type is InterfaceType &&
                    (type.isDartAsyncFuture || type.isDartAsyncFutureOr) &&
                    type.typeArguments.single is VoidType),
          _ => false,
        };
        final setsState =
            declaration is! MethodDeclaration ||
            await _setsState(declaration, stateClass, astNodeFor, {});
        return lifted(
          keptInApp: Issue(
            code: IssueCode.stateKeptInApp,
            message: setsState
                ? "$kept: in '${entry.key}', ${verdict.reason}. Try writing "
                      '${entry.key} as one `setState(() => field = value)` '
                      'call.'
                : returnsValue
                ? "$kept: the build calls '${entry.key}', a method of the "
                      'State that your app runs. Try computing that value in '
                      'a build local from fields the design keeps.'
                : "$kept: the build passes '${entry.key}', a method of the "
                      'State that your app runs. Try writing the call inline '
                      'as a closure, as in '
                      '`() => widget.onContinue?.call(annualSelected)`, which '
                      'the design can split.',
            location: '$location.${entry.key}',
          ),
        );
      }
      issues.add(
        Issue(
          code: IssueCode.stateShapeUnsupported,
          message:
              "State handler '${entry.key}' cannot be lowered: "
              '${verdict.reason}. Rewrite it as a single setState(...) '
              'assignment to one supported State field.',
          location: '$location.${entry.key}',
        ),
      );
      return null;
    }
  }
  return SourceBuildBlueprint(
    contentFree: contentFree,
    rootExpression: blueprint.rootExpression,
    buildContextParameter: blueprint.buildContextParameter,
    state: state,
    rootParams: rootParams,
    constructorParams: constructorParams,
    mountConstructorProblem: blueprint.mountConstructorProblem,
    eventHandlers: eventHandlers,
    localBindings: blueprint.localBindings,
    helpers: blueprint.helpers,
    // The design keeps the State it lowers; the mount's copy owns the rest.
    liftable: liftState
        ? lifted(
            state: state,
            eventHandlers: eventHandlers,
            liftable: lifted(),
          )
        : null,
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
    final defaultValue = parameter.hasDefaultValue
        ? parameter.computeConstantValue()
        : null;
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
        hasNullDefault:
            parameter.hasDefaultValue &&
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
    final expression = node is FormalParameter
        ? node.defaultClause?.value
        : null;
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
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type;
    if (!type.name.isSynthetic) {
      super.visitInstanceCreationExpression(node);
      return;
    }
    // An expanded dot shorthand has no source text for its constructor.
    final constructor = node.constructorName.element;
    final owner = constructor?.enclosingElement;
    final ownerName = owner == null ? null : namespace.elementName(owner);
    if (constructor == null ||
        !_memberIsVisible(constructor) ||
        ownerName == null) {
      _fail();
      return;
    }
    final name = constructor.name;
    final suffix = name == null || name == 'new' ? '' : '.$name';
    _replace(type.offset, node.argumentList.offset, '$ownerName$suffix');
    node.argumentList.accept(this);
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
  final formal = node is FormalParameter ? node : null;
  if (formal == null) {
    return (
      code: namespace.typeCode(effectiveType),
      hasExplicitType: false,
    );
  }

  final explicit = _formalTypeCode(formal);
  if (explicit != null) return (code: explicit, hasExplicitType: true);

  final field = parameter is FieldFormalParameterElement
      ? parameter.field
      : null;
  if (field != null) {
    for (
      var fieldNode = await astNodeFor(field.firstFragment);
      fieldNode != null;
      fieldNode = fieldNode.parent
    ) {
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
String? _formalTypeCode(FormalParameter formal) =>
    formal.functionTypedSuffix == null
    ? formal.type?.toSource()
    : _functionFormalType(formal);

/// Renders an old-style function-typed formal as a function type. Parameter
/// modifiers, metadata and defaults are declaration-only and are dropped.
String _functionFormalType(FormalParameter formal) {
  final suffix = formal.functionTypedSuffix;
  if (suffix == null) {
    throw StateError('Expected a function-typed parameter.');
  }
  final returnType = formal.type;
  final typeParameters = suffix.typeParameters;
  final parameters = suffix.formalParameters;
  final question = suffix.question;
  final requiredPositional = <String>[];
  final optionalPositional = <String>[];
  final named = <String>[];
  for (final parameter in parameters.parameters) {
    final type = _formalTypeCode(parameter) ?? 'dynamic';
    final name = parameter.name?.lexeme;
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
  final source =
      '${returnType?.toSource() ?? 'dynamic'} Function'
      '${typeParameters?.toSource() ?? ''}($arguments)';
  return question == null ? source : '$source?';
}

Element? _buildContextParameter(MethodElement buildMethod) {
  final parameters = buildMethod.formalParameters;
  if (parameters.isEmpty) return null;
  final parameter = parameters.first;
  final type = parameter.type;
  if (type is! InterfaceType || type.element.name != 'BuildContext') {
    return null;
  }
  return parameter;
}

_SourceWidgetKind? _widgetKind(ClassElement cls) {
  // A widget whose own build() receives more than its context, such as a
  // ConsumerWidget, builds from that method.
  final build = cls.methods.where((method) => method.name == 'build');
  if (build.firstOrNull?.formalParameters case [
    final context,
    _,
    ...,
  ] when context.type.element?.name == 'BuildContext') {
    return _SourceWidgetKind.stateless;
  }
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
  final node = await astNodeFor(createState.firstFragment);
  if (node is MethodDeclaration) {
    final returned = singleReturnExpressionOf(node.body);
    if (returned is InstanceCreationExpression) {
      final element = returned.constructorName.type.element;
      if (element is ClassElement) return element;
    }
  }
  final returnType = createState.returnType;
  if (returnType is InterfaceType) {
    final element = returnType.element;
    if (element is ClassElement &&
        element.name != 'State' &&
        !element.isAbstract) {
      return element;
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
          message:
              'State lifecycle method ${method.name}() cannot be '
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
    // A getter computes from the State; it holds nothing to lower.
    if (field.isStatic || !field.isOriginDeclaration) continue;
    if (!_isPrimitiveType(field.type)) {
      issues.add(
        Issue(
          code: IssueCode.stateShapeUnsupported,
          message:
              "State field '${field.name}' has unsupported type "
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
          message:
              "State field '${field.name}' must have a non-null "
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
  required Map<Element, HelperDef> helpers,
  required Future<AstNode?> Function(Fragment fragment) astNodeFor,
}) async {
  final collector = _ReferencedStateMethodCollector(stateClass, helpers);
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

/// The State methods a walk references, reading each helper call as its body.
final class _ReferencedStateMethodCollector extends RecursiveAstVisitor<void> {
  _ReferencedStateMethodCollector(this.stateClass, this.helpers);

  final ClassElement stateClass;
  final Map<Element, HelperDef> helpers;
  final Set<MethodElement> methods = {};
  final Set<Element> _expanded = Set.identity();

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final element = node.methodName.element;
    final helper = helpers[element];
    if (element == null || helper == null) {
      super.visitMethodInvocation(node);
      return;
    }
    node.target?.accept(this);
    node.argumentList.accept(this);
    if (_expanded.add(element)) {
      for (final root in helper.roots) {
        root.accept(this);
      }
    }
  }

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

/// The builder arguments in a surface's build whose widget builds only what
/// that builder returns, wrapped in no widget that builds a render object.
/// Such a builder runs once per build of its widget; any other builder, or
/// one that cannot be decided, may run many times.
@immutable
final class ContentFreeBuilders {
  /// Creates the verdicts, keyed by widget class and argument name.
  const ContentFreeBuilders(this._verdicts, [this._valueEquals = const {}]);

  /// No builder is content-free.
  static const none = ContentFreeBuilders({});

  final Map<(InterfaceElement, String), bool> _verdicts;
  final Set<InterfaceElement> _valueEquals;

  /// Whether the class [key]'s `==` compares values without `identical`.
  bool equalsByValue(InterfaceElement key) => _valueEquals.contains(key);

  /// Whether the [argument] builder of [widget] is content-free.
  bool contains(InterfaceElement widget, String argument) =>
      _verdicts[(widget.baseElement, argument)] ?? false;
}

/// Decides [ContentFreeBuilders] for every widget construction in [roots]
/// that passes a builder closure.
Future<ContentFreeBuilders> contentFreeBuilders(
  Iterable<Expression> roots, {
  required Future<AstNode?> Function(Fragment fragment) astNodeFor,
}) async {
  final walk = _ContentFree(astNodeFor);
  final verdicts = <(InterfaceElement, String), bool>{};
  final constructions = <InstanceCreationExpression>[];
  for (final root in roots) {
    root.accept(_Constructions(constructions));
  }
  for (final construction in constructions) {
    final widget = construction.constructorName.type.element?.baseElement;
    if (widget is! ClassElement) continue;
    for (final argument in construction.argumentList.arguments) {
      if (argument.argumentExpression is! FunctionExpression) continue;
      final key = (widget, _argumentName(argument));
      if (verdicts.containsKey(key)) continue;
      final fields = await walk.fieldsOf(argument.correspondingParameter);
      verdicts[key] = await walk.buildsOnly(widget, fields, 4);
    }
  }
  final valueEquals = <InterfaceElement>{};
  for (final construction in constructions) {
    final type = construction.staticType;
    if (type is! InterfaceType ||
        ![type, ...type.allSupertypes].any(
          (t) =>
              t.element.name == 'LocalKey' &&
              t.element.library.identifier ==
                  'package:flutter/src/foundation/key.dart',
        )) {
      continue;
    }
    final equals = type.lookUpMethod(
      '==',
      type.element.library,
      concrete: true,
    );
    if (equals == null ||
        equals.enclosingElement?.library?.isDartCore != false) {
      continue;
    }
    final declaration = await astNodeFor(equals.baseElement.firstFragment);
    var identity = declaration == null;
    declaration?.accept(_Identical(() => identity = true));
    if (!identity) valueEquals.add(type.element);
  }
  return ContentFreeBuilders(verdicts, valueEquals);
}

String _argumentName(Argument argument) =>
    argument.correspondingParameter?.name ?? '';

// Calls `identical` from dart:core.
final class _Identical extends RecursiveAstVisitor<void> {
  _Identical(this.found);

  final void Function() found;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final element = node.methodName.element;
    if (node.methodName.name == 'identical' &&
        (element?.library?.isDartCore ?? false)) {
      found();
    }
    super.visitMethodInvocation(node);
  }
}

final class _Constructions extends RecursiveAstVisitor<void> {
  _Constructions(this.found);

  final List<InstanceCreationExpression> found;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    found.add(node);
    super.visitInstanceCreationExpression(node);
  }
}

// A method parameter bound to the caller's argument, read in the caller's
// own bindings.
final class _Bound {
  const _Bound(this.argument, this.caller);

  final Expression argument;
  final _Bindings caller;
}

typedef _Bindings = Map<Element, _Bound>;

// Follows builds to decide whether a widget returns only what one of its
// fields holds or builds.
final class _ContentFree {
  _ContentFree(this.astNodeFor);

  final Future<AstNode?> Function(Fragment fragment) astNodeFor;

  /// The fields a constructor [parameter] is stored in: directly, through
  /// the initializer list, or through `super(...)`.
  Future<Set<FieldElement>> fieldsOf(FormalParameterElement? parameter) async {
    final base = parameter?.baseElement;
    if (base == null) return const {};
    final fields = <FieldElement>{};
    if (base is FieldFormalParameterElement) {
      if (base.field?.baseElement case final field?) fields.add(field);
    }
    if (base is SuperFormalParameterElement) {
      fields.addAll(await fieldsOf(base.superConstructorParameter));
    }
    final constructor = base.enclosingElement;
    if (constructor is! ConstructorElement) return fields;
    final node = await astNodeFor(constructor.firstFragment);
    if (node is! ConstructorDeclaration) return fields;
    bool passes(Expression value) =>
        value.unParenthesized is SimpleIdentifier &&
        (value.unParenthesized as SimpleIdentifier).element?.baseElement ==
            base;
    for (final initializer in node.initializers) {
      switch (initializer) {
        case ConstructorFieldInitializer(:final fieldName, :final expression)
            when passes(expression):
          if (fieldName.element case final FieldElement field) {
            fields.add(field.baseElement);
          }
        case SuperConstructorInvocation(:final argumentList) ||
            RedirectingConstructorInvocation(:final argumentList):
          for (final argument in argumentList.arguments) {
            final value = argument is NamedArgument
                ? argument.argumentExpression
                : argument as Expression;
            if (passes(value)) {
              fields.addAll(await fieldsOf(argument.correspondingParameter));
            }
          }
        default:
      }
    }
    return fields;
  }

  /// Whether every build of [widget], or of its State, returns only what
  /// [fields] hold or build, followed [depth] levels deep.
  Future<bool> buildsOnly(
    InterfaceElement widget,
    Set<FieldElement> fields,
    int depth,
  ) async {
    if (depth == 0 || fields.isEmpty) return false;
    if (isFlutterFrameworkType(widget, 'RenderObjectWidget')) return false;
    // A proxy builds only its `child`.
    if (isFlutterFrameworkType(widget, 'ProxyWidget')) {
      return fields.any((field) {
        final owner = field.enclosingElement;
        return field.name == 'child' &&
            owner is InterfaceElement &&
            owner.name == 'ProxyWidget' &&
            isFlutterFrameworkType(owner, 'ProxyWidget');
      });
    }
    var host = widget;
    if (isFlutterFrameworkType(widget, 'StatefulWidget')) {
      final created = await _returns(widget, 'createState');
      final state = switch (created) {
        [InstanceCreationExpression(:final constructorName)] =>
          constructorName.type.element,
        _ => null,
      };
      if (state is! InterfaceElement) return false;
      host = state;
    }
    return _allYield(
      await _returns(host, 'build'),
      fields,
      widget,
      host,
      const {},
      depth,
    );
  }

  Future<bool> _allYield(
    List<Expression>? returned,
    Set<FieldElement> fields,
    InterfaceElement widget,
    InterfaceElement host,
    _Bindings bindings,
    int depth,
  ) async {
    if (returned == null || returned.isEmpty) return false;
    for (final expression in returned) {
      if (!await _yields(expression, fields, widget, host, bindings, depth)) {
        return false;
      }
    }
    return true;
  }

  // Whether [expression] is what [fields] hold or build, or a widget or
  // method that passes it through. Methods dispatch on the concrete [widget]
  // and its State [host].
  Future<bool> _yields(
    Expression expression,
    Set<FieldElement> fields,
    InterfaceElement widget,
    InterfaceElement host,
    _Bindings bindings,
    int depth,
  ) async {
    var value = expression.unParenthesized;
    if (value is PostfixExpression && value.operator.type == TokenType.BANG) {
      value = value.operand.unParenthesized;
    }
    if (value is SimpleIdentifier) {
      if (bindings[value.element?.baseElement] case final bound?) {
        return _yields(
          bound.argument,
          fields,
          widget,
          host,
          bound.caller,
          depth,
        );
      }
    }
    if (_reads(value, fields, widget, host)) return true;
    switch (value) {
      case FunctionExpressionInvocation(:final function):
        return _reads(function.unParenthesized, fields, widget, host);
      case MethodInvocation(:final methodName, :final target):
        final method = methodName.element;
        if (method is GetterElement) {
          return fields.contains(method.variable.baseElement);
        }
        if (method is! MethodElement || method.isStatic || depth <= 1) {
          return false;
        }
        // Templates dispatch on the concrete widget or its State; any other
        // receiver is undecidable.
        final receiver = switch (target?.unParenthesized) {
          null || ThisExpression() => host,
          SimpleIdentifier(element: final GetterElement getter)
              when getter.baseElement == _stateWidgetGetter(getter) =>
            widget,
          _ => null,
        };
        if (receiver is! InterfaceElement) return false;
        final declaration = await _declaration(receiver, method.name ?? '');
        if (declaration == null) return false;
        final parameters =
            declaration.parameters?.parameters ?? const <FormalParameter>[];
        // Positional arguments bind by position, named ones by name, so an
        // override may rename its parameters.
        final positional = [
          for (final parameter in parameters)
            if (parameter.isPositional) parameter,
        ];
        final callee = <Element, _Bound>{};
        for (final (index, argument) in value.argumentList.arguments.indexed) {
          final declared =
              (argument is NamedArgument
                      ? parameters
                            .where(
                              (candidate) =>
                                  candidate.isNamed &&
                                  candidate.name?.lexeme ==
                                      argument.name.lexeme,
                            )
                            .firstOrNull
                      : index < positional.length
                      ? positional[index]
                      : null)
                  ?.declaredFragment
                  ?.element;
          if (declared == null) continue;
          callee[declared] = _Bound(
            argument is NamedArgument
                ? argument.argumentExpression
                : argument as Expression,
            bindings,
          );
        }
        return _allYield(
          _returnsOf(declaration),
          fields,
          widget,
          host,
          callee,
          depth - 1,
        );
      case InstanceCreationExpression(
        :final constructorName,
        :final argumentList,
      ):
        final wrapper = constructorName.type.element;
        if (wrapper is! InterfaceElement || depth <= 1) return false;
        for (final argument in argumentList.arguments) {
          final passed = argument is NamedArgument
              ? argument.argumentExpression
              : argument as Expression;
          if (await _yields(
            passed,
            fields,
            widget,
            host,
            bindings,
            depth - 1,
          )) {
            return buildsOnly(
              wrapper,
              await fieldsOf(argument.correspondingParameter),
              depth - 1,
            );
          }
        }
        return false;
      default:
        return false;
    }
  }

  // Whether [expression] reads one of [fields], with an inherited getter
  // resolved on the concrete widget or State.
  static bool _reads(
    Expression expression,
    Set<FieldElement> fields,
    InterfaceElement widget,
    InterfaceElement host,
  ) {
    final element = switch (expression) {
      SimpleIdentifier(:final element) => element,
      PrefixedIdentifier(:final identifier) => identifier.element,
      PropertyAccess(:final propertyName) => propertyName.element,
      _ => null,
    };
    if (element is! GetterElement) return false;
    final name = element.name ?? '';
    return [
      element,
      for (final owner in [widget, host])
        owner.thisType.lookUpGetter(name, owner.library, concrete: true),
    ].nonNulls.any((getter) => fields.contains(getter.variable.baseElement));
  }

  // The concrete declaration of [name] on [owner], mixins included.
  Future<MethodDeclaration?> _declaration(
    InterfaceElement owner,
    String name,
  ) async {
    final method = owner.thisType.lookUpMethod(
      name,
      owner.library,
      concrete: true,
    );
    if (method == null || method.isAbstract) return null;
    final node = await astNodeFor(method.baseElement.firstFragment);
    return node is MethodDeclaration ? node : null;
  }

  Future<List<Expression>?> _returns(
    InterfaceElement owner,
    String name,
  ) async {
    final declaration = await _declaration(owner, name);
    return declaration == null ? null : _returnsOf(declaration);
  }

  // Every expression [declaration] returns; null when one returns nothing.
  static List<Expression>? _returnsOf(MethodDeclaration declaration) {
    final body = declaration.body;
    if (body is ExpressionFunctionBody) return [body.expression];
    final returns = <ReturnStatement>[];
    body.accept(_Returns(returns));
    final expressions = [
      for (final statement in returns) statement.expression,
    ];
    return expressions.contains(null) ? null : expressions.nonNulls.toList();
  }

  // Flutter's `State.widget`, when [getter] is declared on `State`.
  static GetterElement? _stateWidgetGetter(GetterElement getter) {
    final owner = getter.enclosingElement;
    return owner is InterfaceElement &&
            owner.name == 'State' &&
            isFlutterFrameworkType(owner, 'State')
        ? owner.getGetter('widget')
        : null;
  }
}

// The returns of one body, not of the closures inside it.
final class _Returns extends RecursiveAstVisitor<void> {
  _Returns(this.found);

  final List<ReturnStatement> found;

  @override
  void visitReturnStatement(ReturnStatement node) => found.add(node);

  @override
  void visitFunctionExpression(FunctionExpression node) {}
}

// The refusal for a build [statement], named with its source and place.
String _buildStatementRefusal(AstNode statement) {
  final unit = statement.root;
  var place = '';
  if (unit is CompilationUnit) {
    final uri = unit.declaredFragment?.source.uri;
    final path = uri == null
        ? unit.declaredFragment?.source.shortName ?? 'this file'
        : uri.scheme == 'package'
        ? 'lib/${uri.pathSegments.skip(1).join('/')}'
        : '$uri';
    final location = unit.lineInfo.getLocation(statement.offset);
    place = ' ($path:${location.lineNumber}:${location.columnNumber})';
  }
  return '`${readableSource(statement.toSource())}`$place: Restage can\'t '
      'translate this statement in a build method. Try using a `switch` or '
      '`?:` expression in the returned widget, or moving the code into a '
      'widget of its own.';
}

// Whether [method] calls `setState`, itself or through another method of
// [state] it calls.
Future<bool> _setsState(
  MethodDeclaration method,
  ClassElement state,
  Future<AstNode?> Function(Fragment fragment) astNodeFor,
  Set<String> seen,
) async {
  if (!seen.add(method.name.lexeme)) return false;
  if (_callsSetState(method.body)) return true;
  final calls = <String>{};
  method.body.accept(_StateMethodCalls(calls));
  for (final name in calls) {
    final callee = state.getMethod(name);
    final declaration = callee == null
        ? null
        : await astNodeFor(callee.firstFragment);
    if (declaration is MethodDeclaration &&
        await _setsState(declaration, state, astNodeFor, seen)) {
      return true;
    }
  }
  return false;
}

final class _StateMethodCalls extends RecursiveAstVisitor<void> {
  _StateMethodCalls(this.names);
  final Set<String> names;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null || node.target is ThisExpression) {
      names.add(node.methodName.name);
    }
    super.visitMethodInvocation(node);
  }
}

// Whether [body] calls `setState` itself.
bool _callsSetState(FunctionBody body) {
  var calls = false;
  body.accept(_SetStateCall(() => calls = true));
  return calls;
}

final class _SetStateCall extends RecursiveAstVisitor<void> {
  _SetStateCall(this.found);
  final void Function() found;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'setState' &&
        (node.target == null || node.target is ThisExpression)) {
      found();
    }
    super.visitMethodInvocation(node);
  }
}
