import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show CanonicalJsonCodec;
import 'package:restage_shared/flow_experiment.dart';
import 'package:restage_shared/src/capability/blob_render_capability_gate.dart';
import 'package:restage_shared/src/capability/capability_manifest.dart';
import 'package:restage_shared/src/capability/installed_capability.dart';
import 'package:restage_shared/src/capability/library_compatibility.dart';
import 'package:restage_shared/src/capability/widget_vocabulary.dart';
import 'package:restage_shared/src/flow_document/flow_action_schema.dart';
import 'package:restage_shared/src/flow_document/flow_document.dart';
import 'package:restage_shared/src/surface_contract/surface_contract_json.dart';
import 'package:restage_shared/src/surface_contract/surface_screen_event_schema.dart';
import 'package:restage_shared/src/surface_contract/surface_screen_host_data_schema.dart';

/// The exact content kind supported by a mount.
enum SurfaceContentKindV1 {
  /// One screen.
  single,

  /// A flow managed by the flow runtime.
  flow,
}

/// The presentation ownership of a mount.
enum SurfacePresentationV1 {
  /// An in-tree mount owned by the application.
  inline,

  /// An SDK-owned presented route.
  presented,
}

/// The actual hosting facts of a mount.
@immutable
final class SurfaceHostingV1 {
  /// Creates the mount's exact hosting facts.
  const SurfaceHostingV1({
    required this.contentKind,
    required this.presentation,
  });

  /// Decodes exact hosting metadata.
  factory SurfaceHostingV1.fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, r'$.hosting');
    SurfaceContractJson.exactKeys(
      json,
      const {'contentKind', 'presentation'},
      r'$.hosting',
    );
    return SurfaceHostingV1(
      contentKind: _enumValue(
        SurfaceContentKindV1.values,
        SurfaceContractJson.requiredString(json, 'contentKind', r'$.hosting'),
        (value) => value.name,
      ),
      presentation: _enumValue(
        SurfacePresentationV1.values,
        SurfaceContractJson.requiredString(json, 'presentation', r'$.hosting'),
        (value) => value.name,
      ),
    );
  }

  /// The mount's content kind.
  final SurfaceContentKindV1 contentKind;

  /// The mount's presentation ownership.
  final SurfacePresentationV1 presentation;

  /// Canonical shape with no runtime host values.
  Map<String, Object?> toJson() => {
        'contentKind': contentKind.name,
        'presentation': presentation.name,
      };

  /// Canonical shape bytes.
  Uint8List get canonicalBytes => CanonicalJsonCodec.encode(toJson());

  /// Hash of this exact hosting shape.
  String get contentHash => _shapeHash('surface-hosting', canonicalBytes);
}

/// Publication-proven hosting modes accepted by a candidate.
@immutable
final class SurfaceHostingRequirementV1 {
  /// Creates a requirement with at least one proven presentation mode.
  factory SurfaceHostingRequirementV1({
    required SurfaceContentKindV1 contentKind,
    required Set<SurfacePresentationV1> allowedPresentations,
  }) {
    if (allowedPresentations.isEmpty) {
      throw const FormatException(
        'A hosting requirement needs a presentation.',
      );
    }
    return SurfaceHostingRequirementV1._(
      contentKind,
      Set.unmodifiable(
        SurfacePresentationV1.values.where(allowedPresentations.contains),
      ),
    );
  }

  const SurfaceHostingRequirementV1._(
    this.contentKind,
    this.allowedPresentations,
  );

  /// Decodes an explicit, nonempty presentation proof.
  factory SurfaceHostingRequirementV1.fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, r'$.hosting');
    SurfaceContractJson.exactKeys(
      json,
      const {'contentKind', 'allowedPresentations'},
      r'$.hosting',
    );
    final rawModes = SurfaceContractJson.requireList(
      SurfaceContractJson.requiredValue(
        json,
        'allowedPresentations',
        r'$.hosting',
      ),
      r'$.hosting.allowedPresentations',
    );
    final modes = <SurfacePresentationV1>{};
    for (final raw in rawModes) {
      final mode = _enumValue(
        SurfacePresentationV1.values,
        raw,
        (value) => value.name,
      );
      if (!modes.add(mode)) {
        throw const FormatException('Duplicate allowed presentation.');
      }
    }
    return SurfaceHostingRequirementV1(
      contentKind: _enumValue(
        SurfaceContentKindV1.values,
        SurfaceContractJson.requiredString(json, 'contentKind', r'$.hosting'),
        (value) => value.name,
      ),
      allowedPresentations: modes,
    );
  }

  /// The candidate's exact content kind.
  final SurfaceContentKindV1 contentKind;

  /// The immutable set of publication-proven presentation modes.
  final Set<SurfacePresentationV1> allowedPresentations;

  /// Canonical requirement metadata.
  Map<String, Object?> toJson() => {
        'contentKind': contentKind.name,
        'allowedPresentations': [
          for (final mode in allowedPresentations) mode.name,
        ],
      };

  /// Canonical shape bytes.
  Uint8List get canonicalBytes => CanonicalJsonCodec.encode(toJson());

  /// Hash of this hosting requirement.
  String get contentHash =>
      _shapeHash('surface-hosting-requirement', canonicalBytes);
}

/// Whether an actual mount is in the candidate's proven hosting set.
bool surfaceHostingFits(
  SurfaceHostingV1 host,
  SurfaceHostingRequirementV1 requirement,
) =>
    host.contentKind == requirement.contentKind &&
    requirement.allowedPresentations.contains(host.presentation);

/// The external field names and types of flow outbound declarations.
///
/// Source references belong to the flow implementation and are excluded.
@immutable
final class FlowHostOutboundShapeV1 {
  /// Creates an immutable external outbound shape.
  factory FlowHostOutboundShapeV1({
    Map<String, Map<String, FlowDataType>> actionArgs = const {},
    Map<String, FlowDataType> terminalResult = const {},
    Map<String, FlowDataType> lifecycle = const {},
    Map<String, FlowDataType> surveyAnswers = const {},
    Map<String, FlowDataType> subFlowResult = const {},
    Map<String, Map<String, FlowDataType>> customEvents = const {},
  }) =>
      FlowHostOutboundShapeV1._(
        actionArgs: _freezeTypeMaps(actionArgs),
        terminalResult: _freezeTypes(terminalResult),
        lifecycle: _freezeTypes(lifecycle),
        surveyAnswers: _freezeTypes(surveyAnswers),
        subFlowResult: _freezeTypes(subFlowResult),
        customEvents: _freezeTypeMaps(customEvents),
      );

  const FlowHostOutboundShapeV1._({
    required this.actionArgs,
    required this.terminalResult,
    required this.lifecycle,
    required this.surveyAnswers,
    required this.subFlowResult,
    required this.customEvents,
  });

