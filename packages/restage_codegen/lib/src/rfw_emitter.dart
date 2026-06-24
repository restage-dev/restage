/// The canonical RFW DSL import preamble shared by every emitted library —
/// the three built-in catalog namespaces, in fixed order.
const String kRfwImportPreamble = 'import restage.core;\n'
    'import restage.material;\n'
    'import restage.cupertino;\n';

/// The RFW widget name of the synthesized paywall root. It is reserved — a
/// custom widget inlined under this name would shadow the root in the blob,
/// so the translator rejects the collision.
const String paywallRootWidgetName = 'Paywall';

/// The RFW widget name of the synthesized onboarding screen root.
const String onboardingScreenRootWidgetName = 'OnboardingScreen';

/// Wraps a translated `build()` body [fragment] in the canonical RFW DSL
/// envelope expected by the runtime loader.
///
/// The runtime requests a widget at `(restage.paywall, Paywall)`; the
/// library name is assigned by the SDK at `runtime.update`, so we don't
/// declare a library here — only the imports and the widget bodies.
///
/// [widgetDefinitions] (rfwName → body DSL) are the inlined custom widgets
/// the translator emitted. Each is declared as a `widget <name> = <body>;`
/// ahead of `widget Paywall` so a reference inside the paywall resolves to
/// the library-local definition.
///
/// [widgetDefinitionStates] (rfwName → field-name → literal-DSL) carries
/// the initial-state map for each stateful inlined widget. A widget present
/// in this map with a non-empty inner map renders as
/// `widget <name> { <field>: <literal>, … } = <body>;` — the canonical RFW
/// stateful-widget form. A widget absent from this map, or present with an
/// empty inner map, emits no state block: the binary encoding does not
/// distinguish "no state" from "empty state" anyway.
String emitPaywallLibrary(
  String fragment, {
  Map<String, String> widgetDefinitions = const {},
  Map<String, Map<String, String>> widgetDefinitionStates = const {},
  Map<String, String> rootWidgetState = const {},
}) {
  return emitRemoteWidgetLibrary(
    fragment,
    rootWidgetName: paywallRootWidgetName,
    widgetDefinitions: widgetDefinitions,
    widgetDefinitionStates: widgetDefinitionStates,
    rootWidgetState: rootWidgetState,
  );
}

/// Wraps a translated widget [fragment] in a canonical RFW DSL library with
/// the supplied [rootWidgetName].
String emitRemoteWidgetLibrary(
  String fragment, {
  required String rootWidgetName,
  Map<String, String> widgetDefinitions = const {},
  Map<String, Map<String, String>> widgetDefinitionStates = const {},
  Map<String, String> rootWidgetState = const {},
}) {
  final definitions = StringBuffer();
  for (final entry in widgetDefinitions.entries) {
    final state = widgetDefinitionStates[entry.key];
    final stateBlock = _stateBlock(state ?? const {});
    definitions.writeln('widget ${entry.key}$stateBlock = ${entry.value};');
  }
  if (widgetDefinitions.isNotEmpty) {
    definitions.writeln();
  }
  final rootStateBlock = _stateBlock(rootWidgetState);
  return '$kRfwImportPreamble\n'
      '${definitions}widget $rootWidgetName$rootStateBlock = $fragment;\n';
}

String _stateBlock(Map<String, String> state) => state.isEmpty
    ? ''
    : ' { ${state.entries.map((e) => '${e.key}: ${e.value}').join(', ')} }';
