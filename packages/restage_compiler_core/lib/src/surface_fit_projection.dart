import 'package:restage_compiler_core/src/rfw_catalog_occurrence_resolution.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/flow_experiment.dart' as flow;
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;

/// Projects what a verified publication closure asks of its host app.
extension SurfaceFitProjection on SurfacePublicationArtifactClosure {
  /// Projects replacement requirements from this complete artifact closure.
  ///
  /// Typed source facts are rebound to every final blob. The existing flow
  /// closure owner validates descendant identity and hashes before aggregation.
  SurfaceFitRequirementV1 projectFitRequirement({
    List<SurfacePublicationArtifactClosure> subflows = const [],
  }) {
    final nodes = [this, ...subflows];
    final rootDocument = flowDocument;
    if (rootDocument == null && subflows.isNotEmpty) {
      throw const FormatException('Unrelated subflow fit contracts.');
    }
    if (rootDocument != null) {
      flow.FlowExperimentDocumentContract.checkCompleteClosure(
        surfaceType: publication.surface,
        deliveryMode: rootDocument.deliveryMode,
        descriptor: flow.FlowExperimentDescriptor(
          id: rootDocument.flow,
          version: rootDocument.version,
          minClient: rootDocument.minClient,
        ),
        documents: [
          for (final node in nodes)
            flow.FlowExperimentDocumentContract(
              surfaceType: node.publication.surface,
              flowId: node.flowDocument!.flow,
              version: node.flowDocument!.version,
              schemaVersion: node.flowDocument!.schemaVersion,
              minClient: node.flowDocument!.minClient,
              contentHash: FlowContentHash.compute(
                FlowDocumentCodec.encodeCanonicalJson(node.flowDocument!),
              ),
              requiredLibraries:
                  capabilityManifestUnion(node.sidecarCapabilities.values)
                      .requiredLibraries,
              flowDocument: node.flowDocument!,
            ),
        ],
      );
    }
    final context = <String, SurfaceScreenHostDataShape>{};
    final events = <String, SurfaceScreenEvent>{};
    var vocabulary = WidgetVocabulary();
    final modes = SurfacePresentationV1.values.toSet();
    final manifests = <CapabilityManifest>[];
    for (final node in nodes) {
      final contracts = node.publication.compiledScreenContracts;
      final blobHashes =
          node.screenBlobs.values.map(CapabilitySidecar.hashBlob).toSet();
      if (contracts.length != blobHashes.length ||
          !blobHashes.containsAll(contracts.keys)) {
        throw const FormatException(
          r'$.publication.compiledScreenContracts: missing exact final '
          'screen contracts.',
        );
      }
      if (node.publication.declaredPresentation case final mode?) {
        modes.retainAll({mode});
      }
      final document = node.flowDocument;
      if (document != null) {
        manifests.add(
          CapabilityManifest(
            builtInFloor: document.minClient,
            requiredLibraries: const [],
          ),
        );
      }
      manifests.addAll(node.sidecarCapabilities.values);
      for (final entry in node.screenBlobs.entries) {
        final contract = contracts[CapabilitySidecar.hashBlob(entry.value)]!;
        final renderRoot = node.flowDocument == null &&
                node.publication.sourceKind == SurfaceSourceKind.paywall
            ? 'Paywall'
            : 'OnboardingScreen';
        if (contract.catalogResolution.renderEntryNames.length != 1 ||
            !contract.catalogResolution.renderEntryNames.contains(renderRoot)) {
          throw const FormatException(
            'Compiled contracts omit the actual surface render root.',
          );
        }
        final library = rfw.decodeLibraryBlob(entry.value);
        final resolved = ResolvedRfwCatalogOccurrenceSet.resolve(
          parsedLibrary: library,
          input: contract.catalogResolution,
        );
        final body = resolved.inspectFinalBody(library);
        final imports =
            library.imports.map((value) => value.name.parts.join('.')).toSet();
        final names = <String>{};
        for (final call in body.constructorCalls) {
          if (contract.catalogResolution.localSymbolForName(call.name) !=
              null) {
            continue;
          }
          final origin =
              contract.catalogResolution.catalogConstructorForName(call.name);
          if (origin == null) {
            final installed = rfw.kHostInstalledRfwLibraries.where(
              (host) =>
                  imports.contains(host.namespace) &&
                  host.constructors.contains(call.name),
            );
            if (installed.length == 1 &&
                installed.single != rfw.kPreviewInstrumentationRfwLibrary) {
              continue;
            }
            throw FormatException(
              'Unsupported hosting: unresolved RFW constructor "${call.name}".',
            );
          }
          final catalogEntry = contract.catalog.findByName(
            call.name,
            WidgetLibrary.fromNamespace(origin.catalogLibraryNamespace),
          );
          if (catalogEntry == null ||
              catalogEntry.wireId != origin.catalogWidgetWireId ||
              !imports.contains(origin.catalogLibraryNamespace)) {
            throw FormatException(
              'Catalog origin does not resolve for "${call.name}".',
            );
          }
          if (WidgetLibrary.builtInByNamespace(
                origin.catalogLibraryNamespace,
              ) ==
              null) {
            throw FormatException(
              'Unsupported hosting: opaque native factory '
              '"${origin.catalogLibraryNamespace}:${call.name}".',
            );
          }
          // Curated built-in factories render these catalog constructors. All
          // application-defined bodies must be lowered and inspected locally.
          names.add(
            WidgetVocabulary.qualifiedName(
              origin.catalogLibraryNamespace,
              call.name,
            ),
          );
          if (node.sidecarCapabilities[entry.key]!.builtInFloor <
              catalogEntry.sinceVersion) {
            throw FormatException(
              'Capability sidecar understates "${call.name}".',
            );
          }
          for (final argument in call.arguments.entries) {
            if (argument.key == 'iconCodepoint' ||
                argument.key.endsWith('IconCodepoint')) {
              if (!_literalFitIcon(argument.value)) {
                throw const FormatException(
                  'Unknown data-bound icon vocabulary.',
                );
              }
            }
          }
        }
        vocabulary = vocabulary.union(
          WidgetVocabulary(
            widgetNames: names,
            iconCodePoints: rfw.literalIconCodePoints(library),
          ),
        );
        for (final reference in body.dataReferences) {
          if (reference.parts.isEmpty || reference.parts.first != 'context') {
            continue;
          }
          final gap = _contextReadGap(reference, contract.context);
          if (gap != null) throw FormatException('Undeclared $gap.');
          final name = reference.parts[1] as String;
          final shape = contract.context.inputs[name]!;
          final prior = context[name];
          if (prior != null &&
              !sameCanonicalJson(prior.toJson(), shape.toJson())) {
            throw FormatException('Conflicting closure context "$name".');
          }
          context[name] = shape;
        }
        final typedEvents = {
          for (final event in contract.events.events) event.id: event,
        };
        // Screen-local values are seeded per flow screen or per render root.
        final local = node.localSeeds[
                node.flowDocument == null ? renderRoot : entry.key] ??
            const <String, Object>{};
        for (final emitted in body.events) {
          if (kScreenEventNamesOutsideContract.contains(emitted.eventName)) {
            continue;
          }
          final typed = typedEvents[emitted.eventName];
          final internal = document != null &&
              (emitted.eventName == 'back' ||
                  document.states.values.whereType<ScreenFlowState>().any(
                        (state) =>
                            state.screen == entry.key &&
                            state.on.containsKey(emitted.eventName),
                      ));
          // Synthesized navigation events have no user payload and are consumed
          // by their exact compiled screen transition.
          if (typed == null &&
              internal &&
              _fitEventArguments(emitted).isEmpty) {
            continue;
          }
          if (typed == null) {
            throw FormatException(
              'Missing typed emitted event "${emitted.eventName}".',
            );
          }
          final gaps = _typedEventGaps(emitted, typed, contract.context, local);
          if (gaps.isNotEmpty) {
            throw FormatException('Undeclared ${gaps.first}.');
          }
          if (internal) continue;
          if (document != null) {
            final outward = document.outbound.customEvents[emitted.eventName];
            // The flow runtime drops an event with no transition and no
            // declared egress, so it asks nothing of the host.
            if (outward == null) continue;
            for (final field in outward.fields.values) {
              if (field.ref case final EventFlowOutboundRef reference) {
                _validateFitOutboundEventValue(
                  emitted.eventArguments[reference.key],
                  reference.path,
                  SurfaceScreenEventScalarShapeV1(
                    switch (field.type) {
                      FlowDataType.bool => SurfaceScreenEventScalarKind.boolean,
                      FlowDataType.int => SurfaceScreenEventScalarKind.integer,
                      FlowDataType.string =>
                        SurfaceScreenEventScalarKind.string,
                    },
                  ),
                  contract.context,
                  local,
                );
              }
            }
            continue;
          }
          final prior = events[typed.id];
          if (prior != null &&
              !sameCanonicalJson(prior.toJson(), typed.toJson())) {
            throw FormatException('Conflicting closure event "${typed.id}".');
          }
          events[typed.id] = typed;
        }
      }
    }
    if (modes.isEmpty) {
      throw const FormatException(
        'Incompatible closure presentation constraints.',
      );
    }
    final boundary = rootDocument == null
        ? null
        : FlowHostBoundaryV1.fromDocuments(
            root: rootDocument,
            descendants: [for (final node in subflows) node.flowDocument!],
          );
    return SurfaceFitRequirementV1(
      hosting: SurfaceHostingRequirementV1(
        contentKind: rootDocument == null
            ? SurfaceContentKindV1.single
            : SurfaceContentKindV1.flow,
        allowedPresentations: modes,
      ),
      requiredContext: SurfaceScreenHostDataSchema(context),
      emittedEvents: SurfaceScreenEventSchema(events: events.values.toList()),
      capabilities: capabilityManifestUnion(manifests),
      requiredVocabulary: vocabulary,
      flowBoundary: boundary,
    );
  }
}

