import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:restage_codegen/src/a2ui/a2ui_dart_emitter.dart';
import 'package:restage_codegen/src/a2ui/a2ui_definition_registry.dart';
import 'package:restage_codegen/src/a2ui/a2ui_example_loader.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_node.dart';
import 'package:restage_codegen/src/a2ui/a2ui_schema_semantics.dart';

/// A canonical example that has passed the complete catalog-plan schema and
/// component-graph validation.
@immutable
final class ValidatedA2uiExample {
  /// Creates a validated example over its original loaded source and canonical
  /// JSON representation.
  const ValidatedA2uiExample({
    required this.example,
    required this.canonicalJson,
  });

  /// The deeply immutable, source-anchored example that was validated.
  final LoadedA2uiExample example;

  /// Compact JSON with recursively sorted object keys and preserved array and
  /// numeric kinds.
  final String canonicalJson;
}

/// Validates every exact GenUI component array directly against [plan].
///
/// This is the build-time semantic gate shared with the emitter's classified
/// field IR. It deliberately imports no Flutter, GenUI, or JSON-schema runtime.
List<ValidatedA2uiExample> validateA2uiExamples({
  required A2uiDartCatalogPlan plan,
  required Iterable<LoadedA2uiExample> examples,
}) =>
    List<ValidatedA2uiExample>.unmodifiable([
      for (final example in examples)
        _A2uiExampleValidator(plan, example).validate(),
    ]);

/// Indexes validated canonical examples for deterministic Dart emission.
///
/// Both levels are sorted and unmodifiable. Discovery already rejects a
/// duplicate name on one widget, but this seam fails loud too so no alternate
/// validated-example producer can silently overwrite authored data.
Map<String, Map<String, String>> buildA2uiExampleRegistry(
  Iterable<ValidatedA2uiExample> examples,
) {
  final byWidget = <String, Map<String, String>>{};
  for (final validated in examples) {
    final anchor = validated.example.anchor;
    final byName = byWidget.putIfAbsent(
      anchor.widgetName,
      () => <String, String>{},
    );
    if (byName.containsKey(anchor.exampleName)) {
      throw A2uiExampleException(
        'duplicate example name "${anchor.exampleName}" for this catalog '
        'item',
        anchor,
      );
    }
    byName[anchor.exampleName] = validated.canonicalJson;
  }

  final widgetNames = byWidget.keys.toList()..sort();
  return Map<String, Map<String, String>>.unmodifiable({
    for (final widgetName in widgetNames)
      widgetName: Map<String, String>.unmodifiable({
        for (final exampleName in (byWidget[widgetName]!.keys.toList()..sort()))
          exampleName: byWidget[widgetName]![exampleName],
      }),
  });
}

final class _A2uiExampleValidator {
  _A2uiExampleValidator(A2uiDartCatalogPlan plan, this.example)
      : widgetPlans = plan.widgets;

  final LoadedA2uiExample example;
  final List<A2uiDartWidgetPlan> widgetPlans;
  late final Map<String, _WidgetSchema> widgets;
  final Map<String, _Component> componentsById = {};
  final List<_Component> components = [];
  final Map<String, List<_ChildEdge>> edges = {};

  ValidatedA2uiExample validate() {
    _indexSchemaPlan();
    _preflightSchemaIr();
    _indexComponentEnvelope();
    final root = componentsById['root'];
    if (root == null) {
      _fail(
        'the graph must contain exactly one component ID "root"',
        componentPath: '/',
        schemaPath: '/componentGraph/root',
      );
    }
    if (root.widget.plan.entry.name != example.anchor.widgetName) {
      _fail(
        'component "root" must have component type '
        '"${example.anchor.widgetName}", not "${root.widget.plan.entry.name}"',
        component: root,
        componentPath: _path(root.index, 'component'),
        schemaPath: '/componentGraph/root/component',
      );
    }

    components.forEach(_validateComponent);
    _validateGraph();

    return ValidatedA2uiExample(
      example: example,
      canonicalJson: jsonEncode(_canonicalize(example.components)),
    );
  }