  /// Projects validated declarations without retaining source references.
  factory FlowHostOutboundShapeV1.fromDeclarations(
    FlowOutboundDeclarations declarations,
  ) =>
      FlowHostOutboundShapeV1(
        actionArgs: {
          for (final entry in declarations.actionArgs.entries)
            entry.key: _payloadTypes(entry.value),
        },
        terminalResult: _payloadTypes(declarations.terminalResult),
        lifecycle: _payloadTypes(declarations.lifecycle),
        surveyAnswers: _payloadTypes(declarations.surveyAnswers),
        subFlowResult: _payloadTypes(declarations.subFlowResult),
        customEvents: {
          for (final entry in declarations.customEvents.entries)
            entry.key: _payloadTypes(entry.value),
        },
      );

  /// Decodes every external category strictly.
  factory FlowHostOutboundShapeV1.fromJson(Object? value) {
    final json = SurfaceContractJson.requireObject(value, r'$.outbound');
    SurfaceContractJson.exactKeys(
      json,
      const {
        'actionArgs',
        'terminalResult',
        'lifecycle',
        'surveyAnswers',
        'subFlowResult',
        'customEvents',
      },
      r'$.outbound',
    );
    return FlowHostOutboundShapeV1(
      actionArgs: _decodeTypeMaps(json['actionArgs']),
      terminalResult: _decodeTypes(json['terminalResult']),
      lifecycle: _decodeTypes(json['lifecycle']),
      surveyAnswers: _decodeTypes(json['surveyAnswers']),
      subFlowResult: _decodeTypes(json['subFlowResult']),
      customEvents: _decodeTypeMaps(json['customEvents']),
    );
  }

  /// Outbound action argument fields per action.
  final Map<String, Map<String, FlowDataType>> actionArgs;

  /// Terminal result fields.
  final Map<String, FlowDataType> terminalResult;

  /// Lifecycle fields.
  final Map<String, FlowDataType> lifecycle;

  /// Survey answer fields.
  final Map<String, FlowDataType> surveyAnswers;

  /// Subflow result fields.
  final Map<String, FlowDataType> subFlowResult;

  /// Custom event fields per signal.
  final Map<String, Map<String, FlowDataType>> customEvents;

  /// The canonical projection; it contains no outbound source references.
  Map<String, Object?> toJson() => {
        'actionArgs': _typeMapsJson(actionArgs),
        'terminalResult': _typesJson(terminalResult),
        'lifecycle': _typesJson(lifecycle),
        'surveyAnswers': _typesJson(surveyAnswers),
        'subFlowResult': _typesJson(subFlowResult),
        'customEvents': _typeMapsJson(customEvents),
      };

  /// Canonical shape bytes.
  Uint8List get canonicalBytes => CanonicalJsonCodec.encode(toJson());

  /// Hash of the external outbound shape.
  String get contentHash => _shapeHash('flow-host-outbound', canonicalBytes);
}

/// A flow's immutable host ABI, independent of its ID and internal topology.
@immutable
final class FlowHostBoundaryV1 {
  /// Projects only host-seedable facts, action contracts and external egress.
  factory FlowHostBoundaryV1({
    required FlowDeliveryMode deliveryMode,
    required Map<String, FlowStateDeclaration> hostSeedableState,
    required Map<String, FlowActionContract> actions,
    required Set<String> signals,
    required FlowHostOutboundShapeV1 outbound,
  }) {
    final seeds = <String, FlowStateDeclaration>{};
    for (final key in _names(hostSeedableState.keys)) {
      final declaration = hostSeedableState[key]!;
      if (!declaration.hostSeedable) {
        throw FormatException('State "$key" is not host-seedable.');
      }
      seeds[key] = FlowStateDeclaration(
        type: declaration.type,
        classification: declaration.classification,
        hostSeedable: true,
      );
    }
    final frozenActions = <String, FlowActionContract>{};
    for (final key in _names(actions.keys)) {
      final action = _freezeAction(actions[key]!);
      _actionFingerprint(key, action);
      frozenActions[key] = action;
    }
    final boundary = FlowHostBoundaryV1._(
      deliveryMode: deliveryMode,
      hostSeedableState: Map.unmodifiable(seeds),
      actions: Map.unmodifiable(frozenActions),
      signals: Set.unmodifiable(_names(signals)),
      outbound: outbound,
    );
    CanonicalJsonCodec.encode(boundary.toJson());
    return boundary;
  }

  const FlowHostBoundaryV1._({
    required this.deliveryMode,
    required this.hostSeedableState,
    required this.actions,
    required this.signals,
    required this.outbound,
  });

  /// Projects a document after its owning loader has validated its closure.
  ///
  /// Legacy result passthrough has no declared terminal shape and is refused.
  /// This factory does not establish payload, hash or closure integrity.
  factory FlowHostBoundaryV1.fromDocument(
    FlowDocument document, {
    required Set<String> signals,
  }) {
    if (document.legacyTerminalResultPassthrough) {
      throw const FormatException(
        'Result passthrough requires an explicit qualified terminal shape.',
      );
    }
    return FlowHostBoundaryV1(
      deliveryMode: document.deliveryMode,
      hostSeedableState: {
        for (final entry in document.flowState.entries)
          if (entry.value.hostSeedable) entry.key: entry.value,
      },
      actions: document.actions,
      signals: signals,
      outbound: FlowHostOutboundShapeV1.fromDeclarations(document.outbound),
    );
  }

  /// Projects global callbacks and egress from already validated documents.
  ///
  /// Seeds and terminal/subflow results belong to the root interface. The
  /// existing document loader remains responsible for exact closure integrity.
  factory FlowHostBoundaryV1.fromDocuments({
    required FlowDocument root,
    Iterable<FlowDocument> descendants = const [],
  }) {
    final boundaries = [
      for (final document in [root, ...descendants])
        FlowHostBoundaryV1.fromDocument(document,
            signals: document.outbound.customEvents.keys.toSet()),
    ];
    final rootBoundary = boundaries.first;
    final actions = <String, FlowActionContract>{};
    final signals = <String>{};
    for (final boundary in boundaries) {
      if (boundary.deliveryMode != rootBoundary.deliveryMode) {
        throw const FormatException('Conflicting closure delivery modes.');
      }
      signals.addAll(boundary.signals);
      for (final entry in boundary.actions.entries) {
        final prior = actions[entry.key];
        if (prior != null &&
            !SurfaceContractJson.bytesEqual(
              CanonicalJsonCodec.encode(_actionJson(prior)),
              CanonicalJsonCodec.encode(_actionJson(entry.value)),
            )) {
          throw FormatException(
              'Conflicting closure action contract "${entry.key}".');
        }
        actions[entry.key] = entry.value;
      }
    }
    return FlowHostBoundaryV1(
      deliveryMode: rootBoundary.deliveryMode,
      hostSeedableState: rootBoundary.hostSeedableState,
      actions: actions,
      signals: signals,
      outbound: FlowHostOutboundShapeV1(
        terminalResult: rootBoundary.outbound.terminalResult,
        subFlowResult: rootBoundary.outbound.subFlowResult,
        actionArgs: _mergeOutboundTypeMaps(
            boundaries.map((value) => value.outbound.actionArgs)),
        lifecycle: _mergeOutboundTypes(
            boundaries.map((value) => value.outbound.lifecycle)),
        surveyAnswers: _mergeOutboundTypes(
            boundaries.map((value) => value.outbound.surveyAnswers)),
        customEvents: _mergeOutboundTypeMaps(
            boundaries.map((value) => value.outbound.customEvents)),
      ),
    );
  }

