import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/islands/islands.dart';
import 'package:restage_codegen/src/owning_library_namespace.dart';
import 'package:restage_codegen/src/surface_publication/generated_handle_names.dart';
import 'package:restage_codegen/src/surface_publication/host_data_contract.dart';
import 'package:restage_codegen/src/surface_publication/recorded_layouts.dart';
import 'package:restage_codegen/src/surface_publication/screen_contract_reference_emitter.dart';
import 'package:restage_shared/restage_shared.dart';

/// What a flow's placement passes its steps, from their generated mounts:
/// their host data and islands across the flow and the subflows it reaches,
/// and each step's recorded layouts under `flow/step`. [conflicts] names
/// each value two steps pass under one name with different types, which one
/// placement can't pass for both.
({
  SurfaceScreenHostDataSchema context,
  Map<String, String> islands,
  Map<String, SurfaceLayoutsV1> layouts,
  List<String> conflicts,
})
flowStepHostFacets(
  FlowDocument document, {
  required Map<String, FlowDocument> descendants,
  required Map<String, ResolvedWidgetMountInput> stepMounts,
}) {
  final context = <String, SurfaceScreenHostDataShape>{};
  final passedBy = <String, String>{};
  final conflicts = <String>[];
  final islands = <Island>[];
  final layouts = <String, SurfaceLayoutsV1>{};
  final reached = {document.flow};
  for (final queue = [document]; queue.isNotEmpty;) {
    final flow = queue.removeLast();
    for (final screen in flow.screenArtifacts.keys) {
      final mount = stepMounts[screen];
      if (mount == null) continue;
      for (final MapEntry(:key, :value)
          in mount.hostDataContract.inputs.entries) {
        final step = mount.screen.name ?? screen;
        if (context[key] case final first?) {
          if (!_sameShape(first, value) && passedBy[key] != step) {
            conflicts.add(
              '`${passedBy[key]}` and `$step` both pass '
              '`${value.label ?? key}`, as ${_kindOf(first)} and as '
              '${_kindOf(value)}',
            );
          }
          continue;
        }
        context[key] = value;
        passedBy[key] = step;
      }
      islands.addAll(mount.islands);
      layouts['${flow.flow}/$screen'] = recordedLayoutsOf(
        mount.split?.recordedBuild,
      );
    }
    for (final state in flow.states.values.whereType<SubFlowState>()) {
      if (!reached.add(state.flow)) continue;
      if (descendants[state.flow] case final child?) queue.add(child);
    }
  }
  return (
    context: SurfaceScreenHostDataSchema(context),
    islands: islandHostFacet(islands),
    layouts: layouts,
    conflicts: conflicts,
  );
}

// Whether [a] and [b] pass the same type, whatever they're labelled.
bool _sameShape(SurfaceScreenHostDataShape a, SurfaceScreenHostDataShape b) {
  Map<String, Object?> bare(SurfaceScreenHostDataShape shape) =>
      Map.of(shape.toJson())..remove('label');
  return jsonEncode(bare(a)) == jsonEncode(bare(b));
}

String _kindOf(SurfaceScreenHostDataShape shape) => switch (shape.toJson()) {
  {'contract': {'type': final String type}} => '`$type`',
  {'kind': 'string'} => '`String`',
  {'kind': 'number'} => '`num`',
  {'kind': final String kind} => '`$kind`',
  _ => 'another type',
};

/// Generated original-graph argument and the typed mount that binds it.
typedef CompiledFlowEmission = ({String argument, String mount});

/// Whether [emitCompiledFlow] emits a mount for a flow declared in [library].
bool emitsCompiledFlowMount(LibraryElement library) =>
    _sdkPrefix(OwningLibraryNamespace(library)) != null;

String? _sdkPrefix(OwningLibraryNamespace namespace) =>
    namespace.prefixForOrigin('package:restage', const {
      'CompiledFlow',
      'CompiledFlowScreenBuilder',
      'RestageFlowGraph',
    });

