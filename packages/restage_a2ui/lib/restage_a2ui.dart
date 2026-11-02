/// The app-side half of Restage's A2UI emit target: a fail-closed pre-render
/// capability check plus the Restage capability sidecar for cached A2UI
/// payloads.
///
/// See the package README for the model. The check sits between an app's cached
/// A2UI payload and a2ui_flutter's render seam, checking protocol envelopes,
/// component schemas and catalog resolution before render. Restage sidecars
/// also require the installed capability set. Graph completeness is not
/// required between updates, and preflight never executes functions.
library;

export 'src/catalog_capability.dart';
export 'src/installed_capability.dart';
export 'src/pre_render_check.dart';
export 'src/restage_a2ui_sidecar.dart';
