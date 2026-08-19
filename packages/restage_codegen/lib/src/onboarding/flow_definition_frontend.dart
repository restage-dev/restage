// Analyzer frontend for the flattened flow authoring form.
//
// This file is intentionally independent of any per-directory Builder.  The
// package source roster and the aggregate manifest owner can call
// [inspectFlowDefinitions] for every tracked Dart library, while the legacy
// builders can use the same resolved declarations during the transition.
// ignore_for_file: public_member_api_docs

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/restage_shared.dart';

const String kRestageSdkLibraryOrigin = 'package:restage';
const String kRestageSharedLibraryOrigin = 'package:restage_shared';

const Set<String> _flowGraphAnnotationNames = {'FlowGraph'};
const Set<String> _legacyFlowAnnotationNames = {
  'FlowSource',
  'OnboardingFlow',
};

/// Result of resolving all flow declarations in one analyzer library.
///
/// This is the aggregate-owner seam.  It does not read the filesystem, infer
/// a category from a directory, or emit an artifact.  Callers may therefore
/// run it over the package-wide tracked source set and assemble one
/// deterministic publication index.
@immutable
final class FlowFrontendResult {
  FlowFrontendResult({
    required List<NormalizedFlowSource> flows,
    required List<Issue> issues,
  })  : flows = List.unmodifiable(flows),
        issues = List.unmodifiable(issues);

  final List<NormalizedFlowSource> flows;
  final List<Issue> issues;

  bool get isValid => issues.isEmpty;
}

/// A resolved, annotation-owned flow declaration before artifact emission.
///
/// [graph] is non-null for the flattened `FlowDefinition` form.  Legacy
/// class-shaped flows retain their existing AST frontend for now, but their
/// resolved identity is exposed here so aggregate owners do not need to
/// rediscover annotation meaning.
@immutable
final class NormalizedFlowSource {
  const NormalizedFlowSource({
    required this.id,
    required this.hasExplicitId,
    required this.version,
    required this.minClient,
    required this.surface,
    required this.delivery,
    required this.declaration,
    required this.isCanonical,
    required this.graph,
  });

  final String id;
  final bool hasExplicitId;
  final int version;
  final int minClient;
  final Surface surface;
  final FlowDeliveryMode delivery;
  final Element declaration;
  final bool isCanonical;
  final NormalizedFlowGraph? graph;

  /// The stable identity used by subflow closure assembly.
  NormalizedFlowIdentity get identity =>
      NormalizedFlowIdentity(surface: surface, id: id);

  String get declarationIdentity =>
      '${declaration.library?.identifier ?? '<unknown>'}#'
      '${declaration.name ?? '<unnamed>'}';
}

/// Identity of a published flow within its surface namespace.
///
/// A slug is not globally unique: the same flow ID may be published once in
/// onboarding and once in message.  Keeping the surface in this value prevents
/// aggregate owners from accidentally collapsing those two declarations.
@immutable
final class NormalizedFlowIdentity {
  const NormalizedFlowIdentity({required this.surface, required this.id});

  final Surface surface;
  final String id;

  /// Stable, unambiguous map key for compiler-owned closure indexes.
  String get key => '${surface.wireName}\u0000$id';

  @override
  bool operator ==(Object other) {
    return other is NormalizedFlowIdentity &&
        other.surface == surface &&
        other.id == id;
  }

  @override
  int get hashCode => Object.hash(surface, id);
}

/// Analyzer-resolved metadata for one child-flow reference in a normalized
/// graph.  This is frontend metadata, not a new wire field; the package
/// compiler uses it to resolve closure documents by `(surface, id)`.
@immutable
final class NormalizedChildFlowReference {
  const NormalizedChildFlowReference({
    required this.identity,
    required this.version,
    required this.minClient,
    required this.declarationIdentity,
  });

  final NormalizedFlowIdentity identity;
  final int version;
  final int minClient;
  final String declarationIdentity;
}

/// Normalized graph data shared by the later flow-document and publication
/// emitters.  The maps use the existing `restage_shared` graph algebra; no
/// inference-specific intermediate representation is introduced.
@immutable
final class NormalizedFlowGraph {
  NormalizedFlowGraph({
    required this.flow,
    required this.version,
    required this.minClient,
    required this.delivery,
    required this.initial,
    required Map<String, FlowState> states,
    required Map<String, FlowStateDeclaration> flowState,
    required this.outbound,
    required Map<String, FlowActionContract> actions,
    required Map<String, NormalizedScreenReference> screens,
    Map<NormalizedFlowIdentity, NormalizedChildFlowReference> childFlows =
        const {},
  })  : states = Map.unmodifiable(states),
        flowState = Map.unmodifiable(flowState),
        actions = Map.unmodifiable(actions),
        screens = Map.unmodifiable(screens),
        childFlows = Map.unmodifiable(childFlows);

  final String flow;
  final int version;
  final int minClient;
  final FlowDeliveryMode delivery;
  final String initial;
  final Map<String, FlowState> states;
  final Map<String, FlowStateDeclaration> flowState;
  final FlowOutboundDeclarations outbound;
  final Map<String, FlowActionContract> actions;
  final Map<String, NormalizedScreenReference> screens;

  /// Child-flow references keyed by their complete surface-aware identity.
  final Map<NormalizedFlowIdentity, NormalizedChildFlowReference> childFlows;

  /// Materializes the proven wire model after the aggregate emitter supplies
  /// exact artifact hashes and paths for [artifacts].
  FlowDocument toDocument(Map<String, ScreenArtifact> artifacts) {
    final document = FlowDocument(
      flow: flow,
      version: version,
      schemaVersion: 1,
      minClient: minClient,
      initial: initial,
      actions: actions,
      flowState: flowState,
      outbound: outbound,
      screenArtifacts: artifacts,
      states: states,
      deliveryMode: delivery,
    );
    return document;
  }
}

/// A resolved screen/paywall target used by the aggregate manifest emitter.
///
/// The [element] is the analyzer identity of the authored class.  It is the
/// only authoritative screen reference; the frontend never derives identity
/// from `Type.toString()`, a bare class name, or a generated descriptor name.
@immutable
final class NormalizedScreenReference {
  const NormalizedScreenReference({
    required this.id,
    required this.element,
    required this.declaredSurface,
    required this.effectiveSurface,
    required this.isPaywall,
    required this.version,
    required this.minClient,
  });

  final String id;
  final ClassElement element;
  final Surface? declaredSurface;
  final Surface effectiveSurface;
  final bool isPaywall;
  final int version;
  final int minClient;

  String get declarationIdentity =>
      '${element.library.identifier}#${element.name ?? '<unnamed>'}';
}

/// Resolves flow annotations in one analyzer library.
///
/// [legacySurface] is consulted only for deprecated `*Source` declarations.
/// Canonical `@FlowGraph` declarations must carry a resolved `surface:` value;
/// their physical directory is never consulted.
Future<FlowFrontendResult> inspectFlowDefinitions(
  LibraryElement library,
  AssetId assetId, {
  Surface? legacySurface,
}) async {
  final flows = <NormalizedFlowSource>[];
  final issues = <Issue>[];

  for (final variable in library.topLevelVariables) {
    final annotation = _flowAnnotationFor(variable);
    if (annotation == null) continue;
    final metadata = _readFlowMetadata(
      annotation,
      assetId: assetId,
      legacySurface: legacySurface,
      issues: issues,
    );
    if (metadata == null) continue;
    if (!metadata.isCanonical) {
      issues.add(
        Issue(
          code: IssueCode.buildMethodTooComplex,
          message: 'Deprecated class-shaped flow annotations must target a '
              'RestageFlow class; top-level FlowSource variables are not '
              'accepted.',
          location: '${assetId.path}#${variable.name}',
        ),
      );
      continue;
    }

    if (!variable.isConst && !variable.isFinal) {
      issues.add(
        Issue(
          code: IssueCode.unresolvedIdentifier,
          message: '@FlowGraph must annotate a const or final top-level '
              'FlowDefinition declaration.',
          location: '${assetId.path}#${variable.name}',
        ),
      );
      continue;
    }

    final initializer = await _initializerFor(variable, library);
    if (initializer is! InstanceCreationExpression ||
        !_isRestageTypeConstructor(initializer, 'FlowDefinition')) {
      issues.add(
        Issue(
          code: IssueCode.unresolvedIdentifier,
          message: '@FlowGraph must annotate a top-level variable whose '
              'initializer is a direct analyzer-resolved FlowDefinition(...).',
          location: '${assetId.path}#${variable.name}',
        ),
      );
      continue;
    }

    // The graph parser is deliberately called only after the constructor and
    // annotation have crossed the resolved SDK provenance boundary.  This
    // keeps local classes named FlowDefinition from entering the model.
    final graph = await _FlowDefinitionGraphParser(
      initializer,
      library: library,
      assetId: assetId,
      flow: metadata.id ?? _fileStem(assetId.path),
      version: metadata.version,
      minClient: metadata.minClient,
      delivery: metadata.delivery,
      surface: metadata.surface!,
      issues: issues,
    ).parse();
    if (graph == null) continue;
    flows.add(
      NormalizedFlowSource(
        id: metadata.id ?? _fileStem(assetId.path),
        hasExplicitId: metadata.hasExplicitId,
        version: metadata.version,
        minClient: metadata.minClient,
        surface: metadata.surface!,
        delivery: metadata.delivery,
        declaration: variable,
        isCanonical: true,
        graph: graph,
      ),
    );
  }

  for (final cls in library.classes) {
    final annotation = _flowAnnotationFor(cls);
    if (annotation == null) continue;
    final metadata = _readFlowMetadata(
      annotation,
      assetId: assetId,
      legacySurface: legacySurface,
      issues: issues,
    );
    if (metadata == null) continue;
    if (!_isRestageFlowClass(cls)) {
      issues.add(
        Issue(
          code: IssueCode.unsupportedBaseClass,
          message: 'A flow annotation must target a concrete RestageFlow '
              'subclass resolved from package:restage.',
          location: '${assetId.path}#${cls.name ?? '<unnamed>'}',
        ),
      );
      continue;
    }
    if (!metadata.isCanonical && metadata.id == null) {
      issues.add(
        Issue(
          code: IssueCode.annotationEvaluationFailed,
          message: 'Legacy flow annotations require a non-empty id.',
          location: '${assetId.path}#${cls.name ?? '<unnamed>'}',
        ),
      );
      continue;
    }
    final id = metadata.id ?? _fileStem(assetId.path);
    flows.add(
      NormalizedFlowSource(
        id: id,
        hasExplicitId: metadata.hasExplicitId,
        version: metadata.version,
        minClient: metadata.minClient,
        surface: metadata.surface!,
        delivery: metadata.delivery,
        declaration: cls,
        isCanonical: metadata.isCanonical,
        graph: null,
      ),
    );
  }

  _validateImplicitFlowCount(flows, assetId, issues);
  return FlowFrontendResult(flows: flows, issues: issues);
}

