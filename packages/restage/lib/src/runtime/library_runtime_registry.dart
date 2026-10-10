import 'package:flutter/foundation.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/rfw.dart' as rfw;

import 'restage_widget_factory.dart';
import 'restage_widget_library_registration.dart';

/// Internal store of custom-registered widget libraries, keyed by
/// namespace. Replace-on-conflict.
abstract final class LibraryRuntimeRegistry {
  LibraryRuntimeRegistry._();

  static final Map<String, _CustomLibraryEntry> _entries =
      <String, _CustomLibraryEntry>{};
  // Registrations [install] has merged since the last [register] or [clear].
  static final Set<RestageWidgetLibraryRegistration> _installed =
      Set<RestageWidgetLibraryRegistration>.identity();
  static int _generation = 0;

  /// Changes whenever a registration replaces what a namespace renders.
  ///
  /// Mount installs that only add libraries or widgets leave it unchanged.
  static int get generation => _generation;

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
  /// A reserved built-in namespace (`restage.core` etc.) is rejected so it can
  /// never shadow the genuine built-in library on a mount: the debug assert is
  /// a hard stop in development, and release ignores the registration and logs
  /// (never throws). Asserts that [widgets] contains no duplicate names.
  static void register(
    WidgetLibrary library,
    List<RestageWidgetFactory> widgets, {
    int? capabilityVersion,
  }) =>
      _register(
        library,
        widgets,
        capabilityVersion: capabilityVersion,
        additive: false,
      );

  static void _register(
    WidgetLibrary library,
    List<RestageWidgetFactory> widgets, {
    required int? capabilityVersion,
    required bool additive,
  }) {
    if (hostInstalledRfwLibrary(library.namespace) != null) {
      assert(
        false,
        'Restage.registerWidgetLibrary: "${library.namespace}" is installed '
        'by Restage itself and cannot be registered by an application.',
      );
      debugPrint(
        '[restage] registerWidgetLibrary: "${library.namespace}" is installed '
        'by Restage itself — registration ignored.',
      );
      return;
    }
    if (WidgetLibrary.builtInByNamespace(library.namespace) != null) {
      // Registering a reserved built-in namespace (restage.core / .material /
      // .cupertino) would shadow the genuine built-in library on every mount
      // while the capability contract still declares the built-in floor —
      // which could enrol the client into content it cannot render. Ignore it:
      // the app keeps its real built-ins and the declared floor stays honest.
      // The debug assert is a hard stop during development; release IGNORES and
      // logs rather than throwing, because a field app that does this already
      // "works" (shadowed) and a startup throw on SDK update would turn silent
      // misbehaviour into a crash.
      assert(
        false,
        'Restage.registerWidgetLibrary: "${library.namespace}" is a reserved '
        'Restage namespace and cannot be overridden. Use a custom-scoped '
        'namespace such as "acme.design_system".',
      );
      debugPrint(
        '[restage] registerWidgetLibrary: "${library.namespace}" is a reserved '
        'Restage namespace and cannot be overridden — registration ignored. '
        'Use a custom-scoped namespace such as "acme.design_system".',
      );
      return;
    }
    if (widgets.any(
      (widget) => widget.name == kReservedPreviewConstructorName,
    )) {
      assert(
        false,
        'Restage.registerWidgetLibrary: '
        '"$kReservedPreviewConstructorName" is reserved for internal preview '
        'rendering and cannot be registered by an application.',
      );
      debugPrint(
        '[restage] registerWidgetLibrary: '
        '"$kReservedPreviewConstructorName" is reserved for internal preview '
        'rendering — registration ignored.',
      );
      return;
    }
    assert(
      capabilityVersion == null || capabilityVersion >= 1,
      'Restage.registerWidgetLibrary: capabilityVersion must be a positive '
      'monotonic version (>= 1) when provided, got $capabilityVersion.',
    );
    final registration = RestageWidgetLibraryRegistration(
      library: library,
      widgets: widgets,
      capabilityVersion: capabilityVersion,
    );
    final builders = <String, rfw.LocalWidgetBuilder>{};
    for (final w in registration.widgets) {
      assert(
        !builders.containsKey(w.name),
        'Restage.registerWidgetLibrary: duplicate widget name "${w.name}" in '
        'library "${library.namespace}".',
      );
      builders[w.name] = w.builder;
    }
    // A replaced namespace may drop widgets an earlier install added.
    if (!additive) _installed.clear();
    // Pre-build the rfw types so each per-mount `applyTo` is a cheap update.
    _entries[library.namespace] = _CustomLibraryEntry(
      libraryName: rfw.LibraryName(library.namespace.split('.')),
      widgets: rfw.LocalWidgetLibrary(builders),
      capabilityVersion: capabilityVersion,
      registration: registration,
    );
    if (!additive) _generation += 1;
  }

