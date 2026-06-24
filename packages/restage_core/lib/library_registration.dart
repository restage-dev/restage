/// Library registration entry point for `restage.core` — exposes a
/// [LocalWidgetLibrary] that the SDK runtime registers with rfw at startup.
///
/// The runtime calls [buildCoreWidgetLibrary] once per process, then
/// hands the result to `Runtime.update(LibraryName(['restage', 'core']),
/// library)`. Re-registering with a fresh build replaces the prior
/// library — useful for hot-reload in the editor.
library;

import 'package:rfw/rfw.dart';

import 'src/registration.g.dart';

/// Builds a [LocalWidgetLibrary] for the `restage.core` namespace.
///
/// The map of [LocalWidgetBuilder]s is generated from the registry by
/// codegen — one entry per widget in `lib/registry.dart`. This wrapper
/// exists so the SDK runtime depends only on a stable API surface, not
/// directly on the generated file.
LocalWidgetLibrary buildCoreWidgetLibrary() =>
    LocalWidgetLibrary(kCoreLibraryFactories);
