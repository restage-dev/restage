// Internal builder implementation is reached through documented factories.
// ignore_for_file: public_member_api_docs

import 'dart:convert';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/syntax_diagnostics.dart';
import 'package:restage_shared/restage_shared.dart';

const String _kFlowSourceDir = 'lib/onboarding/flows';
const String _kScreenSourceDir = 'lib/onboarding/screens';
const String _kFlowOutputDir = 'assets/onboarding/flows';
const String _kScreenOutputDir = 'assets/onboarding/screens';
const String _kSdkLibraryOrigin = 'package:restage';

final Object _invalidJsonValue = Object();
final RegExp _identifierPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
final RegExp _wireIdentifierPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$');
final RegExp _generatedSchemaStringPattern = RegExp(r'^[\x20-\x23\x25-\x7E]+$');

const Set<String> _dartReservedWords = {
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'base',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'Function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'new',
  'null',
  'on',
  'operator',
  'part',
  'required',
  'rethrow',
  'return',
  'sealed',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'when',
  'while',
  'with',
  'yield',
};

const Set<String> _objectInstanceMemberNames = {
  'hashCode',
  'noSuchMethod',
  'runtimeType',
  'toString',
};

final class OnboardingFlowBuilder implements Builder {
  OnboardingFlowBuilder(this.options);

  final BuilderOptions options;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '$_kFlowSourceDir/{{name}}.dart': [
          '$_kFlowSourceDir/{{name}}.rsflow.g.dart',
          '$_kFlowOutputDir/{{name}}.flow.json',
        ],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final assetId = buildStep.inputId;
    if (!await buildStep.resolver.isLibrary(assetId)) return;

    final sourceText = await buildStep.readAsString(assetId);
    final library = await buildStep.resolver.libraryFor(
      assetId,
      allowSyntaxErrors: true,
    );

    // The source resolved with `allowSyntaxErrors: true`, so a malformed token
    // can derail flow discovery (`_findFlow` returns null) and hit the
    // early-return below — silently producing no flow document for a flow the
    // author intended. Collect genuine syntactic errors before that
    // early-return so a malformed flow source always fails the build rather
    // than vanishing.
    final issues = <Issue>[];
    final resolvedForSyntax =
        await library.session.getResolvedLibraryByElement(library);
    if (resolvedForSyntax is ResolvedLibraryResult &&
        resolvedForSyntax.units.isNotEmpty) {
      issues.addAll(
        syntacticErrorIssues(resolvedForSyntax, sourcePath: assetId.path),
      );
    }
    if (issues.isNotEmpty) _surfaceIssues(issues);

    final flow = _findFlow(library, assetId);
    if (flow == null) return;

    final stem = p.basenameWithoutExtension(assetId.path);
    final expectedPart = '$stem.rsflow.g.dart';
    if (!_hasPartDirective(sourceText, expectedPart)) {
      issues.add(
        Issue(
          code: IssueCode.missingPartDirective,
          message: "Missing `part '$expectedPart';` directive.",
          location: assetId.path,
        ),
      );
    }
    for (final generated in flow.generatedNames) {
      if (_hasTopLevelDeclaration(library, generated)) {
        issues.add(
          Issue(
            code: IssueCode.generatedSymbolCollision,
            message: 'Generated flow symbol $generated already exists in '
                '${assetId.path}.',
            location: '${assetId.path}#$generated',
          ),
        );
      }
    }
    if (flow.id != stem) {
      issues.add(
        Issue(
          code: IssueCode.filenameMismatch,
          message: "Onboarding flow id '${flow.id}' does not match the file "
              "name '$stem.dart'.",
          location: '${assetId.path}#${flow.className}',
        ),
      );
    }
    for (final action in flow.actions) {
      if (_isWireIdentifier(action.actionName)) continue;
      issues.add(
        Issue(
          code: IssueCode.buildMethodTooComplex,
          message: 'invalid action id "${action.actionName}": action ids '
              'must be valid flow wire identifiers.',
          location: '${assetId.path}#${flow.className}.${action.fieldName}',
        ),
      );
    }
    for (final action in flow.actions) {
      final duplicateOf = action.duplicateOf;
      if (duplicateOf == null) continue;
      issues.add(
        Issue(
          code: IssueCode.buildMethodTooComplex,
          message: 'duplicate action id "${action.actionName}" on '
              '${action.fieldName}; already declared by $duplicateOf.',
          location: '${assetId.path}#${flow.className}.${action.fieldName}',
        ),
      );
    }

    final method = await _resolvedBuildFlow(library, flow, issues, assetId);
    final screenDescriptors =
        await _loadImportedScreenDescriptors(buildStep, assetId, issues);
    if (issues.isNotEmpty) _surfaceIssues(issues);
    if (method == null) return;

    final lowered = await _lowerFlow(
      buildStep,
      flow,
      method,
      screenDescriptors,
      issues,
      assetId,
    );
    if (issues.isNotEmpty) _surfaceIssues(issues);
    if (lowered == null) return;

    await Future.wait<void>([
      buildStep.writeAsString(
        AssetId(assetId.package, '$_kFlowSourceDir/$stem.rsflow.g.dart'),
        // Format the emitted descriptor so a committed `.rsflow.g.dart` is both
        // format-clean AND build_runner-byte-stable (the screen builder's
        // simpler template is already format-clean; the flow builder's richer
        // template needs the explicit pass).
        formatGeneratedDart(_emitFlowDescriptor(stem, flow, lowered)),
      ),
      buildStep.writeAsBytes(
        AssetId(assetId.package, '$_kFlowOutputDir/$stem.flow.json'),
        FlowDocumentCodec.encodeCanonicalJson(lowered.document),
      ),
    ]);
  }
}

_FlowSource? _findFlow(LibraryElement library, AssetId assetId) {
  for (final cls in library.classes) {
    final annotation = firstAnnotationFromOriginAny(
      cls,
      const {'FlowSource', 'OnboardingFlow'},
      _kSdkLibraryOrigin,
    );
    if (annotation == null) continue;
    final value = annotation.computeConstantValue();
    if (value == null) {
      return _FlowSource.invalid(cls);
    }
    final id = value.getField('id')?.toStringValue();
    if (id == null) {
      return _FlowSource.invalid(cls);
    }
    final className = cls.name ?? '<unnamed>';
    return _FlowSource(
      id: id,
      version: value.getField('version')?.toIntValue() ?? 1,
      minClient: value.getField('minClient')?.toIntValue() ?? 3,
      className: className,
      element: cls,
      actions: _collectActions(cls),
      invalidAnnotation: false,
    );
  }
  return null;
}

List<_FlowAction> _collectActions(ClassElement cls) {
  final actions = <_FlowAction>[];
  final usedDescriptorNames = <String>{_actionsClassName(cls.name ?? '')};
  final usedParameterNames = <String>{'flowActionBindings'};
  for (final field in cls.fields) {
    if (!field.isStatic || !field.isConst) continue;
    final value = field.computeConstantValue();
    final id = value?.getField('id')?.toStringValue();
    if (id == null) continue;
    final type = field.type;
    if (type is! InterfaceType ||
        type.element.name != 'FlowActionRef' ||
        !libraryUriMatchesOrigin(
          type.element.library.identifier,
          _kSdkLibraryOrigin,
        )) {
      continue;
    }
    final args = type.typeArguments;
    if (args.length != 2) continue;
    final fieldName = field.name ?? id;
    final duplicate = actions.where((action) => action.actionName == id);
    if (duplicate.isNotEmpty) {
      actions.add(
        _FlowAction.invalidDuplicate(
          fieldName: fieldName,
          actionName: id,
          duplicateOf: duplicate.first.fieldName,
        ),
      );
      continue;
    }
    final descriptorName = _actionDescriptorName(
      fieldName,
      usedDescriptorNames,
    );
    actions.add(
      _FlowAction(
        fieldName: fieldName,
        descriptorName: descriptorName,
        parameterName: _actionParameterName(
          descriptorName,
          usedParameterNames,
        ),
        actionName: id,
        idempotent: value?.getField('idempotent')?.toBoolValue() ?? false,
        inputType: args[0].getDisplayString(),
        outputType: args[1].getDisplayString(),
        inputDartType: args[0],
        outputDartType: args[1],
      ),
    );
  }
  return actions;
}

Future<MethodDeclaration?> _resolvedBuildFlow(
  LibraryElement library,
  _FlowSource flow,
  List<Issue> issues,
  AssetId assetId,
) async {
  if (flow.invalidAnnotation) {
    issues.add(
      Issue(
        code: IssueCode.annotationEvaluationFailed,
        message: '@FlowSource on ${flow.className} could not be '
            'const-evaluated.',
        location: '${assetId.path}#${flow.className}',
      ),
    );
    return null;
  }
  final buildFlow = flow.element.methods
      .where((method) => method.name == 'buildFlow')
      .firstOrNull;
  if (buildFlow == null) {
    issues.add(
      Issue(
        code: IssueCode.buildMethodMissing,
        message: '${flow.className} has no buildFlow() method.',
        location: '${assetId.path}#${flow.className}',
      ),
    );
    return null;
  }
  final resolved = await library.session.getResolvedLibraryByElement(library);
  if (resolved is! ResolvedLibraryResult) {
    issues.add(
      Issue(
        code: IssueCode.analyzerResolutionFailed,
        message: 'Analyzer returned ${resolved.runtimeType}; expected '
            'ResolvedLibraryResult.',
        location: '${assetId.path}#${flow.className}.buildFlow',
      ),
    );
    return null;
  }
  final node = resolved.getFragmentDeclaration(buildFlow.firstFragment)?.node;
  if (node is MethodDeclaration) return node;
  issues.add(
    Issue(
      code: IssueCode.analyzerResolutionFailed,
      message: 'Could not locate buildFlow() in the resolved AST.',
      location: '${assetId.path}#${flow.className}.buildFlow',
    ),
  );
  return null;
}

Future<Map<String, _ScreenDescriptor>> _loadImportedScreenDescriptors(
  BuildStep buildStep,
  AssetId flowAssetId,
  List<Issue> issues,
) async {
  final source = await buildStep.readAsString(flowAssetId);
  final importPattern = RegExp(r'''import\s+['"]([^'"]+)['"]\s*;''');
  final descriptors = <String, _ScreenDescriptor>{};
  for (final match in importPattern.allMatches(source)) {
    final uri = match.group(1)!;
    if (!uri.startsWith('../screens/')) continue;
    final screenPath = p.normalize(p.join(p.dirname(flowAssetId.path), uri));
    if (!screenPath.startsWith(_kScreenSourceDir)) continue;
    final stem = p.basenameWithoutExtension(screenPath);
    final generatedId = AssetId(
      flowAssetId.package,
      '$_kScreenSourceDir/$stem.rsscreen.g.dart',
    );
    if (!await buildStep.canRead(generatedId)) {
      issues.add(
        Issue(
          code: IssueCode.missingScreenDescriptor,
          message: 'Missing generated onboarding screen descriptor for '
              '$screenPath (${_classNameFromStem(stem)}Descriptor).',
          location: flowAssetId.path,
        ),
      );
      continue;
    }
    final generated = await buildStep.readAsString(generatedId);
    for (final descriptor in _parseScreenDescriptors(generated)) {
      descriptors[descriptor.name] = descriptor;
    }
  }
  return descriptors;
}