bool _literalFitIcon(Object? value) =>
    value == null ||
    value is int ||
    value is rfw.Switch && value.outputs.values.every(_literalFitIcon);

SurfaceScreenHostDataShape _fitContextShape(
  Iterable<Object> parts,
  SurfaceScreenHostDataShape shape,
) {
  var current = shape;
  for (final part in parts) {
    while (current is SurfaceScreenHostDataNullableShapeV1) {
      current = current.value;
    }
    current = switch (current) {
      SurfaceScreenHostDataObjectShapeV1(:final fields)
          when fields.containsKey(part) =>
        fields[part]!,
      SurfaceScreenHostDataMapShapeV1(:final values) when part is String =>
        values,
      SurfaceScreenHostDataListShapeV1(:final items)
          when part is int && part >= 0 =>
        items,
      _ =>
        throw FormatException('Unknown typed context path component "$part".'),
    };
  }
  return current;
}

// The data root screen-local values are published under.
const String _localValuesDataKey = 'local';

// The authored arguments, without the reserved measurement namespace.
Map<String, Object?> _fitEventArguments(rfw.EventHandler emitted) => {
      for (final entry in emitted.eventArguments.entries)
        if (!entry.key
            .startsWith(kMeasurementPublicationReservedArgumentPrefixV1))
          entry.key: entry.value,
    };

