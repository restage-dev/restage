import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:meta/meta.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/authored_library_predicate.dart';
import 'package:restage_codegen/src/helper_registry.dart'
    show libraryUriMatchesOrigin;
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/onboarding/flow_definition_frontend.dart';
import 'package:restage_codegen/src/restage_source_roster.dart';
import 'package:restage_codegen/src/surface_publication/dynamic_output_owner.dart';
import 'package:restage_shared/restage_shared.dart'
    show FlowDeliveryMode, Surface;

const String _restageOrigin = 'package:restage';
const String _authoredDartGlob = 'lib/**.dart';
const String _canonicalPublicationOwner =
    'restage_codegen:restage_surface_publication_owner';

const Map<String, RestageRosterSourceKind> _legacyAnnotationKinds = {
  'ScreenSource': RestageRosterSourceKind.screen,
  'OnboardingSource': RestageRosterSourceKind.screen,
  'PaywallSource': RestageRosterSourceKind.paywall,
  'FlowSource': RestageRosterSourceKind.flow,
  'OnboardingFlow': RestageRosterSourceKind.flow,
};

final RegExp _screenSourcePath = RegExp(
  r'^lib/(onboarding|message|survey)/screens/([^/]+)\.dart$',
);
final RegExp _flowSourcePath = RegExp(
  r'^lib/(onboarding|message|survey)/flows/([^/]+)\.dart$',
);
final RegExp _paywallSourcePath = RegExp(r'^lib/paywalls/([^/]+)\.dart$');

/// The package-level source/output owner.
///
/// The `$package$` input is the build graph's package placeholder, so this
/// builder runs once per package.  Its only discovery operation is the
/// tracked `findAssets` glob below; analyzer resolution and the two source
/// reads for legacy `part` admission are consequently dependencies in the
/// asset graph rather than untracked filesystem observations.
@internal
final class RestageSourceRosterBuilder implements Builder {
  /// Creates the package owner.
  const RestageSourceRosterBuilder(this.options);

  /// Builder options are reserved for a later frontend and do not alter the
  /// package roster in this gate.
  final BuilderOptions options;

  @override
  Map<String, List<String>> get buildExtensions => const {
        r'$package$': [
          'assets/restage/source-index.json',
          'assets/restage/output-roster.json',
        ],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final packageName = buildStep.inputId.package;
    final roster = await collectRestageSourceRoster(buildStep);
    if (!roster.isValid) {
      for (final issue in roster.issues) {
        log.severe(issue.toLogString());
      }
    }
    // Always materialize the fixed package index and output ledger before
    // failing. The publication bundle has its own post-process invalid marker;
    // this source-admission failure remains deliberately visible to callers.
    await Future.wait<void>([
      buildStep.writeAsString(
        AssetId(packageName, 'assets/restage/source-index.json'),
        roster.encodeSourceIndex(packageName),
      ),
      buildStep.writeAsString(
        AssetId(packageName, 'assets/restage/output-roster.json'),
        roster.encodeOutputRoster(packageName),
      ),
    ]);
    if (!roster.isValid) {
      throw StateError(
        '${roster.issues.length} Restage source roster issue(s); '
        'see log above.',
      );
    }
  }
}

RestageSourceRoster _withFixedPublicationManifest({
  required String packageName,
  required RestageSourceRoster roster,
}) {
  const manifestIdentity = RestageIdentityClaim(
    namespace: 'fixed-output',
    key: kRestageSurfacePublicationManifestPath,
  );
  final output = RestageOwnedOutput(
    path: kRestageSurfacePublicationManifestPath,
    role: 'surface-publication-manifest',
    builder: 'restage_codegen:restage_surface_publication_owner',
    owner: 'package:$packageName#surface-publication',
    declarationIdentity: 'package:$packageName#surface-publication',
    identities: const [manifestIdentity],
    span: const RestageSourceSpan(
      path: kRestageSurfacePublicationManifestPath,
      startLine: 1,
      startColumn: 1,
      endLine: 1,
      endColumn: 1,
    ),
  );
  return RestageSourceRoster(
    declarations: roster.declarations,
    issues: roster.issues,
    fixedOutputs: [output],
  );
}

