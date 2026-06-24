/// Pure AST recognition for the two vanilla-Flutter single-select idioms that
/// lower to the compiled catalog widgets `RestageRadioGroup` / `RestageDropdown`:
///
/// * a `RadioGroup` with `groupValue:` / `onChanged:` and a `child:` that is a
///   static list of `RadioListTile(value:, title: Text('…'))` leaves;
/// * a `DropdownButton` with `value:` / `onChanged:` and an `items:` list of
///   `DropdownMenuItem(value:, child: Text('…'))` entries.
///
/// The recogniser extracts the per-option `{value, label}` expression pairs and
/// the `selected` / `onChanged` expressions, or a single loud-defer reason.
/// **Carry-all-or-defer at every leaf:** a non-list / dynamic / builder child,
/// a leaf that is not the expected carrier, a non-literal-`Text` label, a
/// missing `value`, or a duplicate value defers the WHOLE widget — never a
/// partial or wrong group. The dispatch site in the translator owns the
/// framework-identity gate on the outer widget and the emission of the
/// recognised parts; this module owns the shape recognition only.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/theme_recognition.dart';

/// One recognised option — the `value` and `label` source expressions, to be
/// translated and emitted by the dispatch site.
final class RecognisedSelectionOption {
  /// Creates a recognised option.
  const RecognisedSelectionOption({required this.value, required this.label});

  /// The option's `value:` argument expression (lowers to the option key).
  final Expression value;

  /// The literal `Text` label's string-content expression (lowers to the
  /// display label).
  final Expression label;
}

/// The recognised parts of a single-select construction.
final class RecognisedSingleSelect {
  /// Creates a recognised single-select.
  const RecognisedSingleSelect({
    required this.options,
    this.selected,
    this.onChanged,
  });

  /// The options in source order, each a `{value, label}` expression pair.
  final List<RecognisedSelectionOption> options;

  /// The selected-value expression (`groupValue:` / `value:`), or `null` when
  /// the author left the group unselected.
  final Expression? selected;

  /// The settled-selection callback expression (`onChanged:`), or `null` when
  /// the author supplied none.
  final Expression? onChanged;
}

/// Outcome of recognising a single-select construction.
sealed class SingleSelectOutcome {
  const SingleSelectOutcome();
}

/// The construction is a clean, fully-extractable single-select.
final class SingleSelectRecognised extends SingleSelectOutcome {
  /// Creates a recognised outcome.
  const SingleSelectRecognised(this.recognised);

  /// The extracted parts.
  final RecognisedSingleSelect recognised;
}

/// The construction is the right widget but an unparseable shape — defer the
/// whole widget loud with [reason].
final class SingleSelectDeferred extends SingleSelectOutcome {
  /// Creates a deferred outcome.
  const SingleSelectDeferred(this.reason);

  /// Author-facing reason for the fatal defer.
  final String reason;
}

/// Recognises a `RadioGroup<String>(groupValue:, onChanged:, child: …)`. The
/// caller has already confirmed the outer widget is the framework `RadioGroup`.
///
/// The compiled target (`RestageRadioGroupString`) is a String-keyed
/// single-select: the wire carries String option values and the decoder reads
/// them as `String`. A `RadioGroup<int>` / `<Object>` / any resolved non-String
/// specialization would silently drop or mis-key its option values, so the
/// type-argument gate ([_typeArgumentGate]) defers loud on a resolved
/// non-String `<T>` and recognises only a resolved `<String>` (or an unresolved
/// synthetic-test construction, by name-fallback).
SingleSelectOutcome recogniseRadioGroup(InstanceCreationExpression creation) {
  final gate = _typeArgumentGate(creation, 'RadioGroup');
  if (gate != null) return gate;
  final args = creation.argumentList.arguments;
  Expression? selected;
  Expression? onChanged;
  Expression? child;
  for (final arg in args) {
    if (arg is! NamedExpression) {
      return const SingleSelectDeferred(
        'a positional argument has no declarative equivalent',
      );
    }
    switch (arg.name.label.name) {
      case 'key':
        break; // the universal super.key convention
      case 'groupValue':
        selected = arg.expression;
      case 'onChanged':
        onChanged = arg.expression;
      case 'child':
        child = arg.expression;
      default:
        return SingleSelectDeferred(
          "the '${arg.name.label.name}' argument has no "
          'RestageRadioGroup equivalent',
        );
    }
  }

  if (child == null) {
    return const SingleSelectDeferred('a child is required');
  }
  final leaves = _staticChildLeaves(child);
  if (leaves == null) {
    return const SingleSelectDeferred(
      'the child must be a static list of RadioListTile rows (a Column / '
      'ListView / list literal of RadioListTile leaves)',
    );
  }

  final options = <RecognisedSelectionOption>[];
  for (final leaf in leaves) {
    final option = _radioListTileOption(leaf);
    switch (option) {
      case _LeafDeferred(:final reason):
        return SingleSelectDeferred(reason);
      case _LeafRecognised(:final option):
        options.add(option);
    }
  }
  return _finishOptions(options, selected: selected, onChanged: onChanged);
}