ElementAnnotation? _flowAnnotationFor(Element element) {
  return firstAnnotationFromOriginAny(
    element,
    {
      ..._flowGraphAnnotationNames,
      ..._legacyFlowAnnotationNames,
    },
    kRestageSdkLibraryOrigin,
  );
}

final class _FlowMetadata {
  const _FlowMetadata({
    required this.id,
    required this.version,
    required this.minClient,
    required this.surface,
    required this.delivery,
    required this.isCanonical,
    required this.hasExplicitId,
  });

  final String? id;
  final int version;
  final int minClient;
  final Surface? surface;
  final FlowDeliveryMode delivery;
  final bool isCanonical;
  final bool hasExplicitId;
}

_FlowMetadata? _readFlowMetadata(
  ElementAnnotation annotation, {
  required AssetId assetId,
  required Surface? legacySurface,
  required List<Issue> issues,
}) {
  final declaration = resolvedAnnotationClass(annotation);
  final location = '${assetId.path}#${annotation.toSource()}';
  if (declaration == null ||
      !libraryUriMatchesOrigin(
        declaration.library.identifier,
        kRestageSdkLibraryOrigin,
      )) {
    issues.add(
      Issue(
        code: IssueCode.unresolvedIdentifier,
        message: 'Flow annotation must resolve to the Restage SDK '
            'declaration; source spelling alone is not accepted.',
        location: location,
      ),
    );
    return null;
  }
  final value = annotation.computeConstantValue();
  if (value == null) {
    issues.add(
      Issue(
        code: IssueCode.annotationEvaluationFailed,
        message: '${declaration.name} could not be const-evaluated.',
        location: location,
      ),
    );
    return null;
  }

  final isCanonical = declaration.name == 'FlowGraph';
  final idValue = value.getField('id');
  final id = idValue == null || idValue.isNull ? null : idValue.toStringValue();
  if (idValue != null && !idValue.isNull && (id == null || id.isEmpty)) {
    issues.add(
      Issue(
        code: IssueCode.annotationEvaluationFailed,
        message: '${declaration.name}.id must be a non-empty String literal.',
        location: location,
      ),
    );
    return null;
  }
  if (!isCanonical && id == null) {
    issues.add(
      Issue(
        code: IssueCode.annotationEvaluationFailed,
        message: '${declaration.name}.id is required for compatibility '
            'annotations.',
        location: location,
      ),
    );
    return null;
  }

  final surface = isCanonical
      ? _surfaceFromValue(value.getField('surface'))
      : legacySurface;
  if (surface == null) {
    issues.add(
      Issue(
        code: IssueCode.annotationEvaluationFailed,
        message: isCanonical
            ? '@FlowGraph.surface is required and must be a resolved '
                'Surface enum value.'
            : 'A legacy flow source requires a surface directory mapping.',
        location: location,
      ),
    );
    return null;
  }

  final delivery =
      _deliveryFromValue(value.getField('delivery')) ?? FlowDeliveryMode.typed;
  return _FlowMetadata(
    id: id,
    hasExplicitId: id != null,
    version: value.getField('version')?.toIntValue() ?? 1,
    minClient:
        value.getField('minClient')?.toIntValue() ?? kBaselineCatalogVersion,
    surface: surface,
    delivery: delivery,
    isCanonical: isCanonical,
  );
}

Surface? _surfaceFromValue(DartObject? value) {
  if (!_isRestageEnumValue(value, 'Surface')) return null;
  final wireName = value!.getField('wireName')?.toStringValue();
  if (wireName == null) return null;
  for (final surface in Surface.values) {
    if (surface.wireName == wireName) return surface;
  }
  return null;
}

FlowDeliveryMode? _deliveryFromValue(DartObject? value) {
  if (!_isRestageEnumValue(value, 'FlowDeliveryMode')) return null;
  final wireName = value!.getField('wireName')?.toStringValue();
  if (wireName == null) return null;
  for (final mode in FlowDeliveryMode.values) {
    if (mode.wireName == wireName) return mode;
  }
  return null;
}

bool _isRestageEnumValue(DartObject? value, String name) {
  if (value == null || value.isNull) return false;
  final type = value.type;
  final element = type?.element;
  return element is EnumElement &&
      element.name == name &&
      libraryUriMatchesOrigin(
        element.library.identifier,
        kRestageSharedLibraryOrigin,
      );
}

bool _isRestageFlowClass(ClassElement element) {
  for (var current = element.supertype; current != null;) {
    final type = current;
    if (type.element.name == 'RestageFlow' &&
        libraryUriMatchesOrigin(
          type.element.library.identifier,
          kRestageSdkLibraryOrigin,
        )) {
      return true;
    }
    current = type.element.supertype;
  }
  return false;
}

bool _isRestageTypeConstructor(
  InstanceCreationExpression expression,
  String typeName,
) {
  final owner = expression.constructorName.type.element;
  return owner is InterfaceElement &&
      owner.name == typeName &&
      libraryUriMatchesOrigin(
        owner.library.identifier,
        kRestageSdkLibraryOrigin,
      );
}

Future<AstNode?> _initializerFor(
  TopLevelVariableElement variable,
  LibraryElement library,
) async {
  final resolved = await library.session.getResolvedLibraryByElement(library);
  if (resolved is! ResolvedLibraryResult) return null;
  final node = resolved.getFragmentDeclaration(variable.firstFragment)?.node;
  return node is VariableDeclaration ? node.initializer : null;
}

void _validateImplicitFlowCount(
  List<NormalizedFlowSource> flows,
  AssetId assetId,
  List<Issue> issues,
) {
  final implicit =
      flows.where((flow) => !flow.hasExplicitId && flow.isCanonical);
  if (implicit.length <= 1) return;
  issues.add(
    Issue(
      code: IssueCode.duplicateId,
      message: 'At most one canonical @FlowGraph declaration may omit id in '
          'a library; add explicit unique ids to the remaining declarations.',
      location: assetId.path,
    ),
  );
}

String _fileStem(String path) {
  final slash = path.lastIndexOf('/');
  final filename = slash == -1 ? path : path.substring(slash + 1);
  return filename.endsWith('.dart')
      ? filename.substring(0, filename.length - '.dart'.length)
      : filename;
}

/// Parser for the flattened object algebra.
///
/// The parser deliberately lowers directly into the DTOs consumed by the
/// existing flow validator and codec.  Its only state is analyzer identity and
/// the literal graph data; it does not introduce a second inference model.
final class _FlowDefinitionGraphParser {
  _FlowDefinitionGraphParser(
    this.initializer, {
    required this.library,
    required this.assetId,
    required this.flow,
    required this.version,
    required this.minClient,
    required this.delivery,
    required this.surface,
    required this.issues,
  });

  final InstanceCreationExpression initializer;
  final LibraryElement library;
  final AssetId assetId;
  final String flow;
  final int version;
  final int minClient;
  final FlowDeliveryMode delivery;
  final Surface surface;
  final List<Issue> issues;

  final _states = <String, FlowState>{};
  final _screens = <String, NormalizedScreenReference>{};
  final _screenTransitions = <String, Map<String, FlowTransition>>{};
  final _flowState = <String, FlowStateDeclaration>{};
  final _stateRefs = <Element, _StateInfo>{};
  final _declaredStateElements = <String, VariableElement>{};
  final _actions = <String, FlowActionContract>{};
  final _actionElements = <String, Element>{};
  final _childFlows = <NormalizedFlowIdentity, NormalizedChildFlowReference>{};
  final _nodeIdentities = <String, _NodeIdentity>{};
  final _screenStateIds = <String, String>{};
  final _parsedNodes = <String>{};
  final _parsingNodes = <String>{};
  String? _terminalId;
  late final Map<String, Object?> _terminalResult;

