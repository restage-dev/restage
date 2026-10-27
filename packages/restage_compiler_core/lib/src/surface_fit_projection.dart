import 'package:restage_compiler_core/src/rfw_catalog_occurrence_resolution.dart';
import 'package:restage_compiler_core/src/rfw_program_envelope.dart';
import 'package:restage_compiler_core/src/surface_capability_derivation.dart';
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
    Map<String, ValueOperation> operations = const {
      ...kCollectionValueOperations,
      ...kGridValueOperations,
      ...kIntlValueOperations
    },
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
        final screenOperations =
            nativeCallOperations(contract.context, operations);
        final nativeScope = RfwProgramScope([
          for (final widget in library.widgets) ...[
            widget.initialState,
            widget.root
          ]
        ], operations: screenOperations);
        validateRfwNativeReferences(library, contract.catalog,
            scope: nativeScope);
        for (final entry in nativeScope.nativeBindings.entries) {
          final declared = contract.context.inputs[entry.key];
          if (declared is! SurfaceScreenHostDataNativeBindingShapeV1 ||
              declared.contract != entry.value) {
            throw FormatException(
                'Undeclared or incompatible native binding "${entry.key}".');
          }
          final shape = SurfaceScreenHostDataNativeBindingShapeV1(entry.value);
          final prior = context[entry.key];
          if (prior != null &&
              !sameCanonicalJson(prior.toJson(), shape.toJson())) {
            throw FormatException(
                'Conflicting native call declaration "${entry.key}".');
          }
          context[entry.key] = shape;
        }
        final actualCapability = deriveSurfaceCapability(
          library,
          contract.catalog,
          operations: screenOperations,
          hostDataContract: contract.context,
        );
        if (node.sidecarCapabilities[entry.key]!.builtInFloor <
            actualCapability.builtInFloor) {
          throw const FormatException(
            'Capability sidecar understates screen features.',
          );
        }
        final resolved = ResolvedRfwCatalogOccurrenceSet.resolve(
          parsedLibrary: library,
          input: contract.catalogResolution,
          operations: screenOperations,
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
            // The app compiles its own library's factories, so the host fits
            // when it installs that library at the declared version.
            final declared =
                node.sidecarCapabilities[entry.key]!.requiredLibraries.any(
              (library) => library.namespace == origin.catalogLibraryNamespace,
            );
            if (!declared) {
              throw FormatException(
                'Capability sidecar omits the library '
                '"${origin.catalogLibraryNamespace}" of "${call.name}".',
              );
            }
            continue;
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
        _validateRfwNativeHostContract(
            library, contract.catalog, contract.context,
            scope: nativeScope, localValues: local);
        final sites = _eventSites(
          library,
          operations: screenOperations,
          onCapture: (value, type) {
            _validateProgramCapture(value, type, contract.context, local);
          },
        );
        for (final raw in body.events) {
          final site = sites[raw];
          final emitted = _withoutLoopReferences(
            raw,
            site?.loops ?? const [],
            frames: site?.frames ?? const {},
          );
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
          // A paywall host takes its events through its generic event
          // channel, so a paywall asks no typed event of its host.
          final paywall =
              node.publication.sourceKind == SurfaceSourceKind.paywall;
          if (paywall && document == null) continue;
          if (typed == null) {
            if (document == null) {
              throw FormatException(
                'Missing typed emitted event "${emitted.eventName}".',
              );
            }
            // A flow transition consumes the event; with no transition and no
            // declared egress the runtime drops it. Declared egress is checked
            // against its own fields below.
            if (internal ||
                !document.outbound.customEvents
                    .containsKey(emitted.eventName)) {
              continue;
            }
          }
          if (typed != null) {
            final call = site?.call;
            final origin = call == null
                ? null
                : contract.catalogResolution.catalogConstructorForName(call);
            final property = origin == null
                ? null
                : contract.catalog
                    .findByName(
                      call!,
                      WidgetLibrary.fromNamespace(
                        origin.catalogLibraryNamespace,
                      ),
                    )
                    ?.properties
                    .where((property) => property.name == site?.argument)
                    .firstOrNull;
            final gaps = _typedEventGaps(
              emitted,
              typed,
              contract.context,
              local,
              widgetValue: _callbackValueShape(property?.callbackSignature),
            );
            if (gaps.isNotEmpty) {
              throw FormatException('Undeclared ${gaps.first}.');
            }
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
          if (typed == null) continue;
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

/// Where one emitted event sits: the loops around it, outermost first, and
/// the constructor argument that holds it.
typedef _BuilderFrames = Map<String, Map<String, List<ValueType>>>;
typedef _EventSite = ({
  List<Object> loops,
  _BuilderFrames frames,
  String? call,
  String? argument
});

/// The site of every event in [library].
Map<rfw.EventHandler, _EventSite> _eventSites(
  rfw.RemoteWidgetLibrary library, {
  Map<String, ValueOperation> operations = const {
    ...kCollectionValueOperations,
    ...kGridValueOperations,
    ...kIntlValueOperations
  },
  void Function(Object? value, ValueType type)? onCapture,
}) {
  final programScope = RfwProgramScope([
    for (final widget in library.widgets) ...[widget.initialState, widget.root]
  ], operations: operations);
  final sites = Map<rfw.EventHandler, _EventSite>.identity();
  void visit(
    Object? value,
    List<Object> loops, {
    String? call,
    String? argument,
    _BuilderFrames frames = const {},
  }) {
    switch (value) {
      case rfw.Loop(:final input, :final output):
        visit(input, loops, frames: frames);
        visit(output, [...loops, input], frames: frames);
      case rfw.EventHandler(:final eventArguments):
        sites[value] =
            (loops: loops, frames: frames, call: call, argument: argument);
        visit(eventArguments, loops, frames: frames);
      case rfw.ConstructorCall(:final name, :final arguments):
        if (name == kBuilderContinuationWidgetName) {
          visit(arguments, loops, frames: frames);
          return;
        }
        for (final entry in arguments.entries) {
          visit(
            entry.value,
            loops,
            call: name,
            argument: entry.key,
            frames: frames,
          );
        }
      case rfw.Switch(:final input, :final outputs):
        visit(input, loops, frames: frames);
        for (final output in outputs.entries) {
          visit(
            output.value,
            loops,
            call: call,
            argument: argument,
            frames: _framesForSwitchCase(input, output.key, outputs, frames),
          );
        }
      case rfw.SetStateHandler(:final value):
        visit(value, loops, frames: frames);
      case rfw.WidgetBuilderDeclaration(:final widget):
        visit(widget, loops, frames: frames);
      case final Map<Object?, Object?> map:
        final envelope = decodeRfwProgramEnvelope(map,
            operations: operations, scope: programScope);
        if (envelope != null) {
          for (final capture in envelope.captures.entries) {
            onCapture?.call(
              _rewriteScopedValue(capture.value, loops, frames),
              envelope.values.captures[capture.key]!,
            );
            visit(capture.value, loops, frames: frames);
          }
          for (var index = 0; index < envelope.bodies.length; index++) {
            final body = envelope.bodies[index];
            visit(
              body.widget,
              loops,
              frames: {
                ...frames,
                body.argumentName: envelope.frameTypes(index),
              },
            );
          }
          return;
        }
        for (final item in map.values) {
          visit(item, loops, frames: frames);
        }
      case final List<Object?> list:
        for (final item in list) {
          visit(item, loops, frames: frames);
        }
    }
  }

  for (final declaration in library.widgets) {
    visit(declaration.root, const []);
  }
  return sites;
}

bool _isFrameNullDiscriminator(Object input, _BuilderFrames frames) =>
    input is rfw.WidgetBuilderArgReference &&
    input.parts.length == 2 &&
    input.parts.first == 'nulls' &&
    frames[input.argumentName]?[input.parts[1]] != null;

// Only the matching false null discriminator proves a frame value exists.
_BuilderFrames _framesForSwitchCase(
  Object input,
  Object? key,
  Map<Object?, Object> outputs,
  _BuilderFrames frames,
) {
  if (!_isFrameNullDiscriminator(input, frames) ||
      !(key == false ||
          key == null &&
              outputs.containsKey(true) &&
              !outputs.containsKey(false))) {
    return frames;
  }
  final reference = input as rfw.WidgetBuilderArgReference;
  final fields = frames[reference.argumentName]!;
  final name = reference.parts[1] as String;
  return {
    ...frames,
    reference.argumentName: {
      ...fields,
      name: fields[name]!
          .map((type) => type.kind == 'Null' ? type : type.nonNull)
          .toList(),
    },
  };
}

/// The shape of the value a `ValueChanged<T>` [signature] passes, or null
/// when it has no event shape.
SurfaceScreenEventShape? _callbackValueShape(String? signature) {
  final type = signature == null ? null : parseRfwCallbackValueType(signature);
  if (type == null) return null;
  SurfaceScreenEventShape? shapeOf(String type) {
    if (type.endsWith('?')) {
      final value = shapeOf(type.substring(0, type.length - 1));
      return value == null ? null : SurfaceScreenEventNullableShapeV1(value);
    }
    if (type.startsWith('List<') && type.endsWith('>')) {
      final items = shapeOf(type.substring(5, type.length - 1));
      return items == null ? null : SurfaceScreenEventListShapeV1(items);
    }
    final kind = switch (type) {
      'String' => SurfaceScreenEventScalarKind.string,
      'bool' => SurfaceScreenEventScalarKind.boolean,
      'int' => SurfaceScreenEventScalarKind.integer,
      'double' => SurfaceScreenEventScalarKind.doubleValue,
      _ => null,
    };
    return kind == null ? null : SurfaceScreenEventScalarShapeV1(kind);
  }

  return shapeOf(type);
}

/// [event] with each loop variable read rewritten as a read of the loop's
/// data, so its arguments validate against the declared context.
rfw.EventHandler _withoutLoopReferences(
  rfw.EventHandler event,
  List<Object> loops, {
  _BuilderFrames frames = const {},
}) =>
    rfw.EventHandler(
      event.eventName,
      _rewriteScopedValue(event.eventArguments, loops, frames)!
          as rfw.DynamicMap,
    );

Object? _rewriteScopedValue(
  Object? value,
  List<Object> scope,
  _BuilderFrames frames,
) {
  switch (value) {
    case rfw.LoopReference(:final loop, :final parts):
      final index = scope.length - 1 - loop;
      if (index < 0) return value;
      final input =
          _rewriteScopedValue(scope[index], scope.sublist(0, index), frames);
      return input is rfw.DataReference
          ? rfw.DataReference([...input.parts, _loopItem, ...parts])
          : value;
    case rfw.WidgetBuilderArgReference(:final argumentName, :final parts):
      final fields = frames[argumentName];
      if (fields != null && parts.length == 2 && parts[1] is String) {
        final types = fields[parts[1]];
        if (types != null && parts[0] == 'values') {
          return _BuilderFrameValue(types);
        }
        if (types != null && parts[0] == 'nulls') {
          return const _BuilderFrameValue([ValueType.boolean]);
        }
      }
      return value;
    case rfw.Switch(:final input, :final outputs):
      return rfw.Switch(
        _rewriteScopedValue(input, scope, frames)!,
        {
          for (final entry in outputs.entries)
            entry.key: _rewriteScopedValue(
              entry.value,
              scope,
              _framesForSwitchCase(input, entry.key, outputs, frames),
            )!,
          if (_isFrameNullDiscriminator(input, frames) &&
              !outputs.containsKey(null))
            for (final key in [true, false])
              if (!outputs.containsKey(key)) key: rfw.missing,
        },
      );
    case final Map<String, Object?> map:
      return <String, Object?>{
        for (final entry in map.entries)
          entry.key: _rewriteScopedValue(entry.value, scope, frames),
      };
    case final List<Object?> list:
      return [
        for (final item in list) _rewriteScopedValue(item, scope, frames),
      ];
  }
  return value;
}

final class _BuilderFrameValue {
  const _BuilderFrameValue(this.types);
  final List<ValueType> types;
}

SurfaceScreenHostDataShape _valueHostShape(ValueType type) {
  final shape = switch (type.kind) {
    'native' => SurfaceScreenHostDataNativeBindingShapeV1(
        NativeBindingContract(type: type.nativeType!, nullable: type.nullable)),
    'list' => SurfaceScreenHostDataListShapeV1(_valueHostShape(type.item!)),
    'record' => SurfaceScreenHostDataObjectShapeV1({
        for (final field in type.fields.entries)
          field.key: _valueHostShape(field.value),
      }),
    _ => SurfaceScreenHostDataScalarShapeV1(
        switch (type.kind) {
          'bool' => SurfaceScreenHostDataScalarKind.boolean,
          'int' => SurfaceScreenHostDataScalarKind.integer,
          'double' => SurfaceScreenHostDataScalarKind.doubleValue,
          'num' => SurfaceScreenHostDataScalarKind.number,
          'String' => SurfaceScreenHostDataScalarKind.string,
          _ =>
            throw const FormatException('Unknown builder frame value shape.'),
        },
      ),
  };
  return type.nullable ? SurfaceScreenHostDataNullableShapeV1(shape) : shape;
}

/// Checks catalog-linked native values against the installed host contract.
void _validateRfwNativeHostContract(
  rfw.RemoteWidgetLibrary library,
  Catalog catalog,
  SurfaceScreenHostDataSchema context, {
  required RfwProgramScope scope,
  Map<String, Object> localValues = const {},
}) {
  validateRfwNativeReferences(library, catalog, scope: scope,
      onReference: (value, expected, nativeOnly) {
    if (decodeRfwProgramEnvelope(value,
            operations: scope.operations, scope: scope) !=
        null) return;
    if (value is Map && value['kind'] == 'nativeLocal') return;
    if (!nativeOnly && value is rfw.Reference) {
      if (value is! rfw.DataReference ||
          value.parts.length < 2 ||
          value.parts.first != 'context') return;
      final root = context.inputs[value.parts[1]];
      if (root == null ||
          _isJsonHostShape(_fitContextShape(value.parts.skip(2), root))) return;
    }
    _validateProgramCapture(value, expected, context, localValues);
  });
}

bool _captureShapeFits(ValueType expected, SurfaceScreenHostDataShape actual) {
  if (actual is SurfaceScreenHostDataNullableShapeV1) {
    return expected.nullable &&
        _captureShapeFits(expected.nonNull, actual.value);
  }
  return switch (actual) {
    SurfaceScreenHostDataNativeBindingShapeV1(:final contract) =>
      contract.call == null &&
          expected.accepts(
              ValueType.native(contract.type, nullable: contract.nullable)),
    SurfaceScreenHostDataScalarShapeV1(
      kind: SurfaceScreenHostDataScalarKind.jsonValue
    ) =>
      false,
    SurfaceScreenHostDataScalarShapeV1(:final kind) => expected.accepts(
        ValueType(
          switch (kind) {
            SurfaceScreenHostDataScalarKind.boolean => 'bool',
            SurfaceScreenHostDataScalarKind.integer => 'int',
            SurfaceScreenHostDataScalarKind.doubleValue => 'double',
            SurfaceScreenHostDataScalarKind.number => 'num',
            SurfaceScreenHostDataScalarKind.string => 'String',
            SurfaceScreenHostDataScalarKind.jsonValue =>
              throw const FormatException('Untyped expression capture.'),
          },
        ),
      ),
    SurfaceScreenHostDataListShapeV1(:final items) =>
      expected.kind == 'list' && _captureShapeFits(expected.item!, items),
    SurfaceScreenHostDataObjectShapeV1(:final fields) =>
      expected.kind == 'record' &&
          expected.fields.entries.every(
            (field) =>
                fields[field.key] != null &&
                _captureShapeFits(field.value, fields[field.key]!),
          ),
    _ => false,
  };
}

void _validateProgramCapture(
  Object? value,
  ValueType type,
  SurfaceScreenHostDataSchema context,
  Map<String, Object> local,
) {
  if (value is _BuilderFrameValue) {
    if (value.types.every(type.accepts)) return;
  } else if (value is rfw.DataReference) {
    if (value.parts.length >= 2 && value.parts.first == 'context') {
      final source = context.inputs[value.parts[1]];
      if (source != null &&
          _captureShapeFits(
            type,
            _fitContextShape(value.parts.skip(2), source),
          )) {
        return;
      }
    } else if (value.parts.length == 2 &&
        value.parts.first == _localValuesDataKey &&
        local.containsKey(value.parts[1])) {
      _validateProgramCapture(local[value.parts[1]], type, context, local);
      return;
    }
  } else if (value is rfw.Switch) {
    for (final output in value.outputs.values) {
      _validateProgramCapture(output, type, context, local);
    }
    return;
  } else if ((value == null || identical(value, rfw.missing)) &&
      type.nullable) {
    return;
  } else if (type.kind == 'native' && value is Map) {
    if (value['kind'] == 'nativeLocal' &&
        value['type'] == type.nativeType &&
        value['nullable'] == type.nullable) return;
    if (value['kind'] == 'nativeBinding' && value['key'] is String) {
      final shape = context.inputs[value['key']];
      if (shape is SurfaceScreenHostDataNativeBindingShapeV1 &&
          shape.contract.call == null &&
          value['type'] == shape.contract.type &&
          value['nullable'] == shape.contract.nullable &&
          _captureShapeFits(type, shape)) return;
    }
  } else if (type.kind == 'record' && value is Map) {
    for (final field in type.fields.entries) {
      if (!value.containsKey(field.key)) {
        throw const FormatException('Missing typed expression capture field.');
      }
      _validateProgramCapture(value[field.key], field.value, context, local);
    }
    return;
  } else if (type.kind == 'list' && value is List) {
    for (final item in value) {
      _validateProgramCapture(item, type.item!, context, local);
    }
    return;
  } else if (switch (type.kind) {
    'bool' => value is bool,
    'int' => value is int,
    'double' => value is double,
    'num' => value is num,
    'String' => value is String,
    _ => false,
  }) {
    return;
  }
  throw const FormatException(
    'Expression capture differs from its declared type.',
  );
}

// The path step a loop variable read takes into its list: an item that exists.
const Object _loopItem = _LoopItem();

final class _LoopItem {
  const _LoopItem();

  @override
  String toString() => '0';
}

bool _literalFitIcon(Object? value) =>
    value == null ||
    value is int ||
    value is rfw.Switch && value.outputs.values.every(_literalFitIcon);

// The shape read at [parts], nullable when a nullable parent, a map key or a
// literal list index on the way can leave it absent, as Dart types `a?.b`.
SurfaceScreenHostDataShape _fitContextShape(
  Iterable<Object> parts,
  SurfaceScreenHostDataShape shape,
) {
  var current = shape;
  var absent = false;
  for (final part in parts) {
    while (current is SurfaceScreenHostDataNullableShapeV1) {
      absent = true;
      current = current.value;
    }
    if (current is SurfaceScreenHostDataMapShapeV1 && part is String ||
        current is SurfaceScreenHostDataListShapeV1 && part is int) {
      absent = true;
    }
    current = switch (current) {
      SurfaceScreenHostDataObjectShapeV1(:final fields)
          when fields.containsKey(part) =>
        fields[part]!,
      SurfaceScreenHostDataMapShapeV1(:final values) when part is String =>
        values,
      SurfaceScreenHostDataListShapeV1(:final items)
          when identical(part, _loopItem) || part is int && part >= 0 =>
        items,
      _ =>
        throw FormatException('Unknown typed context path component "$part".'),
    };
  }
  return absent && current is! SurfaceScreenHostDataNullableShapeV1
      ? SurfaceScreenHostDataNullableShapeV1(current)
      : current;
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
  Map<String, Object> local, {
  SurfaceScreenEventShape? widgetValue,
}) {
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
        // A value callback's widget passes its own value at run time.
        if (widgetValue != null &&
            arguments.isEmpty &&
            sameCanonicalJson(widgetValue.toJson(), shape.toJson())) {
          return const [];
        }
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
  if (identical(value, rfw.missing)) {
    throw const FormatException('Missing builder event value.');
  }
  if (value is _BuilderFrameValue) {
    if (!value.types.every(
      (type) =>
          !type.nullable && _contextValueFits(shape, _valueHostShape(type)),
    )) {
      throw const FormatException(
        'Builder event value differs from its schema.',
      );
    }
    return;
  }
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
    if (!_contextValueFits(shape, actual)) {
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

// Whether a host value of [actual] shape is assignable to [declared].
bool _contextValueFits(
  SurfaceScreenEventShape declared,
  SurfaceScreenHostDataShape actual,
) =>
    switch ((declared, actual)) {
      (
        SurfaceScreenEventScalarShapeV1(
          kind: SurfaceScreenEventScalarKind.jsonValue
        ),
        _
      ) =>
        _isJsonHostShape(actual),
      (
        SurfaceScreenEventNullableShapeV1(:final value),
        SurfaceScreenHostDataNullableShapeV1(value: final inner),
      ) =>
        _contextValueFits(value, inner),
      (SurfaceScreenEventNullableShapeV1(:final value), _) =>
        _contextValueFits(value, actual),
      (
        SurfaceScreenEventScalarShapeV1(:final kind),
        SurfaceScreenHostDataScalarShapeV1(kind: final provided),
      ) =>
        kind.wireName == provided.wireName,
      (
        SurfaceScreenEventListShapeV1(:final items),
        SurfaceScreenHostDataListShapeV1(items: final provided),
      ) =>
        _contextValueFits(items, provided),
      (
        SurfaceScreenEventMapShapeV1(:final values),
        SurfaceScreenHostDataMapShapeV1(values: final provided),
      ) =>
        _contextValueFits(values, provided),
      _ => false,
    };

bool _isJsonHostShape(SurfaceScreenHostDataShape shape) => switch (shape) {
      SurfaceScreenHostDataNativeBindingShapeV1() => false,
      SurfaceScreenHostDataNullableShapeV1(:final value) =>
        _isJsonHostShape(value),
      SurfaceScreenHostDataListShapeV1(:final items) => _isJsonHostShape(items),
      SurfaceScreenHostDataMapShapeV1(:final values) =>
        _isJsonHostShape(values),
      SurfaceScreenHostDataObjectShapeV1(:final fields) =>
        fields.values.every(_isJsonHostShape),
      SurfaceScreenHostDataScalarShapeV1() => true,
    };

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
  Map<String, ValueOperation> operations = const {
    ...kCollectionValueOperations,
    ...kGridValueOperations,
    ...kIntlValueOperations
  },
}) {
  operations = nativeCallOperations(context, operations);
  final typedEvents = {for (final event in events.events) event.id: event};
  final gaps = <SurfaceScreenContractGap>{};
  final sites = _eventSites(
    library,
    operations: operations,
    onCapture: (value, type) {
      _validateProgramCapture(value, type, context, localValues);
    },
  );
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
            final emitted = _withoutLoopReferences(
              value,
              sites[value]?.loops ?? const [],
              frames: sites[value]?.frames ?? const {},
            );
            gaps.addAll(
              _typedEventGaps(emitted, typed, context, localValues),
            );
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