// The undeclared arguments of one emitted [typed] event.
List<SurfaceScreenContractGap> _typedEventGaps(
  rfw.EventHandler emitted,
  SurfaceScreenEvent typed,
  SurfaceScreenHostDataSchema context,
  Map<String, Object> local,
) {
  final arguments = _fitEventArguments(emitted);
  bool fits(Object? value, SurfaceScreenEventShape shape) {
    try {
      _validateFitEventValue(value, shape, context, local);
      return true;
    } on FormatException {
      return false;
    }
  }

  SurfaceScreenContractGap gap(String argument) =>
      SurfaceScreenContractGap.argument(typed.id, argument);
  switch (typed.arguments) {
    case SurfaceScreenEventNoArguments():
      return [for (final name in arguments.keys) gap(name)];
    case SurfaceScreenEventValueArguments(:final shape):
      if (!arguments.containsKey('value')) {
        return [gap('value')];
      }
      return [
        for (final entry in arguments.entries)
          if (entry.key != 'value' || !fits(entry.value, shape)) gap(entry.key),
      ];
    case SurfaceScreenEventObjectArguments(:final shape):
      final values = (shape as SurfaceScreenEventMapShapeV1).values;
      return [
        for (final entry in arguments.entries)
          if (!fits(entry.value, values)) gap(entry.key),
      ];
  }
}

// The gap a `data.context` read leaves, or null when [context] declares it.
SurfaceScreenContractGap? _contextReadGap(
  rfw.DataReference reference,
  SurfaceScreenHostDataSchema context,
) {
  final path = reference.parts.skip(1).join('.');
  if (reference.parts.length < 2 || reference.parts[1] is! String) {
    return SurfaceScreenContractGap.context(path);
  }
  final shape = context.inputs[reference.parts[1] as String];
  if (shape == null) return SurfaceScreenContractGap.context(path);
  try {
    _fitContextShape(reference.parts.skip(2), shape);
  } on FormatException {
    return SurfaceScreenContractGap.context(path);
  }
  return null;
}