  Future<NormalizedFlowGraph?> parse() async {
    final start = _named(initializer, 'start');
    final transitions = _named(initializer, 'transitions');
    if (start == null || transitions is! ListLiteral) {
      issues.add(
        Issue(
          code: IssueCode.buildMethodTooComplex,
          message: 'FlowDefinition requires start: and a literal '
              'transitions: list.',
          location: assetId.path,
        ),
      );
      return null;
    }
    final initial = await _screenReference(start, flowSurface: surface);
    if (initial == null) return null;
    _registerScreen(initial);

    if (!await _parseStateDeclarations(_named(initializer, 'state'))) {
      return null;
    }
    if (!await _parseOutbound(_named(initializer, 'outbound'))) return null;

    final nodes = _named(initializer, 'nodes');
    if (nodes != null && !await _parseNodeList(nodes)) return null;

    for (final element in transitions.elements) {
      if (element is! Expression ||
          element is! InstanceCreationExpression ||
          !_isRestageCreation(element, 'Transition')) {
        _issue(
          IssueCode.buildMethodTooComplex,
          'FlowDefinition.transitions must contain resolved Transition(...) '
          'instances.',
        );
        continue;
      }
      await _parseTransition(element);
    }

    if (_terminalId != null) {
      _states[_terminalId!] = EndFlowState(result: _terminalResult);
    }
    for (final entry in _screenTransitions.entries) {
      _states[entry.key] = ScreenFlowState(
        screen: _screenStateIds[entry.key] ?? entry.key,
        on: Map.unmodifiable(entry.value),
      );
    }
    for (final screen in _screens.values) {
      final stateId = _screenStateId(screen);
      _states.putIfAbsent(
        stateId,
        () => ScreenFlowState(
          screen: screen.id,
          on: _screenTransitions[stateId] ?? const {},
        ),
      );
    }

    final graph = NormalizedFlowGraph(
      flow: flow,
      version: version,
      minClient: minClient,
      delivery: delivery,
      initial: _screenStateId(initial),
      states: _states,
      flowState: _flowState,
      outbound: _outbound,
      actions: _actions,
      screens: _screens,
      childFlows: _childFlows,
    );
    _validateGraph(graph);
    if (issues.isNotEmpty) return null;
    return graph;
  }

  FlowOutboundDeclarations _outbound = const FlowOutboundDeclarations();

  void _validateGraph(NormalizedFlowGraph graph) {
    final artifacts = <String, ScreenArtifact>{
      for (final screen in _screens.values)
        screen.id: ScreenArtifact(
          path: '${screen.id}.rfw',
          version: screen.version,
          schemaVersion: 1,
          minClient: screen.minClient,
          contentHash: FlowContentHash.parse(_zeroHash),
        ),
    };
    try {
      FlowDocumentValidation.checkValid(graph.toDocument(artifacts));
    } on Object catch (error) {
      _issue(
        IssueCode.malformedTranslatorOutput,
        'Normalized FlowDefinition failed graph validation: $error',
      );
    }
  }

  Future<bool> _parseStateDeclarations(Expression? expression) async {
    if (expression == null) return true;
    if (expression is! ListLiteral) {
      _issue(
          IssueCode.buildMethodTooComplex,
          'FlowDefinition.state must be a '
          'literal list of FlowStateRef declarations.');
      return false;
    }
    for (final element in expression.elements) {
      if (element is! Expression) {
        _issue(
            IssueCode.buildMethodTooComplex,
            'Flow state declarations may '
            'not contain collection control or spreads.');
        return false;
      }
      final state = await _stateInfo(element);
      if (state == null) return false;
      final declaration = state.element;
      if (declaration == null) {
        _issue(
          IssueCode.unresolvedIdentifier,
          'FlowDefinition.state entries must reference analyzer-resolved '
          'FlowStateRef declarations.',
        );
        return false;
      }
      if (_flowState.containsKey(state.key)) {
        _issue(
          IssueCode.duplicateId,
          'Flow-state key "${state.key}" is declared more than once.',
        );
        return false;
      }
      _declaredStateElements[state.key] = declaration;
      _flowState[state.key] = FlowStateDeclaration(
        type: state.type,
        classification: state.classification,
        defaultValue: state.defaultValue,
        hostSeedable: state.hostSeedable,
      );
    }
    return true;
  }

  Future<bool> _parseOutbound(Expression? expression) async {
    if (expression == null) return true;
    if (expression is! InstanceCreationExpression ||
        !_isRestageCreation(expression, 'FlowOutboundPolicy')) {
      _issue(
          IssueCode.unresolvedIdentifier,
          'FlowDefinition.outbound must '
          'resolve to the Restage FlowOutboundPolicy type.');
      return false;
    }
    final values = <String, FlowOutboundPayloadDeclaration>{};
    final terminal = await _outboundPayload(
      _named(expression, 'terminalResult'),
      values,
    );
    if (terminal == null) return false;
    final lifecycle = await _outboundPayload(
      _named(expression, 'lifecycle'),
      values,
    );
    if (lifecycle == null) return false;
    final survey = await _outboundPayload(
      _named(expression, 'surveyAnswers'),
      values,
    );
    if (survey == null) return false;
    final subflow = await _outboundPayload(
      _named(expression, 'subflowResult'),
      values,
    );
    if (subflow == null) return false;
    _outbound = FlowOutboundDeclarations(
      terminalResult: terminal,
      lifecycle: lifecycle,
      surveyAnswers: survey,
      subFlowResult: subflow,
    );
    return true;
  }

  Future<FlowOutboundPayloadDeclaration?> _outboundPayload(
    Expression? expression,
    Map<String, FlowOutboundPayloadDeclaration> unused,
  ) async {
    if (expression == null) return const FlowOutboundPayloadDeclaration();
    if (expression is! SetOrMapLiteral || !expression.isMap) {
      _issue(
          IssueCode.buildMethodTooComplex,
          'Outbound policy fields must '
          'be literal string-keyed maps.');
      return null;
    }
    final fields = <String, FlowOutboundField>{};
    for (final entry in expression.elements) {
      if (entry is! MapLiteralEntry) {
        _issue(
            IssueCode.buildMethodTooComplex,
            'Outbound maps may not contain '
            'collection control or spreads.');
        return null;
      }
      final key = _stringExpression(entry.key);
      if (key == null) {
        _issue(
            IssueCode.unresolvedIdentifier,
            'Outbound field names must be '
            'literal strings.');
        return null;
      }
      final state = await _declaredStateInfo(
        entry.value,
        use: 'Outbound field "$key"',
      );
      if (state == null) return null;
      fields[key] = FlowOutboundField(
        type: state.type,
        ref: StateFlowOutboundRef(key: state.key),
      );
    }
    return FlowOutboundPayloadDeclaration(fields: fields);
  }

  Future<bool> _parseNodeList(Expression expression) async {
    if (expression is! ListLiteral) {
      _issue(
          IssueCode.buildMethodTooComplex,
          'FlowDefinition.nodes must be a '
          'literal list.');
      return false;
    }
    for (final element in expression.elements) {
      if (element is! Expression) {
        _issue(
            IssueCode.buildMethodTooComplex,
            'FlowDefinition.nodes may not contain collection control or '
            'spreads.');
        return false;
      }
      if (!await _parseNode(element)) return false;
    }
    return true;
  }

  Future<void> _parseTransition(InstanceCreationExpression creation) async {
    final eventExpression = _positional(creation, 0);
    final event = await _eventInfo(eventExpression);
    if (event == null) return;

    NormalizedScreenReference? source;
    if (event.owner is ClassElement && !_resolvesToRestageSdk(event.owner)) {
      source = await _screenReferenceForElement(
        event.owner! as ClassElement,
        flowSurface: surface,
      );
    }
    final fromExpression = _named(creation, 'from');
    if (source == null) {
      if (fromExpression == null) {
        _issue(
          IssueCode.unresolvedIdentifier,
          'SDK-owned flow events require an explicit from: paywall target.',
        );
        return;
      }
      source = await _screenReference(fromExpression, flowSurface: surface);
      if (source == null || !source.isPaywall) {
        _issue(
          IssueCode.buildMethodTooComplex,
          'from: is permitted only for a @Paywall-owned flow event.',
        );
        return;
      }
    } else if (fromExpression != null) {
      _issue(
        IssueCode.buildMethodTooComplex,
        'from: is reserved for SDK-owned paywall events; ordinary screen '
        'events already identify their owning screen.',
      );
      return;
    }
    _registerScreen(source);

    final name = _constructorName(creation);
    final isCompletion = name == 'complete';
    final target = isCompletion ? null : await _target(_named(creation, 'to'));
    if (!isCompletion && target == null) {
      _issue(
          IssueCode.buildMethodTooComplex,
          'Every Transition must provide '
          'a resolved to: target.');
      return;
    }
    final writes = await _transitionWrites(
      _named(creation, 'writes'),
      event.scalarType,
    );
    if (writes == null) return;
    final capture = _named(creation, 'capture');
    if (capture != null) {
      final state = await _declaredStateInfo(
        capture,
        use: 'Transition.capture',
      );
      if (state == null || event.scalarType == null) {
        _issue(
            IssueCode.buildMethodTooComplex,
            'capture: requires a typed '
            'scalar SurfaceEvent and a declared FlowStateRef.');
        return;
      }
      if (state.type != event.scalarType) {
        _issue(
            IssueCode.buildMethodTooComplex,
            'Captured event type does not '
            'match its FlowStateRef declaration.');
        return;
      }
      if (writes.containsKey(state.key)) {
        _issue(
            IssueCode.duplicateId,
            'A transition may not write the same '
            'state key through both capture: and writes:.');
        return;
      }
      writes[state.key] = FlowStateWrite(
        type: state.type,
        value: const EventFlowValueSource(key: kCapturedEventValueKey),
      );
    }

    if (isCompletion) {
      final id = _stringNamedOrDefault(creation, 'id', 'done');
      final result = _jsonMap(
        _named(creation, 'result'),
      );
      if (result == null) return;
      if (!_registerNodeIdentity(
        id,
        const _NodeIdentity.syntheticTerminal(),
      )) {
        return;
      }
      _recordTerminal(id, result);
      _addTransition(
        _screenStateId(source),
        event.id,
        GotoFlowTransition(id, stateWrites: writes),
      );
      return;
    }

    final action = await _actionTransition(_named(creation, 'action'));
    if (_named(creation, 'action') != null && action == null) return;
    final transition = action == null
        ? GotoFlowTransition(target!, stateWrites: writes)
        : ActionFlowTransition(
            action: action.action,
            resultPredicate: action.predicate,
            target: target!,
            stateWrites: writes,
          );
    _addTransition(_screenStateId(source), event.id, transition);
  }