/// Discovers canonical declarations and deprecated `*Source` declarations and
/// assembles their package ownership facts.
///
/// Canonical declarations are recognized only through resolved SDK analyzer
/// elements.  The legacy branch below is intentionally the only branch that
/// consults a source directory for product meaning.
@visibleForTesting
Future<RestageSourceRoster> collectRestageSourceRoster(
  BuildStep buildStep,
) async {
  final sourceAssets = await buildStep
      .findAssets(Glob(_authoredDartGlob))
      .where(isAuthoredDartLibraryAsset)
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));

  final declarations = <RestageSourceDeclaration>[];
  final normalizedFlows = <NormalizedFlowSource>[];
  final issues = <Issue>[];
  final sourceTexts = <AssetId, String>{};

  for (final assetId in sourceAssets) {
    final LibraryElement library;
    try {
      library = await buildStep.resolver.libraryFor(
        assetId,
        allowSyntaxErrors: true,
      );
    } on NonLibraryAssetException {
      // A part is visited through its owning library.  Processing it again
      // would duplicate every declaration and falsely collide its outputs.
      continue;
    }

    final checkedAdmissionKinds = <RestageRosterSourceKind>{};

    await _collectCanonicalDeclarations(
      buildStep: buildStep,
      assetId: assetId,
      library: library,
      sourceTexts: sourceTexts,
      declarations: declarations,
      normalizedFlows: normalizedFlows,
      issues: issues,
    );

    for (final entry in _legacyAnnotationKinds.entries) {
      final kind = entry.value;
      final annotationName = entry.key;
      final annotatedClasses = <ClassElement>[];
      for (final cls in library.classes) {
        if (firstAnnotationFromOriginAny(
              cls,
              {annotationName},
              _restageOrigin,
            ) !=
            null) {
          annotatedClasses.add(cls);
        }
      }
      if (annotatedClasses.isEmpty) continue;

      if (checkedAdmissionKinds.add(kind)) {
        final sourceText =
            sourceTexts[assetId] ??= await buildStep.readAsString(
          assetId,
        );
        issues.addAll(
          _legacyAdmissionIssues(
            assetId: assetId,
            sourceText: sourceText,
            kind: kind,
            annotatedClasses: annotatedClasses,
          ),
        );
      }

      for (final cls in annotatedClasses) {
        final sourcePath = _elementSourcePath(cls, assetId);
        final span = _sourceSpan(cls, sourcePath);
        final annotation = firstAnnotationFromOriginAny(
          cls,
          {annotationName},
          _restageOrigin,
        );
        if (annotation == null) continue;

        final value = annotation.computeConstantValue();
        if (value == null) {
          issues.add(
            Issue(
              code: IssueCode.annotationEvaluationFailed,
              message: '@$annotationName on ${cls.name ?? '<unnamed>'} '
                  'could not be const-evaluated for package ownership.',
              location: span.location,
            ),
          );
          continue;
        }
        final id = value.getField('id')?.toStringValue();
        if (id == null || id.isEmpty) {
          issues.add(
            Issue(
              code: IssueCode.annotationEvaluationFailed,
              message: '@$annotationName.id is required and must be a '
                  'non-empty String literal.',
              location: span.location,
            ),
          );
          continue;
        }

        final outputs = _legacyOutputClaims(kind, assetId);
        if (outputs == null) {
          issues.add(
            Issue(
              code: IssueCode.invalidScreenSourceLocation,
              message: '@$annotationName is not admitted outside the current '
                  'legacy source topology. Use canonical @Screen, @Paywall, '
                  'or @FlowGraph authoring for directory-free sources and '
                  'colocated declarations.',
              location: span.location,
            ),
          );
          continue;
        }

        final stem = _fileStem(assetId.path);
        if (id != stem) {
          issues.add(
            Issue(
              code: IssueCode.filenameMismatch,
              message: 'Legacy ${kind.wireName} source id "$id" does not '
                  'match the owning file name "$stem.dart".',
              location: span.location,
            ),
          );
        }

        declarations.add(
          RestageSourceDeclaration.frozen(
            kind: kind,
            libraryIdentity: library.identifier,
            libraryPath: assetId.path,
            declarationIdentity:
                '${library.identifier}#${cls.name ?? '<unnamed>'}',
            sourcePath: sourcePath,
            explicitId: id,
            span: span,
            identityClaims: _legacyIdentityClaims(
              kind: kind,
              assetId: assetId,
              id: id,
            ),
            outputs: outputs,
            surface: _legacySurfaceForKind(kind, assetId),
            version: value.getField('version')?.toIntValue() ?? 1,
            minClient: value.getField('minClient')?.toIntValue() ?? 1,
            delivery: _flowDeliveryFromValue(value.getField('delivery')),
          ),
        );
      }
    }
  }

  final ownership = assembleRestageSourceRoster(
    _materializeNeutralScreenOutputs(
      declarations,
      normalizedFlows: normalizedFlows,
    ),
  );
  issues
    ..addAll(ownership.issues)
    ..sort(_compareIssues);
  final roster = RestageSourceRoster(
    declarations: ownership.declarations,
    issues: issues,
  );
  return _withFixedPublicationManifest(
    packageName: buildStep.inputId.package,
    roster: roster,
  );
}

