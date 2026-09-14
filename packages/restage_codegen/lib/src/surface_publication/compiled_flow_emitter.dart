import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/owning_library_namespace.dart';
import 'package:restage_codegen/src/surface_publication/generated_handle_names.dart';
import 'package:restage_shared/restage_shared.dart';

/// Generated original-graph argument and the typed mount that binds it.
typedef CompiledFlowEmission = ({String argument, String mount});

/// Retains the existing canonical documents and original Flutter constructors.
CompiledFlowEmission emitCompiledFlow({
  required FlowDocument document,
  required Map<String, FlowDocument> descendants,
  required Map<String, ClassElement> screens,
  required LibraryElement library,
  required String refName,
  required String mountName,
  required String resultType,
}) {
  final namespace = OwningLibraryNamespace(library);
  final sdk = namespace.prefixForOrigin('package:restage', const {
    'CompiledFlow',
    'CompiledFlowScreenBuilder',
    'RestageFlowGraph',
    'FlowUnavailablePolicy',
  });
  // Like generated screen mounts, preserve descriptor-only imports.
  if (sdk == null) return (argument: '', mount: '');
  final builders = <String, String>{};
  String encode(FlowDocument doc) {
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
        constructors.add('${_string(id)}: $name.new,');
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
      if (child != null) children.add('${_string(id)}: ${encode(child)},');
    }
    return '''
${sdk}CompiledFlow(
      documentJson: ${_string(utf8.decode(FlowDocumentCodec.encodeCanonicalJson(doc)))},
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
    ${builders.entries.map((entry) => '${_string(entry.key)}: ${entry.value},').join('\n')}
  }''';
  return (
    argument: '  compiled: $compiled,\n',
    mount: '''
/// Mounts the authored flow with hosted delivery and a compiled original fallback.
final class $mountName extends ${sdk}RestageFlowGraph<$resultType> {
  ${builders.isEmpty ? 'const ' : ''}$mountName({
    super.key,
    $requiredBuilders
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
  }) : super(flow: $refName$bindings);
}
''',
  );
}

String _string(String value) => jsonEncode(value).replaceAll(r'$', r'\$');