  void _addTransition(String source, String event, FlowTransition transition) {
    final events = _screenTransitions.putIfAbsent(source, () => {});
    if (events.containsKey(event)) {
      _issue(
        IssueCode.duplicateId,
        'Screen "$source" declares event "$event" more than once.',
      );
      return;
    }
    events[event] = transition;
  }

  Future<Map<String, FlowStateWrite>?> _transitionWrites(
    Expression? expression,
    FlowDataType? eventType,
  ) async {
    if (expression == null) return <String, FlowStateWrite>{};
    if (expression is! ListLiteral) {
      _issue(
          IssueCode.buildMethodTooComplex,
          'Transition.writes must be a '
          'literal list.');
      return null;
    }
    final writes = <String, FlowStateWrite>{};
    for (final element in expression.elements) {
      if (element is! MethodInvocation ||
          element.methodName.name != 'set' ||
          !_resolvesToRestageSdk(element.methodName.element)) {
        _issue(
            IssueCode.unresolvedIdentifier,
            'Flow writes must use the '
            'resolved FlowStateRef.set(...) API.');
        return null;
      }
      final state = await _declaredStateInfo(
        element.target,
        use: 'FlowStateRef.set(...)',
      );
      final literal = _literalWriteValue(_positional(element, 0));
      if (state == null || literal == null) return null;
      if (literal.type != state.type) {
        _issue(
            IssueCode.buildMethodTooComplex,
            'FlowStateRef.set(...) value '
            'does not match its declared state type.');
        return null;
      }
      if (writes.containsKey(state.key)) {
        _issue(
            IssueCode.duplicateId,
            'A transition writes state key '
            '"${state.key}" more than once.');
        return null;
      }
      writes[state.key] = FlowStateWrite(
        type: state.type,
        value: LiteralFlowValueSource(type: literal.type, value: literal.value),
      );
    }
    return writes;
  }

  Future<_ActionTransition?> _actionTransition(Expression? expression) async {
    if (expression is! MethodInvocation ||
        expression.methodName.name != 'continueWhen' ||
        !_resolvesToRestageSdk(expression.methodName.element)) {
      if (expression != null) {
        _issue(
            IssueCode.unresolvedIdentifier,
            'Transition.action must use a '
            'resolved FlowActionRef.continueWhen(...) gate.');
      }
      return null;
    }
    final field = _flowActionField(expression.target);
    if (field == null) return null;
    final actionId =
        field.computeConstantValue()?.getField('id')?.toStringValue();
    final type = field.type;
    if (actionId == null ||
        type is! InterfaceType ||
        type.typeArguments.length != 2) {
      _issue(
          IssueCode.unresolvedIdentifier,
          'Host action must be a resolved '
          'static const FlowActionRef<I, O>.');
      return null;
    }
    final argsSchema = _actionSchema(type.typeArguments[0]);
    final resultSchema = _actionSchema(type.typeArguments[1]);
    if (argsSchema == null || resultSchema == null) return null;
    final contract = FlowActionContract(
      actionName: actionId,
      contractVersion: 1,
      argsSchema: argsSchema,
      resultSchema: resultSchema,
      minClient: minClient,
      idempotent:
          field.computeConstantValue()?.getField('idempotent')?.toBoolValue() ??
              false,
    );
    final previous = _actions[actionId];
    final previousElement = _actionElements[actionId];
    if (previous != null &&
        (previousElement != field ||
            !_sameActionContract(previous, contract))) {
      _issue(
        IssueCode.duplicateId,
        'Host action id "$actionId" is declared by both '
        '${_elementIdentity(previousElement)} and ${_elementIdentity(field)} '
        'with incompatible contracts.',
      );
      return null;
    }
    if (previous == null) {
      _actions[actionId] = contract;
      _actionElements[actionId] = field;
    }
    final predicate = _actionPredicate(
      _positional(expression, 0),
      type.typeArguments[1],
    );
    if (predicate == null) return null;
    return _ActionTransition(action: actionId, predicate: predicate);
  }

  FlowActionResultPredicate? _actionPredicate(
    Expression? expression,
    DartType resultType,
  ) {
    if (expression is! FunctionExpression ||
        expression.parameters?.parameters.length != 1 ||
        expression.body is! ExpressionFunctionBody) {
      _issue(
          IssueCode.buildMethodTooComplex,
          'Host action predicates must be '
          'a single-parameter expression function.');
      return null;
    }
    final parameter = expression.parameters!.parameters.single.name?.lexeme;
    final body = (expression.body as ExpressionFunctionBody).expression;
    if (parameter == null) return null;
    if (resultType.isDartCoreBool) {
      if (body is SimpleIdentifier && body.name == parameter) {
        return const BoolEqualsActionResultPredicate(value: true);
      }
      if (body is PrefixExpression &&
          body.operator.lexeme == '!' &&
          body.operand is SimpleIdentifier &&
          (body.operand as SimpleIdentifier).name == parameter) {
        return const BoolEqualsActionResultPredicate(value: false);
      }
    }
    if (resultType is InterfaceType &&
        body is PropertyAccess &&
        body.target is SimpleIdentifier &&
        (body.target! as SimpleIdentifier).name == parameter) {
      final field = resultType.element.getField(body.propertyName.name);
      if (field != null && field.type.isDartCoreBool) {
        return ObjectBoolFieldEqualsActionResultPredicate(
          field: body.propertyName.name,
          value: true,
        );
      }
    }
    _issue(
        IssueCode.buildMethodTooComplex,
        'Unsupported host action result '
        'predicate; only boolean or boolean-field checks are supported.');
    return null;
  }

  Future<String?> _target(Expression? expression) async {
    if (expression == null) return null;
    final screenElement = _typeLiteralElement(expression);
    if (screenElement != null) {
      final screen = await _screenReference(expression, flowSurface: surface);
      if (screen != null) _registerScreen(screen);
      return screen == null ? null : _screenStateId(screen);
    }
    final element = _referencedVariableElement(expression);
    final creation = expression is InstanceCreationExpression
        ? expression
        : element == null
            ? null
            : await _initializerForVariable(element);
    if (creation == null || creation is! InstanceCreationExpression) {
      _issue(
          IssueCode.unresolvedIdentifier,
          'Flow target must be a resolved '
          'screen Type, FlowNode, or NodeRef.');
      return null;
    }
    final type = _resolvedCreationType(creation);
    if (type == null) return null;
    if (type == 'NodeRef') return _nodeRefId(creation);
    if (type == 'Completion' || type == 'Decision' || type == 'Subflow') {
      return _parseNodeCreation(creation, element: element);
    }
    _issue(
        IssueCode.unresolvedIdentifier,
        'Flow target constructor $type is '
        'not a supported Restage FlowNode.');
    return null;
  }

  Future<bool> _parseNode(Expression expression) async {
    final element = _referencedVariableElement(expression);
    final creation = expression is InstanceCreationExpression
        ? expression
        : element == null
            ? null
            : await _initializerForVariable(element);
    if (creation == null || creation is! InstanceCreationExpression) {
      _issue(
          IssueCode.unresolvedIdentifier,
          'Flow nodes must be resolved '
          'Decision, Completion, or Subflow declarations.');
      return false;
    }
    return await _parseNodeCreation(creation, element: element) != null;
  }

