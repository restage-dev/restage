// Internal builder implementation is reached through documented factories.
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/onboarding/flow_definition_frontend.dart';
import 'package:restage_codegen/src/onboarding/general_discipline_validators.dart';
import 'package:restage_codegen/src/surface_publication/package_surface_compiler_builder.dart';
import 'package:restage_codegen/src/syntax_diagnostics.dart';
import 'package:restage_shared/restage_shared.dart';

const String _kSdkLibraryOrigin = 'package:restage';

// The product surface (`onboarding` / `message` / `survey`) is carried by the
// source directory: a flow lives at `lib/<surface>/flows/<stem>.dart` and its
// screens at `lib/<surface>/screens/`. These derive the four source/output
// roots from the surface segment. `buildExtensions` and the output writes in
// `build` (which must match the declared extensions) read the segment from
// the builder's configured `surface`; the top-level helper functions, which
// have no builder instance in scope, derive it from the input path via
// `_surfaceSegmentOf`. The two agree by construction: build_runner only
// routes inputs under `lib/<surface>/flows/` to the builder configured with
// that surface.
String _flowSourceDir(String surface) => 'lib/$surface/flows';
String _screenSourceDir(String surface) => 'lib/$surface/screens';
String _flowOutputDir(String surface) => 'assets/$surface/flows';
String _screenOutputDir(String surface) => 'assets/$surface/screens';

/// The surface segment carried by a `lib/<surface>/{flows,screens}/...` path.
///
/// Only meaningful for asset ids build_runner routed through a surface
/// builder's glob; the assert is a misuse tripwire for any future caller
/// handing it a non-routed path.
String _surfaceSegmentOf(AssetId assetId) {
  final segments = p.split(assetId.path);
  assert(
    segments.length > 2 && segments.first == 'lib',
    'Expected a lib/<surface>/... asset path, got "${assetId.path}".',
  );
  return segments[1];
}

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
  OnboardingFlowBuilder(this.options, {this.surface = Surface.onboarding}) {
    if (!_flowSurfaces.contains(surface)) {
      throw ArgumentError.value(
        surface,
        'surface',
        'must be a flow surface (onboarding / message / survey); paywalls '
            'have dedicated builders',
      );
    }
  }

  /// The surfaces this builder may codegen for. Paywalls have dedicated
  /// builders; a new surface type must be added here deliberately.
  static const Set<Surface> _flowSurfaces = {
    Surface.onboarding,
    Surface.message,
    Surface.survey,
  };

  final BuilderOptions options;

  bool get _aggregateOwnsCanonical =>
      options.config['aggregate_canonical_owner'] == true;

  /// The flow surface (`onboarding` / `message` / `survey`) this builder
  /// instance codegens for. Defaults to [Surface.onboarding], the surface
  /// this builder originally served.
  final Surface surface;

  @override
  Map<String, List<String>> get buildExtensions {
    final flowSource = _flowSourceDir(surface.wireName);
    final flowOutput = _flowOutputDir(surface.wireName);
    final extensions = <String, List<String>>{
      '$flowSource/{{name}}.dart': [
        '$flowSource/{{name}}.rsflow.g.dart',
        '$flowOutput/{{name}}.flow.json',
      ],
    };
    if (surface == Surface.onboarding) {
      extensions['lib/general/flows/{{name}}.dart'] = const [
        'lib/general/flows/{{name}}.rsflow.g.dart',
        'assets/general/flows/{{name}}.flow.json',
      ];
    }
    return extensions;
  }

  @override
  Future<void> build(BuildStep buildStep) async {
    final assetId = buildStep.inputId;
    if (!await buildStep.resolver.isLibrary(assetId)) return;
    final library = await buildStep.resolver.libraryFor(
      assetId,
      allowSyntaxErrors: true,
    );
    final frontend = await inspectFlowDefinitions(
      library,
      assetId,
      legacySurface: surface,
    );
    if (frontend.issues.isNotEmpty) _surfaceIssues(frontend.issues);
    final canonical = frontend.flows
        .where((flow) => flow.isCanonical)
        .toList(growable: false);
    if (canonical.isNotEmpty) {
      if (_aggregateOwnsCanonical) return;
      await _writeCanonicalFallback(buildStep, canonical);
      return;
    }
    final result = await compileResolvedClassFlows(
      buildStep,
      library: library,
      assetId: assetId,
      legacySurface: surface,
      includeCanonical: false,
    );
    if (result.issues.isNotEmpty) _surfaceIssues(result.issues);
    if (result.flows.isEmpty) return;
    if (result.flows.length != 1) {
      _surfaceIssues([
        Issue(
          code: IssueCode.invalidScreenSourceCount,
          message: 'A conventional legacy flow library must compile exactly '
              'one flow; found ${result.flows.length}.',
          location: assetId.path,
        ),
      ]);
    }
    final compiled = result.flows.single;
    final stem = p.basenameWithoutExtension(assetId.path);
    final surfaceSeg = compiled.surface.wireName;
    await Future.wait<void>([
      buildStep.writeAsString(
        AssetId(
          assetId.package,
          '${_flowSourceDir(surfaceSeg)}/$stem.rsflow.g.dart',
        ),
        compiled.generatedPart,
      ),
      buildStep.writeAsBytes(
        AssetId(
          assetId.package,
          '${_flowOutputDir(surfaceSeg)}/$stem.flow.json',
        ),
        compiled.flowDocumentBytes,
      ),
    ]);
  }

  Future<void> _writeCanonicalFallback(
    BuildStep buildStep,
    List<NormalizedFlowSource> flows,
  ) async {
    final compilation = await compileTrackedPackageSurfaces(buildStep);
    if (!compilation.isValid) _surfaceIssues(compilation.issues);
    final publication = compilation.publicationBundle;
    final selected = flows.first;
    final stem = p.basenameWithoutExtension(buildStep.inputId.path);
    final inputSurface = p.posix.split(buildStep.inputId.path)[1];
    final canonicalPath =
        'assets/${selected.surface.wireName}/flows/${selected.id}.flow.json';
    final destinationPath = 'assets/$inputSurface/flows/$stem.flow.json';
    final partPath = '${p.posix.dirname(buildStep.inputId.path)}/'
        '$stem.rsflow.g.dart';
    final document = publication.artifacts[canonicalPath];
    final generatedPart = compilation.generatedParts[partPath];
    if (document == null || generatedPart == null) {
      _surfaceIssues([
        Issue(
          code: IssueCode.missingScreenDescriptor,
          message: 'Standalone canonical flow fallback could not find the '
              'aggregate artifact family for ${selected.id}.',
          location: buildStep.inputId.path,
        ),
      ]);
    }
    await Future.wait<void>([
      buildStep.writeAsBytes(
        AssetId(buildStep.inputId.package, destinationPath),
        document,
      ),
      buildStep.writeAsString(
        AssetId(buildStep.inputId.package, partPath),
        generatedPart,
      ),
    ]);
  }
}

@immutable
final class CompiledClassFlow {
  CompiledClassFlow({
    required this.declaration,
    required this.id,
    required this.surface,
    required this.isCanonical,
    required List<int> flowDocumentBytes,
    required this.generatedPart,
  }) : flowDocumentBytes = Uint8List.fromList(flowDocumentBytes);

  final ClassElement declaration;
  final String id;
  final Surface surface;
  final bool isCanonical;
  final Uint8List flowDocumentBytes;
  final String generatedPart;

  String get declarationIdentity =>
      '${declaration.library.identifier}#${declaration.name ?? '<unnamed>'}';
}

@immutable
final class CompiledClassFlowResult {
  CompiledClassFlowResult({
    required List<CompiledClassFlow> flows,
    required List<Issue> issues,
  })  : flows = List.unmodifiable(flows),
        issues = List.unmodifiable(issues);

  final List<CompiledClassFlow> flows;
  final List<Issue> issues;
}

@immutable
final class ResolvedClassFlowDependency {
  ResolvedClassFlowDependency({
    required this.declaration,
    required this.identity,
    required Iterable<NormalizedFlowIdentity> childIdentities,
  }) : childIdentities = Set.unmodifiable(childIdentities);

  final ClassElement declaration;
  final NormalizedFlowIdentity identity;
  final Set<NormalizedFlowIdentity> childIdentities;

  String get declarationIdentity =>
      '${declaration.library.identifier}#${declaration.name ?? '<unnamed>'}';
}

@immutable
final class ResolvedClassFlowDependencyResult {
  ResolvedClassFlowDependencyResult({
    required Iterable<ResolvedClassFlowDependency> flows,
    required Iterable<Issue> issues,
  })  : flows = List.unmodifiable(flows),
        issues = List.unmodifiable(issues);

  final List<ResolvedClassFlowDependency> flows;
  final List<Issue> issues;
}

@immutable
final class ResolvedClassFlowScreen {
  ResolvedClassFlowScreen({
    required this.declaration,
    required this.surface,
    required this.id,
    required this.artifactPath,
    required this.version,
    required this.minClient,
    required List<int> blob,
    this.canonicalPaywallId,
  }) : blob = Uint8List.fromList(blob);

  /// Resolved authored declaration. The generated descriptor spelling is only
  /// a syntax bridge; this element remains the screen's authority.
  final ClassElement declaration;

  /// The authored category, if this screen is categorized rather than neutral.
  final Surface? surface;
  final String id;
  final String artifactPath;
  final int version;
  final int minClient;
  final Uint8List blob;

  /// The roster-owned authored paywall ID when this is a canonical paywall
  /// adapter. Ordinary screens and legacy paywalls leave this unset.
  final String? canonicalPaywallId;

