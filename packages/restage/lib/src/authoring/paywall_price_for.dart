/// Returns the localized price string for a configured product.
///
/// In a codegen-built paywall, this expression is replaced at build time
/// with the RFW data reference `data.products.<slot>.localizedPrice` (or
/// `data.products.<productId>.localizedPrice`). The SDK populates
/// `DynamicContent` with current price data at render time.
///
/// In a non-codegen runtime context (e.g. local debug preview via `runApp`
/// of an annotated paywall class), returns the placeholder string `$X.XX`
/// so the layout does not crash but the value is clearly identifiable as a
/// binding.
///
/// Provide either [slot] or [productId]; exactly one must be non-null.
String paywallPriceFor({String? slot, String? productId}) {
  assert(
    (slot != null) ^ (productId != null),
    'Provide exactly one of slot: or productId:',
  );
  return r'$X.XX';
}
