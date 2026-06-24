/// Cupertino (Apple HIG) widgets for Restage paywalls. Authoritative
/// metadata lives in [registry.dart] (`kRegistry`); the runtime registers
/// its widgets with rfw via [library_registration.dart]
/// (`buildCupertinoWidgetLibrary`). Both are read by codegen, the editor,
/// and the SDK runtime.
library;

export 'library_registration.dart';
export 'registry.dart';