void _validateFitEventValue(
  Object? value,
  SurfaceScreenEventShape shape,
  SurfaceScreenHostDataSchema context,
  Map<String, Object> local,
) {
  if (value is rfw.DataReference &&
      value.parts.length == 2 &&
      value.parts.first == _localValuesDataKey) {
    // A screen-local value holds its seeded scalar type.
    final seed = local[value.parts[1]];
    if (seed == null) {
      throw const FormatException('Unknown emitted event data type.');
    }
    _validateFitEventValue(seed, shape, context, local);
    return;
  }
  if (value is rfw.DataReference) {
    if (value.parts.length < 2 ||
        value.parts.first != 'context' ||
        value.parts[1] is! String) {
      throw const FormatException('Unknown emitted event data type.');
    }
    final source = context.inputs[value.parts[1]];
    if (source == null) {
      throw const FormatException('Missing emitted event context type.');
    }
    final actual = _fitContextShape(value.parts.skip(2), source);
    if (!sameCanonicalJson(actual.toJson(), shape.toJson())) {
      throw const FormatException(
        'Emitted event context type differs from its schema.',
      );
    }
    return;
  }
  if (value is rfw.Switch) {
    for (final output in value.outputs.values) {
      _validateFitEventValue(output, shape, context, local);
    }
    return;
  }
  switch (shape) {
    case SurfaceScreenEventNullableShapeV1():
      if (value != null) {
        _validateFitEventValue(value, shape.value, context, local);
      }
    case SurfaceScreenEventListShapeV1(:final items):
      if (value is! List) {
        throw const FormatException('Unknown emitted event list type.');
      }
      for (final item in value) {
        _validateFitEventValue(item, items, context, local);
      }
    case SurfaceScreenEventMapShapeV1(:final values):
      if (value is! Map<String, Object?>) {
        throw const FormatException('Unknown emitted event map type.');
      }
      for (final item in value.values) {
        _validateFitEventValue(item, values, context, local);
      }
    case SurfaceScreenEventScalarShapeV1():
      shape.validate(value);
  }
}

void _validateFitOutboundEventValue(
  Object? value,
  List<String> path,
  SurfaceScreenEventShape shape,
  SurfaceScreenHostDataSchema context,
  Map<String, Object> local,
) {
  if (value is rfw.Switch) {
    for (final output in value.outputs.values) {
      _validateFitOutboundEventValue(output, path, shape, context, local);
    }
  } else if (value is rfw.DataReference) {
    _validateFitEventValue(
      rfw.DataReference([...value.parts, ...path]),
      shape,
      context,
      local,
    );
  } else if (path.isEmpty) {
    _validateFitEventValue(value, shape, context, local);
  } else if (value is Map<String, Object?> && value.containsKey(path.first)) {
    _validateFitOutboundEventValue(
      value[path.first],
      path.skip(1).toList(),
      shape,
      context,
      local,
    );
  } else {
    throw const FormatException('Unknown typed flow event egress field.');
  }
}

/// Every event, event argument and `data.context` read in [library] that
/// [events] and [context] do not declare, sorted and each listed once.
///
/// Every declaration counts, reachable or not. [localValues] are the seeded
/// screen-local values an event argument may read.
List<SurfaceScreenContractGap> surfaceScreenContractGaps(
  rfw.RemoteWidgetLibrary library, {
  required SurfaceScreenEventSchema events,
  required SurfaceScreenHostDataSchema context,
  Map<String, Object> localValues = const {},
}) {
  final typedEvents = {for (final event in events.events) event.id: event};
  final gaps = <SurfaceScreenContractGap>{};
  void visit(Object? value) {
    switch (value) {
      case rfw.DataReference()
          when value.parts.isNotEmpty && value.parts.first == 'context':
        final gap = _contextReadGap(value, context);
        if (gap != null) gaps.add(gap);
      case rfw.EventHandler(:final eventName, :final eventArguments):
        if (!kScreenEventNamesOutsideContract.contains(eventName)) {
          final typed = typedEvents[eventName];
          if (typed == null) {
            gaps.add(SurfaceScreenContractGap.event(eventName));
          } else {
            gaps.addAll(_typedEventGaps(value, typed, context, localValues));
          }
        }
        eventArguments.values.forEach(visit);
      case rfw.ConstructorCall(:final arguments):
        arguments.values.forEach(visit);
      case rfw.SetStateHandler(value: final assigned):
        visit(assigned);
      case rfw.WidgetBuilderDeclaration(:final widget):
        visit(widget);
      case rfw.Loop(:final input, :final output):
        visit(input);
        visit(output);
      case rfw.Switch(:final input, :final outputs):
        visit(input);
        outputs.values.forEach(visit);
      case final Map<Object?, Object?> map:
        map.values.forEach(visit);
      case final List<Object?> list:
        list.forEach(visit);
    }
  }

  for (final declaration in library.widgets) {
    visit(declaration.initialState);
    visit(declaration.root);
  }
  return gaps.toList()..sort();
}
