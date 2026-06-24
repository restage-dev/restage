import 'package:restage_codegen/src/helper_registry.dart';

const String _kSdkLibraryOrigin = 'package:restage';

/// Helper-call definitions for onboarding screen transpilation.
const List<HelperDefinition> onboardingHelpers = [
  HelperDefinition(
    name: 'onboardingEvent',
    libraryOrigin: _kSdkLibraryOrigin,
    returnCategory: HelperReturnCategory.voidCallback,
    translate: _translateOnboardingEvent,
  ),
];

String _translateOnboardingEvent(HelperCallArgs args) {
  if (args.positional.isEmpty) {
    throw ArgumentError('onboardingEvent requires an event descriptor');
  }
  final name = _stripQuotes(args.positional.first);
  final body = args.positional.length > 1 ? args.positional[1] : '{}';
  return 'event "$name" $body';
}

String _stripQuotes(String quoted) {
  if (quoted.length >= 2 && quoted.startsWith('"') && quoted.endsWith('"')) {
    return quoted.substring(1, quoted.length - 1);
  }
  return quoted;
}