List<_ScreenDescriptor> _parseScreenDescriptors(String source) {
  final pattern = RegExp(
    r'abstract final class\s+(\w+Descriptor)[\s\S]*?'
    r'OnboardingScreenRef\s*\([\s\S]*?'
    r"id:\s*'([^']+)'[\s\S]*?"
    r"artifactPath:\s*'([^']+)'[\s\S]*?"
    r'version:\s*(\d+)[\s\S]*?'
    r'minClient:\s*(\d+)',
  );
  return [
    for (final match in pattern.allMatches(source))
      _ScreenDescriptor(
        name: match.group(1)!,
        id: match.group(2)!,
        artifactPath: match.group(3)!,
        version: int.parse(match.group(4)!),
        minClient: int.parse(match.group(5)!),
      ),
  ];
}

Future<_LoweredFlow?> _lowerFlow(
  BuildStep buildStep,
  _FlowSource flow,
  MethodDeclaration method,
  Map<String, _ScreenDescriptor> descriptors,
  List<Issue> issues,
  AssetId assetId,
) async {
  final unsupported = _UnsupportedFlowRuntimeFeatureVisitor();
  method.accept(unsupported);
  if (unsupported.names.isNotEmpty) {
    issues.add(
      Issue(
        code: IssueCode.unsupportedFlowRuntimeFeature,
        message: '${unsupported.names.join(', ')} is '
            'not supported by the current flow runtime.',
        location: '${assetId.path}#${flow.className}.buildFlow',
      ),
    );
    return null;
  }

  final body = method.body;
  if (body is! BlockFunctionBody) {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message:
            'buildFlow() must use a block body ending in return flow(...).',
        location: '${assetId.path}#${flow.className}.buildFlow',
      ),
    );
    return null;
  }

  final endLocals = <String, String>{};
  final nodeLocals = <String, String>{};
  MethodInvocation? flowCall;
  for (final statement in body.block.statements) {
    if (statement is VariableDeclarationStatement) {
      for (final variable in statement.variables.variables) {
        final initializer = variable.initializer;
        if (initializer is MethodInvocation &&
            initializer.methodName.name == 'endState') {
          final id = _singleStringArg(initializer);
          if (id != null) endLocals[variable.name.lexeme] = id;
        } else if (initializer is MethodInvocation &&
            initializer.methodName.name == 'flowNode') {
          final id = _singleStringArg(initializer);
          if (id != null) nodeLocals[variable.name.lexeme] = id;
        }
      }
      continue;
    }
    if (statement is ReturnStatement &&
        statement.expression is MethodInvocation) {
      final returned = statement.expression! as MethodInvocation;
      if (returned.methodName.name == 'flow') flowCall = returned;
    }
  }
  if (flowCall == null) {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message: 'buildFlow() must return flow(...).',
        location: '${assetId.path}#${flow.className}.buildFlow',
      ),
    );
    return null;
  }

  final initialExpr = _namedArg(flowCall, 'initial');
  final statesExpr = _namedArg(flowCall, 'states');
  if (initialExpr == null || statesExpr is! ListLiteral) {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message: 'flow(...) must provide initial: and a literal states: list.',
        location: '${assetId.path}#${flow.className}.buildFlow',
      ),
    );
    return null;
  }
  final initial = _screenForRef(initialExpr, descriptors, issues, assetId);
  if (initial == null) return null;
  final flowStateExpr = _namedArg(flowCall, 'flowState');
  final outboundExpr = _namedArg(flowCall, 'outbound');
  final flowState = flowStateExpr == null
      ? const <String, FlowStateDeclaration>{}
      : _flowStateDeclarations(flowStateExpr, issues, assetId);
  final outbound = outboundExpr == null
      ? const FlowOutboundDeclarations()
      : _outboundDeclarations(outboundExpr, issues, assetId);
  if (flowState == null || outbound == null) return null;

  final screenArtifacts = <String, ScreenArtifact>{};
  final states = <String, FlowState>{};
  final actionsByName = {
    for (final action in flow.actions) action.actionName: action,
  };
  final actionContracts = <String, FlowActionContract>{};
  final usedActionContracts = <String, FlowActionContract>{};
  for (final action in flow.actions) {
    final contract = _actionContract(action, flow.minClient, issues, assetId);
    if (contract != null) actionContracts[action.actionName] = contract;
  }
  final endIds = <String>{};
  var endCount = 0;
  for (final element in statesExpr.elements) {
    if (element is! Expression) {
      issues.add(
        Issue(
          code: IssueCode.buildMethodTooComplex,
          message: 'unsupported states list entry: collection control and '
              'spreads are not supported by the current flow runtime.',
          location: assetId.path,
        ),
      );
      continue;
    }
    if (element is MethodInvocation && element.methodName.name == 'end') {
      endCount += 1;
      final endState =
          _endStateId(element.argumentList.arguments.firstOrNull, endLocals);
      final resultExpr = _namedArg(element, 'result');
      if (endState == null || resultExpr == null) {
        issues.add(
          Issue(
            code: IssueCode.buildMethodTooComplex,
            message: 'end(...) must use an endState local and result: map.',
            location: '${assetId.path}#${flow.className}.buildFlow',
          ),
        );
        continue;
      }
      if (!endIds.add(endState)) {
        issues.add(
          Issue(
            code: IssueCode.buildMethodTooComplex,
            message: "duplicate end state '$endState' in flow.",
            location: assetId.path,
          ),
        );
        continue;
      }
      final result = _jsonMap(resultExpr, issues, assetId);
      if (result == null) continue;
      if (!_validateResultKeys(result, issues, assetId) ||
          !_validateResultValues(result, issues, assetId)) {
        continue;
      }
      states[endState] = EndFlowState(result: result);
      continue;
    }

    final graphNode = await _parseGraphNode(
      buildStep,
      assetId,
      element,
      descriptors,
      endLocals,
      nodeLocals,
      issues,
    );
    if (graphNode != null) {
      if (states.containsKey(graphNode.id)) {
        issues.add(
          Issue(
            code: IssueCode.buildMethodTooComplex,
            message: "duplicate graph state '${graphNode.id}' in flow.",
            location: assetId.path,
          ),
        );
        continue;
      }
      states[graphNode.id] = graphNode.state;
      continue;
    }
    if (_isGraphNodeExpression(element)) continue;

    final screenNode = _parseScreenNode(
      element,
      descriptors,
      endLocals,
      nodeLocals,
      actionsByName,
      actionContracts,
      flow.minClient,
      issues,
      assetId,
    );
    if (screenNode == null) continue;
    final actionContract = screenNode.actionContract;
    if (actionContract != null) {
      usedActionContracts[actionContract.actionName] = actionContract;
    }
    if (states.containsKey(screenNode.screen.id)) {
      issues.add(
        Issue(
          code: IssueCode.buildMethodTooComplex,
          message: "duplicate screen state '${screenNode.screen.id}' in flow.",
          location: assetId.path,
        ),
      );
      continue;
    }
    states[screenNode.screen.id] = ScreenFlowState(
      screen: screenNode.screen.id,
      on: {
        screenNode.eventId: screenNode.transition,
      },
    );
    final descriptor = screenNode.screen;
    screenArtifacts[descriptor.id] =
        await _artifactFor(buildStep, assetId, descriptor, issues);
  }
  if (endCount != 1) {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message: 'Onboarding flows must declare exactly one end '
            'state; found $endCount.',
        location: '${assetId.path}#${flow.className}.buildFlow',
      ),
    );
  }
  screenArtifacts[initial.id] =
      await _artifactFor(buildStep, assetId, initial, issues);

  if (issues.isNotEmpty) return null;
  final document = FlowDocument(
    flow: flow.id,
    version: flow.version,
    schemaVersion: 1,
    minClient: flow.minClient,
    initial: initial.id,
    actions: usedActionContracts,
    flowState: flowState,
    outbound: outbound,
    screenArtifacts: screenArtifacts,
    states: states,
  );
  try {
    FlowDocumentValidation.checkValid(document);
  } on Object catch (e) {
    issues.add(
      Issue(
        code: IssueCode.malformedTranslatorOutput,
        message: 'Generated flow document failed validation: $e',
        location: '${assetId.path}#${flow.className}.buildFlow',
      ),
    );
    return null;
  }
  return _LoweredFlow(
    document: document,
    actionContracts: actionContracts,
  );
}

Future<ScreenArtifact> _artifactFor(
  BuildStep buildStep,
  AssetId flowAssetId,
  _ScreenDescriptor descriptor,
  List<Issue> issues,
) async {
  final rfwId = AssetId(
    flowAssetId.package,
    '$_kScreenOutputDir/${descriptor.artifactPath}',
  );
  if (!await buildStep.canRead(rfwId)) {
    issues.add(
      Issue(
        code: IssueCode.missingScreenDescriptor,
        message: 'Missing onboarding screen artifact ${rfwId.path}.',
        location: flowAssetId.path,
      ),
    );
    return ScreenArtifact(
      path: descriptor.artifactPath,
      version: descriptor.version,
      schemaVersion: 1,
      minClient: descriptor.minClient,
      contentHash: FlowContentHash.parse(_zeroHash),
    );
  }
  final bytes = await buildStep.readAsBytes(rfwId);
  return ScreenArtifact(
    path: descriptor.artifactPath,
    version: descriptor.version,
    schemaVersion: 1,
    minClient: descriptor.minClient,
    contentHash: FlowContentHash.compute(bytes),
  );
}

_ScreenNode? _parseScreenNode(
  Expression expression,
  Map<String, _ScreenDescriptor> descriptors,
  Map<String, String> endLocals,
  Map<String, String> nodeLocals,
  Map<String, _FlowAction> actionsByName,
  Map<String, FlowActionContract> actionContracts,
  int minClient,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression is! MethodInvocation || expression.methodName.name != 'goTo') {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message: 'Flow states must be screen(ref).on(event).goTo(target) or '
            'end(...) in the current flow runtime.',
        location: assetId.path,
      ),
    );
    return null;
  }
  final target = _targetId(
    expression.argumentList.arguments.firstOrNull,
    descriptors,
    endLocals,
    nodeLocals,
    issues,
    assetId,
  );
  if (target == null) return null;

  final transitionCall = expression.target;
  final actionTransition = _parseActionTransition(
    transitionCall,
    target,
    actionsByName,
    actionContracts,
    minClient,
    issues,
    assetId,
  );
  final onCall = actionTransition?.onCall ??
      (transitionCall is MethodInvocation ? transitionCall : null);
  if (onCall is! MethodInvocation || onCall.methodName.name != 'on') {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message: 'Screen transitions must call .on(event).goTo(target) or '
            '.on(event).run(action).result(predicate).goTo(target).',
        location: assetId.path,
      ),
    );
    return null;
  }
  final screenCall = onCall.target;
  if (screenCall is! MethodInvocation ||
      screenCall.methodName.name != 'screen') {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message: 'Screen states must start with screen(ref).',
        location: assetId.path,
      ),
    );
    return null;
  }
  final screen = _screenForRef(
    screenCall.argumentList.arguments.firstOrNull,
    descriptors,
    issues,
    assetId,
  );
  final event = _eventId(
    onCall.argumentList.arguments.firstOrNull,
    issues,
    assetId,
  );
  if (screen == null || event == null) return null;
  return _ScreenNode(
    screen: screen,
    eventId: event,
    transition: actionTransition?.transition ?? FlowTransition.goto(target),
    actionContract: actionTransition?.contract,
  );
}