Future<void> _collectCanonicalDeclarations({
  required BuildStep buildStep,
  required AssetId assetId,
  required LibraryElement library,
  required Map<AssetId, String> sourceTexts,
  required List<RestageSourceDeclaration> declarations,
  required List<NormalizedFlowSource> normalizedFlows,
  required List<Issue> issues,
}) async {
  final canonicalParts = <RestageRosterSourceKind>{};

  for (final cls in library.classes) {
    final screenAnnotation = firstAnnotationFromOriginAny(
      cls,
      const {'Screen'},
      _restageOrigin,
    );
    final paywallAnnotation = firstAnnotationFromOriginAny(
      cls,
      const {'Paywall'},
      _restageOrigin,
    );
    if (screenAnnotation != null && paywallAnnotation != null) {
      issues.add(
        Issue(
          code: IssueCode.duplicateId,
          message: 'A class cannot be both @Screen and @Paywall; '
              'source kind must be unambiguous.',
          location: '${assetId.path}#${cls.name ?? '<unnamed>'}',
        ),
      );
      continue;
    }

    final annotation = screenAnnotation ?? paywallAnnotation;
    if (annotation == null) continue;
    final kind = paywallAnnotation == null
        ? RestageRosterSourceKind.screen
        : RestageRosterSourceKind.paywall;
    final metadata = _canonicalClassMetadata(
      annotation,
      kind: kind,
      assetId: assetId,
      className: cls.name ?? '<unnamed>',
      issues: issues,
    );
    if (metadata == null) continue;
    if (!_isSupportedCanonicalWidget(cls)) {
      final sourceKind =
          kind == RestageRosterSourceKind.paywall ? 'Paywall' : 'Screen';
      issues.add(
        Issue(
          code: IssueCode.unsupportedBaseClass,
          message: '@$sourceKind '
              '${cls.name ?? '<unnamed>'} must resolve to a Flutter '
              'StatelessWidget or StatefulWidget.',
          location: '${assetId.path}#${cls.name ?? '<unnamed>'}',
        ),
      );
      continue;
    }

    if (kind == RestageRosterSourceKind.screen && canonicalParts.add(kind)) {
      issues.addAll(
        await _canonicalPartIssues(
          buildStep: buildStep,
          assetId: assetId,
          sourceTexts: sourceTexts,
          suffix: kind == RestageRosterSourceKind.flow
              ? 'rsflow.g.dart'
              : 'rsscreen.g.dart',
        ),
      );
    }

    final id = metadata.id ?? _fileStem(assetId.path);
    declarations.add(
      RestageSourceDeclaration.frozen(
        kind: kind,
        libraryIdentity: library.identifier,
        libraryPath: assetId.path,
        declarationIdentity: '${library.identifier}#${cls.name ?? '<unnamed>'}',
        sourcePath: _elementSourcePath(cls, assetId),
        explicitId: metadata.id,
        span: _elementSpan(cls, _elementSourcePath(cls, assetId)),
        identityClaims: _canonicalIdentityClaims(
          kind: kind,
          surface: metadata.surface,
          id: id,
        ),
        outputs: _canonicalOutputClaims(
          kind: kind,
          surface: metadata.surface,
          id: id,
          libraryIdentity: library.identifier,
          libraryPath: assetId.path,
        ),
        surface: metadata.surface,
        version: metadata.version,
        minClient: metadata.minClient,
        isCanonical: true,
      ),
    );
  }

  final hasCanonicalFlow = library.topLevelVariables.any(
        (variable) =>
            firstAnnotationFromOriginAny(
              variable,
              const {'FlowGraph'},
              _restageOrigin,
            ) !=
            null,
      ) ||
      library.classes.any(
        (cls) =>
            firstAnnotationFromOriginAny(
              cls,
              const {'FlowGraph'},
              _restageOrigin,
            ) !=
            null,
      );
  if (!hasCanonicalFlow) return;

  final frontend = await inspectFlowDefinitions(
    library,
    assetId,
    legacySurface: _legacySurfaceForPath(assetId.path),
  );
  issues.addAll(frontend.issues);
  normalizedFlows.addAll(frontend.flows);
  if (frontend.flows.isEmpty) return;

  final sourceText = sourceTexts[assetId] ??= await buildStep.readAsString(
    assetId,
  );
  final parsed = parseString(
    content: sourceText,
    path: assetId.path,
    throwIfDiagnostics: false,
  ).unit;
  final expectedPart = '${_fileStem(assetId.path)}.rsflow.g.dart';
  if (!parsed.directives.whereType<PartDirective>().any(
        (directive) => directive.uri.stringValue == expectedPart,
      )) {
    issues.add(
      Issue(
        code: IssueCode.missingPartDirective,
        message: "Missing `part '$expectedPart';` directive.",
        location: assetId.path,
      ),
    );
  }

  for (final flow in frontend.flows.where((flow) => flow.isCanonical)) {
    final id = flow.id;
    if (!_validCanonicalId(id)) {
      issues.add(
        Issue(
          code: IssueCode.annotationEvaluationFailed,
          message: '@FlowGraph.id must be a non-empty, trimmed, path-safe '
              'String literal.',
          location: '${assetId.path}#${flow.declaration.name}',
        ),
      );
      continue;
    }
    declarations.add(
      RestageSourceDeclaration.frozen(
        kind: RestageRosterSourceKind.flow,
        libraryIdentity: library.identifier,
        libraryPath: assetId.path,
        declarationIdentity: flow.declarationIdentity,
        sourcePath: _elementSourcePath(flow.declaration, assetId),
        explicitId: flow.hasExplicitId ? id : null,
        span: _elementSpan(
          flow.declaration,
          _elementSourcePath(flow.declaration, assetId),
        ),
        identityClaims: _canonicalIdentityClaims(
          kind: RestageRosterSourceKind.flow,
          surface: flow.surface,
          id: id,
        ),
        outputs: _canonicalOutputClaims(
          kind: RestageRosterSourceKind.flow,
          surface: flow.surface,
          id: id,
          libraryIdentity: library.identifier,
          libraryPath: assetId.path,
        ),
        surface: flow.surface,
        version: flow.version,
        minClient: flow.minClient,
        delivery: flow.delivery,
        isCanonical: true,
      ),
    );
  }
}

