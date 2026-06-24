/// Pure AST recognition for the vanilla-Flutter `SegmentedButton<String>(...)`
/// idiom that lowers to the compiled catalog widget `RestageSegmentedButton`:
///
/// * a `SegmentedButton<String>` with `segments:` (a static list of
///   `ButtonSegment(value:, label: Text('…'))` leaves), an optional `selected:`
///   (a set / list literal of selected values), an optional
///   `onSelectionChanged:` (`ValueChanged<Set<String>>`), and the optional
///   declarative `multiSelectionEnabled:` / `emptySelectionAllowed:` bools.
///
/// The recogniser extracts the per-segment `{value, label}` expression pairs,
/// the `selected` value expressions, the `onSelectionChanged` expression, and
/// the declarative bools — or a single loud-defer reason.
/// **Carry-all-or-defer at every leaf:** a non-`String` (or inferred
/// non-`String`) generic, a non-list / dynamic / builder / spread `segments`, a
/// leaf that is not a `ButtonSegment`, an icon-only / non-literal-`Text` label,
/// a missing `value`, a behavioral carrier arg (`enabled:` / `tooltip:`), a
/// non-literal `selected` collection, or a duplicate value defers the WHOLE
/// widget — never a partial, reordered, or wrong set. The dispatch site in the
/// translator owns the framework-identity gate on the outer widget and the
/// emission of the recognised parts; this module owns the shape recognition
/// only.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/theme_recognition.dart';

/// One recognised segment — the `value` and `label` source expressions, to be
/// translated and emitted by the dispatch site.
final class RecognisedSegment {
  /// Creates a recognised segment.
  const RecognisedSegment({required this.value, required this.label});

  /// The segment's `value:` argument expression (lowers to the option key).
  final Expression value;

  /// The literal `Text` label's string-content expression (lowers to the
  /// display label).
  final Expression label;
}

/// The recognised parts of a segmented-button construction.
final class RecognisedSegmentedButton {
  /// Creates a recognised segmented button.
  const RecognisedSegmentedButton({
    required this.segments,
    required this.selectedValues,
    this.onSelectionChanged,
    this.multiSelectionEnabled,
    this.emptySelectionAllowed,
  });

  /// The segments in source order, each a `{value, label}` expression pair.
  final List<RecognisedSegment> segments;

  /// The selected-value expressions (the elements of the `selected:`
  /// collection), in source order. Empty when the author supplied no
  /// `selected:` (or an empty collection).
  final List<Expression> selectedValues;

  /// The settled-selection callback expression (`onSelectionChanged:`), or
  /// `null` when the author supplied none.
  final Expression? onSelectionChanged;

  /// The `multiSelectionEnabled:` expression, or `null` when the author left
  /// it at the default.
  final Expression? multiSelectionEnabled;

  /// The `emptySelectionAllowed:` expression, or `null` when the author left
  /// it at the default.
  final Expression? emptySelectionAllowed;
}

/// Outcome of recognising a segmented-button construction.
sealed class SegmentedButtonOutcome {
  const SegmentedButtonOutcome();
}

/// The construction is a clean, fully-extractable segmented button.
final class SegmentedButtonRecognised extends SegmentedButtonOutcome {
  /// Creates a recognised outcome.
  const SegmentedButtonRecognised(this.recognised);

  /// The extracted parts.
  final RecognisedSegmentedButton recognised;
}

/// The construction is the right widget but an unparseable shape — defer the
/// whole widget loud with [reason].
final class SegmentedButtonDeferred extends SegmentedButtonOutcome {
  /// Creates a deferred outcome.
  const SegmentedButtonDeferred(this.reason);

  /// Author-facing reason for the fatal defer.
  final String reason;
}