  /// Decodes all boundary facts with no internal state or integrity flags.
  factory FlowHostBoundaryV1.fromJson(Object? value) {
    final json = _versionedObject(
      value,
      const {
        'deliveryMode',
        'hostSeedableState',
        'actions',
        'signals',
        'outbound',
      },
      r'$.flowBoundary',
    );
    final rawSeeds = SurfaceContractJson.requireObject(
      json['hostSeedableState'],
      r'$.flowBoundary.hostSeedableState',
    );
    final seeds = <String, FlowStateDeclaration>{};
    for (final entry in rawSeeds.entries) {
      final path = r'$.flowBoundary.hostSeedableState.' + entry.key;
      final declaration = SurfaceContractJson.requireObject(entry.value, path);
      SurfaceContractJson.exactKeys(
        declaration,
        const {'type', 'classification', 'hostSeedable'},
        path,
      );
      if (declaration['hostSeedable'] != true) {
        throw FormatException('State at "$path" must be host-seedable.');
      }
      seeds[entry.key] = FlowStateDeclaration(
        type: _enumValue(
          FlowDataType.values,
          declaration['type'],
          (value) => value.wireName,
        ),
        classification: _enumValue(
          FlowStateClassification.values,
          declaration['classification'],
          (value) => value.wireName,
        ),
        hostSeedable: true,
      );
    }
    final rawActions = SurfaceContractJson.requireObject(
      json['actions'],
      r'$.flowBoundary.actions',
    );
    final signals = _decodeNames(json['signals'], r'$.flowBoundary.signals');
    return FlowHostBoundaryV1(
      deliveryMode: _enumValue(
        FlowDeliveryMode.values,
        json['deliveryMode'],
        (value) => value.wireName,
      ),
      hostSeedableState: seeds,
      actions: {
        for (final entry in rawActions.entries)
          entry.key: _decodeAction(entry.value),
      },
      signals: signals,
      outbound: FlowHostOutboundShapeV1.fromJson(json['outbound']),
    );
  }

  /// Typed or general delivery mode.
  final FlowDeliveryMode deliveryMode;

  /// Host-seedable declarations with defaults excluded.
  final Map<String, FlowStateDeclaration> hostSeedableState;

  /// Exact frozen host action contracts keyed by registry ID.
  final Map<String, FlowActionContract> actions;

  /// Installed host signals, or candidate-required signal names.
  final Set<String> signals;

  /// External outbound names and types.
  final FlowHostOutboundShapeV1 outbound;

  /// Canonical host ABI with no topology, flow identity or runtime values.
  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'deliveryMode': deliveryMode.wireName,
        'hostSeedableState': {
          for (final entry in hostSeedableState.entries)
            entry.key: {
              'type': entry.value.type.wireName,
              'classification': entry.value.classification.wireName,
              'hostSeedable': true,
            },
        },
        'actions': {
          for (final entry in actions.entries)
            entry.key: _actionJson(entry.value),
        },
        'signals': signals.toList(),
        'outbound': outbound.toJson(),
      };

  /// Canonical ABI bytes.
  Uint8List get canonicalBytes => CanonicalJsonCodec.encode(toJson());

  /// Hash of the complete host ABI.
  String get contentHash => _shapeHash('flow-host-boundary', canonicalBytes);
}

/// The immutable contract a mount provides independently of its fallback.
@immutable
final class SurfaceHostContractV1 {
  /// Creates a complete host shape, excluding actual host data values.
  factory SurfaceHostContractV1({
    required SurfaceHostingV1 hosting,
    required SurfaceScreenHostDataSchema providedContext,
    required SurfaceScreenEventSchema handledEvents,
    FlowHostBoundaryV1? flowBoundary,
  }) {
    _checkBoundary(hosting.contentKind, flowBoundary);
    return SurfaceHostContractV1._(
      hosting: hosting,
      providedContextJson: _snapshotObject(providedContext.toJson()),
      handledEvents: SurfaceScreenEventSchemaV1Codec.decode(
        SurfaceScreenEventSchemaV1Codec.encode(handledEvents),
      ),
      flowBoundary: flowBoundary,
    );
  }

  const SurfaceHostContractV1._({
    required this.hosting,
    required Map<String, Object?> providedContextJson,
    required this.handledEvents,
    required this.flowBoundary,
  }) : _providedContextJson = providedContextJson;

  /// Decodes a complete host declaration strictly.
  factory SurfaceHostContractV1.fromJson(Object? value) {
    final json = _versionedObject(
      value,
      const {'hosting', 'providedContext', 'handledEvents', 'flowBoundary'},
      r'$',
    );
    return SurfaceHostContractV1(
      hosting: SurfaceHostingV1.fromJson(json['hosting']),
      providedContext: SurfaceScreenHostDataSchema.fromJson(
        json['providedContext'],
      ),
      handledEvents:
          SurfaceScreenEventSchemaV1Codec.decode(json['handledEvents']),
      flowBoundary: json['flowBoundary'] == null
          ? null
          : FlowHostBoundaryV1.fromJson(json['flowBoundary']),
    );
  }

  /// The mount's exact hosting facts.
  final SurfaceHostingV1 hosting;
  final Map<String, Object?> _providedContextJson;

  /// A detached schema snapshot of the provided context.
  SurfaceScreenHostDataSchema get providedContext =>
      SurfaceScreenHostDataSchema.fromJson(_providedContextJson);

  /// The event handlers the host installs.
  final SurfaceScreenEventSchema handledEvents;

  /// The complete host ABI when this is a flow mount.
  final FlowHostBoundaryV1? flowBoundary;

