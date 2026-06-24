import 'package:analyzer/dart/ast/ast.dart';

/// Shared recognition of the `intl` number/currency formatting idiom —
/// `NumberFormat.<ctor>(...).format(<value>)` — single-sourced so the
/// direct-paywall translator (which names the adopt-target in its deferral
/// diagnostic, and auto-substitutes the extractable shapes) and the
/// custom-widget classifier (which names the adopt-target on its `dartCall`
/// deferral) never drift in what they recognise.

// The whitelisted `NumberFormat` constructors per adopt-target. `null` is the
// unnamed `NumberFormat(...)` constructor (a decimal formatter). This is the
// BROAD adopt-target vocabulary — the set whose deferral diagnostic names a
// catalog widget to switch to. Auto-substitution fires on a STRICT subset of
// it (see [kSubstitutableNumberFormatCtors]).
const Set<String> _kRestagePriceCtors = {'currency', 'simpleCurrency'};
const Set<String?> _kRestageFormattedNumberCtors = {null, 'decimalPattern'};

/// The constructors that are **auto-substituted** (not merely named as an
/// adopt-target) — a deliberately strict subset of the broad vocabulary above.
///
/// A constructor qualifies only when the substitute catalog widget is
/// equivalent **by construction** — i.e. the widget runs the *same*
/// `NumberFormat` constructor with the same statically-extracted configuration:
///   * `currency`        → `RestagePrice` runs `NumberFormat.currency(...)`;
///   * `decimalPattern`  → `RestageFormattedNumber` runs
///                         `NumberFormat.decimalPattern(...)`;
///   * `null` (unnamed)  → `RestageFormattedNumber` with no locale, which runs
///                         `NumberFormat.decimalPattern(null)` (the unnamed
///                         constructor's own default formatter — proven
///                         output-identical by the differential matrix).
///
/// `simpleCurrency` is **excluded**: the formatting widgets have no
/// simple-currency mode (`RestagePrice` forwards an explicit `symbol`, which is
/// not how `simpleCurrency` derives its glyph), so substituting it would be a
/// differential claim, not a by-construction one. It stays a named adopt-target
/// (a clean defer that points the author at the widget), never an auto-rewrite.
const Set<String?> kSubstitutableNumberFormatCtors = {
  'currency',
  'decimalPattern',
  null,
};

/// The catalog widget a `NumberFormat(...).format(<value>)` idiom should adopt
/// (and, for the statically-extractable shapes, auto-substitute to):
/// `RestagePrice` for the currency constructors, `RestageFormattedNumber` for
/// the plain/decimal ones. Returns null when [expr] is not a NumberFormat
/// `.format()` call, when the construction is a non-whitelisted constructor
/// (percent / compact / scientific / custom-pattern — deferred this cut), or
/// when the construction resolves to a class named NumberFormat that is NOT
/// from `package:intl/` (a customer look-alike — the element gate).
///
/// Element-resolved by design: a real intl `NumberFormat.<ctor>(...)` is a
/// factory constructor, so it resolves to an [InstanceCreationExpression] whose
/// type element library is `package:intl/...`. A customer look-alike resolves
/// elsewhere; an unresolved reference is not an [InstanceCreationExpression] at
/// all. Both yield null — never a wrong hint, never a substitution.
String? numberFormatAdoptTarget(MethodInvocation expr) {
  if (expr.methodName.name != 'format') return null;
  final target = expr.target;
  if (target is! InstanceCreationExpression) return null;
  final ctor = target.constructorName;
  if (ctor.type.name.lexeme != 'NumberFormat') return null;
  final libraryUri = ctor.type.element?.library?.identifier ?? '';
  if (!libraryUri.startsWith('package:intl/')) return null;
  final ctorName = ctor.name?.name;
  if (_kRestagePriceCtors.contains(ctorName)) return 'RestagePrice';
  if (_kRestageFormattedNumberCtors.contains(ctorName)) {
    return 'RestageFormattedNumber';
  }
  return null;
}

/// The deferral diagnostic for a recognized formatting idiom — names the
/// catalog widget to adopt, and the pre-localized `localizedPrice` data
/// reference for the store-price (currency) case.
String numberFormatDeferMessage(String adoptTarget) {
  const base = 'Number formatting with intl.NumberFormat is not a supported '
      'paywall expression.';
  if (adoptTarget == 'RestagePrice') {
    return '$base Use the catalog widget `RestagePrice(value:, numberLocale:, '
        'symbol:, decimalDigits:)`. For a store product price, prefer the '
        'pre-localized `localizedPrice` via a data reference.';
  }
  return '$base Use the catalog widget '
      '`RestageFormattedNumber(value:, numberLocale:)`.';
}