@immutable
final class _CanonicalClassMetadata {
  const _CanonicalClassMetadata({
    required this.id,
    required this.surface,
    required this.version,
    required this.minClient,
  });

  final String? id;
  final Surface? surface;
  final int version;
  final int minClient;
}

_CanonicalClassMetadata? _canonicalClassMetadata(
  ElementAnnotation annotation, {
  required RestageRosterSourceKind kind,
  required AssetId assetId,
  required String className,
  required List<Issue> issues,
}) {
  final owner = resolvedAnnotationClass(annotation);
  if (owner == null ||
      !libraryUriMatchesOrigin(owner.library.identifier, _restageOrigin)) {
    issues.add(
      Issue(
        code: IssueCode.unresolvedIdentifier,
        message: 'Canonical source annotation on $className must resolve to '
            'the Restage SDK.',
        location: '${assetId.path}#$className',
      ),
    );
    return null;
  }
  final value = annotation.computeConstantValue();
  if (value == null) {
    issues.add(
      Issue(
        code: IssueCode.annotationEvaluationFailed,
        message: '@${owner.name} on $className could not be const-evaluated.',
        location: '${assetId.path}#$className',
      ),
    );
    return null;
  }

  final idValue = value.getField('id');
  final id = idValue == null || idValue.isNull ? null : idValue.toStringValue();
  if (idValue != null &&
      !idValue.isNull &&
      (id == null || !_validCanonicalId(id))) {
    issues.add(
      Issue(
        code: IssueCode.annotationEvaluationFailed,
        message: '@${owner.name}.id must be a non-empty, trimmed, path-safe '
            'String literal.',
        location: '${assetId.path}#$className',
      ),
    );
    return null;
  }

  final surface = kind == RestageRosterSourceKind.paywall
      ? Surface.paywall
      : _surfaceFromValue(value.getField('surface'));
  final hasSurface =
      value.getField('surface') != null && !value.getField('surface')!.isNull;
  if (kind == RestageRosterSourceKind.screen && hasSurface && surface == null) {
    issues.add(
      Issue(
        code: IssueCode.annotationEvaluationFailed,
        message: '@Screen.surface must be a resolved Surface enum value.',
        location: '${assetId.path}#$className',
      ),
    );
    return null;
  }
  final version = value.getField('version')?.toIntValue() ?? 1;
  final minClient = value.getField('minClient')?.toIntValue() ?? 1;
  if (version < 1 || minClient < 1) {
    issues.add(
      Issue(
        code: IssueCode.annotationEvaluationFailed,
        message: '@${owner.name} version and minClient must be positive.',
        location: '${assetId.path}#$className',
      ),
    );
    return null;
  }
  return _CanonicalClassMetadata(
    id: id,
    surface: surface,
    version: version,
    minClient: minClient,
  );
}

Future<List<Issue>> _canonicalPartIssues({
  required BuildStep buildStep,
  required AssetId assetId,
  required Map<AssetId, String> sourceTexts,
  required String suffix,
}) async {
  final sourceText = sourceTexts[assetId] ??= await buildStep.readAsString(
    assetId,
  );
  final parsed = parseString(
    content: sourceText,
    path: assetId.path,
    throwIfDiagnostics: false,
  ).unit;
  final expectedPart = '${_fileStem(assetId.path)}.$suffix';
  if (parsed.directives.whereType<PartDirective>().any(
        (directive) => directive.uri.stringValue == expectedPart,
      )) {
    return const [];
  }
  return [
    Issue(
      code: IssueCode.missingPartDirective,
      message: "Missing `part '$expectedPart';` directive.",
      location: assetId.path,
    ),
  ];
}