  void _indexSchemaPlan() {
    final plansByName = <String, List<A2uiDartWidgetPlan>>{};
    for (final plan in widgetPlans) {
      plansByName.putIfAbsent(plan.entry.name, () => []).add(plan);
    }
    final duplicateNames = plansByName.entries
        .where((entry) => entry.value.length > 1)
        .map((entry) => entry.key)
        .toList()
      ..sort();
    if (duplicateNames.isNotEmpty) {
      final name = duplicateNames.first;
      final libraries = plansByName[name]!
          .map((plan) => plan.entry.library.namespace)
          .toList()
        ..sort();
      _fail(
        'duplicate catalog plan component name "$name" across libraries '
        '${libraries.join(', ')}',
        componentId: '<plan>',
        componentPath: '/',
        schemaPath: '/components/${_pointer(name)}',
      );
    }
    final indexed = <String, _WidgetSchema>{};
    for (final entry in plansByName.entries) {
      try {
        indexed[entry.key] = _WidgetSchema(entry.value.single);
        // The schema registry reports malformed IR as StateError. Re-anchor
        // that internal failure to the canonical example schema path.
        // ignore: avoid_catching_errors
      } on StateError catch (error) {
        _fail(
          'catalog schema plan is invalid: $error',
          componentId: '<plan>',
          componentPath: '/',
          schemaPath: '/components/${_pointer(entry.key)}',
        );
      }
    }
    widgets = indexed;
  }

  void _preflightSchemaIr() {
    for (final widget in widgets.values) {
      final visitedDefinitions = <String>{};
      for (final field in widget.layout.fields) {
        if (field.emission case A2uiDataField(:final node)) {
          _preflightNode(
            node,
            widget,
            widget.fieldSchemaPath(field.name),
            visitedDefinitions,
          );
        }
      }
    }
  }

  void _preflightNode(
    A2uiSchemaNode node,
    _WidgetSchema widget,
    String schemaPath,
    Set<String> visitedDefinitions, {
    bool atDefinitionRoot = false,
  }) {
    var effectiveSchemaPath = schemaPath;
    if (!atDefinitionRoot && node is ObjectNode) {
      final defId = node.defId;
      if (defId != null && widget.isHoistedDefinition(defId)) {
        effectiveSchemaPath = widget.definitionSchemaPath(defId);
      }
    }
    switch (node) {
      case ScalarNode() || EnumNode():
        return;
      case ListNode(:final element):
        _preflightNode(
          element,
          widget,
          '$effectiveSchemaPath/items',
          visitedDefinitions,
        );
      case ObjectNode(:final fields):
        for (final entry in fields.entries) {
          _preflightNode(
            entry.value,
            widget,
            '$effectiveSchemaPath/properties/${_pointer(entry.key)}',
            visitedDefinitions,
          );
        }
      case MapNode(:final valueType):
        _preflightNode(
          valueType,
          widget,
          '$effectiveSchemaPath/additionalProperties',
          visitedDefinitions,
        );
      case RefNode(:final defId):
        final definitionPath = widget.definitionSchemaPath(defId);
        final definition = widget.definitions.definitions[defId];
        if (definition == null) {
          _fail(
            'reference "$defId" has no canonical definition',
            componentId: '<plan>',
            componentPath: '/',
            schemaPath: definitionPath,
          );
        }
        if (!visitedDefinitions.add(defId)) return;
        _preflightNode(
          definition,
          widget,
          definitionPath,
          visitedDefinitions,
          atDefinitionRoot: true,
        );
      case UnionNode():
        _fail(
          'UnionNode has no emitted A2UI schema projection',
          componentId: '<plan>',
          componentPath: '/',
          schemaPath: effectiveSchemaPath,
        );
    }
  }

  void _indexComponentEnvelope() {
    for (var index = 0; index < example.components.length; index++) {
      final data = example.components[index];
      final id = data['id'];
      if (id is! String) {
        _fail(
          'component ID must be a string',
          componentId: '<invalid>',
          componentPath: _path(index, 'id'),
          schemaPath: '/componentGraph/ids',
        );
      }
      if (id.isEmpty) {
        _fail(
          'component ID must be non-empty',
          componentId: id,
          componentPath: _path(index, 'id'),
          schemaPath: '/componentGraph/ids',
        );
      }
      if (componentsById.containsKey(id)) {
        _fail(
          'duplicate component ID "$id"',
          componentId: id,
          componentPath: _path(index, 'id'),
          schemaPath: '/componentGraph/ids',
        );
      }

      final componentName = data['component'];
      if (componentName is! String) {
        _fail(
          'component type must be a string',
          componentId: id,
          componentPath: _path(index, 'component'),
          schemaPath: '/componentGraph/components',
        );
      }
      final widget = widgets[componentName];
      if (widget == null) {
        _fail(
          'component type "$componentName" is not in the generated '
          'custom-only catalog',
          componentId: id,
          componentPath: _path(index, 'component'),
          schemaPath: '/componentGraph/components',
        );
      }

      final component = _Component(
        index: index,
        id: id,
        data: data,
        widget: widget,
      );
      components.add(component);
      componentsById[id] = component;
      edges[id] = [];
    }
  }