  String get declarationIdentity =>
      '${declaration.library.identifier}#${declaration.name ?? '<unnamed>'}';

  String? get descriptorName {
    final className = declaration.name;
    return className == null ? null : '${className}Descriptor';
  }
}

/// Resolves the complete surface-aware child-flow dependency set used by a
/// class-shaped flow before aggregate compilation schedules document lowering.
Future<ResolvedClassFlowDependencyResult> inspectResolvedClassFlowDependencies({
  required LibraryElement library,
  required AssetId assetId,
  required Surface legacySurface,
  bool includeCanonical = true,
  bool includeLegacy = true,
}) async {
  final issues = <Issue>[];
  final dependencies = <ResolvedClassFlowDependency>[];
  final candidates = _findFlows(library, assetId)
      .where(
        (flow) => flow.isCanonical ? includeCanonical : includeLegacy,
      )
      .toList(growable: false);
  for (final flow in candidates) {
    final method = await _resolvedBuildFlow(library, flow, issues, assetId);
    if (method == null || issues.isNotEmpty) continue;
    final visitor = _SubFlowInvocationVisitor();
    method.accept(visitor);
    final children = <NormalizedFlowIdentity>{};
    final parentSurface = flow.surface ?? legacySurface;
    for (final invocation in visitor.invocations) {
      final child = _flowRefForExpression(
        _namedArg(invocation, 'flow'),
        issues,
        assetId,
        legacySurfaceFallback: flow.isCanonical ? null : parentSurface,
      );
      if (child == null) continue;
      if (child.surface != parentSurface) {
        issues.add(
          Issue(
            code: IssueCode.buildMethodTooComplex,
            message: 'Subflow child ${child.surface.wireName}/${child.id} '
                'cannot be included in a ${parentSurface.wireName} flow.',
            location: assetId.path,
          ),
        );
        continue;
      }
      children.add(child.identity);
    }
    dependencies.add(
      ResolvedClassFlowDependency(
        declaration: flow.element,
        identity: NormalizedFlowIdentity(
          surface: parentSurface,
          id: flow.id,
        ),
        childIdentities: children,
      ),
    );
  }
  return ResolvedClassFlowDependencyResult(
    flows: issues.isEmpty ? dependencies : const [],
    issues: issues,
  );
}

/// Invokes the proven class-shaped flow lowerer without claiming an output
/// path. The package owner uses this for canonical advanced flows; legacy
/// per-source builders use the same bytes while retaining their old paths.
Future<CompiledClassFlowResult> compileResolvedClassFlows(
  BuildStep buildStep, {
  required LibraryElement library,
  required AssetId assetId,
  required Surface legacySurface,
  bool includeCanonical = true,
  bool includeLegacy = true,
  Iterable<ResolvedClassFlowScreen> resolvedScreens = const [],
  Map<NormalizedFlowIdentity, List<int>> childFlowDocuments = const {},
  Set<String>? declarationIdentities,
}) async {
  final issues = <Issue>[];
  final sourceText = await buildStep.readAsString(assetId);
  final resolvedForSyntax =
      await library.session.getResolvedLibraryByElement(library);
  if (resolvedForSyntax is ResolvedLibraryResult &&
      resolvedForSyntax.units.isNotEmpty) {
    issues.addAll(
      syntacticErrorIssues(resolvedForSyntax, sourcePath: assetId.path),
    );
  }

  final candidates = _findFlows(library, assetId)
      .where(
        (flow) => flow.isCanonical ? includeCanonical : includeLegacy,
      )
      .where(
        (flow) =>
            declarationIdentities == null ||
            declarationIdentities.contains(
              '${flow.element.library.identifier}#'
              '${flow.element.name ?? '<unnamed>'}',
            ),
      )
      .toList(growable: false);
  if (candidates.isEmpty || issues.isNotEmpty) {
    return CompiledClassFlowResult(flows: const [], issues: issues);
  }

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
  final resolvedScreenList = resolvedScreens.toList(growable: false);
  final legacyScreenDescriptors = resolvedScreenList.isEmpty
      ? await _loadImportedScreenDescriptors(buildStep, assetId, issues)
      : <String, _ScreenDescriptor>{};
  final screenBlobsByDeclarationIdentity = <String, Uint8List>{};
  for (final screen in resolvedScreenList) {
    screenBlobsByDeclarationIdentity[screen.declarationIdentity] =
        Uint8List.fromList(screen.blob);
  }
  final compiled = <CompiledClassFlow>[];
  for (final flow in candidates) {
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
    if (!flow.isCanonical && flow.id != stem) {
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
      if (!_isWireIdentifier(action.actionName)) {
        issues.add(
          Issue(
            code: IssueCode.buildMethodTooComplex,
            message: 'invalid action id "${action.actionName}": action ids '
                'must be valid flow wire identifiers.',
            location: '${assetId.path}#${flow.className}.${action.fieldName}',
          ),
        );
      }
      final duplicateOf = action.duplicateOf;
      if (duplicateOf != null) {
        issues.add(
          Issue(
            code: IssueCode.buildMethodTooComplex,
            message: 'duplicate action id "${action.actionName}" on '
                '${action.fieldName}; already declared by $duplicateOf.',
            location: '${assetId.path}#${flow.className}.${action.fieldName}',
          ),
        );
      }
    }
    if (issues.isNotEmpty) continue;

    final method = await _resolvedBuildFlow(library, flow, issues, assetId);
    if (method == null || issues.isNotEmpty) continue;
    final effectiveSurface = flow.surface ?? legacySurface;
    final lowered = await _lowerFlow(
      buildStep,
      flow,
      method,
      _ScreenDescriptorResolver(
        flowLibrary: library,
        flowSurface: effectiveSurface,
        legacyDescriptors: legacyScreenDescriptors,
        resolvedScreens: resolvedScreenList,
      ),
      issues,
      assetId,
      screenBlobsByDeclarationIdentity,
      childFlowDocuments,
    );
    if (lowered == null || issues.isNotEmpty) continue;
    compiled.add(
      CompiledClassFlow(
        declaration: flow.element,
        id: flow.id,
        surface: effectiveSurface,
        isCanonical: flow.isCanonical,
        flowDocumentBytes: FlowDocumentCodec.encodeCanonicalJson(
          lowered.document,
        ),
        generatedPart: formatGeneratedDart(
          _emitFlowDescriptor(stem, flow, lowered, effectiveSurface),
        ),
      ),
    );
  }
  return CompiledClassFlowResult(
    flows: issues.isEmpty ? compiled : const [],
    issues: issues,
  );
}

List<_FlowSource> _findFlows(LibraryElement library, AssetId assetId) {
  final flows = <_FlowSource>[];
  for (final cls in library.classes) {
    final annotation = firstAnnotationFromOriginAny(
      cls,
      const {'FlowGraph', 'FlowSource', 'OnboardingFlow'},
      _kSdkLibraryOrigin,
    );
    if (annotation == null) continue;
    final value = annotation.computeConstantValue();
    if (value == null) {
      flows.add(_FlowSource.invalid(cls));
      continue;
    }
    final isCanonical =
        resolvedAnnotationClass(annotation)?.name == 'FlowGraph';
    final id = value.getField('id')?.toStringValue() ??
        (isCanonical ? p.basenameWithoutExtension(assetId.path) : null);
    if (id == null) {
      flows.add(_FlowSource.invalid(cls));
      continue;
    }
    Surface? declaredSurface;
    if (isCanonical) {
      final surfaceName =
          value.getField('surface')?.getField('wireName')?.toStringValue();
      declaredSurface = Surface.values
          .where((candidate) => candidate.wireName == surfaceName)
          .firstOrNull;
      if (declaredSurface == null) {
        flows.add(_FlowSource.invalid(cls));
        continue;
      }
    }
    final deliveryName =
        value.getField('delivery')?.getField('_name')?.toStringValue();
    FlowDeliveryMode? delivery;
    for (final mode in FlowDeliveryMode.values) {
      if (mode.name == deliveryName) {
        delivery = mode;
        break;
      }
    }
    if (delivery == null) {
      flows.add(_FlowSource.invalid(cls));
      continue;
    }
    final className = cls.name ?? '<unnamed>';
    flows.add(
      _FlowSource(
        id: id,
        version: value.getField('version')?.toIntValue() ?? 1,
        minClient: value.getField('minClient')?.toIntValue() ?? 3,
        delivery: delivery,
        className: className,
        element: cls,
        actions: _collectActions(cls),
        invalidAnnotation: false,
        isCanonical: isCanonical,
        surface: declaredSurface,
      ),
    );
  }
  return flows;
}