/// Recognises a `SegmentedButton` (`<String>`) with `segments:` / `selected:`
/// / `onSelectionChanged:` / the declarative bools. The caller has already
/// confirmed the outer widget is the framework `SegmentedButton`.
///
/// The compiled target (`RestageSegmentedButtonString`) is a String-keyed
/// selector: the wire carries String segment values and the decoder reads them
/// as `String`. A `SegmentedButton<int>` / `<Object>` / any resolved non-String
/// specialization would silently drop or mis-key its segment values, so the
/// type-argument gate ([_typeArgumentGate]) defers loud on a resolved
/// non-String `<T>` and recognises only a resolved `<String>` (or an unresolved
/// synthetic-test construction, by name-fallback).
SegmentedButtonOutcome recogniseSegmentedButton(
  InstanceCreationExpression creation,
) {
  // A named constructor is not the carrier we recognise (SegmentedButton has
  // only the unnamed constructor today; guard so a future one defers rather
  // than silently mis-lowering).
  if (creation.constructorName.name != null) {
    return SegmentedButtonDeferred(
      "the named constructor 'SegmentedButton.${creation.constructorName.name}'"
      ' is not supported (the unnamed constructor only)',
    );
  }

  final gate = _typeArgumentGate(creation);
  if (gate != null) return gate;

  final args = creation.argumentList.arguments;
  Expression? segments;
  Expression? selected;
  Expression? onSelectionChanged;
  Expression? multiSelectionEnabled;
  Expression? emptySelectionAllowed;
  for (final arg in args) {
    if (arg is! NamedExpression) {
      return const SegmentedButtonDeferred(
        'a positional argument has no declarative equivalent',
      );
    }
    switch (arg.name.label.name) {
      case 'key':
        break; // the universal super.key convention
      case 'segments':
        segments = arg.expression;
      case 'selected':
        selected = arg.expression;
      case 'onSelectionChanged':
        onSelectionChanged = arg.expression;
      case 'multiSelectionEnabled':
        multiSelectionEnabled = arg.expression;
      case 'emptySelectionAllowed':
        emptySelectionAllowed = arg.expression;
      default:
        return SegmentedButtonDeferred(
          "the '${arg.name.label.name}' argument has no "
          'RestageSegmentedButton equivalent',
        );
    }
  }

  if (segments == null) {
    return const SegmentedButtonDeferred('a segments list is required');
  }
  final segmentElements = _plainListElements(segments);
  if (segmentElements == null) {
    return const SegmentedButtonDeferred(
      'the segments must be a static list literal of ButtonSegment entries '
      '(no dynamic / builder list, spreads, or `if`/`for` elements)',
    );
  }
  if (segmentElements.isEmpty) {
    return const SegmentedButtonDeferred(
      'the segments list must be non-empty',
    );
  }

  final recognisedSegments = <RecognisedSegment>[];
  for (final element in segmentElements) {
    final segment = _buttonSegment(element);
    switch (segment) {
      case _SegmentDeferred(:final reason):
        return SegmentedButtonDeferred(reason);
      case _SegmentRecognised(:final segment):
        recognisedSegments.add(segment);
    }
  }

  // Reject statically-known duplicate values (literals only). A non-literal
  // value (a state reference) is left to the dispatch-site's post-fold check
  // and the runtime de-dupe.
  final seen = <String>{};
  for (final segment in recognisedSegments) {
    final literal = _stringLiteralValue(segment.value);
    if (literal != null && !seen.add(literal)) {
      return SegmentedButtonDeferred(
        "duplicate segment value '$literal' — each segment value must be "
        'unique',
      );
    }
  }

  // `selected:` is a set or list literal of values; extract its elements (or
  // defer loud on a non-literal collection). Absent / null → no initial
  // selection.
  final selectedValues = <Expression>[];
  if (selected != null && selected is! NullLiteral) {
    final values = _selectedCollectionElements(selected);
    if (values == null) {
      return const SegmentedButtonDeferred(
        'the selected must be a static set or list literal of segment values '
        '(no dynamic / builder collection, spreads, or `if`/`for` elements)',
      );
    }
    selectedValues.addAll(values);
  }

  return SegmentedButtonRecognised(
    RecognisedSegmentedButton(
      segments: recognisedSegments,
      selectedValues: selectedValues,
      onSelectionChanged: onSelectionChanged,
      multiSelectionEnabled: multiSelectionEnabled,
      emptySelectionAllowed: emptySelectionAllowed,
    ),
  );
}

