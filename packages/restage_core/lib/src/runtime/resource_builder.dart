import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Owns native resources constructed while decoding one widget build.
final class RestageResources {
  RestageResources._();

  final List<_OwnedResource> _entries = [];

  /// Registers a fresh resource and its native interaction settling delay.
  T own<T extends Object>(
    T value, {
    required void Function(T) dispose,
    Duration settleDelay = Duration.zero,
  }) =>
      manage(value, dispose: dispose, settleDelay: settleDelay).value;

  /// Registers a resource whose native callbacks signal arena completion.
  RestageResourceHandle<T> manage<T extends Object>(
    T value, {
    required void Function(T) dispose,
    Duration settleDelay = Duration.zero,
  }) {
    final entry = _OwnedResource(() => dispose(value), settleDelay);
    final handle = RestageResourceHandle<T>._(value, entry);
    _entries.add(entry);
    return handle;
  }
}

/// Keeps a resource alive while Flutter retains its gesture-arena entry.
final class RestageResourceHandle<T extends Object> {
  RestageResourceHandle._(this.value, this._entry);

  /// The installed native object.
  final T value;
  final _OwnedResource _entry;

  /// Records one native arena entry that still owns the object.
  void retain(int pointer) => _entry.pending.add(pointer);

  /// Signals native completion without interrupting the current callback.
  void settle(int pointer) {
    _entry.pending.remove(pointer);
    _entry.onSettled?.call();
  }
}

final class _OwnedResource {
  _OwnedResource(this.dispose, this.settleDelay);
  final VoidCallback dispose;
  final Duration settleDelay;
  VoidCallback? onSettled;
  final pending = <int>{};
  bool scheduled = false;
}

/// Supplies per-build ownership without changing native gesture arbitration.
class RestageResourceBuilder extends StatefulWidget {
  /// Runs decoding synchronously in the calling factory's data scope.
  factory RestageResourceBuilder(
      {Key? key, required Widget Function(RestageResources) builder}) {
    final resources = RestageResources._();
    try {
      return RestageResourceBuilder._(
          key: key, resources: resources, child: builder(resources));
    } catch (_) {
      for (final entry in resources._entries) {
        entry.dispose();
      }
      rethrow;
    }
  }

  const RestageResourceBuilder._(
      {super.key, required this.resources, required this.child});

  /// Resources created by this factory invocation.
  final RestageResources resources;

  /// The native widget constructed in the caller's data scope.
  final Widget child;

  @override
  State<RestageResourceBuilder> createState() => _RestageResourceBuilderState();
}

class _RestageResourceBuilderState extends State<RestageResourceBuilder> {
  final _retired = <_OwnedResource>[];
  final _pointers = <int>{};
  bool _listening = true;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_routePointer);
    _adopt(widget.resources);
  }

  void _adopt(RestageResources resources) {
    for (final entry in resources._entries) {
      entry.onSettled = _scheduleRelease;
    }
  }

  @override
  void didUpdateWidget(RestageResourceBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _adopt(widget.resources);
    _retire(oldWidget.resources);
  }

  void _routePointer(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (!_pointers.remove(event.pointer)) return;
      // Cancellation is terminal even when Flutter leaves its arena open.
      if (event is PointerCancelEvent) {
        scheduleMicrotask(() {
          for (final entry in [...widget.resources._entries, ..._retired]) {
            entry.pending.remove(event.pointer);
          }
          _scheduleRelease();
        });
      } else {
        _scheduleRelease();
      }
    }
  }

  void _retire(RestageResources resources) {
    _retired.addAll(resources._entries);
    _scheduleRelease();
  }

  void _scheduleRelease() {
    if (_pointers.isNotEmpty) return;
    for (final entry in _retired) {
      if (entry.pending.isNotEmpty || entry.scheduled) continue;
      entry.scheduled = true;
      void release() {
        entry.scheduled = false;
        if (_pointers.isNotEmpty || entry.pending.isNotEmpty) return;
        _retired.remove(entry);
        entry.onSettled = null;
        entry.dispose();
        _stopListeningIfDisposed();
      }

      if (entry.settleDelay == Duration.zero) {
        scheduleMicrotask(release);
      } else {
        Timer(entry.settleDelay, release);
      }
    }
    _stopListeningIfDisposed();
  }

  void _stopListeningIfDisposed() {
    if (_disposed && _listening && _retired.isEmpty) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_routePointer);
      _listening = false;
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
      onPointerDown: (event) => _pointers.add(event.pointer),
      child: widget.child);

  @override
  void dispose() {
    _disposed = true;
    _retire(widget.resources);
    super.dispose();
  }
}
