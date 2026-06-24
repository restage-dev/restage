// Internal builder implementation is reached through documented factories.
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:typed_data';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/capability_derivation.dart';
import 'package:restage_codegen/src/catalog_loader.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;

const String _kPaywallSourceDir = 'lib/paywalls';
const String _kPaywallOutputDir = 'assets/paywalls';
const String _kScreenOutputDir = 'assets/onboarding/screens';
const String _kDoneState = 'done';
const String _zeroHash = 'sha256:00000000000000000000000000000000'
    '00000000000000000000000000000000';

final class PaywallFlowBuilder implements Builder {
  PaywallFlowBuilder(this.options);

  final BuilderOptions options;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '$_kPaywallSourceDir/{{name}}.dart': [
          '$_kPaywallOutputDir/{{name}}.flow.json',
        ],
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final assetId = buildStep.inputId;
    final stem = p.basenameWithoutExtension(assetId.path);
    final navPlanId = AssetId(
      assetId.package,
      '$_kPaywallOutputDir/$stem.navplan.json',
    );
    if (!await buildStep.canRead(navPlanId)) return;

    final issues = <Issue>[];
    final source = await buildStep.readAsString(navPlanId);
    final plan = _decodeNavigationPlan(source, assetId, navPlanId, issues);
    if (issues.isNotEmpty) _surfaceIssues(issues);

    // Loaded only for an actual navigation flow (past the no-navplan early
    // return). The capability floor each screen artifact declares is derived
    // from the built-ins that screen references, resolved against this catalog
    // — the same derivation the standalone blob uses, so the two never diverge.
    final catalog = await loadMergedCatalog(buildStep);

    final document = await _synthesizeFlowDocument(
      buildStep,
      assetId,
      plan,
      catalog,
      issues,
    );
    if (issues.isNotEmpty) _surfaceIssues(issues);

    await buildStep.writeAsBytes(
      AssetId(assetId.package, '$_kPaywallOutputDir/$stem.flow.json'),
      FlowDocumentCodec.encodeCanonicalJson(document),
    );
  }
}

Future<FlowDocument> _synthesizeFlowDocument(
  BuildStep buildStep,
  AssetId sourceId,
  _NavigationPlan plan,
  Catalog catalog,
  List<Issue> issues,
) async {
  final entryScreen = _screenIdFor(plan.entryId);

  // Depth-1 only. A pushed screen that itself navigates (it has its own
  // navigation plan) would make this a depth > 1 flow, which this increment
  // does not lower. Its nested push event has no transition in this entry
  // flow, so synthesizing it anyway would silently drop the deeper screen's
  // navigation — fatal-defer instead. (The pushed screen still lowers to its
  // own depth-1 flow independently.) Checked BEFORE reading the screen blobs
  // so a depth > 1 defer does not waste blob I/O.
  for (final transition in plan.transitions) {
    final pushedNavPlan = AssetId(
      sourceId.package,
      '$_kPaywallOutputDir/${transition.pushedId}.navplan.json',
    );
    if (await buildStep.canRead(pushedNavPlan)) {
      issues.add(
        Issue(
          code: IssueCode.navigationFormUnsupported,
          message: 'Screen navigation deeper than one level is not supported '
              'in this increment: the pushed screen "${transition.pushedId}" '
              'itself navigates. Flatten the navigation, or defer the deeper '
              'screen.',
          location: sourceId.path,
        ),
      );
    }
  }
  if (issues.isNotEmpty) {
    return _invalidDocument(plan, entryScreen, const {});
  }

  final screenIds = <String>{
    entryScreen,
    for (final transition in plan.transitions)
      _screenIdFor(transition.pushedId),
  };

  final screenArtifacts = <String, ScreenArtifact>{};
  for (final screenId in screenIds) {
    screenArtifacts[screenId] = await _artifactFor(
      buildStep,
      sourceId,
      screenId,
      catalog,
      issues,
    );
  }
  if (issues.isNotEmpty) {
    return _invalidDocument(plan, entryScreen, screenArtifacts);
  }

  final entryTransitions = <String, FlowTransition>{};
  for (final transition in plan.transitions) {
    if (entryTransitions.containsKey(transition.event)) {
      issues.add(
        Issue(
          code: IssueCode.malformedTranslatorOutput,
          message: 'Navigation plan contains duplicate event '
              '"${transition.event}".',
          location: sourceId.path,
        ),
      );
      continue;
    }
    entryTransitions[transition.event] = FlowTransition.goto(
      _screenIdFor(transition.pushedId),
    );
  }
  if (entryTransitions.containsKey(plan.terminatingEvent)) {
    issues.add(
      Issue(
        code: IssueCode.malformedTranslatorOutput,
        message: 'Navigation plan terminating event '
            '"${plan.terminatingEvent}" conflicts with a push event.',
        location: sourceId.path,
      ),
    );
  } else {
    entryTransitions[plan.terminatingEvent] = const FlowTransition.goto(
      _kDoneState,
    );
  }

  final states = <String, FlowState>{
    entryScreen: ScreenFlowState(screen: entryScreen, on: entryTransitions),
  };
  for (final screenId in screenIds.skip(1)) {
    states[screenId] = ScreenFlowState(screen: screenId, on: const {});
  }
  states[_kDoneState] = const EndFlowState(result: {});

  // The flow as a whole requires whatever its most-demanding screen requires:
  // the max content-version floor across its screens (never below the
  // baseline). A client at the flow floor can render every screen in it.
  final flowFloor = screenArtifacts.values.fold<int>(
    kBaselineCatalogVersion,
    (max, artifact) => artifact.minClient > max ? artifact.minClient : max,
  );

  final document = FlowDocument(
    flow: plan.entryId,
    version: 1,
    schemaVersion: 1,
    minClient: flowFloor,
    initial: entryScreen,
    screenArtifacts: screenArtifacts,
    states: states,
  );

  try {
    FlowDocumentValidation.checkValid(document);
  } on Object catch (error) {
    issues.add(
      Issue(
        code: IssueCode.malformedTranslatorOutput,
        message: 'Generated paywall flow document failed validation: $error',
        location: sourceId.path,
      ),
    );
  }
  return document;
}