bool _isGraphNodeExpression(Expression expression) {
  return expression is MethodInvocation &&
      (expression.methodName.name == 'decision' ||
          expression.methodName.name == 'subFlow');
}

Future<_GraphNode?> _parseGraphNode(
  BuildStep buildStep,
  AssetId flowAssetId,
  Expression expression,
  Map<String, _ScreenDescriptor> descriptors,
  Map<String, String> endLocals,
  Map<String, String> nodeLocals,
  List<Issue> issues,
) async {
  if (expression is! MethodInvocation) return null;
  return switch (expression.methodName.name) {
    'decision' => _parseDecisionNode(
        expression,
        descriptors,
        endLocals,
        nodeLocals,
        issues,
        flowAssetId,
      ),
    'subFlow' => _parseSubFlowNode(
        buildStep,
        flowAssetId,
        expression,
        descriptors,
        endLocals,
        nodeLocals,
        issues,
      ),
    _ => null,
  };
}

_GraphNode? _parseDecisionNode(
  MethodInvocation invocation,
  Map<String, _ScreenDescriptor> descriptors,
  Map<String, String> endLocals,
  Map<String, String> nodeLocals,
  List<Issue> issues,
  AssetId assetId,
) {
  final id = _flowNodeId(
    invocation.argumentList.arguments.firstOrNull,
    nodeLocals,
  );
  final branches = _authoredBranches(
    _namedArg(invocation, 'branches'),
    descriptors,
    endLocals,
    nodeLocals,
    issues,
    assetId,
  );
  final defaultBranch = _authoredBranchTarget(
    _namedArg(invocation, 'defaultBranch'),
    descriptors,
    endLocals,
    nodeLocals,
    issues,
    assetId,
  );
  if (id == null) {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      'decision(...) requires a flowNode(...) reference.',
    );
  }
  if (id == null || branches == null || defaultBranch == null) return null;
  return _GraphNode(
    id: id,
    state: DecisionFlowState(
      branches: branches,
      defaultBranch: defaultBranch,
    ),
  );
}

Future<_GraphNode?> _parseSubFlowNode(
  BuildStep buildStep,
  AssetId flowAssetId,
  MethodInvocation invocation,
  Map<String, _ScreenDescriptor> descriptors,
  Map<String, String> endLocals,
  Map<String, String> nodeLocals,
  List<Issue> issues,
) async {
  final id = _flowNodeId(
    invocation.argumentList.arguments.firstOrNull,
    nodeLocals,
  );
  final childRef = _flowRefForExpression(
    _namedArg(invocation, 'flow'),
    issues,
    flowAssetId,
  );
  final childArtifact = childRef == null
      ? null
      : await _childFlowArtifact(
          buildStep,
          flowAssetId,
          childRef,
          issues,
        );
  final input = _flowValueSourceMap(
    _namedArg(invocation, 'input'),
    issues,
    flowAssetId,
    'sub-flow input must be a literal string-keyed FlowValueSource map.',
  );
  final onComplete = _authoredBranches(
    _namedArg(invocation, 'onComplete'),
    descriptors,
    endLocals,
    nodeLocals,
    issues,
    flowAssetId,
  );
  final defaultBranch = _authoredBranchTarget(
    _namedArg(invocation, 'defaultBranch'),
    descriptors,
    endLocals,
    nodeLocals,
    issues,
    flowAssetId,
  );
  final unavailableExpr = _namedArg(invocation, 'subFlowUnavailable');
  final unavailable = unavailableExpr == null
      ? null
      : _authoredBranchTarget(
          unavailableExpr,
          descriptors,
          endLocals,
          nodeLocals,
          issues,
          flowAssetId,
        );
  if (id == null) {
    _unsupportedGraphDeclaration(
      issues,
      flowAssetId,
      'subFlow(...) requires a flowNode(...) reference.',
    );
  }
  if (id == null ||
      childRef == null ||
      childArtifact == null ||
      input == null ||
      onComplete == null ||
      defaultBranch == null ||
      (unavailableExpr != null && unavailable == null)) {
    return null;
  }
  return _GraphNode(
    id: id,
    state: SubFlowState(
      flow: childRef.id,
      version: childRef.version,
      schemaVersion: childArtifact.schemaVersion,
      minClient: childRef.minClient,
      contentHash: childArtifact.contentHash,
      input: input,
      onComplete: onComplete,
      defaultBranch: defaultBranch,
      subFlowUnavailable: unavailable,
    ),
  );
}

List<FlowBranch>? _authoredBranches(
  Expression? expression,
  Map<String, _ScreenDescriptor> descriptors,
  Map<String, String> endLocals,
  Map<String, String> nodeLocals,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression is! ListLiteral) {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      'branches must be a literal list.',
    );
    return null;
  }
  final branches = <FlowBranch>[];
  for (final element in expression.elements) {
    if (element is! Expression) {
      _unsupportedGraphDeclaration(
        issues,
        assetId,
        'collection control and spreads are not supported in graph branches.',
      );
      return null;
    }
    final branch = _authoredBranch(
      element,
      descriptors,
      endLocals,
      nodeLocals,
      issues,
      assetId,
    );
    if (branch == null) return null;
    branches.add(branch);
  }
  return branches;
}

FlowBranch? _authoredBranch(
  Expression expression,
  Map<String, _ScreenDescriptor> descriptors,
  Map<String, String> endLocals,
  Map<String, String> nodeLocals,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression is! MethodInvocation ||
      expression.methodName.name != 'flowBranch') {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      'branches must use flowBranch(...).',
    );
    return null;
  }
  final when = _flowBranchPredicate(
    _namedArg(expression, 'when'),
    issues,
    assetId,
  );
  final target = _targetId(
    _namedArg(expression, 'target'),
    descriptors,
    endLocals,
    nodeLocals,
    issues,
    assetId,
  );
  final stateWrites = _stateWrites(
    _namedArg(expression, 'stateWrites'),
    issues,
    assetId,
  );
  if (when == null || target == null || stateWrites == null) return null;
  return FlowBranch(
    when: when,
    target: target,
    stateWrites: stateWrites,
  );
}

FlowBranchTarget? _authoredBranchTarget(
  Expression? expression,
  Map<String, _ScreenDescriptor> descriptors,
  Map<String, String> endLocals,
  Map<String, String> nodeLocals,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression is! MethodInvocation ||
      expression.methodName.name != 'flowBranchTarget') {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      'branch targets must use flowBranchTarget(...).',
    );
    return null;
  }
  final target = _targetId(
    expression.argumentList.arguments.firstOrNull,
    descriptors,
    endLocals,
    nodeLocals,
    issues,
    assetId,
  );
  final stateWrites = _stateWrites(
    _namedArg(expression, 'stateWrites'),
    issues,
    assetId,
  );
  if (target == null || stateWrites == null) return null;
  return FlowBranchTarget(target: target, stateWrites: stateWrites);
}

_ParsedActionTransition? _parseActionTransition(
  Expression? expression,
  String target,
  Map<String, _FlowAction> actionsByName,
  Map<String, FlowActionContract> actionContracts,
  int minClient,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression is! MethodInvocation ||
      expression.methodName.name != 'result') {
    return null;
  }
  final runCall = expression.target;
  if (runCall is! MethodInvocation || runCall.methodName.name != 'run') {
    return null;
  }
  final onCall = runCall.target;
  if (onCall is! MethodInvocation || onCall.methodName.name != 'on') {
    return null;
  }
  final action = _actionForRef(
    runCall.argumentList.arguments.firstOrNull,
    actionsByName,
    issues,
    assetId,
  );
  if (action == null) return null;
  final predicate = _actionResultPredicate(
    expression.argumentList.arguments.firstOrNull,
    action,
    issues,
    assetId,
  );
  final contract = actionContracts[action.actionName] ??
      _actionContract(action, minClient, issues, assetId);
  if (predicate == null || contract == null) return null;
  return _ParsedActionTransition(
    onCall: onCall,
    transition: ActionFlowTransition(
      action: action.actionName,
      resultPredicate: predicate,
      target: target,
    ),
    contract: contract,
  );
}

_ScreenDescriptor? _screenForRef(
  Expression? expression,
  Map<String, _ScreenDescriptor> descriptors,
  List<Issue> issues,
  AssetId assetId,
) {
  final paywall = _paywallScreenForRef(expression, issues, assetId);
  if (paywall != null) return paywall;

  final descriptorName = _descriptorName(expression);
  if (descriptorName == null) {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message: 'Expected a generated screen descriptor .ref.',
        location: assetId.path,
      ),
    );
    return null;
  }
  final descriptor = descriptors[descriptorName];
  if (descriptor == null) {
    issues.add(
      Issue(
        code: IssueCode.missingScreenDescriptor,
        message: 'Missing imported generated screen descriptor '
            '$descriptorName.',
        location: assetId.path,
      ),
    );
  }
  return descriptor;
}

_ScreenDescriptor? _paywallScreenForRef(
  Expression? expression,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression is! MethodInvocation ||
      expression.methodName.name != 'paywallScreen') {
    return null;
  }
  final id = _singleStringArg(expression);
  if (id == null || !_isWireIdentifier(id)) {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message: 'paywallScreen(...) requires a valid string paywall id.',
        location: assetId.path,
      ),
    );
    return null;
  }
  final screenId = 'paywall_$id';
  return _ScreenDescriptor(
    name: 'paywallScreen($id)',
    id: screenId,
    artifactPath: '$screenId.rfw',
    version: 1,
    minClient: kBaselineCatalogVersion,
  );
}

String? _targetId(
  Expression? expression,
  Map<String, _ScreenDescriptor> descriptors,
  Map<String, String> endLocals,
  Map<String, String> nodeLocals,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression is SimpleIdentifier) {
    final id = endLocals[expression.name];
    if (id != null) return id;
    final nodeId = nodeLocals[expression.name];
    if (nodeId != null) return nodeId;
  }
  final nodeId = _flowNodeId(expression, nodeLocals);
  if (nodeId != null) return nodeId;
  return _screenForRef(expression, descriptors, issues, assetId)?.id;
}

String? _flowNodeId(
  Expression? expression,
  Map<String, String> nodeLocals,
) {
  if (expression is SimpleIdentifier) {
    return nodeLocals[expression.name];
  }
  if (expression is MethodInvocation &&
      expression.methodName.name == 'flowNode') {
    return _singleStringArg(expression);
  }
  return null;
}