/// Gates recognition on the segmented button's resolved `<T>` specialization,
/// using the RESOLVED instantiated type (`creation.staticType`) so an INFERRED
/// generic gates too. A resolved-String type argument (incl. a `String`-aliased
/// typedef) recognises; any other resolved argument defers loud; an UNRESOLVED
/// static type (synthetic parser-test input) falls back to the syntactic `<T>`
/// lexeme. Returns a [SegmentedButtonDeferred] on a non-String argument, or
/// `null` (recognition proceeds) otherwise.
SegmentedButtonOutcome? _typeArgumentGate(InstanceCreationExpression creation) {
  final staticType = creation.staticType;
  if (staticType is InterfaceType && staticType.typeArguments.isNotEmpty) {
    final arg = staticType.typeArguments.first;
    if (arg.isDartCoreString) return null;
    return _nonStringTypeArgDefer(arg.getDisplayString());
  }
  // Unresolved static type (synthetic parser-test input with no resolution):
  // fall back to the syntactic `<T>` lexeme. A bare `String` recognises; any
  // other named lexeme defers loud; no written type argument recognises (the
  // canonical String-keyed lowering).
  final typeArgs = creation.constructorName.type.typeArguments?.arguments;
  if (typeArgs == null || typeArgs.isEmpty) return null;
  final arg = typeArgs.first;
  if (arg is! NamedType) return null;
  if (arg.name.lexeme == 'String') return null;
  return _nonStringTypeArgDefer(arg.name.lexeme);
}

SegmentedButtonDeferred _nonStringTypeArgDefer(String typeArgName) =>
    SegmentedButtonDeferred(
      'SegmentedButton<$typeArgName> is not supported — only the String-keyed '
      'segmented button lowers (rewrite as SegmentedButton<String> with string '
      'segment values)',
    );

/// Result of extracting one `ButtonSegment` leaf — internal to the per-leaf
/// extraction, kept distinct from the public [SegmentedButtonOutcome].
sealed class _SegmentOutcome {
  const _SegmentOutcome();
}

final class _SegmentRecognised extends _SegmentOutcome {
  const _SegmentRecognised(this.segment);
  final RecognisedSegment segment;
}

final class _SegmentDeferred extends _SegmentOutcome {
  const _SegmentDeferred(this.reason);
  final String reason;
}

/// Extracts `{value, label}` from a `ButtonSegment(value:, label: Text('…'))`
/// leaf, or defers loud. Carry-all-or-defer: a non-`ButtonSegment` leaf, an
/// icon-only / icon+label segment (no flat string label), a non-literal-`Text`
/// label, a missing `value`, or any behavioral carrier arg
/// (`enabled:` / `tooltip:`) defers the WHOLE widget.
_SegmentOutcome _buttonSegment(Expression leaf) {
  final creation = _frameworkCreationNamed(leaf, 'ButtonSegment');
  if (creation == null) {
    return const _SegmentDeferred(
      'every segment must be a ButtonSegment (no other leaf type is carried)',
    );
  }
  Expression? value;
  Expression? label;
  for (final arg in creation.argumentList.arguments) {
    if (arg is! NamedExpression) {
      return const _SegmentDeferred(
        'a positional argument on ButtonSegment has no declarative equivalent',
      );
    }
    final name = arg.name.label.name;
    switch (name) {
      case 'value':
        value = arg.expression;
      case 'label':
        label = arg.expression;
      case 'key':
        break; // inert
      case 'icon':
        // An icon-only segment has no flat string label; an icon+label segment
        // would drop the icon. Either way the flat single-string surface
        // cannot carry it — defer the WHOLE widget loud (v1 scope).
        return const _SegmentDeferred(
          'a ButtonSegment carries an icon, which the flat segmented-button '
          'surface does not carry (use a literal Text label only)',
        );
      default:
        // `enabled:` / `tooltip:` change the segment's behavior or
        // presentation the flat surface cannot express; any other carrier arg
        // is unrecognised. Defer the WHOLE widget loud rather than silently
        // drop the author's intent.
        return _SegmentDeferred(
          "a ButtonSegment carries '$name', which has no flat segmented-button "
          'equivalent (only value + a literal Text label are carried)',
        );
    }
  }

  if (value == null) {
    return const _SegmentDeferred('a ButtonSegment is missing its value:');
  }
  if (label == null) {
    // ButtonSegment asserts `icon != null || label != null`; with icon already
    // rejected above, a label-less segment is malformed for our surface.
    return const _SegmentDeferred(
      "a ButtonSegment is missing its label: (the segment's label)",
    );
  }
  final labelText = _literalTextContent(label);
  if (labelText == null) {
    return const _SegmentDeferred(
      "a ButtonSegment label must be a literal Text('…'); a richer label has "
      'no flat segmented-button equivalent',
    );
  }
  return _SegmentRecognised(
    RecognisedSegment(value: value, label: labelText),
  );
}