_FlowSource? _findFlow(LibraryElement library, AssetId assetId) =>
    _findFlows(library, assetId).firstOrNull;

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
  final screenSourceDir = _screenSourceDir(_surfaceSegmentOf(flowAssetId));
  final importPattern = RegExp(r'''import\s+['"]([^'"]+)['"]\s*;''');
  final descriptors = <String, _ScreenDescriptor>{};
  for (final match in importPattern.allMatches(source)) {
    final uri = match.group(1)!;
    if (!uri.startsWith('../screens/')) continue;
    final screenPath = p.normalize(p.join(p.dirname(flowAssetId.path), uri));
    if (!screenPath.startsWith(screenSourceDir)) continue;
    final stem = p.basenameWithoutExtension(screenPath);
    final generatedId = AssetId(
      flowAssetId.package,
      '$screenSourceDir/$stem.rsscreen.g.dart',
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
    r'(?:OnboardingScreenRef|SurfaceScreenRef)\s*\([\s\S]*?'
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
  _ScreenDescriptorResolver descriptors,
  List<Issue> issues,
  AssetId assetId,
  Map<String, Uint8List> resolvedScreenBlobsByDeclarationIdentity,
  Map<NormalizedFlowIdentity, List<int>> childFlowDocuments,
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
      : _flowStateDeclarations(flowStateExpr, issues, assetId, flow.className);
  final outbound = outboundExpr == null
      ? const FlowOutboundDeclarations()
      : _outboundDeclarations(outboundExpr, issues, assetId);
  if (flowState == null || outbound == null) return null;

  if (flow.delivery == FlowDeliveryMode.general) {
    issues.addAll(
      validateGeneralDiscipline(
        outbound: outbound,
        flowState: flowState,
        location: '${assetId.path}#${flow.className}.buildFlow',
      ),
    );
  }

  final screenArtifacts = <String, ScreenArtifact>{};
  final states = <String, FlowState>{};
  bool addState(String id, FlowState state) {
    if (states.containsKey(id)) {
      issues.add(
        Issue(
          code: IssueCode.buildMethodTooComplex,
          message: "duplicate state '$id' in flow.",
          location: assetId.path,
        ),
      );
      return false;
    }
    states[id] = state;
    return true;
  }

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
      addState(endState, EndFlowState(result: result));
      continue;
    }

    final graphNode = await _parseGraphNode(
      buildStep,
      assetId,
      flow,
      element,
      descriptors,
      endLocals,
      nodeLocals,
      issues,
      childFlowDocuments,
    );
    if (graphNode != null) {
      addState(graphNode.id, graphNode.state);
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
      flowState,
      flow.minClient,
      issues,
      assetId,
    );
    if (screenNode == null) continue;
    for (final transition in screenNode.transitions) {
      final actionContract = transition.actionContract;
      if (actionContract != null) {
        usedActionContracts[actionContract.actionName] = actionContract;
      }
    }
    final state = ScreenFlowState(
      screen: screenNode.screen.id,
      on: {
        for (final transition in screenNode.transitions)
          transition.eventId: transition.transition,
      },
    );
    if (!addState(screenNode.screen.id, state)) continue;
    final descriptor = screenNode.screen;
    screenArtifacts[descriptor.id] = await _artifactFor(
      buildStep,
      assetId,
      descriptor,
      issues,
      resolvedScreenBlobsByDeclarationIdentity,
    );
  }
  final hasTerminalScreenState = states.values.any(
    (state) => state is ScreenFlowState && state.on.isEmpty,
  );
  if (endCount > 1 || (endCount == 0 && !hasTerminalScreenState)) {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message: 'Flows must declare one end state unless a reachable screen '
            'has no outgoing transitions; found $endCount end states.',
        location: '${assetId.path}#${flow.className}.buildFlow',
      ),
    );
  }
  if (endCount <= 1) {
    _validateTypedTerminalResultShape(
      delivery: flow.delivery,
      initialStateId: initial.id,
      states: states,
      flowState: flowState,
      outbound: outbound,
      issues: issues,
      assetId: assetId,
      flowClassName: flow.className,
    );
  }
  screenArtifacts[initial.id] = await _artifactFor(
    buildStep,
    assetId,
    initial,
    issues,
    resolvedScreenBlobsByDeclarationIdentity,
  );

  final orderedScreenArtifacts = screenArtifacts.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  for (final entry in orderedScreenArtifacts) {
    if (flow.minClient >= entry.value.minClient) continue;
    issues.add(
      Issue(
        code: IssueCode.annotationEvaluationFailed,
        message: 'Flow ${flow.id} minClient ${flow.minClient} does not cover '
            'screen ${entry.key} minClient ${entry.value.minClient}.',
        location: assetId.path,
      ),
    );
  }

  if (issues.isNotEmpty) return null;
  final document = FlowDocument(
    flow: flow.id,
    version: flow.version,
    schemaVersion: 1,
    minClient: flow.minClient,
    deliveryMode: flow.delivery,
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
  Map<String, Uint8List> resolvedScreenBlobsByDeclarationIdentity,
) async {
  final declarationIdentity = descriptor.declarationIdentity;
  final resolvedBlob = declarationIdentity == null
      ? null
      : resolvedScreenBlobsByDeclarationIdentity[declarationIdentity];
  if (resolvedBlob != null) {
    return ScreenArtifact(
      path: descriptor.artifactPath,
      version: descriptor.version,
      schemaVersion: 1,
      minClient: descriptor.minClient,
      contentHash: FlowContentHash.compute(resolvedBlob),
    );
  }
  if (declarationIdentity != null) {
    issues.add(
      Issue(
        code: IssueCode.missingScreenDescriptor,
        message: 'Resolved screen $declarationIdentity is missing its exact '
            'aggregate-owned artifact bytes.',
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
  final AssetId rfwId;
  if (isPaywallScreenArtifact(descriptor.artifactPath)) {
    final canonicalId = AssetId(
      flowAssetId.package,
      '$kPaywallScreensAssetDir/${descriptor.artifactPath}',
    );
    final legacyId = AssetId(
      flowAssetId.package,
      '$kLegacyPaywallScreensAssetDir/${descriptor.artifactPath}',
    );
    if (await buildStep.canRead(canonicalId)) {
      rfwId = canonicalId;
    } else if (await buildStep.canRead(legacyId)) {
      rfwId = legacyId;
    } else {
      rfwId = canonicalId;
    }
  } else {
    rfwId = AssetId(
      flowAssetId.package,
      '${_screenOutputDir(_surfaceSegmentOf(flowAssetId))}/'
      '${descriptor.artifactPath}',
    );
  }
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
  _ScreenDescriptorResolver descriptors,
  Map<String, String> endLocals,
  Map<String, String> nodeLocals,
  Map<String, _FlowAction> actionsByName,
  Map<String, FlowActionContract> actionContracts,
  Map<String, FlowStateDeclaration> flowState,
  int minClient,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression is MethodInvocation &&
      expression.methodName.name == 'screen') {
    final screen = _screenForRef(
      expression.argumentList.arguments.firstOrNull,
      descriptors,
      issues,
      assetId,
    );
    if (screen == null) return null;
    return _ScreenNode(screen: screen, transitions: const []);
  }

  if (expression is! MethodInvocation || expression.methodName.name != 'goTo') {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message: 'Flow states must be screen(ref), '
            'screen(ref).on(event)…goTo(target), or end(...) in the current '
            'flow runtime.',
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

  // Peel a contiguous run of `.capture()`/`.write()` calls between the
  // `.goTo()` and the `.on()`/`.result()`. The chain nests outermost-first,
  // so collect descending toward the receiver, then reverse to authored order.
  var cursor = expression.target;
  final writeCalls = <MethodInvocation>[];
  while (cursor is MethodInvocation &&
      (cursor.methodName.name == 'capture' ||
          cursor.methodName.name == 'write')) {
    writeCalls.add(cursor);
    cursor = cursor.target;
  }
  final orderedWriteCalls = writeCalls.reversed.toList();

  final actionTransition = _parseActionTransition(
    cursor,
    target,
    actionsByName,
    actionContracts,
    minClient,
    issues,
    assetId,
  );
  final onCall =
      actionTransition?.onCall ?? (cursor is MethodInvocation ? cursor : null);
  if (onCall is! MethodInvocation || onCall.methodName.name != 'on') {
    issues.add(
      Issue(
        code: IssueCode.buildMethodTooComplex,
        message: 'Screen transitions must call .on(event)…goTo(target) or '
            '.on(event).run(action).result(predicate)…goTo(target).',
        location: assetId.path,
      ),
    );
    return null;
  }

  final eventArg = onCall.argumentList.arguments.firstOrNull;
  final event = _eventId(eventArg, issues, assetId);
  if (event == null) return null;
  final eventScalarType = _eventScalarFlowDataType(eventArg);
  final stateWrites = _lowerTransitionStateWrites(
    orderedWriteCalls,
    eventScalarType,
    flowState,
    issues,
    assetId,
  );
  if (stateWrites == null) return null;

  final FlowTransition transition;
  final FlowActionContract? contract;
  if (actionTransition != null) {
    final parsed = actionTransition.transition;
    transition = ActionFlowTransition(
      action: parsed.action,
      resultPredicate: parsed.resultPredicate,
      target: target,
      stateWrites: stateWrites,
    );
    contract = actionTransition.contract;
  } else {
    transition = GotoFlowTransition(target, stateWrites: stateWrites);
    contract = null;
  }
  final thisTransition = _ScreenTransition(
    eventId: event,
    transition: transition,
    actionContract: contract,
  );

  // The `.on()` receiver is either `screen(ref)` (the first transition on this
  // screen) or a prior `.goTo()` chain (a chained fork). Recurse on the latter
  // so all transitions accumulate into one screen node.
  final receiver = onCall.target;
  if (receiver is MethodInvocation && receiver.methodName.name == 'screen') {
    final screen = _screenForRef(
      receiver.argumentList.arguments.firstOrNull,
      descriptors,
      issues,
      assetId,
    );
    if (screen == null) return null;
    return _ScreenNode(screen: screen, transitions: [thisTransition]);
  }
  if (receiver is MethodInvocation && receiver.methodName.name == 'goTo') {
    final prior = _parseScreenNode(
      receiver,
      descriptors,
      endLocals,
      nodeLocals,
      actionsByName,
      actionContracts,
      flowState,
      minClient,
      issues,
      assetId,
    );
    if (prior == null) return null;
    if (prior.transitions.any((t) => t.eventId == event)) {
      issues.add(
        Issue(
          code: IssueCode.buildMethodTooComplex,
          message: "duplicate event '$event' on screen "
              "'${prior.screen.id}': a screen may author at most one "
              'transition per event.',
          location: assetId.path,
        ),
      );
      return null;
    }
    return _ScreenNode(
      screen: prior.screen,
      transitions: [...prior.transitions, thisTransition],
    );
  }
  issues.add(
    Issue(
      code: IssueCode.buildMethodTooComplex,
      message: 'Screen states must start with screen(ref).',
      location: assetId.path,
    ),
  );
  return null;
}

/// Lowers the peeled `.capture()`/`.write()` calls of one transition into wire
/// state writes. Each target key must be declared in `flow(flowState: {...})`
/// and its type must match; `.capture()` requires a scalar event. Every failure
/// is a loud build error, never a silent drop.
Map<String, FlowStateWrite>? _lowerTransitionStateWrites(
  List<MethodInvocation> writeCalls,
  FlowDataType? eventScalarType,
  Map<String, FlowStateDeclaration> flowState,
  List<Issue> issues,
  AssetId assetId,
) {
  final result = <String, FlowStateWrite>{};
  for (final call in writeCalls) {
    final method = call.methodName.name;
    final key = _stringExpression(call.argumentList.arguments.firstOrNull);
    if (key == null) {
      issues.add(
        Issue(
          code: IssueCode.buildMethodTooComplex,
          message: '$method(...) requires a string flow-state key literal.',
          location: assetId.path,
        ),
      );
      return null;
    }
    if (result.containsKey(key)) {
      issues.add(
        Issue(
          code: IssueCode.buildMethodTooComplex,
          message: "duplicate state write '$key' on a single transition.",
          location: assetId.path,
        ),
      );
      return null;
    }
    final declaration = flowState[key];
    if (declaration == null) {
      issues.add(
        Issue(
          code: IssueCode.buildMethodTooComplex,
          message: "$method('$key') targets flow-state key '$key', which is "
              'not declared in flow(flowState: {...}).',
          location: assetId.path,
        ),
      );
      return null;
    }
    final FlowStateWrite write;
    if (method == 'capture') {
      if (eventScalarType == null) {
        issues.add(
          Issue(
            code: IssueCode.buildMethodTooComplex,
            message: "capture('$key') requires a scalar "
                'OnboardingEvent<String|bool|int>.',
            location: assetId.path,
          ),
        );
        return null;
      }
      write = FlowStateWrite(
        type: eventScalarType,
        // A scalar event carries its value under the reserved `value` key
        // (see the screen-event lowering), decoupled from the flow-state key.
        value: const EventFlowValueSource(key: kCapturedEventValueKey),
      );
    } else {
      final literal = _literalWriteValue(
        call.argumentList.arguments.elementAtOrNull(1),
      );
      if (literal == null) {
        issues.add(
          Issue(
            code: IssueCode.buildMethodTooComplex,
            message: "write('$key', ...) requires a String, bool, or int "
                'literal value.',
            location: assetId.path,
          ),
        );
        return null;
      }
      write = FlowStateWrite(
        type: literal.type,
        value: LiteralFlowValueSource(type: literal.type, value: literal.value),
      );
    }
    if (write.type != declaration.type) {
      issues.add(
        Issue(
          code: IssueCode.buildMethodTooComplex,
          message: "$method('$key') produces ${write.type.wireName} but "
              "flowState declares '$key' as ${declaration.type.wireName}.",
          location: assetId.path,
        ),
      );
      return null;
    }
    result[key] = write;
  }
  return result;
}

// Lowers a literal-constant expression to a typed value. The accepted forms are
// bounded to literal SPELLINGS — bare literals, parenthesized literals, and
// adjacent-string literals — matching what the runtime sugar/`write()` see as a
// plain value. A computed const expression (`'a' + 'b'`, `1 + 1`, a const
// reference) is intentionally NOT folded (that would need a const evaluator);
// it stays a loud build error, so the build-time and runtime legs agree on the
// same bounded literal contract.
({FlowDataType type, Object value})? _literalWriteValue(
  Expression? expression,
) {
  if (expression is ParenthesizedExpression) {
    return _literalWriteValue(expression.expression);
  }
  final stringValue = _stringExpression(expression);
  if (stringValue != null) {
    return (type: FlowDataType.string, value: stringValue);
  }
  if (expression is BooleanLiteral) {
    return (type: FlowDataType.bool, value: expression.value);
  }
  if (expression is IntegerLiteral && expression.value != null) {
    return (type: FlowDataType.int, value: expression.value!);
  }
  if (expression is PrefixExpression && expression.operator.lexeme == '-') {
    final operand = _literalWriteValue(expression.operand);
    if (operand != null && operand.type == FlowDataType.int) {
      return (type: FlowDataType.int, value: -(operand.value as int));
    }
  }
  return null;
}

FlowDataType? _eventScalarFlowDataType(Expression? expression) {
  final field = _onboardingEventFieldFor(expression);
  if (field == null) return null;
  final type = field.type;
  if (type is! InterfaceType || type.typeArguments.length != 1) return null;
  switch (type.typeArguments.single.getDisplayString()) {
    case 'String':
      return FlowDataType.string;
    case 'bool':
      return FlowDataType.bool;
    case 'int':
      return FlowDataType.int;
  }
  return null;
}

bool _isGraphNodeExpression(Expression expression) {
  return expression is MethodInvocation &&
      (expression.methodName.name == 'decision' ||
          expression.methodName.name == 'subFlow');
}

Future<_GraphNode?> _parseGraphNode(
  BuildStep buildStep,
  AssetId flowAssetId,
  _FlowSource flow,
  Expression expression,
  _ScreenDescriptorResolver descriptors,
  Map<String, String> endLocals,
  Map<String, String> nodeLocals,
  List<Issue> issues,
  Map<NormalizedFlowIdentity, List<int>> childFlowDocuments,
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
        flow,
        expression,
        descriptors,
        endLocals,
        nodeLocals,
        issues,
        childFlowDocuments,
      ),
    _ => null,
  };
}

_GraphNode? _parseDecisionNode(
  MethodInvocation invocation,
  _ScreenDescriptorResolver descriptors,
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
  _FlowSource flow,
  MethodInvocation invocation,
  _ScreenDescriptorResolver descriptors,
  Map<String, String> endLocals,
  Map<String, String> nodeLocals,
  List<Issue> issues,
  Map<NormalizedFlowIdentity, List<int>> childFlowDocuments,
) async {
  final id = _flowNodeId(
    invocation.argumentList.arguments.firstOrNull,
    nodeLocals,
  );
  final childRef = _flowRefForExpression(
    _namedArg(invocation, 'flow'),
    issues,
    flowAssetId,
    legacySurfaceFallback: flow.isCanonical
        ? null
        : flow.surface ?? _flowSurfaceForAsset(flowAssetId),
  );
  final childArtifact = childRef == null
      ? null
      : await _childFlowArtifact(
          buildStep,
          flowAssetId,
          childRef,
          issues,
          childFlowDocuments,
          parentSurface: flow.surface ?? _flowSurfaceForAsset(flowAssetId),
          canonicalParent: flow.isCanonical,
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
  _ScreenDescriptorResolver descriptors,
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
  _ScreenDescriptorResolver descriptors,
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
  _ScreenDescriptorResolver descriptors,
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
  _ScreenDescriptorResolver descriptors,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression is MethodInvocation &&
      expression.methodName.name == 'paywallScreen') {
    final id = _paywallIdForRef(expression, issues, assetId);
    return id == null
        ? null
        : descriptors.resolvePaywall(id, issues: issues, assetId: assetId);
  }

  return descriptors.resolve(expression, issues: issues, assetId: assetId);
}

String? _paywallIdForRef(
  MethodInvocation expression,
  List<Issue> issues,
  AssetId assetId,
) {
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
  return id;
}

String? _targetId(
  Expression? expression,
  _ScreenDescriptorResolver descriptors,
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

/// Resolves a class-shaped flow's descriptor expression to the authored screen
/// declaration that owns it.
///
/// Canonical aggregate compilation may run before a descriptor part exists on
/// disk. In that case the descriptor class itself is unresolved, but its import
/// prefix remains analyzer-resolved. We use that prefix (or the resolved
/// descriptor class when it is available) to select the authored declaration;
/// the descriptor spelling alone is never a lookup key.
final class _ScreenDescriptorResolver {
  _ScreenDescriptorResolver({
    required this.flowLibrary,
    required this.flowSurface,
    required this.legacyDescriptors,
    required Iterable<ResolvedClassFlowScreen> resolvedScreens,
  }) : _resolvedScreens = List.unmodifiable(resolvedScreens);

  final LibraryElement flowLibrary;
  final Surface flowSurface;
  final Map<String, _ScreenDescriptor> legacyDescriptors;
  final List<ResolvedClassFlowScreen> _resolvedScreens;

  _ScreenDescriptor? resolve(
    Expression? expression, {
    required List<Issue> issues,
    required AssetId assetId,
  }) {
    final reference = _descriptorReference(expression);
    if (reference == null) {
      issues.add(
        Issue(
          code: IssueCode.buildMethodTooComplex,
          message: 'Expected a generated screen descriptor .ref.',
          location: assetId.path,
        ),
      );
      return null;
    }

    if (_resolvedScreens.isEmpty) {
      final descriptor = legacyDescriptors[reference.name];
      if (descriptor == null) {
        issues.add(
          Issue(
            code: IssueCode.missingScreenDescriptor,
            message: 'Missing imported generated screen descriptor '
                '${reference.name}.',
            location: assetId.path,
          ),
        );
      }
      return descriptor;
    }

    final candidates = _resolvedScreens.where((screen) {
      if (screen.canonicalPaywallId != null) return false;
      if (screen.descriptorName != reference.name) return false;
      final descriptorElement = reference.descriptorElement;
      if (descriptorElement != null) {
        return screen.declaration.library.identifier ==
            descriptorElement.library.identifier;
      }
      return _isImportedScreen(screen, reference.importPrefix);
    }).toList(growable: false);
    if (candidates.length != 1) {
      final identities = candidates
          .map((candidate) => candidate.declarationIdentity)
          .toList()
        ..sort();
      issues.add(
        Issue(
          code: IssueCode.analyzerResolutionFailed,
          message: 'Generated screen descriptor ${reference.name} must '
              'resolve through one analyzer-authored library declaration; '
              'found ${candidates.length}'
              '${identities.isEmpty ? '' : ' (${identities.join(', ')})'}.',
          location: assetId.path,
        ),
      );
      return null;
    }

    final screen = candidates.single;
    if (screen.surface != null && screen.surface != flowSurface) {
      issues.add(
        Issue(
          code: IssueCode.annotationEvaluationFailed,
          message: 'Screen ${screen.declarationIdentity} is authored for '
              '${screen.surface!.wireName}, but this flow is '
              '${flowSurface.wireName}.',
          location: assetId.path,
        ),
      );
      return null;
    }
    return _ScreenDescriptor(
      name: reference.name,
      id: screen.id,
      artifactPath: screen.artifactPath,
      version: screen.version,
      minClient: screen.minClient,
      declarationIdentity: screen.declarationIdentity,
    );
  }

  _ScreenDescriptor? resolvePaywall(
    String authoredId, {
    required List<Issue> issues,
    required AssetId assetId,
  }) {
    final screenId = 'paywall_$authoredId';
    if (_resolvedScreens.isEmpty) {
      return _ScreenDescriptor(
        name: 'paywallScreen($authoredId)',
        id: screenId,
        artifactPath: '$screenId.rfw',
        version: 1,
        minClient: kBaselineCatalogVersion,
      );
    }

    final candidates = _resolvedScreens
        .where((screen) => screen.canonicalPaywallId == authoredId)
        .toList(growable: false);
    if (candidates.length != 1) {
      final identities = candidates
          .map((candidate) => candidate.declarationIdentity)
          .toList()
        ..sort();
      issues.add(
        Issue(
          code: IssueCode.analyzerResolutionFailed,
          message: 'paywallScreen($authoredId) must resolve to exactly one '
              'roster-owned canonical paywall declaration; found '
              '${candidates.length}'
              '${identities.isEmpty ? '' : ' (${identities.join(', ')})'}.',
          location: assetId.path,
        ),
      );
      return null;
    }

    final screen = candidates.single;
    return _ScreenDescriptor(
      name: 'paywallScreen($authoredId)',
      id: screen.id,
      artifactPath: screen.artifactPath,
      version: screen.version,
      minClient: screen.minClient,
      declarationIdentity: screen.declarationIdentity,
    );
  }

  bool _isImportedScreen(
    ResolvedClassFlowScreen screen,
    PrefixElement? prefix,
  ) {
    if (prefix == null &&
        screen.declaration.library.identifier == flowLibrary.identifier) {
      return true;
    }
    final screenName = screen.declaration.name;
    if (screenName == null) return false;
    for (final import in flowLibrary.firstFragment.libraryImports) {
      final imported = import.importedLibrary;
      if (imported?.identifier != screen.declaration.library.identifier) {
        continue;
      }
      if (prefix != null) {
        if (import.prefix?.element == prefix) return true;
        continue;
      }
      if (import.prefix == null &&
          import.namespace.get2(screenName) == screen.declaration) {
        return true;
      }
    }
    return false;
  }
}

final class _DescriptorReference {
  const _DescriptorReference({
    required this.name,
    required this.descriptorElement,
    required this.importPrefix,
  });

  final String name;
  final ClassElement? descriptorElement;
  final PrefixElement? importPrefix;
}

_DescriptorReference? _descriptorReference(Expression? expression) {
  if (expression is PrefixedIdentifier && expression.identifier.name == 'ref') {
    return _descriptorReferenceForTarget(expression.prefix);
  }
  if (expression is PropertyAccess && expression.propertyName.name == 'ref') {
    final target = expression.target;
    return target == null ? null : _descriptorReferenceForTarget(target);
  }
  return null;
}

_DescriptorReference? _descriptorReferenceForTarget(Expression target) {
  if (target is SimpleIdentifier) {
    return _descriptorReferenceFromName(
      target.name,
      descriptorElement: _classElement(target.element),
    );
  }
  if (target is PrefixedIdentifier) {
    return _descriptorReferenceFromName(
      target.identifier.name,
      descriptorElement: _classElement(target.identifier.element),
      importPrefix: _prefixElement(target.prefix.element),
    );
  }
  if (target is PropertyAccess) {
    return _descriptorReferenceFromName(
      target.propertyName.name,
      descriptorElement: _classElement(target.propertyName.element),
    );
  }
  return null;
}

_DescriptorReference? _descriptorReferenceFromName(
  String name, {
  ClassElement? descriptorElement,
  PrefixElement? importPrefix,
}) {
  if (!name.endsWith('Descriptor')) return null;
  return _DescriptorReference(
    name: name,
    descriptorElement: descriptorElement,
    importPrefix: importPrefix,
  );
}

ClassElement? _classElement(Element? element) =>
    element is ClassElement ? element : null;

PrefixElement? _prefixElement(Element? element) =>
    element is PrefixElement ? element : null;

String? _eventId(
  Expression? expression,
  List<Issue> issues,
  AssetId assetId,
) {
  final eventField = _onboardingEventFieldFor(expression);
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

FieldElement? _onboardingEventFieldFor(Expression? expression) {
  return _staticConstOnboardingEventField(
    _referencedVariableElement(expression),
  );
}

FieldElement? _staticConstOnboardingEventField(Element? element) {
  if (element is! FieldElement || !element.isStatic || !element.isConst) {
    return null;
  }
  final type = element.type;
  if (type is! InterfaceType ||
      (type.element.name != 'SurfaceEvent' &&
          type.element.name != 'OnboardingEvent') ||
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
  String flowClassName,
) {
  final entries = _stringKeyedMap(
    expression,
    issues,
    assetId,
    'flowState must be a literal map with string keys.',
  );
  if (entries == null) return null;
  final seedClassName = '${_flowBaseName(flowClassName)}Seed';
  final result = <String, FlowStateDeclaration>{};
  for (final entry in entries.entries) {
    final declaration = _flowStateDeclaration(
      entry.value,
      issues,
      assetId,
    );
    if (declaration == null) return null;
    // A host-seedable key is interpolated into the generated seed builder as a
    // field name, a constructor parameter, and a `toFlowState` map key. The
    // wire identifier rule is broader than a Dart identifier (it admits hyphens
    // and reserved/Object/method names), and a key equal to the generated seed
    // class name would clash with the class itself, so reject an
    // unrepresentable seed key with a clear diagnostic instead of broken Dart.
    if (declaration.hostSeedable &&
        !_isSeedKeyDartSafe(entry.key, seedClassName)) {
      issues.add(
        Issue(
          code: IssueCode.buildMethodTooComplex,
          message: "unsupported host-seedable key '${entry.key}': a "
              'host-seedable flowState key must be a non-reserved Dart '
              "identifier that is not an Object member name, 'toFlowState', or "
              "the generated seed class name '$seedClassName'.",
          location: assetId.path,
        ),
      );
      return null;
    }
    result[entry.key] = declaration;
  }
  return result;
}

bool _isSeedKeyDartSafe(String key, String seedClassName) =>
    _isSafeDartIdentifier(key) &&
    !_objectInstanceMemberNames.contains(key) &&
    key != 'toFlowState' &&
    key != seedClassName;

/// The base name a flow's generated symbols derive from (the class name with a
/// trailing `Flow` stripped).
String _flowBaseName(String className) => className.endsWith('Flow')
    ? className.substring(0, className.length - 'Flow'.length)
    : className;

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
  final hostSeedableExpr = _namedConstructorArg(creation, 'hostSeedable');
  final hostSeedable = switch (hostSeedableExpr) {
    null => false,
    BooleanLiteral(:final value) => value,
    _ => null,
  };
  if (hostSeedable == null) {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      'hostSeedable must be a bool literal.',
    );
    return null;
  }
  return FlowStateDeclaration(
    type: type,
    classification: classification,
    defaultValue: defaultValue,
    hostSeedable: hostSeedable,
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

/// The predicate-sugar operators keyed by method name, derived from the shared
/// [FlowPredicateOperator] enum so the parser cannot drift from the authoring
/// API on the operator set.
final Map<String, FlowPredicateOperator> _sugarOperatorsByName = {
  for (final operator in FlowPredicateOperator.values)
    operator.methodName: operator,
};

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
  // Predicate sugar: `allOf([...])` and `state(K).<op>(...)`. The `allOf`, the
  // operator method, and the `state(...)` receiver are each resolved to the
  // Restage SDK library so a same-named customer construct is not silently
  // reinterpreted as sugar.
  if (expression is MethodInvocation) {
    if (expression.methodName.name == 'allOf' &&
        _resolvesToRestageSdk(expression)) {
      return _allOfPredicate(expression, issues, assetId);
    }
    final operator = _sugarOperatorsByName[expression.methodName.name];
    if (operator != null &&
        _resolvesToRestageSdk(expression) &&
        _isStateInvocation(expression.target)) {
      return _statePredicateChain(expression, operator, issues, assetId);
    }
  }
  final creation = _instanceCreation(
    expression,
    'FlowBranchPredicate',
    issues,
    assetId,
    'branch predicates must be a FlowBranchPredicate(...) constructor, a '
        'state(...).<op>(...) predicate, or allOf([...]).',
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

bool _isStateInvocation(Expression? expression) {
  return expression is MethodInvocation &&
      expression.methodName.name == 'state' &&
      _resolvesToRestageSdk(expression);
}

/// Whether [invocation]'s invoked function/method resolves to the Restage SDK
/// library. A name-only match would let a same-named non-Restage `state(...)` /
/// `allOf(...)` / operator (a customer DSL) be silently reinterpreted as Restage
/// sugar and lowered to our wire while the runtime runs the other function;
/// resolving the element to the SDK origin closes that drift. Falls back to
/// accepting an unresolved element (a test AST without a resolved SDK element)
/// by name so such fixtures still parse.
bool _resolvesToRestageSdk(MethodInvocation invocation) {
  final element = invocation.methodName.element;
  if (element == null) return true;
  final library = element.library;
  if (library == null) return true;
  return libraryUriMatchesOrigin(library.identifier, _kSdkLibraryOrigin);
}

/// Lowers a `state(K)` invocation into a [StateFlowValueSource], failing loud
/// on a non-literal key. Shared by the predicate-chain receiver, the sugar
/// right-hand side, and the bare value-source position.
StateFlowValueSource? _stateSugarSource(
  MethodInvocation invocation,
  List<Issue> issues,
  AssetId assetId,
) {
  final key = _stringExpression(invocation.argumentList.arguments.firstOrNull);
  if (key == null) {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      'state(...) requires a string key literal.',
    );
    return null;
  }
  return StateFlowValueSource(key: key);
}

/// Lowers `allOf([...])` into one merged [FlowBranchPredicate]. Each element is
/// itself a single-field predicate; two conditions on the same field cannot be
/// represented (one condition per field) and fail the build loud, via the
/// shared [mergeFlowBranchPredicates] merge rule.
FlowBranchPredicate? _allOfPredicate(
  MethodInvocation invocation,
  List<Issue> issues,
  AssetId assetId,
) {
  final argument = invocation.argumentList.arguments.firstOrNull;
  if (argument is! ListLiteral) {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      'allOf(...) requires a literal list of predicates.',
    );
    return null;
  }
  final parsed = <FlowBranchPredicate>[];
  for (final element in argument.elements) {
    if (element is! Expression) {
      _unsupportedGraphDeclaration(
        issues,
        assetId,
        'collection control and spreads are not supported in allOf(...).',
      );
      return null;
    }
    final predicate = _flowBranchPredicate(element, issues, assetId);
    if (predicate == null) return null;
    parsed.add(predicate);
  }
  final duplicate = firstDuplicatePredicateField(parsed);
  if (duplicate != null) {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      'allOf cannot merge two conditions on field "$duplicate"; the predicate '
      'wire allows one condition per field.',
    );
    return null;
  }
  return FlowBranchPredicate(
    fields: {for (final predicate in parsed) ...predicate.fields},
  );
}

/// Lowers a `state(K).<op>(...)` sugar chain into a single-field
/// [FlowBranchPredicate], using the shared [buildFlowPredicateCondition] so the
/// wire matches the authoring API exactly.
FlowBranchPredicate? _statePredicateChain(
  MethodInvocation invocation,
  FlowPredicateOperator operator,
  List<Issue> issues,
  AssetId assetId,
) {
  final receiver = invocation.target! as MethodInvocation;
  final source = _stateSugarSource(receiver, issues, assetId);
  if (source == null) return null;
  final condition = _sugarCondition(operator, invocation, issues, assetId);
  if (condition == null) return null;
  return FlowBranchPredicate(fields: {source.key: condition});
}

FlowPredicateCondition? _sugarCondition(
  FlowPredicateOperator operator,
  MethodInvocation invocation,
  List<Issue> issues,
  AssetId assetId,
) {
  final arguments = invocation.argumentList.arguments;
  switch (operator.arity) {
    case FlowPredicateValueArity.none:
      if (arguments.isNotEmpty) {
        _unsupportedGraphDeclaration(
          issues,
          assetId,
          '${operator.methodName}() takes no arguments.',
        );
        return null;
      }
      return buildFlowPredicateCondition(operator);
    case FlowPredicateValueArity.single:
      final argument = arguments.firstOrNull;
      if (argument == null) {
        _unsupportedGraphDeclaration(
          issues,
          assetId,
          '${operator.methodName}(...) requires a value.',
        );
        return null;
      }
      final value = _sugarValueSource(argument, operator, issues, assetId);
      if (value == null) return null;
      return buildFlowPredicateCondition(operator, value: value);
    case FlowPredicateValueArity.list:
      final argument = arguments.firstOrNull;
      if (argument is! ListLiteral) {
        _unsupportedGraphDeclaration(
          issues,
          assetId,
          '${operator.methodName}(...) requires a literal list.',
        );
        return null;
      }
      final values = <FlowValueSource>[];
      for (final element in argument.elements) {
        if (element is! Expression) {
          _unsupportedGraphDeclaration(
            issues,
            assetId,
            'collection control and spreads are not supported in '
            '${operator.methodName}(...).',
          );
          return null;
        }
        final value = _sugarValueSource(element, operator, issues, assetId);
        if (value == null) return null;
        values.add(value);
      }
      return buildFlowPredicateCondition(operator, values: values);
  }
}

/// Coerces a sugar right-hand side AST into a [FlowValueSource]: a `state(K)`
/// reference passes through; a scalar literal is auto-wrapped with its inferred
/// wire type. A non-scalar literal — or a non-int literal to an int-only
/// [operator] — fails the build loud.
FlowValueSource? _sugarValueSource(
  Expression expression,
  FlowPredicateOperator operator,
  List<Issue> issues,
  AssetId assetId,
) {
  if (expression is MethodInvocation &&
      expression.methodName.name == 'state' &&
      _resolvesToRestageSdk(expression)) {
    return _stateSugarSource(expression, issues, assetId);
  }
  final literal = _literalWriteValue(expression);
  if (literal == null) {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      '${operator.methodName}(...) requires a bool, int, or String literal '
      'or a state(...) reference.',
    );
    return null;
  }
  if (operator.intOnly && literal.type != FlowDataType.int) {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      '${operator.methodName}(...) compares integers; pass an int literal '
      'or a state(...) reference.',
    );
    return null;
  }
  return LiteralFlowValueSource(type: literal.type, value: literal.value);
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
  if (expression is MethodInvocation &&
      expression.methodName.name == 'state' &&
      _resolvesToRestageSdk(expression)) {
    return _stateSugarSource(expression, issues, assetId);
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
  AssetId assetId, {
  Surface? legacySurfaceFallback,
}) {
  final element = _referencedVariableElement(expression);
  if (element == null) {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      'subFlow flow: must reference a const OnboardingFlowRef.',
    );
    return null;
  }
  final type = element.type;
  if (type is! InterfaceType ||
      (type.element.name != 'SurfaceFlowRef' &&
          type.element.name != 'OnboardingFlowRef') ||
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
  final surfaceName =
      value?.getField('surface')?.getField('wireName')?.toStringValue();
  final resolvedSurface = Surface.values
      .where((candidate) => candidate.wireName == surfaceName)
      .firstOrNull;
  final surface = resolvedSurface ?? legacySurfaceFallback;
  if (id == null || version == null || minClient == null || surface == null) {
    _unsupportedGraphDeclaration(
      issues,
      assetId,
      'subFlow flow: SurfaceFlowRef could not be const-evaluated with an '
      'explicit Surface.',
    );
    return null;
  }
  return _SubFlowRef(
    id: id,
    version: version,
    minClient: minClient,
    surface: surface,
  );
}

Future<_ChildFlowArtifact?> _childFlowArtifact(
  BuildStep buildStep,
  AssetId flowAssetId,
  _SubFlowRef ref,
  List<Issue> issues,
  Map<NormalizedFlowIdentity, List<int>> childFlowDocuments, {
  required Surface parentSurface,
  required bool canonicalParent,
}) async {
  if (ref.surface != parentSurface) {
    _unsupportedGraphDeclaration(
      issues,
      flowAssetId,
      'subflow child ${ref.surface.wireName}/${ref.id} cannot be included '
      'in a ${parentSurface.wireName} flow.',
    );
    return null;
  }

  List<int>? bytes;
  late final String artifactDescription;
  if (canonicalParent) {
    bytes = childFlowDocuments[ref.identity];
    artifactDescription =
        'aggregate child flow ${ref.surface.wireName}/${ref.id}';
  } else {
    final asset = AssetId(
      flowAssetId.package,
      '${_flowOutputDir(_surfaceSegmentOf(flowAssetId))}/'
      '${ref.id}.flow.json',
    );
    artifactDescription = 'child flow artifact ${asset.path}';
    if (await buildStep.canRead(asset)) {
      bytes = await buildStep.readAsBytes(asset);
    } else {
      bytes = await _compileLegacyChildFlowBytes(
        buildStep,
        parentAssetId: flowAssetId,
        ref: ref,
        issues: issues,
      );
    }
  }
  if (bytes == null) {
    _unsupportedGraphDeclaration(
      issues,
      flowAssetId,
      'missing $artifactDescription.',
    );
    return null;
  }
  late final FlowDocument document;
  try {
    document = FlowDocumentCodec.decodeJson(utf8.decode(bytes));
  } on Object catch (e) {
    _unsupportedGraphDeclaration(
      issues,
      flowAssetId,
      'could not decode $artifactDescription: $e.',
    );
    return null;
  }
  if (document.flow != ref.id ||
      document.version != ref.version ||
      document.minClient != ref.minClient) {
    _unsupportedGraphDeclaration(
      issues,
      flowAssetId,
      '$artifactDescription does not match '
      '${ref.id}@${ref.version}/minClient ${ref.minClient}.',
    );
    return null;
  }
  return _ChildFlowArtifact(
    schemaVersion: document.schemaVersion,
    contentHash: FlowContentHash.compute(bytes),
  );
}

Future<List<int>?> _compileLegacyChildFlowBytes(
  BuildStep buildStep, {
  required AssetId parentAssetId,
  required _SubFlowRef ref,
  required List<Issue> issues,
}) async {
  final childAsset = AssetId(
    parentAssetId.package,
    '${_flowSourceDir(_surfaceSegmentOf(parentAssetId))}/${ref.id}.dart',
  );
  if (!await buildStep.canRead(childAsset) ||
      !await buildStep.resolver.isLibrary(childAsset)) {
    return null;
  }
  final library = await buildStep.resolver.libraryFor(
    childAsset,
    allowSyntaxErrors: true,
  );
  final flow = _findFlow(library, childAsset);
  if (flow == null || flow.invalidAnnotation || flow.id != ref.id) return null;
  final localIssues = <Issue>[];
  final method = await _resolvedBuildFlow(
    library,
    flow,
    localIssues,
    childAsset,
  );
  final descriptors = await _loadImportedScreenDescriptors(
    buildStep,
    childAsset,
    localIssues,
  );
  if (method == null || localIssues.isNotEmpty) {
    issues.addAll(localIssues);
    return null;
  }
  final lowered = await _lowerFlow(
    buildStep,
    flow,
    method,
    _ScreenDescriptorResolver(
      flowLibrary: library,
      flowSurface: _flowSurfaceForAsset(childAsset),
      legacyDescriptors: descriptors,
      resolvedScreens: const [],
    ),
    localIssues,
    childAsset,
    const {},
    const {},
  );
  if (lowered == null || localIssues.isNotEmpty) {
    issues.addAll(localIssues);
    return null;
  }
  return FlowDocumentCodec.encodeCanonicalJson(lowered.document);
}

Surface _flowSurfaceForAsset(AssetId assetId) =>
    switch (_surfaceSegmentOf(assetId)) {
      'onboarding' => Surface.onboarding,
      'message' => Surface.message,
      'survey' => Surface.survey,
      'general' => Surface.general,
      final other => throw StateError(
          'Expected a flow-surface source asset, got ${assetId.path} '
          '(surface "$other").',
        ),
    };

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

/// Typed descriptors decode the runtime-filtered terminal payload, so their
/// generated field names must be valid Dart identifiers. Every declared field
/// must also be provably available with its declared scalar type whenever the
/// runtime can reach terminal decoding.
void _validateTypedTerminalResultShape({
  required FlowDeliveryMode delivery,
  required String initialStateId,
  required Map<String, FlowState> states,
  required Map<String, FlowStateDeclaration> flowState,
  required FlowOutboundDeclarations outbound,
  required List<Issue> issues,
  required AssetId assetId,
  required String flowClassName,
}) {
  if (delivery != FlowDeliveryMode.typed) return;
  final terminals = states.values.whereType<EndFlowState>().toList();
  // The caller separately rejects more than one declared terminal. Avoid
  // adding a derivative shape error to that primary structural failure.
  if (terminals.length > 1) return;

  final terminalResult = terminals.firstOrNull?.result;
  final usesGraphRuntime = _usesGraphRuntimeForStates(states.values);
  for (final entry in outbound.terminalResult.fields.entries) {
    final outputKey = entry.key;
    final field = entry.value;
    if (!_isSafeDartIdentifier(outputKey) ||
        _objectInstanceMemberNames.contains(outputKey)) {
      issues.add(
        Issue(
          code: IssueCode.buildMethodTooComplex,
          message: "unsupported typed terminal output key '$outputKey': "
              'outbound.terminalResult field names must be non-reserved '
              'Dart identifiers.',
          location: '${assetId.path}#$flowClassName.buildFlow',
        ),
      );
    }

    final ref = field.ref;
    switch (ref) {
      case EventFlowOutboundRef(:final key, :final path):
        if (path.isNotEmpty) {
          issues.add(
            Issue(
              code: IssueCode.buildMethodTooComplex,
              message: "typed terminal output key '$outputKey' cannot use "
                  'EventFlowOutboundRef.path: end(..., result:) only supports '
                  'scalar top-level result values.',
              location: '${assetId.path}#$flowClassName.buildFlow',
            ),
          );
          continue;
        }
        // A holding flow never reaches terminal decoding. Its outbound
        // declaration is inert metadata, not a claim about an invented empty
        // terminal result.
        if (terminalResult == null) continue;
        _validateTerminalResultFallback(
          outputKey: outputKey,
          sourceKey: key,
          expectedType: field.type,
          terminalResult: terminalResult,
          issues: issues,
          assetId: assetId,
          flowClassName: flowClassName,
        );
        continue;
      case StateFlowOutboundRef(:final key, :final path):
        if (path.isNotEmpty) {
          issues.add(
            Issue(
              code: IssueCode.buildMethodTooComplex,
              message: "typed terminal output key '$outputKey' cannot use "
                  'StateFlowOutboundRef.path: flow state declarations are '
                  'scalar.',
              location: '${assetId.path}#$flowClassName.buildFlow',
            ),
          );
          continue;
        }
        if (terminalResult == null) continue;

        // FlowDocumentValidation owns missing-declaration and type-mismatch
        // diagnostics. Availability proof only applies once that contract is
        // coherent.
        final declaration = flowState[key];
        if (declaration == null || declaration.type != field.type) continue;
        if (declaration.defaultValue != null) continue;

        if (!usesGraphRuntime) {
          // The runtime's legacy state-ref fallback is enabled only for the
          // non-graph lane, so the terminal literal must make the generated
          // non-null field safe when a host seed is absent.
          _validateTerminalResultFallback(
            outputKey: outputKey,
            sourceKey: key,
            expectedType: field.type,
            terminalResult: terminalResult,
            issues: issues,
            assetId: assetId,
            flowClassName: flowClassName,
          );
          continue;
        }

        if (!_isStateAssignedOnEveryCompletionPath(
          stateKey: key,
          initialStateId: initialStateId,
          states: states,
        )) {
          issues.add(
            Issue(
              code: IssueCode.buildMethodTooComplex,
              message: "typed terminal output key '$outputKey' reads state "
                  "'$key', but that scalar is not assigned on every "
                  'completion path. Add a non-null declaration default or '
                  'write it before every reachable terminal.',
              location: '${assetId.path}#$flowClassName.buildFlow',
            ),
          );
        }
    }
  }
}

void _validateTerminalResultFallback({
  required String outputKey,
  required String sourceKey,
  required FlowDataType expectedType,
  required Map<String, Object?> terminalResult,
  required List<Issue> issues,
  required AssetId assetId,
  required String flowClassName,
}) {
  final value = terminalResult[sourceKey];
  final actualType = _resultLiteralFlowDataType(value);
  if (terminalResult.containsKey(sourceKey) && actualType == expectedType) {
    return;
  }
  issues.add(
    Issue(
      code: IssueCode.buildMethodTooComplex,
      message: "typed terminal output key '$outputKey' must read a "
          '${expectedType.wireName} end result field "$sourceKey"; '
          'found ${actualType?.wireName ?? 'missing'}.',
      location: '${assetId.path}#$flowClassName.buildFlow',
    ),
  );
}

bool _usesGraphRuntimeForStates(Iterable<FlowState> states) {
  for (final state in states) {
    switch (state) {
      case DecisionFlowState() || SubFlowState():
        return true;
      case ScreenFlowState(:final on):
        for (final transition in on.values) {
          switch (transition) {
            case GotoFlowTransition(:final stateWrites) ||
                  ActionFlowTransition(:final stateWrites):
              if (stateWrites.isNotEmpty) return true;
          }
        }
        continue;
      case EndFlowState() || UnsupportedFlowState():
        continue;
    }
  }
  return false;
}

bool _isStateAssignedOnEveryCompletionPath({
  required String stateKey,
  required String initialStateId,
  required Map<String, FlowState> states,
}) {
  final pending = <({String stateId, bool assigned})>[
    (stateId: initialStateId, assigned: false),
  ];
  final visited = <({String stateId, bool assigned})>{};

  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    if (!visited.add(current)) continue;
    final state = states[current.stateId];
    if (state == null) return false;
    if (state is EndFlowState) {
      if (!current.assigned) return false;
      continue;
    }

    for (final edge in _outgoingStateEdges(state)) {
      final next = (
        stateId: edge.target,
        assigned: current.assigned || edge.stateWrites.containsKey(stateKey),
      );
      pending.add(next);
    }
  }
  return true;
}

