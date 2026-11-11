import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/onboarding/onboarding_helpers.dart';

/// Helper-call definitions for paywall event authoring: the same event a flow
/// screen fires, whose value travels as `args['value']`.
///
/// Registered into a [HelperRegistry] by the codegen builder at startup.
const List<HelperDefinition> paywallHelpers = [surfaceEventHelper];