String? _descriptorName(Expression? expression) {
  if (expression is PrefixedIdentifier &&
      expression.identifier.name == 'ref' &&
      expression.prefix.name.endsWith('Descriptor')) {
    return expression.prefix.name;
  }
  if (expression is PropertyAccess &&
      expression.propertyName.name == 'ref' &&
      expression.target is SimpleIdentifier) {
    final target = expression.target! as SimpleIdentifier;
    if (target.name.endsWith('Descriptor')) return target.name;
  }
  return null;
}

String? _eventId(
  Expression? expression,
  List<Issue> issues,
  AssetId assetId,
) {
  Element? element;
  if (expression is PrefixedIdentifier) {
    element = expression.identifier.element;
  } else if (expression is PropertyAccess) {
    element = expression.propertyName.element;
  } else if (expression is SimpleIdentifier) {
    element = expression.element;
  }
  if (element is PropertyAccessorElement) element = element.variable;
  final eventField = _staticConstOnboardingEventField(element);
  if (eventField != null) {
    final id =
        eventField.computeConstantValue()?.getField('id')?.toStringValue();
    if (id != null) return id;
  }
  issues.add(
    Issue(
      code: IssueCode.buildMethodTooComplex,
      message: 'Expected a static OnboardingEvent field reference; got '
          '${expression?.toSource() ?? '<missing>'}.',
      location: assetId.path,
    ),
  );
  return null;
}

FieldElement? _staticConstOnboardingEventField(Element? element) {
  if (element is! FieldElement || !element.isStatic || !element.isConst) {
    return null;
  }
  final type = element.type;
  if (type is! InterfaceType ||
      type.element.name != 'OnboardingEvent' ||
      !libraryUriMatchesOrigin(
        type.element.library.identifier,
        _kSdkLibraryOrigin,
      )) {
    return null;
  }
  return element;
}

_FlowAction? _actionForRef(
  Expression? expression,
  Map<String, _FlowAction> actionsByName,
  List<Issue> issues,
  AssetId assetId,
) {
  Element? element;
  if (expression is PrefixedIdentifier) {
    element = expression.identifier.element;
  } else if (expression is PropertyAccess) {
    element = expression.propertyName.element;
  } else if (expression is SimpleIdentifier) {
    element = expression.element;
  }
  if (element is PropertyAccessorElement) element = element.variable;
  final actionField = _staticConstFlowActionRefField(element);
  final actionName =
      actionField?.computeConstantValue()?.getField('id')?.toStringValue();
  final action = actionName == null ? null : actionsByName[actionName];
  if (action != null) return action;
  issues.add(
    Issue(
      code: IssueCode.buildMethodTooComplex,
      message: 'Expected a static FlowActionRef field reference; got '
          '${expression?.toSource() ?? '<missing>'}.',
      location: assetId.path,
    ),
  );
  return null;
}

FieldElement? _staticConstFlowActionRefField(Element? element) {
  if (element is! FieldElement || !element.isStatic || !element.isConst) {
    return null;
  }
  final type = element.type;
  if (type is! InterfaceType ||
      type.element.name != 'FlowActionRef' ||
      !libraryUriMatchesOrigin(
        type.element.library.identifier,
        _kSdkLibraryOrigin,
      )) {
    return null;
  }
  return element;
}

FlowActionResultPredicate? _actionResultPredicate(
  Expression? expression,
  _FlowAction action,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression is! FunctionExpression) {
    _unsupportedActionResultPredicate(expression, issues, assetId);
    return null;
  }
  final parameter = _singleFunctionParameterName(expression);
  final body = _functionExpressionBody(expression);
  if (parameter == null || body == null) {
    _unsupportedActionResultPredicate(expression, issues, assetId);
    return null;
  }

  final boolValue = _boolResultPredicateValue(body, parameter);
  if (boolValue != null && action.outputType == 'bool') {
    return BoolEqualsActionResultPredicate(value: boolValue);
  }

  final fieldPredicate = _objectBoolFieldPredicate(body, parameter);
  final outputType = action.outputDartType;
  if (fieldPredicate != null &&
      outputType != null &&
      _objectBoolFieldIsBool(outputType, fieldPredicate.field)) {
    return ObjectBoolFieldEqualsActionResultPredicate(
      field: fieldPredicate.field,
      value: fieldPredicate.value,
    );
  }

  _unsupportedActionResultPredicate(expression, issues, assetId);
  return null;
}

String? _singleFunctionParameterName(FunctionExpression expression) {
  final parameters = expression.parameters?.parameters;
  if (parameters == null || parameters.length != 1) return null;
  return parameters.single.name?.lexeme;
}

Expression? _functionExpressionBody(FunctionExpression expression) {
  final body = expression.body;
  if (body is ExpressionFunctionBody) return body.expression;
  return null;
}

bool? _boolResultPredicateValue(Expression expression, String parameter) {
  if (expression is SimpleIdentifier && expression.name == parameter) {
    return true;
  }
  if (expression is PrefixExpression && expression.operator.lexeme == '!') {
    final operand = expression.operand;
    if (operand is SimpleIdentifier && operand.name == parameter) {
      return false;
    }
  }
  return null;
}

_ObjectBoolFieldPredicate? _objectBoolFieldPredicate(
  Expression expression,
  String parameter,
) {
  final positive = _objectBoolFieldName(expression, parameter);
  if (positive != null) {
    return _ObjectBoolFieldPredicate(field: positive, value: true);
  }
  if (expression is PrefixExpression && expression.operator.lexeme == '!') {
    final negative = _objectBoolFieldName(expression.operand, parameter);
    if (negative != null) {
      return _ObjectBoolFieldPredicate(field: negative, value: false);
    }
  }
  return null;
}

String? _objectBoolFieldName(Expression expression, String parameter) {
  if (expression is PrefixedIdentifier && expression.prefix.name == parameter) {
    return expression.identifier.name;
  }
  if (expression is PropertyAccess &&
      expression.target is SimpleIdentifier &&
      (expression.target! as SimpleIdentifier).name == parameter) {
    return expression.propertyName.name;
  }
  return null;
}

bool _objectBoolFieldIsBool(DartType type, String fieldName) {
  if (type is! InterfaceType || _isDartCoreType(type)) return false;
  for (final field in type.element.fields) {
    // `isOriginDeclaration` is the modern replacement for the deprecated
    // `!isSynthetic` — it selects source-declared instance fields and excludes
    // the synthetic getter/setter-induced fields. (The two diverge only for
    // Dart-3 primary-constructor fields, which `isOriginDeclaration` excludes;
    // that language feature is off-by-default here, so the behavior is
    // unchanged today — revisit if primary constructors stabilize.)
    if (field.name == fieldName &&
        !field.isStatic &&
        field.isOriginDeclaration &&
        field.isFinal &&
        field.type.getDisplayString() == 'bool') {
      return true;
    }
  }
  return false;
}

void _unsupportedActionResultPredicate(
  Expression? expression,
  List<Issue> issues,
  AssetId assetId,
) {
  issues.add(
    Issue(
      code: IssueCode.buildMethodTooComplex,
      message: 'unsupported action result predicate: '
          '${expression?.toSource() ?? '<missing>'}.',
      location: assetId.path,
    ),
  );
}

FlowActionContract? _actionContract(
  _FlowAction action,
  int minClient,
  List<Issue> issues,
  AssetId assetId,
) {
  final inputType = action.inputDartType;
  final outputType = action.outputDartType;
  if (inputType == null || outputType == null) return null;
  final argsSchema = _schemaForActionArgumentType(
    inputType,
    issues,
    assetId,
  );
  final resultSchema = _schemaForActionType(
    outputType,
    issues,
    assetId,
  );
  if (argsSchema == null || resultSchema == null) return null;
  return FlowActionContract(
    actionName: action.actionName,
    contractVersion: 1,
    argsSchema: argsSchema,
    resultSchema: resultSchema,
    minClient: minClient,
    idempotent: action.idempotent,
  );
}

FlowActionSchema? _schemaForActionArgumentType(
  DartType type,
  List<Issue> issues,
  AssetId assetId,
) {
  if (type.getDisplayString() == 'void') {
    return const FlowActionSchema.object({});
  }
  if (type is InterfaceType && type.element is EnumElement) {
    _unsupportedActionSchemaEnumType(type, issues, assetId);
    return null;
  }
  issues.add(
    Issue(
      code: IssueCode.buildMethodTooComplex,
      message: 'unsupported action argument type: ${type.getDisplayString()}. '
          'Generated action argument decoders support only '
          'FlowActionRef<void, R>.',
      location: assetId.path,
    ),
  );
  return null;
}

void _unsupportedActionSchemaEnumType(
  DartType type,
  List<Issue> issues,
  AssetId assetId,
) {
  final display = type.getDisplayString();
  issues.add(
    Issue(
      code: IssueCode.buildMethodTooComplex,
      message: 'unsupported action schema enum type: $display. '
          'Dart enum action argument/result types are not supported yet; '
          'use String with explicit wire values.',
      location: assetId.path,
    ),
  );
}

FlowActionSchema? _schemaForActionType(
  DartType type,
  List<Issue> issues,
  AssetId assetId,
) {
  final display = type.getDisplayString();
  switch (display) {
    case 'void':
      return const FlowActionSchema.object({});
    case 'bool':
      return const FlowActionSchema.bool();
    case 'int':
      return const FlowActionSchema.int();
    case 'double':
      return const FlowActionSchema.double();
    case 'String':
      return const FlowActionSchema.string();
  }

  if (type is InterfaceType && type.element is EnumElement) {
    _unsupportedActionSchemaEnumType(type, issues, assetId);
    return null;
  }

  if (type is InterfaceType && _isListType(type)) {
    final child =
        _schemaForActionType(type.typeArguments.single, issues, assetId);
    if (child == null) return null;
    return FlowActionSchema.list(child);
  }

  if (type is InterfaceType && !_isDartCoreType(type)) {
    final fields = <String, FlowActionSchemaField>{};
    for (final field in type.element.fields) {
      final name = field.name;
      if (field.isStatic || !field.isOriginDeclaration) {
        continue;
      }
      if (name == null || !field.isFinal) {
        final fieldName = name ?? '<unnamed>';
        issues.add(
          Issue(
            code: IssueCode.buildMethodTooComplex,
            message: 'unsupported action schema field: $display.$fieldName '
                'must be a final instance field.',
            location: assetId.path,
          ),
        );
        return null;
      }
      if (!_isAsciiGeneratedSchemaString(name)) {
        _unsupportedActionSchemaString(name, issues, assetId);
        return null;
      }
      final schema = _schemaForActionType(field.type, issues, assetId);
      if (schema == null) return null;
      fields[name] = FlowActionSchemaField(required: true, schema: schema);
    }
    return FlowActionSchema.object(fields);
  }

  issues.add(
    Issue(
      code: IssueCode.buildMethodTooComplex,
      message: 'unsupported action schema type: $display.',
      location: assetId.path,
    ),
  );
  return null;
}

bool _isListType(InterfaceType type) {
  return type.element.name == 'List' &&
      type.element.library.identifier == 'dart:core' &&
      type.typeArguments.length == 1;
}

bool _isDartCoreType(InterfaceType type) {
  return type.element.library.identifier == 'dart:core';
}

