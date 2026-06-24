/// Pinned protocol + dialect constants for the A2UI catalog emit target.
///
/// This is the single isolation point for the **protocol/version surface** —
/// one of the three independently-churning external surfaces the emit adapter
/// is built to absorb. The adapter targets exactly one A2UI protocol version;
/// a future protocol major (the candidate release's renamed/added fields) is
/// absorbed by adding a *second* adapter version that pins its own constant,
/// never by mutating this one. Keeping the pin in one place means a version
/// move touches only the adapter, and the emitted-catalog goldens move with it.
library;

/// The A2UI protocol version the emit adapter currently targets.
///
/// Pinned to the current production release. The candidate (next-major) release
/// is absorbed via a separate adapter version when it is promoted to
/// production, not by changing this value in place.
const String kA2uiProtocolVersion = '0.9.1';

/// The JSON-Schema dialect the emitted A2UI catalog declares in its `$schema`.
///
/// The A2UI catalog document is a JSON-Schema (Draft 2020-12) document whose
/// `components` map each component name to that component's property schema.
const String kA2uiSchemaDialect =
    'https://json-schema.org/draft/2020-12/schema';