List<RestageIdentityClaim> _canonicalIdentityClaims({
  required RestageRosterSourceKind kind,
  required Surface? surface,
  required String id,
}) {
  final surfaceKey = surface?.wireName ?? 'neutral';
  final claims = <RestageIdentityClaim>[
    RestageIdentityClaim(
      namespace: 'canonical-source/${kind.wireName}/$surfaceKey',
      key: id,
    ),
  ];
  // Neutral screens are reusable flow content, not standalone publications.
  // Their category is inherited by the containing flow, so they must not
  // reserve a package-wide neutral publication identity.
  if (surface != null || kind != RestageRosterSourceKind.screen) {
    claims.add(
      RestageIdentityClaim(
        namespace: 'canonical-publication/$surfaceKey',
        key: id,
      ),
    );
  }
  return claims;
}

List<RestageOutputClaim> _canonicalOutputClaims({
  required RestageRosterSourceKind kind,
  required Surface? surface,
  required String id,
  required String libraryIdentity,
  required String libraryPath,
}) {
  final surfaceKey = surface?.wireName ?? 'neutral';
  final sourceDirectory = libraryPath.substring(
    0,
    libraryPath.lastIndexOf('/') + 1,
  );
  final partSuffix = kind == RestageRosterSourceKind.flow
      ? 'rsflow.g.dart'
      : 'rsscreen.g.dart';
  final part = kind == RestageRosterSourceKind.paywall
      ? null
      : RestageOutputClaim(
          path: '$sourceDirectory${_fileStem(libraryPath)}.$partSuffix',
          role: kind == RestageRosterSourceKind.flow
              ? 'flow-descriptor'
              : 'screen-descriptor',
          builder: _canonicalPublicationOwner,
          ownershipKey: 'canonical-library:$libraryIdentity',
        );

  if (kind == RestageRosterSourceKind.screen && surface == null) {
    return [part!];
  }

  if (kind == RestageRosterSourceKind.flow) {
    return [
      part!,
      RestageOutputClaim(
        path: 'assets/$surfaceKey/flows/$id.flow.json',
        role: 'flow-document',
        builder: _canonicalPublicationOwner,
        ownershipKey: 'canonical-publication:$surfaceKey/$id',
      ),
    ];
  }

  final root = kind == RestageRosterSourceKind.paywall
      ? 'assets/paywalls/$id'
      : 'assets/$surfaceKey/screens/$id';
  final claims = <RestageOutputClaim>[
    if (part != null) part,
    RestageOutputClaim(
      path: '$root.rfwtxt',
      role: 'screen-text',
      builder: _canonicalPublicationOwner,
      ownershipKey: 'canonical-publication:$surfaceKey/$id',
    ),
    RestageOutputClaim(
      path: '$root.rfw',
      role: 'screen-blob',
      builder: _canonicalPublicationOwner,
      ownershipKey: 'canonical-publication:$surfaceKey/$id',
    ),
    RestageOutputClaim(
      path: '$root.capability.json',
      role: 'capability-sidecar',
      builder: _canonicalPublicationOwner,
      ownershipKey: 'canonical-publication:$surfaceKey/$id',
    ),
  ];
  if (kind == RestageRosterSourceKind.paywall) {
    claims.addAll([
      RestageOutputClaim(
        path: '$root.navplan.json',
        role: 'navigation-plan',
        builder: _canonicalPublicationOwner,
        ownershipKey: 'canonical-publication:$surfaceKey/$id',
      ),
      RestageOutputClaim(
        path: 'assets/paywalls/screens/paywall_$id.rfw',
        role: 'flow-screen-blob',
        builder: _canonicalPublicationOwner,
        ownershipKey: 'canonical-publication:$surfaceKey/$id',
      ),
      RestageOutputClaim(
        path: 'assets/paywalls/screens/paywall_$id.capability.json',
        role: 'flow-screen-capability-sidecar',
        builder: _canonicalPublicationOwner,
        ownershipKey: 'canonical-publication:$surfaceKey/$id',
      ),
      RestageOutputClaim(
        path: '$root.flow.json',
        role: 'flow-document',
        builder: _canonicalPublicationOwner,
        ownershipKey: 'canonical-publication:$surfaceKey/$id',
      ),
    ]);
  }
  return claims;
}

