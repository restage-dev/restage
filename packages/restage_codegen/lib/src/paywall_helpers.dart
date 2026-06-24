import 'package:restage_codegen/src/helper_registry.dart';

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
  final id = _stripQuotes(slot ?? productId!);
  return 'data.products.$id.localizedPrice';
}

String _stripQuotes(String quoted) {
  if (quoted.length >= 2 && quoted.startsWith('"') && quoted.endsWith('"')) {
    return quoted.substring(1, quoted.length - 1);
  }
  return quoted;
}