  /// The canonical mount contract without any particular surface identity.
  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'hosting': hosting.toJson(),
        'providedContext': _providedContextJson,
        'handledEvents': SurfaceScreenEventSchemaV1Codec.encode(handledEvents),
        'flowBoundary': flowBoundary?.toJson(),
      };

  /// Canonical contract bytes.
  Uint8List get canonicalBytes => CanonicalJsonCodec.encode(toJson());

  /// Hash identifying this generated or explicitly declared host contract.
  String get contentHash => hashOfCanonicalBytes(canonicalBytes);

  /// The host contract hash of [bytes], the canonical bytes of a contract.
  static String hashOfCanonicalBytes(List<int> bytes) =>
      _shapeHash('surface-host-contract', bytes);
}

/// Immutable requirements projected from a candidate's complete publication.
///
/// The publication loader must qualify its payload, hashes and reachable
/// closure before creating or using this projection.
@immutable
final class SurfaceFitRequirementV1 {
  /// Creates a complete requirement with explicit empty schemas when unused.
  factory SurfaceFitRequirementV1({
    required SurfaceHostingRequirementV1 hosting,
    required SurfaceScreenHostDataSchema requiredContext,
    required SurfaceScreenEventSchema emittedEvents,
    required CapabilityManifest capabilities,
    required WidgetVocabulary requiredVocabulary,
    FlowHostBoundaryV1? flowBoundary,
  }) {
    _checkBoundary(hosting.contentKind, flowBoundary);
    final manifestJson = SurfaceContractJson.encodeCapabilityManifest(
      capabilities,
      path: r'$.capabilities',
    );
    CanonicalJsonCodec.encode(manifestJson);
    return SurfaceFitRequirementV1._(
      hosting: hosting,
      requiredContextJson: _snapshotObject(requiredContext.toJson()),
      emittedEvents: SurfaceScreenEventSchemaV1Codec.decode(
        SurfaceScreenEventSchemaV1Codec.encode(emittedEvents),
      ),
      capabilities: SurfaceContractJson.decodeCapabilityManifest(
        manifestJson,
        path: r'$.capabilities',
      ),
      requiredVocabulary: _decodeVocabulary(requiredVocabulary.toJson()),
      flowBoundary: flowBoundary,
    );
  }

  const SurfaceFitRequirementV1._({
    required this.hosting,
    required Map<String, Object?> requiredContextJson,
    required this.emittedEvents,
    required this.capabilities,
    required this.requiredVocabulary,
    required this.flowBoundary,
  }) : _requiredContextJson = requiredContextJson;

  /// Decodes every requirement facet with no default for absent metadata.
  factory SurfaceFitRequirementV1.fromJson(Object? value) {
    final json = _versionedObject(
      value,
      const {
        'hosting',
        'requiredContext',
        'emittedEvents',
        'capabilities',
        'requiredVocabulary',
        'flowBoundary',
      },
      r'$',
    );
    return SurfaceFitRequirementV1(
      hosting: SurfaceHostingRequirementV1.fromJson(json['hosting']),
      requiredContext: SurfaceScreenHostDataSchema.fromJson(
        json['requiredContext'],
      ),
      emittedEvents:
          SurfaceScreenEventSchemaV1Codec.decode(json['emittedEvents']),
      capabilities: SurfaceContractJson.decodeCapabilityManifest(
        json['capabilities'],
        path: r'$.capabilities',
      ),
      requiredVocabulary: _decodeVocabulary(json['requiredVocabulary']),
      flowBoundary: json['flowBoundary'] == null
          ? null
          : FlowHostBoundaryV1.fromJson(json['flowBoundary']),
    );
  }

  /// Candidate hosting requirements proven by its producer.
  final SurfaceHostingRequirementV1 hosting;
  final Map<String, Object?> _requiredContextJson;

  /// A detached schema snapshot of every required host context read.
  SurfaceScreenHostDataSchema get requiredContext =>
      SurfaceScreenHostDataSchema.fromJson(_requiredContextJson);

  /// Every event the candidate may emit.
  final SurfaceScreenEventSchema emittedEvents;

  /// Catalog and custom library requirements.
  final CapabilityManifest capabilities;

  /// Exact required widget and icon names.
  final WidgetVocabulary requiredVocabulary;

  /// The projected host boundary for a flow candidate.
  final FlowHostBoundaryV1? flowBoundary;

  /// Canonical requirement metadata without artifact-integrity assertions.
  Map<String, Object?> toJson() => {
        'schemaVersion': 1,
        'hosting': hosting.toJson(),
        'requiredContext': _requiredContextJson,
        'emittedEvents': SurfaceScreenEventSchemaV1Codec.encode(emittedEvents),
        'capabilities': capabilities.toJson(),
        'requiredVocabulary': requiredVocabulary.toJson(),
        'flowBoundary': flowBoundary?.toJson(),
      };

  /// Canonical requirement bytes.
  Uint8List get canonicalBytes => CanonicalJsonCodec.encode(toJson());

  /// Hash of the complete immutable requirement projection.
  String get contentHash =>
      _shapeHash('surface-fit-requirement', canonicalBytes);
}

/// Bounded diagnostic categories for a refused host fit.
enum SurfaceFitFailureCodeV1 {
  /// Content kind or presentation membership differs.
  hostingMismatch,

  /// A required context field is absent.
  missingHostField,

  /// Provided context values exceed the candidate's input shape.
  incompatibleHostField,

  /// An emitted event has no installed handler.
  unhandledEvent,

  /// Emitted argument wrapping or values exceed the handler shape.
  incompatibleEventShape,

  /// The complete installed vocabulary is unknown.
  missingInstalledVocabulary,

  /// A required widget name is absent.
  missingWidget,

  /// A required font-family/code-point pair is absent.
  missingIcon,

  /// A required catalog or action floor is too high.
  builtInFloor,

  /// A custom library is missing or unversioned.
  missingLibrary,

  /// A custom library is too old.
  oldLibrary,

  /// A custom library broke the required version's contract.
  brokenLibrary,

  /// Typed and general delivery modes differ.
  deliveryModeMismatch,

  /// A required action fingerprint or support floor differs.
  actionMismatch,

  /// The candidate cannot preserve a possible host seed.
  seedMismatch,

  /// A required host signal is absent.
  signalMismatch,

  /// The exact typed terminal result keys or types differ.
  resultMismatch,

  /// An external outbound field or payload is unsupported.
  outboundMismatch,

  /// A complete requirement could not be obtained by the caller.
  missingRequirement,

  /// Requirement metadata could not be decoded by the caller.
  malformedRequirement,
}

