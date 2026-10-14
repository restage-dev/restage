import 'dart:convert' show jsonDecode, jsonEncode;

/// One step of an authored path.
sealed class PathStep {
  const PathStep();
}

/// An argument of a constructor call or an event handler.
final class SlotStep extends PathStep {
  /// Create a slot step.
  const SlotStep(this.name);

  /// Argument name.
  final String name;

  @override
  bool operator ==(Object other) => other is SlotStep && other.name == name;

  @override
  int get hashCode => Object.hash(SlotStep, name);
}

/// A key of a plain map value.
final class KeyStep extends PathStep {
  /// Create a key step.
  const KeyStep(this.name);

  /// Map key.
  final String name;

  @override
  bool operator ==(Object other) => other is KeyStep && other.name == name;

  @override
  int get hashCode => Object.hash(KeyStep, name);
}

/// An element of a list value.
final class IndexStep extends PathStep {
  /// Create an index step.
  const IndexStep(this.index);

  /// Zero-based list index.
  final int index;

  @override
  bool operator ==(Object other) => other is IndexStep && other.index == index;

  @override
  int get hashCode => Object.hash(IndexStep, index);
}

/// The value of one case of a switch, by position in its case list.
final class CaseStep extends PathStep {
  /// Create a case step.
  const CaseStep(this.index);

  /// Zero-based position among the switch's cases.
  final int index;

  @override
  bool operator ==(Object other) => other is CaseStep && other.index == index;

  @override
  int get hashCode => Object.hash(CaseStep, index);
}

/// The repeated body of a loop.
final class OutputStep extends PathStep {
  /// Create an output step.
  const OutputStep();

  @override
  bool operator ==(Object other) => other is OutputStep;

  @override
  int get hashCode => (OutputStep).hashCode;
}

/// The widget built by a widget-builder argument.
final class BodyStep extends PathStep {
  /// Create a body step.
  const BodyStep();

  @override
  bool operator ==(Object other) => other is BodyStep;

  @override
  int get hashCode => (BodyStep).hashCode;
}

/// The value written by a state-setting event handler.
final class ValueStep extends PathStep {
  /// Create a value step.
  const ValueStep();

  @override
  bool operator ==(Object other) => other is ValueStep;

  @override
  int get hashCode => (ValueStep).hashCode;
}

/// Strict JSON codec for compact authored-widget paths, and the one parser
/// for both path dialects.
///
/// A compact path starts with a widget declaration name, then repeats steps:
/// a bare slot name (with an optional list index), `$key` and a plain-map key,
/// `$case` and a case position, or one of `$output`, `$body`, `$value`. A slot
/// name that itself starts with `$` is written with one extra `$`, so slot
/// names are opaque: `args` has no structural meaning here.
///
/// The document dialect is the literal path into the editor document, with
/// `$key` preceding every plain-map key so keys never read as structure.
abstract final class DocumentPathCodec {
  static const String _key = r'$key';
  static const String _case = r'$case';
  static const String _output = r'$output';
  static const String _body = r'$body';
  static const String _value = r'$value';

  /// Encode [path] as the compact JSON representation used by marker keys.
  static String encode(List<Object> path) => jsonEncode(validate(path));

  /// Decode and validate a compact JSON marker key.
  static List<Object> decode(String encoded) {
    final Object? decoded = jsonDecode(encoded);
    if (decoded is! List<Object?>) {
      throw const FormatException('Document path must be a JSON array.');
    }
    final path = validate(decoded);
    if (jsonEncode(path) != encoded) {
      throw const FormatException(
        'Document path must use its canonical JSON encoding.',
      );
    }
    return path;
  }

  /// Validate [path] and return an immutable copy.
  static List<Object> validate(List<Object?> path) {
    parseCompact(path);
    return List<Object>.unmodifiable(path.cast<Object>());
  }

  /// The declaration name that starts [path].
  static String declarationOf(List<Object?> path) {
    if (path.isEmpty || path.first is! String) {
      throw const FormatException(
        'Document path must start with a widget declaration name.',
      );
    }
    return path.first! as String;
  }

