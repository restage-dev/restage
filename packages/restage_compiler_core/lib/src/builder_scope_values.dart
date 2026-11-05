import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;

/// The native values each builder scope in [library] supplies, by scope name
/// and key: a lambda passed to a builder slot whose catalog contract declares
/// native values reads them as `<scope>.values.<key>`.
///
/// Throws [FormatException] when two slots declare one key of one scope as
/// different values.
Map<String, Map<String, NativeBindingContract>> rfwBuilderScopeValues(
  rfw.RemoteWidgetLibrary library,
  Catalog catalog,
) {
  final local = {for (final widget in library.widgets) widget.name};
  final scopes = <String, Map<String, NativeBindingContract>>{};
  void declare(String scope, Map<String, WidgetBuilderNativeValue> values) {
    final declared = scopes[scope] ??= {};
    for (final MapEntry(:key, :value) in values.entries) {
      final contract =
          NativeBindingContract(type: value.type, nullable: value.nullable);
      final previous = declared.putIfAbsent(key, () => contract);
      if (previous != contract) {
        throw FormatException('Conflicting builder scope value "$scope.$key".');
      }
    }
  }

  // The lambda names a builder slot's value passes its body.
  Iterable<String> lambdas(Object? value) sync* {
    switch (value) {
      case rfw.WidgetBuilderDeclaration(:final argumentName):
        yield argumentName;
      case rfw.ConstructorCall(:final arguments):
        yield* lambdas(arguments['bodies']);
      case final List<Object?> list:
        for (final item in list) {
          yield* lambdas(item);
        }
    }
  }

  void visit(Object? node) {
    switch (node) {
      case rfw.ConstructorCall(:final name, :final arguments):
        if (!local.contains(name)) {
          for (final entry in catalog.widgets) {
            if (entry.name != name) continue;
            for (final property in entry.properties) {
              final values = property.builderContract?.nativeValues;
              if (values == null || values.isEmpty) continue;
              for (final scope in lambdas(arguments[property.name])) {
                declare(scope, values);
              }
            }
          }
        }
        visit(arguments);
      case final Map<Object?, Object?> map:
        map.values.forEach(visit);
      case final List<Object?> list:
        list.forEach(visit);
      case rfw.Switch(:final input, :final outputs):
        visit(input);
        outputs.values.forEach(visit);
      case rfw.Loop(:final input, :final output):
        visit(input);
        visit(output);
      case rfw.WidgetBuilderDeclaration(:final widget):
        visit(widget);
      case rfw.EventHandler(:final eventArguments):
        visit(eventArguments);
    }
  }

  for (final widget in library.widgets) {
    visit(widget.root);
  }
  return scopes;
}