  Future<String?> _parseNodeCreation(
    InstanceCreationExpression creation, {
    Element? element,
  }) async {
    final type = _resolvedCreationType(creation);
    if (type == null) return null;
    final id = _stringExpression(_positional(creation, 0));
    if (id == null || id.isEmpty) {
      _issue(
          IssueCode.annotationEvaluationFailed,
          'Flow nodes require a '
          'non-empty stable id.');
      return null;
    }
    final identity = element == null
        ? _NodeIdentity.creation(creation)
        : _NodeIdentity.declaration(element);
    final previous = _nodeIdentities[id];
    if (!_registerNodeIdentity(id, identity)) return null;
    if (previous != null) {
      // A reference to a node that is already being lowered is a valid graph
      // cycle.  A completed node is likewise a valid repeated reference.
      if (_parsedNodes.contains(id) || _parsingNodes.contains(id)) return id;
    }
    _parsingNodes.add(id);
    String? result;
    switch (type) {
      case 'Completion':
        final value = _jsonMap(_named(creation, 'result'));
        if (value != null) {
          _recordTerminal(id, value);
          _states[id] = EndFlowState(result: value);
          result = id;
        }
      case 'Decision':
        result = await _parseDecision(creation, id);
      case 'Subflow':
        result = await _parseSubflow(creation, id);
    }
    _parsingNodes.remove(id);
    if (result != null) _parsedNodes.add(id);
    return result;
  }

  Future<String?> _parseDecision(
    InstanceCreationExpression creation,
    String id,
  ) async {
    final branchesExpression = _named(creation, 'branches');
    if (branchesExpression is! ListLiteral) {
      _issue(
          IssueCode.buildMethodTooComplex,
          'Decision.branches must be a '
          'literal list.');
      return null;
    }
    final branches = <FlowBranch>[];
    for (final expression in branchesExpression.elements) {
      if (expression is! InstanceCreationExpression ||
          !_isRestageCreation(expression, 'Branch')) {
        _issue(
            IssueCode.unresolvedIdentifier,
            'Decision branches must use '
            'the resolved Branch constructor.');
        return null;
      }
      final when = await _condition(_named(expression, 'when'));
      final target = await _target(_named(expression, 'to'));
      final writes =
          await _transitionWrites(_named(expression, 'writes'), null);
      if (when == null || target == null || writes == null) return null;
      branches.add(FlowBranch(when: when, target: target, stateWrites: writes));
    }
    final otherwise = await _target(_named(creation, 'otherwise'));
    if (otherwise == null) return null;
    _states[id] = DecisionFlowState(
      branches: branches,
      defaultBranch: FlowBranchTarget(target: otherwise),
    );
    return id;
  }

  Future<String?> _parseSubflow(
    InstanceCreationExpression creation,
    String id,
  ) async {
    final child = await _flowReference(_named(creation, 'flow'));
    final onComplete = await _target(_named(creation, 'onComplete'));
    final unavailableExpression = _named(creation, 'onUnavailable');
    final unavailable = unavailableExpression == null
        ? null
        : await _target(unavailableExpression);
    if (child == null ||
        onComplete == null ||
        (unavailableExpression != null && unavailable == null)) {
      return null;
    }
    final input = await _subflowInput(_named(creation, 'input'));
    if (input == null) return null;
    final branch = FlowBranch(
      when: const FlowBranchPredicate(fields: {}),
      target: onComplete,
    );
    _states[id] = SubFlowState(
      flow: child.identity.id,
      version: child.version,
      schemaVersion: 1,
      minClient: child.minClient,
      contentHash: FlowContentHash.parse(_zeroHash),
      input: input,
      onComplete: [branch],
      defaultBranch: FlowBranchTarget(target: onComplete),
      subFlowUnavailable:
          unavailable == null ? null : FlowBranchTarget(target: unavailable),
    );
    return id;
  }

  Future<Map<String, FlowValueSource>?> _subflowInput(
    Expression? expression,
  ) async {
    if (expression == null) return <String, FlowValueSource>{};
    if (expression is! ListLiteral) {
      _issue(
          IssueCode.buildMethodTooComplex,
          'Subflow.input must be a literal '
          'list of typed state input references.');
      return null;
    }
    final result = <String, FlowValueSource>{};
    for (final value in expression.elements) {
      if (value is! MethodInvocation ||
          (value.methodName.name != 'fromState' &&
              value.methodName.name != 'fromValue') ||
          !_resolvesToRestageSdk(value.methodName.element)) {
        _issue(
            IssueCode.unresolvedIdentifier,
            'Subflow inputs must use the '
            'resolved FlowStateRef.fromState/fromValue API.');
        return null;
      }
      final child = await _stateInfo(value.target);
      if (child == null) return null;
      if (result.containsKey(child.key)) {
        _issue(
          IssueCode.duplicateId,
          'Subflow input child key "${child.key}" is mapped more than once.',
        );
        return null;
      }
      final source = value.methodName.name == 'fromState'
          ? await _declaredStateInfo(
              _positional(value, 0),
              use: 'Subflow parent-state input',
            )
          : null;
      if (value.methodName.name == 'fromState') {
        if (source == null || source.type != child.type) return null;
        result[child.key] = StateFlowValueSource(key: source.key);
      } else {
        final literal = _literalWriteValue(_positional(value, 0));
        if (literal == null || literal.type != child.type) return null;
        result[child.key] = LiteralFlowValueSource(
          type: literal.type,
          value: literal.value,
        );
      }
    }
    return result;
  }

  Future<_ChildFlow?> _flowReference(Expression? expression) async {
    if (expression == null) return null;

    // A class-shaped advanced flow is referenced by its resolved Type
    // literal.  It is deliberately handled before variable references so a
    // class named like a flow cannot fall through to generated-name guessing.
    final classElement = _typeLiteralElement(expression);
    if (classElement != null) {
      return _childFlowFromDeclaration(classElement, requireClass: true);
    }

    final element = _referencedVariableElement(expression);
    if (element != null) {
      final type = element.type;
      if (_isSurfaceFlowReferenceType(type)) {
        final value = element.computeConstantValue();
        final id = value?.getField('id')?.toStringValue();
        final version = value?.getField('version')?.toIntValue();
        final min = value?.getField('minClient')?.toIntValue();
        final childSurface = _surfaceFromValue(value?.getField('surface'));
        if (id != null &&
            version != null &&
            min != null &&
            childSurface != null) {
          return _recordChildFlow(
            _ChildFlow(
              identity: NormalizedFlowIdentity(
                surface: childSurface,
                id: id,
              ),
              version: version,
              minClient: min,
              declarationIdentity: _elementIdentity(element),
            ),
          );
        }
        _issue(
          IssueCode.annotationEvaluationFailed,
          'SurfaceFlowRef must const-evaluate to a non-empty id, version, '
          'minClient, and explicit Surface.',
        );
        return null;
      }
      return _childFlowFromDeclaration(element);
    }
    _issue(
        IssueCode.unresolvedIdentifier,
        'Subflow.flow must reference a '
        'resolved @FlowGraph Type or SurfaceFlowRef.');
    return null;
  }

  bool _isSurfaceFlowReferenceType(DartType type) {
    final alias = type.alias;
    if (alias != null &&
        alias.element.name == 'OnboardingFlowRef' &&
        libraryUriMatchesOrigin(
          alias.element.library.identifier,
          kRestageSdkLibraryOrigin,
        )) {
      return true;
    }
    return type is InterfaceType &&
        type.element.name == 'SurfaceFlowRef' &&
        libraryUriMatchesOrigin(
          type.element.library.identifier,
          kRestageSdkLibraryOrigin,
        );
  }

  _ChildFlow? _childFlowFromDeclaration(
    Element element, {
    bool requireClass = false,
  }) {
    if (requireClass && element is! ClassElement) {
      _issue(
        IssueCode.unresolvedIdentifier,
        'Subflow.flow Type must resolve to a canonical @FlowGraph class.',
      );
      return null;
    }
    if (element is ClassElement && !_isRestageFlowClass(element)) {
      _issue(
        IssueCode.unsupportedBaseClass,
        'Subflow.flow Type ${element.name} must resolve to a '
        'canonical @FlowGraph class extending package:restage RestageFlow.',
      );
      return null;
    }
    final annotation = _flowAnnotationFor(element);
    final annotationOwner =
        annotation == null ? null : resolvedAnnotationClass(annotation);
    if (annotation == null ||
        annotationOwner == null ||
        annotationOwner.name != 'FlowGraph' ||
        !libraryUriMatchesOrigin(
          annotationOwner.library.identifier,
          kRestageSdkLibraryOrigin,
        )) {
      _issue(
        IssueCode.unresolvedIdentifier,
        element is ClassElement
            ? 'Subflow.flow Type must resolve to a canonical '
                '@FlowGraph class.'
            : 'Subflow.flow must resolve to a canonical '
                '@FlowGraph declaration.',
      );
      return null;
    }
    final value = annotation.computeConstantValue();
    final idValue = value?.getField('id');
    final id = idValue == null || idValue.isNull
        ? _libraryStem(element.library!)
        : idValue.toStringValue();
    final childSurface = _surfaceFromValue(value?.getField('surface'));
    if (id == null || id.isEmpty || childSurface == null) {
      _issue(
        IssueCode.annotationEvaluationFailed,
        'Canonical @FlowGraph child references require a non-empty id and '
        'explicit Surface.',
      );
      return null;
    }
    final version = value?.getField('version')?.toIntValue() ?? 1;
    final min =
        value?.getField('minClient')?.toIntValue() ?? kBaselineCatalogVersion;
    return _recordChildFlow(
      _ChildFlow(
        identity: NormalizedFlowIdentity(surface: childSurface, id: id),
        version: version,
        minClient: min,
        declarationIdentity: _elementIdentity(element),
      ),
    );
  }