List<RestageSourceDeclaration> _materializeNeutralScreenOutputs(
  List<RestageSourceDeclaration> declarations, {
  required List<NormalizedFlowSource> normalizedFlows,
}) {
  final effectiveSurfaces = <String, Set<Surface>>{};
  for (final flow in normalizedFlows) {
    final graph = flow.graph;
    if (graph == null) {
      // The proven class-shaped frontend resolves its exact closure while
      // lowering buildFlow(). Until that lowering runs, conservatively give
      // package-local neutral screens the advanced flow's explicit surface.
      // Only screens actually present in the lowered document enter the
      // manifest closure; these claims merely make their aggregate-owned
      // bytes available without consulting a directory.
      for (final declaration in declarations) {
        if (declaration.kind == RestageRosterSourceKind.screen &&
            declaration.surface == null) {
          effectiveSurfaces
              .putIfAbsent(
                declaration.declarationIdentity,
                () => <Surface>{},
              )
              .add(flow.surface);
        }
      }
      continue;
    }
    for (final reference in graph.screens.values) {
      if (reference.isPaywall || reference.declaredSurface != null) continue;
      effectiveSurfaces
          .putIfAbsent(reference.declarationIdentity, () => <Surface>{})
          .add(reference.effectiveSurface);
    }
  }

  return [
    for (final declaration in declarations)
      if (declaration.kind != RestageRosterSourceKind.screen ||
          declaration.surface != null ||
          effectiveSurfaces[declaration.declarationIdentity] == null)
        declaration
      else
        RestageSourceDeclaration.frozen(
          kind: declaration.kind,
          libraryIdentity: declaration.libraryIdentity,
          libraryPath: declaration.libraryPath,
          declarationIdentity: declaration.declarationIdentity,
          sourcePath: declaration.sourcePath,
          explicitId: declaration.explicitId,
          span: declaration.span,
          identityClaims: declaration.identityClaims,
          outputs: [
            ...declaration.outputs,
            for (final surface
                in effectiveSurfaces[declaration.declarationIdentity]!.toList()
                  ..sort(
                    (left, right) => left.wireName.compareTo(right.wireName),
                  ))
              ..._neutralScreenArtifactClaims(
                declaration,
                surface: surface,
              ),
          ],
          surface: declaration.surface,
          version: declaration.version,
          minClient: declaration.minClient,
          delivery: declaration.delivery,
          isCanonical: declaration.isCanonical,
        ),
  ];
}

List<RestageOutputClaim> _neutralScreenArtifactClaims(
  RestageSourceDeclaration declaration, {
  required Surface surface,
}) {
  final root = 'assets/${surface.wireName}/screens/${declaration.effectiveId}';
  final owner =
      'canonical-flow-content:${surface.wireName}/${declaration.effectiveId}';
  return [
    RestageOutputClaim(
      path: '$root.rfwtxt',
      role: 'screen-text',
      builder: _canonicalPublicationOwner,
      ownershipKey: owner,
    ),
    RestageOutputClaim(
      path: '$root.rfw',
      role: 'screen-blob',
      builder: _canonicalPublicationOwner,
      ownershipKey: owner,
    ),
    RestageOutputClaim(
      path: '$root.capability.json',
      role: 'capability-sidecar',
      builder: _canonicalPublicationOwner,
      ownershipKey: owner,
    ),
  ];
}

Surface? _surfaceFromValue(DartObject? value) {
  if (value == null || value.isNull) return null;
  final type = value.type;
  final element = type?.element;
  if (element is! EnumElement ||
      element.name != 'Surface' ||
      !libraryUriMatchesOrigin(
        element.library.identifier,
        'package:restage_shared',
      )) {
    return null;
  }
  final wireName = value.getField('wireName')?.toStringValue();
  if (wireName == null) return null;
  for (final surface in Surface.values) {
    if (surface.wireName == wireName) return surface;
  }
  return null;
}

bool _isSupportedCanonicalWidget(ClassElement cls) {
  for (var type = cls.supertype; type != null; type = type.element.supertype) {
    if ((type.element.name == 'StatelessWidget' ||
            type.element.name == 'StatefulWidget') &&
        libraryUriMatchesOrigin(
          type.element.library.identifier,
          'package:flutter',
        )) {
      return true;
    }
  }
  return false;
}

Surface? _legacySurfaceForPath(String path) {
  final screen = _screenSourcePath.firstMatch(path);
  if (screen != null) return _surfaceFromWireName(screen.group(1)!);
  final flow = _flowSourcePath.firstMatch(path);
  if (flow != null) return _surfaceFromWireName(flow.group(1)!);
  return null;
}

Surface? _legacySurfaceForKind(RestageRosterSourceKind kind, AssetId assetId) {
  if (kind == RestageRosterSourceKind.paywall) return Surface.paywall;
  return _legacySurfaceForPath(assetId.path);
}

Surface? _surfaceFromWireName(String wireName) {
  for (final surface in Surface.values) {
    if (surface.wireName == wireName) return surface;
  }
  return null;
}