Iterable<({String target, Map<String, FlowStateWrite> stateWrites})>
    _outgoingStateEdges(FlowState state) sync* {
  switch (state) {
    case ScreenFlowState(:final on):
      for (final transition in on.values) {
        switch (transition) {
          case GotoFlowTransition(:final target, :final stateWrites) ||
                ActionFlowTransition(:final target, :final stateWrites):
            yield (target: target, stateWrites: stateWrites);
        }
      }
      return;
    case DecisionFlowState(:final branches, :final defaultBranch):
      for (final branch in branches) {
        yield (target: branch.target, stateWrites: branch.stateWrites);
      }
      yield (
        target: defaultBranch.target,
        stateWrites: defaultBranch.stateWrites,
      );
      return;
    case SubFlowState(
        :final onComplete,
        :final defaultBranch,
        :final subFlowUnavailable,
      ):
      for (final branch in onComplete) {
        yield (target: branch.target, stateWrites: branch.stateWrites);
      }
      yield (
        target: defaultBranch.target,
        stateWrites: defaultBranch.stateWrites,
      );
      if (subFlowUnavailable != null) {
        yield (
          target: subFlowUnavailable.target,
          stateWrites: subFlowUnavailable.stateWrites,
        );
      }
      return;
    case EndFlowState() || UnsupportedFlowState():
      return;
  }
}

