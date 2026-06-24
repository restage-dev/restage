/// The app-side half of Restage's A2UI emit target: a fail-closed pre-render
/// capability check plus the Restage capability sidecar for cached A2UI
/// payloads.
///
/// See the package README for the model. The check sits between an app's cached
/// A2UI payload and genui's render seam, verifying the payload against the
/// catalog the app registered before render — emitting a clean diagnostic
/// instead of genui's mid-render hard-fail.
library;

export 'src/installed_capability.dart';
export 'src/pre_render_check.dart';
export 'src/restage_a2ui_sidecar.dart';
