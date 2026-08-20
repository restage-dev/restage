/// The shared unbound-price placeholder: [paywallPriceFor]'s local-Dart
/// return value, and the same string a compiled surface renders for a
/// `data.products.*.localizedPrice` reference when no commerce context is
/// configured (see `Restage.hasCommerceContext`). One definition so the two
/// paths cannot drift apart.
const String kRestageUnboundPriceLabel = r'$X.XX';

/// Returns the localized price string for a configured product.
///
/// In a codegen-built paywall, this expression is replaced at build time
/// with an RFW data reference into the `products` namespace, keyed by the
/// slot or product id — `data.products.annual.localizedPrice`. A key that is
/// not a bare RFW identifier is emitted as a quoted part, so a reverse-DNS
/// store id becomes `data.products."com.example.pro.annual".localizedPrice`
/// and stays a single key rather than splitting at each dot. The SDK
/// populates `DynamicContent` with current price data at render time; when no
/// commerce context is configured, the compiled surface renders the same
/// [kRestageUnboundPriceLabel] placeholder as this function.
///
/// In a non-codegen runtime context (e.g. local debug preview via `runApp`
/// of an annotated paywall class), returns the placeholder string
/// [kRestageUnboundPriceLabel] so the layout does not crash but the value
/// is clearly identifiable as a binding.
///
/// Provide either [slot] or [productId]; exactly one must be non-null.
///
/// [productId] is the id as the store knows it, written exactly as you
/// registered it — reverse-DNS ids like `com.example.pro.annual` need no
/// escaping, substitution, or slot alias. [slot] is your own short name for a
/// position on the surface (`annual`, `primary`), and either form resolves to
/// the same product.
String paywallPriceFor({String? slot, String? productId}) {
  assert(
    (slot != null) ^ (productId != null),
    'Provide exactly one of slot: or productId:',
  );
  return kRestageUnboundPriceLabel;
}