  /// Adds the widgets of [registration] that its namespace does not yet carry.
  ///
  /// Installed widgets keep their builders. A registration already installed
  /// returns at once, so installing it on every mount costs a set lookup.
  static void install(RestageWidgetLibraryRegistration registration) {
    if (_installed.contains(registration)) return;
    _merge(registration);
    _installed.add(registration);
  }

  static void _merge(RestageWidgetLibraryRegistration registration) {
    final namespace = registration.library.namespace;
    final existing = _entries[namespace]?.registration;
    if (existing == null) {
      _register(
        registration.library,
        registration.widgets,
        capabilityVersion: registration.capabilityVersion,
        additive: true,
      );
      return;
    }
    final installed = {for (final widget in existing.widgets) widget.name};
    final added = [
      for (final widget in registration.widgets)
        if (!installed.contains(widget.name)) widget,
    ];
    final existingVersion = existing.capabilityVersion;
    final addedVersion = registration.capabilityVersion;
    final version = existingVersion == null ||
            addedVersion != null && addedVersion > existingVersion
        ? addedVersion
        : existingVersion;
    if (added.isEmpty && version == existingVersion) return;
    _register(
      existing.library,
      [...existing.widgets, ...added],
      capabilityVersion: version,
      additive: true,
    );
  }

  /// Whether any custom library is registered at all.
  static bool get hasRegistrations => _entries.isNotEmpty;

  /// Whether a custom library with [namespace] is registered.
  static bool isRegistered(String namespace) => _entries.containsKey(namespace);

  /// The declared capability version of the registered library [namespace], or
  /// `null` if the namespace is not registered OR was registered without a
  /// version. Use [isRegistered] to tell those two cases apart (for a precise
  /// diagnostic).
  static int? registeredVersion(String namespace) =>
      _entries[namespace]?.capabilityVersion;

  /// Captures the currently registered libraries and their declared capability
  /// versions.
  static List<InstalledLibrary> installedSnapshot() => [
        for (final entry in _entries.entries)
          InstalledLibrary(
            namespace: entry.key,
            version: entry.value.capabilityVersion,
          ),
      ];

  /// Captures immutable custom registrations for a caller-owned runtime.
  static List<RestageWidgetLibraryRegistration> registrationSnapshot() =>
      List<RestageWidgetLibraryRegistration>.unmodifiable(
        _entries.values.map((entry) => entry.registration),
      );

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

  /// Register every recorded custom library on [runtime] via
  /// `Runtime.update(LibraryName, LocalWidgetLibrary)`.
  static void applyTo(rfw.Runtime runtime) {
    for (final entry in _entries.values) {
      runtime.update(entry.libraryName, entry.widgets);
    }
  }

  /// Drop every recorded library. Called by `Restage.debugReset` so tests
  /// don't leak registrations across cases.
  static void clear() {
    _entries.clear();
    _installed.clear();
    _generation += 1;
  }
}

class _CustomLibraryEntry {
  const _CustomLibraryEntry({
    required this.libraryName,
    required this.widgets,
    required this.capabilityVersion,
    required this.registration,
  });

  final rfw.LibraryName libraryName;
  final rfw.LocalWidgetLibrary widgets;
  final RestageWidgetLibraryRegistration registration;

  /// The library's declared monotonic capability version, or `null` when the
  /// registration omitted it (unversioned).
  final int? capabilityVersion;
}