/// Recognises a `DropdownButton<String>(items: [...], value:, onChanged:)`. The
/// caller has already confirmed the outer widget is the framework
/// `DropdownButton`.
///
/// The compiled target (`RestageDropdownString`) is String-keyed; a resolved
/// non-String `<T>` defers loud via [_typeArgumentGate] (see
/// [recogniseRadioGroup]).
SingleSelectOutcome recogniseDropdown(InstanceCreationExpression creation) {
  final gate = _typeArgumentGate(creation, 'DropdownButton');
  if (gate != null) return gate;
  final args = creation.argumentList.arguments;
  Expression? selected;
  Expression? onChanged;
  Expression? items;
  for (final arg in args) {
    if (arg is! NamedExpression) {
      return const SingleSelectDeferred(
        'a positional argument has no declarative equivalent',
      );
    }
    switch (arg.name.label.name) {
      case 'key':
        break;
      case 'value':
        selected = arg.expression;
      case 'onChanged':
        onChanged = arg.expression;
      case 'items':
        items = arg.expression;
      default:
        return SingleSelectDeferred(
          "the '${arg.name.label.name}' argument has no "
          'RestageDropdown equivalent',
        );
    }
  }

  if (items == null) {
    return const SingleSelectDeferred('an items list is required');
  }
  if (items is! ListLiteral) {
    return const SingleSelectDeferred(
      'the items must be a static list literal of DropdownMenuItem entries',
    );
  }

  final options = <RecognisedSelectionOption>[];
  for (final element in items.elements) {
    if (element is! Expression) {
      return const SingleSelectDeferred(
        'the items list must contain only DropdownMenuItem expressions (no '
        'spreads or `if`/`for` elements)',
      );
    }
    final option = _dropdownMenuItemOption(element);
    switch (option) {
      case _LeafDeferred(:final reason):
        return SingleSelectDeferred(reason);
      case _LeafRecognised(:final option):
        options.add(option);
    }
  }
  return _finishOptions(options, selected: selected, onChanged: onChanged);
}

/// Gates recognition on the single-select's resolved `<T>` specialization. The
/// compiled targets are String-keyed (`RestageRadioGroupString` /
/// `RestageDropdownString` — the decoder reads each option value as `String`),
/// so a resolved non-String specialization must defer loud rather than lower to
/// a String widget that drops or mis-keys its values.
///
/// Gates on the RESOLVED instantiated type (`creation.staticType`), not the
/// syntactic `<T>` argument list, so an INFERRED generic gates too:
/// `DropdownButton(value: 1, items: [...])` has no written `<int>` but the
/// analyzer infers `DropdownButton<int>`, which must defer loud just as an
/// explicit `<int>` does. A resolved-String type argument recognises —
/// including a `typedef PlanId = String`, which resolves through to `String`.
///
/// Returns a [SingleSelectDeferred] when the resolved type argument is
/// non-String (whether written or inferred); returns `null` (recognition
/// proceeds) for a resolved-String argument, a resolved generic with no type
/// argument, or an UNRESOLVED static type (synthetic parser-test input — kept
/// by the syntactic name-fallback, the same affordance the leaf gate uses).
SingleSelectOutcome? _typeArgumentGate(
  InstanceCreationExpression creation,
  String widgetName,
) {
  final staticType = creation.staticType;
  if (staticType is InterfaceType && staticType.typeArguments.isNotEmpty) {
    // Resolved instantiation: inspect the first (and only) type argument. A
    // resolved `String` (incl. via a `String`-aliased typedef, which resolves
    // through) recognises; any other resolved argument — `int`, `Object`,
    // `dynamic`, `num`, a customer enum, … written `<int>` or inferred — defers
    // loud, since the String widget cannot faithfully carry it.
    final arg = staticType.typeArguments.first;
    if (arg.isDartCoreString) return null;
    return _nonStringTypeArgDefer(widgetName, arg.getDisplayString());
  }
  // Unresolved static type (synthetic parser-test input with no resolution):
  // fall back to the syntactic `<T>` lexeme so tests that drive the recogniser
  // without resolution still gate. A bare `String` recognises; any other named
  // lexeme defers loud; no written type argument recognises (the canonical
  // String-keyed lowering).
  final typeArgs = creation.constructorName.type.typeArguments?.arguments;
  if (typeArgs == null || typeArgs.isEmpty) return null;
  final arg = typeArgs.first;
  if (arg is! NamedType) return null;
  if (arg.name.lexeme == 'String') return null;
  return _nonStringTypeArgDefer(widgetName, arg.name.lexeme);
}

