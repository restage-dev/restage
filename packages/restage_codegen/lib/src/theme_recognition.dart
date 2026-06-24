import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

/// [libraryIsFlutter] and [isFrameworkValueTypeLibrary] are the shared
/// framework-vs-customer disambiguation the translator, the classifier, and the
/// theme-read recogniser key on: a resolved class is framework code iff its
/// library matches; any OTHER resolved class is a customer look-alike that must
/// NOT be lowered as the framework value/const (a value-substitution
/// silent-wrong the type-aware floor cannot catch). A null element is NOT
/// recognised — the recognisers run on resolved ASTs in production, so a null
/// element is genuinely-unresolvable input, and recognising it on a name alone
/// would re-open the silent-wrong in a degraded build. Call sites that need a
/// synthetic-test affordance layer their own name-fallback on top (see
/// [isFlutterStaticOf]; the translator's `_frameworkOrUnresolved`).

/// Resolves to `package:flutter/` — the strict gate for the `Colors` / `Icons` /
/// theme-read arms. See the shared rationale above.
bool libraryIsFlutter(Element? element) =>
    _libraryStartsWithAny(element, const ['package:flutter/']);

/// Resolves to a framework VALUE-TYPE library — the broader gate for the
/// structured-value recognition arms. The value types the translator lowers
/// span `package:flutter/` (`EdgeInsets` / `BorderRadius` / `Alignment` / shape
/// borders), `dart:ui` (`Color` / `Offset` / `Locale` / `Paint` / `Shadow`),
/// and `dart:core` (`Duration`); a customer cannot place a class in `dart:` /
/// `package:flutter/`. See the shared rationale above [libraryIsFlutter].
bool isFrameworkValueTypeLibrary(Element? element) =>
    _libraryStartsWithAny(element, const ['dart:', 'package:flutter/']);

bool _libraryStartsWithAny(Element? element, List<String> prefixes) {
  if (element == null) return false;
  final uri = element.library?.identifier ?? '';
  return prefixes.any(uri.startsWith);
}

/// Whether [invocation] is a static `<className>.of(...)` call on a class
/// the `data.theme.*` channel sources from.
///
/// When the analyzer resolves the call, requires the enclosing class name
/// AND the originating library URI (`package:flutter/...`) to match — so
/// a customer class literally named `Theme` (or `DefaultTextStyle`) with
/// its own `of(...)` member does not silently slip through and produce a
/// wrong `data.theme.*` reference at emit time. A prefixed import like
/// `material.Theme.of(c)` resolves to the same Flutter element and is
/// recognised the same way.
///
/// When unresolved (synthetic test inputs), falls back to a syntactic
/// check on the receiver — accepting either a bare `<className>` or a
/// prefixed `<prefix>.<className>` form. The fallback is unavoidable for
/// codegen-tests that drive `parseExpressionForTest` (no element
/// resolution); the production path always resolves.
bool isFlutterStaticOf(MethodInvocation invocation, String className) {
  if (invocation.methodName.name != 'of') return false;
  final element = invocation.methodName.element;
  if (element != null) {
    if (!libraryIsFlutter(element)) return false;
    return element.enclosingElement?.name == className;
  }
  final target = invocation.target;
  if (target is SimpleIdentifier) return target.name == className;
  if (target is PrefixedIdentifier) {
    return target.identifier.name == className;
  }
  return false;
}

/// Walks down [expr]'s `PropertyAccess` chain, unwrapping any wrapping
/// `ParenthesizedExpression` nodes encountered along the way, and returns
/// the bottom non-`PropertyAccess` expression. Returns `null` if any
/// intermediate `PropertyAccess` is a cascade (`..foo` — `target == null`).
Expression? propertyAccessRoot(Expression expr) {
  var current = expr;
  while (true) {
    while (current is ParenthesizedExpression) {
      current = current.expression;
    }
    if (current is PropertyAccess) {
      final target = current.target;
      if (target == null) return null;
      current = target;
      continue;
    }
    return current;
  }
}