Future<ScreenArtifact> _artifactFor(
  BuildStep buildStep,
  AssetId sourceId,
  String screenId,
  Catalog catalog,
  List<Issue> issues,
) async {
  final artifactPath = '$screenId.rfw';
  final rfwId = AssetId(sourceId.package, '$_kScreenOutputDir/$artifactPath');
  if (!await buildStep.canRead(rfwId)) {
    issues.add(
      Issue(
        code: IssueCode.missingScreenDescriptor,
        message: 'Missing paywall screen artifact ${rfwId.path}.',
        location: sourceId.path,
      ),
    );
    // Error path: an issue was raised, so the document is discarded before it
    // is written. The baseline floor here is a placeholder, never shipped.
    return ScreenArtifact(
      path: artifactPath,
      version: 1,
      schemaVersion: 1,
      minClient: kBaselineCatalogVersion,
      contentHash: FlowContentHash.parse(_zeroHash),
    );
  }
  final bytes = await buildStep.readAsBytes(rfwId);
  return ScreenArtifact(
    path: artifactPath,
    version: 1,
    schemaVersion: 1,
    minClient: _deriveScreenFloor(bytes, catalog, sourceId, issues),
    contentHash: FlowContentHash.compute(bytes),
  );
}

/// The capability floor a compiled screen blob declares: the maximum content
/// version over the built-ins the screen references, computed by the same
/// derivation the standalone blob uses so a flow screen and its standalone
/// twin can never disagree on the floor.
///
/// Fail-closed: a blob that cannot be decoded, or whose derivation raises a
/// fatal diagnostic (e.g. a custom library without a declared capability
/// version), surfaces the issue — which discards the document — and falls back
/// to the baseline rather than shipping an under-declared floor.
int _deriveScreenFloor(
  List<int> bytes,
  Catalog catalog,
  AssetId sourceId,
  List<Issue> issues,
) {
  final fmt.RemoteWidgetLibrary library;
  try {
    library = fmt.decodeLibraryBlob(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    );
  } on Object catch (error) {
    issues.add(
      Issue(
        code: IssueCode.malformedTranslatorOutput,
        message: 'Could not decode the compiled screen blob to derive its '
            'capability floor: $error. This is a codegen bug.',
        location: sourceId.path,
      ),
    );
    return kBaselineCatalogVersion;
  }
  final derivation = deriveCapabilityManifest(library, catalog);
  if (derivation.issues.isNotEmpty) {
    issues.addAll(derivation.issues);
    return kBaselineCatalogVersion;
  }
  return derivation.manifest!.builtInFloor;
}