String? _endStateId(Expression? expression, Map<String, String> endLocals) {
  if (expression is SimpleIdentifier) return endLocals[expression.name];
  return null;
}

Expression? _namedArg(MethodInvocation invocation, String name) {
  for (final arg in invocation.argumentList.arguments) {
    if (arg is NamedExpression && arg.name.label.name == name) {
      return arg.expression;
    }
  }
  return null;
}

String? _singleStringArg(MethodInvocation invocation) {
  final arg = invocation.argumentList.arguments.firstOrNull;
  if (arg is SimpleStringLiteral) return arg.value;
  return null;
}

Map<String, FlowStateDeclaration>? _flowStateDeclarations(
  Expression expression,
  List<Issue> issues,
  AssetId assetId,
) {
  final entries = _stringKeyedMap(
    expression,
    issues,
    assetId,
    'flowState must be a literal map with string keys.',
  );
  if (entries == null) return null;
  final result = <String, FlowStateDeclaration>{};
  for (final entry in entries.entries) {
    final declaration = _flowStateDeclaration(
      entry.value,
      issues,
      assetId,
    );
    if (declaration == null) return null;
    result[entry.key] = declaration;
  }
  return result;
}

FlowStateDeclaration? _flowStateDeclaration(
  Expression expression,
  List<Issue> issues,
  AssetId assetId,
) {
  final creation = _instanceCreation(
    expression,
    'FlowStateDeclaration',
    issues,
    assetId,
    'flowState values must be FlowStateDeclaration(...) constructors.',
  );
  if (creation == null) return null;
  final type = _flowDataType(
    _namedConstructorArg(creation, 'type'),
    issues,
    assetId,
  );
  final classification = _flowStateClassification(
    _namedConstructorArg(creation, 'classification'),
    issues,
    assetId,
  );
  if (type == null || classification == null) return null;
  final defaultExpr = _namedConstructorArg(creation, 'defaultValue') ??
      _namedConstructorArg(creation, 'default');
  final defaultValue =
      defaultExpr == null ? null : _jsonValue(defaultExpr, issues, assetId);
  if (identical(defaultValue, _invalidJsonValue)) return null;
  return FlowStateDeclaration(
    type: type,
    classification: classification,
    defaultValue: defaultValue,
  );
}

FlowOutboundDeclarations? _outboundDeclarations(
  Expression expression,
  List<Issue> issues,
  AssetId assetId,
) {
  final creation = _instanceCreation(
    expression,
    'FlowOutboundDeclarations',
    issues,
    assetId,
    'outbound must be a FlowOutboundDeclarations(...) constructor.',
  );
  if (creation == null) return null;
  final actionArgs = _outboundPayloadMap(
    _namedConstructorArg(creation, 'actionArgs'),
    issues,
    assetId,
  );
  final terminalResult = _outboundPayload(
    _namedConstructorArg(creation, 'terminalResult'),
    issues,
    assetId,
  );
  final lifecycle = _outboundPayload(
    _namedConstructorArg(creation, 'lifecycle'),
    issues,
    assetId,
  );
  final surveyAnswers = _outboundPayload(
    _namedConstructorArg(creation, 'surveyAnswers'),
    issues,
    assetId,
  );
  final subFlowResult = _outboundPayload(
    _namedConstructorArg(creation, 'subFlowResult'),
    issues,
    assetId,
  );
  final customEvents = _outboundPayloadMap(
    _namedConstructorArg(creation, 'customEvents'),
    issues,
    assetId,
  );
  if (actionArgs == null ||
      terminalResult == null ||
      lifecycle == null ||
      surveyAnswers == null ||
      subFlowResult == null ||
      customEvents == null) {
    return null;
  }
  return FlowOutboundDeclarations(
    actionArgs: actionArgs,
    terminalResult: terminalResult,
    lifecycle: lifecycle,
    surveyAnswers: surveyAnswers,
    subFlowResult: subFlowResult,
    customEvents: customEvents,
  );
}

Map<String, FlowOutboundPayloadDeclaration>? _outboundPayloadMap(
  Expression? expression,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression == null) return const {};
  final entries = _stringKeyedMap(
    expression,
    issues,
    assetId,
    'outbound payload maps must be literal maps with string keys.',
  );
  if (entries == null) return null;
  final result = <String, FlowOutboundPayloadDeclaration>{};
  for (final entry in entries.entries) {
    final payload = _outboundPayload(entry.value, issues, assetId);
    if (payload == null) return null;
    result[entry.key] = payload;
  }
  return result;
}

FlowOutboundPayloadDeclaration? _outboundPayload(
  Expression? expression,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression == null) return const FlowOutboundPayloadDeclaration();
  final creation = _instanceCreation(
    expression,
    'FlowOutboundPayloadDeclaration',
    issues,
    assetId,
    'outbound payloads must be FlowOutboundPayloadDeclaration(...) '
        'constructors.',
  );
  if (creation == null) return null;
  final fieldsExpr = _namedConstructorArg(creation, 'fields');
  final fields = _outboundFields(fieldsExpr, issues, assetId);
  if (fields == null) return null;
  return FlowOutboundPayloadDeclaration(fields: fields);
}

Map<String, FlowOutboundField>? _outboundFields(
  Expression? expression,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression == null) return const {};
  final entries = _stringKeyedMap(
    expression,
    issues,
    assetId,
    'outbound fields must be a literal map with string keys.',
  );
  if (entries == null) return null;
  final result = <String, FlowOutboundField>{};
  for (final entry in entries.entries) {
    final field = _outboundField(entry.value, issues, assetId);
    if (field == null) return null;
    result[entry.key] = field;
  }
  return result;
}

FlowOutboundField? _outboundField(
  Expression expression,
  List<Issue> issues,
  AssetId assetId,
) {
  final creation = _instanceCreation(
    expression,
    'FlowOutboundField',
    issues,
    assetId,
    'outbound field values must be FlowOutboundField(...) constructors.',
  );
  if (creation == null) return null;
  final type = _flowDataType(
    _namedConstructorArg(creation, 'type'),
    issues,
    assetId,
  );
  final ref = _outboundRef(
    _namedConstructorArg(creation, 'ref'),
    issues,
    assetId,
  );
  if (type == null || ref == null) return null;
  return FlowOutboundField(type: type, ref: ref);
}

FlowOutboundRef? _outboundRef(
  Expression? expression,
  List<Issue> issues,
  AssetId assetId,
) {
  final stateRef = _maybeInstanceCreation(expression, 'StateFlowOutboundRef');
  if (stateRef != null) {
    final key = _stringExpression(_namedConstructorArg(stateRef, 'key'));
    if (key == null) {
      _unsupportedOutboundDeclaration(
        issues,
        assetId,
        'StateFlowOutboundRef requires a string key.',
      );
      return null;
    }
    final path = _stringList(
      _namedConstructorArg(stateRef, 'path'),
      issues,
      assetId,
    );
    if (path == null) return null;
    return StateFlowOutboundRef(key: key, path: path);
  }
  final eventRef = _maybeInstanceCreation(expression, 'EventFlowOutboundRef');
  if (eventRef != null) {
    final key = _stringExpression(_namedConstructorArg(eventRef, 'key'));
    if (key == null) {
      _unsupportedOutboundDeclaration(
        issues,
        assetId,
        'EventFlowOutboundRef requires a string key.',
      );
      return null;
    }
    final path = _stringList(
      _namedConstructorArg(eventRef, 'path'),
      issues,
      assetId,
    );
    if (path == null) return null;
    return EventFlowOutboundRef(key: key, path: path);
  }
  _unsupportedOutboundDeclaration(
    issues,
    assetId,
    'outbound refs must be StateFlowOutboundRef(...) or '
    'EventFlowOutboundRef(...) constructors.',
  );
  return null;
}

Map<String, FlowValueSource>? _flowValueSourceMap(
  Expression? expression,
  List<Issue> issues,
  AssetId assetId,
  String detail,
) {
  if (expression == null) return const {};
  final entries = _stringKeyedMap(expression, issues, assetId, detail);
  if (entries == null) return null;
  final result = <String, FlowValueSource>{};
  for (final entry in entries.entries) {
    final source = _flowValueSource(entry.value, issues, assetId);
    if (source == null) return null;
    result[entry.key] = source;
  }
  return result;
}

Map<String, FlowStateWrite>? _stateWrites(
  Expression? expression,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression == null) return const {};
  final entries = _stringKeyedMap(
    expression,
    issues,
    assetId,
    'stateWrites must be a literal string-keyed FlowStateWrite map.',
  );
  if (entries == null) return null;
  final result = <String, FlowStateWrite>{};
  for (final entry in entries.entries) {
    final write = _stateWrite(entry.value, issues, assetId);
    if (write == null) return null;
    result[entry.key] = write;
  }
  return result;
}

FlowStateWrite? _stateWrite(
  Expression expression,
  List<Issue> issues,
  AssetId assetId,
) {
  final creation = _instanceCreation(
    expression,
    'FlowStateWrite',
    issues,
    assetId,
    'stateWrites values must be FlowStateWrite(...) constructors.',
  );
  if (creation == null) return null;
  final type = _flowDataType(
    _namedConstructorArg(creation, 'type'),
    issues,
    assetId,
  );
  final value = _flowValueSource(
    _namedConstructorArg(creation, 'value'),
    issues,
    assetId,
  );
  if (type == null || value == null) return null;
  return FlowStateWrite(type: type, value: value);
}

FlowBranchPredicate? _flowBranchPredicate(
  Expression? expression,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression == null) {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      'FlowBranchPredicate is required.',
    );
    return null;
  }
  final creation = _instanceCreation(
    expression,
    'FlowBranchPredicate',
    issues,
    assetId,
    'branch predicates must be FlowBranchPredicate(...) constructors.',
  );
  if (creation == null) return null;
  final fieldsExpr = _namedConstructorArg(creation, 'fields');
  if (fieldsExpr == null) {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      'FlowBranchPredicate requires fields:.',
    );
    return null;
  }
  final entries = _stringKeyedMap(
    fieldsExpr,
    issues,
    assetId,
    'branch predicate fields must be a literal string-keyed map.',
  );
  if (entries == null) return null;
  final fields = <String, FlowPredicateCondition>{};
  for (final entry in entries.entries) {
    final condition = _predicateCondition(entry.value, issues, assetId);
    if (condition == null) return null;
    fields[entry.key] = condition;
  }
  return FlowBranchPredicate(fields: fields);
}

