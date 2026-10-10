import 'package:flutter/foundation.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/rfw.dart' as rfw;

import '../delivery/surface_delivery_receipt.dart';
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

  /// Registers [widgets] under [library], replacing that namespace.
  /// [capabilityVersion] must satisfy the surface's required version;
  /// unversioned registrations satisfy no positive requirement.
  /// [compatibleSince] (default 1) is the oldest required version supported.
  ///
  /// Reserved namespaces assert in debug and are logged and ignored in release.
  /// Duplicate widget names also assert.
  static void register(
    WidgetLibrary library,
    List<RestageWidgetFactory> widgets, {
    int? capabilityVersion,
    int? compatibleSince,
  }) =>
      _register(
        library,
        widgets,
        capabilityVersion: capabilityVersion,
        compatibleSince: compatibleSince,
        additive: false,
      );

  static void _register(
    WidgetLibrary library,
    List<RestageWidgetFactory> widgets, {
    required int? capabilityVersion,
    required int? compatibleSince,
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
      compatibleSince: compatibleSince,
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
      compatibleSince: compatibleSince,
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
        compatibleSince: registration.compatibleSince,
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
    // The higher version carries its compatibleSince; on a tie the higher
    // compatibleSince wins so a declared break is never dropped.
    final int? version;
    final int? compatibleSince;
    if (existingVersion == null ||
        addedVersion != null && addedVersion > existingVersion) {
      version = addedVersion;
      compatibleSince = registration.compatibleSince;
    } else if (addedVersion == existingVersion &&
        (registration.compatibleSince ?? 1) > (existing.compatibleSince ?? 1)) {
      version = existingVersion;
      compatibleSince = registration.compatibleSince;
    } else {
      version = existingVersion;
      compatibleSince = existing.compatibleSince;
    }
    if (added.isEmpty &&
        version == existingVersion &&
        compatibleSince == existing.compatibleSince) {
      return;
    }
    _register(
      existing.library,
      [...existing.widgets, ...added],
      capabilityVersion: version,
      compatibleSince: compatibleSince,
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
            compatibleSince: entry.value.compatibleSince,
          ),
      ];

  /// Captures immutable custom registrations for a caller-owned runtime.
  static List<RestageWidgetLibraryRegistration> registrationSnapshot() =>
      List<RestageWidgetLibraryRegistration>.unmodifiable(
        _entries.values.map((entry) => entry.registration),
      );

  /// How the registered library compares with [requirement].
  static LibraryCompatibility compatibilityOf(LibraryRequirement requirement) =>
      LibraryCompatibility.evaluate(
        _installedLibrary(requirement.namespace),
        requirement,
      );

  /// Whether the registered library renders content needing [requirement].
  /// Fail-closed: an unregistered or unversioned library satisfies nothing.
  static bool satisfies(LibraryRequirement requirement) =>
      compatibilityOf(requirement) == LibraryCompatibility.satisfied;

  /// The receipt reason for refusing content needing [manifest]:
  /// `incompatibleLibrary` when a registered library declared a break past a
  /// requirement, otherwise `unsupported`.
  static SurfaceDeliveryReceiptReason receiptReasonFor(
    CapabilityManifest manifest,
  ) =>
      receiptReasonForLibraries(manifest.requiredLibraries);

  /// [receiptReasonFor] over a bare list of required libraries.
  static SurfaceDeliveryReceiptReason receiptReasonForLibraries(
    Iterable<LibraryRequirement> requiredLibraries,
  ) =>
      requiredLibraries.any(
        (requirement) =>
            compatibilityOf(requirement) == LibraryCompatibility.contractBroken,
      )
          ? SurfaceDeliveryReceiptReason.incompatibleLibrary
          : SurfaceDeliveryReceiptReason.unsupported;

  /// A short phrase naming what is registered for [requirement], for a
  /// rejection diagnostic after [satisfies] returned false.
  static String describeGap(LibraryRequirement requirement) =>
      LibraryCompatibility.describeInstalled(
        _installedLibrary(requirement.namespace),
      );

  static InstalledLibrary? _installedLibrary(String namespace) {
    final entry = _entries[namespace];
    if (entry == null) return null;
    return InstalledLibrary(
      namespace: namespace,
      version: entry.capabilityVersion,
      compatibleSince: entry.compatibleSince,
    );
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
    required this.compatibleSince,
    required this.registration,
  });

  final rfw.LibraryName libraryName;
  final rfw.LocalWidgetLibrary widgets;
  final RestageWidgetLibraryRegistration registration;

  /// The library's declared monotonic capability version, or `null` when the
  /// registration omitted it (unversioned).
  final int? capabilityVersion;

  /// The oldest capability version whose content the library still renders,
  /// or `null` for 1.
  final int? compatibleSince;
}