  _ChildFlow? _recordChildFlow(_ChildFlow child) {
    if (child.identity.surface != surface) {
      _issue(
        IssueCode.buildMethodTooComplex,
        'Subflow child ${child.identity.surface.wireName}/'
        '${child.identity.id} cannot be included in a '
        '${surface.wireName} flow.',
      );
      return null;
    }
    final reference = NormalizedChildFlowReference(
      identity: child.identity,
      version: child.version,
      minClient: child.minClient,
      declarationIdentity: child.declarationIdentity,
    );
    final previous = _childFlows[child.identity];
    if (previous != null &&
        (previous.declarationIdentity != reference.declarationIdentity ||
            previous.version != reference.version ||
            previous.minClient != reference.minClient)) {
      _issue(
        IssueCode.duplicateId,
        'Subflow identity ${child.identity.surface.wireName}/'
        '${child.identity.id} resolves to incompatible declarations '
        '${previous.declarationIdentity} and ${reference.declarationIdentity}.',
      );
      return null;
    }
    _childFlows[child.identity] = reference;
    return child;
  }

  Future<FlowBranchPredicate?> _condition(Expression? expression) async {
    if (expression is! MethodInvocation ||
        !_resolvesToRestageSdk(expression.methodName.element)) {
      _issue(
          IssueCode.unresolvedIdentifier,
          'Decision conditions must use a '
          'resolved FlowStateRef condition method.');
      return null;
    }
    final state = await _declaredStateInfo(
      expression.target,
      use: 'Decision predicate',
    );
    if (state == null) return null;
    final method = expression.methodName.name;
    if (method == 'isSet' || method == 'isUnset') {
      if (expression.argumentList.arguments.isNotEmpty) return null;
      return FlowBranchPredicate(
        fields: {
          state.key: ExistsFlowPredicateCondition(
            exists: method == 'isSet',
          ),
        },
      );
    }
    final argument = _positional(expression, 0);
    if (method == 'equalsState') {
      final other = await _declaredStateInfo(
        argument,
        use: 'FlowStateRef.equalsState(...) argument',
      );
      if (other == null || other.type != state.type) return null;
      return FlowBranchPredicate(
        fields: {
          state.key: EqualsFlowPredicateCondition(
            value: StateFlowValueSource(key: other.key),
          ),
        },
      );
    }
    final relation = switch (method) {
      'equals' => 'equals',
      'notEquals' => 'notEquals',
      'oneOf' => 'oneOf',
      'greaterThan' => 'greaterThan',
      'atLeast' => 'atLeast',
      'lessThan' => 'lessThan',
      'atMost' => 'atMost',
      _ => null,
    };
    if (relation == null) return null;
    final value =
        relation == 'oneOf' ? _literalList(argument) : _literalValue(argument);
    if (value == null) return null;
    if (relation == 'oneOf') {
      final values = (value as List<Object?>)
          .map(_literalFlowValue)
          .whereType<FlowValueSource>()
          .toList();
      if (values.length != value.length) return null;
      return FlowBranchPredicate(
        fields: {
          state.key: InFlowPredicateCondition(values: values),
        },
      );
    }
    final source = _literalFlowValue(value);
    if (source == null) return null;
    final condition = switch (relation) {
      'equals' => EqualsFlowPredicateCondition(value: source),
      'notEquals' => NotEqualsFlowPredicateCondition(value: source),
      'greaterThan' => GreaterThanFlowPredicateCondition(value: source),
      'atLeast' => GreaterThanOrEqualsFlowPredicateCondition(value: source),
      'lessThan' => LessThanFlowPredicateCondition(value: source),
      'atMost' => LessThanOrEqualsFlowPredicateCondition(value: source),
      _ => null,
    };
    if (condition == null) return null;
    return FlowBranchPredicate(
      fields: {state.key: condition},
    );
  }

  Future<_StateInfo?> _stateInfo(Expression? expression) async {
    if (expression == null) return null;
    final element = _referencedVariableElement(expression);
    if (element != null) {
      final cached = _stateRefs[element];
      if (cached != null) return cached;
      final type = element.type;
      final value = element.computeConstantValue();
      final initializer = await _initializerForVariable(element);
      final creation =
          initializer is InstanceCreationExpression ? initializer : null;
      final info = _makeStateInfo(
        type,
        element: element,
        key: value?.getField('key')?.toStringValue() ??
            (creation == null
                ? null
                : _stringExpression(_positional(creation, 0))),
        classification: _classificationFromValue(
              value?.getField('classification'),
            ) ??
            (creation == null
                ? null
                : _classificationFromExpression(
                    _named(creation, 'classification'),
                  )),
        defaultValue: _dartObjectValue(value?.getField('defaultValue')) ??
            (creation == null
                ? null
                : _literalValue(_named(creation, 'defaultValue'))),
      );
      if (info != null) {
        _stateRefs[element] = info;
        return info;
      }
    }
    if (expression is InstanceCreationExpression) {
      final type = expression.staticType;
      return _makeStateInfo(
        type,
        element: null,
        key: _stringExpression(_positional(expression, 0)),
        classification: _classificationFromExpression(
          _named(expression, 'classification'),
        ),
        defaultValue: _literalValue(_named(expression, 'defaultValue')),
      );
    }
    _issue(
        IssueCode.unresolvedIdentifier,
        'Expected a resolved '
        'FlowStateRef<T> declaration.');
    return null;
  }

  Future<_StateInfo?> _declaredStateInfo(
    Expression? expression, {
    required String use,
  }) async {
    final state = await _stateInfo(expression);
    if (state == null) return null;
    final declaration = _declaredStateElements[state.key];
    if (declaration == null) {
      _issue(
        IssueCode.unresolvedIdentifier,
        '$use references flow-state key "${state.key}", which is not '
        'declared in FlowDefinition.state.',
      );
      return null;
    }
    if (!identical(declaration, state.element)) {
      _issue(
        IssueCode.duplicateId,
        '$use for flow-state key "${state.key}" must reuse the exact '
        'analyzer-resolved FlowStateRef declaration from '
        'FlowDefinition.state.',
      );
      return null;
    }
    return state;
  }

  _StateInfo? _makeStateInfo(
    DartType? type, {
    required VariableElement? element,
    required String? key,
    required FlowStateClassification? classification,
    required Object? defaultValue,
  }) {
    if (type is! InterfaceType ||
        (type.element.name != 'FlowStateRef' &&
            type.element.name != 'SeedableFlowStateRef') ||
        !libraryUriMatchesOrigin(
          type.element.library.identifier,
          kRestageSdkLibraryOrigin,
        ) ||
        type.typeArguments.length != 1 ||
        key == null ||
        key.isEmpty) {
      _issue(
          IssueCode.unresolvedIdentifier,
          'Flow-state references must be '
          'resolved SDK FlowStateRef<T> values with a non-empty key.');
      return null;
    }
    final dataType = _dataType(type.typeArguments.single);
    if (dataType == null) {
      _issue(
          IssueCode.buildMethodTooComplex,
          'FlowStateRef supports only '
          'bool, int, and String values.');
      return null;
    }
    final effectiveClassification =
        classification ?? FlowStateClassification.internal;
    final state = _StateInfo(
      element: element,
      key: key,
      type: dataType,
      classification: effectiveClassification,
      defaultValue: defaultValue,
      hostSeedable: type.element.name == 'SeedableFlowStateRef',
    );
    return state;
  }

  Future<_EventInfo?> _eventInfo(Expression? expression) async {
    final field = _eventField(expression);
    if (field == null) {
      _issue(
          IssueCode.unresolvedIdentifier,
          'Transition events must be '
          'analyzer-resolved static const SurfaceEvent fields.');
      return null;
    }
    final value = field.element.computeConstantValue();
    final id = value?.getField('id')?.toStringValue();
    final type = field.element.type;
    if (id == null ||
        type is! InterfaceType ||
        type.typeArguments.length != 1) {
      _issue(
          IssueCode.annotationEvaluationFailed,
          'SurfaceEvent could not be '
          'const-evaluated.');
      return null;
    }
    final scalar = _dataType(type.typeArguments.single);
    return _EventInfo(
      id: id,
      field: field.element,
      owner: field.element.enclosingElement,
      scalarType: scalar,
    );
  }

  Future<NormalizedScreenReference?> _screenReference(
    Expression expression, {
    required Surface flowSurface,
  }) async {
    final element = _typeLiteralElement(expression);
    if (element == null) {
      _issue(
        IssueCode.unresolvedIdentifier,
        'Flow screen references must be analyzer-resolved Type literals.',
      );
      return null;
    }
    return _screenReferenceForElement(element, flowSurface: flowSurface);
  }

