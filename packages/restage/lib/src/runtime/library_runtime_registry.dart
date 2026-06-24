import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/rfw.dart' as rfw;

import 'restage_widget_factory.dart';

/// Internal store of customer-registered widget libraries, keyed by
/// namespace. Replace-on-conflict.
abstract final class LibraryRuntimeRegistry {
  LibraryRuntimeRegistry._();

  static final Map<String, _CustomLibraryEntry> _entries =
      <String, _CustomLibraryEntry>{};

  /// Record [library] under its namespace, replacing any prior registration.
  ///
  /// [capabilityVersion] is the library's declared monotonic capability version
  /// (from its `@RestageLibrary(capabilityVersion: …)` declaration), recorded so
  /// the resolvers can verify a delivered surface's required-library floor
  /// before render. A registration that omits it (`null`) is treated as
  /// **unversioned** and satisfies no positive requirement (fail-closed) — a
  /// surface requiring `acme.widgets >= 2` needs a registration declaring a
  /// capability version at or above 2.
  ///
  /// Asserts that [library] is not a reserved built-in namespace (registering
  /// `restage.core` etc. would silently shadow the built-in library on every
  /// paywall mount) and that [widgets] contains no duplicate names.
  static void register(
    WidgetLibrary library,
    List<RestageWidgetFactory> widgets, {
    int? capabilityVersion,
  }) {
    assert(
      WidgetLibrary.builtInByNamespace(library.namespace) == null,
      'Restage.registerWidgetLibrary: "${library.namespace}" is a reserved '
      'Restage namespace and cannot be overridden. Use a customer-scoped '
      'namespace such as "acme.design_system".',
    );
    assert(
      capabilityVersion == null || capabilityVersion >= 1,
      'Restage.registerWidgetLibrary: capabilityVersion must be a positive '
      'monotonic version (>= 1) when provided, got $capabilityVersion.',
    );
    final builders = <String, rfw.LocalWidgetBuilder>{};
    for (final w in widgets) {
      assert(
        !builders.containsKey(w.name),
        'Restage.registerWidgetLibrary: duplicate widget name "${w.name}" in '
        'library "${library.namespace}".',
      );
      builders[w.name] = w.builder;
    }
    // Pre-build the rfw types so each per-mount `applyTo` is a cheap update.
    _entries[library.namespace] = _CustomLibraryEntry(
      libraryName: rfw.LibraryName(library.namespace.split('.')),
      widgets: rfw.LocalWidgetLibrary(builders),
      capabilityVersion: capabilityVersion,
    );
  }

  /// Whether a custom library with [namespace] is registered.
  static bool isRegistered(String namespace) => _entries.containsKey(namespace);

  /// The declared capability version of the registered library [namespace], or
  /// `null` if the namespace is not registered OR was registered without a
  /// version. Use [isRegistered] to tell those two cases apart (for a precise
  /// diagnostic).
  static int? registeredVersion(String namespace) =>
      _entries[namespace]?.capabilityVersion;

  /// Whether the installed registry satisfies [requirement]: the namespace is
  /// registered AND was registered with a capability version at or above the
  /// requirement's `minVersion`. Fail-closed — an unregistered or unversioned
  /// library satisfies nothing.
  static bool satisfies(LibraryRequirement requirement) {
    final version = _entries[requirement.namespace]?.capabilityVersion;
    return version != null && version >= requirement.minVersion;
  }

  /// A short phrase describing why [requirement] is unsatisfied, for a
  /// resolver's rejection diagnostic. Single-sourced so both resolvers name the
  /// gap the same way. (Undefined when [requirement] is satisfied — call only
  /// after [satisfies] returns false.)
  static String describeGap(LibraryRequirement requirement) {
    final entry = _entries[requirement.namespace];
    if (entry == null) return 'not registered';
    final version = entry.capabilityVersion;
    return version == null
        ? 'registered without a capability version'
        : 'installed v$version';
  }

  /// Register every recorded customer library on [runtime] via
  /// `Runtime.update(LibraryName, LocalWidgetLibrary)`.
  static void applyTo(rfw.Runtime runtime) {
    for (final entry in _entries.values) {
      runtime.update(entry.libraryName, entry.widgets);
    }
  }

  /// Drop every recorded library. Called by `Restage.debugReset` so tests
  /// don't leak registrations across cases.
  static void clear() => _entries.clear();
}

class _CustomLibraryEntry {
  const _CustomLibraryEntry({
    required this.libraryName,
    required this.widgets,
    required this.capabilityVersion,
  });

  final rfw.LibraryName libraryName;
  final rfw.LocalWidgetLibrary widgets;

  /// The library's declared monotonic capability version, or `null` when the
  /// registration omitted it (unversioned).
  final int? capabilityVersion;
}