FlowDataType? _resultLiteralFlowDataType(Object? value) {
  if (value is bool) return FlowDataType.bool;
  if (value is int) return FlowDataType.int;
  if (value is String) return FlowDataType.string;
  return null;
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
  Surface surface,
) {
  final baseName = _flowBaseName(flow.className);
  final descriptorClass = '${flow.className}Descriptor';
  final actionsClass = _actionsClassName(flow.className);
  final actionsInterface =
      flow.actions.isEmpty ? '' : ' implements FlowActionRegistry';
  final seedClass =
      _emitSeedClass('${baseName}Seed', lowered.document.flowState);
  if (flow.delivery == FlowDeliveryMode.general) {
    final signalNames = lowered.document.outbound.customEvents.keys.toList()
      ..sort();
    final signalSet = signalNames.isEmpty
        ? 'const <String>{}'
        : 'const {${signalNames.map(_dartStringLiteral).join(', ')}}';
    final generalActionsBody = flow.actions.isEmpty
        ? '  const $actionsClass();\n\n'
            '  @override\n'
            '  Map<String, FlowActionBinding<dynamic, dynamic>> get '
            'flowActionBindings => const {};\n'
        : '${_emitActionsConstructor(actionsClass, flow.actions)}'
            '${_emitActionFields(
            flow.actions,
            flow.minClient,
            lowered.actionContracts,
          )}';
    return '''
part of '$stem.dart';

abstract final class $descriptorClass {
  const $descriptorClass._();

  static const SurfaceFlowRef<Map<String, Object?>> ref =
      SurfaceFlowRef<Map<String, Object?>>(
    id: '${flow.id}',
    version: ${flow.version},
    minClient: ${flow.minClient},
    surface: Surface.${surface.wireName},
    deliveryMode: FlowDeliveryMode.${flow.delivery.wireName},
    decodeResult: $descriptorClass._decodeResult,
  );

  static Map<String, Object?> _decodeResult(Map<String, Object?> result) =>
      result;
}

class $actionsClass implements FlowActionRegistry, FlowSignalRegistry {
$generalActionsBody
  @override
  Set<String> get installedSignalNames => $signalSet;
}
$seedClass''';
  }
  final resultClass = '${baseName}Result';
  final result = _typedTerminalResultShape(lowered.document);
  return '''
part of '$stem.dart';

abstract final class $descriptorClass {
  const $descriptorClass._();

  static const SurfaceFlowRef<$resultClass> ref =
      SurfaceFlowRef<$resultClass>(
    id: '${flow.id}',
    version: ${flow.version},
    minClient: ${flow.minClient},
    surface: Surface.${surface.wireName},
    deliveryMode: FlowDeliveryMode.${flow.delivery.wireName},
    decodeResult: $descriptorClass._decodeResult,
  );

${_emitResultDecoder(resultClass, result)}
}

${_emitResultClass(resultClass, result)}

final class $actionsClass$actionsInterface {
${_emitActionsConstructor(actionsClass, flow.actions)}
${_emitActionFields(flow.actions, flow.minClient, lowered.actionContracts)}
}
$seedClass''';
}

