import 'package:restage_shared/src/rfw_formats.dart';

const String _defaultIconFontFamily = 'MaterialIcons';
const String _codepointSuffix = 'Codepoint';
const String _fontFamilySuffix = 'FontFamily';

/// Literal icon code points in [library], keyed by font family.
///
/// Reads every `iconCodepoint` / `<name>IconCodepoint` argument whose value is
/// an int literal or a switch over int literals, paired with its sibling
/// `...FontFamily`. Data-bound code points and families are skipped.
Map<String, Set<int>> literalIconCodePoints(RemoteWidgetLibrary library) {
  final found = <String, Set<int>>{};
  void walk(Object? value) {
    if (value == null) return;
    if (value is ConstructorCall) {
      _collect(value.arguments, found);
      walk(value.arguments);
    } else if (value is WidgetBuilderDeclaration) {
      walk(value.widget);
    } else if (value is Loop) {
      walk(value.input);
      walk(value.output);
    } else if (value is Switch) {
      walk(value.input);
      for (final entry in value.outputs.entries) {
        walk(entry.key);
        walk(entry.value);
      }
    } else if (value is EventHandler) {
      walk(value.eventArguments);
    } else if (value is SetStateHandler) {
      walk(value.value);
    } else if (value is BoundArgsReference) {
      walk(value.arguments);
    } else if (value is BoundLoopReference) {
      walk(value.value);
    } else if (value is Map<Object?, Object?>) {
      value.values.forEach(walk);
    } else if (value is Iterable<Object?>) {
      value.forEach(walk);
    }
  }

  for (final widget in library.widgets) {
    walk(widget.initialState);
    walk(widget.root);
  }
  return found;
}

void _collect(Map<String, Object?> arguments, Map<String, Set<int>> found) {
  for (final entry in arguments.entries) {
    final key = entry.key;
    if (key != 'iconCodepoint' && !key.endsWith('Icon$_codepointSuffix')) {
      continue;
    }
    final familyKey =
        '${key.substring(0, key.length - _codepointSuffix.length)}'
        '$_fontFamilySuffix';
    final family = arguments[familyKey] ?? _defaultIconFontFamily;
    if (family is! String) continue;
    final codePoints = <int>{};
    _literalInts(entry.value, codePoints);
    if (codePoints.isEmpty) continue;
    found.putIfAbsent(family, () => <int>{}).addAll(codePoints);
  }
}

void _literalInts(Object? value, Set<int> out) {
  if (value is int) {
    out.add(value);
  } else if (value is Switch) {
    for (final output in value.outputs.values) {
      _literalInts(output, out);
    }
  }
}