/// Retains the existing canonical documents and original Flutter constructors.
///
/// [providedContext] is what the flow's step mounts pass its steps.
CompiledFlowEmission emitCompiledFlow({
  required FlowDocument document,
  required Surface surface,
  required Map<String, FlowDocument> descendants,
  required Map<String, ClassElement> screens,
  required LibraryElement library,
  required String refName,
  required String mountName,
  required String resultType,
  Map<String, String> islands = const {},
  Map<String, SurfaceLayoutsV1> screenLayouts = const {},
  SurfaceScreenHostDataSchema providedContext =
      const SurfaceScreenHostDataSchema.empty(),
}) {
  final namespace = OwningLibraryNamespace(library);
  final sdk = _sdkPrefix(namespace);
  // Like generated screen mounts, preserve descriptor-only imports.
  if (sdk == null) return (argument: '', mount: '');
  final builders = <String, String>{};
  final compiledDocuments = <FlowDocument>{};
  String encode(FlowDocument doc) {
    compiledDocuments.add(doc);
    final constructors = <String>[];
    for (final id in doc.screenArtifacts.keys) {
      final declaration = screens[id];
      final name = declaration == null
          ? null
          : namespace.elementName(declaration);
      final constructor = declaration?.unnamedConstructor;
      if (name != null &&
          constructor != null &&
          !constructor.formalParameters.any(
            (parameter) => parameter.isRequired,
          ) &&
          !(declaration!.isAbstract && !constructor.isFactory)) {
        constructors.add('${dartStringLiteral(id)}: $name.new,');
      } else {
        final identifier = id.replaceAll(RegExp('[^a-zA-Z0-9_]'), '_');
        final stem = lowerCamelIdentifier(identifier, fallback: 'screen');
        var name = '${stem}ScreenBuilder';
        var suffix = 2;
        while (builders.containsValue(name)) {
          name = '${stem}ScreenBuilder${suffix++}';
        }
        builders[id] = name;
      }
    }
    final children = <String>[];
    final childIds = {
      for (final state in doc.states.values.whereType<SubFlowState>())
        state.flow,
    };
    for (final id in childIds) {
      final child = descendants[id];
      if (child != null) {
        children.add('${dartStringLiteral(id)}: ${encode(child)},');
      }
    }
    return '''
${sdk}CompiledFlow(
      documentJson: ${dartStringLiteral(utf8.decode(FlowDocumentCodec.encodeCanonicalJson(doc)))},
      screens: {${constructors.join('\n')}},
      children: {${children.join('\n')}},
    )''';
  }

  final compiled = encode(document);
  final requiredBuilders = builders.entries
      .map(
        (entry) => 'required ${sdk}CompiledFlowScreenBuilder ${entry.value},',
      )
      .join('\n');
  final bindings = builders.isEmpty
      ? ''
      : '''
, screenBuilders: {
    ${builders.entries.map((entry) => '${dartStringLiteral(entry.key)}: ${entry.value},').join('\n')}
  }''';
  final provider = placementDefinitionProviderName(
    refName.substring(0, refName.length - 'Ref'.length),
  );
  final definition = emitPlacementDefinition(
    declarationName: refName.substring(0, refName.length - 'Ref'.length),
    defaultSurfaceArgument: 'defaultSurface: $refName',
    surface: surface,
    slug: document.flow,
    hostContract: SurfaceHostContractV1(
      hosting: const SurfaceHostingV1(
        contentKind: SurfaceContentKindV1.flow,
        presentation: SurfacePresentationV1.inline,
      ),
      providedContext: providedContext,
      handledEvents: SurfaceScreenEventSchema(events: const []),
      flowBoundary: FlowHostBoundaryV1.fromDocuments(
        root: document,
        descendants: compiledDocuments.where((child) => child != document),
      ),
      islands: islands,
      screenLayouts: screenLayouts,
    ),
    vocabulary: '$refName.vocabulary',
    sdkHost: '${sdk}RestageFlowGraph',
  );
  String constructor({required bool atPlacement}) =>
      '''
  /// ${atPlacement ? 'Overrides the implicit placement with an explicit name.' : 'Mounts this flow at its implicit placement by default.'}
  ///
  /// ${atPlacement ? 'Use [$mountName] for the default placement; no name is needed.' : 'Use this constructor for ordinary mounts; no placement name is needed.'}
  ${builders.isEmpty ? 'const ' : ''}$mountName${atPlacement ? '.atPlacement(String restagePlacementId, ' : '('}{
    super.key,
    $requiredBuilders
    ${atPlacement ? '' : 'String? placement,'}
    super.initialState,
    super.actions,
    super.installedSignalNames,
    super.resolver,
    super.onFlowUnavailable,
    super.onComplete,
    super.loadingBuilder,
    super.transition,
    super.systemBack,
    super.liveRefresh,
    super.context,
    super.fallbackBuilder,
    super.errorBuilder,
  }) : _restagePlacementName = ${atPlacement ? 'restagePlacementId' : 'placement'},
       super(flow: $refName$bindings);
''';
  return (
    argument:
        '  compiled: $compiled,\n'
        '  surfaceWidget: ${dartStringLiteral(mountName)},\n',
    mount:
        '''
$definition
/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class $mountName extends ${sdk}RestageFlowGraph<$resultType> {
${constructor(atPlacement: false)}
${constructor(atPlacement: true)}
  final String? _restagePlacementName;

  @override
  get placementBinding => ${sdk}RestageFlowGraph.generatedPlacementBinding(
    definition: $provider,
    name: _restagePlacementName,
  );
}
''',
  );
}