  void _validateComponent(_Component component) {
    for (final field in component.widget.layout.fields) {
      final name = field.name;
      final componentPath = _path(component.index, name);
      final schemaPath = component.widget.fieldSchemaPath(name);
      if (!component.data.containsKey(name)) {
        if (field.required) {
          _fail(
            'required property is missing',
            component: component,
            componentPath: componentPath,
            schemaPath: schemaPath,
          );
        }
        continue;
      }

      final value = component.data[name];
      switch (field.emission) {
        case A2uiDataField(
            :final node,
            :final writeBack,
            :final constraints,
          ):
          if (a2uiUsesValueReferenceSchema(node, writeBack: writeBack) &&
              value is Map<String, Object?>) {
            final arm = value.containsKey('path')
                ? 'path'
                : value.containsKey('call')
                    ? 'call'
                    : null;
            if (arm != null) {
              _fail(
                'deferred {$arm} value references are not canonical literals',
                component: component,
                componentPath: componentPath,
                schemaPath: schemaPath,
              );
            }
          }
          final isNull = value == null;
          _validateNode(
            value,
            node,
            component,
            componentPath,
            schemaPath,
            component.widget,
          );
          if (!isNull) {
            _validateConstraints(
              value,
              constraints,
              component,
              componentPath,
              schemaPath,
            );
          }
        case A2uiChildField(:final slot):
          _validateChildSlot(
            value,
            slot,
            component,
            componentPath,
            schemaPath,
          );
      }
    }
  }

  void _validateNode(
    Object? value,
    A2uiSchemaNode node,
    _Component component,
    String componentPath,
    String schemaPath,
    _WidgetSchema widget, {
    bool atDefinitionRoot = false,
  }) {
    var effectiveSchemaPath = schemaPath;
    if (!atDefinitionRoot && node is ObjectNode) {
      final defId = node.defId;
      if (defId != null && widget.isHoistedDefinition(defId)) {
        effectiveSchemaPath = widget.definitionSchemaPath(defId);
      }
    }
    if (value == null) {
      if (node.nullable) return;
      _fail(
        'null is not accepted by this schema',
        component: component,
        componentPath: componentPath,
        schemaPath: effectiveSchemaPath,
      );
    }

    switch (node) {
      case ScalarNode(:final type):
        final valid = switch (type) {
          A2uiScalarType.string => value is String,
          A2uiScalarType.boolean => value is bool,
          A2uiScalarType.number => value is num && value.isFinite,
          A2uiScalarType.integer => value is int ||
              (value is double && value.isFinite && value == value.truncate()),
        };
        if (!valid) {
          final expected = switch (type) {
            A2uiScalarType.string => 'JSON string',
            A2uiScalarType.boolean => 'JSON boolean',
            A2uiScalarType.number => 'finite JSON number',
            A2uiScalarType.integer => 'JSON integer',
          };
          _fail(
            'expected $expected',
            component: component,
            componentPath: componentPath,
            schemaPath: effectiveSchemaPath,
          );
        }
      case EnumNode(:final members):
        if (value is! String) {
          _fail(
            'expected JSON string for resolved enum member',
            component: component,
            componentPath: componentPath,
            schemaPath: effectiveSchemaPath,
          );
        }
        if (members.isNotEmpty && !members.contains(value)) {
          _fail(
            'expected a resolved enum member: ${members.join(', ')}',
            component: component,
            componentPath: componentPath,
            schemaPath: effectiveSchemaPath,
          );
        }
      case ListNode(:final element):
        if (value is! List<Object?>) {
          _fail(
            'expected JSON array',
            component: component,
            componentPath: componentPath,
            schemaPath: effectiveSchemaPath,
          );
        }
        for (var index = 0; index < value.length; index++) {
          _validateNode(
            value[index],
            element,
            component,
            _path(componentPath, index),
            '$effectiveSchemaPath/items',
            widget,
          );
        }
      case ObjectNode(:final fields, :final required):
        if (value is! Map<String, Object?>) {
          _fail(
            'expected JSON object',
            component: component,
            componentPath: componentPath,
            schemaPath: effectiveSchemaPath,
          );
        }
        for (final name in required) {
          if (!value.containsKey(name)) {
            _fail(
              'required property is missing',
              component: component,
              componentPath: _path(componentPath, name),
              schemaPath: '$effectiveSchemaPath/properties/${_pointer(name)}',
            );
          }
        }
        for (final entry in fields.entries) {
          if (!value.containsKey(entry.key)) continue;
          _validateNode(
            value[entry.key],
            entry.value,
            component,
            _path(componentPath, entry.key),
            '$effectiveSchemaPath/properties/${_pointer(entry.key)}',
            widget,
          );
        }
      case MapNode(:final valueType):
        if (value is! Map<String, Object?>) {
          _fail(
            'expected JSON object',
            component: component,
            componentPath: componentPath,
            schemaPath: effectiveSchemaPath,
          );
        }
        for (final entry in value.entries) {
          _validateNode(
            entry.value,
            valueType,
            component,
            _path(componentPath, entry.key),
            '$effectiveSchemaPath/additionalProperties',
            widget,
          );
        }
      case RefNode(:final defId):
        _validateNode(
          value,
          widget.definitions.definitionFor(defId),
          component,
          componentPath,
          widget.definitionSchemaPath(defId),
          widget,
          atDefinitionRoot: true,
        );
      case UnionNode():
        _fail(
          'UnionNode has no emitted A2UI schema projection',
          component: component,
          componentPath: componentPath,
          schemaPath: effectiveSchemaPath,
        );
    }
  }