/// Returns the element expressions of a `selected:` set or list literal when
/// every element is a plain expression, else `null` (a dynamic / non-literal
/// collection, or one with spreads / `if` / `for` elements).
List<Expression>? _selectedCollectionElements(Expression expr) {
  final stripped = _unwrapParens(expr);
  // A `{...}` set literal or a `[...]` list literal — both are TypedLiteral /
  // accept the same plain-element extraction. A `SetOrMapLiteral` with map
  // entries (`{k: v}`) yields a non-Expression element and is rejected.
  if (stripped is SetOrMapLiteral) {
    final result = <Expression>[];
    for (final element in stripped.elements) {
      if (element is! Expression) return null;
      result.add(element);
    }
    return result;
  }
  if (stripped is ListLiteral) return _plainListElementsOf(stripped);
  return null;
}

/// Returns the static list of leaf expressions when [expr] is a plain list
/// literal whose every element is a plain expression (no spreads, `if`, or
/// `for` collection elements), else `null`.
List<Expression>? _plainListElements(Expression expr) {
  final stripped = _unwrapParens(expr);
  if (stripped is! ListLiteral) return null;
  return _plainListElementsOf(stripped);
}

List<Expression>? _plainListElementsOf(ListLiteral list) {
  final result = <Expression>[];
  for (final element in list.elements) {
    if (element is! Expression) return null;
    result.add(element);
  }
  return result;
}

/// Returns the [InstanceCreationExpression] for an unnamed construction of a
/// framework class named [name], or `null` for any other shape. Uses the
/// resolved element when available (rejecting a customer look-alike) and falls
/// back to the bare type name for unresolved synthetic-test input.
InstanceCreationExpression? _frameworkCreationNamed(
  Expression expr,
  String name,
) {
  final creation = _unwrapParens(expr);
  if (creation is! InstanceCreationExpression) return null;
  if (_creationTypeName(creation) != name) return null;
  if (creation.constructorName.name != null) return null;
  final element = creation.constructorName.type.element;
  if (element != null) return libraryIsFlutter(element) ? creation : null;
  // Unresolved (synthetic parser-test input): fall back to the name.
  return creation;
}

/// The simple type name of an instance creation (the class being constructed).
String _creationTypeName(InstanceCreationExpression creation) =>
    creation.constructorName.type.name.lexeme;

/// Returns the string-content expression of a literal `Text('…')` construction,
/// or `null` for any other label shape. Accepts ONLY a bare unnamed
/// `Text('…')` — its single positional string argument — and rejects any
/// configured `Text` (a `style:`, `textAlign:`, `key:`, … or a second
/// positional). The flat segmented-button surface carries only the label
/// STRING; a `Text` carrying styling/configuration would silently drop that
/// configuration at render, so it must defer loud (carry-all-or-defer) rather
/// than lower to a degraded plain label.
Expression? _literalTextContent(Expression label) {
  final creation = _unwrapParens(label);
  if (creation is! InstanceCreationExpression) return null;
  if (_creationTypeName(creation) != 'Text') return null;
  // `Text.rich(...)` is a different shape with no flat string label.
  if (creation.constructorName.name != null) return null;
  final element = creation.constructorName.type.element;
  if (element != null && !libraryIsFlutter(element)) return null;
  final args = creation.argumentList.arguments;
  // Exactly one positional string argument — no `style:` / `textAlign:` /
  // `key:` / etc. and no second positional. Any extra argument would be
  // silently dropped by the string-only lowering, so reject (defer loud).
  if (args.length != 1) return null;
  final only = args.single;
  if (only is NamedExpression) return null;
  return only;
}

/// The static string value of [expr] when it is a simple string literal, else
/// `null`. Used only for duplicate-value detection.
String? _stringLiteralValue(Expression expr) {
  final stripped = _unwrapParens(expr);
  return stripped is SimpleStringLiteral ? stripped.value : null;
}

/// Strips semantically-inert surrounding parentheses.
Expression _unwrapParens(Expression expr) =>
    expr is ParenthesizedExpression ? _unwrapParens(expr.expression) : expr;