/// The `data.theme.*` path segments [expr] reads, or `null` when [expr] is not
/// a recognised theme read. This is the single canonical theme-read recognizer
/// the classifier recognizer, the translator lowerer, and the slot validator
/// all route through, so the three never drift.
///
/// Recognised shapes:
/// - `Theme.of(c).<x>(.<y>)` — any chain that reaches the `Theme` root, mapping
///   directly to the path segments.
/// - `DefaultTextStyle.of(c).style.<x>` — must lead with `.style.`; the leading
///   `style` segment normalises to the `defaultTextStyle.<x>` contract path so
///   unrelated accesses (e.g. `.maxLines`) fall through to `null`.
///
/// Binding-aware: the chain may pass through a bound `final` theme-local
/// captured in [bindings] (element-keyed) — `scheme.primary` where a leading
/// `final scheme = Theme.of(c).colorScheme;` is in scope splices the
/// initializer in and continues the walk. Element-resolved only; with an empty
/// [bindings] map this is byte-identical to recognising the direct chain.
///
/// Coarse on the segment names — path validation against the `data.theme.*`
/// contract happens at emit time in the translator. The `.of(<single
/// SimpleIdentifier>)` arg shape is required so a computed-context read is not
/// mis-recognised; bare `<Class>.of(c)` (no trailing segment) returns `null`.
List<String>? themeReadSegments(
  Expression expr, {
  Map<Element, Expression> bindings = const {},
}) {
  final reversedSegments = <String>[];
  var current = expr;
  while (true) {
    while (current is ParenthesizedExpression) {
      current = current.expression;
    }
    if (current is PropertyAccess) {
      final target = current.target;
      if (target == null) return null;
      reversedSegments.add(current.propertyName.name);
      current = target;
      continue;
    }
    if (current is PrefixedIdentifier) {
      // `<bound-theme-local>.member` — splice the local's initializer in and
      // continue the walk. A non-bound prefix (`Theme.of` is never reached as
      // a PrefixedIdentifier here) falls through to the tail check below.
      final bound = bindings[current.prefix.element];
      if (bound == null) break;
      reversedSegments.add(current.identifier.name);
      current = bound;
      continue;
    }
    if (current is SimpleIdentifier) {
      // A bare reference to a bound theme-local — splice and continue.
      final bound = bindings[current.element];
      if (bound == null) break;
      current = bound;
      continue;
    }
    break;
  }
  if (current is! MethodInvocation) return null;
  final args = current.argumentList.arguments;
  if (args.length != 1 || args.first is! SimpleIdentifier) return null;
  final segments = reversedSegments.reversed.toList();
  // A bare `<Class>.of(c)` with no trailing access returns a ThemeData/style
  // object that can't be emitted as a blob primitive — not a theme read.
  if (segments.isEmpty) return null;
  if (isFlutterStaticOf(current, 'Theme')) return segments;
  if (isFlutterStaticOf(current, 'DefaultTextStyle')) {
    // The contract publishes `defaultTextStyle.<x>` from the ambient
    // `DefaultTextStyle`'s `.style.<x>`; require and consume the leading
    // `style` segment so unrelated chains (`.maxLines`) fall through.
    // (`segments` is non-empty — the bare-`.of(c)` case returned above.)
    if (segments.first != 'style') return null;
    return ['defaultTextStyle', ...segments.skip(1)];
  }
  return null;
}

/// Whether [expr] is a recognised theme read — the boolean form of
/// [themeReadSegments]. Pass [bindings] to recognise a read through a bound
/// `final` theme-local; the default (no bindings) recognises only the direct
/// chain.
bool isThemeReadChain(
  Expression expr, {
  Map<Element, Expression> bindings = const {},
}) =>
    themeReadSegments(expr, bindings: bindings) != null;
