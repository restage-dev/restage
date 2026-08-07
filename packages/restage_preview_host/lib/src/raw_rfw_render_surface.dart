import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:restage_core/library_registration.dart' as restage_core;
import 'package:restage_cupertino/library_registration.dart'
    as restage_cupertino;
import 'package:restage_material/library_registration.dart' as restage_material;
import 'package:rfw/rfw.dart' hide WidgetLibrary;

import 'protocol.dart';
import 'geometry_registry.dart';
import 'marker_library.dart';

/// Raw RFW render core with built-ins and caller-supplied widget registrations.
class RawRfwRenderSurface extends StatefulWidget {
  RawRfwRenderSurface({
    required this.epoch,
    required Uint8List blob,
    required Map<String, Object?> data,
    required this.environment,
    required List<RestageWidgetLibraryRegistration> registrations,
    required this.entryWidgetName,
    required this.onRemoteEvent,
    this.onRenderEvent,
    this.geometryRegistry,
    super.key,
  })  : blob = Uint8List.fromList(blob).asUnmodifiableView(),
        library = null,
        data = _snapshotData(data),
        registrations = List<RestageWidgetLibraryRegistration>.unmodifiable(
          registrations,
        );

  RawRfwRenderSurface.library({
    required this.epoch,
    required RemoteWidgetLibrary library,
    required Map<String, Object?> data,
    required this.environment,
    required List<RestageWidgetLibraryRegistration> registrations,
    required this.entryWidgetName,
    required this.onRemoteEvent,
    this.onRenderEvent,
    this.geometryRegistry,
    super.key,
  })  :
        // This constructor narrows the nullable storage used by the blob path.
        // ignore: prefer_initializing_formals
        library = library,
        blob = null,
        data = _snapshotData(data),
        registrations = List<RestageWidgetLibraryRegistration>.unmodifiable(
          registrations,
        );

  final int epoch;
  final Uint8List? blob;
  final RemoteWidgetLibrary? library;
  final Map<String, Object?> data;
  final RenderEnv environment;
  final List<RestageWidgetLibraryRegistration> registrations;
  final String entryWidgetName;
  final RemoteEventHandler onRemoteEvent;
  final ValueChanged<RenderEvent>? onRenderEvent;
  final GeometryRegistry? geometryRegistry;

  @override
  State<RawRfwRenderSurface> createState() => _RawRfwRenderSurfaceState();
}

class _RawRfwRenderSurfaceState extends State<RawRfwRenderSurface> {
  static const LibraryName _documentLibrary = LibraryName(<String>['paywall']);

  late Runtime _runtime;
  late DynamicContent _data;
  late Set<String> _dataKeys;
  Object? _loadError;
  int _lifecycleRevision = 0;

  @override
  void initState() {
    super.initState();
    _rebuildRuntime();
  }