// Returned only when issues were raised, so the caller discards it before any
// write. The baseline floor here is a placeholder for the never-shipped
// document, not a capability claim.
FlowDocument _invalidDocument(
  _NavigationPlan plan,
  String entryScreen,
  Map<String, ScreenArtifact> screenArtifacts,
) {
  return FlowDocument(
    flow: plan.entryId,
    version: 1,
    schemaVersion: 1,
    minClient: kBaselineCatalogVersion,
    initial: entryScreen,
    screenArtifacts: screenArtifacts,
    states: {
      entryScreen: const ScreenFlowState(screen: '', on: {}),
    },
  );
}

_NavigationPlan _decodeNavigationPlan(
  String source,
  AssetId sourceId,
  AssetId navPlanId,
  List<Issue> issues,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException catch (error) {
    issues.add(
      Issue(
        code: IssueCode.malformedTranslatorOutput,
        message: 'Could not decode navigation plan ${navPlanId.path}: $error',
        location: sourceId.path,
      ),
    );
    return _NavigationPlan.invalid();
  }

  if (decoded is! Map<String, Object?>) {
    issues.add(
      Issue(
        code: IssueCode.malformedTranslatorOutput,
        message: 'Navigation plan ${navPlanId.path} must be a JSON object.',
        location: sourceId.path,
      ),
    );
    return _NavigationPlan.invalid();
  }

  final entryId = _stringField(decoded, 'entryId', sourceId, issues);
  final terminatingEvent =
      _stringField(decoded, 'terminatingEvent', sourceId, issues);
  final transitionsValue = decoded['transitions'];
  final transitions = <_NavigationTransition>[];
  if (transitionsValue is List<Object?>) {
    for (final (index, value) in transitionsValue.indexed) {
      if (value is! Map<String, Object?>) {
        issues.add(
          Issue(
            code: IssueCode.malformedTranslatorOutput,
            message: 'Navigation plan transition $index must be an object.',
            location: sourceId.path,
          ),
        );
        continue;
      }
      final event = _stringField(value, 'event', sourceId, issues);
      final pushedId = _stringField(value, 'pushedId', sourceId, issues);
      transitions.add(_NavigationTransition(event: event, pushedId: pushedId));
    }
  } else {
    issues.add(
      Issue(
        code: IssueCode.malformedTranslatorOutput,
        message: 'Navigation plan transitions must be a list.',
        location: sourceId.path,
      ),
    );
  }

  return _NavigationPlan(
    entryId: entryId,
    transitions: transitions,
    terminatingEvent: terminatingEvent,
  );
}

String _stringField(
  Map<String, Object?> json,
  String field,
  AssetId sourceId,
  List<Issue> issues,
) {
  final value = json[field];
  if (value is String && value.isNotEmpty) return value;
  issues.add(
    Issue(
      code: IssueCode.malformedTranslatorOutput,
      message: 'Navigation plan field "$field" must be a non-empty string.',
      location: sourceId.path,
    ),
  );
  return '_invalid';
}

String _screenIdFor(String paywallId) => 'paywall_$paywallId';

Never _surfaceIssues(List<Issue> issues) {
  for (final issue in issues) {
    log.severe(issue.toLogString());
  }
  throw StateError(
    '${issues.length} codegen issue(s) detected; see log above.',
  );
}

final class _NavigationPlan {
  _NavigationPlan({
    required this.entryId,
    required List<_NavigationTransition> transitions,
    required this.terminatingEvent,
  }) : transitions = List.unmodifiable(transitions);

  _NavigationPlan.invalid()
      : entryId = '_invalid',
        transitions = const [],
        terminatingEvent = '_invalid';

  final String entryId;
  final List<_NavigationTransition> transitions;
  final String terminatingEvent;
}

final class _NavigationTransition {
  const _NavigationTransition({required this.event, required this.pushedId});

  final String event;
  final String pushedId;
}
