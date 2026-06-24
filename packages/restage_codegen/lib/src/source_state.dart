import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:restage_codegen/src/const_folding.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/setstate_recognition.dart';

/// Root-source build material for `@PaywallSource` and `@OnboardingSource`.
@immutable
final class SourceBuildBlueprint {
  /// Creates the source build blueprint.
  SourceBuildBlueprint({
    required this.rootExpression,
    this.buildContextParameter,
    List<CustomWidgetStateField>? state,
    Map<String, RecognisedSetState> eventHandlers = const {},
  })  : state = state == null ? null : List.unmodifiable(state),
        eventHandlers = Map.unmodifiable(eventHandlers);

  /// The returned expression from the effective `build()` host.
  final Expression rootExpression;

  /// The effective `build()` method's `BuildContext` parameter element.
  final Element? buildContextParameter;

  /// Root `State` fields, or `null` for a stateless root.
  final List<CustomWidgetStateField>? state;

  /// Referenced State method tear-offs recognised as `setState` handlers.
  final Map<String, RecognisedSetState> eventHandlers;
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
  final rootExpression = singleReturnExpressionOf(buildNode.body);
  if (rootExpression == null) {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message: 'build() must be a single returned widget expression.',
        location: '$location.build',
      ),
    );
    return null;
  }

  final buildContextParameter = _buildContextParameter(buildMethod);

  if (stateClass == null) {
    return SourceBuildBlueprint(
      rootExpression: rootExpression,
      buildContextParameter: buildContextParameter,
    );
  }

  final state = await _collectStateFields(
    stateClass,
    astNodeFor: astNodeFor,
    issues: issues,
    location: location,
  );
  if (state == null) return null;
  final eventHandlers = await _collectReferencedHandlers(
    rootExpression,
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
    rootExpression: rootExpression,
    buildContextParameter: buildContextParameter,
    state: state,
    eventHandlers: eventHandlers,
  );
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
  Expression rootExpression, {
  required ClassElement stateClass,
  required Set<String> stateFieldNames,
  required Future<AstNode?> Function(Fragment fragment) astNodeFor,
}) async {
  final collector = _ReferencedStateMethodCollector(stateClass);
  rootExpression.accept(collector);
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