SingleSelectDeferred _nonStringTypeArgDefer(
  String widgetName,
  String typeArgName,
) =>
    SingleSelectDeferred(
      '$widgetName<$typeArgName> is not supported — only the String-keyed '
      'single-select lowers (rewrite as $widgetName<String> with string '
      'option values)',
    );

/// Common close-out: rejects an empty option set and duplicate values, then
/// wraps the options into a recognised result.
SingleSelectOutcome _finishOptions(
  List<RecognisedSelectionOption> options, {
  required Expression? selected,
  required Expression? onChanged,
}) {
  if (options.isEmpty) {
    return const SingleSelectDeferred('at least one option is required');
  }
  final seen = <String>{};
  for (final option in options) {
    final literal = _stringLiteralValue(option.value);
    // Only statically-known string values can be checked for duplication; a
    // non-literal value (a state reference) is left to the runtime de-dupe.
    if (literal != null && !seen.add(literal)) {
      return SingleSelectDeferred(
        "duplicate option value '$literal' — each option value must be unique",
      );
    }
  }
  return SingleSelectRecognised(
    RecognisedSingleSelect(
      options: options,
      selected: selected,
      onChanged: onChanged,
    ),
  );
}

/// Result of extracting one option leaf — internal to the per-leaf extraction,
/// kept distinct from the public [SingleSelectOutcome] so the public sealed
/// type stays a clean two-case (recognised / deferred).
sealed class _LeafOutcome {
  const _LeafOutcome();
}

final class _LeafRecognised extends _LeafOutcome {
  const _LeafRecognised(this.option);
  final RecognisedSelectionOption option;
}

final class _LeafDeferred extends _LeafOutcome {
  const _LeafDeferred(this.reason);
  final String reason;
}

/// Extracts `{value, label}` from a `RadioListTile(value:, title: Text('…'))`
/// leaf, or defers loud.
_LeafOutcome _radioListTileOption(Expression leaf) {
  final creation = _frameworkCreationNamed(leaf, 'RadioListTile');
  if (creation == null) {
    return const _LeafDeferred(
      'every option must be a RadioListTile (no other leaf type is carried)',
    );
  }
  return _optionFromCarrier(
    creation,
    labelArg: 'title',
    widgetName: 'RadioListTile',
  );
}

/// Extracts `{value, label}` from a `DropdownMenuItem(value:, child: Text())`
/// leaf, or defers loud.
_LeafOutcome _dropdownMenuItemOption(Expression leaf) {
  final creation = _frameworkCreationNamed(leaf, 'DropdownMenuItem');
  if (creation == null) {
    return const _LeafDeferred(
      'every item must be a DropdownMenuItem (no other entry type is carried)',
    );
  }
  return _optionFromCarrier(
    creation,
    labelArg: 'child',
    widgetName: 'DropdownMenuItem',
  );
}

