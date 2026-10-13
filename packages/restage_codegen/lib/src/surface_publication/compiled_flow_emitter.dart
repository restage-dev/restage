import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/owning_library_namespace.dart';
import 'package:restage_codegen/src/surface_publication/generated_handle_names.dart';
import 'package:restage_codegen/src/surface_publication/host_data_contract.dart';
import 'package:restage_shared/restage_shared.dart';

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
      'FlowUnavailablePolicy',
    });

/// Retains the existing canonical documents and original Flutter constructors.
CompiledFlowEmission emitCompiledFlow({
  required FlowDocument document,
  required Surface surface,
  required Map<String, FlowDocument> descendants,
  required Map<String, ClassElement> screens,
  required LibraryElement library,
  required String refName,
  required String mountName,
  required String resultType,
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
      final name =
          declaration == null ? null : namespace.elementName(declaration);
      final constructor = declaration?.unnamedConstructor;
      if (name != null &&
          constructor != null &&
          !constructor.formalParameters
              .any((parameter) => parameter.isRequired) &&
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
      providedContext: const SurfaceScreenHostDataSchema.empty(),
      handledEvents: SurfaceScreenEventSchema(events: const []),
      flowBoundary: FlowHostBoundaryV1.fromDocuments(
        root: document,
        descendants: compiledDocuments.where((child) => child != document),
      ),
    ),
    vocabulary: '$refName.vocabulary',
    sdkHost: '${sdk}RestageFlowGraph',
  );
  String constructor({required bool atPlacement}) => '''
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
    super.unavailable = const ${sdk}FlowUnavailablePolicy.hide(),
  }) : _restagePlacementName = ${atPlacement ? 'restagePlacementId' : 'placement'},
       super(flow: $refName$bindings);
''';
  return (
    argument: '  compiled: $compiled,\n',
    mount: '''
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
