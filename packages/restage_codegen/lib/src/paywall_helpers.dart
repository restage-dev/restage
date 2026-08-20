import 'package:restage_codegen/src/helper_registry.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

const String _kSdkLibraryOrigin = 'package:restage';

/// Helper-call definitions for the paywall feature kind.
///
/// Registered into a [HelperRegistry] by the codegen builder at startup.
const List<HelperDefinition> paywallHelpers = [
  HelperDefinition(
    name: 'paywallEvent',
    libraryOrigin: _kSdkLibraryOrigin,
    returnCategory: HelperReturnCategory.voidCallback,
    translate: _translatePaywallEvent,
  ),
  HelperDefinition(
    name: 'paywallPurchase',
    libraryOrigin: _kSdkLibraryOrigin,
    returnCategory: HelperReturnCategory.voidCallback,
    translate: _translatePaywallPurchase,
  ),
  HelperDefinition(
    name: 'paywallPriceFor',
    libraryOrigin: _kSdkLibraryOrigin,
    returnCategory: HelperReturnCategory.string,
    translate: _translatePaywallPriceFor,
  ),
];

String _translatePaywallEvent(HelperCallArgs args) {
  if (args.positional.isEmpty) {
    throw ArgumentError('paywallEvent requires a positional name argument');
  }
  final name = _stripQuotes(args.positional.first);
  final argsMap = args.named['args'];
  final body = (argsMap == null) ? '{}' : argsMap;
  return 'event "$name" $body';
}

String _translatePaywallPurchase(HelperCallArgs args) {
  final slot = args.named['slot'];
  final productId = args.named['productId'];
  if ((slot == null) == (productId == null)) {
    throw ArgumentError(
      'paywallPurchase requires exactly one of slot: or productId:',
    );
  }
  final body = slot != null ? '{ slot: $slot }' : '{ productId: $productId }';
  return 'event "restage.purchase" $body';
}

String _translatePaywallPriceFor(HelperCallArgs args) {
  final slot = args.named['slot'];
  final productId = args.named['productId'];
  if ((slot == null) == (productId == null)) {
    throw ArgumentError(
      'paywallPriceFor requires exactly one of slot: or productId:',
    );
  }
  return 'data.products.${_referencePart(slot ?? productId!)}'
      '.localizedPrice';
}

/// The reference-part text for a product key supplied as [value].
///
/// A part of a dotted reference may be an identifier, an integer, or a quoted
/// string. Only an identifier can be written bare, so any key outside
/// [isRfwIdentifier] must keep its quotes — and each way an unquoted key goes
/// wrong is silent or misleading rather than obviously broken:
///
///  * A key containing a dot — every real store id, which are reverse-DNS —
///    is split by the parser into one part per segment, so a three-part
///    reference becomes six and matches nothing.
///  * An all-digit key is tokenized as an *integer* part, which can never
///    equal the string key the runtime registers the product under.
///  * A key holding any other non-identifier character (a hyphen, a leading
///    digit, a space) yields a reference that does not parse, which fails the
///    build blaming the translator rather than naming the key.
///
/// Identifier-shaped keys are unwrapped to the bare form: it is the
/// conventional spelling, and it leaves output that previously parsed
/// byte-for-byte unchanged. Reserved words need no special case — reference
/// parts are not reserved-word checked.
///
/// [value] arrives as the expression translator already lowered it, so a
/// string argument is a double-quoted literal whose body is *already* escaped
/// for the RFW text format. A quoted key is therefore returned as the
/// UNCHANGED [value] rather than rebuilt around its body: re-escaping would
/// double every backslash and change the key. A value that is not a quoted
/// literal (an argument the translator lowered to something else) is passed
/// through untouched.
///
/// A blank key is rejected rather than quoted. Quoting it would turn what used
/// to be a build failure into a reference that parses and then silently never
/// resolves — the opposite of the point of quoting the others. Blankness is
/// judged on the escaped body, so a key written as a lone escape sequence
/// (`'\n'`) reads as non-blank and is quoted like any other odd key.
String _referencePart(String value) {
  final body = _stringLiteralBody(value);
  if (body == null) return value;
  if (body.trim().isEmpty) {
    throw ArgumentError(
      'paywallPriceFor needs a non-blank product key, got $value',
    );
  }
  return isRfwIdentifier(body) ? body : value;
}

/// The body of [value] if it is a double-quoted string literal, else null.
String? _stringLiteralBody(String value) {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return null;
}

String _stripQuotes(String quoted) => _stringLiteralBody(quoted) ?? quoted;