/// A contract-path diagnostic with immutable required and available shapes.
@immutable
final class SurfaceFitFailureV1 {
  /// Freezes a diagnostic; shape values use the canonical JSON grammar.
  factory SurfaceFitFailureV1({
    required SurfaceFitFailureCodeV1 code,
    required String path,
    required Object? required,
    required Object? available,
  }) {
    _checkName(path);
    return SurfaceFitFailureV1._(
      code,
      path,
      _snapshotJson(required),
      _snapshotJson(available),
    );
  }

  const SurfaceFitFailureV1._(
    this.code,
    this.path,
    this.required,
    this.available,
  );

  /// The bounded failure category.
  final SurfaceFitFailureCodeV1 code;

  /// The contract path that failed.
  final String path;

  /// Required shape or capability, excluding runtime values.
  final Object? required;

  /// Available shape or capability; null when absent.
  final Object? available;
}

/// An accepted fit or a rejection with at least one immutable failure.
@immutable
final class SurfaceFitVerdictV1 {
  /// Accepts a complete fit.
  const SurfaceFitVerdictV1.fits() : failures = const [];

  /// Rejects with at least one cause.
  factory SurfaceFitVerdictV1.doesNotFit(List<SurfaceFitFailureV1> failures) {
    if (failures.isEmpty) {
      throw ArgumentError.value(failures, 'failures', 'must be nonempty');
    }
    return SurfaceFitVerdictV1._(List.unmodifiable(failures));
  }

  const SurfaceFitVerdictV1._(this.failures);

  /// Whether every host boundary and installed capability fits.
  bool get accepted => failures.isEmpty;

  /// Immutable contract failures; empty only for an accepted fit.
  final List<SurfaceFitFailureV1> failures;
}

/// Shared fit authority for a qualified immutable candidate projection.
///
/// Payload/hash/closure integrity and same-surface version lineage remain
/// prerequisites enforced by their existing loader and render-gate owners.
abstract final class SurfaceFitEvaluator {
  /// Checks complete host shapes and installed capabilities directionally.
  static SurfaceFitVerdictV1 evaluate({
    required SurfaceHostContractV1 host,
    required SurfaceFitRequirementV1 requirement,
    required InstalledCapability installed,
  }) {
    final failures = <SurfaceFitFailureV1>[];
    if (!surfaceHostingFits(host.hosting, requirement.hosting)) {
      _fail(
        failures,
        SurfaceFitFailureCodeV1.hostingMismatch,
        r'$.hosting',
        requirement.hosting.toJson(),
        host.hosting.toJson(),
      );
    }
    final provided = host.providedContext.inputs;
    for (final entry in requirement.requiredContext.inputs.entries) {
      final path = r'$.requiredContext.' + entry.key;
      final available = provided[entry.key];
      if (available == null) {
        _fail(
          failures,
          SurfaceFitFailureCodeV1.missingHostField,
          path,
          entry.value.toJson(),
          null,
        );
        continue;
      }
      _checkHostShape(entry.value, available, path, failures);
    }
    final handlers = {
      for (final event in host.handledEvents.events) event.id: event.arguments,
    };
    for (final event in requirement.emittedEvents.events) {
      final handled = handlers[event.id];
      final path = r'$.emittedEvents.' + event.id;
      if (handled == null) {
        _fail(
          failures,
          SurfaceFitFailureCodeV1.unhandledEvent,
          path,
          event.arguments.toJson(),
          null,
        );
      } else if (!_eventArgumentsAccept(handled, event.arguments)) {
        _fail(
          failures,
          SurfaceFitFailureCodeV1.incompatibleEventShape,
          path,
          event.arguments.toJson(),
          handled.toJson(),
        );
      }
    }
    _checkCapabilities(requirement, installed, failures);
    final requiredBoundary = requirement.flowBoundary;
    final hostBoundary = host.flowBoundary;
    if (requiredBoundary != null && hostBoundary != null) {
      _checkFlowBoundary(hostBoundary, requiredBoundary, installed, failures);
    }
    return failures.isEmpty
        ? const SurfaceFitVerdictV1.fits()
        : SurfaceFitVerdictV1.doesNotFit(failures);
  }
}

/// Whether every provided host value belongs to the candidate input shape.
bool hostDataShapeAcceptsProvided(
  SurfaceScreenHostDataShape required,
  SurfaceScreenHostDataShape provided,
) {
  final failures = <SurfaceFitFailureV1>[];
  _checkHostShape(required, provided, r'$', failures);
  return failures.isEmpty;
}

void _checkHostShape(
  SurfaceScreenHostDataShape required,
  SurfaceScreenHostDataShape provided,
  String path,
  List<SurfaceFitFailureV1> failures,
) {
  if (required is SurfaceScreenHostDataScalarShapeV1 &&
      required.kind == SurfaceScreenHostDataScalarKind.jsonValue) {
    return;
  }
  if (required is SurfaceScreenHostDataNullableShapeV1) {
    var accepted = required.value;
    var supplied = provided;
    while (accepted is SurfaceScreenHostDataNullableShapeV1) {
      accepted = accepted.value;
    }
    while (supplied is SurfaceScreenHostDataNullableShapeV1) {
      supplied = supplied.value;
    }
    _checkHostShape(
      accepted,
      supplied,
      path,
      failures,
    );
    return;
  }
  switch ((required, provided)) {
    case (
        SurfaceScreenHostDataScalarShapeV1(kind: final requiredKind),
        SurfaceScreenHostDataScalarShapeV1(kind: final providedKind),
      ):
      if (requiredKind == providedKind ||
          requiredKind == SurfaceScreenHostDataScalarKind.number &&
              (providedKind == SurfaceScreenHostDataScalarKind.integer ||
                  providedKind ==
                      SurfaceScreenHostDataScalarKind.doubleValue)) {
        return;
      }
    case (
        SurfaceScreenHostDataListShapeV1(items: final requiredItems),
        SurfaceScreenHostDataListShapeV1(items: final providedItems),
      ):
      _checkHostShape(requiredItems, providedItems, '$path[]', failures);
      return;
    case (
        SurfaceScreenHostDataMapShapeV1(values: final requiredValues),
        SurfaceScreenHostDataMapShapeV1(values: final providedValues),
      ):
      _checkHostShape(requiredValues, providedValues, '$path.*', failures);
      return;
    case (
        SurfaceScreenHostDataMapShapeV1(values: final requiredValues),
        SurfaceScreenHostDataObjectShapeV1(fields: final providedFields),
      ):
      for (final entry in providedFields.entries) {
        _checkHostShape(
          requiredValues,
          entry.value,
          '$path.${entry.key}',
          failures,
        );
      }
      return;
    case (
        SurfaceScreenHostDataObjectShapeV1(fields: final requiredFields),
        SurfaceScreenHostDataObjectShapeV1(fields: final providedFields),
      ):
      for (final entry in requiredFields.entries) {
        final available = providedFields[entry.key];
        final fieldPath = '$path.${entry.key}';
        if (available == null) {
          _fail(
            failures,
            SurfaceFitFailureCodeV1.missingHostField,
            fieldPath,
            entry.value.toJson(),
            null,
          );
        } else {
          _checkHostShape(entry.value, available, fieldPath, failures);
        }
      }
      return;
    default:
      break;
  }
  _fail(
    failures,
    SurfaceFitFailureCodeV1.incompatibleHostField,
    path,
    required.toJson(),
    provided.toJson(),
  );
}