FlowDeliveryMode? _flowDeliveryFromValue(DartObject? value) {
  if (value == null || value.isNull) return null;
  final type = value.type;
  final element = type?.element;
  if (element is! EnumElement ||
      element.name != 'FlowDeliveryMode' ||
      !libraryUriMatchesOrigin(
        element.library.identifier,
        'package:restage_shared',
      )) {
    return null;
  }
  final wireName = value.getField('wireName')?.toStringValue();
  if (wireName == null) return null;
  for (final mode in FlowDeliveryMode.values) {
    if (mode.wireName == wireName) return mode;
  }
  return null;
}

RestageSourceSpan _elementSpan(Element element, String sourcePath) {
  final name = element.name ?? '<unnamed>';
  final fragment = element.firstFragment.libraryFragment;
  if (fragment == null) {
    return RestageSourceSpan(
      path: sourcePath,
      startLine: 1,
      startColumn: 1,
      endLine: 1,
      endColumn: name.length + 1,
    );
  }
  final location = fragment.lineInfo.getLocation(element.firstFragment.offset);
  return RestageSourceSpan(
    path: sourcePath,
    startLine: location.lineNumber,
    startColumn: location.columnNumber,
    endLine: location.lineNumber,
    endColumn: location.columnNumber + name.length,
  );
}

List<Issue> _legacyAdmissionIssues({
  required AssetId assetId,
  required String sourceText,
  required RestageRosterSourceKind kind,
  required List<ClassElement> annotatedClasses,
}) {
  final issues = <Issue>[];
  final parsed = parseString(
    content: sourceText,
    path: assetId.path,
    throwIfDiagnostics: false,
  ).unit;

  final pathMatch = switch (kind) {
    RestageRosterSourceKind.screen =>
      _screenSourcePath.firstMatch(assetId.path),
    RestageRosterSourceKind.flow => _flowSourcePath.firstMatch(assetId.path),
    RestageRosterSourceKind.paywall => null,
  };
  if (kind != RestageRosterSourceKind.paywall && pathMatch == null) {
    issues.add(
      Issue(
        code: IssueCode.invalidScreenSourceLocation,
        message: 'Legacy ${kind.wireName} sources must remain under their '
            'current surface-specific source directory; found '
            '`${assetId.path}`.',
        location: assetId.path,
      ),
    );
  }

  if (kind == RestageRosterSourceKind.screen && annotatedClasses.length != 1) {
    issues.add(
      Issue(
        code: IssueCode.invalidScreenSourceCount,
        message: 'A legacy ScreenSource library must declare exactly one '
            'annotated screen class; found ${annotatedClasses.length}.',
        location: assetId.path,
      ),
    );
  }

  if (kind == RestageRosterSourceKind.screen ||
      kind == RestageRosterSourceKind.flow) {
    final stem = _fileStem(assetId.path);
    final suffix = kind == RestageRosterSourceKind.screen
        ? 'rsscreen.g.dart'
        : 'rsflow.g.dart';
    final expectedPart = '$stem.$suffix';
    final hasPart = parsed.directives.whereType<PartDirective>().any(
          (directive) => directive.uri.stringValue == expectedPart,
        );
    if (!hasPart) {
      issues.add(
        Issue(
          code: IssueCode.missingPartDirective,
          message: "Missing `part '$expectedPart';` directive.",
          location: assetId.path,
        ),
      );
    }
  }
  return issues;
}