  @override
  void didUpdateWidget(RawRfwRenderSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.geometryRegistry, widget.geometryRegistry)) {
      _rebuildRuntime();
      return;
    }
    if (oldWidget.library != null && widget.library != null) {
      _updateLibraryMode(oldWidget);
      if (oldWidget.epoch != widget.epoch ||
          oldWidget.entryWidgetName != widget.entryWidgetName) {
        _beginLifecycle();
      }
      return;
    }
    if (_requiresRuntimeRebuild(oldWidget)) {
      _rebuildRuntime();
    } else if (oldWidget.epoch != widget.epoch ||
        oldWidget.entryWidgetName != widget.entryWidgetName) {
      _beginLifecycle();
    }
  }

  bool _requiresRuntimeRebuild(RawRfwRenderSurface oldWidget) =>
      !identical(oldWidget.library, widget.library) ||
      !listEquals(oldWidget.blob, widget.blob) ||
      !listEquals(oldWidget.registrations, widget.registrations) ||
      !_deepEquals(oldWidget.data, widget.data) ||
      !identical(oldWidget.geometryRegistry, widget.geometryRegistry) ||
      !_sameEnvironment(oldWidget.environment, widget.environment);

  void _rebuildRuntime() {
    _loadError = null;
    _runtime = Runtime();
    try {
      final library = widget.library ?? decodeLibraryBlob(widget.blob!);
      _replaceRuntimeLibraries(library, clearExisting: false);
    } on Object catch (error) {
      _loadError = error;
    }
    final data = _renderData(widget);
    _data = DynamicContent(data);
    _dataKeys = data.keys.toSet();
    _beginLifecycle();
  }

  void _updateLibraryMode(RawRfwRenderSurface oldWidget) {
    assert(widget.library != null);
    _loadError = null;
    if (!listEquals(oldWidget.registrations, widget.registrations)) {
      // Runtime has no per-library removal API. Clear and deterministically
      // restore the complete registry on the same Runtime so dropped customer
      // namespaces cannot leave stale builders behind.
      _replaceRuntimeLibraries(widget.library!, clearExisting: true);
    } else if (!identical(oldWidget.library, widget.library)) {
      _runtime.update(_documentLibrary, widget.library!);
    }

    final data = _renderData(widget);
    final dataKeys = data.keys.toSet();
    if (_dataKeys.difference(dataKeys).isNotEmpty) {
      // RFW 1.1.3's updateAll deliberately retains omitted top-level keys and
      // exposes no removal operation. Replacing only DynamicContent is the
      // bounded removal path; the Runtime and RemoteWidget tree stay stable.
      _data = DynamicContent(data);
    } else {
      _data.updateAll(data);
    }
    _dataKeys = dataKeys;
  }

  void _replaceRuntimeLibraries(
    RemoteWidgetLibrary document, {
    required bool clearExisting,
  }) {
    if (clearExisting) _runtime.clearLibraries();
    _runtime
      ..update(
        const LibraryName(<String>['restage', 'core']),
        restage_core.buildCoreWidgetLibrary(),
      )
      ..update(
        const LibraryName(<String>['restage', 'material']),
        restage_material.buildMaterialWidgetLibrary(),
      )
      ..update(
        const LibraryName(<String>['restage', 'cupertino']),
        restage_cupertino.buildCupertinoWidgetLibrary(),
      );
    final geometryRegistry = widget.geometryRegistry;
    if (geometryRegistry != null) {
      _runtime.update(
        const LibraryName(<String>['restage', 'editor']),
        buildMarkerWidgetLibrary(geometryRegistry),
      );
    }
    for (final registration in widget.registrations) {
      if (registration.library.namespace == kReservedPreviewLibraryName ||
          registration.widgets.any(
            (factory) => factory.name == kReservedPreviewConstructorName,
          )) {
        continue;
      }
      if (WidgetLibrary.builtInByNamespace(registration.library.namespace) !=
          null) {
        continue;
      }
      _runtime.update(
        LibraryName(registration.library.namespace.split('.')),
        LocalWidgetLibrary(<String, LocalWidgetBuilder>{
          for (final factory in registration.widgets)
            factory.name: factory.builder,
        }),
      );
    }
    _runtime.update(_documentLibrary, document);
  }

  void _beginLifecycle() {
    final revision = ++_lifecycleRevision;
    if (_loadError == null) return;
    final epoch = widget.epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _lifecycleRevision) return;
      widget.onRenderEvent?.call(
        RenderError(
          epoch: epoch,
          message: 'Unable to decode the render bundle.',
        ),
      );
    });
  }

  void _reportSettled(int revision, int epoch) {
    if (!mounted || revision != _lifecycleRevision) return;
    widget.onRenderEvent?.call(
      Settled(epoch: epoch, diagnostics: const <RenderDiagnostic>[]),
    );
  }

  void _reportBuildError(int revision, int epoch) {
    if (!mounted || revision != _lifecycleRevision) return;
    widget.onRenderEvent?.call(
      RenderError(epoch: epoch, message: 'Unable to build the render bundle.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) return const SizedBox.shrink();
    final environment = widget.environment;
    final revision = _lifecycleRevision;
    final epoch = widget.epoch;
    final rendered = MediaQuery(
      data: MediaQuery.of(context).copyWith(
        size: environment.frame,
        textScaler: TextScaler.linear(environment.textScale),
      ),
      child: Localizations.override(
        context: context,
        locale: _parseLocale(environment.locale),
        child: Theme(
          data: ThemeData(
            brightness: environment.brightness == 'dark'
                ? Brightness.dark
                : Brightness.light,
            useMaterial3: true,
          ),
          child: RemoteWidget(
            runtime: _runtime,
            data: _data,
            widget: FullyQualifiedWidgetName(
              _documentLibrary,
              widget.entryWidgetName,
            ),
            onEvent: widget.onRemoteEvent,
          ),
        ),
      ),
    );
    if (widget.onRenderEvent == null) return rendered;
    return RuntimeErrorBoundary(
      key: ValueKey<int>(revision),
      onFirstPaintSuccess: () => _reportSettled(revision, epoch),
      onError: (_, __) => _reportBuildError(revision, epoch),
      errorReplacement: (_, __, ___) => const SizedBox.shrink(),
      child: rendered,
    );
  }
}

Map<String, Object?> _renderData(RawRfwRenderSurface widget) =>
    <String, Object?>{
      ...widget.data,
      'theme': widget.environment.theme,
    };

bool _sameEnvironment(RenderEnv left, RenderEnv right) =>
    left.brightness == right.brightness &&
    left.locale == right.locale &&
    left.textScale == right.textScale &&
    left.zoom == right.zoom &&
    left.frame == right.frame &&
    _deepEquals(left.theme, right.theme);

bool _deepEquals(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is Map<Object?, Object?> && right is Map<Object?, Object?>) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_deepEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List<Object?> && right is List<Object?>) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (!_deepEquals(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}

Map<String, Object?> _snapshotData(Map<String, Object?> source) =>
    Map<String, Object?>.unmodifiable(
      source.map(
        (key, value) => MapEntry<String, Object?>(key, _snapshotValue(value)),
      ),
    );

Object? _snapshotValue(Object? value) {
  if (value is Map<Object?, Object?>) {
    final snapshot = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ArgumentError.value(key, 'data', 'object keys must be strings');
      }
      snapshot[key] = _snapshotValue(entry.value);
    }
    return Map<String, Object?>.unmodifiable(snapshot);
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_snapshotValue));
  }
  return value;
}

Locale _parseLocale(String tag) {
  final parts = tag.replaceAll('_', '-').split('-');
  if (parts.length == 1) return Locale(parts.first);
  if (parts.length >= 3 && parts[1].length == 4) {
    return Locale.fromSubtags(
      languageCode: parts[0],
      scriptCode: parts[1],
      countryCode: parts[2],
    );
  }
  return Locale.fromSubtags(languageCode: parts[0], countryCode: parts[1]);
}