FlowPredicateCondition? _predicateCondition(
  Expression expression,
  List<Issue> issues,
  AssetId assetId,
) {
  FlowValueSource? singleValue(InstanceCreationExpression creation) {
    return _flowValueSource(
      _namedConstructorArg(creation, 'value'),
      issues,
      assetId,
    );
  }

  final equals =
      _maybeInstanceCreation(expression, 'EqualsFlowPredicateCondition');
  if (equals != null) {
    final value = singleValue(equals);
    return value == null ? null : EqualsFlowPredicateCondition(value: value);
  }
  final notEquals =
      _maybeInstanceCreation(expression, 'NotEqualsFlowPredicateCondition');
  if (notEquals != null) {
    final value = singleValue(notEquals);
    return value == null ? null : NotEqualsFlowPredicateCondition(value: value);
  }
  final inCondition =
      _maybeInstanceCreation(expression, 'InFlowPredicateCondition');
  if (inCondition != null) {
    final valuesExpr = _namedConstructorArg(inCondition, 'values');
    if (valuesExpr is! ListLiteral) {
      _unsupportedGraphDeclaration(
        issues,
        assetId,
        'InFlowPredicateCondition requires a literal values list.',
      );
      return null;
    }
    final values = <FlowValueSource>[];
    for (final element in valuesExpr.elements) {
      if (element is! Expression) {
        _unsupportedGraphDeclaration(
          issues,
          assetId,
          'collection control and spreads are not supported in predicates.',
        );
        return null;
      }
      final value = _flowValueSource(element, issues, assetId);
      if (value == null) return null;
      values.add(value);
    }
    return InFlowPredicateCondition(values: values);
  }
  final greaterThan =
      _maybeInstanceCreation(expression, 'GreaterThanFlowPredicateCondition');
  if (greaterThan != null) {
    final value = singleValue(greaterThan);
    return value == null
        ? null
        : GreaterThanFlowPredicateCondition(value: value);
  }
  final greaterThanOrEquals = _maybeInstanceCreation(
    expression,
    'GreaterThanOrEqualsFlowPredicateCondition',
  );
  if (greaterThanOrEquals != null) {
    final value = singleValue(greaterThanOrEquals);
    return value == null
        ? null
        : GreaterThanOrEqualsFlowPredicateCondition(value: value);
  }
  final lessThan =
      _maybeInstanceCreation(expression, 'LessThanFlowPredicateCondition');
  if (lessThan != null) {
    final value = singleValue(lessThan);
    return value == null ? null : LessThanFlowPredicateCondition(value: value);
  }
  final lessThanOrEquals = _maybeInstanceCreation(
    expression,
    'LessThanOrEqualsFlowPredicateCondition',
  );
  if (lessThanOrEquals != null) {
    final value = singleValue(lessThanOrEquals);
    return value == null
        ? null
        : LessThanOrEqualsFlowPredicateCondition(value: value);
  }
  final exists =
      _maybeInstanceCreation(expression, 'ExistsFlowPredicateCondition');
  if (exists != null) {
    final existsExpr = _namedConstructorArg(exists, 'exists');
    if (existsExpr is BooleanLiteral) {
      return ExistsFlowPredicateCondition(exists: existsExpr.value);
    }
  }
  _unsupportedGraphDeclaration(
    issues,
    assetId,
    'unsupported branch predicate condition ${expression.toSource()}.',
  );
  return null;
}

FlowValueSource? _flowValueSource(
  Expression? expression,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression == null) {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      'FlowValueSource is required.',
    );
    return null;
  }
  final literal = _maybeInstanceCreation(expression, 'LiteralFlowValueSource');
  if (literal != null) {
    final type = _flowDataType(
      _namedConstructorArg(literal, 'type'),
      issues,
      assetId,
    );
    final valueExpr = _namedConstructorArg(literal, 'value');
    if (valueExpr == null) {
      _unsupportedGraphDeclaration(
        issues,
        assetId,
        'LiteralFlowValueSource requires value:.',
      );
      return null;
    }
    final value = _jsonValue(valueExpr, issues, assetId);
    if (type == null || identical(value, _invalidJsonValue) || value == null) {
      return null;
    }
    return LiteralFlowValueSource(type: type, value: value);
  }
  final state = _refFlowValueSource(expression, 'StateFlowValueSource');
  if (state != null) {
    return StateFlowValueSource(key: state.key, path: state.path);
  }
  final event = _refFlowValueSource(expression, 'EventFlowValueSource');
  if (event != null) {
    return EventFlowValueSource(key: event.key, path: event.path);
  }
  final action = _refFlowValueSource(expression, 'ActionResultFlowValueSource');
  if (action != null) {
    return ActionResultFlowValueSource(key: action.key, path: action.path);
  }
  final subFlow =
      _refFlowValueSource(expression, 'SubFlowResultFlowValueSource');
  if (subFlow != null) {
    return SubFlowResultFlowValueSource(key: subFlow.key, path: subFlow.path);
  }
  _unsupportedGraphDeclaration(
    issues,
    assetId,
    'unsupported FlowValueSource ${expression.toSource()}.',
  );
  return null;
}

_RefValueSource? _refFlowValueSource(Expression expression, String typeName) {
  final creation = _maybeInstanceCreation(expression, typeName);
  if (creation == null) return null;
  final key = _stringExpression(_namedConstructorArg(creation, 'key'));
  if (key == null) return null;
  final pathExpr = _namedConstructorArg(creation, 'path');
  if (pathExpr == null) return _RefValueSource(key: key, path: const []);
  if (pathExpr is! ListLiteral) return null;
  final path = <String>[];
  for (final element in pathExpr.elements) {
    if (element is! Expression) return null;
    final value = _stringExpression(element);
    if (value == null) return null;
    path.add(value);
  }
  return _RefValueSource(key: key, path: path);
}

VariableElement? _referencedVariableElement(Expression? expression) {
  Element? element;
  if (expression is SimpleIdentifier) {
    element = expression.element;
  } else if (expression is PrefixedIdentifier) {
    element = expression.identifier.element;
  } else if (expression is PropertyAccess) {
    element = expression.propertyName.element;
  }
  if (element is PropertyAccessorElement) {
    element = element.variable;
  }
  return element is VariableElement ? element : null;
}

_SubFlowRef? _flowRefForExpression(
  Expression? expression,
  List<Issue> issues,
  AssetId assetId,
) {
  final element = _referencedVariableElement(expression);
  if (element == null || !element.isConst) {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      'subFlow flow: must reference a const OnboardingFlowRef.',
    );
    return null;
  }
  final type = element.type;
  if (type is! InterfaceType ||
      type.element.name != 'OnboardingFlowRef' ||
      !libraryUriMatchesOrigin(
        type.element.library.identifier,
        _kSdkLibraryOrigin,
      )) {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      'subFlow flow: must reference an SDK OnboardingFlowRef.',
    );
    return null;
  }
  final value = element.computeConstantValue();
  final id = value?.getField('id')?.toStringValue();
  final version = value?.getField('version')?.toIntValue();
  final minClient = value?.getField('minClient')?.toIntValue();
  if (id == null || version == null || minClient == null) {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      'subFlow flow: OnboardingFlowRef could not be const-evaluated.',
    );
    return null;
  }
  return _SubFlowRef(id: id, version: version, minClient: minClient);
}

Future<_ChildFlowArtifact?> _childFlowArtifact(
  BuildStep buildStep,
  AssetId flowAssetId,
  _SubFlowRef ref,
  List<Issue> issues,
) async {
  final asset = AssetId(
    flowAssetId.package,
    '$_kFlowOutputDir/${ref.id}.flow.json',
  );
  if (!await buildStep.canRead(asset)) {
    _unsupportedGraphDeclaration(
      issues,
      flowAssetId,
      'missing child flow artifact ${asset.path}.',
    );
    return null;
  }
  final bytes = await buildStep.readAsBytes(asset);
  late final FlowDocument document;
  try {
    document = FlowDocumentCodec.decodeJson(utf8.decode(bytes));
  } on Object catch (e) {
    _unsupportedGraphDeclaration(
      issues,
      flowAssetId,
      'could not decode child flow artifact ${asset.path}: $e.',
    );
    return null;
  }
  if (document.flow != ref.id ||
      document.version != ref.version ||
      document.minClient != ref.minClient) {
    _unsupportedGraphDeclaration(
      issues,
      flowAssetId,
      'child flow artifact ${asset.path} does not match '
      '${ref.id}@${ref.version}/minClient ${ref.minClient}.',
    );
    return null;
  }
  return _ChildFlowArtifact(
    schemaVersion: document.schemaVersion,
    contentHash: FlowContentHash.compute(bytes),
  );
}

void _unsupportedGraphDeclaration(
  List<Issue> issues,
  AssetId assetId,
  String detail,
) {
  issues.add(
    Issue(
      code: IssueCode.buildMethodTooComplex,
      message: 'unsupported graph declaration: $detail',
      location: assetId.path,
    ),
  );
}

FlowDataType? _flowDataType(
  Expression? expression,
  List<Issue> issues,
  AssetId assetId,
) {
  final value = _enumConstant(expression, 'FlowDataType');
  if (value == null) {
    _unsupportedOutboundDeclaration(
      issues,
      assetId,
      'Expected a FlowDataType enum constant.',
    );
    return null;
  }
  for (final type in FlowDataType.values) {
    if (type.name == value) return type;
  }
  _unsupportedOutboundDeclaration(
    issues,
    assetId,
    'Unsupported FlowDataType.$value.',
  );
  return null;
}

FlowStateClassification? _flowStateClassification(
  Expression? expression,
  List<Issue> issues,
  AssetId assetId,
) {
  final value = _enumConstant(expression, 'FlowStateClassification');
  if (value == null) {
    _unsupportedOutboundDeclaration(
      issues,
      assetId,
      'Expected a FlowStateClassification enum constant.',
    );
    return null;
  }
  for (final classification in FlowStateClassification.values) {
    if (classification.name == value) return classification;
  }
  _unsupportedOutboundDeclaration(
    issues,
    assetId,
    'Unsupported FlowStateClassification.$value.',
  );
  return null;
}

Map<String, Expression>? _stringKeyedMap(
  Expression expression,
  List<Issue> issues,
  AssetId assetId,
  String detail,
) {
  if (expression is! SetOrMapLiteral || !expression.isMap) {
    _unsupportedOutboundDeclaration(issues, assetId, detail);
    return null;
  }
  final result = <String, Expression>{};
  final seenKeys = <String>{};
  for (final entry in expression.elements) {
    if (entry is! MapLiteralEntry) {
      _unsupportedOutboundDeclaration(
        issues,
        assetId,
        'collection control and spreads are not supported in outbound '
        'declarations.',
      );
      return null;
    }
    final key = _stringExpression(entry.key);
    if (key == null) {
      _unsupportedOutboundDeclaration(
        issues,
        assetId,
        'outbound declaration map keys must be string literals.',
      );
      return null;
    }
    if (!seenKeys.add(key)) {
      _unsupportedOutboundDeclaration(
        issues,
        assetId,
        "duplicate outbound declaration key '$key'.",
      );
      return null;
    }
    result[key] = entry.value;
  }
  return result;
}

InstanceCreationExpression? _instanceCreation(
  Expression expression,
  String typeName,
  List<Issue> issues,
  AssetId assetId,
  String detail,
) {
  final creation = _maybeInstanceCreation(expression, typeName);
  if (creation != null) return creation;
  _unsupportedOutboundDeclaration(issues, assetId, detail);
  return null;
}

InstanceCreationExpression? _maybeInstanceCreation(
  Expression? expression,
  String typeName,
) {
  if (expression is! InstanceCreationExpression) return null;
  if (expression.constructorName.type.name.lexeme != typeName) return null;
  return expression;
}

