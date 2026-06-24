import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/theme_recognition.dart';
import 'package:restage_codegen/src/translator_kernels.dart';
import 'package:restage_codegen/src/translator_recipe.dart';

/// Translates a captured Dart expression to a DSL fragment — the recursion
/// hook back into the host translator.
typedef TranslateCallback = String Function(Expression, List<Issue>);

/// Emits a list literal with each element coerced to a double-formatted
/// literal (`[0, 1]` -> `[0.0, 1.0]`), using [translate] for each element.
///
/// rfw decodes some numeric lists (e.g. a gradient's `stops`) as
/// `list<double>` via an exact `v<double> ?? 0.0` cast, so an author-written
/// int element is silently nulled to `0.0` without this per-element coercion —
/// the list analogue of the scalar `asDoubleLiteral` the sibling slots apply.
///
/// Only a plain list literal of expression elements is coerced. Anything else
/// — a data reference, or a list carrying a spread / collection-if /
/// collection-for — falls back to [translate] so the host's own list handling
/// emits it (and surfaces any unsupported-collection-flow diagnostic).
String emitDoubleList(
  Expression expr,
  TranslateCallback translate,
  TranslateCallback translateDouble,
  List<Issue> issues,
) {
  if (expr is! ListLiteral ||
      expr.elements.any((element) => element is! Expression)) {
    return translate(expr, issues);
  }
  // Each element coerces to a double literal through [translateDouble] — which
  // coerces PER BRANCH when an element is a conditional, so a bare-int branch
  // does not survive (a plain `asDoubleLiteral` over the assembled
  // `switch state.X { … }` string would pass the bare ints through unchanged
  // because the string contains a `.` from `state.X`).
  final parts = expr.elements
      .cast<Expression>()
      .map((element) => translateDouble(element, issues))
      .toList();
  return '[${parts.join(', ')}]';
}

/// Generic table-driven translator. Consumes a [TranslatorRecipe], runs its
/// validations, evaluates its emit tree, and produces an RFW DSL fragment.
///
/// Coexists with hand-authored translator methods: a key with no recipe
/// yields `null` from [tryTranslate] so the caller falls through to the
/// unchanged hand-authored dispatch.
final class RecipeDispatcher {
  /// Creates a dispatcher over [recipes], using [translate] for recursive
  /// sub-expression translation and [translateDouble] for `asLength` /
  /// `asDoubleList` scalar positions (per-branch double coercion of a
  /// conditional).
  RecipeDispatcher({
    required Map<String, TranslatorRecipe> recipes,
    required TranslateCallback translate,
    required TranslateCallback translateDouble,
    bool Function(Element?) isFrameworkLibrary = isFrameworkValueTypeLibrary,
  })  : _recipes = recipes,
        _translate = translate,
        _translateDouble = translateDouble,
        _isFrameworkLibrary = isFrameworkLibrary;

  final Map<String, TranslatorRecipe> _recipes;
  final TranslateCallback _translate;
  final TranslateCallback _translateDouble;

  /// Framework-vs-customer predicate for the member-table nested-value gate.
  /// Defaults to [isFrameworkValueTypeLibrary]; the host translator injects its
  /// own (`forTesting`-aware) predicate so a synthetic catalog's stubs count as
  /// framework. A member access (`X.member`) whose prefix resolves to a
  /// non-framework class is a customer look-alike and is deferred with a
  /// diagnostic rather than name-substituted to the framework value. An
  /// unresolved prefix keeps the name-based path (the synthetic-test
  /// affordance) — production always resolves.
  final bool Function(Element?) _isFrameworkLibrary;

  /// Whether a recipe is registered for [key].
  bool hasRecipe(String key) => _recipes.containsKey(key);