  Future<NormalizedScreenReference?> _screenReferenceForElement(
    ClassElement element, {
    Surface? flowSurface,
  }) async {
    final annotation = firstAnnotationFromOriginAny(
      element,
      const {
        'Screen',
        'ScreenSource',
        'OnboardingSource',
        'Paywall',
        'PaywallSource',
      },
      kRestageSdkLibraryOrigin,
    );
    if (annotation == null ||
        !annotationHasOrigin(annotation, kRestageSdkLibraryOrigin)) {
      _issue(
          IssueCode.unresolvedIdentifier,
          'Flow screen target must resolve '
          'to a Restage @Screen or @Paywall declaration.');
      return null;
    }
    if (!_isSupportedFlutterWidget(element)) {
      _issue(
          IssueCode.unsupportedBaseClass,
          'Flow screen target ${element.name} '
          'must resolve to a Flutter StatelessWidget or StatefulWidget.');
      return null;
    }
    final metadata = _screenMetadata(annotation);
    if (metadata == null) return null;
    if (metadata.id != null && metadata.id!.isEmpty) {
      _issue(
        IssueCode.annotationEvaluationFailed,
        '${annotation.toSource()} id must be a non-empty String literal.',
      );
      return null;
    }
    if (flowSurface != null &&
        !metadata.isPaywall &&
        metadata.declaredSurface != null &&
        metadata.declaredSurface != flowSurface) {
      _issue(
        IssueCode.buildMethodTooComplex,
        'Categorized screen ${element.name} '
        'has surface ${metadata.declaredSurface!.wireName}, but the '
        'containing flow is ${flowSurface.wireName}.',
      );
      return null;
    }
    final sourceIdentity = metadata.id ?? _libraryStem(element.library);
    final sourceId = metadata.isPaywall
        ? '$kPaywallScreenIdPrefix$sourceIdentity'
        : sourceIdentity;
    final reference = NormalizedScreenReference(
      id: sourceId,
      element: element,
      declaredSurface: metadata.declaredSurface,
      effectiveSurface:
          flowSurface ?? metadata.declaredSurface ?? Surface.general,
      isPaywall: metadata.isPaywall,
      version: metadata.version,
      minClient: metadata.minClient,
    );
    _registerScreen(reference);
    return reference;
  }

  _EventField? _eventField(Expression? expression) {
    final element = _referencedVariableElement(expression);
    if (element is! FieldElement || !element.isStatic || !element.isConst) {
      return null;
    }
    final type = element.type;
    if (type is! InterfaceType ||
        (type.element.name != 'SurfaceEvent' &&
            type.element.name != 'OnboardingEvent') ||
        !libraryUriMatchesOrigin(
          type.element.library.identifier,
          kRestageSdkLibraryOrigin,
        )) {
      return null;
    }
    final args = type.typeArguments;
    return _EventField(
      element,
      args.length == 1 ? _dataType(args.single) : null,
    );
  }

  VariableElement? _flowActionField(Expression? expression) {
    final element = _referencedVariableElement(expression);
    if (element is! VariableElement || !element.isConst) {
      return null;
    }
    if (element is FieldElement && !element.isStatic) return null;
    final type = element.type;
    if (type is! InterfaceType ||
        type.element.name != 'FlowActionRef' ||
        !libraryUriMatchesOrigin(
          type.element.library.identifier,
          kRestageSdkLibraryOrigin,
        )) {
      return null;
    }
    return element;
  }

  void _recordTerminal(String id, Map<String, Object?> result) {
    if (_terminalId == null) {
      _terminalId = id;
      _terminalResult = result;
      return;
    }
    if (_terminalId != id || !_deepEqualMap(_terminalResult, result)) {
      _issue(
          IssueCode.duplicateId,
          'All completion paths must converge on '
          'one terminal identity; found $_terminalId and $id.');
    }
  }

  bool _registerNodeIdentity(String id, _NodeIdentity identity) {
    final previous = _nodeIdentities[id];
    if (previous != null) {
      if (previous.sameAs(identity)) return true;
      _issue(
        IssueCode.duplicateId,
        'Flow node id "$id" resolves to distinct analyzer declarations '
        'or creations (${previous.description} and '
        '${identity.description}).',
      );
      return false;
    }
    if (_screens.containsKey(id)) {
      _issue(
        IssueCode.duplicateId,
        'Flow node id "$id" collides with screen identity "$id"; '
        'node and screen identities must be distinct.',
      );
      return false;
    }
    _nodeIdentities[id] = identity;
    return true;
  }

  void _issue(IssueCode code, String message) {
    issues.add(Issue(code: code, message: message, location: assetId.path));
  }

  String _screenStateId(NormalizedScreenReference screen) {
    _screenStateIds[screen.id] = screen.id;
    return screen.id;
  }

  void _registerScreen(NormalizedScreenReference screen) {
    if (_nodeIdentities.containsKey(screen.id)) {
      _issue(
        IssueCode.duplicateId,
        'Screen identity "${screen.id}" collides with flow node id '
        '"${screen.id}"; node and screen identities must be distinct.',
      );
      return;
    }
    final previous = _screens[screen.id];
    if (previous != null && previous.element != screen.element) {
      _issue(
        IssueCode.duplicateId,
        'Screen identity "${screen.id}" resolves to both '
        '${previous.declarationIdentity} and ${screen.declarationIdentity}.',
      );
      return;
    }
    _screens[screen.id] = screen;
  }

  bool _resolvesToRestageSdk(Element? element) {
    final library = element?.library;
    return library != null &&
        libraryUriMatchesOrigin(library.identifier, kRestageSdkLibraryOrigin);
  }
}

final class _ScreenMetadata {
  const _ScreenMetadata({
    required this.id,
    required this.declaredSurface,
    required this.isPaywall,
    required this.version,
    required this.minClient,
  });

  final String? id;
  final Surface? declaredSurface;
  final bool isPaywall;
  final int version;
  final int minClient;
}

_ScreenMetadata? _screenMetadata(
  ElementAnnotation annotation,
) {
  final owner = resolvedAnnotationClass(annotation);
  final value = annotation.computeConstantValue();
  if (owner == null || value == null) return null;
  final isPaywall = owner.name == 'Paywall' || owner.name == 'PaywallSource';
  final idValue = value.getField('id');
  final id = idValue == null || idValue.isNull ? null : idValue.toStringValue();
  final declaredSurface = isPaywall
      ? Surface.paywall
      : _surfaceFromValue(value.getField('surface'));
  return _ScreenMetadata(
    id: id,
    declaredSurface: declaredSurface,
    isPaywall: isPaywall,
    version: value.getField('version')?.toIntValue() ?? 1,
    minClient:
        value.getField('minClient')?.toIntValue() ?? kBaselineCatalogVersion,
  );
}

const String _zeroHash =
    'sha256:0000000000000000000000000000000000000000000000000000000000000000';

final class _StateInfo {
  const _StateInfo({
    required this.element,
    required this.key,
    required this.type,
    required this.classification,
    required this.defaultValue,
    required this.hostSeedable,
  });

  final VariableElement? element;
  final String key;
  final FlowDataType type;
  final FlowStateClassification classification;
  final Object? defaultValue;
  final bool hostSeedable;
}

final class _NodeIdentity {
  const _NodeIdentity.declaration(this.element)
      : creation = null,
        syntheticTerminal = false;

  const _NodeIdentity.creation(this.creation)
      : element = null,
        syntheticTerminal = false;

  const _NodeIdentity.syntheticTerminal()
      : element = null,
        creation = null,
        syntheticTerminal = true;

  final Element? element;
  final InstanceCreationExpression? creation;
  final bool syntheticTerminal;

  bool sameAs(_NodeIdentity other) {
    if (syntheticTerminal || other.syntheticTerminal) {
      return syntheticTerminal && other.syntheticTerminal;
    }
    if (element != null || other.element != null) {
      return identical(element, other.element);
    }
    return identical(creation, other.creation);
  }

  String get description {
    if (syntheticTerminal) return 'a Transition.complete synthetic terminal';
    final declaration = element;
    return declaration == null
        ? 'a direct resolved node creation'
        : _elementIdentity(declaration);
  }
}

final class _EventField {
  const _EventField(this.element, this.scalarType);

  final FieldElement element;
  final FlowDataType? scalarType;
}

final class _EventInfo {
  const _EventInfo({
    required this.id,
    required this.field,
    required this.owner,
    required this.scalarType,
  });

  final String id;
  final FieldElement field;
  final Element? owner;
  final FlowDataType? scalarType;
}

final class _ActionTransition {
  const _ActionTransition({required this.action, required this.predicate});

  final String action;
  final FlowActionResultPredicate predicate;
}

final class _ChildFlow {
  const _ChildFlow({
    required this.identity,
    required this.version,
    required this.minClient,
    required this.declarationIdentity,
  });

  final NormalizedFlowIdentity identity;
  final int version;
  final int minClient;
  final String declarationIdentity;
}

bool _isRestageCreation(
  InstanceCreationExpression expression,
  String typeName,
) {
  final type = expression.constructorName.type.element;
  return type is InterfaceElement &&
      type.name == typeName &&
      libraryUriMatchesOrigin(
        type.library.identifier,
        kRestageSdkLibraryOrigin,
      );
}

String? _resolvedCreationType(InstanceCreationExpression expression) {
  final type = expression.constructorName.type.element;
  if (type is! InterfaceElement ||
      !libraryUriMatchesOrigin(
        type.library.identifier,
        kRestageSdkLibraryOrigin,
      )) {
    return null;
  }
  return type.name;
}

String? _constructorName(InstanceCreationExpression expression) {
  return expression.constructorName.name?.name;
}

String _elementIdentity(Element? element) {
  if (element == null) return '<unknown>';
  return '${element.library?.identifier ?? '<unknown>'}#'
      '${element.name ?? '<unnamed>'}';
}