  /// Parse a compact path into its steps, after the declaration name.
  static List<PathStep> parseCompact(List<Object?> path) {
    declarationOf(path);
    final steps = <PathStep>[];
    var index = 1;
    FormatException invalid() => FormatException(
          'Invalid compact document-path segment at index $index.',
        );
    while (index < path.length) {
      final segment = path[index];
      if (segment is int) {
        if (steps.isEmpty || !_takesIndex(steps.last) || segment < 0) {
          throw invalid();
        }
        steps.add(IndexStep(segment));
        index++;
        continue;
      }
      if (segment is! String) throw invalid();
      switch (segment) {
        case _key:
          final name = index + 1 < path.length ? path[index + 1] : null;
          if (name is! String) throw invalid();
          steps.add(KeyStep(name));
          index += 2;
        case _case:
          final position = index + 1 < path.length ? path[index + 1] : null;
          if (position is! int || position < 0) throw invalid();
          steps.add(CaseStep(position));
          index += 2;
        case _output:
          steps.add(const OutputStep());
          index++;
        case _body:
          steps.add(const BodyStep());
          index++;
        case _value:
          steps.add(const ValueStep());
          index++;
        default:
          if (segment.startsWith(r'$$')) {
            steps.add(SlotStep(segment.substring(1)));
          } else if (segment.startsWith(r'$')) {
            throw invalid();
          } else {
            steps.add(SlotStep(segment));
          }
          index++;
      }
    }
    return steps;
  }

  /// Parse a document-dialect path into its steps, after the declaration name.
  static List<PathStep> parseDocument(List<Object?> path) {
    declarationOf(path);
    final steps = <PathStep>[];
    var index = 1;
    FormatException invalid() => FormatException(
          'Invalid document-path segment at index $index.',
        );
    Object? at(int offset) =>
        index + offset < path.length ? path[index + offset] : null;
    while (index < path.length) {
      final segment = path[index];
      if (segment is int) {
        if (steps.isEmpty || !_takesIndex(steps.last) || segment < 0) {
          throw invalid();
        }
        steps.add(IndexStep(segment));
        index++;
        continue;
      }
      switch (segment) {
        case 'args':
          final name = at(1);
          if (name is! String) throw invalid();
          steps.add(SlotStep(name));
          index += 2;
        case _key:
          final name = at(1);
          if (name is! String) throw invalid();
          steps.add(KeyStep(name));
          index += 2;
        case 'cases':
          final position = at(1);
          if (position is! int || position < 0 || at(2) != 1) throw invalid();
          steps.add(CaseStep(position));
          index += 3;
        case 'output':
          steps.add(const OutputStep());
          index++;
        case 'body':
          steps.add(const BodyStep());
          index++;
        case 'value':
          steps.add(const ValueStep());
          index++;
        default:
          throw invalid();
      }
    }
    return steps;
  }

  /// The compact path of [declaration] followed by [steps].
  static List<Object> formatCompact(String declaration, List<PathStep> steps) {
    final path = <Object>[declaration];
    for (final step in steps) {
      switch (step) {
        case SlotStep(:final name):
          path.add(name.startsWith(r'$') ? '\$$name' : name);
        case KeyStep(:final name):
          path
            ..add(_key)
            ..add(name);
        case IndexStep(:final index):
          path.add(index);
        case CaseStep(:final index):
          path
            ..add(_case)
            ..add(index);
        case OutputStep():
          path.add(_output);
        case BodyStep():
          path.add(_body);
        case ValueStep():
          path.add(_value);
      }
    }
    return List<Object>.unmodifiable(path);
  }

  /// The document-dialect path of [declaration] followed by [steps].
  static List<Object> formatDocument(String declaration, List<PathStep> steps) {
    final path = <Object>[declaration];
    for (final step in steps) {
      switch (step) {
        case SlotStep(:final name):
          path
            ..add('args')
            ..add(name);
        case KeyStep(:final name):
          path
            ..add(_key)
            ..add(name);
        case IndexStep(:final index):
          path.add(index);
        case CaseStep(:final index):
          path
            ..add('cases')
            ..add(index)
            ..add(1);
        case OutputStep():
          path.add('output');
        case BodyStep():
          path.add('body');
        case ValueStep():
          path.add('value');
      }
    }
    return List<Object>.unmodifiable(path);
  }

  static bool _takesIndex(PathStep step) => step is! IndexStep;
}