/// Pulls the `value:` and the literal-`Text` label (from [labelArg]) off a
/// recognised carrier construction, deferring loud on any missing or
/// non-literal part.
_LeafOutcome _optionFromCarrier(
  InstanceCreationExpression creation, {
  required String labelArg,
  required String widgetName,
}) {
  Expression? value;
  Expression? label;
  for (final arg in creation.argumentList.arguments) {
    if (arg is! NamedExpression) {
      return _LeafDeferred(
        'a positional argument on $widgetName has no declarative equivalent',
      );
    }
    final name = arg.name.label.name;
    if (name == 'value') {
      value = arg.expression;
    } else if (name == labelArg) {
      label = arg.expression;
    } else if (name == 'key') {
      // The universal `super.key` convention — inert, never a behavior change.
      continue;
    } else {
      // Any OTHER carrier argument changes the option's behavior or
      // selectability — `enabled: false` makes a remote option un-tappable,
      // `onTap` / a per-tile `onChanged` runs a side-effect the flat
      // single-select cannot express, and styling args the compiled widget
      // does NOT honor would render a degraded option. Carry-all-or-defer: an
      // unrecognised carrier arg defers the WHOLE widget loud (named) rather
      // than emit an option that silently drops the author's intent.
      return _LeafDeferred(
        "a $widgetName carries '$name', which has no flat single-select "
        'equivalent (the compiled single-select owns presentation and '
        'enabled/tap behavior; only value + $labelArg are carried)',
      );
    }
  }

  if (value == null) {
    return _LeafDeferred('a $widgetName is missing its value:');
  }
  if (label == null) {
    return _LeafDeferred(
      "a $widgetName is missing its $labelArg: (the option's label)",
    );
  }
  final labelText = _literalTextContent(label);
  if (labelText == null) {
    return _LeafDeferred(
      "a $widgetName label must be a literal Text('…'); a richer label has no "
      'flat single-select equivalent',
    );
  }
  return _LeafRecognised(
    RecognisedSelectionOption(value: value, label: labelText),
  );
}

/// Returns the static list of leaf expressions in a `child` subtree when it is
/// a framework `Column` / `ListView` / `ListBody` (resolved to
/// `package:flutter`) whose `children` is a plain list literal, or a bare list
/// literal. Returns `null` for any dynamic / builder / non-list shape, and for a
/// resolved customer look-alike named `Column`/`ListView`/`ListBody` that is NOT
/// the framework container (defer-loud at the caller).
List<Expression>? _staticChildLeaves(Expression child) {
  if (child is ListLiteral) {
    return _plainListElements(child);
  }
  final creation = child is InstanceCreationExpression ? child : null;
  if (creation == null) return null;
  final name = _creationTypeName(creation);
  if (name != 'Column' && name != 'ListView' && name != 'ListBody') {
    return null;
  }
  // `ListView(children: [...])` only — the `.builder` form (a dynamic
  // itemBuilder) is not a static leaf list.
  if (creation.constructorName.name != null) return null;
  // Element-gate the wrapper to `package:flutter`. A customer container named
  // `Column`/`ListView`/`ListBody` (resolving to a non-flutter library) may
  // reorder / filter / inject children — treating it as a static Flutter
  // container would silently lower a reordered or dropped option set. A
  // resolved non-flutter look-alike is rejected (the caller defers loud);
  // an UNRESOLVED construction (synthetic parser-test input) falls back to the
  // bare type name, the same affordance the leaf carrier gate uses.
  final element = creation.constructorName.type.element;
  if (element != null && !libraryIsFlutter(element)) return null;
  for (final arg in creation.argumentList.arguments) {
    if (arg is NamedExpression && arg.name.label.name == 'children') {
      final list = arg.expression;
      return list is ListLiteral ? _plainListElements(list) : null;
    }
  }
  return null;
}

/// Returns the element expressions of [list] when every element is a plain
/// expression (no spreads, `if`, or `for` collection elements), else `null`.
List<Expression>? _plainListElements(ListLiteral list) {
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
  // A named constructor (e.g. `RadioListTile.adaptive`) is not the carrier we
  // recognise.
  if (creation.constructorName.name != null) return null;
  final element = creation.constructorName.type.element;
  if (element != null) return libraryIsFlutter(element) ? creation : null;
  // Unresolved (synthetic parser-test input): fall back to the name.
  return creation;
}

/// The simple type name of an instance creation (the class being constructed).
String _creationTypeName(InstanceCreationExpression creation) =>
    creation.constructorName.type.name.lexeme;

/// Returns the string-content expression of a literal `Text('…')` /
/// `Text.rich`-free construction, or `null` for any other label shape. Accepts
/// the positional first argument of an unnamed `Text(...)`.
Expression? _literalTextContent(Expression label) {
  final creation = _unwrapParens(label);
  if (creation is! InstanceCreationExpression) return null;
  if (_creationTypeName(creation) != 'Text') return null;
  // `Text.rich(...)` is a different shape with no flat string label.
  if (creation.constructorName.name != null) return null;
  final element = creation.constructorName.type.element;
  if (element != null && !libraryIsFlutter(element)) return null;
  final args = creation.argumentList.arguments;
  if (args.isEmpty) return null;
  final first = args.first;
  // The data is the first positional argument.
  if (first is NamedExpression) return null;
  return first;
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