bool _eventArgumentsAccept(
  SurfaceScreenEventArguments handled,
  SurfaceScreenEventArguments emitted,
) =>
    switch ((handled, emitted)) {
      (SurfaceScreenEventNoArguments(), SurfaceScreenEventNoArguments()) =>
        true,
      (
        SurfaceScreenEventObjectArguments(shape: final accepted),
        SurfaceScreenEventObjectArguments(shape: final provided),
      ) =>
        _eventShapeAccepts(accepted, provided),
      (
        SurfaceScreenEventValueArguments(shape: final accepted),
        SurfaceScreenEventValueArguments(shape: final provided),
      ) =>
        _eventShapeAccepts(accepted, provided),
      _ => false,
    };

bool _eventShapeAccepts(
  SurfaceScreenEventShape handled,
  SurfaceScreenEventShape emitted,
) {
  if (handled is SurfaceScreenEventScalarShapeV1 &&
      handled.kind == SurfaceScreenEventScalarKind.jsonValue) {
    return true;
  }
  if (handled is SurfaceScreenEventNullableShapeV1) {
    var accepted = handled.value;
    var supplied = emitted;
    while (accepted is SurfaceScreenEventNullableShapeV1) {
      accepted = accepted.value;
    }
    while (supplied is SurfaceScreenEventNullableShapeV1) {
      supplied = supplied.value;
    }
    return _eventShapeAccepts(
      accepted,
      supplied,
    );
  }
  return switch ((handled, emitted)) {
    (
      SurfaceScreenEventScalarShapeV1(kind: final accepted),
      SurfaceScreenEventScalarShapeV1(kind: final provided),
    ) =>
      accepted == provided,
    (
      SurfaceScreenEventListShapeV1(items: final accepted),
      SurfaceScreenEventListShapeV1(items: final provided),
    ) =>
      _eventShapeAccepts(accepted, provided),
    (
      SurfaceScreenEventMapShapeV1(values: final accepted),
      SurfaceScreenEventMapShapeV1(values: final provided),
    ) =>
      _eventShapeAccepts(accepted, provided),
    _ => false,
  };
}

void _checkCapabilities(
  SurfaceFitRequirementV1 requirement,
  InstalledCapability installed,
  List<SurfaceFitFailureV1> failures,
) {
  final manifest = requirement.capabilities;
  final verdict = BlobRenderCapabilityGate.evaluate(
    required: manifest,
    installed: installed,
  );
  if (verdict is BlobRenderRejected &&
      verdict.reason == BlobRenderRejectionReason.capabilityFloorRaised) {
    _fail(
      failures,
      SurfaceFitFailureCodeV1.builtInFloor,
      r'$.capabilities.builtInFloor',
      manifest.builtInFloor,
      installed.builtInCatalogVersion,
    );
  }
  for (final library in manifest.requiredLibraries) {
    final actual = installed.libraryOf(library.namespace);
    final compatibility = LibraryCompatibility.evaluate(actual, library);
    if (compatibility == LibraryCompatibility.satisfied) continue;
    final code = switch (compatibility) {
      LibraryCompatibility.missing => SurfaceFitFailureCodeV1.missingLibrary,
      LibraryCompatibility.tooOld => SurfaceFitFailureCodeV1.oldLibrary,
      LibraryCompatibility.contractBroken =>
        SurfaceFitFailureCodeV1.brokenLibrary,
      LibraryCompatibility.satisfied => throw StateError('Already satisfied.'),
    };
    _fail(
      failures,
      code,
      r'$.capabilities.requiredLibraries.' + library.namespace,
      library.toJson(),
      actual?.toJson(),
    );
  }
  final vocabulary = installed.vocabulary;
  if (vocabulary == null) {
    _fail(
      failures,
      SurfaceFitFailureCodeV1.missingInstalledVocabulary,
      r'$.requiredVocabulary',
      requirement.requiredVocabulary.toJson(),
      null,
    );
    return;
  }
  final required = requirement.requiredVocabulary;
  if (vocabulary.containsAll(required)) return;
  for (final widget
      in required.widgetNames.difference(vocabulary.widgetNames)) {
    _fail(
      failures,
      SurfaceFitFailureCodeV1.missingWidget,
      r'$.requiredVocabulary.widgetNames',
      widget,
      null,
    );
  }
  for (final entry in required.iconCodePoints.entries) {
    final available = vocabulary.iconCodePoints[entry.key] ?? const <int>{};
    for (final codePoint in entry.value.difference(available)) {
      _fail(
        failures,
        SurfaceFitFailureCodeV1.missingIcon,
        r'$.requiredVocabulary.iconCodePoints.' + entry.key,
        codePoint,
        null,
      );
    }
  }
}