  void _validateConstraints(
    Object? value,
    A2uiConstraintSet constraints,
    _Component component,
    String componentPath,
    String schemaPath,
  ) {
    for (final entry in constraints.keywords.entries) {
      final keyword = entry.key;
      final boundary = entry.value;
      final valid = switch (keyword) {
        'minimum' => value is num && value >= (boundary! as num),
        'exclusiveMinimum' => value is num && value > (boundary! as num),
        'maximum' => value is num && value <= (boundary! as num),
        'exclusiveMaximum' => value is num && value < (boundary! as num),
        'enum' => (boundary! as List<Object?>)
            .any((candidate) => _deepJsonEquals(candidate, value)),
        'pattern' => value is String &&
            RegExp(boundary! as String, unicode: true).hasMatch(value),
        'minLength' =>
          value is String && value.runes.length >= (boundary! as int),
        'maxLength' =>
          value is String && value.runes.length <= (boundary! as int),
        'minItems' =>
          value is List<Object?> && value.length >= (boundary! as int),
        'maxItems' =>
          value is List<Object?> && value.length <= (boundary! as int),
        _ => false,
      };
      if (!valid) {
        _fail(
          'value violates $keyword constraint',
          component: component,
          componentPath: componentPath,
          schemaPath: '$schemaPath/$keyword',
        );
      }
    }
  }

  void _validateChildSlot(
    Object? value,
    A2uiChildSlot slot,
    _Component component,
    String componentPath,
    String schemaPath,
  ) {
    if (value == null) {
      if (slot.nullable) return;
      _fail(
        'null is not accepted by this child schema',
        component: component,
        componentPath: componentPath,
        schemaPath: schemaPath,
      );
    }
    switch (slot) {
      case A2uiChildNode():
        if (value is! String) {
          _fail(
            'expected child component ID string',
            component: component,
            componentPath: componentPath,
            schemaPath: schemaPath,
          );
        }
        _addChildEdge(
          component,
          value,
          componentPath,
          schemaPath,
        );
      case A2uiChildrenNode():
        if (value is! List<Object?>) {
          _fail(
            'expected child component ID array',
            component: component,
            componentPath: componentPath,
            schemaPath: schemaPath,
          );
        }
        for (var index = 0; index < value.length; index++) {
          final target = value[index];
          if (target is! String) {
            _fail(
              'expected child component ID string',
              component: component,
              componentPath: _path(componentPath, index),
              schemaPath: '$schemaPath/items',
            );
          }
          _addChildEdge(
            component,
            target,
            _path(componentPath, index),
            '$schemaPath/items',
          );
        }
    }
  }

  void _addChildEdge(
    _Component component,
    String target,
    String componentPath,
    String schemaPath,
  ) {
    if (!componentsById.containsKey(target)) {
      _fail(
        'child target "$target" does not exist',
        component: component,
        componentPath: componentPath,
        schemaPath: schemaPath,
      );
    }
    edges[component.id]!.add(
      _ChildEdge(
        source: component,
        target: target,
        componentPath: componentPath,
        schemaPath: schemaPath,
      ),
    );
  }

