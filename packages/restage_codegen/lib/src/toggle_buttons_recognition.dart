/// Pure AST recognition for the vanilla-Flutter multi-toggle idiom that lowers
/// to the compiled catalog widget `RestageToggleButtons`:
///
/// * a `ToggleButtons` with `children:` (a static list of label widgets),
///   `isSelected:` (a static list of `bool` literals, one per child), and an
///   optional `onPressed:` (`ValueChanged<int>`, the pressed index).
///
/// The recogniser extracts the `children` and `isSelected` element expressions
/// and the `onPressed` expression, or a single loud-defer reason.
/// **Carry-all-or-defer at every leaf:** a non-list / dynamic / builder
/// `children` or `isSelected`, a spread / `if` / `for` collection element, a
/// non-`bool`-literal selection flag, an empty set, an unrecognised argument,
/// or — the load-bearing guard — a LITERAL length mismatch between `children`
/// and `isSelected` defers the WHOLE widget loud, never a partial or
/// misaligned set. (A mismatched-length WIRE is separately reconciled by the
/// compiled `RestageToggleButtons` at render; this build-time gate rejects a
/// statically-knowable mismatch so an author sees it loudly.) The dispatch
/// site in the translator owns the framework-identity gate on the outer widget
/// and the emission of the recognised parts; this module owns the shape
/// recognition only.
library;

import 'package:analyzer/dart/ast/ast.dart';

/// The recognised parts of a multi-toggle construction.
final class RecognisedToggleButtons {
  /// Creates a recognised multi-toggle.
  const RecognisedToggleButtons({
    required this.children,
    required this.isSelected,
    this.onPressed,
  });

  /// The `children` list-literal expression (a static list of label widgets),
  /// translated as a whole through the `children` widget-list slot.
  final Expression children;

  /// The `isSelected` list-literal expression (a static list of `bool`
  /// literals, one per child), translated as a whole through the `isSelected`
  /// boolean-list slot.
  final Expression isSelected;

  /// The settled-press callback expression (`onPressed:`), or `null` when the
  /// author supplied none (a display-only toggle set).
  final Expression? onPressed;
}

/// Outcome of recognising a multi-toggle construction.
sealed class ToggleButtonsOutcome {
  const ToggleButtonsOutcome();
}

/// The construction is a clean, fully-extractable multi-toggle.
final class ToggleButtonsRecognised extends ToggleButtonsOutcome {
  /// Creates a recognised outcome.
  const ToggleButtonsRecognised(this.recognised);

  /// The extracted parts.
  final RecognisedToggleButtons recognised;
}

/// The construction is the right widget but an unparseable shape — defer the
/// whole widget loud with [reason].
final class ToggleButtonsDeferred extends ToggleButtonsOutcome {
  /// Creates a deferred outcome.
  const ToggleButtonsDeferred(this.reason);

  /// Author-facing reason for the fatal defer.
  final String reason;
}

/// Recognises a `ToggleButtons(children:, isSelected:, onPressed:)`. The caller
/// has already confirmed the outer widget is the framework `ToggleButtons`.
ToggleButtonsOutcome recogniseToggleButtons(
  InstanceCreationExpression creation,
) {
  // A named constructor is not the carrier form (ToggleButtons has only the
  // unnamed constructor today; guard so a future one defers rather than
  // silently mis-lowers).
  if (creation.constructorName.name != null) {
    return ToggleButtonsDeferred(
      "the named constructor 'ToggleButtons.${creation.constructorName.name}' "
      'is not supported (the unnamed constructor only)',
    );
  }

  Expression? children;
  Expression? isSelected;
  Expression? onPressed;
  for (final arg in creation.argumentList.arguments) {
    if (arg is! NamedExpression) {
      return const ToggleButtonsDeferred(
        'a positional argument has no declarative equivalent',
      );
    }
    switch (arg.name.label.name) {
      case 'key':
        break; // the universal super.key convention
      case 'children':
        children = arg.expression;
      case 'isSelected':
        isSelected = arg.expression;
      case 'onPressed':
        onPressed = arg.expression;
      default:
        return ToggleButtonsDeferred(
          "the '${arg.name.label.name}' argument has no "
          'RestageToggleButtons equivalent',
        );
    }
  }

  if (children == null) {
    return const ToggleButtonsDeferred('a children list is required');
  }
  if (isSelected == null) {
    return const ToggleButtonsDeferred('an isSelected list is required');
  }

  final childElements = _plainListElements(children);
  if (childElements == null) {
    return const ToggleButtonsDeferred(
      'the children must be a static list literal of label widgets (no '
      'dynamic / builder list, spreads, or `if`/`for` elements)',
    );
  }
  if (childElements.isEmpty) {
    return const ToggleButtonsDeferred(
      'the children list must be non-empty',
    );
  }

  final flagElements = _plainListElements(isSelected);
  if (flagElements == null) {
    return const ToggleButtonsDeferred(
      'the isSelected must be a static list literal of bool literals (no '
      'dynamic / builder list, spreads, or `if`/`for` elements)',
    );
  }
  for (final flag in flagElements) {
    if (_unwrapParens(flag) is! BooleanLiteral) {
      return const ToggleButtonsDeferred(
        'every isSelected entry must be a bool literal (`true` / `false`); a '
        'non-literal flag has no declarative equivalent',
      );
    }
  }

  // The load-bearing guard: a statically-knowable length mismatch between the
  // labels and their selection flags is malformed authoring (Flutter's
  // `ToggleButtons` asserts equal lengths). Defer the WHOLE widget loud rather
  // than emit a set the runtime would have to pad/truncate. (A mismatched WIRE
  // — a corruption/tamper case — is reconciled by the compiled widget; this
  // gate is the build-time, author-facing half.)
  if (childElements.length != flagElements.length) {
    return ToggleButtonsDeferred(
      'children and isSelected must have the same length '
      '(${childElements.length} children vs ${flagElements.length} '
      'isSelected flags) — each button needs exactly one selection flag',
    );
  }

  return ToggleButtonsRecognised(
    RecognisedToggleButtons(
      children: children,
      isSelected: isSelected,
      onPressed: onPressed,
    ),
  );
}

/// Returns the element expressions of [expr] when it is a plain list literal
/// whose every element is a plain expression (no spreads, `if`, or `for`
/// collection elements), else `null` (a dynamic / builder / non-list shape, or
/// a list with non-plain elements).
List<Expression>? _plainListElements(Expression expr) {
  final stripped = _unwrapParens(expr);
  if (stripped is! ListLiteral) return null;
  final result = <Expression>[];
  for (final element in stripped.elements) {
    if (element is! Expression) return null;
    result.add(element);
  }
  return result;
}

/// Strips semantically-inert surrounding parentheses.
Expression _unwrapParens(Expression expr) =>
    expr is ParenthesizedExpression ? _unwrapParens(expr.expression) : expr;
