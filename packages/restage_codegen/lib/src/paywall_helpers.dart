import 'package:restage_codegen/src/helper_registry.dart';

const String _kSdkLibraryOrigin = 'package:restage';

/// Helper-call definitions for paywall event authoring.
///
/// Registered into a [HelperRegistry] by the codegen builder at startup.
const List<HelperDefinition> paywallHelpers = [
  HelperDefinition(
    name: 'paywallEvent',
    libraryOrigin: _kSdkLibraryOrigin,
    returnCategory: HelperReturnCategory.voidCallback,
    translate: _translatePaywallEvent,
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

/// The body of [value] if it is a double-quoted string literal, else null.
String? _stringLiteralBody(String value) {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return null;
}

String _stripQuotes(String quoted) => _stringLiteralBody(quoted) ?? quoted;