void _checkFlowBoundary(
  FlowHostBoundaryV1 host,
  FlowHostBoundaryV1 required,
  InstalledCapability installed,
  List<SurfaceFitFailureV1> failures,
) {
  if (host.deliveryMode != required.deliveryMode) {
    _fail(
      failures,
      SurfaceFitFailureCodeV1.deliveryModeMismatch,
      r'$.flowBoundary.deliveryMode',
      required.deliveryMode.wireName,
      host.deliveryMode.wireName,
    );
  }
  for (final entry in required.actions.entries) {
    final actual = host.actions[entry.key];
    if (!flowActionBindingSatisfiesContract(
      installed: actual == null ? null : _actionFingerprint(entry.key, actual),
      required: entry.value,
    )) {
      _fail(
        failures,
        SurfaceFitFailureCodeV1.actionMismatch,
        r'$.flowBoundary.actions.' + entry.key,
        _actionJson(entry.value),
        actual == null ? null : _actionJson(actual),
      );
    }
    if (entry.value.minClient > installed.builtInCatalogVersion) {
      _fail(
        failures,
        SurfaceFitFailureCodeV1.builtInFloor,
        r'$.flowBoundary.actions.' '${entry.key}.minClient',
        entry.value.minClient,
        installed.builtInCatalogVersion,
      );
    }
  }
  // A generated mount may seed any of its declared keys, even if the fallback
  // never needs them. A replacement must still accept every possible seed.
  for (final entry in host.hostSeedableState.entries) {
    final candidate = required.hostSeedableState[entry.key];
    if (candidate == null || candidate.type != entry.value.type) {
      _fail(
        failures,
        SurfaceFitFailureCodeV1.seedMismatch,
        r'$.flowBoundary.hostSeedableState.' + entry.key,
        entry.value.type.wireName,
        candidate?.type.wireName,
      );
    }
  }
  final signals = <String>{
    ...required.signals,
    ...required.outbound.customEvents.keys,
  }.toList()
    ..sort(SurfaceContractJson.compareUtf8);
  for (final signal in signals) {
    if (!host.signals.contains(signal)) {
      _fail(
        failures,
        SurfaceFitFailureCodeV1.signalMismatch,
        r'$.flowBoundary.signals',
        signal,
        null,
      );
    }
  }
  if (required.deliveryMode == FlowDeliveryMode.typed) {
    _checkExactResult(
      host.outbound.terminalResult,
      required.outbound.terminalResult,
      failures,
    );
  } else {
    _checkOutboundFields(
      host.outbound.terminalResult,
      required.outbound.terminalResult,
      r'$.flowBoundary.outbound.terminalResult',
      failures,
    );
  }
  _checkOutboundFields(
    host.outbound.lifecycle,
    required.outbound.lifecycle,
    r'$.flowBoundary.outbound.lifecycle',
    failures,
  );
  _checkOutboundFields(
    host.outbound.surveyAnswers,
    required.outbound.surveyAnswers,
    r'$.flowBoundary.outbound.surveyAnswers',
    failures,
  );
  _checkOutboundFields(
    host.outbound.subFlowResult,
    required.outbound.subFlowResult,
    r'$.flowBoundary.outbound.subFlowResult',
    failures,
  );
  _checkOutboundMaps(
    host.outbound.actionArgs,
    required.outbound.actionArgs,
    r'$.flowBoundary.outbound.actionArgs',
    failures,
  );
  _checkOutboundMaps(
    host.outbound.customEvents,
    required.outbound.customEvents,
    r'$.flowBoundary.outbound.customEvents',
    failures,
  );
}

void _checkExactResult(
  Map<String, FlowDataType> host,
  Map<String, FlowDataType> emitted,
  List<SurfaceFitFailureV1> failures,
) {
  if (host.length == emitted.length &&
      emitted.entries.every((entry) => host[entry.key] == entry.value)) {
    return;
  }
  _fail(
    failures,
    SurfaceFitFailureCodeV1.resultMismatch,
    r'$.flowBoundary.outbound.terminalResult',
    _typesJson(emitted),
    _typesJson(host),
  );
}

void _checkOutboundFields(
  Map<String, FlowDataType> host,
  Map<String, FlowDataType> emitted,
  String path,
  List<SurfaceFitFailureV1> failures,
) {
  for (final entry in emitted.entries) {
    if (host[entry.key] != entry.value) {
      _fail(
        failures,
        SurfaceFitFailureCodeV1.outboundMismatch,
        '$path.${entry.key}',
        entry.value.wireName,
        host[entry.key]?.wireName,
      );
    }
  }
}

void _checkOutboundMaps(
  Map<String, Map<String, FlowDataType>> host,
  Map<String, Map<String, FlowDataType>> emitted,
  String path,
  List<SurfaceFitFailureV1> failures,
) {
  for (final entry in emitted.entries) {
    final available = host[entry.key];
    if (available == null) {
      _fail(
        failures,
        SurfaceFitFailureCodeV1.outboundMismatch,
        '$path.${entry.key}',
        _typesJson(entry.value),
        null,
      );
    } else {
      _checkOutboundFields(
        available,
        entry.value,
        '$path.${entry.key}',
        failures,
      );
    }
  }
}

void _fail(
  List<SurfaceFitFailureV1> failures,
  SurfaceFitFailureCodeV1 code,
  String path,
  Object? required,
  Object? available,
) {
  failures.add(
    SurfaceFitFailureV1(
      code: code,
      path: path,
      required: required,
      available: available,
    ),
  );
}

void _checkBoundary(SurfaceContentKindV1 kind, FlowHostBoundaryV1? boundary) {
  if ((kind == SurfaceContentKindV1.flow) != (boundary != null)) {
    throw const FormatException(
      'Exactly flow content requires a flow boundary.',
    );
  }
}

Map<String, Object?> _versionedObject(
  Object? value,
  Set<String> fields,
  String path,
) {
  final json = SurfaceContractJson.requireObject(value, path);
  SurfaceContractJson.exactKeys(json, {'schemaVersion', ...fields}, path);
  if (SurfaceContractJson.requiredInt(json, 'schemaVersion', path) != 1) {
    throw FormatException('Unsupported schemaVersion at "$path".');
  }
  return json;
}

T _enumValue<T>(List<T> values, Object? wire, String Function(T) name) {
  for (final value in values) {
    if (name(value) == wire) return value;
  }
  throw FormatException('Unsupported discriminator "$wire".');
}

void _checkName(String name) {
  SurfaceContractJson.requireUnicodeScalars(name, 'contract name');
  if (name.isEmpty) {
    throw const FormatException('Contract names cannot be empty.');
  }
}

List<String> _names(Iterable<String> names) {
  return names.toList()
    ..forEach(_checkName)
    ..sort(SurfaceContractJson.compareUtf8);
}

Set<String> _decodeNames(Object? value, String path) {
  final names = <String>{};
  for (final raw in SurfaceContractJson.requireList(value, path)) {
    if (raw is! String || !names.add(raw)) {
      throw FormatException('Expected distinct string names at "$path".');
    }
    _checkName(raw);
  }
  return names;
}

Map<String, FlowDataType> _payloadTypes(
  FlowOutboundPayloadDeclaration payload,
) =>
    {for (final entry in payload.fields.entries) entry.key: entry.value.type};

Map<String, FlowDataType> _freezeTypes(Map<String, FlowDataType> fields) =>
    Map.unmodifiable(
      {for (final key in _names(fields.keys)) key: fields[key]},
    );

Map<String, Map<String, FlowDataType>> _freezeTypeMaps(
  Map<String, Map<String, FlowDataType>> payloads,
) =>
    Map.unmodifiable({
      for (final key in _names(payloads.keys))
        key: _freezeTypes(payloads[key]!),
    });

Map<String, Object?> _typesJson(Map<String, FlowDataType> fields) => {
      for (final entry in fields.entries) entry.key: entry.value.wireName,
    };

Map<String, Object?> _typeMapsJson(
  Map<String, Map<String, FlowDataType>> payloads,
) =>
    {for (final entry in payloads.entries) entry.key: _typesJson(entry.value)};