Expression? _namedConstructorArg(
  InstanceCreationExpression creation,
  String name,
) {
  for (final arg in creation.argumentList.arguments) {
    if (arg is NamedExpression && arg.name.label.name == name) {
      return arg.expression;
    }
  }
  return null;
}

String? _enumConstant(Expression? expression, String enumType) {
  if (expression is PrefixedIdentifier && expression.prefix.name == enumType) {
    return expression.identifier.name;
  }
  if (expression is PropertyAccess &&
      expression.target is SimpleIdentifier &&
      (expression.target! as SimpleIdentifier).name == enumType) {
    return expression.propertyName.name;
  }
  return null;
}

String? _stringExpression(Expression? expression) {
  if (expression is SimpleStringLiteral) return expression.value;
  if (expression is AdjacentStrings) {
    final parts = <String>[];
    for (final part in expression.strings) {
      final value = _stringExpression(part);
      if (value == null) return null;
      parts.add(value);
    }
    return parts.join();
  }
  return null;
}

List<String>? _stringList(
  Expression? expression,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression == null) return const [];
  if (expression is! ListLiteral) {
    _unsupportedOutboundDeclaration(
      issues,
      assetId,
      'outbound ref path must be a literal string list.',
    );
    return null;
  }
  final result = <String>[];
  for (final element in expression.elements) {
    if (element is! Expression) {
      _unsupportedOutboundDeclaration(
        issues,
        assetId,
        'collection control and spreads are not supported in outbound ref '
        'paths.',
      );
      return null;
    }
    final value = _stringExpression(element);
    if (value == null) {
      _unsupportedOutboundDeclaration(
        issues,
        assetId,
        'outbound ref path entries must be string literals.',
      );
      return null;
    }
    result.add(value);
  }
  return result;
}

void _unsupportedOutboundDeclaration(
  List<Issue> issues,
  AssetId assetId,
  String detail,
) {
  issues.add(
    Issue(
      code: IssueCode.buildMethodTooComplex,
      message: 'unsupported outbound declaration: $detail',
      location: assetId.path,
    ),
  );
}

Map<String, Object?>? _jsonMap(
  Expression expression,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression is! SetOrMapLiteral || !expression.isMap) {
    _unsupportedResultLiteral(
      issues,
      assetId,
      'result must be a literal map with string keys.',
    );
    return null;
  }
  return _jsonObject(expression.elements, issues, assetId);
}

Object? _jsonValue(
  Expression expression,
  List<Issue> issues,
  AssetId assetId,
) {
  switch (expression) {
    case SimpleStringLiteral(:final value):
      return value;
    case BooleanLiteral(:final value):
      return value;
    case IntegerLiteral(:final value):
      return value;
    case ListLiteral(:final elements):
      final result = <Object?>[];
      for (final element in elements) {
        if (element is! Expression) {
          _unsupportedResultLiteral(
            issues,
            assetId,
            'collection control and spreads are not supported.',
          );
          return _invalidJsonValue;
        }
        final value = _jsonValue(element, issues, assetId);
        if (identical(value, _invalidJsonValue)) return _invalidJsonValue;
        result.add(value);
      }
      return result;
    case SetOrMapLiteral(:final elements):
      final result = _jsonObject(elements, issues, assetId);
      return result ?? _invalidJsonValue;
    default:
      _unsupportedResultLiteral(
        issues,
        assetId,
        'unsupported expression ${expression.toSource()}.',
      );
      return _invalidJsonValue;
  }
}

Map<String, Object?>? _jsonObject(
  NodeList<CollectionElement> elements,
  List<Issue> issues,
  AssetId assetId,
) {
  final result = <String, Object?>{};
  final seenKeys = <String>{};
  for (final entry in elements) {
    if (entry is! MapLiteralEntry) {
      _unsupportedResultLiteral(
        issues,
        assetId,
        'collection control and spreads are not supported.',
      );
      return null;
    }
    final key = entry.key;
    if (key is! SimpleStringLiteral) {
      _unsupportedResultLiteral(
        issues,
        assetId,
        'map keys must be string literals.',
      );
      return null;
    }
    if (!seenKeys.add(key.value)) {
      issues.add(
        Issue(
          code: IssueCode.buildMethodTooComplex,
          message: "duplicate result key '${key.value}' in result literal.",
          location: assetId.path,
        ),
      );
      return null;
    }
    final value = _jsonValue(entry.value, issues, assetId);
    if (identical(value, _invalidJsonValue)) return null;
    result[key.value] = value;
  }
  return result;
}

bool _validateResultKeys(
  Map<String, Object?> result,
  List<Issue> issues,
  AssetId assetId,
) {
  var isValid = true;
  for (final key in result.keys) {
    if (_isSafeDartIdentifier(key) &&
        !_objectInstanceMemberNames.contains(key)) {
      continue;
    }
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message: "unsupported result key '$key': result keys must be "
            'non-reserved Dart identifiers.',
        location: assetId.path,
      ),
    );
    isValid = false;
  }
  return isValid;
}

bool _validateResultValues(
  Map<String, Object?> result,
  List<Issue> issues,
  AssetId assetId,
) {
  var isValid = true;
  for (final entry in result.entries) {
    final value = entry.value;
    if (value is bool || value is int || value is String) continue;
    _unsupportedResultLiteral(
      issues,
      assetId,
      "result field '${entry.key}' must be a bool, int, or String literal "
      'in this generator version.',
    );
    isValid = false;
  }
  return isValid;
}

bool _isSafeDartIdentifier(String value) {
  if (!_identifierPattern.hasMatch(value)) return false;
  return !_dartReservedWords.contains(value);
}

bool _isWireIdentifier(String value) => _wireIdentifierPattern.hasMatch(value);

bool _isAsciiGeneratedSchemaString(String value) {
  return _generatedSchemaStringPattern.hasMatch(value);
}

void _unsupportedResultLiteral(
  List<Issue> issues,
  AssetId assetId,
  String detail,
) {
  issues.add(
    Issue(
      code: IssueCode.buildMethodTooComplex,
      message: 'unsupported result literal: $detail',
      location: assetId.path,
    ),
  );
}

void _unsupportedActionSchemaString(
  String value,
  List<Issue> issues,
  AssetId assetId,
) {
  issues.add(
    Issue(
      code: IssueCode.buildMethodTooComplex,
      message: 'unsupported action schema string: generated schema strings '
          'must be ASCII and cannot contain dollar signs in this generator '
          'version; '
          'got "$value".',
      location: assetId.path,
    ),
  );
}

String _emitFlowDescriptor(
  String stem,
  _FlowSource flow,
  _LoweredFlow lowered,
) {
  final baseName = flow.className.endsWith('Flow')
      ? flow.className.substring(0, flow.className.length - 'Flow'.length)
      : flow.className;
  final resultClass = '${baseName}Result';
  final descriptorClass = '${flow.className}Descriptor';
  final actionsClass = _actionsClassName(flow.className);
  final actionsInterface =
      flow.actions.isEmpty ? '' : ' implements FlowActionRegistry';
  final result = _firstEndResult(lowered.document);
  return '''
part of '$stem.dart';

abstract final class $descriptorClass {
  const $descriptorClass._();

  static const OnboardingFlowRef<$resultClass> ref =
      OnboardingFlowRef<$resultClass>(
    id: '${flow.id}',
    version: ${flow.version},
    minClient: ${flow.minClient},
    decodeResult: $descriptorClass._decodeResult,
  );

${_emitResultDecoder(resultClass, result)}
}

${_emitResultClass(resultClass, result)}

final class $actionsClass$actionsInterface {
${_emitActionsConstructor(actionsClass, flow.actions)}
${_emitActionFields(flow.actions, flow.minClient, lowered.actionContracts)}
}
''';
}

Map<String, Object?> _firstEndResult(FlowDocument document) {
  for (final state in document.states.values) {
    if (state is EndFlowState) return state.result;
  }
  return const {};
}

String _emitResultDecoder(String className, Map<String, Object?> result) {
  if (result.isEmpty) {
    return '''
  static $className _decodeResult(Map<String, Object?> result) {
    if (result.isNotEmpty) {
      throw const FormatException('Unexpected flow result keys.');
    }
    return const $className();
  }
''';
  }

  final keyChecks =
      result.keys.map((key) => "!result.containsKey('$key')").join(' || ');
  final valueReads = result.entries
      .map((entry) => _emitResultValueRead(entry.key, entry.value))
      .join('\n');
  final params = result.keys.map((key) => '$key: $key').join(', ');
  return '''
  static $className _decodeResult(Map<String, Object?> result) {
    if (result.length != ${result.length} || $keyChecks) {
      throw const FormatException('Unexpected flow result keys.');
    }
$valueReads
    return $className($params);
  }
''';
}

String _emitResultValueRead(String key, Object? value) {
  final type = _dartType(value);
  if (type == 'Object') {
    return '''
    final $key = result['$key'];
    if ($key == null) {
      throw const FormatException('Expected non-null result field $key.');
    }''';
  }
  return '''
    final $key = result['$key'];
    if ($key is! $type) {
      throw const FormatException('Expected result field $key to be $type.');
    }''';
}

String _emitResultClass(String className, Map<String, Object?> result) {
  if (result.isEmpty) {
    return '''
final class $className {
  const $className();
}
''';
  }
  final params = result.keys.map((key) => 'required this.$key').join(', ');
  final fields = result.entries
      .map((entry) => '  final ${_dartType(entry.value)} ${entry.key};')
      .join('\n');
  return '''
final class $className {
  const $className({$params});
$fields
}
''';
}

String _dartType(Object? value) {
  if (value is bool) return 'bool';
  if (value is int) return 'int';
  if (value is String) return 'String';
  return 'Object';
}

String _emitActionsConstructor(
  String className,
  List<_FlowAction> actions,
) {
  if (actions.isEmpty) return '  const $className();\n';
  final params = actions
      .map(
        (action) => '    required FlowActionHandler<${action.inputType}, '
            '${action.outputType}> ${action.parameterName},',
      )
      .join('\n');
  final entries = actions
      .map(
        (action) => "          '${action.actionName}': "
            'FlowActionBinding<${action.inputType}, ${action.outputType}>('
            '\n            descriptor: ${action.descriptorFieldName},'
            '\n            actionName: '
            '${action.descriptorFieldName}.actionName,'
            '\n            contractVersion: '
            '${action.descriptorFieldName}.contractVersion,'
            '\n            argsSchema: '
            '${action.descriptorFieldName}.argsSchema,'
            '\n            resultSchema: '
            '${action.descriptorFieldName}.resultSchema,'
            '\n            minClient: ${action.descriptorFieldName}.minClient,'
            '\n            idempotent: '
            '${action.descriptorFieldName}.idempotent,'
            '\n            handler: ${action.parameterName},'
            '\n            decodeArgs: ${_emitActionArgumentDecoder(action)},'
            '\n            encodeResult: ${_emitActionResultEncoder(action)},'
            '\n          ),',
      )
      .join('\n');
  return '''
  $className({
$params
  }) : flowActionBindings =
            Map<String, FlowActionBinding<dynamic, dynamic>>.unmodifiable({
$entries
          });

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;

''';
}

