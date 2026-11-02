import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/surface_publication/generated_handle_names.dart';
import 'package:restage_codegen/src/theme_recognition.dart';
import 'package:restage_codegen/src/widget_constructor_facts.dart';
import 'package:restage_shared/restage_shared.dart';

/// The package-local handoff carrying the capture plan to the outputs builder.
const String kRestageSurfaceCapturePlanCompilerPath =
    'lib/src/surface_publication/surface_capture.compiler.json';

/// The capture plan's file name, written beside the publication manifest.
const String kRestageSurfaceCapturePlanFileName = 'restage.capture.json';

/// The capture plan's shape version.
const int kRestageSurfaceCapturePlanVersion = 1;

/// The key a surface's plan is stored under: `<surface>.<slug>`.
String surfaceCapturePlanKey(Surface surface, String slug) =>
    '${surface.wireName}.$slug';

/// How a push draws [declaration]'s flow: its first screen, from its ref.
Map<String, Object?> captureFlowPlan(Element declaration) => {
  'kind': 'flow',
  'importUri': declaration.library!.identifier,
  'ref': generatedHandleName(declaration.name!, fallback: 'surfaceFlow'),
};

/// How a push constructs the surface widget [widget] from sample host data.
Map<String, Object?> captureWidgetPlan(ClassElement widget) =>
    _CapturePlanner().object(widget, root: true);

final class _CapturePlanner {
  final Set<ClassElement> _active = Set.identity();

  /// A root widget's sample is keyed by parameter, a host-data class's by
  /// field.
  Map<String, Object?> object(ClassElement cls, {bool root = false}) {
    final name = cls.name ?? '<unnamed>';
    if (name.startsWith('_')) return {'kind': 'private', 'name': name};
    final constructor = cls.constructors
        .where(
          (candidate) =>
              candidate.isGenerative &&
              !candidate.isFactory &&
              const {null, '', 'new'}.contains(candidate.name),
        )
        .firstOrNull;
    if (cls.isAbstract ||
        cls.typeParameters.isNotEmpty ||
        constructor == null ||
        cls.library.identifier.startsWith('dart:')) {
      return {'kind': 'unconstructible', 'name': name};
    }
    if (!_active.add(cls)) return {'kind': 'recursive', 'name': name};
    try {
      return {
        'kind': 'object',
        'importUri': cls.library.identifier,
        'name': name,
        'parameters': [
          for (final formal in constructor.formalParameters)
            _parameter(cls, constructor, formal, root: root),
        ],
      };
    } finally {
      _active.remove(cls);
    }
  }

  Map<String, Object?> _parameter(
    ClassElement cls,
    ConstructorElement constructor,
    FormalParameterElement formal, {
    required bool root,
  }) {
    final resolved = resolveWidgetConstructorFormal(cls, constructor, formal);
    final name = formal.name ?? '';
    return {
      'name': name,
      'named': formal.isNamed,
      'required': formal.isRequiredPositional || formal.isRequiredNamed,
      'hasDefault': formal.hasDefaultValue,
      // Null when no field holds the parameter, so the push says it drew
      // without the sample.
      'sampleKey': root
          ? name
          : resolved.field?.name ??
                (cls.fields.any(
                      (field) => !field.isStatic && field.name == name,
                    )
                    ? name
                    : null),
      'type': type(resolved.type),
    };
  }

  Map<String, Object?> type(DartType type) {
    final nullable =
        type.nullabilitySuffix == NullabilitySuffix.question ||
        type is DynamicType;
    final shape = _shape(type);
    return {...shape, if (nullable) 'nullable': true};
  }

  Map<String, Object?> _shape(DartType type) {
    if (type is DynamicType) return {'kind': 'json'};
    if (type is! InterfaceType) {
      return {'kind': 'unbuildable', 'display': type.getDisplayString()};
    }
    final arguments = type.typeArguments;
    if (type.isDartCoreObject) return {'kind': 'json'};
    if (type.isDartCoreBool) return {'kind': 'bool'};
    if (type.isDartCoreInt) return {'kind': 'int'};
    if (type.isDartCoreDouble) return {'kind': 'double'};
    if (type.isDartCoreNum) return {'kind': 'num'};
    if (type.isDartCoreString) return {'kind': 'string'};
    if (type.isDartCoreList && arguments.length == 1) {
      return {'kind': 'list', 'item': this.type(arguments.single)};
    }
    if (type.isDartCoreSet && arguments.length == 1) {
      return {'kind': 'set', 'item': this.type(arguments.single)};
    }
    if (type.isDartCoreMap && arguments.length == 2) {
      return {'kind': 'map', 'value': this.type(arguments.last)};
    }
    final element = type.element;
    final library = element.library.identifier;
    if (library == 'dart:core' &&
        const {'DateTime', 'Duration'}.contains(element.name)) {
      return {'kind': 'value', 'name': element.name};
    }
    if (element.name == 'Color' && isFrameworkValueTypeLibrary(element)) {
      return {'kind': 'value', 'name': 'Color'};
    }
    if (element is EnumElement) {
      return {
        'kind': 'enum',
        'importUri': library,
        'name': element.name,
        'values': [
          for (final constant in element.constants) constant.name,
        ],
      };
    }
    if (element is ClassElement && !isFrameworkValueTypeLibrary(element)) {
      return object(element);
    }
    return {'kind': 'unbuildable', 'display': type.getDisplayString()};
  }
}