  /// Translates the call described by [args] via the recipe for [key], or
  /// returns null when no recipe is registered — the fall-through signal.
  ///
  /// On a validation failure, adds one [Issue] and returns the recipe's
  /// failure DSL; on success, returns the evaluated emit fragment.
  String? tryTranslate(
    String key,
    List<Expression> args,
    List<Issue> issues,
    String loc,
  ) {
    final recipe = _recipes[key];
    if (recipe == null) return null;

    final positional = args.where((a) => a is! NamedExpression).toList();
    final named = <String, Expression>{
      for (final a in args.whereType<NamedExpression>())
        a.name.label.name: a.expression,
    };

    for (final validation in recipe.validations) {
      final failure = _checkValidation(validation.check, positional);
      if (failure != null) {
        issues.add(
          Issue(
            code: IssueCode.values.byName(validation.issueCode),
            message: validation.message.replaceAll('{value}', '$failure'),
            location: loc,
          ),
        );
        return recipe.failureDsl;
      }
    }

    // A named argument the source type supports but this recipe does not yet
    // lower: defer LOUD rather than silently drop the field (which omitting an
    // emit entry for it would do). One diagnostic, the failure DSL — never a
    // partial emit that renders as if the field were unset.
    if (recipe.deferredNamedArgs.isNotEmpty) {
      final present = recipe.deferredNamedArgs.where(named.containsKey).toList()
        ..sort();
      if (present.isNotEmpty) {
        final fields = present.join(', ');
        issues.add(
          Issue(
            code: IssueCode.unrecognizedMethodCall,
            message: '${recipe.typeName} field(s) not yet supported: $fields. '
                'Remove them, or move this value into the customer app where '
                'the full type renders.',
            location: loc,
          ),
        );
        return recipe.failureDsl;
      }
    }

    return _emitFragment(recipe.emit, positional, named, issues, loc);
  }

  /// Returns null when [check] passes, or the offending value (`''` when
  /// there is no specific value) when it fails. The first failure stops the
  /// recipe — so a later check may assume the earlier ones held.
  Object? _checkValidation(ValidationCheck check, List<Expression> positional) {
    switch (check) {
      case ArityExact(:final count):
        return positional.length == count ? null : '';
      case PositionalsAreIntLiterals(:final start, :final endExclusive):
        for (var i = start; i < endExclusive; i++) {
          if (i >= positional.length || positional[i] is! IntegerLiteral) {
            return '';
          }
        }
        return null;
      case PositionalIntsHaveValue(:final start, :final endExclusive):
        for (var i = start; i < endExclusive; i++) {
          if ((positional[i] as IntegerLiteral).value == null) return '';
        }
        return null;
      case PositionalIntsInRange(
          :final start,
          :final endExclusive,
          :final min,
          :final max,
        ):
        for (var i = start; i < endExclusive; i++) {
          final value = (positional[i] as IntegerLiteral).value!;
          if (value < min || value > max) return value;
        }
        return null;
      case PositionalNumLiteralInRange(:final index, :final min, :final max):
        final value =
            index < positional.length ? _numLiteral(positional[index]) : null;
        if (value == null || value < min || value > max) return value ?? '';
        return null;
    }
  }