List<RestageOutputClaim>? _legacyOutputClaims(
  RestageRosterSourceKind kind,
  AssetId assetId,
) {
  final path = assetId.path;
  switch (kind) {
    case RestageRosterSourceKind.screen:
      final match = _screenSourcePath.firstMatch(path);
      if (match == null) return null;
      final surface = match.group(1)!;
      final stem = match.group(2)!;
      final sourceDir = 'lib/$surface/screens';
      final outputDir = 'assets/$surface/screens';
      final builder = 'restage_codegen:${surface}_screen_codegen';
      return [
        RestageOutputClaim(
          path: '$sourceDir/$stem.rsscreen.g.dart',
          role: 'descriptor',
          builder: builder,
        ),
        RestageOutputClaim(
          path: '$outputDir/$stem.rfwtxt',
          role: 'text',
          builder: builder,
        ),
        RestageOutputClaim(
          path: '$outputDir/$stem.rfw',
          role: 'binary',
          builder: builder,
        ),
        RestageOutputClaim(
          path: '$outputDir/$stem.capability.json',
          role: 'capability',
          builder: builder,
        ),
      ];
    case RestageRosterSourceKind.flow:
      final match = _flowSourcePath.firstMatch(path);
      if (match == null) return null;
      final surface = match.group(1)!;
      final stem = match.group(2)!;
      final sourceDir = 'lib/$surface/flows';
      final outputDir = 'assets/$surface/flows';
      final builder = 'restage_codegen:${surface}_flow_codegen';
      return [
        RestageOutputClaim(
          path: '$sourceDir/$stem.rsflow.g.dart',
          role: 'descriptor',
          builder: builder,
        ),
        RestageOutputClaim(
          path: '$outputDir/$stem.flow.json',
          role: 'flow',
          builder: builder,
        ),
      ];
    case RestageRosterSourceKind.paywall:
      final match = _paywallSourcePath.firstMatch(path);
      if (match == null) return null;
      final stem = match.group(1)!;
      const builder = 'restage_codegen:paywall_codegen';
      return [
        RestageOutputClaim(
          path: 'assets/paywalls/$stem.rfwtxt',
          role: 'text',
          builder: builder,
        ),
        RestageOutputClaim(
          path: 'assets/paywalls/$stem.rfw',
          role: 'binary',
          builder: builder,
        ),
        RestageOutputClaim(
          path: 'assets/paywalls/$stem.capability.json',
          role: 'capability',
          builder: builder,
        ),
        RestageOutputClaim(
          path: 'assets/paywalls/$stem.navplan.json',
          role: 'navigation-plan',
          builder: builder,
        ),
        RestageOutputClaim(
          path: 'assets/paywalls/screens/paywall_$stem.rfw',
          role: 'flow-screen-binary',
          builder: builder,
        ),
        RestageOutputClaim(
          path: 'assets/paywalls/screens/paywall_$stem.capability.json',
          role: 'flow-screen-capability',
          builder: builder,
        ),
        RestageOutputClaim(
          path: 'assets/paywalls/$stem.flow.json',
          role: 'flow',
          builder: 'restage_codegen:paywall_flow_codegen',
        ),
      ];
  }
}

/// Returns only the identity namespaces this pre-frontend lane can prove.
///
/// The surface segment is retained in the legacy source namespace so two
/// source declarations in different surfaces do not accidentally freeze a
/// package-wide `kind:id` contract.  This is still not the backend/publication
/// `(surface, slug)` identity: source/payload-kind immutability and publication
/// collision are deliberately deferred to the later frontend. Artifact output
/// paths are a separate namespace and are checked by the normalized roster.
List<RestageIdentityClaim> _legacyIdentityClaims({
  required RestageRosterSourceKind kind,
  required AssetId assetId,
  required String id,
}) {
  final surface = switch (kind) {
    RestageRosterSourceKind.screen =>
      _screenSourcePath.firstMatch(assetId.path)?.group(1),
    RestageRosterSourceKind.flow =>
      _flowSourcePath.firstMatch(assetId.path)?.group(1),
    RestageRosterSourceKind.paywall => 'paywall',
  };
  final admittedSurface = surface ?? 'unadmitted';
  return [
    RestageIdentityClaim(
      namespace: 'legacy-source/${kind.wireName}/$admittedSurface',
      key: id,
    ),
  ];
}

RestageSourceSpan _sourceSpan(ClassElement element, String sourcePath) {
  final className = element.name ?? '<unnamed>';
  final fragment = element.firstFragment.libraryFragment;
  final offset = element.firstFragment.offset;
  final location = fragment.lineInfo.getLocation(offset);
  return RestageSourceSpan(
    path: sourcePath,
    startLine: location.lineNumber,
    startColumn: location.columnNumber,
    endLine: location.lineNumber,
    endColumn: location.columnNumber + className.length,
  );
}

String _elementSourcePath(Element element, AssetId contextAsset) {
  final fragment = element.firstFragment.libraryFragment;
  if (fragment == null) return contextAsset.path;
  final source = fragment.source;
  final uri = source.uri;
  if (uri.scheme == 'package' || uri.scheme == 'asset') {
    final asset = AssetId.resolve(uri);
    return asset.package == contextAsset.package ? asset.path : uri.toString();
  }
  if (uri.scheme == 'file') return source.fullName;
  if (uri.hasScheme) return uri.toString();
  return contextAsset.path;
}

String _fileStem(String path) {
  final slash = path.lastIndexOf('/');
  final filename = slash == -1 ? path : path.substring(slash + 1);
  return filename.endsWith('.dart')
      ? filename.substring(0, filename.length - '.dart'.length)
      : filename;
}

bool _validCanonicalId(String value) {
  if (value.isEmpty || value.trim() != value || value.contains('\u0000')) {
    return false;
  }
  if (value.startsWith('/') || value.contains(r'\')) return false;
  return value.split('/').every(
        (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
      );
}

int _compareIssues(Issue left, Issue right) {
  final byLocation = left.location.compareTo(right.location);
  if (byLocation != 0) return byLocation;
  final byCode = left.code.name.compareTo(right.code.name);
  return byCode != 0 ? byCode : left.message.compareTo(right.message);
}