/// Emits a typed seed builder exposing only the flow's `hostSeedable` keys.
///
/// Returns an empty string when no key is host-seedable, so a flow that opts
/// nothing in generates no builder. Each seedable key becomes an optional,
/// nullable, typed parameter, so a non-seedable or mistyped seed is
/// unconstructable; `toFlowState` omits unset keys (their declaration default
/// applies).
String _emitSeedClass(
  String className,
  Map<String, FlowStateDeclaration> flowState,
) {
  final seedable = <String, FlowDataType>{
    for (final entry in flowState.entries)
      if (entry.value.hostSeedable) entry.key: entry.value.type,
  };
  if (seedable.isEmpty) return '';
  final params = seedable.keys.map((key) => '    this.$key,').join('\n');
  final fields = seedable.entries
      .map((entry) => '  final ${_seedDartType(entry.value)}? ${entry.key};')
      .join('\n');
  final mapEntries = seedable.keys
      .map((key) => "        if ($key != null) '$key': $key,")
      .join('\n');
  return '''

final class $className implements FlowSeed {
  const $className({
$params
  });

$fields

  @override
  Map<String, Object?> toFlowState() => {
$mapEntries
      };
}
''';
}

String _seedDartType(FlowDataType type) => switch (type) {
      FlowDataType.bool => 'bool',
      FlowDataType.int => 'int',
      FlowDataType.string => 'String',
    };