  String _emitFragment(
    EmitFragment node,
    List<Expression> positional,
    Map<String, Expression> named,
    List<Issue> issues,
    String loc,
  ) {
    switch (node) {
      case EmitFragmentLiteral(:final dsl):
        return dsl;
      case EmitFragmentArg(
          :final arg,
          :final ifUnset,
          :final asLength,
          :final asDoubleList,
        ):
        final expr = _resolveArg(arg, positional, named);
        if (expr == null) {
          return ifUnset == null
              ? ''
              : _emitFragment(ifUnset, positional, named, issues, loc);
        }
        if (asDoubleList) {
          return emitDoubleList(expr, _translate, _translateDouble, issues);
        }
        // `asLength` coerces through [_translateDouble] (per-branch for a
        // conditional); otherwise translate as-is.
        return asLength
            ? _translateDouble(expr, issues)
            : _translate(expr, issues);
      case EmitFragmentList(:final items):
        final parts = items
            .map((item) => _emitFragment(item, positional, named, issues, loc))
            .toList();
        return '[${parts.join(', ')}]';
      case EmitFragmentMap(:final entries):
        final parts = <String>[];
        for (final entry in entries) {
          if (entry.omitWhenArgUnset &&
              _entryArgUnset(entry.value, positional, named)) {
            continue;
          }
          final value =
              _emitFragment(entry.value, positional, named, issues, loc);
          parts.add('${entry.key}: $value');
        }
        return '{${parts.join(', ')}}';
      case EmitFragmentKernel(:final kernel, :final inputs):
        final values =
            inputs.map((i) => _emitValue(i, positional, named)).toList();
        return runFragmentKernel(kernel, values);
      case EmitFragmentMemberTable(
          :final memberArg,
          :final members,
          :final fallback,
        ):
        final expr = _resolveArg(memberArg, positional, named);
        // Nested name-only gate. The member table maps a member NAME to a
        // framework value fragment. A member access (`X.member`) whose prefix
        // resolves to a NON-framework class is a customer look-alike — emitting
        // the framework value for it is a value-substitution silent-wrong the
        // type-aware floor cannot catch. Defer with a diagnostic (NEVER the
        // bare-string fallback, which would re-emit the member name = a
        // silent-loss); an unresolved prefix keeps the name-based path
        // (synthetic-test affordance). A constructor call has no member prefix
        // to gate and falls through to the fallback -> the host translator's
        // own (gated) dispatch.
        final (memberPrefixElement, isMemberAccess) = switch (expr) {
          PrefixedIdentifier(:final prefix) => (prefix.element, true),
          SimpleIdentifier(:final element) => (element, true),
          _ => (null, false),
        };
        if (isMemberAccess &&
            memberPrefixElement != null &&
            !_isFrameworkLibrary(memberPrefixElement)) {
          issues.add(
            Issue(
              code: IssueCode.unresolvedIdentifier,
              message: "'${expr!.toSource()}' is not a framework value member; "
                  'a customer class with this member name cannot be lowered as '
                  'the framework value. Reference its value directly.',
              location: loc,
            ),
          );
          return '';
        }
        final name = switch (expr) {
          PrefixedIdentifier(:final identifier) => identifier.name,
          SimpleIdentifier(:final name) => name,
          _ => null,
        };
        final hit = name == null ? null : members[name];
        if (hit != null) {
          return _emitFragment(hit, positional, named, issues, loc);
        }
        // A member access whose prefix RESOLVES to a framework library but
        // whose member name is not in the table is a real, unsupported
        // framework member (e.g. `AlignmentDirectional.centerStart`, or any
        // `Alignment` member outside the resolved-coordinate set). The
        // fallback's recurse would lower it to its bare member-name string,
        // which the consuming map/`{x, y}` decoder silently nulls to the slot
        // default — a silent wrong-render. Defer LOUD instead. The two cases
        // the fallback legitimately serves still reach it below: a constructor
        // call (`isMemberAccess` false — e.g. `Alignment(x, y)`) and an
        // UNRESOLVED member access (synthetic-test affordance), which is
        // diagnosed downstream rather than here.
        if (isMemberAccess &&
            memberPrefixElement != null &&
            _isFrameworkLibrary(memberPrefixElement)) {
          issues.add(
            Issue(
              code: IssueCode.unrecognizedMethodCall,
              message: "'${expr!.toSource()}' is not a supported value here. "
                  'Supported members: ${members.keys.join(", ")}; or use the '
                  'constructor form for an arbitrary value.',
              location: loc,
            ),
          );
          return '';
        }
        return fallback == null
            ? ''
            : _emitFragment(fallback, positional, named, issues, loc);
    }
  }

  Object _emitValue(
    EmitValue node,
    List<Expression> positional,
    Map<String, Expression> named,
  ) {
    switch (node) {
      case EmitValueArg(:final arg):
        return _numLiteral(_resolveArg(arg, positional, named)!)!;
      case EmitValueKernel(:final kernel, :final inputs):
        final values =
            inputs.map((i) => _emitValue(i, positional, named)).toList();
        return runValueKernel(kernel, values);
    }
  }

  Expression? _resolveArg(
    ArgRef ref,
    List<Expression> positional,
    Map<String, Expression> named,
  ) {
    final index = ref.index;
    if (index != null) {
      return index < positional.length ? positional[index] : null;
    }
    return named[ref.label];
  }

  bool _entryArgUnset(
    EmitFragment value,
    List<Expression> positional,
    Map<String, Expression> named,
  ) =>
      switch (value) {
        EmitFragmentArg(:final arg) =>
          _resolveArg(arg, positional, named) == null,
        EmitFragmentMemberTable(:final memberArg) =>
          _resolveArg(memberArg, positional, named) == null,
        _ => false,
      };

  /// The numeric value of a numeric-literal expression (handling unary
  /// minus), or null when [expr] is not a numeric literal.
  num? _numLiteral(Expression expr) {
    if (expr is IntegerLiteral) return expr.value;
    if (expr is DoubleLiteral) return expr.value;
    if (expr is PrefixExpression &&
        expr.operator.lexeme == '-' &&
        (expr.operand is IntegerLiteral || expr.operand is DoubleLiteral)) {
      final inner = _numLiteral(expr.operand);
      return inner == null ? null : -inner;
    }
    return null;
  }
}