Map<String, FlowDataType> _decodeTypes(Object? value) {
  final json = SurfaceContractJson.requireObject(value, r'$.outbound.fields');
  return {
    for (final entry in json.entries)
      entry.key: _enumValue(
        FlowDataType.values,
        entry.value,
        (value) => value.wireName,
      ),
  };
}

Map<String, Map<String, FlowDataType>> _decodeTypeMaps(Object? value) {
  final json = SurfaceContractJson.requireObject(value, r'$.outbound.payloads');
  return {
    for (final entry in json.entries) entry.key: _decodeTypes(entry.value),
  };
}

Map<String, FlowDataType> _mergeOutboundTypes(
  Iterable<Map<String, FlowDataType>> values,
) {
  final merged = <String, FlowDataType>{};
  for (final fields in values) {
    for (final entry in fields.entries) {
      if (merged.containsKey(entry.key) && merged[entry.key] != entry.value) {
        throw FormatException(
            'Conflicting closure outbound field "${entry.key}".');
      }
      merged[entry.key] = entry.value;
    }
  }
  return merged;
}

Map<String, Map<String, FlowDataType>> _mergeOutboundTypeMaps(
  Iterable<Map<String, Map<String, FlowDataType>>> values,
) {
  final merged = <String, Map<String, FlowDataType>>{};
  for (final maps in values) {
    for (final entry in maps.entries) {
      merged[entry.key] =
          _mergeOutboundTypes([merged[entry.key] ?? {}, entry.value]);
    }
  }
  return merged;
}

FlowActionBindingFingerprint _actionFingerprint(
  String id,
  FlowActionContract action,
) =>
    FlowActionBindingFingerprint(
      actionId: id,
      actionName: action.actionName,
      contractVersion: action.contractVersion,
      argsSchemaHash: action.argsSchemaHash,
      resultSchemaHash: action.resultSchemaHash,
      minClient: action.minClient,
      idempotent: action.idempotent,
    );

Map<String, Object?> _actionJson(FlowActionContract action) => {
      'actionName': action.actionName,
      'contractVersion': action.contractVersion,
      'argsSchema': FlowActionSchema.toJson(action.argsSchema),
      'resultSchema': FlowActionSchema.toJson(action.resultSchema),
      'minClient': action.minClient,
      'idempotent': action.idempotent,
    };

FlowActionContract _decodeAction(Object? value) {
  final json = SurfaceContractJson.requireObject(value, r'$.actions');
  SurfaceContractJson.exactKeys(
    json,
    const {
      'actionName',
      'contractVersion',
      'argsSchema',
      'resultSchema',
      'minClient',
      'idempotent',
    },
    r'$.actions',
  );
  final idempotent = json['idempotent'];
  if (idempotent is! bool) {
    throw const FormatException('Action idempotency must be explicit.');
  }
  return FlowActionContract(
    actionName:
        SurfaceContractJson.requiredString(json, 'actionName', r'$.actions'),
    contractVersion: SurfaceContractJson.requiredPositiveInt(
      json,
      'contractVersion',
      r'$.actions',
    ),
    argsSchema: FlowActionSchema.fromJson(
      SurfaceContractJson.requireObject(
        json['argsSchema'],
        r'$.actions.args',
      ),
    ),
    resultSchema: FlowActionSchema.fromJson(
      SurfaceContractJson.requireObject(
        json['resultSchema'],
        r'$.actions.result',
      ),
    ),
    minClient: SurfaceContractJson.requiredPositiveInt(
      json,
      'minClient',
      r'$.actions',
    ),
    idempotent: idempotent,
  );
}

FlowActionContract _freezeAction(FlowActionContract action) {
  final validated = _decodeAction(_actionJson(action));
  return FlowActionContract(
    actionName: validated.actionName,
    contractVersion: validated.contractVersion,
    argsSchema: _freezeActionSchema(validated.argsSchema),
    resultSchema: _freezeActionSchema(validated.resultSchema),
    minClient: validated.minClient,
    idempotent: validated.idempotent,
  );
}

FlowActionSchema _freezeActionSchema(FlowActionSchema schema) =>
    switch (schema) {
      FlowObjectActionSchema(:final fields) => FlowActionSchema.object(
          Map.unmodifiable({
            for (final key in _names(fields.keys))
              key: FlowActionSchemaField(
                required: fields[key]!.required,
                schema: _freezeActionSchema(fields[key]!.schema),
              ),
          }),
        ),
      FlowEnumActionSchema(:final values) =>
        FlowActionSchema.enumValues(List.unmodifiable(values)),
      FlowListActionSchema(:final child) =>
        FlowActionSchema.list(_freezeActionSchema(child)),
      FlowNullableActionSchema(:final child) =>
        FlowActionSchema.nullable(_freezeActionSchema(child)),
      _ => schema,
    };

WidgetVocabulary _decodeVocabulary(Object? value) {
  final json =
      SurfaceContractJson.requireObject(value, r'$.requiredVocabulary');
  SurfaceContractJson.exactKeys(
    json,
    const {'widgetNames', 'iconCodePoints'},
    r'$.requiredVocabulary',
  );
  _decodeNames(json['widgetNames'], r'$.requiredVocabulary.widgetNames');
  final families = SurfaceContractJson.requireObject(
    json['iconCodePoints'],
    r'$.requiredVocabulary.iconCodePoints',
  );
  for (final entry in families.entries) {
    _checkName(entry.key);
    final points = <int>{};
    for (final point in SurfaceContractJson.requireList(
      entry.value,
      r'$.requiredVocabulary.iconCodePoints.' + entry.key,
    )) {
      if (point is! int || !points.add(point)) {
        throw const FormatException(
          'Expected distinct integer icon code points.',
        );
      }
    }
  }
  CanonicalJsonCodec.encode(json);
  return WidgetVocabulary.fromJson(Map<String, dynamic>.from(json));
}

Map<String, Object?> _snapshotObject(Object? value) =>
    _snapshotJson(value)! as Map<String, Object?>;

Object? _snapshotJson(Object? value) =>
    _freezeJson(CanonicalJsonCodec.decode(CanonicalJsonCodec.encode(value)));

Object? _freezeJson(Object? value) => switch (value) {
      Map<String, Object?>() => Map<String, Object?>.unmodifiable({
          for (final entry in value.entries)
            entry.key: _freezeJson(entry.value),
        }),
      List<Object?>() => List<Object?>.unmodifiable(value.map(_freezeJson)),
      _ => value,
    };

String _shapeHash(String domain, List<int> bytes) => SurfaceContractJson.hash(
      [...utf8.encode('restage.$domain.v1\n'), ...bytes],
    );