  void _validateGraph() {
    final states = <String, _VisitState>{};
    final stack = <String>[];

    void visit(String id) {
      states[id] = _VisitState.visiting;
      stack.add(id);
      for (final edge in edges[id]!) {
        switch (states[edge.target]) {
          case _VisitState.visiting:
            final cycleStart = stack.indexOf(edge.target);
            final cycle = [...stack.sublist(cycleStart), edge.target];
            _fail(
              'component graph cycle: ${cycle.join(' -> ')}',
              component: edge.source,
              componentPath: edge.componentPath,
              schemaPath: '/componentGraph/acyclic',
            );
          case _VisitState.visited:
            break;
          case null:
            visit(edge.target);
        }
      }
      stack.removeLast();
      states[id] = _VisitState.visited;
    }

    for (final component in components) {
      if (states[component.id] == null) visit(component.id);
    }

    final reachable = <String>{};
    void markReachable(String id) {
      if (!reachable.add(id)) return;
      for (final edge in edges[id]!) {
        markReachable(edge.target);
      }
    }

    markReachable('root');
    final unreachable = componentsById.keys
        .where((id) => !reachable.contains(id))
        .toList()
      ..sort();
    if (unreachable.isNotEmpty) {
      final component = componentsById[unreachable.first]!;
      _fail(
        'components unreachable from "root": ${unreachable.join(', ')}',
        component: component,
        componentPath: '/${component.index}',
        schemaPath: '/componentGraph/reachable',
      );
    }
  }

  Never _fail(
    String detail, {
    required String componentPath,
    required String schemaPath,
    _Component? component,
    String? componentId,
  }) {
    throw A2uiExampleException(
      'component "${component?.id ?? componentId ?? '<graph>'}"; '
      'component path "$componentPath"; schema path "$schemaPath": $detail',
      example.anchor,
    );
  }
}

final class _WidgetSchema {
  _WidgetSchema(this.plan) : layout = a2uiWidgetSchemaLayoutForPlan(plan);

  final A2uiDartWidgetPlan plan;
  final A2uiWidgetSchemaLayout layout;

  A2uiDefinitionRegistry get definitions => layout.registry;

  Map<String, String> get safeDefinitionKeys => layout.safeDefinitionKeys;

  String get componentSchemaPath => '/components/${_pointer(plan.entry.name)}';

  String get dataRootSchemaPath {
    if (!layout.includesSyntheticRoot) return componentSchemaPath;
    final rootKey = safeDefinitionKeys[a2uiSyntheticRootDefinitionId]!;
    return '$componentSchemaPath/\$defs/${_pointer(rootKey)}';
  }

  String fieldSchemaPath(String fieldName) =>
      '$dataRootSchemaPath/properties/${_pointer(fieldName)}';

  bool isHoistedDefinition(String definitionId) =>
      layout.hoistTargets.contains(definitionId);

  String definitionSchemaPath(String definitionId) {
    final key = safeDefinitionKeys[definitionId];
    if (key == null) {
      throw StateError(
        'A2UI example validation: no emitted definition key for '
        '"$definitionId" on component "${plan.entry.name}".',
      );
    }
    return '$componentSchemaPath/\$defs/${_pointer(key)}';
  }
}

final class _Component {
  const _Component({
    required this.index,
    required this.id,
    required this.data,
    required this.widget,
  });

  final int index;
  final String id;
  final Map<String, Object?> data;
  final _WidgetSchema widget;
}

final class _ChildEdge {
  const _ChildEdge({
    required this.source,
    required this.target,
    required this.componentPath,
    required this.schemaPath,
  });

  final _Component source;
  final String target;
  final String componentPath;
  final String schemaPath;
}

enum _VisitState { visiting, visited }

String _path(Object parent, Object segment) {
  final prefix = parent is int ? '/$parent' : parent as String;
  return '$prefix/${_pointer(segment.toString())}';
}

String _pointer(String segment) =>
    segment.replaceAll('~', '~0').replaceAll('/', '~1');

Object? _canonicalize(Object? value) {
  if (value is List<Object?>) {
    return [for (final item in value) _canonicalize(item)];
  }
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  return value;
}

bool _deepJsonEquals(Object? first, Object? second) {
  if (first is num && second is num) return first == second;
  if (first is List<Object?> && second is List<Object?>) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (!_deepJsonEquals(first[index], second[index])) return false;
    }
    return true;
  }
  if (first is Map<String, Object?> && second is Map<String, Object?>) {
    if (first.length != second.length) return false;
    for (final entry in first.entries) {
      if (!second.containsKey(entry.key) ||
          !_deepJsonEquals(entry.value, second[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return first == second;
}