/// Mirrors the exact result map the runtime gives to a typed decoder.
///
/// Legacy documents preserve their one terminal literal. Every current
/// document instead filters through `outbound.terminalResult`, whose declared
/// key/type map is the generated result contract.
Map<String, FlowDataType> _typedTerminalResultShape(FlowDocument document) {
  if (document.legacyTerminalResultPassthrough) {
    final result = _soleTypedTerminalResult(document);
    return {
      for (final entry in result.entries)
        entry.key: _resultLiteralFlowDataType(entry.value) ??
            (throw StateError(
              'Validated legacy terminal result has unsupported field '
              "'${entry.key}'.",
            )),
    };
  }
  return {
    for (final entry in document.outbound.terminalResult.fields.entries)
      entry.key: entry.value.type,
  };
}

Map<String, Object?> _soleTypedTerminalResult(FlowDocument document) {
  final terminals = document.states.values.whereType<EndFlowState>().toList();
  switch (terminals.length) {
    case 0:
      return const {};
    case 1:
      return terminals.single.result;
    default:
      throw StateError(
        'Typed flow descriptors require at most one terminal state; '
        'validation should have rejected this document before emission.',
      );
  }
}

String _emitResultDecoder(String className, Map<String, FlowDataType> result) {
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

String _emitResultValueRead(String key, FlowDataType value) {
  final type = _dartType(value);
  return '''
    final $key = result['$key'];
    if ($key is! $type) {
      throw const FormatException('Expected result field $key to be $type.');
    }''';
}

String _emitResultClass(String className, Map<String, FlowDataType> result) {
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

String _dartType(FlowDataType value) {
  return switch (value) {
    FlowDataType.bool => 'bool',
    FlowDataType.int => 'int',
    FlowDataType.string => 'String',
  };
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

final class _SubFlowInvocationVisitor extends RecursiveAstVisitor<void> {
  final List<MethodInvocation> invocations = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'subFlow') invocations.add(node);
    super.visitMethodInvocation(node);
  }
}

final class _FlowSource {
  _FlowSource({
    required this.id,
    required this.version,
    required this.minClient,
    required this.delivery,
    required this.className,
    required this.element,
    required this.actions,
    required this.invalidAnnotation,
    this.isCanonical = false,
    this.surface,
  });

  _FlowSource.invalid(ClassElement element)
      : this(
          id: '',
          version: 1,
          minClient: kBaselineCatalogVersion,
          delivery: FlowDeliveryMode.typed,
          className: element.name ?? '<unnamed>',
          element: element,
          actions: const [],
          invalidAnnotation: true,
          isCanonical: false,
        );

  final String id;
  final int version;
  final int minClient;
  final FlowDeliveryMode delivery;
  final String className;
  final ClassElement element;
  final List<_FlowAction> actions;
  final bool invalidAnnotation;
  final bool isCanonical;
  final Surface? surface;

  List<String> get generatedNames {
    final baseName = _flowBaseName(className);
    return [
      '${className}Descriptor',
      '${baseName}Result',
      '${baseName}Actions',
      '${baseName}Seed',
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
    this.declarationIdentity,
  });

  final String name;
  final String id;
  final String artifactPath;
  final int version;
  final int minClient;
  final String? declarationIdentity;
}

final class _ScreenNode {
  const _ScreenNode({
    required this.screen,
    required this.transitions,
  });

  final _ScreenDescriptor screen;
  final List<_ScreenTransition> transitions;
}

final class _ScreenTransition {
  const _ScreenTransition({
    required this.eventId,
    required this.transition,
    this.actionContract,
  });

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
    required this.surface,
  });

  final String id;
  final int version;
  final int minClient;
  final Surface surface;

  NormalizedFlowIdentity get identity =>
      NormalizedFlowIdentity(surface: surface, id: id);
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