String _emitActionArgumentDecoder(_FlowAction action) {
  if (action.inputType == 'void') return '(_) {}';
  return '(value) => value as ${action.inputType}';
}

String _emitActionResultEncoder(_FlowAction action) {
  if (action.outputType == 'void') return '(_) => null';
  final encoded = _emitActionValueEncoder(action.outputDartType, 'value');
  return '(value) => $encoded';
}

String _emitActionValueEncoder(
  DartType? type,
  String expression, [
  int depth = 0,
]) {
  final display = type?.getDisplayString();
  switch (display) {
    case 'bool':
    case 'int':
    case 'double':
    case 'String':
      return expression;
  }
  if (type is InterfaceType && _isListType(type)) {
    final item = 'item$depth';
    final encodedItem = _emitActionValueEncoder(
      type.typeArguments.single,
      item,
      depth + 1,
    );
    return '$expression.map(($item) => $encodedItem).toList(growable: false)';
  }
  if (type is InterfaceType && !_isDartCoreType(type)) {
    final fields = type.element.fields
        .where((field) => !field.isStatic && field.isOriginDeclaration)
        .toList()
      ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
    final entries = fields.map((field) {
      final name = field.name ?? '';
      return '${_dartStringLiteral(name)}: '
          '${_emitActionValueEncoder(field.type, '$expression.$name', depth)}';
    }).join(', ');
    return '{$entries}';
  }
  return expression;
}

String _emitActionFields(
  List<_FlowAction> actions,
  int minClient,
  Map<String, FlowActionContract> contracts,
) {
  return actions.map(
    (action) {
      final contract = contracts[action.actionName];
      if (contract == null) {
        throw StateError(
          'Missing generated action contract for ${action.actionName}.',
        );
      }
      return '''
  static final FlowActionDescriptor<${action.inputType}, ${action.outputType}> ${action.descriptorFieldName} =
      FlowActionDescriptor<${action.inputType}, ${action.outputType}>(
    actionName: '${contract.actionName}',
    contractVersion: ${contract.contractVersion},
    argsSchema: ${_emitFlowActionSchema(contract.argsSchema)},
    resultSchema: ${_emitFlowActionSchema(contract.resultSchema)},
    minClient: ${contract.minClient},
    idempotent: ${contract.idempotent},
  );
''';
    },
  ).join('\n');
}

String _emitFlowActionSchema(
  FlowActionSchema schema, {
  bool inConstContext = false,
}) {
  final prefix = inConstContext ? '' : 'const ';
  switch (schema) {
    case FlowObjectActionSchema(:final fields):
      if (fields.isEmpty) return '${prefix}FlowActionSchema.object({})';
      final names = fields.keys.toList()..sort();
      final entries = names.map((name) {
        final field = fields[name]!;
        return (StringBuffer()
              ..write(_dartStringLiteral(name))
              ..write(': FlowActionSchemaField(')
              ..write('required: ${field.required}, ')
              ..write(
                'schema: ${_emitFlowActionSchema(
                  field.schema,
                  inConstContext: true,
                )},',
              )
              ..write(')'))
            .toString();
      }).join(', ');
      return '${prefix}FlowActionSchema.object({$entries})';
    case FlowBoolActionSchema():
      return '${prefix}FlowActionSchema.bool()';
    case FlowIntActionSchema():
      return '${prefix}FlowActionSchema.int()';
    case FlowDoubleActionSchema():
      return '${prefix}FlowActionSchema.double()';
    case FlowStringActionSchema():
      return '${prefix}FlowActionSchema.string()';
    case FlowEnumActionSchema(:final values):
      final emittedValues = values.map(_dartStringLiteral).join(', ');
      return '${prefix}FlowActionSchema.enumValues([$emittedValues])';
    case FlowListActionSchema(:final child):
      return '${prefix}FlowActionSchema.list(${_emitFlowActionSchema(
        child,
        inConstContext: true,
      )})';
    case FlowNullableActionSchema(:final child):
      return '${prefix}FlowActionSchema.nullable(${_emitFlowActionSchema(
        child,
        inConstContext: true,
      )})';
  }
}

String _dartStringLiteral(String value) {
  return "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";
}

String _actionsClassName(String flowClassName) {
  final baseName = flowClassName.endsWith('Flow')
      ? flowClassName.substring(0, flowClassName.length - 'Flow'.length)
      : flowClassName;
  return '${baseName}Actions';
}

String _actionDescriptorName(String fieldName, Set<String> usedNames) {
  var candidate = fieldName;
  if (usedNames.contains(candidate)) {
    candidate = _lowerFirst(candidate);
  }
  final base = candidate;
  var suffix = 2;
  while (!usedNames.add(candidate)) {
    candidate = '$base$suffix';
    suffix += 1;
  }
  return candidate;
}

String _lowerFirst(String value) {
  if (value.isEmpty) return value;
  return value[0].toLowerCase() + value.substring(1);
}

String _actionParameterName(String fieldName, Set<String> usedNames) {
  var base = fieldName;
  while (base.startsWith('_')) {
    base = base.substring(1);
  }
  if (base.isEmpty) {
    base = 'handler';
  }
  if (base == 'actionHandlersByName') {
    base = 'actionHandler';
  }
  if (!_isSafeDartIdentifier(base)) {
    base = 'handler';
  }
  var candidate = base;
  var suffix = 2;
  while (!usedNames.add(candidate)) {
    candidate = '$base$suffix';
    suffix += 1;
  }
  return candidate;
}

bool _hasPartDirective(String source, String expectedPart) {
  final pattern = RegExp(
    "part\\s+['\"]${RegExp.escape(expectedPart)}['\"]\\s*;",
  );
  return pattern.hasMatch(source);
}

bool _hasTopLevelDeclaration(LibraryElement library, String name) {
  return _topLevelDeclarations(library).any(
    (element) => _elementHasName(element, name),
  );
}

Iterable<Element> _topLevelDeclarations(LibraryElement library) sync* {
  yield* library.classes;
  yield* library.enums;
  yield* library.mixins;
  yield* library.extensions;
  yield* library.extensionTypes;
  yield* library.typeAliases;
  yield* library.topLevelFunctions;
  yield* library.topLevelVariables;
  yield* library.getters;
  yield* library.setters;
}

bool _elementHasName(Element element, String name) {
  return element.name == name ||
      element.lookupName == name ||
      element.lookupName == '$name=';
}

String _classNameFromStem(String stem) {
  return stem
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join();
}

Never _surfaceIssues(List<Issue> issues) {
  for (final issue in issues) {
    log.severe(issue.toLogString());
  }
  throw StateError(
    '${issues.length} codegen issue(s) detected; see log above.',
  );
}

final class _UnsupportedFlowRuntimeFeatureVisitor
    extends RecursiveAstVisitor<void> {
  final Set<String> names = {};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (name == 'action' || name == 'subflow') {
      names.add(name);
    }
    super.visitMethodInvocation(node);
  }
}

final class _FlowSource {
  _FlowSource({
    required this.id,
    required this.version,
    required this.minClient,
    required this.className,
    required this.element,
    required this.actions,
    required this.invalidAnnotation,
  });

  _FlowSource.invalid(ClassElement element)
      : this(
          id: '',
          version: 1,
          minClient: kBaselineCatalogVersion,
          className: element.name ?? '<unnamed>',
          element: element,
          actions: const [],
          invalidAnnotation: true,
        );

  final String id;
  final int version;
  final int minClient;
  final String className;
  final ClassElement element;
  final List<_FlowAction> actions;
  final bool invalidAnnotation;

  List<String> get generatedNames {
    final baseName = className.endsWith('Flow')
        ? className.substring(0, className.length - 'Flow'.length)
        : className;
    return [
      '${className}Descriptor',
      '${baseName}Result',
      '${baseName}Actions',
      if (actions.isNotEmpty) ...[
        'FlowActionBinding',
        'FlowActionDescriptor',
        'FlowActionHandler',
        'FlowActionRegistry',
        'FlowActionSchema',
        'FlowActionSchemaField',
      ],
    ];
  }
}

final class _FlowAction {
  const _FlowAction({
    required this.fieldName,
    required this.descriptorName,
    required this.parameterName,
    required this.actionName,
    required this.idempotent,
    required this.inputType,
    required this.outputType,
    required this.inputDartType,
    required this.outputDartType,
    this.duplicateOf,
  });

  _FlowAction.invalidDuplicate({
    required String fieldName,
    required String actionName,
    required String duplicateOf,
  }) : this(
          fieldName: fieldName,
          descriptorName: fieldName,
          parameterName: fieldName,
          actionName: actionName,
          idempotent: false,
          inputType: 'void',
          outputType: 'void',
          inputDartType: null,
          outputDartType: null,
          duplicateOf: duplicateOf,
        );

  final String fieldName;
  final String descriptorName;
  final String parameterName;
  final String actionName;
  final bool idempotent;
  final String inputType;
  final String outputType;
  final DartType? inputDartType;
  final DartType? outputDartType;
  final String? duplicateOf;

  String get descriptorFieldName => '${descriptorName}Descriptor';
}

final class _ScreenDescriptor {
  const _ScreenDescriptor({
    required this.name,
    required this.id,
    required this.artifactPath,
    required this.version,
    required this.minClient,
  });

  final String name;
  final String id;
  final String artifactPath;
  final int version;
  final int minClient;
}

final class _ScreenNode {
  const _ScreenNode({
    required this.screen,
    required this.eventId,
    required this.transition,
    this.actionContract,
  });

  final _ScreenDescriptor screen;
  final String eventId;
  final FlowTransition transition;
  final FlowActionContract? actionContract;
}

final class _GraphNode {
  const _GraphNode({
    required this.id,
    required this.state,
  });

  final String id;
  final FlowState state;
}

final class _ParsedActionTransition {
  const _ParsedActionTransition({
    required this.onCall,
    required this.transition,
    required this.contract,
  });

  final MethodInvocation onCall;
  final ActionFlowTransition transition;
  final FlowActionContract contract;
}

final class _ObjectBoolFieldPredicate {
  const _ObjectBoolFieldPredicate({
    required this.field,
    required this.value,
  });

  final String field;
  final bool value;
}

final class _RefValueSource {
  const _RefValueSource({
    required this.key,
    required this.path,
  });

  final String key;
  final List<String> path;
}

final class _SubFlowRef {
  const _SubFlowRef({
    required this.id,
    required this.version,
    required this.minClient,
  });

  final String id;
  final int version;
  final int minClient;
}

final class _ChildFlowArtifact {
  const _ChildFlowArtifact({
    required this.schemaVersion,
    required this.contentHash,
  });

  final int schemaVersion;
  final FlowContentHash contentHash;
}

final class _LoweredFlow {
  const _LoweredFlow({
    required this.document,
    required this.actionContracts,
  });

  final FlowDocument document;
  final Map<String, FlowActionContract> actionContracts;
}

const _zeroHash = 'sha256:00000000000000000000000000000000'
    '00000000000000000000000000000000';