bool _sameActionContract(
  FlowActionContract left,
  FlowActionContract right,
) {
  return left.actionName == right.actionName &&
      left.contractVersion == right.contractVersion &&
      left.minClient == right.minClient &&
      left.idempotent == right.idempotent &&
      FlowActionSchema.hashFor(
            contractKind: 'args',
            schema: left.argsSchema,
          ) ==
          FlowActionSchema.hashFor(
            contractKind: 'args',
            schema: right.argsSchema,
          ) &&
      FlowActionSchema.hashFor(
            contractKind: 'result',
            schema: left.resultSchema,
          ) ==
          FlowActionSchema.hashFor(
            contractKind: 'result',
            schema: right.resultSchema,
          );
}

Expression? _positional(AstNode node, int index) {
  final arguments = switch (node) {
    InstanceCreationExpression(:final argumentList) => argumentList.arguments,
    MethodInvocation(:final argumentList) => argumentList.arguments,
    _ => const <Expression>[],
  };
  final positional = arguments.whereType<Expression>().toList();
  return index < positional.length ? positional[index] : null;
}

String _stringNamedOrDefault(
  InstanceCreationExpression expression,
  String name,
  String fallback,
) {
  return _stringExpression(_named(expression, name)) ?? fallback;
}

String? _stringExpression(Expression? expression) {
  if (expression is SimpleStringLiteral) return expression.value;
  if (expression is AdjacentStrings) {
    final values = expression.strings
        .whereType<SimpleStringLiteral>()
        .map((literal) => literal.value)
        .toList();
    if (values.length == expression.strings.length) return values.join();
  }
  if (expression is StringInterpolation) return null;
  if (expression is ParenthesizedExpression) {
    return _stringExpression(expression.expression);
  }
  return null;
}

({FlowDataType type, Object value})? _literalWriteValue(
  Expression? expression,
) {
  final value = _literalValue(expression);
  if (value is String) return (type: FlowDataType.string, value: value);
  if (value is bool) return (type: FlowDataType.bool, value: value);
  if (value is int) return (type: FlowDataType.int, value: value);
  return null;
}

Object? _literalValue(Expression? expression) {
  if (expression == null) return null;
  if (expression is ParenthesizedExpression) {
    return _literalValue(expression.expression);
  }
  final string = _stringExpression(expression);
  if (string != null) return string;
  if (expression is BooleanLiteral) return expression.value;
  if (expression is IntegerLiteral) return expression.value;
  if (expression is DoubleLiteral) return expression.value;
  if (expression is NullLiteral) return null;
  if (expression is PrefixExpression && expression.operator.lexeme == '-') {
    final value = _literalValue(expression.operand);
    if (value is num) return -value;
  }
  if (expression is ListLiteral) return _literalList(expression);
  if (expression is SetOrMapLiteral && expression.isMap) {
    final map = <String, Object?>{};
    for (final entry in expression.elements) {
      if (entry is! MapLiteralEntry) return null;
      final key = _stringExpression(entry.key);
      if (key == null) return null;
      map[key] = _literalValue(entry.value);
    }
    return map;
  }
  return null;
}

List<Object?>? _literalList(Expression? expression) {
  if (expression is! ListLiteral) return null;
  final values = <Object?>[];
  for (final element in expression.elements) {
    if (element is! Expression) return null;
    final value = _literalValue(element);
    if (value == null && element is! NullLiteral) return null;
    values.add(value);
  }
  return values;
}

FlowValueSource? _literalFlowValue(Object? value) {
  if (value is String) {
    return LiteralFlowValueSource(type: FlowDataType.string, value: value);
  }
  if (value is bool) {
    return LiteralFlowValueSource(type: FlowDataType.bool, value: value);
  }
  if (value is int) {
    return LiteralFlowValueSource(type: FlowDataType.int, value: value);
  }
  return null;
}

Map<String, Object?>? _jsonMap(Expression? expression) {
  if (expression == null) return <String, Object?>{};
  final value = _literalValue(expression);
  if (value is! Map) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String || !_isJsonValue(entry.value)) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}

bool _isJsonValue(Object? value) {
  if (value == null || value is String || value is bool || value is num) {
    return true;
  }
  if (value is List) return value.every(_isJsonValue);
  if (value is Map) {
    return value.entries.every(
      (entry) => entry.key is String && _isJsonValue(entry.value),
    );
  }
  return false;
}

Object? _dartObjectValue(DartObject? value) {
  if (value == null || value.isNull) return null;
  final string = value.toStringValue();
  if (string != null) return string;
  final boolean = value.toBoolValue();
  if (boolean != null) return boolean;
  final integer = value.toIntValue();
  if (integer != null) return integer;
  final double = value.toDoubleValue();
  if (double != null) return double;
  return null;
}

FlowActionSchema? _actionSchema(DartType type) {
  switch (type.getDisplayString()) {
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
  if (type is InterfaceType &&
      type.element.name == 'List' &&
      type.element.library.identifier == 'dart:core' &&
      type.typeArguments.length == 1) {
    final child = _actionSchema(type.typeArguments.single);
    return child == null ? null : FlowActionSchema.list(child);
  }
  if (type is InterfaceType && type.element.library.identifier != 'dart:core') {
    final fields = <String, FlowActionSchemaField>{};
    for (final field in type.element.fields) {
      if (field.isStatic || !field.isOriginDeclaration) continue;
      final name = field.name;
      if (name == null || !field.isFinal) return null;
      final schema = _actionSchema(field.type);
      if (schema == null) return null;
      fields[name] = FlowActionSchemaField(required: true, schema: schema);
    }
    return FlowActionSchema.object(fields);
  }
  return null;
}

FlowDataType? _dataType(DartType type) {
  if (type.isDartCoreBool) return FlowDataType.bool;
  if (type.isDartCoreInt) return FlowDataType.int;
  if (type.isDartCoreString) return FlowDataType.string;
  return null;
}

FlowStateClassification? _classificationFromValue(DartObject? value) {
  if (!_isRestageEnumValue(value, 'FlowStateClassification')) return null;
  final wireName = value!.getField('wireName')?.toStringValue() ??
      value.getField('_name')?.toStringValue();
  if (wireName == null) return null;
  for (final classification in FlowStateClassification.values) {
    if (classification.wireName == wireName ||
        classification.name == wireName) {
      return classification;
    }
  }
  return null;
}

FlowStateClassification? _classificationFromExpression(Expression? expression) {
  final field = _resolvedStaticEnumField(
    expression,
    'FlowStateClassification',
  );
  return field == null
      ? null
      : _classificationFromValue(field.computeConstantValue());
}

FieldElement? _resolvedStaticEnumField(
  Expression? expression,
  String enumName,
) {
  final element = _referencedVariableElement(expression);
  if (element is! FieldElement || !element.isStatic || !element.isConst) {
    return null;
  }
  final owner = element.enclosingElement;
  if (owner is! EnumElement || owner.name != enumName) return null;
  if (!libraryUriMatchesOrigin(
    owner.library.identifier,
    kRestageSharedLibraryOrigin,
  )) {
    return null;
  }
  return element;
}

String _libraryStem(LibraryElement library) {
  return _fileStem(library.identifier);
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
  if (element is PropertyAccessorElement) element = element.variable;
  return element is VariableElement ? element : null;
}

Future<AstNode?> _initializerForVariable(VariableElement variable) async {
  final library = variable.library;
  if (library == null) return null;
  final resolved = await library.session.getResolvedLibraryByElement(library);
  if (resolved is! ResolvedLibraryResult) return null;
  final node = resolved.getFragmentDeclaration(variable.firstFragment)?.node;
  return node is VariableDeclaration ? node.initializer : null;
}

String? _nodeRefId(InstanceCreationExpression expression) {
  return _stringExpression(_positional(expression, 0));
}

bool _deepEqualMap(Map<String, Object?> left, Map<String, Object?> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!_deepEqualValue(entry.value, right[entry.key])) return false;
  }
  return true;
}

bool _deepEqualValue(Object? left, Object? right) {
  if (left is Map<String, Object?> && right is Map<String, Object?>) {
    return _deepEqualMap(left, right);
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        List.generate(left.length, (index) => index).every(
          (index) => _deepEqualValue(left[index], right[index]),
        );
  }
  return left == right;
}

ClassElement? _typeLiteralElement(Expression expression) {
  if (expression is TypeLiteral) {
    final element = expression.type.element;
    if (element is ClassElement) return element;
  }
  if (expression is SimpleIdentifier && expression.element is ClassElement) {
    return expression.element! as ClassElement;
  }
  if (expression is PrefixedIdentifier &&
      expression.identifier.element is ClassElement) {
    return expression.identifier.element! as ClassElement;
  }
  if (expression is PropertyAccess &&
      expression.propertyName.element is ClassElement) {
    return expression.propertyName.element! as ClassElement;
  }
  return null;
}

bool _isSupportedFlutterWidget(ClassElement element) {
  for (var current = element.supertype; current != null;) {
    final name = current.element.name;
    final library = current.element.library.identifier;
    if ((name == 'StatelessWidget' || name == 'StatefulWidget') &&
        library.startsWith('package:flutter/')) {
      return true;
    }
    current = current.element.supertype;
  }
  return false;
}

Expression? _named(
  InstanceCreationExpression expression,
  String name,
) {
  for (final argument in expression.argumentList.arguments) {
    if (argument is NamedExpression && argument.name.label.name == name) {
      return argument.expression;
    }
  }
  return null;
}
